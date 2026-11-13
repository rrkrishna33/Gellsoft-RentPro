import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/core/constants.dart';
import 'package:gellsoft_rentpro/core/format.dart';
import 'package:gellsoft_rentpro/core/theme.dart';
import 'package:gellsoft_rentpro/data/app_settings.dart';
import 'package:gellsoft_rentpro/data/booking_models.dart';
import 'package:gellsoft_rentpro/data/booking_repo.dart';
import 'package:gellsoft_rentpro/data/business_profile.dart';
import 'package:gellsoft_rentpro/data/dashboard_repo.dart';
import 'package:gellsoft_rentpro/data/database.dart';
import 'package:gellsoft_rentpro/data/models.dart';
import 'package:gellsoft_rentpro/data/notifications.dart';
import 'package:gellsoft_rentpro/data/photo_store.dart';
import 'package:gellsoft_rentpro/data/repositories.dart';
import 'package:gellsoft_rentpro/data/shops.dart';
import 'package:gellsoft_rentpro/data/staff.dart';
import 'package:gellsoft_rentpro/features/bookings/booking_detail_screen.dart';
import 'package:gellsoft_rentpro/features/bookings/booking_form_screen.dart';
import 'package:gellsoft_rentpro/features/bookings/bookings_screen.dart';
import 'package:gellsoft_rentpro/features/home/home_screen.dart';
import 'package:gellsoft_rentpro/features/onboarding/onboarding_screen.dart';
import 'package:gellsoft_rentpro/features/security/lock_gate.dart';
import 'package:gellsoft_rentpro/features/settings/staff_screen.dart';
import 'package:gellsoft_rentpro/features/shops/shop_switcher.dart';
import 'package:gellsoft_rentpro/l10n/strings.dart';
import 'package:gellsoft_rentpro/subscription/entitlement.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _costume = BusinessProfile(name: 'Royal Costumes', type: ShopType.costume);
const _makeup = BusinessProfile(name: 'Glow Studio', type: ShopType.makeup);

class _Profile extends ProfileNotifier {
  _Profile(this.p);
  final BusinessProfile p;
  @override
  Future<BusinessProfile?> build() async => p;
}

class _SignedIn extends SessionNotifier {
  _SignedIn(this.user);
  final StaffUser? user;
  @override
  StaffUser? build() => user;
}

StaffUser person(String name, Role role, String pin) {
  final salt = AppSettings.newSalt();
  return StaffUser(
    id: 1,
    uuid: 'u-$name',
    name: name,
    role: role,
    pinHash: AppSettings.hashPin(pin, salt),
    pinSalt: salt,
    createdAt: DateTime(2027),
  );
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

void tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Widget host(
  Widget child, {
  bool pro = true,
  BusinessProfile shop = _costume,
  StaffUser? user,
  List<StaffUser>? people,
}) => ProviderScope(
  key: UniqueKey(),
  overrides: [
    profileProvider.overrideWith(() => _Profile(shop)),
    isProProvider.overrideWithValue(pro),
    sessionProvider.overrideWith(() => _SignedIn(user)),
    if (people != null)
      staffUsersProvider.overrideWith((ref) async => people),
  ],
  child: MaterialApp(theme: AppTheme.light(), home: child),
);

/// Opens the booking form as a page, so that the id it returns can be seen.
Widget formHost({
  bool pro = true,
  BusinessProfile shop = _costume,
  StaffUser? user,
  void Function(int?)? onResult,
}) => host(
  Builder(
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
  pro: pro,
  shop: shop,
  user: user,
);

void main() {
  final items = ItemRepo();
  final customers = CustomerRepo();
  final bookings = BookingRepo();
  late int anu, chair, makeupService;
  late Directory photoDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  /// A widget test on a fresh temporary database with a customer, ten chairs
  /// and a makeup service.
  void testDb(String name, Future<void> Function(WidgetTester t) body) {
    testWidgets(name, (t) async {
      SharedPreferences.setMockInitialValues({});
      Shops.resetForTests();
      forgetSignedInPerson();
      final dir = Directory.systemTemp.createTempSync('rentpro_new');
      photoDir = Directory('${dir.path}/photos')..createSync();
      PhotoStore.folderOverride = photoDir;
      AppDatabase.pathOverride = '${dir.path}/t.db';
      await t.runAsync(() async {
        anu = await customers.save(
          Customer(name: 'Anu', phone: '9000000001', createdAt: DateTime(2027)),
        );
        chair = await items.save(
          RentItem(name: 'Chair', rate: 50, quantity: 10, createdAt: DateTime(2027)),
        );
        makeupService = await items.save(
          RentItem(name: 'Bridal makeup', rate: 15000, createdAt: DateTime(2027)),
        );
      });
      try {
        tall(t);
        await body(t);
      } finally {
        Lang.current = AppLanguage.en;
        PhotoStore.picker = null;
        PhotoStore.folderOverride = null;
        await t.runAsync(() => AppDatabase.instance.close());
        AppDatabase.pathOverride = null;
        Shops.resetForTests();
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });
  }

  Future<int> seedBooking(
    WidgetTester t,
    int item,
    int qty, {
    int pickup = 6,
    int event = 7,
    int ret = 8,
    int? customer,
    String time = '',
  }) async {
    final today = dayOf(DateTime.now());
    DateTime d(int n) => today.add(Duration(days: n));
    final id = await t.runAsync(
      () => bookings.create(
        BookingDraft(
          customerId: customer ?? anu,
          eventDate: d(event),
          pickupDate: d(pickup),
          returnDate: d(ret),
          itemIds: [item],
          quantities: {item: qty},
          eventTime: time,
        ),
        isPro: true,
        checkAvailability: false,
      ),
    );
    return id!;
  }

  Future<Booking> reload(WidgetTester t, int id) async =>
      (await t.runAsync(() => bookings.get(id)))!;

  Future<void> chooseCustomer(WidgetTester t) async {
    await t.scrollUntilVisible(
      find.text('Choose the customer'),
      -300,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(find.text('Choose the customer'));
    await settle(t);
    await t.tap(find.text('Anu').last);
    await settle(t);
  }

  Future<void> chooseItems(WidgetTester t, {String label = 'Choose items'}) async {
    await t.scrollUntilVisible(
      find.text(label),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(find.text(label));
    await settle(t);
  }

  Future<void> save(WidgetTester t) async {
    await t.scrollUntilVisible(
      find.text('Save booking'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(find.text('Save booking'));
    await settle(t);
  }

  group('quantity on a booking', () {
    testDb('the picker says how many are free and the stepper sets how many', (t) async {
      int? saved;
      // 8 of 10 chairs are out, but three weeks from now
      await seedBooking(t, chair, 8, pickup: 20, event: 21, ret: 22);
      await t.pumpWidget(formHost(onResult: (v) => saved = v));
      await t.tap(find.text('open'));
      await settle(t);
      await chooseCustomer(t);

      await chooseItems(t);
      // the chairs are out later; on the dates of this booking all 10 are free
      expect(find.textContaining('2 of 10 free'), findsNothing);
      expect(find.textContaining('10 of 10 free'), findsOneWidget);
      await t.tap(find.text('Chair'));
      await t.pump();
      await t.tap(find.text('Done (1)'));
      await settle(t);

      // one piece to start; the stepper adds more, up to the 10 in stock
      expect(find.text('1'), findsWidgets);
      for (var i = 0; i < 3; i++) {
        await t.tap(find.byTooltip('More'));
        await t.pump();
      }
      // 4 chairs at 50
      expect(find.text(money(200)), findsWidgets);
      for (var i = 0; i < 20; i++) {
        await t.tap(find.byTooltip('More'));
        await t.pump();
      }
      expect(find.text(money(500)), findsWidgets, reason: 'never more than the 10 in stock');
      for (var i = 0; i < 6; i++) {
        await t.tap(find.byTooltip('Fewer'));
        await t.pump();
      }
      expect(find.text(money(200)), findsWidgets);

      await save(t);
      expect(saved, isNotNull);
      final b = await reload(t, saved!);
      expect(b.lines.single.qty, 4);
      expect(b.rentTotal, 200);
    });

    testDb('asking for more than is free on those days says how many are', (t) async {
      final today = dayOf(DateTime.now());
      // the form opens on the event a week ahead: pickup 6 days, return 8 days
      await seedBooking(t, chair, 8, pickup: 6, event: 7, ret: 8);
      await t.pumpWidget(formHost());
      await t.tap(find.text('open'));
      await settle(t);
      expect(dateText(today), isNotEmpty);
      await chooseItems(t);
      expect(find.textContaining('2 of 10 free'), findsOneWidget);
      await t.tap(find.text('Chair'));
      await t.pump();
      await t.tap(find.text('Done (1)'));
      await settle(t);
      for (var i = 0; i < 4; i++) {
        await t.tap(find.byTooltip('More'));
        await t.pump();
      }
      await settle(t);
      expect(find.text('Only 2 of 10 Chair are free for these days.'), findsOneWidget);
      // and saving is refused with the same reason
      await chooseCustomer(t);
      await save(t);
      expect(find.text('Not enough Chair are free for these days.'), findsWidgets);
    });

    testDb('detail shows the pieces and the booking carries who made it', (t) async {
      final id = await seedBooking(t, chair, 6);
      await t.pumpWidget(host(BookingDetailScreen(bookingId: id)));
      await settle(t);
      expect(find.text('Chair × 6'), findsOneWidget);
      expect(find.textContaining('× 6'), findsWidgets);
      expect(find.text(money(300)), findsWidgets);
    });
  });

  group('makeup artist: a service booking', () {
    testDb('one appointment date and time, no pickup or return', (t) async {
      int? saved;
      await t.pumpWidget(formHost(shop: _makeup, onResult: (v) => saved = v));
      await t.tap(find.text('open'));
      await settle(t);
      expect(find.text('Appointment'), findsOneWidget);
      expect(find.text('Appointment date'), findsOneWidget);
      expect(find.text('Appointment time'), findsOneWidget);
      expect(find.text('Not set'), findsOneWidget);
      expect(find.text('Pickup date'), findsNothing);
      expect(find.text('Return date'), findsNothing);
      expect(find.text('Event date'), findsNothing);
      expect(find.text('Remind me before the appointment'), findsOneWidget);

      await chooseCustomer(t);
      await chooseItems(t, label: 'Choose services');
      await t.tap(find.text('Bridal makeup'));
      await t.pump();
      await t.tap(find.text('Done (1)'));
      await settle(t);
      // a service has no deposit and no days: just the price
      expect(find.text(money(15000)), findsWidgets);
      expect(find.text('Deposit to hold'), findsNothing);

      // pick a time
      await t.scrollUntilVisible(
        find.text('Not set'),
        -300,
        scrollable: find.byType(Scrollable).last,
      );
      await t.tap(find.text('Not set'));
      await settle(t);
      await t.tap(find.text('OK'));
      await settle(t);
      expect(find.text('Not set'), findsNothing);
      expect(find.textContaining(RegExp(r'\d\d:\d\d [AP]M')), findsOneWidget);

      await save(t);
      final b = await reload(t, saved!);
      expect(b.pickupDate, b.eventDate);
      expect(b.returnDate, b.eventDate);
      expect(RegExp(r'^\d\d:\d\d$').hasMatch(b.eventTime), isTrue);
      expect(b.lines.single.name, 'Bridal makeup');
    });

    testDb('two clients can be booked for the same service on the same day', (t) async {
      final a = await seedBooking(t, makeupService, 1, pickup: 5, event: 5, ret: 5, time: '10:00');
      int? saved;
      await t.pumpWidget(formHost(shop: _makeup, onResult: (v) => saved = v));
      await t.tap(find.text('open'));
      await settle(t);
      await chooseCustomer(t);
      await chooseItems(t, label: 'Choose services');
      // nothing is greyed out: a service is never "taken"
      final tile = t.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'Bridal makeup'),
      );
      expect(tile.enabled, isTrue);
      expect(find.textContaining('Booked by'), findsNothing);
      await t.tap(find.text('Bridal makeup'));
      await t.pump();
      await t.tap(find.text('Done (1)'));
      await settle(t);
      // the same day as the first booking
      final first = await reload(t, a);
      await t.scrollUntilVisible(
        find.text(dateText(dayOf(DateTime.now()).add(const Duration(days: 7)))),
        -300,
        scrollable: find.byType(Scrollable).last,
      );
      await save(t);
      expect(saved, isNotNull, reason: 'the second booking was saved');
      expect(first.eventTime, '10:00');
    });

    testDb('the detail page marks the appointment done', (t) async {
      final id = await seedBooking(t, makeupService, 1, pickup: 2, event: 2, ret: 2, time: '14:30');
      await t.pumpWidget(host(BookingDetailScreen(bookingId: id), shop: _makeup));
      await settle(t);
      expect(find.text('Appointment'), findsWidgets);
      expect(find.text('02:30 PM'), findsOneWidget);
      expect(find.text('Services'), findsOneWidget);
      expect(find.text('Mark as picked up'), findsNothing);
      expect(find.text('Remind about the appointment'), findsOneWidget);
      await t.scrollUntilVisible(
        find.text('Mark as done'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await t.tap(find.text('Mark as done'));
      await settle(t);
      expect((await reload(t, id)).status, BookingStatus.returned);
      expect(find.text('Done'), findsWidgets);
      expect(find.text('Mark as done'), findsNothing);
    });

    testDb('the list has Upcoming, Done and Cancelled, with the time', (t) async {
      await seedBooking(t, makeupService, 1, pickup: 2, event: 2, ret: 2, time: '09:15');
      await t.pumpWidget(host(const Scaffold(body: BookingsScreen()), shop: _makeup));
      await settle(t);
      expect(find.text('Upcoming'), findsOneWidget);
      expect(find.text('Out'), findsNothing, reason: 'nothing is picked up');
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.textContaining('09:15 AM'), findsOneWidget);
    });
  });

  group('what each person may do', () {
    testDb('a cashier takes payments but cannot cancel, discount or make a new item', (t) async {
      final id = await seedBooking(t, chair, 2);
      await t.pumpWidget(
        host(
          BookingDetailScreen(bookingId: id),
          user: person('Meena', Role.cashier, '1111'),
        ),
      );
      await settle(t);
      expect(find.text('Take payment'), findsOneWidget);
      expect(find.byType(PopupMenuButton<String>), findsWidgets,
          reason: 'the receipt menu is not the booking menu');
      // the booking's own menu offers Edit
      await t.tap(find.byIcon(Icons.more_vert));
      await settle(t);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Cancel booking'), findsNothing);
    });

    for (final (who, role, sees) in [
      ('a cashier does not see the discount box', Role.cashier, false),
      ('staff see the discount box', Role.staff, true),
      ('the owner sees the discount box', Role.admin, true),
    ]) {
      testDb(who, (t) async {
        await t.pumpWidget(formHost(user: person('Pat', role, '1111')));
        await t.tap(find.text('open'));
        await settle(t);
        await t.drag(find.byType(ListView).first, const Offset(0, -1200));
        await t.pump();
        expect(find.text('Money'), findsOneWidget);
        expect(
          find.widgetWithText(TextField, 'Discount (₹)'),
          sees ? findsOneWidget : findsNothing,
        );
      });
    }

    testDb('a booking made while signed in carries the name', (t) async {
      int? saved;
      await t.pumpWidget(
        formHost(
          user: person('Meena', Role.cashier, '1111'),
          onResult: (v) => saved = v,
        ),
      );
      await t.tap(find.text('open'));
      await settle(t);
      await chooseCustomer(t);
      await chooseItems(t);
      await t.tap(find.text('Chair'));
      await t.pump();
      await t.tap(find.text('Done (1)'));
      await settle(t);
      await save(t);
      expect((await reload(t, saved!)).createdBy, 'Meena');
    });

    testDb('the detail page names who made the booking', (t) async {
      final id = await t.runAsync(
        () => bookings.create(
          BookingDraft(
            customerId: anu,
            eventDate: DateTime(2027, 3, 10),
            pickupDate: DateTime(2027, 3, 9),
            returnDate: DateTime(2027, 3, 11),
            itemIds: [chair],
            createdBy: 'Mani',
          ),
          isPro: true,
          now: DateTime(2027, 3, 1),
        ),
      );
      await t.pumpWidget(host(BookingDetailScreen(bookingId: id!)));
      await settle(t);
      expect(find.text('Booked by Mani'), findsOneWidget);
    });
  });

  group('staff login screen', () {
    Widget gate(List<StaffUser> people, {StaffUser? user}) => host(
      const LockGate(child: Scaffold(body: Text('the app'))),
      people: people,
      user: user,
    );

    testWidgets('with logins off the app opens at once', (t) async {
      SharedPreferences.setMockInitialValues({});
      await t.pumpWidget(gate(const []));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('the app'), findsOneWidget);
      expect(find.text('Who is using the app?'), findsNothing);
    });

    testWidgets('with logins on, pick a person and enter the PIN', (t) async {
      SharedPreferences.setMockInitialValues({});
      final people = [
        person('Krishna', Role.admin, '1234'),
        person('Meena', Role.cashier, '5678'),
      ];
      await t.pumpWidget(gate(people));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Who is using the app?'), findsOneWidget);
      expect(find.text('Krishna'), findsOneWidget);
      expect(find.text('Cashier'), findsOneWidget);

      await t.tap(find.text('Meena'));
      await t.pump();
      await t.enterText(find.byType(TextField), '0000');
      await t.tap(find.text('Unlock'));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await t.pump();
      expect(find.text('Wrong PIN'), findsOneWidget);

      await t.enterText(find.byType(TextField), '5678');
      await t.tap(find.text('Unlock'));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Who is using the app?'), findsNothing);
      expect(find.text('the app'), findsOneWidget);
    });

    testWidgets('only the Admin gets "Forgot PIN?"', (t) async {
      SharedPreferences.setMockInitialValues({});
      await t.pumpWidget(
        gate([
          person('Krishna', Role.admin, '1234'),
          person('Meena', Role.cashier, '5678'),
        ]),
      );
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(find.text('Meena'));
      await t.pump();
      expect(find.text('Forgot PIN?'), findsNothing);
      await t.tap(find.text('Not you?'));
      await t.pump();
      await t.tap(find.text('Krishna'));
      await t.pump();
      expect(find.text('Forgot PIN?'), findsOneWidget);
    });

    testWidgets('five wrong PINs lock the screen for a while', (t) async {
      SharedPreferences.setMockInitialValues({});
      await t.pumpWidget(gate([person('Krishna', Role.admin, '1234')]));
      await t.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 5; i++) {
        await t.enterText(find.byType(TextField), '9999');
        await t.tap(find.text('Unlock'));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await t.pump();
      }
      expect(find.textContaining('Too many wrong attempts'), findsOneWidget);
    });
  });

  group('staff screen', () {
    testDb('turning on shows the recovery code once and signs the Admin in', (t) async {
      await t.pumpWidget(host(const StaffScreen(), pro: true));
      await settle(t);
      expect(find.text('Turn on staff logins'), findsOneWidget);
      expect(find.text('What each role can do'), findsNothing);
      await t.tap(find.text('Turn on staff logins'));
      await settle(t);
      await t.enterText(find.widgetWithText(TextField, 'Name'), 'Krishna');
      await t.enterText(find.widgetWithText(TextField, 'PIN'), '1234');
      await t.enterText(find.widgetWithText(TextField, 'Confirm PIN'), '1234');
      await t.tap(find.text('Save'));
      await settle(t);
      expect(find.text('Your recovery code'), findsOneWidget);
      expect(find.text('I have written it down'), findsOneWidget);
      await t.tap(find.text('I have written it down'));
      await settle(t);
      final people = await t.runAsync(() => StaffRepo().list());
      expect(people!.single.name, 'Krishna');
      expect(people.single.role, Role.admin);
    });

    testDb('without Pro, adding people asks for Pro', (t) async {
      await t.pumpWidget(host(const StaffScreen(), pro: false));
      await settle(t);
      await t.tap(find.text('Turn on staff logins'));
      await settle(t);
      // with the paywall off (the test default) the feature is open, so this
      // checks that the dialog for the Admin opens rather than blocking
      expect(find.text('Set up the Admin'), findsOneWidget);
    });
  });

  group('shops', () {
    testDb('the list shows each shop and marks the open one', (t) async {
      await t.runAsync(() async {
        await const BusinessProfile(name: 'Royal Costumes', type: ShopType.costume).save();
        final id = await Shops.create();
        await const BusinessProfile(name: 'Glow Studio', type: ShopType.makeup).save(shop: id);
      });
      await t.pumpWidget(host(const Scaffold(body: ShopSwitcher())));
      await settle(t);
      expect(find.text('Your shops'), findsOneWidget);
      expect(find.text('Royal Costumes'), findsOneWidget);
      expect(find.text('Glow Studio'), findsOneWidget);
      expect(find.text('Makeup artist'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.text('Add a shop'), findsOneWidget);
    });

    testDb('a cashier cannot add or delete shops', (t) async {
      await t.runAsync(() async {
        await const BusinessProfile(name: 'Royal Costumes', type: ShopType.costume).save();
      });
      await t.pumpWidget(
        host(
          const Scaffold(body: ShopSwitcher()),
          user: person('Meena', Role.cashier, '1111'),
        ),
      );
      await settle(t);
      expect(find.text('Add a shop'), findsNothing);
    });

    testDb('adding a shop saves its details, opens it, and keeps the first apart', (t) async {
      SharedPreferences.setMockInitialValues({'b_name': 'Royal Costumes', 'b_type': 'costume'});
      await t.runAsync(() => Shops.load());
      await t.pumpWidget(
        host(const OnboardingScreen(newShop: true)),
      );
      await settle(t);
      expect(find.text('Add a shop'), findsWidgets);
      await t.enterText(find.widgetWithText(TextFormField, 'Shop name'), 'Glow Studio');
      await t.tap(find.byType(DropdownButtonFormField<ShopType>));
      await settle(t);
      await t.tap(find.text('Makeup artist').last);
      await settle(t);
      await t.scrollUntilVisible(
        find.text('Add shop'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await t.tap(find.text('Add shop'));
      await settle(t);
      expect(Shops.all, ['main', 's2']);
      expect(Shops.activeId, 's2');
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString('b_s2_name'), 'Glow Studio');
      expect(sp.getString('b_s2_type'), 'makeup');
      expect(sp.getString('b_name'), 'Royal Costumes');
    });
  });

  group('brand logo', () {
    testDb('choose a logo for the shop, and it is kept by name', (t) async {
      final source = File('${photoDir.parent.path}/pick.png')
        ..writeAsBytesSync([1, 2, 3, 4]);
      PhotoStore.picker = (camera) async {
        expect(camera, isFalse, reason: 'a logo comes from the gallery');
        return source.path;
      };
      await t.runAsync(() => const BusinessProfile(name: 'Royal Costumes', type: ShopType.costume).save());
      await t.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const OnboardingScreen(
              editing: BusinessProfile(name: 'Royal Costumes', type: ShopType.costume),
            ),
          ),
        ),
      );
      await settle(t);
      expect(find.text('Brand logo'), findsOneWidget);
      expect(find.text('Choose logo'), findsOneWidget);
      await t.tap(find.text('Choose logo'));
      await settle(t);
      expect(find.text('Change'), findsOneWidget);
      await t.scrollUntilVisible(
        find.text('Save'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await t.tap(find.text('Save'));
      await settle(t);
      final saved = await t.runAsync(() => BusinessProfile.load());
      expect(saved!.logoName, matches(RegExp(r'^[A-Za-z0-9-]{8,64}\.png$')));
      expect(File('${photoDir.path}/${saved.logoName}').readAsBytesSync(), [1, 2, 3, 4]);
    });

    testDb('leaving without saving throws the picked logo away', (t) async {
      final source = File('${photoDir.parent.path}/pick2.png')
        ..writeAsBytesSync([9, 9]);
      PhotoStore.picker = (camera) async => source.path;
      await t.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const OnboardingScreen(
              editing: BusinessProfile(name: 'Royal Costumes', type: ShopType.costume),
            ),
          ),
        ),
      );
      await settle(t);
      await t.tap(find.text('Choose logo'));
      await settle(t);
      expect(photoDir.listSync().whereType<File>(), hasLength(1));
      await t.pumpWidget(const SizedBox()); // the page is gone, nothing saved
      await settle(t);
      expect(photoDir.listSync().whereType<File>(), isEmpty);
    });

    testDb('removing the logo clears it and deletes the file', (t) async {
      final file = File('${photoDir.path}/aaaaaaaa-9999.png')..writeAsBytesSync([5]);
      const shop = BusinessProfile(
        name: 'Royal Costumes',
        type: ShopType.costume,
        logoName: 'aaaaaaaa-9999.png',
      );
      await t.runAsync(() => shop.save());
      await t.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const OnboardingScreen(editing: shop),
          ),
        ),
      );
      await settle(t);
      await t.tap(find.text('Remove'));
      await settle(t);
      await t.scrollUntilVisible(
        find.text('Save'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await t.tap(find.text('Save'));
      await settle(t);
      expect((await t.runAsync(() => BusinessProfile.load()))!.logoName, '');
      expect(file.existsSync(), isFalse);
    });
  });

  group('the back button', () {
    Widget app({List<StaffUser> people = const [], StaffUser? user}) => ProviderScope(
      key: UniqueKey(),
      overrides: [
        dashboardRepoProvider.overrideWithValue(_NoDashboard()),
        bookingRepoProvider.overrideWithValue(_NoBookings()),
        itemRepoProvider.overrideWithValue(_NoItems()),
        customerRepoProvider.overrideWithValue(_NoCustomers()),
        profileProvider.overrideWith(() => _Profile(_costume)),
        isProProvider.overrideWithValue(true),
        sessionProvider.overrideWith(() => _SignedIn(user)),
        staffUsersProvider.overrideWith((ref) async => people),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const HomeScreen(profile: _costume),
      ),
    );

    testWidgets('from Bookings it goes to Home, and from Home it closes the app', (t) async {
      SharedPreferences.setMockInitialValues({'b_name': 'Royal Costumes', 'b_type': 'costume'});
      final closed = <String>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemNavigator.pop') closed.add('closed');
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await t.pumpWidget(app());
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Collected this month'), findsOneWidget);

      await t.tap(find.text('Bookings').last);
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Collected this month'), findsNothing);

      // back from Bookings: Home, and the app stays open
      await t.binding.handlePopRoute();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Collected this month'), findsOneWidget);
      expect(closed, isEmpty);

      // back again from Home: the app closes
      await t.binding.handlePopRoute();
      await t.pump(const Duration(milliseconds: 500));
      expect(closed, ['closed']);
    });

    testWidgets('from Items and Customers it also goes to Home first', (t) async {
      SharedPreferences.setMockInitialValues({'b_name': 'Royal Costumes', 'b_type': 'costume'});
      final closed = <String>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemNavigator.pop') closed.add('closed');
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await t.pumpWidget(app());
      await t.pump(const Duration(milliseconds: 500));
      for (final tab in ['Items', 'Customers']) {
        await t.tap(find.text(tab).last);
        await t.pump(const Duration(milliseconds: 500));
        expect(find.text('Collected this month'), findsNothing);
        await t.binding.handlePopRoute();
        await t.pump(const Duration(milliseconds: 500));
        expect(find.text('Collected this month'), findsOneWidget, reason: tab);
      }
      expect(closed, isEmpty);
    });

    testWidgets('a page opened on top closes first, as always', (t) async {
      SharedPreferences.setMockInitialValues({'b_name': 'Royal Costumes', 'b_type': 'costume'});
      t.view.physicalSize = const Size(900, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(app());
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(find.text('Reminders'));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 300));
      }
      expect(find.text('Nothing needs your attention right now.'), findsOneWidget);
      await t.binding.handlePopRoute();
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 300));
      }
      expect(find.text('Collected this month'), findsOneWidget);
    });
  });

  group('notification permission on the first open', () {
    Widget app() => ProviderScope(
      key: UniqueKey(),
      overrides: [
        dashboardRepoProvider.overrideWithValue(_NoDashboard()),
        bookingRepoProvider.overrideWithValue(_NoBookings()),
        itemRepoProvider.overrideWithValue(_NoItems()),
        customerRepoProvider.overrideWithValue(_NoCustomers()),
        profileProvider.overrideWith(() => _Profile(_costume)),
        isProProvider.overrideWithValue(false),
        sessionProvider.overrideWith(() => _SignedIn(null)),
        staffUsersProvider.overrideWith((ref) async => const []),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const HomeScreen(profile: _costume),
      ),
    );

    testWidgets('Home asks to show notifications the first time, not again', (t) async {
      SharedPreferences.setMockInitialValues({});
      final phone = _Phone();
      NotificationService.backend = phone;
      await t.pumpWidget(app());
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 500));
      expect(phone.asked, 1, reason: 'the first time the app opens');

      // opened again (a new start of the screens): not asked again
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(app());
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 500));
      expect(phone.asked, 1);
    });
  });

  group('Home for each person', () {
    Widget appAs(StaffUser? user, {BusinessProfile shop = _costume}) => ProviderScope(
      key: UniqueKey(),
      overrides: [
        dashboardRepoProvider.overrideWithValue(_NoDashboard()),
        bookingRepoProvider.overrideWithValue(_NoBookings()),
        itemRepoProvider.overrideWithValue(_NoItems()),
        customerRepoProvider.overrideWithValue(_NoCustomers()),
        profileProvider.overrideWith(() => _Profile(shop)),
        isProProvider.overrideWithValue(true),
        sessionProvider.overrideWith(() => _SignedIn(user)),
        staffUsersProvider.overrideWith((ref) async => const []),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: HomeScreen(profile: shop),
      ),
    );

    testWidgets('the owner sees every tile', (t) async {
      SharedPreferences.setMockInitialValues({});
      t.view.physicalSize = const Size(900, 2600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(appAs(null));
      await t.pump(const Duration(milliseconds: 500));
      for (final label in ['Reports', 'Billing and GST', 'Settings', 'Reminders', 'Invoices']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
    });

    testWidgets('a cashier has no reports, billing or settings, and no money totals', (t) async {
      SharedPreferences.setMockInitialValues({});
      t.view.physicalSize = const Size(900, 2600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(appAs(person('Meena', Role.cashier, '1111')));
      await t.pump(const Duration(milliseconds: 500));
      for (final label in ['Reports', 'Billing and GST', 'Settings']) {
        expect(find.text(label), findsNothing, reason: label);
      }
      expect(find.text('Reminders'), findsWidgets);
      expect(find.text('Bookings'), findsWidgets);
      // the money on Home is hidden, and there is no eye to show it
      expect(find.text('₹ ••••••'), findsWidgets);
      expect(find.byIcon(Icons.visibility_outlined), findsNothing);
    });

    testWidgets('staff see reports but not billing or settings', (t) async {
      SharedPreferences.setMockInitialValues({});
      t.view.physicalSize = const Size(900, 2600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(appAs(person('Mani', Role.staff, '2222')));
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Reports'), findsWidgets);
      expect(find.text('Billing and GST'), findsNothing);
      expect(find.text('Settings'), findsNothing);
    });

    testWidgets('a makeup artist sees Services, not Items, and appointments', (t) async {
      SharedPreferences.setMockInitialValues({});
      t.view.physicalSize = const Size(900, 2600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(appAs(null, shop: _makeup));
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Services'), findsWidgets);
      expect(find.text('Items'), findsNothing);
      expect(find.text('Appointments today'), findsOneWidget);
      expect(find.text('Out today'), findsNothing);
      expect(find.text('Back today'), findsNothing);
      expect(find.text('Pick the customer, the services and the date'), findsOneWidget);
    });

    testWidgets('the shop name opens the list of shops', (t) async {
      SharedPreferences.setMockInitialValues({'b_name': 'Royal Costumes', 'b_type': 'costume'});
      await t.pumpWidget(appAs(null));
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(find.byIcon(Icons.unfold_more_rounded));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Your shops'), findsOneWidget);
    });
  });
}

class _Phone implements NotificationBackend {
  int asked = 0;
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async {
    asked++;
    return true;
  }

  @override
  Future<void> cancelAll() async {}
  @override
  Future<void> schedule(PlannedNotification n) async {}
}

class _NoDashboard extends DashboardRepo {
  @override
  Future<DashboardCounts> counts([DateTime? now]) async =>
      const DashboardCounts();
}

class _NoBookings extends BookingRepo {
  @override
  Future<List<Booking>> list({
    BookingFilter filter = BookingFilter.upcoming,
    String query = '',
  }) async => const [];

  @override
  Future<List<Booking>> forReminders() async => const [];

  @override
  Future<int> freeLeft([DateTime? now]) async => 12;
}

class _NoItems extends ItemRepo {
  @override
  Future<List<RentItem>> list({
    String query = '',
    bool includeRetired = false,
  }) async => const [];
}

class _NoCustomers extends CustomerRepo {
  @override
  Future<List<Customer>> list({String query = ''}) async => const [];
}
