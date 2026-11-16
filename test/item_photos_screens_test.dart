import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/core/constants.dart';
import 'package:gellsoft_rentpro/core/pdf_text.dart';
import 'package:gellsoft_rentpro/core/theme.dart';
import 'package:gellsoft_rentpro/core/whatsapp_pdf.dart' as wa;
import 'package:gellsoft_rentpro/data/business_profile.dart';
import 'package:gellsoft_rentpro/data/database.dart';
import 'package:gellsoft_rentpro/data/models.dart';
import 'package:gellsoft_rentpro/data/photo_store.dart';
import 'package:gellsoft_rentpro/data/repositories.dart';
import 'package:gellsoft_rentpro/features/items/catalog_pdf.dart';
import 'package:gellsoft_rentpro/features/items/catalog_screen.dart';
import 'package:gellsoft_rentpro/features/items/item_form_screen.dart';
import 'package:gellsoft_rentpro/features/items/item_photo_strip.dart';
import 'package:gellsoft_rentpro/features/items/items_screen.dart';
import 'package:gellsoft_rentpro/l10n/strings.dart';
import 'package:gellsoft_rentpro/subscription/entitlement.dart';
import 'package:gellsoft_rentpro/subscription/license_state.dart';
import 'package:gellsoft_rentpro/subscription/plan.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'license_fixtures.dart';

class _Profile extends ProfileNotifier {
  @override
  Future<BusinessProfile?> build() async => const BusinessProfile(
    name: 'Royal Costumes',
    phone: '9876543210',
    type: ShopType.costume,
  );
}

class _License extends LicenseNotifier {
  _License(this.pro);
  final bool pro;
  @override
  Future<LicenseState> build() async => LicenseState(
    entitlement: Entitlement(
      tier: pro ? Tier.pro : Tier.free,
      enforced: true,
      proUntil: DateTime(2100),
    ),
    installId: fixtureInstallId,
    now: DateTime.now(),
  );
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

Widget host(Widget child, {bool pro = true}) => ProviderScope(
  key: ValueKey(pro),
  overrides: [
    profileProvider.overrideWith(_Profile.new),
    isProProvider.overrideWithValue(pro),
    licenseProvider.overrideWith(() => _License(pro)),
  ],
  child: MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child)),
);

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGM4scAGiBggFAAwLgaRMe177wAAAABJRU5ErkJggg==',
);

void main() {
  final items = ItemRepo();
  late Directory dir;
  late int gown;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  void testDb(String name, Future<void> Function(WidgetTester t) body) {
    testWidgets(name, (t) async {
      SharedPreferences.setMockInitialValues({});
      dir = Directory.systemTemp.createTempSync('rentpro_item_ui');
      AppDatabase.pathOverride = '${dir.path}/t.db';
      PhotoStore.folderOverride = Directory(p.join(dir.path, 'photos'))
        ..createSync();
      t.view.physicalSize = const Size(800, 2600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.runAsync(() async {
        gown = await items.save(
          RentItem(
            name: 'Red gown',
            rate: 1500,
            deposit: 2000,
            size: '38',
            createdAt: DateTime(2027),
          ),
        );
      });
      try {
        await body(t);
      } finally {
        Lang.current = AppLanguage.en;
        PhotoStore.picker = null;
        PhotoStore.manyPicker = null;
        wa.imagesWhatsAppSender = null;
        wa.pdfWhatsAppSender = null;
        await t.runAsync(() => AppDatabase.instance.close());
        AppDatabase.pathOverride = null;
        PhotoStore.folderOverride = null;
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });
  }

  /// A picture on disk that the pickers below hand to the app.
  String source(String name) {
    final f = File(p.join(dir.path, name))..writeAsBytesSync(_png);
    return f.path;
  }

  Future<int> savedFor(WidgetTester t, int itemId) async =>
      (await t.runAsync(() => items.photosOf(itemId)))!.length;

  group('the item form', () {
    testDb('a picture is added from the camera and kept on Save', (t) async {
      PhotoStore.picker = (camera) async => source('shot1.png');
      await t.pumpWidget(host(const ItemFormScreen()));
      await settle(t);
      await t.tap(find.text('Add picture'));
      await settle(t);
      await t.tap(find.text('Take a photo'));
      await settle(t);
      expect(find.byType(PhotoThumb), findsOneWidget);
      expect(find.text('Cover'), findsOneWidget);
      await t.enterText(find.widgetWithText(TextFormField, 'Item name'), 'Blue sherwani');
      await t.enterText(find.widgetWithText(TextFormField, 'Rent for one piece (₹)'), '900');
      await t.ensureVisible(find.text('Save'));
      await t.tap(find.text('Save'));
      await settle(t);
      final all = await t.runAsync(() => items.list());
      final saved = all!.firstWhere((i) => i.name == 'Blue sherwani');
      expect(await savedFor(t, saved.id!), 1);
    });

    testDb('leaving without saving throws the picked picture away', (t) async {
      PhotoStore.picker = (camera) async => source('shot2.png');
      await t.pumpWidget(host(const ItemFormScreen()));
      await settle(t);
      await t.tap(find.text('Add picture'));
      await settle(t);
      await t.tap(find.text('Take a photo'));
      await settle(t);
      expect(Directory(p.join(dir.path, 'photos')).listSync(), hasLength(1));
      await t.pumpWidget(const SizedBox());
      await settle(t);
      expect(Directory(p.join(dir.path, 'photos')).listSync(), isEmpty);
    });

    testDb('free: the second picture asks for Pro', (t) async {
      final file = p.join(PhotoStore.folderOverride!.path, 'aaaaaaaa-0001.png');
      File(file).writeAsBytesSync(_png);
      await t.runAsync(() => items.addPhoto(gown, file, isPro: false));
      final item = await t.runAsync(() => items.get(gown));
      await t.pumpWidget(host(ItemFormScreen(item: item), pro: false));
      await settle(t);
      expect(find.byType(PhotoThumb), findsOneWidget);
      expect(find.text('More with Pro'), findsOneWidget);
      await t.tap(find.text('More with Pro'));
      await settle(t);
      expect(
        find.text('The free plan keeps 1 picture of each item. Pro keeps up to 5.'),
        findsOneWidget,
      );
    });

    testDb('Pro picks several from the gallery, and the cover can be changed', (t) async {
      PhotoStore.manyPicker = () async => [source('g1.png'), source('g2.png'), source('g3.png')];
      final item = await t.runAsync(() => items.get(gown));
      await t.pumpWidget(host(ItemFormScreen(item: item)));
      await settle(t);
      await t.tap(find.text('Add picture'));
      await settle(t);
      await t.tap(find.text('Choose from the gallery'));
      await settle(t);
      expect(find.byType(PhotoThumb), findsNWidgets(3));
      // make the third the cover, then save
      await t.tap(find.byTooltip('Make this the cover').last);
      await settle(t);
      await t.ensureVisible(find.text('Save'));
      await t.tap(find.text('Save'));
      await settle(t);
      final saved = await t.runAsync(() => items.photosOf(gown));
      expect(saved, hasLength(3));
      final covers = await t.runAsync(() => items.covers());
      expect(covers![gown], saved!.first.path);
    });

    testDb('a gallery that returns too many drops the extras', (t) async {
      PhotoStore.manyPicker = () async => [
        for (var i = 0; i < 7; i++) source('m$i.png'),
      ];
      final item = await t.runAsync(() => items.get(gown));
      await t.pumpWidget(host(ItemFormScreen(item: item)));
      await settle(t);
      await t.tap(find.text('Add picture'));
      await settle(t);
      await t.tap(find.text('Choose from the gallery'));
      await settle(t);
      expect(find.byType(PhotoThumb), findsNWidgets(proPhotosPerItem));
      expect(Directory(p.join(dir.path, 'photos')).listSync(), hasLength(proPhotosPerItem));
    });

    testDb('removing a saved picture deletes it on Save', (t) async {
      final file = p.join(PhotoStore.folderOverride!.path, 'aaaaaaaa-0002.png');
      File(file).writeAsBytesSync(_png);
      await t.runAsync(() => items.addPhoto(gown, file, isPro: true));
      final item = await t.runAsync(() => items.get(gown));
      await t.pumpWidget(host(ItemFormScreen(item: item)));
      await settle(t);
      await t.tap(find.byTooltip('Remove this picture'));
      await settle(t);
      expect(find.byType(PhotoThumb), findsNothing);
      expect(File(file).existsSync(), isTrue, reason: 'not until Save');
      await t.ensureVisible(find.text('Save'));
      await t.tap(find.text('Save'));
      await settle(t);
      expect(await savedFor(t, gown), 0);
      expect(File(file).existsSync(), isFalse);
    });
  });

  group('the items list and sending', () {
    Future<void> withPicture(WidgetTester t) async {
      final file = p.join(PhotoStore.folderOverride!.path, 'aaaaaaaa-0003.png');
      File(file).writeAsBytesSync(_png);
      await t.runAsync(() => items.addPhoto(gown, file, isPro: true));
    }

    testDb('an item with a picture shows it in the list', (t) async {
      await withPicture(t);
      await t.pumpWidget(host(const ItemsScreen()));
      await settle(t);
      expect(find.text('Red gown'), findsOneWidget);
      expect(find.byType(PhotoThumb), findsOneWidget);
    });

    testDb('send on WhatsApp: the pictures and the text go, to a chosen chat', (t) async {
      await withPicture(t);
      wa.imagesWhatsAppSender = ({
        required List<String> paths,
        required String phone,
        required String message,
      }) async {
        _sent = (paths, phone, message);
        return wa.PdfSendResult.whatsapp;
      };
      await t.pumpWidget(host(const ItemsScreen()));
      await settle(t);
      await t.tap(find.byTooltip('Send on WhatsApp'));
      await settle(t);
      expect(find.text('Send Red gown on WhatsApp'), findsOneWidget);
      await t.tap(find.text('Choose the chat in WhatsApp'));
      await settle(t);
      final text = _sent!.$3;
      expect(_sent!.$1, hasLength(1));
      expect(_sent!.$2, '');
      expect(text, contains('Red gown'));
      expect(text, contains('Size: 38'));
      expect(text, contains('Rent: '));
      expect(text, contains('Deposit: '));
      expect(text, contains('Royal Costumes'));
    });

    testDb('send to a customer opens their chat', (t) async {
      await withPicture(t);
      await t.runAsync(
        () => CustomerRepo().save(
          Customer(name: 'Anu', phone: '9000000001', createdAt: DateTime(2027)),
        ),
      );
      wa.imagesWhatsAppSender = ({
        required List<String> paths,
        required String phone,
        required String message,
      }) async {
        _sent = (paths, phone, message);
        return wa.PdfSendResult.whatsapp;
      };
      await t.pumpWidget(host(const ItemsScreen()));
      await settle(t);
      await t.tap(find.byTooltip('Send on WhatsApp'));
      await settle(t);
      await t.tap(find.text('Anu'));
      await settle(t);
      expect(_sent!.$2, '9000000001');
    });

    testDb('an item with no picture can still be sent as text', (t) async {
      wa.imagesWhatsAppSender = ({
        required List<String> paths,
        required String phone,
        required String message,
      }) async {
        _sent = (paths, phone, message);
        return wa.PdfSendResult.whatsapp;
      };
      await t.pumpWidget(host(const ItemsScreen()));
      await settle(t);
      await t.tap(find.byTooltip('Send on WhatsApp'));
      await settle(t);
      await t.tap(find.text('Choose the chat in WhatsApp'));
      await settle(t);
      expect(_sent!.$1, isEmpty);
      expect(_sent!.$3, contains('Red gown'));
    });
  });

  group('the catalog', () {
    testDb('free is asked for Pro, Pro opens the catalog', (t) async {
      await t.pumpWidget(host(const ItemsScreen(), pro: false));
      await settle(t);
      await t.tap(find.byTooltip('Share a catalog'));
      await settle(t);
      expect(
        find.text('Sharing a catalog of your items with their pictures is part of Pro.'),
        findsOneWidget,
      );
      expect(find.byType(CatalogScreen), findsNothing);
      await t.tap(find.text('Not now'));
      await settle(t);

      await t.pumpWidget(host(const ItemsScreen()));
      await settle(t);
      await t.tap(find.byTooltip('Share a catalog'));
      await settle(t);
      expect(find.byType(CatalogScreen), findsOneWidget);
      expect(find.text('Red gown'), findsOneWidget);
    });

    testDb('sending the catalog builds a PDF and sends it', (t) async {
      final file = p.join(PhotoStore.folderOverride!.path, 'aaaaaaaa-0004.png');
      File(file).writeAsBytesSync(_png);
      await t.runAsync(() => items.addPhoto(gown, file, isPro: true));
      String? name;
      int? size;
      wa.pdfWhatsAppSender = ({
        required bytes,
        required fileName,
        required phone,
        required message,
      }) async {
        name = fileName;
        size = bytes.length;
        return wa.PdfSendResult.whatsapp;
      };
      await t.pumpWidget(host(const CatalogScreen()));
      await settle(t);
      expect(find.text('1 chosen'), findsOneWidget, reason: 'items with a picture start ticked');
      await t.tap(find.text('Send on WhatsApp'));
      for (var i = 0; i < 30 && name == null; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await t.pump();
      }
      expect(name, 'catalog.pdf');
      expect(size, greaterThan(500));
    });
  });

  group('the catalog PDF', () {
    setUp(PdfTextKit.resetForTests);
    const shop = BusinessProfile(name: 'Royal Costumes', phone: '9876543210', type: ShopType.costume);
    RentItem item(String name) =>
        RentItem(name: name, rate: 1200, deposit: 500, size: 'L', category: 'Gown', createdAt: DateTime(2027));

    test('builds with pictures, without rates, and with a picture that is not readable', () async {
      final withPic = await buildCatalogPdf(
        shop: shop,
        entries: [CatalogEntry(item('A'), Uint8List.fromList(_png)), CatalogEntry(item('B'), null)],
        showRates: true,
      );
      expect(latin1.decode(withPic.sublist(0, 5)), '%PDF-');
      final noRates = await buildCatalogPdf(
        shop: shop,
        entries: [CatalogEntry(item('A'), Uint8List.fromList(_png))],
        showRates: false,
      );
      expect(latin1.decode(noRates.sublist(0, 5)), '%PDF-');
      final broken = await buildCatalogPdf(
        shop: shop,
        entries: [CatalogEntry(item('A'), Uint8List.fromList([1, 2, 3, 4]))],
        showRates: true,
      );
      expect(latin1.decode(broken.sublist(0, 5)), '%PDF-');
    });

    test('many items run onto more pages', () async {
      final one = await buildCatalogPdf(
        shop: shop,
        entries: [CatalogEntry(item('A'), null)],
        showRates: true,
      );
      final many = await buildCatalogPdf(
        shop: shop,
        entries: [for (var i = 0; i < 40; i++) CatalogEntry(item('Item $i'), null)],
        showRates: true,
      );
      expect(many.length, greaterThan(one.length));
    });
  });
}

(List<String>, String, String)? _sent;
