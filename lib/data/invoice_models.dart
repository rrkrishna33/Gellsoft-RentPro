import 'models.dart';

/// One item on an invoice, as it was when the invoice was made.
class InvoiceLine {
  const InvoiceLine({
    required this.name,
    required this.hsn,
    required this.rateType,
    required this.rate,
    required this.days,
    required this.gstRate,
    required this.taxable,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.total,
  });

  final String name;
  final String hsn;
  final RateType rateType;
  final double rate;

  /// Days charged (1 for a flat per-event rate).
  final int days;
  final double gstRate;
  final double taxable;
  final double cgst;
  final double sgst;
  final double igst;
  final double total;

  double get tax => cgst + sgst + igst;
}

/// An invoice, or a plain bill when GST was off. It keeps its own copy of the
/// customer and every line, so it never changes after it is issued.
class Invoice {
  const Invoice({
    required this.id,
    required this.uuid,
    required this.bookingId,
    required this.prefix,
    required this.number,
    required this.date,
    required this.cancelled,
    required this.customerName,
    required this.customerPhone,
    required this.customerAddress,
    required this.customerGstin,
    required this.supplyState,
    required this.interState,
    required this.gstEnabled,
    required this.taxInclusive,
    required this.discount,
    required this.taxable,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.total,
    required this.eventDate,
    required this.pickupDate,
    required this.returnDate,
    this.paid = 0,
    this.bookingNumber = 0,
    this.lines = const [],
  });

  final int id;
  final String uuid;
  final int bookingId;
  final String prefix;
  final int number;
  final DateTime date;
  final bool cancelled;
  final String customerName;
  final String customerPhone;
  final String customerAddress;
  final String customerGstin;

  /// State code of the place of supply (the customer's state).
  final String supplyState;
  final bool interState;
  final bool gstEnabled;
  final bool taxInclusive;
  final double discount;
  final double taxable;
  final double cgst;
  final double sgst;
  final double igst;
  final double total;
  final DateTime eventDate;
  final DateTime pickupDate;
  final DateTime returnDate;

  /// Rent paid on the booking so far (advance and balance).
  final double paid;
  final int bookingNumber;
  final List<InvoiceLine> lines;

  double get tax => cgst + sgst + igst;

  double get due {
    final v = total - paid;
    return v < 0.005 ? 0 : v;
  }

  /// "RNT-0007", or just "7" when the shop uses no letters.
  String get label => invoiceLabel(prefix, number);

  /// A tax invoice when GST was charged, otherwise a plain bill.
  bool get isTaxInvoice => gstEnabled;
}

String invoiceLabel(String prefix, int number) {
  final n = number.toString().padLeft(4, '0');
  return prefix.isEmpty ? n : '$prefix-$n';
}
