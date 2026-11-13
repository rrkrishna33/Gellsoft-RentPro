import 'package:intl/intl.dart';

import 'constants.dart';

final _inr = NumberFormat.currency(
  locale: 'en_IN',
  symbol: AppInfo.currencySymbol,
  decimalDigits: 2,
);

String money(double v) => _inr.format(v);

/// A date written for lists and receipts, for example "05 Mar 2027".
String dateText(DateTime d) => DateFormat('dd MMM yyyy').format(d);

/// A date and time, for example "05 Mar 2027, 06:30 PM".
String dateTimeText(DateTime d) =>
    DateFormat('dd MMM yyyy, hh:mm a').format(d);

/// The calendar day of [d] at midnight. Bookings store whole days, so two
/// dates on the same day always compare equal.
DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// First moment of the month that holds [d].
DateTime monthStart(DateTime d) => DateTime(d.year, d.month);

/// An appointment time stored as "14:30", written as "02:30 PM". An empty or
/// damaged value gives ''.
String timeText(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length != 2) return '';
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return '';
  return DateFormat('hh:mm a').format(DateTime(2000, 1, 1, h, m));
}
