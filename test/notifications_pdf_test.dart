import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/core/constants.dart';
import 'package:gellsoft_rentpro/data/booking_models.dart';
import 'package:gellsoft_rentpro/data/business_profile.dart';
import 'package:gellsoft_rentpro/data/invoice_models.dart';
import 'package:gellsoft_rentpro/data/models.dart';
import 'package:gellsoft_rentpro/data/notifications.dart';
import 'package:gellsoft_rentpro/features/invoices/invoice_pdf.dart';
import 'package:gellsoft_rentpro/l10n/strings.dart';
import 'package:gellsoft_rentpro/subscription/plan.dart';

DateTime day(int d) => DateTime(2027, 3, d);

Booking booking({
  int id = 1,
  BookingStatus status = BookingStatus.booked,
  int pickup = 9,
  int event = 10,
  int ret = 11,
  int remind = 2,
  double payable = 1000,
  bool paidUp = true,
}) => Booking(
  id: id,
  uuid: 'u$id',
  number: id,
  customerId: 1,
  customerName: 'Anu',
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
  payments: paidUp
      ? [
          Payment(
            id: id,
            bookingId: id,
            kind: PaymentKind.advance,
            amount: payable,
            mode: PayMode.cash,
            note: '',
            paidAt: day(2),
          ),
        ]
      : const [],
);

class _Recorder implements NotificationBackend {
  final calls = <String>[];
  final scheduled = <PlannedNotification>[];
  bool permission = true;

  @override
  Future<void> init() async => calls.add('init');

  @override
  Future<bool> requestPermission() async {
    calls.add('permission');
    return permission;
  }

  @override
  Future<void> cancelAll() async => calls.add('cancelAll');

  @override
  Future<void> schedule(PlannedNotification n) async {
    calls.add('schedule');
    scheduled.add(n);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => Lang.current = AppLanguage.en);

  group('notification plan', () {
    final morning = DateTime(2027, 3, 8, 7, 0);

    test('a morning summary for each day that has something to do', () {
      final plan = planNotifications(
        bookings: [booking(pickup: 9, event: 10, ret: 11)],
        settings: const NotifySettings(beforeEvent: false),
        now: morning,
      );
      // sendItems shows on the 8th (2 days before the event), 9th, 10th, 11th
      expect(plan.map((n) => n.at.day), [8, 9, 10, 11]);
      expect(plan.first.at, DateTime(2027, 3, 8, 8, 0));
      expect(plan.first.title, '1 things need you today');
      expect(plan.first.body, '1 to send');
    });

    test('a time that has passed today is not scheduled', () {
      final plan = planNotifications(
        bookings: [booking()],
        settings: const NotifySettings(beforeEvent: false),
        now: DateTime(2027, 3, 8, 9, 30),
      );
      expect(plan.first.at.day, 9);
    });

    test('the reminder time follows the setting', () {
      final plan = planNotifications(
        bookings: [booking()],
        settings: const NotifySettings(
          beforeEvent: false,
          hour: 18,
          minute: 30,
        ),
        now: morning,
      );
      expect(plan.first.at, DateTime(2027, 3, 8, 18, 30));
    });

    test('each booking gets a reminder before the event and on return day', () {
      final plan = planNotifications(
        bookings: [booking(id: 7, pickup: 12, event: 13, ret: 14, remind: 3)],
        settings: const NotifySettings(daily: false),
        now: morning,
      );
      expect(plan.length, 2);
      final send = plan.firstWhere((n) => n.title.startsWith('Send the items'));
      expect(send.at, DateTime(2027, 3, 10, 8, 0), reason: '3 days before the 13th');
      expect(send.title, 'Send the items for #7');
      expect(send.body, 'Gown for Anu, event on 13 Mar 2027');
      final back = plan.firstWhere((n) => n.title.startsWith('Items due back'));
      expect(back.at, DateTime(2027, 3, 14, 8, 0));
      expect(send.id, isNot(back.id));
    });

    test('money still due is counted in the morning summary', () {
      final plan = planNotifications(
        bookings: [booking(paidUp: false)],
        settings: const NotifySettings(beforeEvent: false),
        now: morning,
      );
      expect(plan.first.body, contains('1 to send'));
      expect(plan.first.body, contains('1 with money due'));
    });

    test('out bookings only remind about the return', () {
      final plan = planNotifications(
        bookings: [booking(status: BookingStatus.pickedUp, ret: 12)],
        settings: const NotifySettings(daily: false),
        now: morning,
      );
      expect(plan.single.title, startsWith('Items due back'));
    });

    test('cancelled and returned bookings give nothing', () {
      final plan = planNotifications(
        bookings: [
          booking(id: 1, status: BookingStatus.cancelled),
          booking(id: 2, status: BookingStatus.returned),
        ],
        settings: const NotifySettings(),
        now: morning,
      );
      expect(plan, isEmpty);
    });

    test('both switches off plans nothing; the list is sorted and capped', () {
      expect(
        planNotifications(
          bookings: [booking()],
          settings: const NotifySettings(daily: false, beforeEvent: false),
          now: morning,
        ),
        isEmpty,
      );
      final many = [
        for (var i = 1; i <= 40; i++)
          booking(id: i, pickup: 9 + i % 3, event: 10 + i % 3, ret: 11 + i % 3),
      ];
      final plan = planNotifications(
        bookings: many,
        settings: const NotifySettings(),
        now: morning,
      );
      expect(plan.length, notifyLimit);
      for (var i = 1; i < plan.length; i++) {
        expect(plan[i].at.isBefore(plan[i - 1].at), isFalse);
      }
      expect(plan.map((n) => n.id).toSet().length, plan.length, reason: 'unique ids');
    });

    test('Tamil titles when the app is in Tamil', () {
      Lang.current = AppLanguage.ta;
      final plan = planNotifications(
        bookings: [booking()],
        settings: const NotifySettings(beforeEvent: false),
        now: morning,
      );
      expect(plan.first.title, contains('இன்று'));
    });
  });

  group('syncing with the phone', () {
    late _Recorder phone;
    setUp(() {
      phone = _Recorder();
      NotificationService.backend = phone;
    });

    test('Pro: old reminders are cleared and the plan is scheduled', () async {
      final n = await NotificationService.sync(
        isPro: true,
        settings: const NotifySettings(),
        bookings: [booking()],
        now: DateTime(2027, 3, 8, 7),
      );
      expect(n, greaterThan(0));
      expect(phone.calls.first, 'cancelAll');
      expect(phone.scheduled.length, n);
    });

    test('without Pro nothing stays scheduled', () async {
      final n = await NotificationService.sync(
        isPro: false,
        settings: const NotifySettings(),
        bookings: [booking()],
        now: DateTime(2027, 3, 8, 7),
      );
      expect(n, 0);
      expect(phone.calls, ['cancelAll']);
    });

    test('both switches off schedules nothing', () async {
      final n = await NotificationService.sync(
        isPro: true,
        settings: const NotifySettings(daily: false, beforeEvent: false),
        bookings: [booking()],
        now: DateTime(2027, 3, 8, 7),
      );
      expect(n, 0);
      expect(phone.scheduled, isEmpty);
    });

    test('asking permission goes to the phone', () async {
      expect(await NotificationService.askPermission(), isTrue);
      phone.permission = false;
      expect(await NotificationService.askPermission(), isFalse);
    });
  });

  group('settings are kept', () {
    test('defaults, save and load', () async {
      const a = NotifySettings();
      expect(a.daily, isTrue);
      expect(a.hour, 8);
      final b = a.copyWith(daily: false, hour: 17, minute: 15);
      expect(b.daily, isFalse);
      expect(b.beforeEvent, isTrue);
      expect(b.time.hour, 17);
      expect(b.time.minute, 15);
    });
  });

  group('PDFs', () {
    const shop = BusinessProfile(
      name: 'Royal Costumes',
      type: ShopType.costume,
      phone: '9000000000',
      address: 'Madurai',
      gstEnabled: true,
      gstin: '33ABCDE1234F1Z5',
      invoiceFooter: 'Thank you',
    );

    Invoice inv({bool gst = true, bool inter = false, bool cancelled = false, String name = 'Anu'}) => Invoice(
      id: 1,
      uuid: 'x',
      bookingId: 1,
      prefix: 'RNT',
      number: 12,
      date: day(12),
      cancelled: cancelled,
      customerName: name,
      customerPhone: '9876543210',
      customerAddress: 'Sivakasi',
      customerGstin: gst ? '29ABCDE1234F1Z5' : '',
      supplyState: gst ? '29' : '',
      interState: inter,
      gstEnabled: gst,
      taxInclusive: false,
      discount: 50,
      taxable: 950,
      cgst: inter ? 0 : 85.5,
      sgst: inter ? 0 : 85.5,
      igst: inter ? 171 : 0,
      total: 1121,
      eventDate: day(10),
      pickupDate: day(9),
      returnDate: day(11),
      paid: 500,
      bookingNumber: 3,
      lines: [
        InvoiceLine(
          name: 'Gown',
          hsn: '9973',
          rateType: RateType.event,
          rate: 1000,
          days: 1,
          gstRate: 18,
          taxable: 950,
          cgst: inter ? 0 : 85.5,
          sgst: inter ? 0 : 85.5,
          igst: inter ? 171 : 0,
          total: 1121,
        ),
      ],
    );

    Payment pay(PaymentKind k) => Payment(
      id: 5,
      bookingId: 1,
      kind: k,
      amount: 500,
      mode: PayMode.upi,
      note: 'first',
      paidAt: day(3),
    );

    test('an invoice is a real PDF', () async {
      final bytes = await buildInvoicePdf(
        shop: shop,
        invoice: inv(),
        payments: [pay(PaymentKind.advance)],
        depositTotal: 2000,
        depositHeld: 1500,
      );
      expect(bytes.length, greaterThan(1500));
      expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
    });

    test('plain bills, IGST invoices and cancelled ones all build', () async {
      for (final i in [inv(gst: false), inv(inter: true), inv(cancelled: true)]) {
        final bytes = await buildInvoicePdf(shop: shop, invoice: i);
        expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
      }
    });

    test('Tamil names do not break the PDF', () async {
      final bytes = await buildInvoicePdf(
        shop: shop.copyWith(name: 'ராயல் ஆடைகள்'),
        invoice: inv(name: 'அனு'),
      );
      expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
    });

    test('a receipt and a refund voucher build', () async {
      final b = booking();
      for (final k in [PaymentKind.advance, PaymentKind.refund]) {
        final bytes = await buildReceiptPdf(shop: shop, booking: b, payment: pay(k));
        expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
        expect(bytes.length, greaterThan(1000));
      }
    });
  });

  group('plan', () {
    test('free limit states', () {
      const free = Entitlement(tier: Tier.free, enforced: true);
      expect(free.bookingState(0), BookingState.ok);
      expect(free.bookingState(warnAtBookings), BookingState.nearLimit);
      expect(free.bookingState(FreePlan.bookingsPerMonth), BookingState.blocked);
      expect(free.allows(ProFeature.notifications), isFalse);
      const pro = Entitlement(tier: Tier.pro, enforced: true);
      expect(pro.bookingState(99), BookingState.ok);
      expect(pro.allows(ProFeature.unlimitedPhotos), isTrue);
      const launch = Entitlement(tier: Tier.free);
      expect(launch.unlocked, isTrue, reason: 'nothing locked before the paywall');
    });

    test('trial then free, and Pro from a subscription', () {
      final start = DateTime(2027, 3, 1);
      final onTrial = Entitlement.derive(now: DateTime(2027, 3, 3), trialStart: start, enforced: true);
      expect(onTrial.tier, Tier.trial);
      expect(onTrial.trialDaysLeft(DateTime(2027, 3, 3)), 5);
      final after = Entitlement.derive(now: DateTime(2027, 3, 9), trialStart: start, enforced: true);
      expect(after.tier, Tier.free);
      final paid = Entitlement.derive(
        now: DateTime(2027, 3, 9),
        trialStart: start,
        proUntil: DateTime(2027, 4, 9),
        enforced: true,
      );
      expect(paid.tier, Tier.pro);
    });

    test('the clock cannot be moved back to cheat', () {
      final seen = DateTime(2027, 3, 10, 12);
      expect(TimeGuard.effective(DateTime(2027, 3, 1), seen), seen);
      expect(TimeGuard.effective(DateTime(2027, 3, 10, 11, 58), seen), DateTime(2027, 3, 10, 11, 58));
      expect(TimeGuard.effective(DateTime(2027, 3, 11), seen), DateTime(2027, 3, 11));
    });
  });
}
