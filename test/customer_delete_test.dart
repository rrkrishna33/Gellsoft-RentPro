import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/core/theme.dart';
import 'package:gellsoft_rentpro/data/booking_repo.dart';
import 'package:gellsoft_rentpro/data/database.dart';
import 'package:gellsoft_rentpro/data/models.dart';
import 'package:gellsoft_rentpro/data/repositories.dart';
import 'package:gellsoft_rentpro/features/customers/customers_screen.dart';
import 'package:gellsoft_rentpro/l10n/strings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('a customer can be removed from the list, with a warning when '
      'bookings are still open', (t) async {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('rentpro_cust_delete');
    AppDatabase.pathOverride = '${dir.path}/t.db';
    t.view.physicalSize = const Size(800, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    late int busy;
    late int bookingId;
    try {
      await t.runAsync(() async {
        busy = await CustomerRepo().save(
          Customer(name: 'Busy Bala', phone: '9000000002', createdAt: DateTime(2027)),
        );
        await CustomerRepo().save(
          Customer(name: 'Quiet Anu', phone: '9000000001', createdAt: DateTime(2027)),
        );
        final gown = await ItemRepo().save(
          RentItem(name: 'Gown', rate: 800, createdAt: DateTime(2027)),
        );
        final today = DateTime.now();
        final d = DateTime(today.year, today.month, today.day + 5);
        bookingId = await BookingRepo().create(
          BookingDraft(
            customerId: busy,
            eventDate: d,
            pickupDate: d,
            returnDate: d,
            itemIds: [gown],
          ),
          isPro: true,
        );
      });
      await t.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CustomersScreen()),
          ),
        ),
      );
      await settle(t);
      expect(find.text('Busy Bala'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));

      // Anu has no bookings: the plain question
      await t.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('Quiet Anu'),
            matching: find.byType(InkWell),
          ).first,
          matching: find.byIcon(Icons.delete_outline),
        ),
      );
      await settle(t);
      expect(find.text('Remove this customer?'), findsOneWidget);
      expect(
        find.text('Their old bookings stay. They will leave the customer list.'),
        findsOneWidget,
      );
      await t.tap(find.text('Cancel'));
      await settle(t);
      expect(find.text('Quiet Anu'), findsOneWidget, reason: 'cancel keeps them');

      // Bala has an open booking: the question says so
      await t.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('Busy Bala'),
            matching: find.byType(InkWell),
          ).first,
          matching: find.byIcon(Icons.delete_outline),
        ),
      );
      await settle(t);
      expect(
        find.textContaining('1 of their bookings are still open'),
        findsOneWidget,
      );
      await t.tap(find.widgetWithText(FilledButton, 'Remove'));
      await settle(t);
      expect(find.text('Busy Bala'), findsNothing);
      expect(find.text('Quiet Anu'), findsOneWidget);

      // the booking is still there and still has its customer's name
      final b = await t.runAsync(() => BookingRepo().get(bookingId));
      expect(b, isNotNull);
      expect(b!.customerName, 'Busy Bala');
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
