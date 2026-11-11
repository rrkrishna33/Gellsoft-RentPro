import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/core/constants.dart';
import 'package:gellsoft_rentpro/core/share.dart';
import 'package:gellsoft_rentpro/data/booking_models.dart';
import 'package:gellsoft_rentpro/data/business_profile.dart';
import 'package:gellsoft_rentpro/data/invoice_models.dart';
import 'package:gellsoft_rentpro/data/models.dart';
import 'package:gellsoft_rentpro/data/reminders.dart';
import 'package:gellsoft_rentpro/features/bookings/messages.dart';
import 'package:gellsoft_rentpro/l10n/strings.dart';

DateTime day(int d) => DateTime(2027, 3, d);

Booking booking({
  int id = 1,
  int number = 1,
  BookingStatus status = BookingStatus.booked,
  int pickup = 9,
  int event = 10,
  int ret = 11,
  int remind = 2,
  double payable = 1000,
  double paid = 0,
  String name = 'Anu',
}) => Booking(
  id: id,
  uuid: 'u$id',
  number: number,
  customerId: 1,
  customerName: name,
  customerPhone: '9876543210',
  eventDate: day(event),
  pickupDate: day(pickup),
  returnDate: day(ret),
  status: status,
  rentTotal: payable,
  depositTotal: 0,
  discount: 0,
  payable: payable,
  notes: '',
  remindDays: remind,
  createdAt: day(1),
  lines: const [
    BookingLine(
      itemId: 1,
      name: 'Gown',
      rateType: RateType.event,
      rate: 1000,
      deposit: 0,
      amount: 1000,
    ),
  ],
  payments: paid > 0
      ? [
          Payment(
            id: 1,
            bookingId: id,
            kind: PaymentKind.advance,
            amount: paid,
            mode: PayMode.cash,
            note: '',
            paidAt: day(2),
          ),
        ]
      : const [],
);

List<ReminderKind> kinds(List<Booking> b, int today) =>
    buildReminders(b, day(today)).map((r) => r.kind).toList();

void main() {
  tearDown(() => Lang.current = AppLanguage.en);

  group('buildReminders', () {
    test('send items: from remindDays before the event until return', () {
      final b = booking(pickup: 9, event: 10, ret: 11, remind: 2, paid: 1000);
      expect(kinds([b], 7), isEmpty, reason: 'too early');
      expect(kinds([b], 8), [ReminderKind.sendItems]);
      expect(kinds([b], 10), [ReminderKind.sendItems]);
      expect(kinds([b], 11), [ReminderKind.sendItems], reason: 'late ones keep showing');
      expect(kinds([b], 12), isEmpty, reason: 'long past');
    });

    test('remind on the day means only on the event day', () {
      final b = booking(remind: 0, paid: 1000);
      expect(kinds([b], 9), isEmpty);
      expect(kinds([b], 10), [ReminderKind.sendItems]);
    });

    test('out: due back today or tomorrow, then overdue', () {
      final b = booking(status: BookingStatus.pickedUp, ret: 11, paid: 1000);
      expect(kinds([b], 9), isEmpty);
      expect(kinds([b], 10), [ReminderKind.returnDue], reason: 'tomorrow');
      expect(kinds([b], 11), [ReminderKind.returnDue]);
      expect(kinds([b], 12), [ReminderKind.overdue]);
    });

    test('balance: out or back with rent unpaid; booked only close to pickup', () {
      final out = booking(status: BookingStatus.pickedUp, ret: 20);
      expect(kinds([out], 9), [ReminderKind.balance]);
      final back = booking(status: BookingStatus.returned, payable: 500, paid: 100);
      expect(kinds([back], 30), [ReminderKind.balance]);
      final paidUp = booking(status: BookingStatus.returned, payable: 500, paid: 500);
      expect(kinds([paidUp], 30), isEmpty);
      final soon = booking(pickup: 20, event: 21, ret: 22, remind: 0);
      expect(kinds([soon], 10), isEmpty, reason: 'pickup is far off');
      expect(kinds([soon], 19), [ReminderKind.balance], reason: 'pickup tomorrow');
    });

    test('a cancelled booking never shows', () {
      expect(kinds([booking(status: BookingStatus.cancelled)], 10), isEmpty);
    });

    test('order: overdue, due back, send, then money', () {
      final all = [
        booking(id: 1, number: 1, status: BookingStatus.returned, payable: 100),
        booking(id: 2, number: 2, paid: 1000),
        booking(id: 3, number: 3, status: BookingStatus.pickedUp, ret: 11, paid: 1000),
        booking(id: 4, number: 4, status: BookingStatus.pickedUp, ret: 5, paid: 1000),
      ];
      expect(kinds(all, 10), [
        ReminderKind.overdue,
        ReminderKind.returnDue,
        ReminderKind.sendItems,
        ReminderKind.balance,
      ]);
    });

    test('daysAway counts from today', () {
      final r = buildReminders([booking(paid: 1000)], day(8)).single;
      expect(r.daysAway(day(8)), 1, reason: 'pickup is on the 9th');
      expect(r.daysAway(day(10)), -1);
    });
  });

  group('WhatsApp numbers and links', () {
    test('normalises Indian numbers', () {
      expect(whatsappNumber('98765 43210'), '919876543210');
      expect(whatsappNumber('098765-43210'), '919876543210');
      expect(whatsappNumber('+91 98765 43210'), '919876543210');
      expect(whatsappNumber('919876543210'), '919876543210');
      expect(whatsappNumber('0091 98765 43210'), '919876543210');
      expect(whatsappNumber('+44 7700 900123'), '447700900123');
    });

    test('too short or empty is no number', () {
      expect(whatsappNumber(''), isNull);
      expect(whatsappNumber('12345'), isNull);
      expect(whatsappNumber('abc'), isNull);
    });

    test('the link carries the encoded message', () {
      final u = whatsappLink('9876543210', 'Hello & thanks\nBye');
      expect(u.host, 'wa.me');
      expect(u.path, '/919876543210');
      expect(u.queryParameters['text'], 'Hello & thanks\nBye');
    });

    test('sendWhatsApp opens the link, or refuses a bad number', () async {
      Uri? opened;
      linkOpener = (u) async {
        opened = u;
        return true;
      };
      addTearDown(() => linkOpener = null);
      expect(await sendWhatsApp('9876543210', 'Hi'), isTrue);
      expect(opened!.toString(), startsWith('https://wa.me/919876543210?text='));
      opened = null;
      expect(await sendWhatsApp('12', 'Hi'), isFalse);
      expect(opened, isNull, reason: 'nothing opened for a bad number');
      linkOpener = (u) async => false;
      expect(await sendWhatsApp('9876543210', 'Hi'), isFalse);
    });

    test('call opens a tel link', () async {
      Uri? opened;
      linkOpener = (u) async {
        opened = u;
        return true;
      };
      addTearDown(() => linkOpener = null);
      expect(await callPhone('98765 43210'), isTrue);
      expect(opened.toString(), 'tel:9876543210');
      expect(await callPhone(''), isFalse);
    });
  });

  group('messages', () {
    const shop = BusinessProfile(
      name: 'Royal Costumes',
      type: ShopType.costume,
      phone: '9000000000',
    );

    test('confirmation has the facts', () {
      final m = confirmationMessage(booking(paid: 400), shop);
      expect(m, contains('Anu'));
      expect(m, contains('#1'));
      expect(m, contains('Royal Costumes'));
      expect(m, contains('Gown'));
      expect(m, contains('10 Mar 2027'));
      expect(m, contains('₹1,000.00'));
      expect(m, contains('₹600.00'), reason: 'balance');
      expect(m, contains('9000000000'));
    });

    test('each reminder says the right thing', () {
      final b = booking(paid: 100);
      expect(reminderMessage(ReminderKind.sendItems, b, shop), contains('ready'));
      expect(reminderMessage(ReminderKind.sendItems, b, shop), contains('9 Mar 2027'));
      expect(reminderMessage(ReminderKind.returnDue, b, shop), contains('return'));
      expect(reminderMessage(ReminderKind.overdue, b, shop), contains('were due back on 11 Mar 2027'));
      expect(reminderMessage(ReminderKind.balance, b, shop), contains('₹900.00'));
    });

    test('a shop with no phone signs with just its name', () {
      const bare = BusinessProfile(name: 'Shop', type: ShopType.other);
      final m = reminderMessage(ReminderKind.balance, booking(), bare);
      expect(m.trimRight().endsWith('Shop'), isTrue);
    });

    test('receipt and refund wording', () {
      final b = booking(paid: 400);
      final pay = b.payments.single;
      expect(receiptMessage(pay, b, shop), contains('received ₹400.00'));
      final refund = Payment(
        id: 2,
        bookingId: 1,
        kind: PaymentKind.refund,
        amount: 250,
        mode: PayMode.cash,
        note: '',
        paidAt: day(12),
      );
      expect(receiptMessage(refund, b, shop), contains('returned ₹250.00'));
    });

    test('the invoice message says tax invoice or bill, with the figures', () {
      Invoice inv(bool gst) => Invoice(
        id: 1,
        uuid: 'x',
        bookingId: 1,
        prefix: 'RNT',
        number: 7,
        date: day(12),
        cancelled: false,
        customerName: 'Anu',
        customerPhone: '',
        customerAddress: '',
        customerGstin: '',
        supplyState: '',
        interState: false,
        gstEnabled: gst,
        taxInclusive: false,
        discount: 0,
        taxable: 1000,
        cgst: 90,
        sgst: 90,
        igst: 0,
        total: 1180,
        eventDate: day(10),
        pickupDate: day(9),
        returnDate: day(11),
        paid: 500,
      );
      final tax = invoiceMessage(inv(true), shop);
      expect(tax, contains('tax invoice RNT-0007'));
      expect(tax, contains('₹1,180.00'));
      expect(tax, contains('₹680.00'));
      expect(invoiceMessage(inv(false), shop), contains('bill RNT-0007'));
    });

    test('Tamil messages use the Tamil text', () {
      Lang.current = AppLanguage.ta;
      final m = reminderMessage(ReminderKind.balance, booking(), shop);
      expect(m, isNot(contains('is pending for booking')));
      expect(m, contains('Anu'));
    });
  });
}
