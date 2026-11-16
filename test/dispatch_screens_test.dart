import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/core/constants.dart';
import 'package:gellsoft_rentpro/core/format.dart';
import 'package:gellsoft_rentpro/core/theme.dart';
import 'package:gellsoft_rentpro/data/booking_models.dart';
import 'package:gellsoft_rentpro/data/booking_repo.dart';
import 'package:gellsoft_rentpro/data/business_profile.dart';
import 'package:gellsoft_rentpro/data/database.dart';
import 'package:gellsoft_rentpro/data/models.dart';
import 'package:gellsoft_rentpro/data/repositories.dart';
import 'package:gellsoft_rentpro/features/bookings/availability_calendar_screen.dart';
import 'package:gellsoft_rentpro/features/bookings/booking_detail_screen.dart';
import 'package:gellsoft_rentpro/features/bookings/bookings_screen.dart';
import 'package:gellsoft_rentpro/features/customers/customer_history_screen.dart';
import 'package:gellsoft_rentpro/features/reminders/bulk_reminders_screen.dart';
import 'package:gellsoft_rentpro/features/reminders/reminders_screen.dart';
import 'package:gellsoft_rentpro/features/reports/reports_screen.dart';
import 'package:gellsoft_rentpro/l10n/strings.dart';
import 'package:gellsoft_rentpro/subscription/entitlement.dart';
import 'package:gellsoft_rentpro/subscription/license_state.dart';
import 'package:gellsoft_rentpro/subscription/plan.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'license_fixtures.dart';

class _Profile extends ProfileNotifier {
  _Profile(this.type);
  final ShopType type;
  @override
  Future<BusinessProfile?> build() async =>
      BusinessProfile(name: 'Shop', type: type);
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

void tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Widget host(
  Widget child, {
  bool pro = true,
  ShopType type = ShopType.costume,
}) => ProviderScope(
  key: ValueKey(pro),
  overrides: [
    profileProvider.overrideWith(() => _Profile(type)),
    isProProvider.overrideWithValue(pro),
    licenseProvider.overrideWith(() => _License(pro)),
  ],
  child: MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child)),
);

void main() {
  final items = ItemRepo();
  final customers = CustomerRepo();
  final bookings = BookingRepo();
  late int anu, sherwani;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  void testDb(String name, Future<void> Function(WidgetTester t) body) {
    testWidgets(name, (t) async {
      SharedPreferences.setMockInitialValues({});
      final dir = Directory.systemTemp.createTempSync('rentpro_dispatch_ui');
      AppDatabase.pathOverride = '${dir.path}/t.db';
      await t.runAsync(() async {
        anu = await customers.save(
          Customer(
            name: 'Anu',
            phone: '9000000001',
            notes: 'Likes ivory, chest 40',
            createdAt: DateTime(2027),
          ),
        );
        sherwani = await items.save(
          RentItem(name: 'Red sherwani', rate: 2000, createdAt: DateTime(2027)),
        );
      });
      try {
        tall(t);
        await body(t);
      } finally {
        Lang.current = AppLanguage.en;
        await t.runAsync(() => AppDatabase.instance.close());
        AppDatabase.pathOverride = null;
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });
  }

  Future<Booking> reload(WidgetTester t, int id) async =>
      (await t.runAsync(() => bookings.get(id)))!;

  Future<int> seed(
    WidgetTester t, {
    int pickup = 1,
    int event = 2,
    int ret = 3,
  }) async {
    final today = dayOf(DateTime.now());
    DateTime d(int n) => today.add(Duration(days: n));
    final id = await t.runAsync(
      () => bookings.create(
        BookingDraft(
          customerId: anu,
          eventDate: d(event),
          pickupDate: d(pickup),
          returnDate: d(ret),
          itemIds: [sherwani],
        ),
        isPro: true,
      ),
    );
    return id!;
  }

  testDb('dispatch by courier: name and number, then returned', (t) async {
    final id = await seed(t);
    await t.pumpWidget(host(BookingDetailScreen(bookingId: id)));
    await settle(t);
    expect(find.text('Dispatch by courier'), findsOneWidget);
    expect(find.text('Mark as picked up'), findsOneWidget);

    await t.tap(find.text('Dispatch by courier'));
    await settle(t);
    await t.enterText(
      find.widgetWithText(TextField, 'Courier name (optional)'),
      'DTDC',
    );
    await t.enterText(
      find.widgetWithText(TextField, 'Courier booking number (optional)'),
      'D12345',
    );
    await t.tap(find.widgetWithText(FilledButton, 'Mark as dispatched'));
    await settle(t);

    final b = await reload(t, id);
    expect(b.status, BookingStatus.dispatched);
    expect(b.courierName, 'DTDC');
    expect(b.courierNo, 'D12345');
    // the page now shows the courier, and offers the next steps
    expect(find.text('Courier'), findsWidgets);
    expect(find.text('D12345'), findsOneWidget);
    expect(find.text('Send courier details on WhatsApp'), findsOneWidget);
    expect(find.text('Change courier details'), findsOneWidget);
    expect(find.text('Dispatch by courier'), findsNothing);

    await t.tap(find.text('Mark as returned'));
    await settle(t);
    expect((await reload(t, id)).status, BookingStatus.returned);
  });

  testDb('the courier name and number can be left empty', (t) async {
    final id = await seed(t);
    await t.pumpWidget(host(BookingDetailScreen(bookingId: id)));
    await settle(t);
    await t.tap(find.text('Dispatch by courier'));
    await settle(t);
    await t.tap(find.widgetWithText(FilledButton, 'Mark as dispatched'));
    await settle(t);
    final b = await reload(t, id);
    expect(b.status, BookingStatus.dispatched);
    expect(b.courierName, '');
  });

  testDb('the courier details can be corrected afterwards', (t) async {
    final id = await seed(t);
    await t.runAsync(
      () => bookings.markDispatched(id, courierName: 'DTDC', courierNo: '1'),
    );
    await t.pumpWidget(host(BookingDetailScreen(bookingId: id)));
    await settle(t);
    await t.tap(find.text('Change courier details'));
    await settle(t);
    await t.enterText(
      find.widgetWithText(TextField, 'Courier booking number (optional)'),
      '999',
    );
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(t);
    expect((await reload(t, id)).courierNo, '999');
  });

  testDb('a makeup artist has no courier option', (t) async {
    final id = await seed(t);
    await t.pumpWidget(
      host(BookingDetailScreen(bookingId: id), type: ShopType.makeup),
    );
    await settle(t);
    expect(find.text('Dispatch by courier'), findsNothing);
    expect(find.text('Mark as done'), findsOneWidget);
  });

  testDb('the list shows the courier of a dispatched booking', (t) async {
    final id = await seed(t);
    await t.runAsync(
      () => bookings.markDispatched(id, courierName: 'DTDC', courierNo: 'D1'),
    );
    await t.pumpWidget(host(const BookingsScreen()));
    await settle(t);
    await t.tap(find.text('Out'));
    await settle(t);
    expect(find.text('Dispatched'), findsOneWidget);
    expect(find.text('DTDC · D1'), findsOneWidget);
  });

  testDb('the list has a Balance due tab', (t) async {
    await seed(t);
    await t.pumpWidget(host(const BookingsScreen()));
    await settle(t);
    await t.tap(find.text('Balance due'));
    await settle(t);
    expect(find.textContaining('#1  Anu'), findsOneWidget);
  });

  testDb('a charge: free is asked for Pro, Pro can add and remove it', (t) async {
    final id = await seed(t);
    await t.runAsync(() => bookings.markPickedUp(id));

    await t.pumpWidget(host(BookingDetailScreen(bookingId: id), pro: false));
    await settle(t);
    await t.tap(find.text('Add late fee or damage charge'));
    await settle(t);
    expect(
      find.text('Adding late fees and damage charges to a booking is part of Pro.'),
      findsOneWidget,
    );
    expect((await reload(t, id)).charges, isEmpty);
    await t.tap(find.text('Not now'));
    await settle(t);

    await t.pumpWidget(host(BookingDetailScreen(bookingId: id)));
    await settle(t);
    await t.tap(find.text('Add late fee or damage charge'));
    await settle(t);
    await t.enterText(find.widgetWithText(TextField, 'Amount (₹)'), '350');
    await t.enterText(
      find.widgetWithText(TextField, 'Note (optional)'),
      'torn sleeve',
    );
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(t);
    var b = await reload(t, id);
    expect(b.charges.single.amount, 350);
    expect(b.charges.single.kind, ChargeKind.damage);
    expect(b.payable, 2350);
    expect(find.text('Damage (torn sleeve)'), findsOneWidget);

    await t.tap(find.textContaining('Remove Damage'));
    await settle(t);
    await t.tap(find.widgetWithText(FilledButton, 'Remove'));
    await settle(t);
    b = await reload(t, id);
    expect(b.charges, isEmpty);
    expect(b.payable, 2000);
  });

  testDb('a late return offers a late fee, which can be skipped', (t) async {
    final id = await seed(t, pickup: -5, event: -4, ret: -2);
    await t.runAsync(() => bookings.markPickedUp(id));
    await t.pumpWidget(host(BookingDetailScreen(bookingId: id)));
    await settle(t);
    await t.tap(find.text('Mark as returned'));
    await settle(t);
    expect(find.text('Returned late'), findsOneWidget);
    expect(
      find.text('These items are 2 days late. Add a late fee for them?'),
      findsOneWidget,
    );
    await t.tap(find.text('No late fee'));
    await settle(t);
    final b = await reload(t, id);
    expect(b.status, BookingStatus.returned);
    expect(b.charges, isEmpty);
  });

  testDb('a free shop returning late items is not stopped by a Pro prompt', (t) async {
    final id = await seed(t, pickup: -5, event: -4, ret: -2);
    await t.runAsync(() => bookings.markPickedUp(id));
    await t.pumpWidget(host(BookingDetailScreen(bookingId: id), pro: false));
    await settle(t);
    await t.tap(find.text('Mark as returned'));
    await settle(t);
    expect(find.text('Returned late'), findsNothing);
    expect(find.text('Not now'), findsNothing);
    expect((await reload(t, id)).status, BookingStatus.returned);
  });

  testDb('a late return with a late fee records both', (t) async {
    final id = await seed(t, pickup: -5, event: -4, ret: -2);
    await t.runAsync(() => bookings.markPickedUp(id));
    await t.pumpWidget(host(BookingDetailScreen(bookingId: id)));
    await settle(t);
    await t.tap(find.text('Mark as returned'));
    await settle(t);
    await t.tap(find.text('Add late fee'));
    await settle(t);
    await t.enterText(find.widgetWithText(TextField, 'Amount (₹)'), '400');
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(t);
    final b = await reload(t, id);
    expect(b.status, BookingStatus.returned);
    expect(b.charges.single.kind, ChargeKind.late);
    expect(b.charges.single.amount, 400);
    expect(b.charges.single.note, '2 days late');
  });

  testDb('remind everyone who owes: Pro only, then a list with Send next', (t) async {
    await seed(t);
    await t.pumpWidget(host(const RemindersScreen(), pro: false));
    await settle(t);
    await t.tap(find.byTooltip('Remind everyone who owes'));
    await settle(t);
    expect(
      find.text('Reminding everyone who owes money in one go is part of Pro.'),
      findsOneWidget,
    );
    expect(find.byType(BulkRemindersScreen), findsNothing);
    await t.tap(find.text('Not now'));
    await settle(t);

    await t.pumpWidget(host(const RemindersScreen()));
    await settle(t);
    await t.tap(find.byTooltip('Remind everyone who owes'));
    await settle(t);
    expect(find.byType(BulkRemindersScreen), findsOneWidget);
    expect(find.textContaining('#1  Anu'), findsOneWidget);
    expect(find.text('Send next: Anu'), findsOneWidget);
    expect(find.textContaining('1 bookings'), findsOneWidget);
  });

  testDb('exporting spreadsheets is Pro only', (t) async {
    await seed(t);
    await t.pumpWidget(host(const ReportsScreen(), pro: false));
    await settle(t);
    await t.scrollUntilVisible(
      find.text('Export a spreadsheet'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Export a spreadsheet'));
    await settle(t);
    expect(
      find.text(
        'Exporting spreadsheets, including the sheets for your accountant, is part of Pro.',
      ),
      findsOneWidget,
    );
  });

  testDb('customer history: bookings, what they owe, and their notes', (t) async {
    await seed(t);
    final c = await t.runAsync(() => customers.get(anu));
    await t.pumpWidget(host(CustomerHistoryScreen(customer: c!)));
    await settle(t);
    expect(find.text('Likes ivory, chest 40'), findsOneWidget);
    expect(find.text('Past bookings'), findsOneWidget);
    expect(find.textContaining('#1  Anu'), findsOneWidget);
    expect(find.text('Owes'), findsOneWidget);
  });

  testDb('customer history of someone with no bookings says so', (t) async {
    final c = await t.runAsync(() => customers.get(anu));
    await t.pumpWidget(host(CustomerHistoryScreen(customer: c!)));
    await settle(t);
    expect(find.text('This customer has no bookings yet.'), findsOneWidget);
  });

  testDb('the calendar shows booked days and who has what', (t) async {
    await seed(t, pickup: 0, event: 1, ret: 2);
    await t.pumpWidget(host(const AvailabilityCalendarScreen()));
    await settle(t);
    expect(find.text('Availability calendar'), findsOneWidget);
    // today is selected and held by the booking
    expect(find.textContaining('#1  Anu'), findsOneWidget);
    expect(find.text('Red sherwani'), findsWidgets);
    // an item filter is offered
    expect(find.text('Everything'), findsOneWidget);
  });
}
