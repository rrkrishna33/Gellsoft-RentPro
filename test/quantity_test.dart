import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/core/booking_math.dart';
import 'package:gellsoft_rentpro/data/booking_models.dart';
import 'package:gellsoft_rentpro/data/booking_repo.dart';
import 'package:gellsoft_rentpro/data/csv_export.dart';
import 'package:gellsoft_rentpro/data/database.dart';
import 'package:gellsoft_rentpro/data/invoice_repo.dart';
import 'package:gellsoft_rentpro/data/models.dart';
import 'package:gellsoft_rentpro/data/repositories.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DateTime day(int d) => DateTime(2027, 3, d);

/// An item can have many pieces ("Chair", 10): bookings take some of them, and
/// only what is still free on every day can be booked.
void main() {
  late Directory dir;
  final bookings = BookingRepo();
  final items = ItemRepo();
  late int anu, bala;
  late int chair; // 10 pieces, 50 a piece for the event
  late int lamp; // 4 pieces, 100 a day, 200 deposit each
  late int single; // one piece

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('rentpro_qty');
    AppDatabase.pathOverride = '${dir.path}/test.db';
    final customers = CustomerRepo();
    anu = await customers.save(Customer(name: 'Anu', phone: '9000000001', createdAt: DateTime(2027)));
    bala = await customers.save(Customer(name: 'Bala', phone: '9000000002', createdAt: DateTime(2027)));
    chair = await items.save(RentItem(name: 'Chair', rate: 50, quantity: 10, gstRate: 18, createdAt: DateTime(2027)));
    lamp = await items.save(RentItem(
      name: 'Lamp',
      rate: 100,
      rateType: RateType.day,
      deposit: 200,
      quantity: 4,
      createdAt: DateTime(2027),
    ));
    single = await items.save(RentItem(name: 'Sherwani', rate: 2000, createdAt: DateTime(2027)));
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    AppDatabase.pathOverride = null;
    await dir.delete(recursive: true);
  });

  BookingDraft draft(
    int item,
    int qty, {
    int pickup = 9,
    int event = 10,
    int ret = 11,
    int? customer,
    double discount = 0,
  }) => BookingDraft(
    customerId: customer ?? anu,
    eventDate: day(event),
    pickupDate: day(pickup),
    returnDate: day(ret),
    itemIds: [item],
    quantities: {item: qty},
    discount: discount,
  );

  Future<int> make(BookingDraft d, {GstConfig gst = GstConfig.off}) =>
      bookings.create(d, isPro: true, gst: gst, now: day(1));

  Future<void> expectError(Future<Object?> f, BookingError e) async {
    try {
      await f;
      fail('expected $e');
    } on BookingException catch (x) {
      expect(x.error, e);
    }
  }

  test('an item remembers how many pieces the shop has', () async {
    expect((await items.get(chair))!.quantity, 10);
    expect((await items.get(single))!.quantity, 1, reason: 'one unless said');
    // a quantity below one is kept as one
    final id = await items.save(RentItem(name: 'Odd', rate: 1, quantity: 0, createdAt: DateTime(2027)));
    expect((await items.get(id))!.quantity, 1);
  });

  group('money', () {
    test('the line is the rate for one piece times the pieces', () async {
      final id = await make(draft(chair, 4));
      final b = (await bookings.get(id))!;
      final line = b.lines.single;
      expect(line.qty, 4);
      expect(line.rate, 50, reason: 'the rate stays that of one piece');
      expect(line.amount, 200);
      expect(line.label, 'Chair × 4');
      expect(b.rentTotal, 200);
      expect(b.payable, 200);
    });

    test('a day rate multiplies by days and pieces, and deposit by pieces', () async {
      // 9th to 11th is three days: 100 x 3 days x 2 lamps
      final id = await make(draft(lamp, 2));
      final b = (await bookings.get(id))!;
      expect(b.lines.single.amount, 600);
      expect(b.depositTotal, 400, reason: '200 deposit for each of 2 lamps');
      expect(b.lines.single.depositAmount, 400);
    });

    test('GST and the discount work on the whole line', () async {
      final id = await make(
        draft(chair, 10, discount: 100),
        gst: const GstConfig(enabled: true),
      );
      final b = (await bookings.get(id))!;
      // 10 x 50 = 500, less 100 = 400 taxable, 18% = 72
      expect(b.rentTotal, 500);
      expect(b.lines.single.taxable, 400);
      expect(b.taxTotal, 72);
      expect(b.payable, 472);
    });

    test('one piece is still the default', () async {
      final id = await make(
        BookingDraft(
          customerId: anu,
          eventDate: day(10),
          pickupDate: day(9),
          returnDate: day(11),
          itemIds: [chair],
        ),
      );
      final line = (await bookings.get(id))!.lines.single;
      expect(line.qty, 1);
      expect(line.label, 'Chair');
    });
  });

  group('availability by pieces', () {
    test('bookings share the pieces until they are used up', () async {
      await make(draft(chair, 4));
      await make(draft(chair, 5, customer: bala));
      await expectError(make(draft(chair, 2)), BookingError.notEnough);
      await make(draft(chair, 1)); // exactly the last piece
      await expectError(make(draft(chair, 1)), BookingError.notEnough);
    });

    test('more than the shop has is refused even when nothing else is booked', () async {
      await expectError(make(draft(chair, 11)), BookingError.notEnough);
      await expectError(make(draft(lamp, 5)), BookingError.notEnough);
    });

    test('a single piece still says it is busy', () async {
      await make(draft(single, 1));
      await expectError(make(draft(single, 1, customer: bala)), BookingError.itemBusy);
    });

    test('pieces come back for days nobody has them', () async {
      await make(draft(chair, 8, pickup: 9, event: 10, ret: 11));
      // the 12th to 14th are free again
      await make(draft(chair, 10, pickup: 12, event: 13, ret: 14, customer: bala));
      // the 11th still has 8 out: only 2 are free for a booking that reaches it
      await expectError(
        make(draft(chair, 3, pickup: 11, event: 11, ret: 11)),
        BookingError.notEnough,
      );
      await make(draft(chair, 2, pickup: 11, event: 11, ret: 11));
    });

    test('the busiest day decides, not the total of all bookings', () async {
      await make(draft(chair, 6, pickup: 1, event: 2, ret: 3));
      await make(draft(chair, 6, pickup: 5, event: 6, ret: 7, customer: bala));
      // 12 pieces in all, but never more than 6 on one day: 4 more fit across both
      await make(draft(chair, 4, pickup: 1, event: 4, ret: 7));
      // and no more than that
      await expectError(
        make(draft(chair, 1, pickup: 2, event: 3, ret: 3)),
        BookingError.notEnough,
      );
    });

    test('availability says how many are free and who has the rest', () async {
      final first = await make(draft(chair, 4));
      final a = (await bookings.availability(
        itemIds: [chair, single],
        pickup: day(10),
        ret: day(10),
      ));
      expect(a[chair]!.stock, 10);
      expect(a[chair]!.free, 6);
      expect(a[chair]!.holder!.bookingId, first);
      expect(a[chair]!.holder!.customerName, 'Anu');
      expect(a[single]!.free, 1);
      expect(a[single]!.holder, isNull);
      // another week: all ten are free
      final later = await bookings.availability(
        itemIds: [chair],
        pickup: day(20),
        ret: day(21),
      );
      expect(later[chair]!.free, 10);
    });

    test('conflicts lists only the items that fall short of what is wanted', () async {
      await make(draft(chair, 8));
      final c = await bookings.conflicts(
        itemIds: [chair, lamp],
        pickup: day(10),
        ret: day(10),
        quantities: {chair: 3, lamp: 4},
      );
      expect(c.keys, [chair]);
      expect(c[chair]!.free, 2);
      expect(c[chair]!.stock, 10);
    });

    test('changing a booking does not count its own pieces twice', () async {
      final id = await make(draft(chair, 10));
      // the same booking, now asking for 7: fine, it is its own
      await bookings.update(id, draft(chair, 7));
      expect((await bookings.get(id))!.lines.single.qty, 7);
      // and it cannot grow past the shop's stock
      await expectError(bookings.update(id, draft(chair, 11)), BookingError.notEnough);
    });

    test('cancelled and returned bookings give their pieces back', () async {
      final a = await make(draft(chair, 6));
      await expectError(make(draft(chair, 6, customer: bala)), BookingError.notEnough);
      await bookings.cancel(a, now: day(2));
      final b = await make(draft(chair, 6, customer: bala));
      await bookings.markPickedUp(b, now: day(9));
      await bookings.markReturned(b, now: day(11));
      await make(draft(chair, 10));
    });

    test('pieces still out and late stay taken until they are brought back', () async {
      final a = await make(draft(chair, 7));
      await bookings.markPickedUp(a, now: day(9));
      // the 20th: due back on the 11th, but not back yet
      final c = await bookings.conflicts(
        itemIds: [chair],
        pickup: day(20),
        ret: day(21),
        quantities: {chair: 5},
        now: day(20),
      );
      expect(c.keys, [chair]);
      expect(c[chair]!.free, 3);
    });
  });

  group('a service business is not limited by other bookings', () {
    test('the same service can be booked many times on one day', () async {
      final service = await items.save(RentItem(name: 'Bridal makeup', rate: 15000, createdAt: DateTime(2027)));
      for (var i = 0; i < 3; i++) {
        await bookings.create(
          draft(service, 1, pickup: 10, event: 10, ret: 10),
          isPro: true,
          checkAvailability: false,
          now: day(1),
        );
      }
      // asked normally, the same booking is refused
      await expectError(make(draft(service, 1, pickup: 10, event: 10, ret: 10)), BookingError.itemBusy);
    });

    test('a service goes from booked straight to done', () async {
      final service = await items.save(RentItem(name: 'Hair styling', rate: 2000, createdAt: DateTime(2027)));
      final id = await bookings.create(
        BookingDraft(
          customerId: anu,
          eventDate: day(10),
          pickupDate: day(10),
          returnDate: day(10),
          itemIds: [service],
          eventTime: '14:30',
          createdBy: 'Meena',
        ),
        isPro: true,
        checkAvailability: false,
        now: day(1),
      );
      var b = (await bookings.get(id))!;
      expect(b.eventTime, '14:30');
      expect(b.createdBy, 'Meena');
      await bookings.markDone(id, now: day(10));
      b = (await bookings.get(id))!;
      expect(b.status, BookingStatus.returned);
      expect(b.status.labelFor(service: true), 'Done');
      expect(b.status.labelFor(service: false), 'Returned');
      // done cannot be done again
      await expectError(bookings.markDone(id), BookingError.badState);
    });
  });

  group('invoice, export and reminders carry the pieces', () {
    test('the invoice keeps the quantity and the rate of one piece', () async {
      final id = await make(
        draft(chair, 4),
        gst: const GstConfig(enabled: true),
      );
      final inv = InvoiceRepo();
      final invoiceId = await inv.createForBooking(
        id,
        shopStateCode: '33',
        prefix: 'RNT',
        gstEnabled: true,
        taxInclusive: false,
        now: day(12),
      );
      final line = (await inv.get(invoiceId))!.lines.single;
      expect(line.qty, 4);
      expect(line.rate, 50);
      expect(line.taxable, 200);
      expect(line.tax, 36);
      expect(line.total, 236);
    });

    test('the bookings export names the pieces', () async {
      await make(draft(chair, 3));
      final lines = await CsvExport().bookings(
        (from: DateTime(2027), to: DateTime(2028)),
      );
      final csv = lines.join(' | ');
      expect(csv, contains('Chair x 3'));
    });
  });
}
