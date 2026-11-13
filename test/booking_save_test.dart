import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/core/booking_math.dart';
import 'package:gellsoft_rentpro/core/theme.dart';
import 'package:gellsoft_rentpro/data/booking_models.dart';
import 'package:gellsoft_rentpro/data/booking_repo.dart';
import 'package:gellsoft_rentpro/data/database.dart';
import 'package:gellsoft_rentpro/data/models.dart';
import 'package:gellsoft_rentpro/data/repositories.dart';
import 'package:gellsoft_rentpro/features/bookings/booking_form_screen.dart';
import 'package:gellsoft_rentpro/l10n/strings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 14; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

class _Boom extends BookingRepo {
  int tries = 0;

  @override
  Future<int> create(
    BookingDraft draft, {
    required bool isPro,
    double advance = 0,
    PayMode advanceMode = PayMode.cash,
    GstConfig gst = GstConfig.off,
    bool checkAvailability = true,
    DateTime? now,
  }) async {
    tries++;
    throw StateError('the disk is full');
  }
}

/// The booking form, opened as a page so that its result can be seen.
Widget host({BookingRepo? repo, void Function(int?)? onResult}) => ProviderScope(
  overrides: [if (repo != null) bookingRepoProvider.overrideWithValue(repo)],
  child: MaterialApp(
    theme: AppTheme.light(),
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () async {
              final id = await Navigator.of(ctx).push<int>(
                MaterialPageRoute<int>(builder: (_) => const BookingFormScreen()),
              );
              onResult?.call(id);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  void testForm(String name, Future<void> Function(WidgetTester t) body,
      {bool gst = true}) {
    testWidgets(name, (t) async {
      t.view.physicalSize = const Size(900, 3000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      SharedPreferences.setMockInitialValues({
        'b_name': 'Royal',
        'b_type': 'costume',
        if (gst) 'b_gst': true,
        if (gst) 'b_state': '33',
      });
      final dir = Directory.systemTemp.createTempSync('rentpro_save');
      AppDatabase.pathOverride = '${dir.path}/t.db';
      await t.runAsync(() async {
        await CustomerRepo().save(
          Customer(name: 'Anu', phone: '9000000001', createdAt: DateTime(2027)),
        );
        await ItemRepo().save(
          RentItem(
            name: 'Gown',
            rate: 1000,
            deposit: 500,
            hsn: '9973',
            gstRate: 18,
            createdAt: DateTime(2027),
          ),
        );
      });
      try {
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

  Future<void> open(WidgetTester t) async {
    await t.tap(find.text('open'));
    await settle(t);
  }

  Future<void> pickCustomer(WidgetTester t) async {
    await t.tap(find.text('Choose the customer'));
    await settle(t);
    await t.tap(find.text('Anu').last);
    await settle(t);
  }

  Future<void> pickGown(WidgetTester t) async {
    await t.tap(find.text('Choose items'));
    await settle(t);
    await t.tap(find.text('Gown'));
    await t.pump();
    await t.tap(find.textContaining('Done'));
    await settle(t);
  }

  Future<void> tapSave(WidgetTester t) async {
    await t.scrollUntilVisible(
      find.text('Save booking'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(find.text('Save booking'));
    await settle(t);
  }

  testForm('saves with GST on, a discount and an advance', (t) async {
    int? saved;
    await t.pumpWidget(host(onResult: (id) => saved = id));
    await open(t);
    await pickCustomer(t);
    await pickGown(t);
    await t.enterText(find.widgetWithText(TextField, 'Advance paid (₹)'), '200');
    await t.enterText(find.widgetWithText(TextField, 'Discount (₹)'), '50');
    await t.pump();
    await tapSave(t);
    expect(saved, isNotNull, reason: 'the form closed with the booking id');
    final b = (await t.runAsync(() => BookingRepo().get(saved!)))!;
    expect(b.discount, 50);
    expect(b.taxTotal, 171); // 18% of 950
    expect(b.payable, 1121);
    expect(b.rentPaid, 200);
    expect(b.depositTotal, 500);
  });

  testForm('saves with GST off too', (t) async {
    int? saved;
    await t.pumpWidget(host(onResult: (id) => saved = id));
    await open(t);
    await pickCustomer(t);
    await pickGown(t);
    await tapSave(t);
    final b = (await t.runAsync(() => BookingRepo().get(saved!)))!;
    expect(b.payable, 1000);
    expect(b.taxTotal, 0);
  }, gst: false);

  testForm('without a customer the reason is shown and the button works again', (t) async {
    int? saved;
    await t.pumpWidget(host(onResult: (id) => saved = id));
    await open(t);
    await pickGown(t);
    await tapSave(t);
    expect(find.text('Choose the customer.'), findsWidgets);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(saved, isNull);
    // choose one and save again
    await t.scrollUntilVisible(
      find.text('Choose the customer'),
      -300,
      scrollable: find.byType(Scrollable).last,
    );
    await pickCustomer(t);
    await tapSave(t);
    expect(saved, isNotNull);
  });

  testForm('without items the reason is shown', (t) async {
    await t.pumpWidget(host());
    await open(t);
    await pickCustomer(t);
    await tapSave(t);
    expect(find.text('Choose at least one item.'), findsWidgets);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testForm('an unexpected error is shown, and saving can be tried again', (t) async {
    final boom = _Boom();
    await t.pumpWidget(host(repo: boom));
    await open(t);
    await pickCustomer(t);
    await pickGown(t);
    await tapSave(t);
    expect(boom.tries, 1);
    expect(find.textContaining('Could not save the booking: Bad state: the disk is full'), findsWidgets);
    expect(find.byType(SnackBar), findsOneWidget);
    // the button is alive again
    await tapSave(t);
    expect(boom.tries, 2);
  });
}
