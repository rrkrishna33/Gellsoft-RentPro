import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/constants.dart';
import '../../core/format.dart';
import '../../core/pdf_text.dart';
import '../../data/booking_models.dart';
import '../../data/business_profile.dart';
import '../../data/invoice_models.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';

// The built-in PDF fonts have no rupee glyph, so amounts use "Rs.".
final _num = NumberFormat('#,##0.00', 'en_IN');
String _m(double v) => _num.format(v);
String _q(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

const _accent = PdfColor.fromInt(0xFF1C2C54);
const _ink = PdfColor.fromInt(0xFF1F2937);
const _soft = PdfColor.fromInt(0xFF6B7280);
const _zebra = PdfColor.fromInt(0xFFF8F2DF);
const _line = PdfColor.fromInt(0xFFE2D6B0);

String _stateName(String code) {
  final n = indianStates[code];
  return n == null ? '' : '$code - $n';
}

/// The shop's block at the top: logo, name, address, phone, GSTIN.
List<pw.Widget> _shopBlock(
  PdfTextKit kit,
  BusinessProfile shop,
  bool gst, {
  Uint8List? logo,
}) => [
  if (logo != null)
    pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Image(pw.MemoryImage(logo), height: 44, fit: pw.BoxFit.contain),
    ),
  kit.text(shop.name, size: 18, bold: true, style: const pw.TextStyle(color: _accent)),
  if (shop.address.trim().isNotEmpty)
    kit.text(shop.address, size: 9, style: const pw.TextStyle(color: _soft)),
  if (shop.phone.trim().isNotEmpty)
    kit.text('${tr('Phone')}: ${shop.phone}', size: 9, style: const pw.TextStyle(color: _soft)),
  if (gst && shop.gstin.trim().isNotEmpty)
    kit.text('GSTIN: ${shop.gstin}', size: 9, bold: true),
];

pw.Widget _cell(PdfTextKit kit, String s, {bool bold = false, bool right = false, double size = 9, PdfColor? color}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: kit.text(
        s,
        size: size,
        bold: bold,
        align: right ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(color: color ?? _ink),
      ),
    );

pw.Widget _kv(PdfTextKit kit, String k, String v, {bool bold = false, PdfColor? color}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 2),
  child: pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      kit.text(k, size: 10, bold: bold, style: pw.TextStyle(color: color ?? _ink)),
      kit.text(v, size: 10, bold: bold, style: pw.TextStyle(color: color ?? _ink)),
    ],
  ),
);

/// A tax invoice (or a plain bill when GST was off) as an A4 PDF.
///
/// [payments] are the payments on the booking; [depositTotal] and
/// [depositHeld] are printed as a note, because a deposit is returned and so
/// is not part of the invoice.
Future<Uint8List> buildInvoicePdf({
  required BusinessProfile shop,
  required Invoice invoice,
  List<Payment> payments = const [],
  double depositTotal = 0,
  double depositHeld = 0,

  /// The appointment time of a service booking ("14:30"), printed with the date.
  String eventTime = '',
}) async {
  final kit = await PdfTextKit.load();
  final logo = await shop.logoBytes();
  final service = shop.type.isService;
  final inv = invoice;
  final gst = inv.gstEnabled;
  final doc = pw.Document(
    theme: kit.theme,
    title: inv.label,
    author: shop.name,
  );

  // columns: item, [SAC/HSN], quantity, [days], rate, [taxable, GST %], amount.
  // A service bill (makeup) has no days, since nothing is taken away.
  final headers = [
    service ? tr('Service') : tr('Item'),
    if (gst) 'SAC/HSN',
    tr('Qty'),
    if (!service) tr('Days'),
    tr('Rate'),
    if (gst) ...[tr('Taxable'), 'GST %'],
    tr('Amount'),
  ];

  pw.TableRow row(List<String> cells, {bool head = false, int index = 0}) => pw.TableRow(
    decoration: head
        ? const pw.BoxDecoration(color: _accent)
        : (index.isOdd ? const pw.BoxDecoration(color: _zebra) : null),
    children: [
      for (var i = 0; i < cells.length; i++)
        _cell(
          kit,
          cells[i],
          bold: head,
          right: i != 0 && !(gst && i == 1),
          color: head ? PdfColors.white : null,
        ),
    ],
  );

  final body = <pw.TableRow>[
    row(headers, head: true),
    for (final (i, l) in inv.lines.indexed)
      row(
        [
          l.name,
          if (gst) l.hsn.isEmpty ? '-' : l.hsn,
          '${l.qty}',
          if (!service) l.rateType == RateType.day ? '${l.days}' : '1',
          _m(l.rate),
          if (gst) ...[_m(l.taxable), _q(l.gstRate)],
          _m(l.total),
        ],
        index: i,
      ),
  ];

  // GST rate summary: taxable value and tax for each rate
  final rates = <double, List<InvoiceLine>>{};
  for (final l in inv.lines) {
    rates.putIfAbsent(l.gstRate, () => []).add(l);
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      footer: (c) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: kit.text(
          '${inv.label}  -  ${c.pageNumber}/${c.pagesCount}',
          size: 8,
          style: const pw.TextStyle(color: _soft),
        ),
      ),
      build: (ctx) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: _shopBlock(kit, shop, gst, logo: logo),
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                kit.text(
                  gst
                      ? tr('TAX INVOICE')
                      : service
                      ? tr('BILL')
                      : tr('RENTAL BILL'),
                  size: 16,
                  bold: true,
                  style: const pw.TextStyle(color: _accent),
                ),
                kit.text('${tr('Invoice no')}: ${inv.label}', size: 10, bold: true),
                kit.text('${tr('Date')}: ${dateText(inv.date)}', size: 10),
                kit.text('${tr('Booking')}: #${inv.bookingNumber}', size: 10),
                if (inv.cancelled)
                  kit.text(
                    tr('CANCELLED'),
                    size: 12,
                    bold: true,
                    style: const pw.TextStyle(color: PdfColors.red),
                  ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Divider(color: _line),
        pw.SizedBox(height: 6),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  kit.text(tr('Bill to'), size: 8, style: const pw.TextStyle(color: _soft)),
                  kit.text(inv.customerName, size: 11, bold: true),
                  if (inv.customerPhone.isNotEmpty) kit.text(inv.customerPhone, size: 9),
                  if (inv.customerAddress.isNotEmpty) kit.text(inv.customerAddress, size: 9),
                  if (gst && inv.customerGstin.isNotEmpty)
                    kit.text('GSTIN: ${inv.customerGstin}', size: 9, bold: true),
                  if (gst && _stateName(inv.supplyState).isNotEmpty)
                    kit.text('${tr('Place of supply')}: ${_stateName(inv.supplyState)}', size: 9),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (service) ...[
                  kit.text(tr('Appointment'), size: 8, style: const pw.TextStyle(color: _soft)),
                  kit.text(
                    dateText(inv.eventDate) +
                        (eventTime.isEmpty ? '' : '  $eventTime'),
                    size: 9,
                  ),
                ] else ...[
                  kit.text(tr('Rental dates'), size: 8, style: const pw.TextStyle(color: _soft)),
                  kit.text('${tr('Pickup')}: ${dateText(inv.pickupDate)}', size: 9),
                  kit.text('${tr('Event')}: ${dateText(inv.eventDate)}', size: 9),
                  kit.text('${tr('Return')}: ${dateText(inv.returnDate)}', size: 9),
                ],
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Table(
          border: pw.TableBorder(
            bottom: const pw.BorderSide(color: _line),
            horizontalInside: const pw.BorderSide(color: _line, width: 0.4),
          ),
          columnWidths: {
            for (var c = 0; c < headers.length; c++)
              c: pw.FlexColumnWidth(
                c == 0 ? (gst ? 3.0 : 4.0) : (gst && c == 1 ? 1.3 : 1.2),
              ),
          },
          children: body,
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: gst && rates.isNotEmpty
                  ? pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        kit.text(tr('GST summary'), size: 8, style: const pw.TextStyle(color: _soft)),
                        for (final e in rates.entries)
                          kit.text(
                            '${_q(e.key)}%: ${tr('taxable')} Rs. ${_m(e.value.fold(0.0, (a, l) => a + l.taxable))}, '
                            '${tr('tax')} Rs. ${_m(e.value.fold(0.0, (a, l) => a + l.tax))}',
                            size: 8,
                          ),
                        if (inv.taxInclusive)
                          kit.text(tr('Rents include GST.'), size: 8, style: const pw.TextStyle(color: _soft)),
                      ],
                    )
                  : pw.SizedBox(),
            ),
            pw.SizedBox(
              width: 220,
              child: pw.Column(
                children: [
                  if (inv.discount > 0)
                    _kv(kit, tr('Discount'), '- Rs. ${_m(inv.discount)}'),
                  if (gst) ...[
                    _kv(kit, tr('Taxable value'), 'Rs. ${_m(inv.taxable)}'),
                    if (inv.interState)
                      _kv(kit, 'IGST', 'Rs. ${_m(inv.igst)}')
                    else ...[
                      _kv(kit, 'CGST', 'Rs. ${_m(inv.cgst)}'),
                      _kv(kit, 'SGST', 'Rs. ${_m(inv.sgst)}'),
                    ],
                  ],
                  pw.Divider(color: _line),
                  _kv(kit, tr('Total'), 'Rs. ${_m(inv.total)}', bold: true, color: _accent),
                  if (payments.isNotEmpty) ...[
                    _kv(kit, tr('Paid'), 'Rs. ${_m(inv.paid)}'),
                    _kv(
                      kit,
                      tr('Balance due'),
                      'Rs. ${_m(inv.due)}',
                      bold: true,
                      color: inv.due > 0 ? PdfColors.red800 : PdfColors.green800,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (payments.isNotEmpty) ...[
          pw.SizedBox(height: 12),
          kit.text(tr('Payments'), size: 9, bold: true),
          for (final p in payments)
            kit.text(
              '${dateText(p.paidAt)}  -  ${p.kind.label}  (${p.mode.label}):  '
              '${p.kind == PaymentKind.refund ? '- ' : ''}Rs. ${_m(p.amount)}',
              size: 8,
              style: const pw.TextStyle(color: _soft),
            ),
        ],
        if (depositTotal > 0) ...[
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: _zebra,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: kit.text(
              tr(
                'Refundable deposit: Rs. {total} (held: Rs. {held}). The deposit is returned when the items are back, so it is not part of this invoice.',
                {'total': _m(depositTotal), 'held': _m(depositHeld)},
              ),
              size: 8,
            ),
          ),
        ],
        if (shop.invoiceFooter.trim().isNotEmpty) ...[
          pw.SizedBox(height: 14),
          kit.text(shop.invoiceFooter, size: 9, style: const pw.TextStyle(color: _soft)),
        ],
        pw.SizedBox(height: 16),
        kit.text(tr('Thank you!'), size: 10, bold: true, style: const pw.TextStyle(color: _accent)),
      ],
    ),
  );
  return doc.save();
}

/// A receipt for one payment on a booking (advance, balance, deposit or
/// refund), with where the booking stands afterwards.
Future<Uint8List> buildReceiptPdf({
  required BusinessProfile shop,
  required Booking booking,
  required Payment payment,
}) async {
  final kit = await PdfTextKit.load();
  final logo = await shop.logoBytes();
  final doc = pw.Document(theme: kit.theme, title: 'Receipt #${payment.id}', author: shop.name);
  final refund = payment.kind == PaymentKind.refund;
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(28),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          ..._shopBlock(kit, shop, false, logo: logo),
          pw.SizedBox(height: 10),
          pw.Divider(color: _line),
          pw.SizedBox(height: 6),
          kit.text(
            refund ? tr('REFUND VOUCHER') : tr('PAYMENT RECEIPT'),
            size: 15,
            bold: true,
            style: const pw.TextStyle(color: _accent),
          ),
          pw.SizedBox(height: 8),
          _kv(kit, tr('Receipt no'), '${payment.id}'),
          _kv(kit, tr('Date'), dateText(payment.paidAt)),
          _kv(kit, tr('Booking'), '#${booking.number}'),
          _kv(kit, refund ? tr('Paid to') : tr('Received from'), booking.customerName),
          pw.SizedBox(height: 6),
          pw.Divider(color: _line),
          _kv(kit, tr('For'), payment.kind.label),
          _kv(kit, tr('By'), payment.mode.label),
          if (payment.note.isNotEmpty) _kv(kit, tr('Note'), payment.note),
          pw.SizedBox(height: 6),
          _kv(kit, tr('Amount'), 'Rs. ${_m(payment.amount)}', bold: true, color: _accent),
          pw.SizedBox(height: 10),
          pw.Divider(color: _line),
          kit.text(tr('Where the booking stands'), size: 8, style: const pw.TextStyle(color: _soft)),
          _kv(kit, tr('Rent'), 'Rs. ${_m(booking.payable)}'),
          _kv(kit, tr('Paid'), 'Rs. ${_m(booking.rentPaid)}'),
          _kv(kit, tr('Balance due'), 'Rs. ${_m(booking.balanceDue)}', bold: true),
          if (booking.depositTotal > 0)
            _kv(kit, tr('Deposit held'), 'Rs. ${_m(booking.depositHeld)}'),
          pw.Spacer(),
          kit.text(tr('Thank you!'), size: 10, bold: true, style: const pw.TextStyle(color: _accent)),
        ],
      ),
    ),
  );
  return doc.save();
}
