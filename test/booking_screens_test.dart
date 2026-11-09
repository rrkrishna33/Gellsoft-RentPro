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
import 'package:gellsoft_rentpro/features/bookings/booking_detail_screen.dart';
import 'package:gellsoft_rentpro/features/bookings/booking_form_screen.dart';
import 'package:gellsoft_rentpro/features/bookings/bookings_screen.dart';
import 'package:gellsoft_rentpro/l10n/strings.dart';
import 'package:gellsoft_rentpro/subscription/entitlement.dart';
import 'package:gellsoft_rentpro/subscription/plan.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Profile extends ProfileNotifier {
  @override
  Future<BusinessProfile?> build() async =>
      const BusinessProfile(name: 'Shop', type: ShopType.costume);
}

/// These screens talk to a real (temporary) database, so time has to pass
/// outside the fake clock for it to answer.
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

Widget host(Widget child, {bool pro = false}) => ProviderScope(
  overrides: [
    profileProvider.overrideWith(_Profile.new),
    isProProvider.overrideWithValue(pro),
  ],
  child: MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: child),
  ),
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

  /// A widget test on a fresh temporary database with a customer and two
  /// items. The database answers in real time, so every call to it runs
  /// inside [WidgetTester.runAsync].
  void testDb(String name, Future<void> Function(WidgetTester t) body) {
    testWidgets(name, (t) async {
      SharedPreferences.setMockInitialValues({});
      final dir = Directory.systemTemp.createTempSync('rentpro_screens');
      AppDatabase.pathOverride = '${dir.path}/t.db';
      await t.runAsync(() async {
        anu = await customers.save(
          Customer(name: 'Anu', phone: '9000000001', createdAt: DateTime(2027)),
        );
        sherwani = await items.save(
          RentItem(
            name: 'Red sherwani',
            rate: 2000,
            deposit: 3000,
            createdAt: DateTime(2027),
          ),
        );
        await items.save(
          RentItem(
            name: 'Blue gown',
            rate: 500,
            rateType: RateType.day,
            createdAt: DateTime(2027),
          ),
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

  Future<Booking> reload(WidgetTester t, int id) async {
    final b = await t.runAsync(() => bookings.get(id));
    return b!;
  }

  Future<int> seed(
    WidgetTester t, {
    int ret = 12,
    int pickup = 10,
    int event = 11,
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

  testDb('make a booking: customer, items, advance, save', (t) async {
    int? saved;
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          profileProvider.overrideWith(_Profile.new),
          isProProvider.overrideWithValue(false),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async => saved = await Navigator.of(ctx)
                      .push<int>(
                        MaterialPageRoute<int>(
                          builder: (_) => const BookingFormScreen(),
                        ),
                      ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await settle(t);
    expect(find.text('New booking'), findsOneWidget);
    expect(find.text('12 free bookings left this month.'), findsOneWidget);

    // saving with nothing chosen says what is missing
    await t.scrollUntilVisible(
      find.text('Save booking'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(find.text('Save booking'));
    await settle(t);
    expect(find.text('Choose the customer.'), findsOneWidget);

    await t.scrollUntilVisible(
      find.text('Choose the customer'),
      -300,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(find.text('Choose the customer'));
    await settle(t);
    await t.tap(find.text('Anu').last);
    await settle(t);
    expect(find.text('9000000001'), findsOneWidget);

    await t.tap(find.text('Choose items'));
    await settle(t);
    await t.tap(find.text('Red sherwani'));
    await t.tap(find.text('Blue gown'));
    await t.pump();
    await t.tap(find.text('Done (2)'));
    await settle(t);
    // 2000 flat + 500 x 3 days
    expect(find.text(money(3500)), findsWidgets);

    await t.enterText(
      find.widgetWithText(TextField, 'Advance paid (₹)'),
      '1000',
    );
    await t.pump();
    expect(find.text(money(2500)), findsWidgets, reason: 'balance to collect');
    await t.scrollUntilVisible(
      find.text('Save booking'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(find.text('Save booking'));
    await settle(t);

    expect(saved, isNotNull);
    final b = (await reload(t, saved!));
    expect(b.customerName, 'Anu');
    expect(b.lines.length, 2);
    expect(b.rentTotal, 3500);
    expect(b.rentPaid, 1000);
    expect(b.balanceDue, 2500);
    expect(b.depositTotal, 3000);
  });

  testDb('an item that is taken is greyed out and says who has it', (t) async {
    await seed(t, pickup: 6, event: 7, ret: 8); // sherwani, a week from now
    await t.pumpWidget(host(const BookingFormScreen()));
    await settle(t);
    await t.tap(find.text('Choose items'));
    await settle(t);
    expect(find.textContaining('Booked by Anu (#1)'), findsOneWidget);
    final tile = t.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Red sherwani'),
    );
    expect(tile.enabled, isFalse);
    final free = t.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Blue gown'),
    );
    expect(free.enabled, isTrue);
  });

  testDb('at the free limit the booking is refused and Pro is offered', (
    t,
  ) async {
    await t.runAsync(() async {
      for (var i = 0; i < FreePlan.bookingsPerMonth; i++) {
        final it = await items.save(
          RentItem(name: 'filler$i', rate: 10, createdAt: DateTime(2027)),
        );
        await bookings.create(
          BookingDraft(
            customerId: anu,
            eventDate: DateTime.now(),
            pickupDate: DateTime.now(),
            returnDate: DateTime.now(),
            itemIds: [it],
          ),
          isPro: true,
        );
      }
    });
    await t.pumpWidget(host(const BookingFormScreen()));
    await settle(t);
    expect(find.textContaining('used all 12 free bookings'), findsOneWidget);
    await t.tap(find.text('Choose the customer'));
    await settle(t);
    await t.tap(find.text('Anu').last);
    await settle(t);
    await t.tap(find.text('Choose items'));
    await settle(t);
    await t.tap(find.text('Red sherwani'));
    await t.pump();
    await t.tap(find.textContaining('Done'));
    await settle(t);
    await t.scrollUntilVisible(
      find.text('Save booking'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(find.text('Save booking'));
    await settle(t);
    expect(find.text('This needs Pro'), findsOneWidget);
    expect(find.textContaining('You have used them all'), findsOneWidget);
  });

  testDb('list shows the booking; detail takes payment, picks up, returns', (
    t,
  ) async {
    final id = await seed(t);
    await t.pumpWidget(host(const BookingsScreen()));
    await settle(t);
    expect(find.textContaining('#1  Anu'), findsOneWidget);
    expect(find.text('Red sherwani'), findsOneWidget);
    expect(find.textContaining('Due'), findsOneWidget);

    await t.tap(find.textContaining('#1  Anu'));
    await settle(t);
    expect(find.text('Balance to collect'), findsOneWidget);

    // take a payment of the default (everything due)
    await t.tap(find.text('Take payment'));
    await settle(t);
    await t.enterText(find.widgetWithText(TextField, 'Amount (₹)'), '500');
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(t);
    var b = (await reload(t, id));
    expect(b.rentPaid, 500);
    expect(b.payments.single.kind, PaymentKind.advance);

    // more than is due is refused with a hint
    await t.tap(find.text('Take payment'));
    await settle(t);
    await t.enterText(find.widgetWithText(TextField, 'Amount (₹)'), '99999');
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(t);
    expect(find.textContaining('Enter an amount up to'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await settle(t);

    // deposit
    await t.tap(find.text('Take deposit'));
    await settle(t);
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(t);
    b = (await reload(t, id));
    expect(b.depositHeld, 3000);

    await t.tap(find.text('Mark as picked up'));
    await settle(t);
    expect((await reload(t, id)).status, BookingStatus.pickedUp);

    // returning asks about the deposit; keep 500 back for a stain
    await t.tap(find.text('Mark as returned'));
    await settle(t);
    expect(find.text('Give deposit back'), findsWidgets);
    await t.enterText(find.widgetWithText(TextField, 'Amount (₹)'), '2500');
    await t.enterText(
      find.widgetWithText(TextField, 'Reason for keeping some (optional)'),
      'stain',
    );
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(t);
    b = (await reload(t, id));
    expect(b.status, BookingStatus.returned);
    expect(b.depositRefunded, 2500);
    expect(b.depositHeld, 500);
    expect(find.text('Mark as returned'), findsNothing);
  });

  testDb('cancelling asks first and frees the item', (t) async {
    final id = await seed(t);
    await t.pumpWidget(host(BookingDetailScreen(bookingId: id)));
    await settle(t);
    await t.tap(find.byType(PopupMenuButton<String>));
    await settle(t);
    await t.tap(find.text('Cancel booking').last);
    await settle(t);
    expect(find.text('Cancel this booking?'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Cancel booking'));
    await settle(t);
    final b = (await reload(t, id));
    expect(b.status, BookingStatus.cancelled);
    expect(find.text('Mark as picked up'), findsNothing);
  });

  testDb('Tamil labels show on the list', (t) async {
    Lang.current = AppLanguage.ta;
    await seed(t);
    await t.pumpWidget(host(const BookingsScreen()));
    await settle(t);
    expect(find.text('முன்பதிவுகள்'), findsOneWidget);
    expect(find.text('வரவிருப்பவை'), findsOneWidget);
    expect(find.textContaining('மீதி'), findsOneWidget);
  });
}
