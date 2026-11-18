import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/core/booking_math.dart';
import 'package:gellsoft_rentpro/core/constants.dart';
import 'package:gellsoft_rentpro/core/pdf_text.dart';
import 'package:gellsoft_rentpro/data/booking_models.dart';
import 'package:gellsoft_rentpro/data/booking_repo.dart';
import 'package:gellsoft_rentpro/data/business_profile.dart';
import 'package:gellsoft_rentpro/data/database.dart';
import 'package:gellsoft_rentpro/data/invoice_repo.dart';
import 'package:gellsoft_rentpro/data/models.dart';
import 'package:gellsoft_rentpro/data/report_repo.dart';
import 'package:gellsoft_rentpro/data/repositories.dart';
import 'package:gellsoft_rentpro/features/bookings/messages.dart';
import 'package:gellsoft_rentpro/data/reminders.dart';
import 'package:gellsoft_rentpro/features/invoices/invoice_pdf.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DateTime day(int d) => DateTime(2027, 3, d);
DateRange march() => (from: DateTime(2027, 3), to: DateTime(2027, 4));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  final bookings = BookingRepo();
  final items = ItemRepo();
  final customers = CustomerRepo();
  late int anu, bala;
  late int bike; // 100 a day, 500 a week, 1800 a month
  late int gown; // 1000 an event, deposit 2000

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    PdfTextKit.resetForTests();
    dir = await Directory.systemTemp.createTemp('rentpro_control');
    AppDatabase.pathOverride = '${dir.path}/test.db';
    anu = await customers.save(
      Customer(name: 'Anu', phone: '9000000001', createdAt: DateTime(2027)),
    );
    bala = await customers.save(
      Customer(name: 'Bala', phone: '9000000002', createdAt: DateTime(2027)),
    );
    bike = await items.save(
      RentItem(
        name: 'Bike',
        rate: 100,
        rateType: RateType.day,
        weekRate: 500,
        monthRate: 1800,
        createdAt: DateTime(2027),
      ),
    );
    gown = await items.save(
      RentItem(name: 'Gown', rate: 1000, deposit: 2000, createdAt: DateTime(2027)),
    );
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    AppDatabase.pathOverride = null;
    await dir.delete(recursive: true);
  });

  Future<int> book(
    int item, {
    int customer = -1,
    int pickup = 10,
    int ret = 10,
    Map<int, double> rates = const {},
    DateTime? trial,
    double advance = 0,
  }) => bookings.create(
    BookingDraft(
      customerId: customer == -1 ? anu : customer,
      eventDate: day(pickup),
      pickupDate: day(pickup),
      returnDate: day(ret),
      itemIds: [item],
      rates: rates,
      trialDate: trial,
    ),
    isPro: true,
    advance: advance,
    now: day(1),
  );

  Future<int> invoiceFor(int id) => InvoiceRepo().createForBooking(
    id,
    shopStateCode: '33',
    prefix: 'RP',
    gstEnabled: false,
    taxInclusive: false,
    now: day(12),
  );

  Future<void> expectError(Future<Object?> f, BookingError e) async {
    try {
      await f;
      fail('expected $e');
    } on BookingException catch (x) {
      expect(x.error, e);
    }
  }

  group('weekly and monthly rates', () {
    test('the charge for a number of days', () {
      double c(int d) => dayCharge(d, 100, week: 500, month: 1800);
      expect(c(1), 100);
      expect(c(4), 400);
      expect(c(6), 500, reason: '6 days never cost more than the week');
      expect(c(7), 500);
      expect(c(8), 600);
      expect(c(14), 1000);
      expect(c(29), 1800, reason: 'four weeks and a day, capped at the month');
      expect(c(30), 1800);
      expect(c(31), 1900);
      expect(c(60), 3600);
      // no tiers: plain days
      expect(dayCharge(10, 100), 1000);
      // a week rate only
      expect(dayCharge(9, 100, week: 500), 700);
    });

    test('a long booking uses the weekly rate', () async {
      final id = await book(bike, ret: 16); // 7 days
      expect((await bookings.get(id))!.rentTotal, 500);
      final id2 = await book(bike, customer: bala, pickup: 20, ret: 29); // 10 days
      expect((await bookings.get(id2))!.rentTotal, 500 + 300);
    });

    test('a rent agreed for the booking is charged as agreed, by the day',
        () async {
      final id = await book(bike, ret: 16, rates: {bike: 90});
      expect((await bookings.get(id))!.rentTotal, 630);
    });
  });

  group('cleaning gap after a return', () {
    test('the item stays blocked, then is free again', () async {
      await items.save((await items.get(bike))!.copyWith(bufferHours: 24));
      await book(bike, ret: 10); // day 10, blocked until the end of day 11
      await expectError(
        book(bike, customer: bala, pickup: 11, ret: 11),
        BookingError.itemBusy,
      );
      await book(bike, customer: bala, pickup: 12, ret: 12);
    });

    test('no gap set: back to back days are fine', () async {
      await book(bike, ret: 10);
      await book(bike, customer: bala, pickup: 11, ret: 11);
    });

    test('the gap also stops a booking that would run into the next one',
        () async {
      await items.save((await items.get(bike))!.copyWith(bufferHours: 24));
      await book(bike, pickup: 12, ret: 12);
      // day 11 would need day 12 free for cleaning
      await expectError(
        book(bike, customer: bala, pickup: 11, ret: 11),
        BookingError.itemBusy,
      );
      await book(bike, customer: bala, pickup: 9, ret: 9);
    });
  });

  group('an item out of service until a date', () {
    test('cannot be booked before the date, can be on it', () async {
      final it = (await items.get(gown))!;
      await items.save(
        it.copyWith(status: ItemStatus.cleaning, statusUntil: day(15)),
      );
      expect((await items.get(gown))!.statusUntil, day(15));
      expect((await items.get(gown))!.bookableOn(day(14)), isFalse);
      expect((await items.get(gown))!.bookableOn(day(15)), isTrue);
      await expectError(book(gown, pickup: 12, ret: 12), BookingError.itemUnavailable);
      await book(gown, pickup: 15, ret: 15);
    });

    test('with no date it stays out; retired never comes back', () async {
      final it = (await items.get(gown))!;
      await items.save(it.copyWith(status: ItemStatus.repair));
      await expectError(book(gown, pickup: 20, ret: 20), BookingError.itemUnavailable);
      await items.save(
        it.copyWith(status: ItemStatus.retired, statusUntil: day(5)),
      );
      expect((await items.get(gown))!.statusUntil, isNull);
      await expectError(book(gown, pickup: 20, ret: 20), BookingError.itemUnavailable);
    });

    test('an available item forgets its date', () async {
      final it = (await items.get(gown))!;
      await items.save(it.copyWith(status: ItemStatus.repair, statusUntil: day(15)));
      await items.save(
        (await items.get(gown))!.copyWith(status: ItemStatus.active),
      );
      expect((await items.get(gown))!.statusUntil, isNull);
    });
  });

  group('repair log and profit', () {
    test('entries are listed newest first and can be removed', () async {
      final a = await items.addRepair(gown, at: day(3), note: 'Torn hem', cost: 150);
      await items.addRepair(gown, at: day(9), note: 'Dry clean', cost: 250);
      final list = await items.repairsOf(gown);
      expect(list.map((r) => r.note), ['Dry clean', 'Torn hem']);
      expect(list.fold<double>(0, (s, r) => s + r.cost), 400);
      await items.removeRepair(a);
      expect((await items.repairsOf(gown)).length, 1);
    });

    test('profit is the rent less the repairs', () async {
      await book(gown, pickup: 10, ret: 10);
      await book(gown, customer: bala, pickup: 20, ret: 20);
      await items.addRepair(gown, at: day(12), note: 'Torn', cost: 300);
      await items.addRepair(bike, at: day(5), note: 'Puncture', cost: 80);
      final p = await ReportRepo().itemProfit(march());
      final g = p.firstWhere((x) => x.name == 'Gown');
      expect(g.bookings, 2);
      expect(g.rent, 2000);
      expect(g.repairs, 300);
      expect(g.profit, 1700);
      final b = p.firstWhere((x) => x.name == 'Bike');
      expect(b.bookings, 0);
      expect(b.profit, -80);
      expect(p.first.name, 'Gown', reason: 'best first');
    });

    test('a cancelled booking earns nothing', () async {
      final id = await book(gown, pickup: 10, ret: 10);
      await bookings.cancel(id, now: day(2));
      expect(await ReportRepo().itemProfit(march()), isEmpty);
    });
  });

  group('customer warning and trial date', () {
    test('a warning is kept with the customer', () async {
      final c = (await customers.get(anu))!;
      await customers.save(c.copyWith(warning: '  Returned late twice  '));
      expect((await customers.get(anu))!.warning, 'Returned late twice');
      await customers.save((await customers.get(anu))!.copyWith(warning: ''));
      expect((await customers.get(anu))!.warning, '');
    });

    test('a trial date is kept on the booking and survives an extension',
        () async {
      final id = await book(gown, pickup: 20, ret: 21, trial: day(15));
      expect((await bookings.get(id))!.trialDate, day(15));
      await bookings.extend(id, returnDate: day(23), now: day(2));
      expect((await bookings.get(id))!.trialDate, day(15));
      expect((await bookings.get(id))!.returnDate, day(23));
      final none = await book(bike, customer: bala, pickup: 5, ret: 5);
      expect((await bookings.get(none))!.trialDate, isNull);
    });
  });

  group('extend a booking', () {
    test('the rent and the invoice follow the new return', () async {
      final id = await book(bike, pickup: 10, ret: 11, rates: {bike: 100});
      final inv = await invoiceFor(id);
      expect((await InvoiceRepo().get(inv))!.total, 200);
      await bookings.extend(id, returnDate: day(13), now: day(5));
      await InvoiceRepo().refreshForBooking(id);
      final b = (await bookings.get(id))!;
      expect(b.returnDate, day(13));
      expect(b.rentTotal, 400);
      expect(b.payable, 400);
      final i = (await InvoiceRepo().get(inv))!;
      expect(i.total, 400);
      expect(i.lines.single.days, 4);
      expect(i.number, 1);
    });

    test('an agreed rent is kept when extending', () async {
      final id = await book(bike, pickup: 10, ret: 11, rates: {bike: 80});
      await bookings.extend(id, returnDate: day(12), now: day(5));
      expect((await bookings.get(id))!.rentTotal, 240);
    });

    test('it cannot run into the next booking of the item', () async {
      final id = await book(bike, pickup: 10, ret: 10);
      await book(bike, customer: bala, pickup: 12, ret: 12);
      await expectError(
        bookings.extend(id, returnDate: day(12), now: day(5)),
        BookingError.itemBusy,
      );
      await bookings.extend(id, returnDate: day(11), now: day(5));
    });

    test('a returned booking cannot be extended', () async {
      final id = await book(gown, pickup: 10, ret: 10);
      await bookings.markPickedUp(id, now: day(10));
      await bookings.markReturned(id, now: day(10));
      await expectError(
        bookings.extend(id, returnDate: day(12)),
        BookingError.badState,
      );
    });

    test('an hourly booking moves its return time', () async {
      final court = await items.save(
        RentItem(
          name: 'Court',
          rate: 500,
          rateType: RateType.hour,
          createdAt: DateTime(2027),
        ),
      );
      final id = await bookings.create(
        BookingDraft(
          customerId: anu,
          eventDate: day(10),
          pickupDate: day(10),
          returnDate: day(10),
          itemIds: [court],
          pickupTime: '10:00',
          returnTime: '12:00',
        ),
        isPro: true,
        now: day(1),
      );
      await bookings.extend(id, returnDate: day(10), returnTime: '14:30', now: day(2));
      final b = (await bookings.get(id))!;
      expect(b.returnTime, '14:30');
      expect(b.rentTotal, 2500); // 4.5 hours round up to 5 hours at 500
    });
  });

  group('deposit kept for damage', () {
    Future<int> outBooking() async {
      final id = await book(gown, pickup: 10, ret: 10);
      await bookings.addPayment(
        id,
        kind: PaymentKind.advance,
        amount: 1000,
        at: day(2),
      );
      await bookings.addPayment(
        id,
        kind: PaymentKind.deposit,
        amount: 2000,
        at: day(2),
      );
      await bookings.markPickedUp(id, now: day(10));
      return id;
    }

    test('part is kept: charged, taken from the deposit, nothing owed',
        () async {
      final id = await outBooking();
      final inv = await invoiceFor(id);
      await bookings.settleDeposit(id, refund: 1500, reason: 'Torn lace', now: day(11));
      await bookings.markReturned(id, now: day(11));
      await InvoiceRepo().refreshForBooking(id);
      final b = (await bookings.get(id))!;
      expect(b.charges.single.amount, 500);
      expect(b.charges.single.note, 'Torn lace');
      expect(b.payable, 1500);
      expect(b.balanceDue, 0);
      // handed back 1500, kept 500, nothing held any more
      expect(b.depositRefunded, 1500);
      expect(b.depositKept, 500);
      expect(b.depositHeld, 0);
      expect(b.depositTaken, 2000);
      expect((await InvoiceRepo().get(inv))!.total, 1500);
      // the kept amount is rent collected, not money handed back
      expect(b.rentPaid, 1500);
    });

    test('everything handed back keeps nothing and adds no charge', () async {
      final id = await outBooking();
      await bookings.settleDeposit(id, refund: 2000, now: day(11));
      final b = (await bookings.get(id))!;
      expect(b.charges, isEmpty);
      expect(b.depositHeld, 0);
      expect(b.balanceDue, 1000 - 1000);
    });

    test('all of the deposit kept', () async {
      final id = await outBooking();
      await bookings.settleDeposit(id, refund: 0, reason: 'Lost', now: day(11));
      final b = (await bookings.get(id))!;
      expect(b.charges.single.amount, 2000);
      expect(b.depositHeld, 0);
      expect(b.balanceDue, 0);
    });

    test('more than the deposit cannot be handed back', () async {
      final id = await outBooking();
      await expectError(
        bookings.settleDeposit(id, refund: 2500),
        BookingError.badAmount,
      );
    });
  });

  group('photos', () {
    test('an ID picture does not use up the free photos', () async {
      final id = await book(gown, pickup: 10, ret: 10);
      await bookings.addPhoto(id, path: 'a.jpg', stage: 'id', isPro: false);
      await bookings.addPhoto(id, path: 'b.jpg', stage: 'id', isPro: false);
      await bookings.addPhoto(id, path: 'c.jpg', stage: 'id', isPro: false);
      await bookings.addPhoto(id, path: 'd.jpg', stage: 'pickup', isPro: false);
      await bookings.addPhoto(id, path: 'e.jpg', stage: 'return', isPro: false);
      await expectError(
        bookings.addPhoto(id, path: 'f.jpg', stage: 'other', isPro: false),
        BookingError.limitReached,
      );
      expect((await bookings.get(id))!.photos.length, 5);
    });
  });

  group('UPI QR, agreement and messages', () {
    const shop = BusinessProfile(
      name: 'Bala Rentals',
      type: ShopType.vehicle,
      phone: '9000000009',
      upiId: 'bala@okbank',
    );

    test('the pay link carries the shop, the amount and the note', () {
      final link = shop.upiLink(amount: 450.5, note: 'RNT-0001')!;
      final u = Uri.parse(link);
      expect(u.scheme, 'upi');
      expect(u.host, 'pay');
      expect(u.queryParameters['pa'], 'bala@okbank');
      expect(u.queryParameters['pn'], 'Bala Rentals');
      expect(u.queryParameters['am'], '450.50');
      expect(u.queryParameters['cu'], 'INR');
      expect(u.queryParameters['tn'], 'RNT-0001');
      expect(shop.copyWith(upiId: '').upiLink(amount: 5, note: 'x'), isNull);
    });

    test('the QR is printed only when something is due', () async {
      final id = await book(gown, pickup: 10, ret: 10);
      final inv = (await InvoiceRepo().get(await invoiceFor(id)))!;
      final withQr = await buildInvoicePdf(shop: shop, invoice: inv);
      final noUpi = await buildInvoicePdf(
        shop: shop.copyWith(upiId: ''),
        invoice: inv,
      );
      expect(withQr.length, greaterThan(noUpi.length));

      // paid in full: no QR, same size as without a UPI id
      await bookings.addPayment(id, kind: PaymentKind.balance, amount: 1000, at: day(3));
      final paid = (await InvoiceRepo().forBooking(id))!;
      final paidPdf = await buildInvoicePdf(shop: shop, invoice: paid);
      final paidNoUpi = await buildInvoicePdf(
        shop: shop.copyWith(upiId: ''),
        invoice: paid,
      );
      expect(paidPdf.length, paidNoUpi.length);
    });

    test('the receipt carries the QR for the balance', () async {
      final id = await book(gown, pickup: 10, ret: 10, advance: 300);
      final b = (await bookings.get(id))!;
      final a = await buildReceiptPdf(shop: shop, booking: b, payment: b.payments.first);
      final c = await buildReceiptPdf(
        shop: shop.copyWith(upiId: ''),
        booking: b,
        payment: b.payments.first,
      );
      expect(a.length, greaterThan(c.length));
    });

    test('the balance reminder ends with the pay link', () async {
      final id = await book(gown, pickup: 10, ret: 10);
      final b = (await bookings.get(id))!;
      final msg = reminderMessage(ReminderKind.balance, b, shop);
      expect(msg, contains('upi://pay?pa=bala%40okbank'));
      expect(msg, contains('am=1000.00'));
      expect(
        reminderMessage(ReminderKind.balance, b, shop.copyWith(upiId: '')),
        isNot(contains('upi://')),
      );
    });

    test('the agreement is a PDF with the standard or the shop terms', () async {
      final id = await book(gown, pickup: 10, ret: 11);
      final b = (await bookings.get(id))!;
      final customer = await customers.get(anu);
      final pdf = await buildAgreementPdf(shop: shop, booking: b, customer: customer);
      expect(String.fromCharCodes(pdf.take(4)), '%PDF');
      // standard terms; a vehicle shop has two more
      final vehicle = agreementTermsFor(shop);
      final other = agreementTermsFor(shop.copyWith(type: ShopType.costume));
      expect(vehicle.length, other.length + 2);
      // the shop's own terms replace them, one per line
      final own = agreementTermsFor(
        shop.copyWith(agreementTerms: 'No smoking\n\n  Return by 6 PM  '),
      );
      expect(own, ['No smoking', 'Return by 6 PM']);
      final custom = await buildAgreementPdf(
        shop: shop.copyWith(agreementTerms: 'No smoking'),
        booking: b,
      );
      expect(custom.length, isNot(pdf.length));
    });
  });
}
