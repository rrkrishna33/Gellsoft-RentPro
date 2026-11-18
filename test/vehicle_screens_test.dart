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
import 'package:gellsoft_rentpro/features/items/item_form_screen.dart';
import 'package:gellsoft_rentpro/l10n/strings.dart';
import 'package:gellsoft_rentpro/subscription/entitlement.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Profile extends ProfileNotifier {
  @override
  Future<BusinessProfile?> build() async =>
      const BusinessProfile(name: 'Shop', type: ShopType.vehicle);
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

  Widget app(Widget home) => ProviderScope(
    overrides: [
      profileProvider.overrideWith(_Profile.new),
      isProProvider.overrideWithValue(true),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: home),
  );

  testWidgets('a bike shop: no event date, and the rent can be changed',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('rentpro_vehicle_screen');
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
            name: 'Activa',
            rate: 400,
            rateType: RateType.day,
            deposit: 2000,
            createdAt: DateTime(2027),
          ),
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
      // the shop's profile is loaded long before the form in the real app
      final container = ProviderScope.containerOf(t.element(find.text('open')));
      await t.runAsync(() => container.read(profileProvider.future));
      await t.tap(find.text('open'));
      await settle(t);

      // pickup and return, but no event date
      expect(find.text('Pickup date'), findsOneWidget);
      expect(find.text('Return date'), findsOneWidget);
      expect(find.text('Event date'), findsNothing);
      expect(find.text('Remind me before pickup'), findsOneWidget);

      await t.tap(find.text('Choose the customer'));
      await settle(t);
      await t.tap(find.text('Anu').last);
      await settle(t);
      await t.tap(find.text('Choose vehicles'));
      await settle(t);
      await t.tap(find.text('Activa'));
      await t.pump();
      await t.tap(find.text('Done (1)'));
      await settle(t);

      // today to tomorrow: two days at 400
      expect(find.text(money(800)), findsWidgets);

      // agree 350 a day and a smaller deposit
      await t.tap(find.byTooltip('Change the rent'));
      await settle(t);
      expect(find.text('Usual rate: ${money(400)}'), findsOneWidget);
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await t.enterText(fields.first, '350');
      await t.pump();
      expect(find.text('This line comes to ${money(700)}'), findsOneWidget);
      await t.enterText(fields.last, '1500');
      await t.tap(find.text('Done').last);
      await settle(t);
      expect(find.textContaining('changed'), findsWidgets);
      expect(find.text(money(700)), findsWidgets);

      await t.scrollUntilVisible(
        find.text('Save booking'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await t.tap(find.text('Save booking'));
      await settle(t);
      expect(saved, isNotNull);
      final b = await t.runAsync(() => BookingRepo().get(saved!));
      expect(b!.lines.single.rate, 350);
      expect(b.lines.single.deposit, 1500);
      expect(b.rentTotal, 700);
      expect(b.depositTotal, 1500);
      // no event of its own: it is the pickup day
      expect(b.eventDate, b.pickupDate);
    } finally {
      Lang.current = AppLanguage.en;
      await t.runAsync(() => AppDatabase.instance.close());
      AppDatabase.pathOverride = null;
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  testWidgets('a bike shop: the item form says vehicle, not piece', (t) async {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('rentpro_vehicle_item');
    AppDatabase.pathOverride = '${dir.path}/t.db';
    t.view.physicalSize = const Size(800, 2600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    try {
      await t.pumpWidget(app(const ItemFormScreen()));
      await settle(t);
      expect(find.text('Add vehicle'), findsOneWidget);
      expect(find.text('Rent for one vehicle (₹)'), findsOneWidget);
      expect(find.text('Deposit for one vehicle (₹)'), findsOneWidget);
      expect(find.text('Vehicles you have'), findsOneWidget);
      expect(find.text('Rent for one piece (₹)'), findsNothing);
      // by the day or the hour; never per event
      expect(find.text('Per day'), findsOneWidget);
      expect(find.text('Per hour'), findsOneWidget);
      expect(find.text('Per event'), findsNothing);
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
