import '../l10n/strings.dart';
import 'models.dart';

/// Where a booking is in its life: booked, items out, items back, or called off.
enum BookingStatus {
  booked('booked', 'Booked'),
  pickedUp('picked_up', 'Picked up'),
  returned('returned', 'Returned'),
  cancelled('cancelled', 'Cancelled');

  final String db;

  /// English wording; also the translation key (see `tr`).
  final String en;
  const BookingStatus(this.db, this.en);

  String get label => tr(en);

  /// The wording for a service booking: finished is "Done", not "Returned".
  String labelFor({required bool service}) =>
      service && this == returned ? tr('Done') : tr(en);

  /// The items are, or will be, out of the shop: they block other bookings.
  bool get holdsItems => this == booked || this == pickedUp;

  static BookingStatus fromDb(String? v) =>
      values.firstWhere((s) => s.db == v, orElse: () => BookingStatus.booked);
}

/// What a payment is for. Advance and balance are rent; deposit is money held
/// until the items come back; refund is money handed back.
enum PaymentKind {
  advance('Advance'),
  balance('Balance'),
  deposit('Deposit'),
  refund('Refund');

  final String en;
  const PaymentKind(this.en);

  String get label => tr(en);

  bool get isRent => this == advance || this == balance;

  static PaymentKind fromName(String? v) =>
      values.firstWhere((k) => k.name == v, orElse: () => PaymentKind.advance);
}

enum PayMode {
  cash('Cash'),
  upi('UPI'),
  card('Card'),
  bank('Bank transfer');

  final String en;
  const PayMode(this.en);

  String get label => tr(en);

  static PayMode fromName(String? v) =>
      values.firstWhere((m) => m.name == v, orElse: () => PayMode.cash);
}

/// One item on a booking, as it was booked (name and rate are kept even if the
/// item is later changed or removed).
class BookingLine {
  final int itemId;
  final String name;
  final RateType rateType;

  /// How many of the item were booked.
  final int qty;

  /// The rate and deposit of ONE piece.
  final double rate;
  final double deposit;

  /// What this line came to for the booked days and all [qty] pieces, before
  /// discount and tax.
  final double amount;
  final String hsn;
  final double gstRate;

  /// After this item's share of the discount; GST is on top of this unless
  /// the rates include it.
  final double taxable;
  final double tax;

  const BookingLine({
    required this.itemId,
    required this.name,
    required this.rateType,
    required this.rate,
    required this.deposit,
    required this.amount,
    this.qty = 1,
    this.hsn = '',
    this.gstRate = 0,
    double? taxable,
    this.tax = 0,
  }) : taxable = taxable ?? amount;

  /// What the customer pays for this item.
  double get total => ((taxable + tax) * 100).roundToDouble() / 100;

  /// The deposit for all pieces on this line.
  double get depositAmount => deposit * qty;

  /// The name with the quantity when more than one: "Chair x 10".
  String get label => qty > 1 ? '$name × $qty' : name;
}

class Payment {
  final int id;
  final int bookingId;
  final PaymentKind kind;
  final double amount;
  final PayMode mode;
  final String note;
  final DateTime paidAt;

  const Payment({
    required this.id,
    required this.bookingId,
    required this.kind,
    required this.amount,
    required this.mode,
    required this.note,
    required this.paidAt,
  });
}

class BookingPhoto {
  final int id;
  final int bookingId;

  /// 'pickup', 'return' or 'other'.
  final String stage;

  /// A file in the app's own folder.
  final String path;
  final DateTime createdAt;

  const BookingPhoto({
    required this.id,
    required this.bookingId,
    required this.stage,
    required this.path,
    required this.createdAt,
  });
}

/// A booking with everything shown on its page.
class Booking {
  final int id;
  final String uuid;
  final int number;
  final int customerId;
  final String customerName;
  final String customerPhone;
  final DateTime eventDate;
  final DateTime pickupDate;
  final DateTime returnDate;
  final BookingStatus status;
  final double rentTotal;
  final double depositTotal;
  final double discount;

  /// GST on the whole booking (inside the total when rates include GST).
  final double taxTotal;

  /// What the customer pays for the rent: the lines, less the discount, with
  /// GST. Deposit is not part of it.
  final double payable;
  final String notes;

  /// Days before the event to remind the owner to send the items.
  final int remindDays;

  /// The appointment time ("14:30") for a service booking, or '' when the
  /// booking has no time.
  final String eventTime;

  /// Who made the booking (the signed-in person), or '' when staff logins
  /// are off.
  final String createdBy;
  final DateTime createdAt;
  final List<BookingLine> lines;
  final List<Payment> payments;
  final List<BookingPhoto> photos;

  const Booking({
    required this.id,
    required this.uuid,
    required this.number,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.eventDate,
    required this.pickupDate,
    required this.returnDate,
    required this.status,
    required this.rentTotal,
    required this.depositTotal,
    required this.discount,
    required this.notes,
    this.taxTotal = 0,
    double? payable,
    required this.remindDays,
    required this.createdAt,
    this.eventTime = '',
    this.createdBy = '',
    this.lines = const [],
    this.payments = const [],
    this.photos = const [],
  }) : payable = payable ?? rentTotal - discount;

  double _sum(bool Function(Payment) test) =>
      payments.where(test).fold(0.0, (a, p) => a + p.amount);

  /// What the customer owes for the rent (after discount, with GST).
  double get rentNet => payable;

  /// Rent paid so far (advance and balance).
  double get rentPaid => _sum((p) => p.kind.isRent);

  /// Rent still to collect. Never negative.
  double get balanceDue {
    final v = rentNet - rentPaid;
    return v < 0.005 ? 0 : v;
  }

  double get depositTaken => _sum((p) => p.kind == PaymentKind.deposit);
  double get depositRefunded => _sum((p) => p.kind == PaymentKind.refund);

  /// Deposit the shop is holding right now.
  double get depositHeld {
    final v = depositTaken - depositRefunded;
    return v < 0.005 ? 0 : v;
  }

  /// Deposit the customer still has to hand over.
  double get depositDue {
    final v = depositTotal - depositTaken;
    return v < 0.005 ? 0 : v;
  }

  /// The items should be back by now but are still out.
  bool isOverdue(DateTime today) =>
      status == BookingStatus.pickedUp && returnDate.isBefore(today);
}
