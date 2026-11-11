import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/core/share.dart' as share;
import 'package:gellsoft_rentpro/core/whatsapp_pdf.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory cache;
  final pdf = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2d, 1, 2, 3]);

  setUp(() {
    cache = Directory.systemTemp.createTempSync('rentpro_cache');
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => call.method == 'getTemporaryDirectory' ? cache.path : null,
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(const MethodChannel('gellsoft/share'), null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    share.pdfSharer = null;
    cache.deleteSync(recursive: true);
  });

  test('the PDF is written to the shared folder and handed to WhatsApp', () async {
    MethodCall? seen;
    Uint8List? onDisk;
    messenger.setMockMethodCallHandler(const MethodChannel('gellsoft/share'), (call) async {
      seen = call;
      onDisk = File((call.arguments as Map)['path'] as String).readAsBytesSync();
      return 'whatsapp';
    });
    final r = await sendPdfOnWhatsApp(
      bytes: pdf,
      fileName: 'RNT-0001.pdf',
      phone: '98765 43210',
      message: 'Hello Anu',
    );
    expect(r, PdfSendResult.whatsapp);
    expect(seen!.method, 'sendPdf');
    final args = seen!.arguments as Map;
    expect(p.basename(args['path'] as String), 'RNT-0001.pdf');
    expect(p.basename(p.dirname(args['path'] as String)), 'shared',
        reason: 'only the shared folder is ever handed out');
    expect(args['number'], '919876543210');
    expect(args['text'], 'Hello Anu');
    expect(onDisk, pdf);
  });

  test('a phone number that is not usable is sent as no number', () async {
    Map? args;
    messenger.setMockMethodCallHandler(const MethodChannel('gellsoft/share'), (call) async {
      args = call.arguments as Map;
      return 'whatsapp';
    });
    await sendPdfOnWhatsApp(bytes: pdf, fileName: 'a.pdf', phone: '12', message: 'x');
    expect(args!['number'], isNull);
  });

  test('without WhatsApp the share sheet result is reported', () async {
    messenger.setMockMethodCallHandler(
      const MethodChannel('gellsoft/share'),
      (call) async => 'chooser',
    );
    expect(
      await sendPdfOnWhatsApp(bytes: pdf, fileName: 'a.pdf', phone: '9876543210', message: 'x'),
      PdfSendResult.shareSheet,
    );
  });

  test('if the phone side fails, the share sheet opens with the same PDF', () async {
    final shared = <String>[];
    share.pdfSharer = (bytes, name) async => shared.add(name);
    messenger.setMockMethodCallHandler(const MethodChannel('gellsoft/share'), (call) async {
      throw PlatformException(code: 'send_failed', message: 'no way');
    });
    final r = await sendPdfOnWhatsApp(
      bytes: pdf,
      fileName: 'RNT-0002.pdf',
      phone: '9876543210',
      message: 'x',
    );
    expect(r, PdfSendResult.shareSheet);
    expect(shared, ['RNT-0002.pdf']);
  });

  test('an odd file name cannot point outside the folder', () async {
    Map? args;
    messenger.setMockMethodCallHandler(const MethodChannel('gellsoft/share'), (call) async {
      args = call.arguments as Map;
      return 'whatsapp';
    });
    await sendPdfOnWhatsApp(
      bytes: pdf,
      fileName: '../../evil name.pdf',
      phone: '9876543210',
      message: 'x',
    );
    final path = args!['path'] as String;
    expect(p.basename(p.dirname(path)), 'shared');
    expect(p.basename(path), '.._.._evil_name.pdf');
  });

  test('old shared files are cleared before a new one is written', () async {
    final dir = Directory(p.join(cache.path, 'shared'))..createSync();
    File(p.join(dir.path, 'old.pdf')).writeAsBytesSync([1]);
    messenger.setMockMethodCallHandler(
      const MethodChannel('gellsoft/share'),
      (call) async => 'whatsapp',
    );
    await sendPdfOnWhatsApp(bytes: pdf, fileName: 'new.pdf', phone: '9876543210', message: 'x');
    expect(dir.listSync().map((f) => p.basename(f.path)), ['new.pdf']);
  });
}
