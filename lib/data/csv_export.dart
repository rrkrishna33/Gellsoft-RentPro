import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../core/constants.dart' show indianStates;
import 'database.dart';
import 'report_repo.dart';

/// Spreadsheet files an accountant can open in Excel or Google Sheets.
///
/// The `gstr1...` ones follow the sheets of the GSTR-1 return (B2B invoices,
/// B2C small supplies and the HSN summary), so an accountant can copy them
/// across instead of typing the month's invoices again.
enum CsvKind {
  bookings,
  payments,
  invoices,
  gstr1B2b,
  gstr1B2c,
  gstr1Hsn,
  customers,
  items,
}

/// Text cell: quoted when it has a comma, quote or line break, and defused if
/// it could be read as a formula (a name like `=1+1` must not run in Excel).
String csvText(String? value) {
  var s = value ?? '';
  if (s.isNotEmpty && '=+-@\t\r'.contains(s[0])) s = "'$s";
  if (s.contains(',') ||
      s.contains('"') ||
      s.contains('\n') ||
      s.contains('\r')) {
    s = '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

/// Number cell: plain digits with two decimals, no thousands separators.
String csvNum(num value) => value.toStringAsFixed(2);

final _day = DateFormat('yyyy-MM-dd');
String csvDate(DateTime d) => _day.format(d);
String _ms(Object? ms) =>
    csvDate(DateTime.fromMillisecondsSinceEpoch(ms as int));

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;

String _state(String code) {
  final name = indianStates[code];
  return name == null ? code : '$code-$name';
}

/// Builds the CSV text for a period. UTF-8 with a byte-order mark, so Excel
/// shows Tamil names and symbols correctly.
class CsvExport {
  /// [ownState] is the shop's own GST state code: the place of supply for
  /// customers who gave no state.
  CsvExport({this.ownState = ''});
  final String ownState;

  Future<Uint8List> build(CsvKind kind, DateRange r) async {
    final lines = switch (kind) {
      CsvKind.bookings => await bookings(r),
      CsvKind.payments => await payments(r),
      CsvKind.invoices => await invoices(r),
      CsvKind.gstr1B2b => await gstr1B2b(r),
      CsvKind.gstr1B2c => await gstr1B2c(r),
      CsvKind.gstr1Hsn => await gstr1Hsn(r),
      CsvKind.customers => await customers(),
      CsvKind.items => await items(r),
    };
    return Uint8List.fromList(utf8.encode('﻿${lines.join('\r\n')}\r\n'));
  }

  /// A name like `gellsoft-rentpro-bookings-2027-03-01_to_2027-03-31.csv`.
  static String fileName(CsvKind kind, DateRange r) {
    final last = r.to.subtract(const Duration(days: 1));
    return 'gellsoft-rentpro-${kind.name}-${csvDate(r.from)}_to_${csvDate(last)}.csv';
  }

  List<Object> _args(DateRange r) => [
    r.from.millisecondsSinceEpoch,
    r.to.millisecondsSinceEpoch,
  ];

  String _row(List<String> cells) => cells.join(',');

  /// Every booking whose event falls in the period.
  Future<List<String>> bookings(DateRange r) async {
    final d = await AppDatabase.instance.db;
    final rows = await d.rawQuery('''
      SELECT b.*, c.name AS c_name, c.phone AS c_phone,
        COALESCE((SELECT SUM(p.amount) FROM payments p WHERE p.booking_id = b.id
                  AND p.kind IN ('advance','balance')), 0) AS paid,
        COALESCE((SELECT SUM(CASE WHEN p.kind='deposit' THEN p.amount
                                  WHEN p.kind='refund' THEN -p.amount ELSE 0 END)
                  FROM payments p WHERE p.booking_id = b.id), 0) AS held,
        (SELECT GROUP_CONCAT(bi.name, '; ') FROM booking_items bi
           WHERE bi.booking_id = b.id) AS item_names
      FROM bookings b JOIN customers c ON c.id = b.customer_id
      WHERE b.deleted = 0 AND b.event_date >= ? AND b.event_date < ?
      ORDER BY b.event_date, b.number
    ''', _args(r));
    return [
      _row([
        'Booking no', 'Customer', 'Phone', 'Event date', 'Pickup date',
        'Return date', 'Status', 'Items', 'Rent', 'Discount', 'GST', 'Total',
        'Paid', 'Balance', 'Deposit', 'Deposit held', 'Notes',
      ]),
      for (final b in rows)
        _row([
          '${b['number']}',
          csvText(b['c_name'] as String?),
          csvText(b['c_phone'] as String?),
          _ms(b['event_date']),
          _ms(b['pickup_date']),
          _ms(b['return_date']),
          csvText(b['status'] as String?),
          csvText(b['item_names'] as String?),
          csvNum(_d(b['rent_total'])),
          csvNum(_d(b['discount'])),
          csvNum(_d(b['tax_total'])),
          csvNum(_d(b['payable'])),
          csvNum(_d(b['paid'])),
          csvNum(_d(b['payable']) - _d(b['paid']) < 0.005
              ? 0
              : _d(b['payable']) - _d(b['paid'])),
          csvNum(_d(b['deposit_total'])),
          csvNum(_d(b['held'])),
          csvText(b['notes'] as String?),
        ]),
    ];
  }

  /// Every payment taken or given back in the period.
  Future<List<String>> payments(DateRange r) async {
    final d = await AppDatabase.instance.db;
    final rows = await d.rawQuery('''
      SELECT p.*, b.number AS b_number, c.name AS c_name
      FROM payments p JOIN bookings b ON b.id = p.booking_id
        JOIN customers c ON c.id = b.customer_id
      WHERE b.deleted = 0 AND p.paid_at >= ? AND p.paid_at < ?
      ORDER BY p.paid_at, p.id
    ''', _args(r));
    return [
      _row(['Date', 'Booking no', 'Customer', 'Type', 'Mode', 'Amount', 'Note']),
      for (final p in rows)
        _row([
          _ms(p['paid_at']),
          '${p['b_number']}',
          csvText(p['c_name'] as String?),
          csvText(p['kind'] as String?),
          csvText(p['mode'] as String?),
          // a refund goes out, so it is negative in the sheet
          csvNum(p['kind'] == 'refund' ? -_d(p['amount']) : _d(p['amount'])),
          csvText(p['note'] as String?),
        ]),
    ];
  }

  /// The sales register: every invoice and bill of the period.
  Future<List<String>> invoices(DateRange r) async {
    final d = await AppDatabase.instance.db;
    final rows = await d.rawQuery('''
      SELECT i.*, b.number AS b_number,
        COALESCE((SELECT SUM(p.amount) FROM payments p WHERE p.booking_id = i.booking_id
                  AND p.kind IN ('advance','balance')), 0) AS paid
      FROM invoices i JOIN bookings b ON b.id = i.booking_id
      WHERE i.deleted = 0 AND i.invoice_date >= ? AND i.invoice_date < ?
      ORDER BY i.invoice_date, i.number
    ''', _args(r));
    return [
      _row([
        'Invoice no', 'Date', 'Booking no', 'Customer', 'GSTIN',
        'Place of supply', 'Type', 'Status', 'Taxable value', 'CGST', 'SGST',
        'IGST', 'Total', 'Paid', 'Balance',
      ]),
      for (final i in rows)
        _row([
          csvText(_label(i)),
          _ms(i['invoice_date']),
          '${i['b_number']}',
          csvText(i['cust_name'] as String?),
          csvText(i['cust_gstin'] as String?),
          csvText(_state((i['supply_state'] as String?) ?? '')),
          i['gst_enabled'] == 1 ? 'Tax invoice' : 'Bill',
          i['status'] == 'cancelled' ? 'Cancelled' : 'Active',
          csvNum(_d(i['taxable'])),
          csvNum(_d(i['cgst'])),
          csvNum(_d(i['sgst'])),
          csvNum(_d(i['igst'])),
          csvNum(_d(i['total'])),
          csvNum(_d(i['paid'])),
          csvNum(_d(i['total']) - _d(i['paid']) < 0.005
              ? 0
              : _d(i['total']) - _d(i['paid'])),
        ]),
    ];
  }

  String _label(Map<String, Object?> i) {
    final n = (i['number'] as int).toString().padLeft(4, '0');
    final p = (i['prefix'] as String?) ?? '';
    return p.isEmpty ? n : '$p-$n';
  }

  /// GSTR-1 B2B: one row per invoice and GST rate, for customers with a GSTIN.
  Future<List<String>> gstr1B2b(DateRange r) async {
    final d = await AppDatabase.instance.db;
    final rows = await d.rawQuery('''
      SELECT i.*, ii.gst_rate AS rate, SUM(ii.taxable) AS taxable_r,
             SUM(ii.igst) AS igst_r, SUM(ii.cgst) AS cgst_r, SUM(ii.sgst) AS sgst_r
      FROM invoices i JOIN invoice_items ii ON ii.invoice_id = i.id
      WHERE i.deleted = 0 AND i.status = 'active' AND i.gst_enabled = 1
        AND i.cust_gstin != '' AND i.invoice_date >= ? AND i.invoice_date < ?
      GROUP BY i.id, ii.gst_rate ORDER BY i.invoice_date, i.number
    ''', _args(r));
    return [
      _row([
        'GSTIN/UIN of Recipient', 'Receiver Name', 'Invoice Number',
        'Invoice date', 'Invoice Value', 'Place Of Supply', 'Reverse Charge',
        'Invoice Type', 'Rate', 'Taxable Value', 'IGST', 'CGST', 'SGST',
      ]),
      for (final i in rows)
        _row([
          csvText(i['cust_gstin'] as String?),
          csvText(i['cust_name'] as String?),
          csvText(_label(i)),
          _ms(i['invoice_date']),
          csvNum(_d(i['total'])),
          csvText(_state(_supply(i))),
          'N',
          'Regular',
          csvNum(_d(i['rate'])),
          csvNum(_d(i['taxable_r'])),
          csvNum(_d(i['igst_r'])),
          csvNum(_d(i['cgst_r'])),
          csvNum(_d(i['sgst_r'])),
        ]),
    ];
  }

  String _supply(Map<String, Object?> i) {
    final s = (i['supply_state'] as String?) ?? '';
    return s.isEmpty ? ownState : s;
  }

  /// GSTR-1 B2C (small): totals by place of supply and rate, for invoices
  /// without a customer GSTIN.
  Future<List<String>> gstr1B2c(DateRange r) async {
    final d = await AppDatabase.instance.db;
    final rows = await d.rawQuery('''
      SELECT CASE WHEN i.supply_state = '' THEN ? ELSE i.supply_state END AS pos,
             ii.gst_rate AS rate, SUM(ii.taxable) AS taxable_r,
             SUM(ii.igst) AS igst_r, SUM(ii.cgst) AS cgst_r, SUM(ii.sgst) AS sgst_r
      FROM invoices i JOIN invoice_items ii ON ii.invoice_id = i.id
      WHERE i.deleted = 0 AND i.status = 'active' AND i.gst_enabled = 1
        AND i.cust_gstin = '' AND i.invoice_date >= ? AND i.invoice_date < ?
      GROUP BY pos, ii.gst_rate ORDER BY pos, ii.gst_rate
    ''', [ownState, ..._args(r)]);
    return [
      _row([
        'Type', 'Place Of Supply', 'Rate', 'Taxable Value', 'IGST', 'CGST', 'SGST',
      ]),
      for (final i in rows)
        _row([
          'OE',
          csvText(_state(i['pos'] as String)),
          csvNum(_d(i['rate'])),
          csvNum(_d(i['taxable_r'])),
          csvNum(_d(i['igst_r'])),
          csvNum(_d(i['cgst_r'])),
          csvNum(_d(i['sgst_r'])),
        ]),
    ];
  }

  /// GSTR-1 HSN summary: what was supplied under each SAC/HSN code and rate.
  Future<List<String>> gstr1Hsn(DateRange r) async {
    final d = await AppDatabase.instance.db;
    final rows = await d.rawQuery('''
      SELECT ii.hsn AS hsn, ii.gst_rate AS rate, COUNT(*) AS qty,
             SUM(ii.total) AS total_v, SUM(ii.taxable) AS taxable_r,
             SUM(ii.igst) AS igst_r, SUM(ii.cgst) AS cgst_r, SUM(ii.sgst) AS sgst_r
      FROM invoices i JOIN invoice_items ii ON ii.invoice_id = i.id
      WHERE i.deleted = 0 AND i.status = 'active' AND i.gst_enabled = 1
        AND i.invoice_date >= ? AND i.invoice_date < ?
      GROUP BY ii.hsn, ii.gst_rate ORDER BY ii.hsn, ii.gst_rate
    ''', _args(r));
    return [
      _row([
        'HSN', 'Description', 'UQC', 'Total Quantity', 'Total Value',
        'Taxable Value', 'Rate', 'IGST', 'CGST', 'SGST',
      ]),
      for (final i in rows)
        _row([
          csvText(i['hsn'] as String?),
          'Rental of goods',
          'OTH-OTHERS',
          '${i['qty']}',
          csvNum(_d(i['total_v'])),
          csvNum(_d(i['taxable_r'])),
          csvNum(_d(i['rate'])),
          csvNum(_d(i['igst_r'])),
          csvNum(_d(i['cgst_r'])),
          csvNum(_d(i['sgst_r'])),
        ]),
    ];
  }

  /// All customers with what they have been billed and still owe.
  Future<List<String>> customers() async {
    final d = await AppDatabase.instance.db;
    final rows = await d.rawQuery('''
      SELECT c.*, COUNT(b.id) AS n, COALESCE(SUM(b.payable), 0) AS billed,
        COALESCE(SUM(b.payable - COALESCE((SELECT SUM(p.amount) FROM payments p
          WHERE p.booking_id = b.id AND p.kind IN ('advance','balance')), 0)), 0) AS due
      FROM customers c LEFT JOIN bookings b
        ON b.customer_id = c.id AND b.deleted = 0 AND b.status != 'cancelled'
      WHERE c.deleted = 0 GROUP BY c.id ORDER BY c.name COLLATE NOCASE
    ''');
    return [
      _row([
        'Name', 'Phone', 'Address', 'GSTIN', 'State', 'Bookings', 'Billed', 'Balance',
      ]),
      for (final c in rows)
        _row([
          csvText(c['name'] as String?),
          csvText(c['phone'] as String?),
          csvText(c['address'] as String?),
          csvText(c['gstin'] as String?),
          csvText(_state((c['state_code'] as String?) ?? '')),
          '${c['n']}',
          csvNum(_d(c['billed'])),
          csvNum(_d(c['due']) < 0.005 ? 0 : _d(c['due'])),
        ]),
    ];
  }

  /// All items with how often they were booked in the period and what they earned.
  Future<List<String>> items(DateRange r) async {
    final d = await AppDatabase.instance.db;
    final rows = await d.rawQuery('''
      SELECT it.*,
        (SELECT COUNT(*) FROM booking_items bi JOIN bookings b ON b.id = bi.booking_id
           WHERE bi.item_id = it.id AND b.deleted = 0 AND b.status != 'cancelled'
             AND b.event_date >= ? AND b.event_date < ?) AS times,
        (SELECT COALESCE(SUM(bi.taxable + bi.tax), 0) FROM booking_items bi
           JOIN bookings b ON b.id = bi.booking_id
           WHERE bi.item_id = it.id AND b.deleted = 0 AND b.status != 'cancelled'
             AND b.event_date >= ? AND b.event_date < ?) AS earned
      FROM items it WHERE it.deleted = 0 ORDER BY it.category COLLATE NOCASE, it.name COLLATE NOCASE
    ''', [..._args(r), ..._args(r)]);
    return [
      _row([
        'Name', 'Category', 'Size', 'Rate type', 'Rate', 'Deposit', 'GST %',
        'HSN', 'Status', 'Times booked', 'Earned',
      ]),
      for (final i in rows)
        _row([
          csvText(i['name'] as String?),
          csvText(i['category'] as String?),
          csvText(i['size'] as String?),
          csvText(i['rate_type'] as String?),
          csvNum(_d(i['rate'])),
          csvNum(_d(i['deposit'])),
          csvNum(_d(i['gst_rate'])),
          csvText(i['hsn'] as String?),
          csvText(i['status'] as String?),
          '${i['times']}',
          csvNum(_d(i['earned'])),
        ]),
    ];
  }
}
