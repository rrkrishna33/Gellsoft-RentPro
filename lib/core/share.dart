
import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

/// The phone number as WhatsApp wants it: digits only, with the country code.
/// A 10-digit Indian number gets 91 in front; a leading 0 is dropped.
/// Returns null when there are not enough digits to be a phone number.
String? whatsappNumber(String phone, {String countryCode = '91'}) {
  var digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  if (phone.trim().startsWith('+')) {
    return digits.length >= 8 ? digits : null;
  }
  if (digits.startsWith('00')) digits = digits.substring(2);
  if (digits.startsWith('0')) digits = digits.substring(1);
  if (digits.length == 10) return '$countryCode$digits';
  if (digits.length > 10 && digits.startsWith(countryCode)) return digits;
  return digits.length >= 10 ? digits : null;
}

/// The link that opens WhatsApp with [message] ready to send to [phone].
Uri whatsappLink(String phone, String message) {
  final n = whatsappNumber(phone);
  return Uri.parse(
    n == null
        ? 'https://wa.me/?text=${Uri.encodeComponent(message)}'
        : 'https://wa.me/$n?text=${Uri.encodeComponent(message)}',
  );
}

/// How links are opened. Tests replace it so no app is launched.
@visibleForTesting
Future<bool> Function(Uri uri)? linkOpener;

Future<bool> _open(Uri uri) async {
  final hook = linkOpener;
  if (hook != null) return hook(uri);
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Opens WhatsApp with a ready message to the customer. False when the phone
/// number is missing or WhatsApp could not be opened.
Future<bool> sendWhatsApp(String phone, String message) async {
  if (whatsappNumber(phone) == null) return false;
  return _open(whatsappLink(phone, message));
}

Future<bool> callPhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
  if (digits.isEmpty) return Future.value(false);
  return _open(Uri.parse('tel:$digits'));
}

/// Hooks for tests, so no share sheet or print dialog opens.
@visibleForTesting
Future<void> Function(Uint8List bytes, String filename)? pdfSharer;
@visibleForTesting
Future<void> Function(Uint8List bytes, String name)? pdfPrinter;

/// Opens the phone's share sheet with the PDF (WhatsApp, e-mail, Drive...).
Future<void> sharePdf(Uint8List bytes, String filename) async {
  final hook = pdfSharer;
  if (hook != null) return hook(bytes, filename);
  await Printing.sharePdf(bytes: bytes, filename: filename);
}

/// Opens the print dialog for the PDF.
Future<void> printPdf(Uint8List bytes, String name) async {
  final hook = pdfPrinter;
  if (hook != null) return hook(bytes, name);
  await Printing.layoutPdf(name: name, onLayout: (_) async => bytes);
}
