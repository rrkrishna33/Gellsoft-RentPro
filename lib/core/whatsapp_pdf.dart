import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'share.dart';

/// How a PDF went out.
enum PdfSendResult {
  /// WhatsApp opened with the PDF (and, when possible, the customer's chat).
  whatsapp,

  /// WhatsApp is not on the phone, so the phone's share sheet opened instead.
  shareSheet,
}

/// Replaced in tests so nothing is launched.
@visibleForTesting
Future<PdfSendResult> Function({
  required Uint8List bytes,
  required String fileName,
  required String phone,
  required String message,
})?
pdfWhatsAppSender;

/// Replaced in tests so nothing is launched.
@visibleForTesting
Future<PdfSendResult> Function({
  required List<String> paths,
  required String phone,
  required String message,
})?
imagesWhatsAppSender;

const _channel = MethodChannel('gellsoft/share');

/// Sends pictures (files in the app's folder) on WhatsApp with [message] as
/// the text. With no [paths] only the text goes. WhatsApp opens on the
/// customer's chat when [phone] is a usable number; with no number the person
/// chooses the chat inside WhatsApp. With no WhatsApp on the phone the share
/// sheet opens instead.
Future<PdfSendResult> sendImagesOnWhatsApp({
  required List<String> paths,
  required String phone,
  required String message,
}) async {
  final hook = imagesWhatsAppSender;
  if (hook != null) {
    return hook(paths: paths, phone: phone, message: message);
  }
  // copies in the one folder the app lets other apps read; old ones go first
  final dir = Directory(p.join((await getTemporaryDirectory()).path, 'shared'));
  if (await dir.exists()) await dir.delete(recursive: true);
  await dir.create(recursive: true);
  final copies = <String>[];
  for (final src in paths) {
    if (!await File(src).exists()) continue;
    final dest = p.join(dir.path, _safeName(p.basename(src)));
    await File(src).copy(dest);
    copies.add(dest);
  }
  final how = await _channel.invokeMethod<String>('sendImages', {
    'paths': copies,
    'number': whatsappNumber(phone),
    'text': message,
  });
  return how == 'whatsapp' ? PdfSendResult.whatsapp : PdfSendResult.shareSheet;
}

/// Sends [bytes] as a PDF named [fileName] on WhatsApp, with [message] as the
/// caption. WhatsApp opens on the customer's chat when [phone] is a usable
/// number (WhatsApp may still ask which chat on some versions), and the person
/// only has to press send.
///
/// With no WhatsApp on the phone the share sheet opens instead, so the PDF can
/// go by any other app.
Future<PdfSendResult> sendPdfOnWhatsApp({
  required Uint8List bytes,
  required String fileName,
  required String phone,
  required String message,
}) async {
  final hook = pdfWhatsAppSender;
  if (hook != null) {
    return hook(bytes: bytes, fileName: fileName, phone: phone, message: message);
  }
  try {
    // A file in the one folder the app lets other apps read; old ones go first.
    final dir = Directory(p.join((await getTemporaryDirectory()).path, 'shared'));
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, _safeName(fileName)));
    await file.writeAsBytes(bytes, flush: true);
    final how = await _channel.invokeMethod<String>('sendPdf', {
      'path': file.path,
      'number': whatsappNumber(phone),
      'text': message,
    });
    return how == 'whatsapp' ? PdfSendResult.whatsapp : PdfSendResult.shareSheet;
  } on MissingPluginException {
    await sharePdf(bytes, fileName);
    return PdfSendResult.shareSheet;
  } on PlatformException {
    await sharePdf(bytes, fileName);
    return PdfSendResult.shareSheet;
  }
}

/// A file name with only safe characters (it becomes a file in the cache).
String _safeName(String name) {
  final clean = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return clean.isEmpty ? 'document.pdf' : clean;
}
