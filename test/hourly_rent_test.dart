import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/core/booking_math.dart';
import 'package:gellsoft_rentpro/data/booking_repo.dart';
import 'package:gellsoft_rentpro/data/database.dart';
import 'package:gellsoft_rentpro/data/notifications.dart';
import 'package:gellsoft_rentpro/data/reminders.dart';
import 'package:gellsoft_rentpro/data/invoice_repo.dart';
import 'package:gellsoft_rentpro/data/models.dart';
import 'package:gellsoft_rentpro/data/repositories.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DateTime day(int d) => DateTime(2027, 3, d);

void main() {
  late Directory dir;
  final bookings = BookingRepo();
  final items = ItemRepo();
  final customers = CustomerRepo();
  late int anu, bala;
  late int court; // 500 an hour
  late int gown; // 1000 a day
  late int hall; // 2 pieces, 300 an hour

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('rentpro_hourly');
    AppDatabase.pathOverride = '${dir.path}/test.db';
    anu = await customers.save(
      Customer(name: 'Anu', phone: '9000000001', createdAt: DateTime(2027)),
    );
    bala = await customers.save(
      Customer(name: 'Bala', phone: '9000000002', createdAt: DateTime(2027)),
    );
    court = await items.save(
      RentItem(
        name: 'Court',
        rate: 500,
        rateType: RateType.hour,
        createdAt: DateTime(2027),
      ),
    );
    gown = await items.save(
      RentItem(
        name: 'Gown',
        rate: 1000,
        rateType: RateType.day,
        createdAt: DateTime(2027),
      ),
    );
    hall = await items.save(
      RentItem(
        name: 'Hall',
        rate: 300,
        rateType: RateType.hour,
        quantity: 2,
        createdAt: DateTime(2027),
      ),
    );
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    AppDatabase.pathOverride = null;
    await dir.delete(recursive: true);
  });

  Future<int> make({
    int? customer,
    List<int>? ids,
    int d = 10,
    int? retDay,
    String from = '10:00',
    String to = '12:00',
    Map<int, int> qty = const {},
  }) => bookings.create(
    BookingDraft(
      customerId: customer ?? anu,
      eventDate: day(d),
      pickupDate: day(d),
      returnDate: day(retDay ?? d),
      itemIds: ids ?? [court],
      quantities: qty,
      pickupTime: from,
      returnTime: to,
    ),
    isPro: true,
    now: day(1),
  );

  Future<void> expectError(Future<Object?> f, BookingError e) async {
    try {
      await f;
      fail('expected $e');
    } on BookingException catch (x) {
      expect(x.error, e);
    }
  }

  group('hours and price', () {
    test('a started hour counts as a whole hour, and one hour is the least', () {
      int h(String a, String b) => rentalHours(day(10), a, day(10), b);
      expect(h('10:00', '12:00'), 2);
      expect(h('10:00', '12:10'), 3);
      expect(h('10:00', '10:20'), 1);
      expect(h('10:00', '10:00'), 1);
      expect(rentalHours(day(10), '22:00', day(11), '02:30'), 5);
    });

    test('times are checked', () {
      expect(validHourlySpan(day(10), '10:00', day(10), '12:00'), isTrue);
      expect(validHourlySpan(day(10), '12:00', day(10), '10:00'), isFalse);
      expect(validHourlySpan(day(10), '10:00', day(10), '10:00'), isFalse);
      expect(validHourlySpan(day(10), '', day(10), '12:00'), isFalse);
      expect(validHourlySpan(day(10), '10:00', day(11), '09:00'), isTrue);
      expect(minutesOfTime('25:00'), isNull);
      expect(minutesOfTime('9:5'), 9 * 60 + 5);
    });

    test('the rent is the hourly rate times the hours', () async {
      final id = await make(from: '10:00', to: '12:30'); // 3 hours
      final b = (await bookings.get(id))!;
      expect(b.rentTotal, 1500);
      expect(b.lines.single.amount, 1500);
      expect(b.pickupTime, '10:00');
      expect(b.returnTime, '12:30');
      expect(b.hasHourly, isTrue);
      expect(b.hours, 3);
    });

    test('quantity multiplies the hourly rent', () async {
      final id = await make(ids: [hall], qty: {hall: 2}); // 2 h x 300 x 2
      expect((await bookings.get(id))!.rentTotal, 1200);
    });

    test('a booking by the day keeps no times and is priced as before', () async {
      final id = await bookings.create(
        BookingDraft(
          customerId: anu,
          eventDate: day(10),
          pickupDate: day(9),
          returnDate: day(11),
          itemIds: [gown],
          pickupTime: '10:00',
          returnTime: '12:00',
        ),
        isPro: true,
        now: day(1),
      );
      final b = (await bookings.get(id))!;
      expect(b.rentTotal, 3000);
      expect(b.pickupTime, '');
      expect(b.returnTime, '');
      expect(b.hasHourly, isFalse);
    });

    test('a day item and an hourly item on one booking each price their own way',
        () async {
      final id = await make(
        ids: [court, gown],
        d: 10,
        from: '09:00',
        to: '11:00',
      );
      final b = (await bookings.get(id))!;
      final byName = {for (final l in b.lines) l.name: l.amount};
      expect(byName['Court'], 1000); // 2 hours
      expect(byName['Gown'], 1000); // one day
      expect(b.rentTotal, 2000);
    });

    test('an hourly item needs both times, the return after the pickup', () async {
      await expectError(make(from: '', to: '12:00'), BookingError.badTimes);
      await expectError(make(from: '10:00', to: ''), BookingError.badTimes);
      await expectError(make(from: '12:00', to: '10:00'), BookingError.badTimes);
      await expectError(make(from: '10:00', to: '10:00'), BookingError.badTimes);
    });

    test('editing keeps the times and prices the new hours', () async {
      final id = await make(from: '10:00', to: '12:00');
      await bookings.update(
        id,
        BookingDraft(
          customerId: anu,
          eventDate: day(10),
          pickupDate: day(10),
          returnDate: day(10),
          itemIds: [court],
          pickupTime: '10:00',
          returnTime: '14:00',
        ),
        now: day(1),
      );
      final b = (await bookings.get(id))!;
      expect(b.returnTime, '14:00');
      expect(b.rentTotal, 2000);
    });
  });

  group('availability by the hour', () {
    test('two bookings of one item on the same day, at different hours', () async {
      await make(from: '10:00', to: '12:00');
      // after it: fine, and back to back is fine too
      await make(customer: bala, from: '12:00', to: '14:00');
      await make(from: '15:00', to: '16:00');
    });

    test('overlapping hours clash and say who has it', () async {
      final first = await make(from: '10:00', to: '12:00');
      await expectError(
        make(customer: bala, from: '11:00', to: '13:00'),
        BookingError.itemBusy,
      );
      final clash = await bookings.conflicts(
        itemIds: [court],
        pickup: day(10),
        ret: day(10),
        pickupTime: '09:00',
        returnTime: '10:30',
      );
      expect(clash[court]!.bookingId, first);
      expect(clash[court]!.pickupTime, '10:00');
      expect(clash[court]!.returnTime, '12:00');
    });

    test('a different day is free', () async {
      await make(from: '10:00', to: '12:00');
      await make(d: 11, from: '10:00', to: '12:00');
    });

    test('pieces are counted at each hour', () async {
      await make(ids: [hall], from: '10:00', to: '12:00');
      await make(customer: bala, ids: [hall], from: '11:00', to: '13:00');
      // both are in between 11 and 12: no piece is left
      await expectError(
        make(ids: [hall], from: '11:30', to: '12:30'),
        BookingError.notEnough,
      );
      final a = (await bookings.availability(
        itemIds: [hall],
        pickup: day(10),
        ret: day(10),
        pickupTime: '12:00',
        returnTime: '13:00',
      ))[hall]!;
      expect(a.free, 1); // only the second booking is still on at noon
    });

    test('an item by the day blocks the whole day for another booking by the day',
        () async {
      await bookings.create(
        BookingDraft(
          customerId: anu,
          eventDate: day(10),
          pickupDate: day(10),
          returnDate: day(10),
          itemIds: [gown],
        ),
        isPro: true,
        now: day(1),
      );
      await expectError(
        bookings.create(
          BookingDraft(
            customerId: bala,
            eventDate: day(10),
            pickupDate: day(10),
            returnDate: day(10),
            itemIds: [gown],
          ),
          isPro: true,
          now: day(1),
        ),
        BookingError.itemBusy,
      );
    });

    test('a booking that is out and past its return time keeps the item', () async {
      final id = await make(from: '10:00', to: '12:00');
      await bookings.markPickedUp(id, now: day(10));
      // later the same day, after the return time: still held
      await expectError(
        bookings.create(
          BookingDraft(
            customerId: bala,
            eventDate: day(10),
            pickupDate: day(10),
            returnDate: day(10),
            itemIds: [court],
            pickupTime: '15:00',
            returnTime: '16:00',
          ),
          isPro: true,
          now: DateTime(2027, 3, 10, 14),
        ),
        BookingError.itemBusy,
      );
    });
  });

  group('late by the hour', () {
    test('overdue as soon as the return time has passed', () async {
      final id = await make(from: '10:00', to: '12:00');
      await bookings.markPickedUp(id, now: day(10));
      final b = (await bookings.get(id))!;
      expect(b.isOverdue(day(10), DateTime(2027, 3, 10, 11, 59)), isFalse);
      expect(b.isOverdue(day(10), DateTime(2027, 3, 10, 12, 1)), isTrue);
      expect(b.dueBack, DateTime(2027, 3, 10, 12));
    });

    test('a booking by the day is late only after its return day', () async {
      final id = await bookings.create(
        BookingDraft(
          customerId: anu,
          eventDate: day(10),
          pickupDate: day(9),
          returnDate: day(11),
          itemIds: [gown],
        ),
        isPro: true,
        now: day(1),
      );
      await bookings.markPickedUp(id, now: day(9));
      final b = (await bookings.get(id))!;
      expect(b.isOverdue(day(11), DateTime(2027, 3, 11, 23)), isFalse);
      expect(b.isOverdue(day(12), DateTime(2027, 3, 12, 1)), isTrue);
    });
  });

  group('invoice', () {
    test('an hourly line carries its hours', () async {
      final id = await make(from: '10:00', to: '12:30');
      final inv = await InvoiceRepo().createForBooking(
        id,
        shopStateCode: '33',
        prefix: 'RP',
        gstEnabled: false,
        taxInclusive: false,
        now: day(10),
      );
      final line = (await InvoiceRepo().get(inv))!.lines.single;
      expect(line.rateType, RateType.hour);
      expect(line.days, 3);
      expect(line.total, 1500);
    });
  });

  group('minimum hours', () {
    test('a short use is charged for the item minimum', () async {
      final studio = await items.save(
        RentItem(
          name: 'Studio',
          rate: 100,
          rateType: RateType.hour,
          minHours: 3,
          createdAt: DateTime(2027),
        ),
      );
      expect((await items.get(studio))!.minHours, 3);
      final id = await make(ids: [studio], from: '10:00', to: '11:00');
      final b = (await bookings.get(id))!;
      expect(b.lines.single.hours, 3);
      expect(b.rentTotal, 300);
      // a longer booking is charged for the longer time
      final long = await make(
        customer: bala,
        ids: [studio],
        d: 11,
        from: '10:00',
        to: '15:00',
      );
      expect((await bookings.get(long))!.rentTotal, 500);
      final inv = await InvoiceRepo().createForBooking(
        id,
        shopStateCode: '33',
        prefix: 'RP',
        gstEnabled: false,
        taxInclusive: false,
        now: day(10),
      );
      expect((await InvoiceRepo().get(inv))!.lines.single.days, 3);
    });

    test('the minimum is kept when the item is saved again', () async {
      final id = await items.save(
        RentItem(
          name: 'Cam',
          rate: 50,
          rateType: RateType.hour,
          minHours: 2,
          createdAt: DateTime(2027),
        ),
      );
      final it = (await items.get(id))!;
      await items.save(it.copyWith(rate: 60));
      expect((await items.get(id))!.minHours, 2);
      await items.save(it.copyWith(minHours: 0));
      expect((await items.get(id))!.minHours, 1);
    });
  });

  group('reminders by the hour', () {
    test('overdue the moment the return time passes, not at midnight', () async {
      final id = await make(from: '10:00', to: '12:00');
      await bookings.markPickedUp(id, now: day(10));
      final b = (await bookings.get(id))!;
      ReminderKind? kind(DateTime now) {
        final r = buildReminders([b], now);
        return r.isEmpty ? null : r.first.kind;
      }

      expect(kind(DateTime(2027, 3, 10, 11)), ReminderKind.returnDue);
      expect(kind(DateTime(2027, 3, 10, 13)), ReminderKind.overdue);
      // a booking by the day is still only due back on its return day
      final dayId = await bookings.create(
        BookingDraft(
          customerId: bala,
          eventDate: day(10),
          pickupDate: day(10),
          returnDate: day(10),
          itemIds: [gown],
        ),
        isPro: true,
        now: day(1),
      );
      await bookings.markPickedUp(dayId, now: day(10));
      final d = (await bookings.get(dayId))!;
      expect(
        buildReminders([d], DateTime(2027, 3, 10, 23)).first.kind,
        ReminderKind.returnDue,
      );
    });

    test('notifications at the pickup and return times of an hourly booking',
        () async {
      final id = await make(from: '10:00', to: '12:00');
      final b = (await bookings.get(id))!;
      final plan = planNotifications(
        bookings: [b],
        settings: const NotifySettings(daily: false),
        now: DateTime(2027, 3, 9, 20),
      );
      final times = plan.map((n) => n.at).toList();
      // an hour before the items go out, 15 minutes before they are due back
      expect(times, contains(DateTime(2027, 3, 10, 9)));
      expect(times, contains(DateTime(2027, 3, 10, 11, 45)));
      // and no reminder at the usual morning time for the return
      expect(times, isNot(contains(DateTime(2027, 3, 10, 8))));
    });
  });

  group('a phone that already had an early version 7 file', () {
    test('gets the missing hour columns and can book by the hour', () async {
      // make the file as the first version 7 did: no min_hours, no hours
      final d = await AppDatabase.instance.db;
      await d.execute('ALTER TABLE items DROP COLUMN min_hours');
      await d.execute('ALTER TABLE booking_items DROP COLUMN hours');
      await d.execute('PRAGMA user_version = 7');
      await AppDatabase.instance.close();

      // opening it again runs the upgrade from 7
      final again = await AppDatabase.instance.db;
      final items0 = (await again.rawQuery('PRAGMA table_info(items)'))
          .map((r) => r['name']);
      final lines0 = (await again.rawQuery('PRAGMA table_info(booking_items)'))
          .map((r) => r['name']);
      expect(items0, contains('min_hours'));
      expect(lines0, contains('hours'));
      expect(
        (await again.rawQuery('PRAGMA user_version')).first.values.first,
        AppDatabase.schemaVersion,
      );

      final id = await make(from: '10:00', to: '12:00');
      final b = (await bookings.get(id))!;
      expect(b.rentTotal, 1000);
      expect(b.lines.single.hours, 2);
    });
  });
}
