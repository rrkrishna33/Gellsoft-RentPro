import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/core/format.dart';
import 'package:gellsoft_rentpro/core/constants.dart';
import 'package:gellsoft_rentpro/core/theme.dart';
import 'package:gellsoft_rentpro/data/booking_repo.dart';
import 'package:gellsoft_rentpro/data/business_profile.dart';
import 'package:gellsoft_rentpro/data/database.dart';
import 'package:gellsoft_rentpro/data/models.dart';
import 'package:gellsoft_rentpro/data/repositories.dart';
import 'package:gellsoft_rentpro/features/bookings/booking_form_screen.dart';
import 'package:gellsoft_rentpro/l10n/strings.dart';
import 'package:gellsoft_rentpro/subscription/entitlement.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Profile extends ProfileNotifier {
  @override
  Future<BusinessProfile?> build() async =>
      const BusinessProfile(name: 'Shop', type: ShopType.costume);
}

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

  testWidgets('an hourly item shows the times and prices the hours', (t) async {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('rentpro_hourly_screen');
    AppDatabase.pathOverride = '${dir.path}/t.db';
    t.view.physicalSize = const Size(800, 2600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    int? saved;
    try {
      await t.runAsync(() async {
        await CustomerRepo().save(
          Customer(name: 'Anu', phone: '9000000001', createdAt: DateTime(2027)),
        );
        await ItemRepo().save(
          RentItem(
            name: 'Court',
            rate: 500,
            rateType: RateType.hour,
            createdAt: DateTime(2027),
          ),
        );
        await ItemRepo().save(
          RentItem(name: 'Tent', rate: 800, createdAt: DateTime(2027)),
        );
      });
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider.overrideWith(_Profile.new),
            isProProvider.overrideWithValue(true),
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

      // no hourly item yet: no time rows
      expect(find.text('Pickup time'), findsNothing);

      await t.tap(find.text('Choose the customer'));
      await settle(t);
      await t.tap(find.text('Anu').last);
      await settle(t);

      await t.tap(find.text('Choose items'));
      await settle(t);
      await t.tap(find.text('Court'));
      await t.pump();
      await t.tap(find.text('Done (1)'));
      await settle(t);

      // the time rows appear, with the 10:00 to 12:00 start, two hours
      expect(find.text('Pickup time'), findsOneWidget);
      expect(find.text('Return time'), findsOneWidget);
      expect(find.text('10:00 AM'), findsOneWidget);
      expect(find.text('12:00 PM'), findsOneWidget);
      expect(
        find.text('Charged for 2 hours (each started hour counts).'),
        findsOneWidget,
      );
      expect(find.text(money(1000)), findsWidgets);

      await t.scrollUntilVisible(
        find.text('Save booking'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await t.tap(find.text('Save booking'));
      await settle(t);
      expect(saved, isNotNull);
      final b = await t.runAsync(() => BookingRepo().get(saved!));
      expect(b!.pickupTime, '10:00');
      expect(b.returnTime, '12:00');
      expect(b.rentTotal, 1000);
      // an hourly rental is one day: pickup, event and return are the same day
      expect(b.pickupDate, b.returnDate);
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
