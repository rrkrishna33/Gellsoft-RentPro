import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/data/booking_models.dart';
import 'package:gellsoft_rentpro/data/booking_repo.dart';
import 'package:gellsoft_rentpro/data/database.dart';
import 'package:gellsoft_rentpro/data/invoice_repo.dart';
import 'package:gellsoft_rentpro/data/models.dart';
import 'package:gellsoft_rentpro/data/report_repo.dart';
import 'package:gellsoft_rentpro/data/repositories.dart';
import 'package:gellsoft_rentpro/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DateTime day(int d) => DateTime(2027, 3, d);

void main() {
  late Directory dir;
  final bookings = BookingRepo();
  final items = ItemRepo();
  final customers = CustomerRepo();
  late int anu, bala;
  late int gown, tent;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('rentpro_dispatch');
    AppDatabase.pathOverride = '${dir.path}/test.db';
    anu = await customers.save(
      Customer(name: 'Anu', phone: '9000000001', createdAt: DateTime(2027)),
    );
    bala = await customers.save(
      Customer(name: 'Bala', phone: '9000000002', createdAt: DateTime(2027)),
    );
    gown = await items.save(
      RentItem(name: 'Gown', rate: 1000, createdAt: DateTime(2027)),
    );
    tent = await items.save(
      RentItem(name: 'Tent', rate: 500, createdAt: DateTime(2027)),
    );
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    AppDatabase.pathOverride = null;
    await dir.delete(recursive: true);
  });

  Future<int> make({
    int? customer,
    int item = -1,
    int pickup = 9,
    int event = 10,
    int ret = 11,
    double advance = 0,
    String by = '',
  }) => bookings.create(
    BookingDraft(
      customerId: customer ?? anu,
      eventDate: day(event),
      pickupDate: day(pickup),
      returnDate: day(ret),
      itemIds: [item == -1 ? gown : item],
      createdBy: by,
    ),
    isPro: true,
    advance: advance,
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

  group('courier dispatch', () {
    test('a booked booking can be sent, with the courier details', () async {
      final id = await make();
      await bookings.markDispatched(
        id,
        courierName: ' DTDC ',
        courierNo: 'D123',
        now: day(8),
      );
      final b = (await bookings.get(id))!;
      expect(b.status, BookingStatus.dispatched);
      expect(b.courierName, 'DTDC');
      expect(b.courierNo, 'D123');
      expect(b.dispatchedAt, day(8));
      expect(b.status.isOut, isTrue);
    });

    test('the courier name and number are optional', () async {
      final id = await make();
      await bookings.markDispatched(id);
      final b = (await bookings.get(id))!;
      expect(b.status, BookingStatus.dispatched);
      expect(b.courierName, '');
      expect(b.courierNo, '');
    });

    test('only a booked booking can be dispatched', () async {
      final a = await make();
      await bookings.markPickedUp(a);
      await expectError(bookings.markDispatched(a), BookingError.badState);
      final c = await make(item: tent);
      await bookings.cancel(c);
      await expectError(bookings.markDispatched(c), BookingError.badState);
      final d = await make(item: tent, pickup: 20, event: 21, ret: 22);
      await bookings.markDispatched(d);
      await expectError(bookings.markDispatched(d), BookingError.badState);
    });

    test('a dispatched booking can be returned, and its courier corrected', () async {
      final id = await make();
      await bookings.markDispatched(id, courierName: 'DTDC');
      await bookings.updateCourier(id, courierName: 'Blue Dart', courierNo: 'B9');
      var b = (await bookings.get(id))!;
      expect(b.courierName, 'Blue Dart');
      expect(b.courierNo, 'B9');
      await bookings.markReturned(id);
      b = (await bookings.get(id))!;
      expect(b.status, BookingStatus.returned);
      expect(b.courierName, 'Blue Dart', reason: 'kept for the record');
    });

    test('courier details cannot be changed on a booking that was not sent', () async {
      final id = await make();
      await expectError(
        bookings.updateCourier(id, courierName: 'x', courierNo: 'y'),
        BookingError.badState,
      );
    });

    test('a dispatched booking still blocks its item', () async {
      final id = await make();
      await bookings.markDispatched(id);
      final clash = await bookings.conflicts(
        itemIds: [gown],
        pickup: day(10),
        ret: day(10),
        now: day(8),
      );
      expect(clash.keys, [gown]);
    });

    test('late and not back: overdue, in the out list, in the reminders', () async {
      final id = await make();
      await bookings.markDispatched(id);
      final b = (await bookings.get(id))!;
      expect(b.isOverdue(day(12)), isTrue);
      expect(b.isOverdue(day(11)), isFalse);
      final out = await bookings.list(filter: BookingFilter.out);
      expect(out.map((x) => x.id), [id]);
      final remind = await bookings.forReminders();
      expect(remind.map((x) => x.id), contains(id));
    });

    test('Out lists collected and sent bookings together', () async {
      final a = await make();
      final c = await make(item: tent);
      await bookings.markPickedUp(a);
      await bookings.markDispatched(c);
      final out = await bookings.list(filter: BookingFilter.out);
      expect(out.map((x) => x.id).toSet(), {a, c});
    });
  });

  group('balance due list', () {
    test('only bookings that still owe rent, never cancelled ones', () async {
      final owes = await make(advance: 400); // 1000 rent, 600 left
      final paid = await make(item: tent, advance: 500); // paid in full
      final gone = await make(item: tent, customer: bala, pickup: 20, event: 21, ret: 22);
      await bookings.cancel(gone);
      final due = await bookings.list(filter: BookingFilter.due);
      expect(due.map((b) => b.id), [owes]);
      expect(paid, isNot(owes));
    });
  });

  group('late and damage charges', () {
    test('a charge is added to what is owed', () async {
      final id = await make(advance: 1000);
      await bookings.markPickedUp(id);
      await bookings.addCharge(
        id,
        kind: ChargeKind.late,
        amount: 250,
        note: '2 days late',
      );
      final b = (await bookings.get(id))!;
      expect(b.payable, 1250);
      expect(b.chargesTotal, 250);
      expect(b.balanceDue, 250);
      expect(b.charges.single.kind, ChargeKind.late);
      expect(b.charges.single.note, '2 days late');
    });

    test('charges can be added after the return, not before pickup', () async {
      final id = await make();
      await expectError(
        bookings.addCharge(id, kind: ChargeKind.damage, amount: 100),
        BookingError.badState,
      );
      await bookings.markPickedUp(id);
      await bookings.markReturned(id);
      await bookings.addCharge(id, kind: ChargeKind.damage, amount: 100);
      expect((await bookings.get(id))!.balanceDue, 1100);
    });

    test('an amount of nothing is refused', () async {
      final id = await make();
      await bookings.markPickedUp(id);
      await expectError(
        bookings.addCharge(id, kind: ChargeKind.late, amount: 0),
        BookingError.badAmount,
      );
    });

    test('a charge can be paid like the rest of the rent', () async {
      final id = await make();
      await bookings.markPickedUp(id);
      await bookings.addCharge(id, kind: ChargeKind.damage, amount: 300);
      await bookings.addPayment(id, kind: PaymentKind.balance, amount: 1300);
      expect((await bookings.get(id))!.balanceDue, 0);
    });

    test('removing a charge takes it off again', () async {
      final id = await make();
      await bookings.markPickedUp(id);
      final c = await bookings.addCharge(id, kind: ChargeKind.late, amount: 200);
      await bookings.removeCharge(c);
      final b = (await bookings.get(id))!;
      expect(b.payable, 1000);
      expect(b.charges, isEmpty);
    });

    test('a charge that was already paid can be taken off, and the refund is noted', () async {
      final id = await make(advance: 1000);
      await bookings.markPickedUp(id);
      final c = await bookings.addCharge(id, kind: ChargeKind.late, amount: 200);
      await bookings.addPayment(id, kind: PaymentKind.balance, amount: 200);
      await bookings.removeCharge(c);
      final b = (await bookings.get(id))!;
      expect(b.payable, 1000);
      expect(b.charges, isEmpty);
      expect(b.rentPaid, 1000, reason: 'the 200 going back is counted');
      expect(b.balanceDue, 0);
      final refund = b.payments.firstWhere((p) => p.amount < 0);
      expect(refund.amount, -200);
      expect(refund.note, 'Refund of a removed charge');
    });

    test('a charge only partly paid: just the paid part is refunded', () async {
      final id = await make(advance: 1000);
      await bookings.markPickedUp(id);
      final c = await bookings.addCharge(id, kind: ChargeKind.late, amount: 200);
      await bookings.addPayment(id, kind: PaymentKind.balance, amount: 50);
      await bookings.removeCharge(c);
      final b = (await bookings.get(id))!;
      expect(b.rentPaid, 1000);
      expect(b.payments.firstWhere((p) => p.amount < 0).amount, -50);
    });

    test('an unpaid charge is removed with no refund', () async {
      final id = await make(advance: 1000);
      await bookings.markPickedUp(id);
      final c = await bookings.addCharge(id, kind: ChargeKind.late, amount: 200);
      await bookings.removeCharge(c);
      expect((await bookings.get(id))!.payments.length, 1);
    });

    test('changing the booking keeps its charges', () async {
      final id = await make();
      await bookings.markPickedUp(id);
      await bookings.addCharge(id, kind: ChargeKind.damage, amount: 150);
      await bookings.update(
        id,
        BookingDraft(
          customerId: anu,
          eventDate: day(10),
          pickupDate: day(9),
          returnDate: day(11),
          itemIds: [gown, tent],
        ),
        now: day(1),
      );
      final b = (await bookings.get(id))!;
      expect(b.rentTotal, 1500);
      expect(b.payable, 1650, reason: 'rent and the charge');
    });

    test('the invoice carries the charges and matches the booking', () async {
      final id = await make();
      await bookings.markPickedUp(id);
      await bookings.addCharge(
        id,
        kind: ChargeKind.late,
        amount: 200,
        note: '1 day late',
      );
      final inv = await InvoiceRepo().createForBooking(
        id,
        shopStateCode: '33',
        prefix: 'RP',
        gstEnabled: false,
        taxInclusive: false,
        now: day(12),
      );
      final i = (await InvoiceRepo().get(inv))!;
      expect(i.total, 1200);
      expect(i.lines.map((l) => l.name), contains('Late return (1 day late)'));
    });
  });

  group('charges on an invoice that already exists', () {
    Future<int> invoiceFor(int id) => InvoiceRepo().createForBooking(
      id,
      shopStateCode: '33',
      prefix: 'RP',
      gstEnabled: false,
      taxInclusive: false,
      now: day(12),
    );

    test('a charge added after the invoice appears on it', () async {
      final id = await make(advance: 1000);
      await bookings.markPickedUp(id);
      final inv = await invoiceFor(id);
      expect((await InvoiceRepo().get(inv))!.total, 1000);
      await bookings.addCharge(
        id,
        kind: ChargeKind.damage,
        amount: 300,
        note: 'torn',
      );
      final i = (await InvoiceRepo().get(inv))!;
      expect(i.total, 1300);
      expect(i.total, (await bookings.get(id))!.payable);
      expect(i.lines.map((l) => l.name), contains('Damage (torn)'));
      expect(i.lines.length, 2);
    });

    test('removing it takes it off the invoice again', () async {
      final id = await make();
      await bookings.markPickedUp(id);
      final inv = await invoiceFor(id);
      final c = await bookings.addCharge(id, kind: ChargeKind.late, amount: 200);
      await bookings.removeCharge(c);
      final i = (await InvoiceRepo().get(inv))!;
      expect(i.total, 1000);
      expect(i.lines.length, 1);
    });

    test('a cancelled invoice is left alone', () async {
      final id = await make();
      await bookings.markPickedUp(id);
      final inv = await invoiceFor(id);
      final d = await AppDatabase.instance.db;
      await d.update('invoices', {'status': 'cancelled'}, where: 'id = ?', whereArgs: [inv]);
      await bookings.addCharge(id, kind: ChargeKind.late, amount: 200);
      final i = (await InvoiceRepo().get(inv))!;
      expect(i.total, 1000);
      expect(i.lines.length, 1);
    });

    test('the invoice line is found even after the language was switched', () async {
      final id = await make();
      await bookings.markPickedUp(id);
      final inv = await invoiceFor(id);
      final c = await bookings.addCharge(
        id,
        kind: ChargeKind.late,
        amount: 200,
        note: '2 days late',
      );
      Lang.current = AppLanguage.ta;
      addTearDown(() => Lang.current = AppLanguage.en);
      await bookings.removeCharge(c);
      final i = (await InvoiceRepo().get(inv))!;
      expect(i.total, 1000);
      expect(i.lines.length, 1);
    });

    test('two charges of the same kind and amount come off one at a time', () async {
      final id = await make();
      await bookings.markPickedUp(id);
      final inv = await invoiceFor(id);
      await bookings.addCharge(id, kind: ChargeKind.damage, amount: 100);
      final second = await bookings.addCharge(id, kind: ChargeKind.damage, amount: 100);
      await bookings.removeCharge(second);
      final i = (await InvoiceRepo().get(inv))!;
      expect(i.total, 1100);
      expect(i.lines.length, 2);
    });
  });

  group('customer history', () {
    test('every booking of that customer, cancelled ones included', () async {
      final a = await make();
      final b = await make(item: tent, pickup: 20, event: 21, ret: 22);
      await bookings.cancel(b);
      await make(item: tent, customer: bala, pickup: 5, event: 6, ret: 7);
      final list = await bookings.forCustomer(anu);
      expect(list.map((x) => x.id).toSet(), {a, b});
      expect(list.first.id, b, reason: 'newest event first');
    });
  });

  group('availability calendar', () {
    test('bookings that hold items on some day of the span', () async {
      final inside = await make(pickup: 9, event: 10, ret: 11);
      final other = await make(item: tent, pickup: 25, event: 26, ret: 27);
      final sent = await make(
        item: tent,
        customer: bala,
        pickup: 3,
        event: 4,
        ret: 5,
      );
      await bookings.markDispatched(sent);
      final returned = await make(item: gown, pickup: 15, event: 16, ret: 17);
      await bookings.markPickedUp(returned);
      await bookings.markReturned(returned);

      final week = await bookings.heldBetween(day(8), day(14), now: day(2));
      expect(week.map((b) => b.id), [inside]);
      final month = await bookings.heldBetween(day(1), day(31), now: day(2));
      expect(month.map((b) => b.id).toSet(), {inside, other, sent});
    });

    test('items not back after the return day are held up to today', () async {
      final late = await make(pickup: 3, event: 4, ret: 5);
      await bookings.markPickedUp(late);
      final span = await bookings.heldBetween(day(8), day(10), now: day(9));
      expect(span.map((b) => b.id), [late]);
      final past = await bookings.heldBetween(day(6), day(7), now: day(5));
      expect(past, isEmpty);
    });
  });

  group('bookings by person', () {
    test('grouped by who made them, biggest first, cancelled left out', () async {
      await make(by: 'Meena', advance: 300);
      await make(item: tent, by: 'Meena', pickup: 12, event: 13, ret: 14);
      final c = await make(by: 'Ravi', pickup: 15, event: 16, ret: 17);
      await make(item: tent, by: '', pickup: 18, event: 19, ret: 20);
      final x = await make(item: tent, by: 'Ravi', pickup: 21, event: 22, ret: 23);
      await bookings.cancel(x);
      expect(c, isNot(x));
      final r = await ReportRepo().byStaff((from: day(1), to: day(31)));
      expect(r.map((p) => p.name), ['Meena', 'Ravi', '']);
      expect(r.first.count, 2);
      expect(r.first.amount, 1500);
      expect(r.first.paid, 300);
      expect(r[1].count, 1);
    });
  });
}
