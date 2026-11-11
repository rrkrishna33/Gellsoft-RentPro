import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/core/booking_math.dart';
import 'package:gellsoft_rentpro/core/constants.dart';
import 'package:gellsoft_rentpro/core/format.dart';
import 'package:gellsoft_rentpro/core/pdf_text.dart';
import 'package:gellsoft_rentpro/core/share.dart' as share;
import 'package:gellsoft_rentpro/core/theme.dart';
import 'package:gellsoft_rentpro/core/whatsapp_pdf.dart' as wa;
import 'package:gellsoft_rentpro/data/booking_models.dart';
import 'package:gellsoft_rentpro/data/booking_repo.dart';
import 'package:gellsoft_rentpro/data/business_profile.dart';
import 'package:gellsoft_rentpro/data/database.dart';
import 'package:gellsoft_rentpro/data/models.dart';
import 'package:gellsoft_rentpro/data/notifications.dart';
import 'package:gellsoft_rentpro/data/photo_store.dart';
import 'package:gellsoft_rentpro/data/repositories.dart';
import 'package:gellsoft_rentpro/features/bookings/booking_detail_screen.dart';
import 'package:gellsoft_rentpro/features/customers/customer_form_screen.dart';
import 'package:gellsoft_rentpro/features/invoices/invoice_list_screen.dart';
import 'package:gellsoft_rentpro/features/items/item_form_screen.dart';
import 'package:gellsoft_rentpro/features/reminders/reminders_screen.dart';
import 'package:gellsoft_rentpro/features/reports/reports_screen.dart';
import 'package:gellsoft_rentpro/features/settings/billing_settings_screen.dart';
import 'package:gellsoft_rentpro/features/settings/settings_screen.dart';
import 'package:gellsoft_rentpro/l10n/strings.dart';
import 'package:gellsoft_rentpro/subscription/entitlement.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _gstShop = BusinessProfile(
  name: 'Royal Costumes',
  type: ShopType.costume,
  phone: '9000000000',
  gstEnabled: true,
  gstin: '33ABCDE1234F1Z5',
  stateCode: '33',
);

class _FixedProfile extends ProfileNotifier {
  _FixedProfile(this.p);
  final BusinessProfile p;
  @override
  Future<BusinessProfile?> build() async => p;
}

class _Phone implements NotificationBackend {
  final scheduled = <PlannedNotification>[];
  int cancels = 0;
  int permissionAsked = 0;

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async {
    permissionAsked++;
    return true;
  }

  @override
  Future<void> cancelAll() async => cancels++;

  @override
  Future<void> schedule(PlannedNotification n) async => scheduled.add(n);
}

/// The database answers in real time, so time has to pass outside the fake
/// clock for it to reply.
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Waits (in real time) until [done] is true: building a PDF takes a moment.
Future<void> until(WidgetTester t, bool Function() done) async {
  for (var i = 0; i < 600 && !done(); i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pump(const Duration(milliseconds: 50));
  }
}

void tall(WidgetTester t) {
  t.view.physicalSize = const Size(900, 3000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Widget host(Widget child, {bool pro = true, BusinessProfile shop = _gstShop}) =>
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        profileProvider.overrideWith(() => _FixedProfile(shop)),
        isProProvider.overrideWithValue(pro),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: child),
    );

void main() {
  final items = ItemRepo();
  final customers = CustomerRepo();
  final bookings = BookingRepo();
  late int anu, gown, tent;
  late Directory photoDir;
  final opened = <Uri>[];
  final sharedPdfs = <String>[];
  final onWhatsApp = <({String file, String phone, String message, int size})>[];
  final phone = _Phone();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  /// A widget test on a fresh temporary database with a customer, a gown and
  /// a tent. Every call to the database goes through runAsync.
  void testDb(String name, Future<void> Function(WidgetTester t) body) {
    testWidgets(name, (t) async {
      SharedPreferences.setMockInitialValues({
        'b_name': 'Royal Costumes',
        'b_type': 'costume',
      });
      final dir = Directory.systemTemp.createTempSync('rentpro_flow');
      photoDir = Directory('${dir.path}/photos')..createSync();
      AppDatabase.pathOverride = '${dir.path}/t.db';
      PhotoStore.folderOverride = photoDir;
      PdfTextKit.resetForTests();
      opened.clear();
      sharedPdfs.clear();
      onWhatsApp.clear();
      wa.pdfWhatsAppSender = ({
        required Uint8List bytes,
        required String fileName,
        required String phone,
        required String message,
      }) async {
        expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
        onWhatsApp.add((file: fileName, phone: phone, message: message, size: bytes.length));
        return wa.PdfSendResult.whatsapp;
      };
      phone.scheduled.clear();
      phone.cancels = 0;
      phone.permissionAsked = 0;
      NotificationService.backend = phone;
      share.linkOpener = (u) async {
        opened.add(u);
        return true;
      };
      share.pdfSharer = (Uint8List bytes, String name) async {
        expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
        sharedPdfs.add(name);
      };
      await t.runAsync(() async {
        anu = await customers.save(
          Customer(
            name: 'Anu',
            phone: '98765 43210',
            stateCode: '33',
            createdAt: DateTime(2027),
          ),
        );
        gown = await items.save(
          RentItem(
            name: 'Red gown',
            rate: 1000,
            deposit: 500,
            hsn: '9973',
            gstRate: 18,
            createdAt: DateTime(2027),
          ),
        );
        tent = await items.save(
          RentItem(
            name: 'Tent',
            rate: 400,
            rateType: RateType.day,
            hsn: '9973',
            gstRate: 5,
            createdAt: DateTime(2027),
          ),
        );
      });
      try {
        tall(t);
        await body(t);
      } finally {
        Lang.current = AppLanguage.en;
        share.linkOpener = null;
        share.pdfSharer = null;
        wa.pdfWhatsAppSender = null;
        PhotoStore.picker = null;
        PhotoStore.folderOverride = null;
        await t.runAsync(() => AppDatabase.instance.close());
        AppDatabase.pathOverride = null;
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });
  }

  DateTime d(int n) => dayOf(DateTime.now()).add(Duration(days: n));

  Future<int> seed(
    WidgetTester t, {
    List<int>? ids,
    int pickup = 1,
    int event = 2,
    int ret = 3,
    double advance = 0,
    int? customer,
  }) async {
    final id = await t.runAsync(
      () => bookings.create(
        BookingDraft(
          customerId: customer ?? anu,
          eventDate: d(event),
          pickupDate: d(pickup),
          returnDate: d(ret),
          itemIds: ids ?? [gown],
        ),
        isPro: true,
        advance: advance,
        gst: _gstShop.gst,
      ),
    );
    return id!;
  }

  Future<Booking> reload(WidgetTester t, int id) async =>
      (await t.runAsync(() => bookings.get(id)))!;

  /// Puts a photo file where the camera would, and tells the store about it.
  String fakeShot(String name) {
    final f = File('${photoDir.parent.path}/$name.jpg')
      ..writeAsBytesSync(List.filled(64, 7));
    return f.path;
  }

  testDb('invoice: create from a booking, share, WhatsApp, cancel', (t) async {
    final id = await seed(t, ids: [gown, tent], advance: 500);
    await t.pumpWidget(host(BookingDetailScreen(bookingId: id)));
    await settle(t);

    // the money shows GST
    expect(find.text('GST'), findsOneWidget);
    expect(find.text(money(240)), findsOneWidget);
    expect(find.text('Create tax invoice'), findsOneWidget);

    await t.tap(find.text('Create tax invoice'));
    await settle(t);
    expect(find.text('RNT-0001'), findsWidgets);
    expect(find.text('Tax invoice'), findsOneWidget);
    expect(find.text('CGST'), findsOneWidget);
    expect(find.text('SGST'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);

    await t.tap(find.text('Share PDF'));
    await until(t, () => sharedPdfs.isNotEmpty);
    expect(sharedPdfs, ['RNT-0001.pdf']);

    await t.tap(find.text('WhatsApp'));
    await until(t, () => onWhatsApp.isNotEmpty);
    // WhatsApp gets the invoice PDF itself, the customer's number and the message
    expect(onWhatsApp.single.file, 'RNT-0001.pdf');
    expect(onWhatsApp.single.phone, '98765 43210');
    expect(onWhatsApp.single.message, contains('RNT-0001'));
    expect(onWhatsApp.single.message, contains('tax invoice'));
    expect(onWhatsApp.single.size, greaterThan(1500));
    expect(opened, isEmpty, reason: 'no plain text link is opened as well');

    // back on the booking the invoice is linked, and it is in the list
    await t.pageBack();
    await settle(t);
    expect(find.text('Create tax invoice'), findsNothing);
    expect(find.text('RNT-0001'), findsOneWidget);

    await t.pumpWidget(host(const InvoiceListScreen()));
    await settle(t);
    expect(find.textContaining('RNT-0001  Anu'), findsOneWidget);
    expect(find.textContaining('Tax invoice'), findsOneWidget);

    // open it and cancel it
    await t.tap(find.textContaining('RNT-0001  Anu'));
    await settle(t);
    await t.tap(find.byType(PopupMenuButton<String>));
    await settle(t);
    await t.tap(find.text('Cancel invoice').last);
    await settle(t);
    expect(find.text('Cancel this invoice?'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Cancel invoice'));
    await settle(t);
    expect(find.text('Cancelled'), findsWidgets);
    await t.pageBack();
    await settle(t);
  });

  testDb('a plain bill when GST is off', (t) async {
    final id = await t.runAsync(
      () => bookings.create(
        BookingDraft(
          customerId: anu,
          eventDate: d(2),
          pickupDate: d(1),
          returnDate: d(3),
          itemIds: [gown],
        ),
        isPro: true,
        gst: GstConfig.off,
      ),
    );
    await t.pumpWidget(
      host(
        BookingDetailScreen(bookingId: id!),
        shop: const BusinessProfile(name: 'Shop', type: ShopType.other),
      ),
    );
    await settle(t);
    expect(find.text('Create bill'), findsOneWidget);
    expect(find.text('GST'), findsNothing);
    await t.tap(find.text('Create bill'));
    await settle(t);
    expect(find.text('Rental bill'), findsOneWidget);
    expect(find.text('CGST'), findsNothing);
  });

  testDb('payment receipts: PDF and WhatsApp; messages to the customer', (t) async {
    final id = await seed(t, advance: 400);
    await t.pumpWidget(host(BookingDetailScreen(bookingId: id)));
    await settle(t);

    await t.tap(find.byTooltip('Receipt'));
    await settle(t);
    await t.tap(find.text('Share receipt PDF'));
    await until(t, () => sharedPdfs.isNotEmpty);
    expect(sharedPdfs.single, startsWith('receipt-'));

    await t.tap(find.byTooltip('Receipt'));
    await settle(t);
    await t.tap(find.text('Send receipt on WhatsApp'));
    await until(t, () => onWhatsApp.isNotEmpty);
    expect(onWhatsApp.single.file, startsWith('receipt-'));
    expect(onWhatsApp.single.message, contains('received ₹400.00'));
    expect(opened, isEmpty);
    await settle(t); // let the menu finish closing

    await t.tap(find.text('Send booking details on WhatsApp'));
    await settle(t);
    expect(opened.last.queryParameters['text'], contains('is confirmed'));
    expect(opened.last.queryParameters['text'], contains('Red gown'));

    await t.tap(find.text('Remind to collect the items'));
    await settle(t);
    expect(opened.last.queryParameters['text'], contains('ready at Royal Costumes'));

    await t.tap(find.text('Remind about the balance'));
    await settle(t);
    expect(opened.last.queryParameters['text'], contains('is pending for booking #1'));

    await t.tap(find.text('Call Anu'));
    await settle(t);
    expect(opened.last.scheme, 'tel');
    expect(opened.length, 4, reason: 'details, two reminders and the call');
  });

  testDb('a customer with no phone: WhatsApp says so and opens nothing', (t) async {
    final nophone = await t.runAsync(
      () => customers.save(Customer(name: 'No phone', createdAt: DateTime(2027))),
    );
    final id = await seed(t, customer: nophone);
    await t.pumpWidget(host(BookingDetailScreen(bookingId: id)));
    await settle(t);
    await t.tap(find.text('Send booking details on WhatsApp'));
    await settle(t);
    expect(opened, isEmpty);
    expect(
      find.text('Could not open WhatsApp. Check the customer phone number.'),
      findsOneWidget,
    );
    expect(find.textContaining('Call'), findsNothing);
  });

  testDb('photos: two are free, a third needs Pro, removing deletes the file', (t) async {
    final id = await seed(t);
    var n = 0;
    PhotoStore.picker = (camera) async => fakeShot('shot${n++}');
    await t.pumpWidget(host(BookingDetailScreen(bookingId: id), pro: false));
    await settle(t);
    expect(find.text('0 of 2 on the free plan'), findsOneWidget);

    Future<void> add() async {
      await t.tap(find.text('Add photo'));
      await settle(t);
      await t.tap(find.text('Take photo'));
      await settle(t);
    }

    await add();
    await add();
    var b = await reload(t, id);
    expect(b.photos.length, 2);
    expect(b.photos.first.stage, 'pickup');
    expect(File(b.photos.first.path).existsSync(), isTrue);
    expect(find.text('2 of 2 on the free plan'), findsOneWidget);

    // the third is refused before the camera opens
    await t.tap(find.text('Add photo'));
    await settle(t);
    expect(find.text('This needs Pro'), findsOneWidget);
    expect(find.textContaining('keeps 2 photos'), findsOneWidget);
    expect(n, 2, reason: 'the camera was not opened');
    await t.tap(find.text('Not now'));
    await settle(t);

    // remove the first one
    final path = b.photos.first.path;
    await t.tap(find.byType(Image).first);
    await settle(t);
    await t.tap(find.text('Remove').last);
    await settle(t);
    expect(find.text('Remove this photo?'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Remove'));
    await settle(t);
    b = await reload(t, id);
    expect(b.photos.length, 1);
    expect(File(path).existsSync(), isFalse);
  });

  testDb('photos: Pro keeps more, and the stage can be chosen', (t) async {
    final id = await seed(t);
    var n = 0;
    PhotoStore.picker = (camera) async => fakeShot('pro${n++}');
    await t.pumpWidget(host(BookingDetailScreen(bookingId: id)));
    await settle(t);
    expect(find.textContaining('on the free plan'), findsNothing);
    for (var i = 0; i < 3; i++) {
      await t.tap(find.text('Add photo'));
      await settle(t);
      if (i == 1) {
        await t.tap(find.widgetWithText(ChoiceChip, 'Return'));
        await settle(t);
      }
      await t.tap(find.text('Choose from gallery'));
      await settle(t);
    }
    final b = await reload(t, id);
    expect(b.photos.length, 3);
    expect(b.photos.map((p) => p.stage), ['pickup', 'return', 'pickup']);
  });

  testDb('a cancelled picture never gets saved', (t) async {
    final id = await seed(t);
    PhotoStore.picker = (camera) async => null;
    await t.pumpWidget(host(BookingDetailScreen(bookingId: id)));
    await settle(t);
    await t.tap(find.text('Add photo'));
    await settle(t);
    await t.tap(find.text('Take photo'));
    await settle(t);
    expect((await reload(t, id)).photos, isEmpty);
  });

  testDb('reminders: sections, and the WhatsApp button', (t) async {
    // out and late: overdue
    final late = await seed(t, ids: [tent], pickup: -6, event: -5, ret: -3);
    await t.runAsync(() => bookings.markPickedUp(late));
    // to send tomorrow, nothing paid: send items and balance
    await seed(t, ids: [gown], pickup: 1, event: 2, ret: 3);
    await t.pumpWidget(host(const RemindersScreen()));
    await settle(t);
    expect(find.text('Overdue returns'), findsOneWidget);
    expect(find.text('Send the items'), findsOneWidget);
    expect(find.text('Money to collect'), findsOneWidget);
    expect(find.textContaining('#1  Anu'), findsWidgets);

    await t.tap(find.byTooltip('Send on WhatsApp').first);
    await settle(t);
    expect(opened.single.queryParameters['text'], contains('were due back on'));
  });

  testDb('reminders: nothing to do', (t) async {
    await t.pumpWidget(host(const RemindersScreen()));
    await settle(t);
    expect(find.text('Nothing needs your attention right now.'), findsOneWidget);
  });

  testDb('reports: figures for the month, and the period chips', (t) async {
    final now = DateTime.now();
    // an event today: inside every "this month" range
    final today = dayOf(now);
    await t.runAsync(
      () => bookings.create(
        BookingDraft(
          customerId: anu,
          eventDate: today,
          pickupDate: today.subtract(const Duration(days: 1)),
          returnDate: today.add(const Duration(days: 1)),
          itemIds: [gown],
        ),
        isPro: true,
        advance: 300,
        gst: _gstShop.gst,
      ),
    );
    await t.pumpWidget(host(const ReportsScreen()));
    await settle(t);
    expect(find.text('Rent billed'), findsOneWidget);
    expect(find.text(money(1180)), findsWidgets);
    expect(find.text(money(300)), findsWidgets, reason: 'collected');
    expect(find.text(money(880)), findsWidgets, reason: 'still to collect');
    expect(find.text('Red gown'), findsOneWidget);
    expect(find.text('Anu'), findsOneWidget);
    expect(find.text('GST in the bills'), findsOneWidget);

    await t.tap(find.text('Last month'));
    await settle(t);
    expect(find.text('No bookings in this period.'), findsOneWidget);
    await t.tap(find.text('Today'));
    await settle(t);
    expect(find.text(money(1180)), findsWidgets);
  });

  testDb('billing settings: GST on, a bad GSTIN is refused, a good one saves', (t) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [isProProvider.overrideWithValue(true)],
        child: MaterialApp(theme: AppTheme.light(), home: const BillingSettingsScreen()),
      ),
    );
    await settle(t);
    expect(find.text('Invoices are plain bills, with no tax.'), findsOneWidget);
    expect(find.text('Your GSTIN'), findsNothing);

    await t.tap(find.text('Charge GST'));
    await settle(t);
    expect(find.text('Invoices are tax invoices with GST.'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextFormField, 'Your GSTIN'), 'NOT-A-GSTIN');
    await t.enterText(find.widgetWithText(TextFormField, 'Letters before the number'), 'ry');
    await t.scrollUntilVisible(
      find.text('Save'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Save'));
    await settle(t);
    expect(find.text('This GSTIN does not look right'), findsOneWidget);

    await t.enterText(find.widgetWithText(TextFormField, 'Your GSTIN'), '33abcde1234f1z5');
    await t.tap(find.text('Save'));
    await settle(t);
    final p = (await t.runAsync(BusinessProfile.load))!;
    expect(p.gstEnabled, isTrue);
    expect(p.gstin, '33ABCDE1234F1Z5');
    expect(p.invoicePrefix, 'RY');
  });

  testDb('item and customer forms show GST fields only when GST is on', (t) async {
    await t.pumpWidget(host(const ItemFormScreen()));
    await settle(t);
    expect(find.text('GST rate'), findsOneWidget);
    expect(find.text('SAC / HSN code'), findsOneWidget);

    await t.pumpWidget(host(const ItemFormScreen(), shop: const BusinessProfile(name: 'S', type: ShopType.other)));
    await settle(t);
    expect(find.text('GST rate'), findsNothing);

    await t.pumpWidget(host(const CustomerFormScreen()));
    await settle(t);
    expect(find.text('Customer GSTIN (optional)'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextFormField, 'Customer name'), 'Biz');
    await t.enterText(find.widgetWithText(TextFormField, 'Customer GSTIN (optional)'), 'bad');
    await t.scrollUntilVisible(find.text('Save'), 200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('Save'));
    await settle(t);
    expect(find.text('This GSTIN does not look right'), findsOneWidget);
  });

  testDb('settings: reminders are Pro; Pro switches schedule notifications', (t) async {
    await seed(t);
    await t.pumpWidget(host(const Scaffold(body: SettingsScreen()), pro: false));
    await settle(t);
    expect(find.text('Reminder notifications'), findsOneWidget);
    await t.tap(find.text('Reminder notifications'));
    await settle(t);
    expect(find.text('This needs Pro'), findsOneWidget);
    expect(find.textContaining('Reminder notifications are part of Pro'), findsOneWidget);
    await t.tap(find.text('Not now'));
    await settle(t);

    await t.pumpWidget(host(const Scaffold(body: SettingsScreen())));
    await settle(t);
    expect(find.text('Morning summary'), findsOneWidget);
    await t.tap(find.text('Morning summary'));
    await settle(t);
    expect(phone.permissionAsked, 1, reason: 'the notification permission is asked when a switch changes');
    expect(phone.cancels, greaterThan(0), reason: 'the reminders were set again');
    final s = (await t.runAsync(NotifySettings.load))!;
    expect(s.daily, isFalse);
    expect(s.beforeEvent, isTrue);
  });
}
