import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/core/constants.dart';
import 'package:gellsoft_rentpro/core/theme.dart';
import 'package:gellsoft_rentpro/data/booking_repo.dart';
import 'package:gellsoft_rentpro/data/business_profile.dart';
import 'package:gellsoft_rentpro/data/database.dart';
import 'package:gellsoft_rentpro/data/models.dart';
import 'package:gellsoft_rentpro/data/repositories.dart';
import 'package:gellsoft_rentpro/features/bookings/booking_detail_screen.dart';
import 'package:gellsoft_rentpro/features/bookings/booking_form_screen.dart';
import 'package:gellsoft_rentpro/features/items/item_form_screen.dart';
import 'package:gellsoft_rentpro/l10n/strings.dart';
import 'package:gellsoft_rentpro/subscription/entitlement.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Costume extends ProfileNotifier {
  @override
  Future<BusinessProfile?> build() async =>
      const BusinessProfile(name: 'Shop', type: ShopType.costume);
}

class _Vehicle extends ProfileNotifier {
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

  Future<void> withDb(
    WidgetTester t,
    Future<void> Function(Directory dir) body,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('rentpro_control_screen');
    AppDatabase.pathOverride = '${dir.path}/t.db';
    t.view.physicalSize = const Size(800, 3000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    try {
      await body(dir);
    } finally {
      Lang.current = AppLanguage.en;
      await t.runAsync(() => AppDatabase.instance.close());
      AppDatabase.pathOverride = null;
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  Widget app(Widget home, {required ProfileNotifier Function() profile, bool pro = true}) =>
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          profileProvider.overrideWith(profile),
          isProProvider.overrideWithValue(pro),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: home),
      );

  testWidgets('a customer with a warning shows it on the booking form; a costume '
      'shop has a trial date, a bike shop does not', (t) async {
    await withDb(t, (_) async {
      await t.runAsync(() async {
        await CustomerRepo().save(
          Customer(
            name: 'Anu',
            phone: '9000000001',
            warning: 'Returned late twice',
            createdAt: DateTime(2027),
          ),
        );
      });
      await t.pumpWidget(app(const BookingFormScreen(), profile: _Costume.new));
      final c = ProviderScope.containerOf(t.element(find.byType(BookingFormScreen)));
      await t.runAsync(() => c.read(profileProvider.future));
      await t.pump();
      await settle(t);
      expect(find.text('Trial or fitting date'), findsOneWidget);
      expect(find.text('Returned late twice'), findsNothing);
      await t.tap(find.text('Choose the customer'));
      await settle(t);
      await t.tap(find.text('Anu').last);
      await settle(t);
      expect(find.text('Returned late twice'), findsOneWidget);
    });
    await withDb(t, (_) async {
      await t.pumpWidget(app(const BookingFormScreen(), profile: _Vehicle.new));
      final c = ProviderScope.containerOf(t.element(find.byType(BookingFormScreen)));
      await t.runAsync(() => c.read(profileProvider.future));
      await t.pump();
      await settle(t);
      expect(find.text('Trial or fitting date'), findsNothing);
    });
  });

  testWidgets('the item form: more control is part of Pro for a free shop',
      (t) async {
    await withDb(t, (_) async {
      await t.pumpWidget(
        app(const ItemFormScreen(), profile: _Costume.new, pro: false),
      );
      final c = ProviderScope.containerOf(t.element(find.byType(ItemFormScreen)));
      await t.runAsync(() => c.read(profileProvider.future));
      await t.pump();
      await settle(t);
      await t.scrollUntilVisible(
        find.text('More control'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Part of Pro'), findsOneWidget);
      expect(find.text('Gap after each return (hours)'), findsOneWidget);
      // the weekly rate is only for items rented by the day
      expect(find.text('Weekly rate (₹)'), findsNothing);
      await t.tap(find.text('Per day'));
      await t.pump();
      expect(find.text('Weekly rate (₹)'), findsOneWidget);
      expect(find.text('Monthly rate (₹)'), findsOneWidget);
      // a tap on a locked field offers Pro
      await t.tap(find.text('Weekly rate (₹)'), warnIfMissed: false);
      await settle(t);
      expect(find.textContaining('Weekly and monthly rates'), findsWidgets);
    });
  });

  testWidgets('the booking page offers the agreement and extending the return',
      (t) async {
    await withDb(t, (_) async {
      late int id;
      await t.runAsync(() async {
        final anu = await CustomerRepo().save(
          Customer(name: 'Anu', phone: '9000000001', createdAt: DateTime(2027)),
        );
        final bike = await ItemRepo().save(
          RentItem(
            name: 'Bike',
            rate: 100,
            rateType: RateType.day,
            createdAt: DateTime(2027),
          ),
        );
        final today = DateTime.now();
        final d = DateTime(today.year, today.month, today.day + 3);
        id = await BookingRepo().create(
          BookingDraft(
            customerId: anu,
            eventDate: d,
            pickupDate: d,
            returnDate: d.add(const Duration(days: 1)),
            itemIds: [bike],
          ),
          isPro: true,
        );
      });
      await t.pumpWidget(
        app(BookingDetailScreen(bookingId: id), profile: _Vehicle.new),
      );
      await settle(t);
      await t.scrollUntilVisible(
        find.text('Rental agreement'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Rental agreement'), findsOneWidget);
      await t.scrollUntilVisible(
        find.text('Extend or change the return'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('Extend or change the return'));
      await settle(t);
      expect(find.text('New return date'), findsOneWidget);
      expect(find.textContaining('worked out again'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await settle(t);
    });
  });
}
