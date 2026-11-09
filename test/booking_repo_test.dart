import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/core/booking_math.dart';
import 'package:gellsoft_rentpro/data/booking_models.dart';
import 'package:gellsoft_rentpro/data/booking_repo.dart';
import 'package:gellsoft_rentpro/data/database.dart';
import 'package:gellsoft_rentpro/data/models.dart';
import 'package:gellsoft_rentpro/data/repositories.dart';
import 'package:gellsoft_rentpro/subscription/plan.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DateTime day(int d) => DateTime(2027, 3, d);

void main() {
  late Directory dir;
  final bookings = BookingRepo();
  final items = ItemRepo();
  final customers = CustomerRepo();
  late int anu, bala;
  late int sherwani, gown, tent;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('rentpro_booking');
    AppDatabase.pathOverride = '${dir.path}/test.db';
    anu = await customers.save(Customer(name: 'Anu', phone: '9000000001', createdAt: DateTime(2027)));
    bala = await customers.save(Customer(name: 'Bala', phone: '9000000002', createdAt: DateTime(2027)));
    sherwani = await items.save(RentItem(name: 'Sherwani', rate: 2000, deposit: 3000, createdAt: DateTime(2027)));
    gown = await items.save(RentItem(name: 'Gown', rate: 500, rateType: RateType.day, deposit: 1000, createdAt: DateTime(2027)));
    tent = await items.save(RentItem(name: 'Tent', rate: 800, createdAt: DateTime(2027)));
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    AppDatabase.pathOverride = null;
    await dir.delete(recursive: true);
  });

  BookingDraft draft({
    int? customer,
    List<int>? itemIds,
    int pickup = 9,
    int event = 10,
    int ret = 11,
    double discount = 0,
  }) => BookingDraft(
    customerId: customer ?? anu,
    eventDate: day(event),
    pickupDate: day(pickup),
    returnDate: day(ret),
    itemIds: itemIds ?? [sherwani],
    discount: discount,
  );

  Future<int> make(BookingDraft d, {bool pro = false, double advance = 0, DateTime? now}) =>
      bookings.create(d, isPro: pro, advance: advance, now: now ?? day(1));

  Future<void> expectError(Future<Object?> f, BookingError e) async {
    try {
      await f;
      fail('expected $e');
    } on BookingException catch (x) {
      expect(x.error, e);
    }
  }

  group('maths', () {
    test('days count both ends', () {
      expect(rentalDays(day(9), day(9)), 1);
      expect(rentalDays(day(9), day(11)), 3);
      expect(rentalDays(day(31), DateTime(2027, 4, 2)), 3, reason: 'across a month');
      expect(rentalDays(day(11), day(9)), 1, reason: 'never below one day');
    });

    test('event rate is flat, day rate multiplies', () {
      expect(lineAmount(RateType.event, 2000, day(9), day(12)), 2000);
      expect(lineAmount(RateType.day, 500, day(9), day(12)), 2000);
    });

    test('ranges overlap on a shared day only', () {
      expect(rangesOverlap(day(9), day(11), day(11), day(12)), isTrue);
      expect(rangesOverlap(day(9), day(10), day(11), day(12)), isFalse);
      expect(rangesOverlap(day(9), day(20), day(12), day(13)), isTrue);
    });
  });

  group('creating', () {
    test('saves the lines, totals and a first number of 1', () async {
      final id = await make(draft(itemIds: [sherwani, gown, tent]));
      final b = (await bookings.get(id))!;
      expect(b.number, 1);
      expect(b.status, BookingStatus.booked);
      expect(b.customerName, 'Anu');
      expect(b.lines.length, 3);
      // sherwani flat 2000 + gown 500 x 3 days + tent flat 800
      expect(b.rentTotal, 2000 + 1500 + 800);
      expect(b.depositTotal, 4000);
      expect(b.balanceDue, 4300);
      expect(b.lines.firstWhere((l) => l.name == 'Gown').amount, 1500);
      expect(b.remindDays, 2);
    });

    test('numbers go up by one', () async {
      await make(draft());
      final id = await make(draft(itemIds: [tent], pickup: 20, event: 21, ret: 22));
      expect((await bookings.get(id))!.number, 2);
    });

    test('an advance becomes a payment and lowers the balance', () async {
      final id = await make(draft(discount: 200), advance: 500);
      final b = (await bookings.get(id))!;
      expect(b.payments.single.kind, PaymentKind.advance);
      expect(b.rentNet, 1800);
      expect(b.rentPaid, 500);
      expect(b.balanceDue, 1300);
    });

    test('refuses an advance larger than the rent', () async {
      await expectError(make(draft(), advance: 5000), BookingError.badAmount);
    });

    test('refuses bad dates, no items, bad discount', () async {
      await expectError(make(draft(pickup: 11, event: 10, ret: 12)), BookingError.badDates);
      await expectError(make(draft(pickup: 9, event: 12, ret: 11)), BookingError.badDates);
      await expectError(make(draft(itemIds: [])), BookingError.noItems);
      await expectError(make(draft(discount: 99999)), BookingError.badDiscount);
      await expectError(make(draft(discount: -1)), BookingError.badDiscount);
      expect(await bookings.createdInMonth(day(1)), 0, reason: 'nothing half-saved');
    });

    test('an item in repair, retired or removed cannot be booked', () async {
      await items.setStatus(sherwani, ItemStatus.repair);
      await expectError(make(draft()), BookingError.itemUnavailable);
      await items.setStatus(sherwani, ItemStatus.retired);
      await expectError(make(draft()), BookingError.itemUnavailable);
      await items.setStatus(sherwani, ItemStatus.active);
      await items.delete(sherwani);
      await expectError(make(draft()), BookingError.itemUnavailable);
    });

    test('the booking keeps the rate it was made at', () async {
      final id = await make(draft());
      final it = (await items.get(sherwani))!;
      await items.save(it.copyWith(rate: 9999, name: 'Renamed'));
      final b = (await bookings.get(id))!;
      expect(b.lines.single.name, 'Sherwani');
      expect(b.lines.single.rate, 2000);
      expect(b.rentTotal, 2000);
    });
  });

  group('free limit', () {
    Future<void> fill(int n, {DateTime? now}) async {
      for (var i = 0; i < n; i++) {
        final it = await items.save(RentItem(name: 'x$i${now ?? ''}', rate: 100, createdAt: DateTime(2027)));
        await make(draft(itemIds: [it]), now: now);
      }
    }

    test('stops at the monthly limit, Pro does not', () async {
      await fill(FreePlan.bookingsPerMonth);
      expect(await bookings.createdInMonth(day(1)), FreePlan.bookingsPerMonth);
      expect(await bookings.freeLeft(day(1)), 0);
      await expectError(make(draft(itemIds: [tent])), BookingError.limitReached);
      final id = await make(draft(itemIds: [tent]), pro: true);
      expect((await bookings.get(id))!.number, FreePlan.bookingsPerMonth + 1);
    });

    test('a cancelled booking still used its place', () async {
      await fill(FreePlan.bookingsPerMonth - 1);
      final id = await make(draft(itemIds: [tent]));
      await bookings.cancel(id);
      expect(await bookings.freeLeft(day(1)), 0);
      await expectError(make(draft(itemIds: [tent], pickup: 20, event: 21, ret: 22)), BookingError.limitReached);
    });

    test('a new month starts fresh', () async {
      await fill(FreePlan.bookingsPerMonth);
      final april = DateTime(2027, 4, 1);
      expect(await bookings.freeLeft(april), FreePlan.bookingsPerMonth);
      final id = await bookings.create(
        BookingDraft(
          customerId: anu,
          eventDate: DateTime(2027, 4, 10),
          pickupDate: DateTime(2027, 4, 9),
          returnDate: DateTime(2027, 4, 11),
          itemIds: [tent],
        ),
        isPro: false,
        now: april,
      );
      expect(id, greaterThan(0));
    });

    test('editing never uses another place', () async {
      await fill(FreePlan.bookingsPerMonth - 1);
      final id = await make(draft(itemIds: [tent]));
      await bookings.update(id, draft(itemIds: [tent], discount: 100), now: day(1));
      expect(await bookings.createdInMonth(day(1)), FreePlan.bookingsPerMonth);
    });
  });

  group('availability', () {
    test('the same item on overlapping days is refused, naming the item', () async {
      await make(draft(pickup: 9, event: 10, ret: 11));
      try {
        await make(draft(customer: bala, pickup: 11, event: 11, ret: 12));
        fail('should clash on the 11th');
      } on BookingException catch (e) {
        expect(e.error, BookingError.itemBusy);
        expect(e.detail, 'Sherwani');
      }
    });

    test('the day after the return is free', () async {
      await make(draft(pickup: 9, event: 10, ret: 11));
      final id = await make(draft(customer: bala, pickup: 12, event: 12, ret: 13));
      expect(id, greaterThan(0));
    });

    test('another item on the same days is fine', () async {
      await make(draft());
      expect(await make(draft(itemIds: [tent])), greaterThan(0));
    });

    test('cancelled and returned bookings free the item', () async {
      final a = await make(draft());
      await bookings.cancel(a);
      final b = await make(draft(customer: bala));
      await bookings.markPickedUp(b);
      await bookings.markReturned(b);
      expect(await make(draft()), greaterThan(0));
    });

    test('conflicts() reports who has it and when', () async {
      final a = await make(draft(pickup: 9, event: 10, ret: 11));
      final c = await bookings.conflicts(
        itemIds: [sherwani, tent],
        pickup: day(10),
        ret: day(12),
        now: day(1),
      );
      expect(c.keys, [sherwani]);
      expect(c[sherwani]!.bookingId, a);
      expect(c[sherwani]!.customerName, 'Anu');
      expect(c[sherwani]!.bookingNumber, 1);
    });

    test('a late item that is still out stays taken until it is back', () async {
      final a = await make(draft(pickup: 5, event: 6, ret: 7));
      await bookings.markPickedUp(a);
      // today is the 20th and it has not come back
      final c = await bookings.conflicts(
        itemIds: [sherwani],
        pickup: day(18),
        ret: day(19),
        now: day(20),
      );
      expect(c, isNotEmpty);
      await bookings.markReturned(a);
      final after = await bookings.conflicts(
        itemIds: [sherwani],
        pickup: day(18),
        ret: day(19),
        now: day(20),
      );
      expect(after, isEmpty);
    });
  });

  group('changing a booking', () {
    test('its own dates and items are not a clash with itself', () async {
      final id = await make(draft(pickup: 9, event: 10, ret: 11));
      await bookings.update(
        id,
        draft(itemIds: [sherwani, tent], pickup: 9, event: 10, ret: 12),
        now: day(1),
      );
      final b = (await bookings.get(id))!;
      expect(b.lines.length, 2);
      expect(b.returnDate, day(12));
      expect(b.rentTotal, 2800);
      expect(b.number, 1, reason: 'number never changes');
    });

    test('moving onto another booking is refused', () async {
      await make(draft(pickup: 9, event: 10, ret: 11));
      final other = await make(draft(pickup: 20, event: 21, ret: 22));
      await expectError(
        bookings.update(other, draft(pickup: 10, event: 10, ret: 12), now: day(1)),
        BookingError.itemBusy,
      );
      expect((await bookings.get(other))!.pickupDate, day(20), reason: 'unchanged');
    });

    test('payments stay when the rent changes', () async {
      final id = await make(draft(), advance: 1000);
      await bookings.update(id, draft(itemIds: [sherwani, tent]), now: day(1));
      final b = (await bookings.get(id))!;
      expect(b.rentPaid, 1000);
      expect(b.balanceDue, 1800);
    });

    test('a returned or cancelled booking cannot be changed', () async {
      final a = await make(draft());
      await bookings.cancel(a);
      await expectError(bookings.update(a, draft(discount: 1)), BookingError.badState);
    });
  });

  group('status', () {
    test('booked then picked up then returned', () async {
      final id = await make(draft());
      await bookings.markPickedUp(id);
      expect((await bookings.get(id))!.status, BookingStatus.pickedUp);
      await bookings.markReturned(id);
      expect((await bookings.get(id))!.status, BookingStatus.returned);
    });

    test('moves out of order are refused', () async {
      final id = await make(draft());
      await expectError(bookings.markReturned(id), BookingError.badState);
      await bookings.markPickedUp(id);
      await expectError(bookings.markPickedUp(id), BookingError.badState);
      await expectError(bookings.cancel(id), BookingError.badState);
      await bookings.markReturned(id);
      await expectError(bookings.cancel(id), BookingError.badState);
    });

    test('overdue means out and past the return day', () async {
      final id = await make(draft(pickup: 9, event: 10, ret: 11));
      await bookings.markPickedUp(id);
      final b = (await bookings.get(id))!;
      expect(b.isOverdue(day(11)), isFalse);
      expect(b.isOverdue(day(12)), isTrue);
    });
  });

  group('payments', () {
    test('advance then balance clears the rent', () async {
      final id = await make(draft(itemIds: [sherwani, tent]));
      await bookings.addPayment(id, kind: PaymentKind.advance, amount: 1000, mode: PayMode.upi);
      await bookings.addPayment(id, kind: PaymentKind.balance, amount: 1800);
      final b = (await bookings.get(id))!;
      expect(b.balanceDue, 0);
      expect(b.payments.length, 2);
      expect(b.payments.first.mode, PayMode.upi);
    });

    test('cannot pay more rent than is due, or nothing', () async {
      final id = await make(draft());
      await expectError(
        bookings.addPayment(id, kind: PaymentKind.balance, amount: 2001),
        BookingError.badAmount,
      );
      await expectError(
        bookings.addPayment(id, kind: PaymentKind.balance, amount: 0),
        BookingError.badAmount,
      );
    });

    test('deposit is taken up to what is due and refunded up to what is held', () async {
      final id = await make(draft());
      await bookings.addPayment(id, kind: PaymentKind.deposit, amount: 2000);
      var b = (await bookings.get(id))!;
      expect(b.depositHeld, 2000);
      expect(b.depositDue, 1000);
      await expectError(
        bookings.addPayment(id, kind: PaymentKind.deposit, amount: 1001),
        BookingError.badAmount,
      );
      await bookings.addPayment(id, kind: PaymentKind.deposit, amount: 1000);
      await expectError(
        bookings.addPayment(id, kind: PaymentKind.refund, amount: 3001),
        BookingError.badAmount,
      );
      await bookings.addPayment(id, kind: PaymentKind.refund, amount: 2500, note: 'one stain');
      b = (await bookings.get(id))!;
      expect(b.depositHeld, 500);
      expect(b.depositRefunded, 2500);
      expect(b.rentPaid, 0, reason: 'a deposit is not rent');
    });

    test('a cancelled booking only takes refunds', () async {
      final id = await make(draft(), advance: 500);
      await bookings.addPayment(id, kind: PaymentKind.deposit, amount: 3000);
      await bookings.cancel(id);
      await expectError(
        bookings.addPayment(id, kind: PaymentKind.balance, amount: 100),
        BookingError.badState,
      );
      await bookings.addPayment(id, kind: PaymentKind.refund, amount: 3000);
      expect((await bookings.get(id))!.depositHeld, 0);
    });
  });

  group('photos', () {
    test('the free plan keeps two, Pro keeps more', () async {
      final id = await make(draft());
      await bookings.addPhoto(id, path: 'a.jpg', stage: 'pickup', isPro: false);
      await bookings.addPhoto(id, path: 'b.jpg', stage: 'return', isPro: false);
      await expectError(
        bookings.addPhoto(id, path: 'c.jpg', stage: 'other', isPro: false),
        BookingError.limitReached,
      );
      await bookings.addPhoto(id, path: 'c.jpg', stage: 'other', isPro: true);
      final b = (await bookings.get(id))!;
      expect(b.photos.map((p) => p.path), ['a.jpg', 'b.jpg', 'c.jpg']);
      await bookings.removePhoto(b.photos.first.id);
      expect((await bookings.get(id))!.photos.length, 2);
    });

    test('the limit is per booking', () async {
      final a = await make(draft());
      final b = await make(draft(itemIds: [tent]));
      for (final id in [a, b]) {
        await bookings.addPhoto(id, path: 'x$id.jpg', stage: 'pickup', isPro: false);
        await bookings.addPhoto(id, path: 'y$id.jpg', stage: 'pickup', isPro: false);
      }
      expect((await bookings.get(b))!.photos.length, 2);
    });
  });

  group('listing', () {
    test('filters by status and orders by pickup', () async {
      final late = await make(draft(pickup: 20, event: 21, ret: 22));
      final soon = await make(draft(itemIds: [tent], pickup: 12, event: 13, ret: 14));
      final out = await make(draft(itemIds: [gown], pickup: 5, event: 6, ret: 7));
      await bookings.markPickedUp(out);
      expect((await bookings.list()).map((b) => b.id), [soon, late]);
      expect((await bookings.list(filter: BookingFilter.out)).map((b) => b.id), [out]);
      expect(await bookings.list(filter: BookingFilter.returned), isEmpty);
    });

    test('search by name, phone and number', () async {
      final a = await make(draft(customer: anu));
      final b = await make(draft(customer: bala, itemIds: [tent]));
      expect((await bookings.list(query: 'anu')).map((x) => x.id), [a]);
      expect((await bookings.list(query: '0002')).map((x) => x.id), [b]);
      expect((await bookings.list(query: '#2')).map((x) => x.id), [b]);
      expect((await bookings.list(query: '2')).map((x) => x.id), [b]);
      expect(await bookings.list(query: 'zzz'), isEmpty);
    });

    test('a removed customer does not hide their booking', () async {
      final id = await make(draft());
      await customers.delete(anu);
      expect((await bookings.get(id))!.customerName, 'Anu');
    });
  });
}
