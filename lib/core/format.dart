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

/// The calendar day of [d] at midnight. Bookings store whole days, so two
/// dates on the same day always compare equal.
DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// First moment of the month that holds [d].
DateTime monthStart(DateTime d) => DateTime(d.year, d.month);
