import '../data/models.dart';
import '../l10n/strings.dart';
import 'format.dart';

/// How many calendar days the items are away, counting both the pickup day
/// and the return day (pick up Monday, return Wednesday = 3 days).
int rentalDays(DateTime pickup, DateTime ret) {
  final a = DateTime.utc(pickup.year, pickup.month, pickup.day);
  final b = DateTime.utc(ret.year, ret.month, ret.day);
  final days = b.difference(a).inDays + 1;
  return days < 1 ? 1 : days;
}

/// Minutes after midnight for a time written "14:30", or null when it is not a
/// valid time (an empty text means no time was set).
int? minutesOfTime(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
  return h * 60 + m;
}

/// The moment a day and a "14:30" time make. An unset time is midnight.
DateTime momentOf(DateTime day, String hhmm) {
  final m = minutesOfTime(hhmm) ?? 0;
  return DateTime(day.year, day.month, day.day, m ~/ 60, m % 60);
}

/// Whether both times are set and the end is after the start (the dates are
/// the pickup and return days).
bool validHourlySpan(
  DateTime pickup,
  String pickupTime,
  DateTime ret,
  String returnTime,
) {
  if (minutesOfTime(pickupTime) == null || minutesOfTime(returnTime) == null) {
    return false;
  }
  return momentOf(ret, returnTime).isAfter(momentOf(pickup, pickupTime));
}

/// Hours an hourly booking is charged for: the time between pickup and return,
/// rounded up to a whole hour (2 h 10 min is 3 hours), and never less than one.
int rentalHours(
  DateTime pickup,
  String pickupTime,
  DateTime ret,
  String returnTime,
) {
  final a = momentOf(pickup, pickupTime);
  final b = momentOf(ret, returnTime);
  final minutes = b.difference(a).inMinutes;
  if (minutes <= 0) return 1;
  return (minutes + 59) ~/ 60;
}

/// "3 hours" / "1 hour", for lines and messages.
String hoursText(int hours) =>
    hours == 1 ? tr('1 hour') : tr('{n} hours', {'n': hours});

/// What [days] days cost at a daily [rate] when the item also has a [week]
/// rate (7 days) and a [month] rate (30 days). Whole months and weeks are
/// charged at their own rate, and what is left over is charged by the day but
/// never more than the next longer rate (6 days cost at most one week).
double dayCharge(int days, double rate, {double week = 0, double month = 0}) {
  double upToWeeks(int d) {
    if (week <= 0) return d * rate;
    final r = d % 7 * rate;
    return d ~/ 7 * week + (r < week ? r : week);
  }

  if (month > 0) {
    final rest = upToWeeks(days % 30);
    return days ~/ 30 * month + (rest < month ? rest : month);
  }
  return upToWeeks(days);
}

/// What one item costs for a booking: its flat rate, its daily rate (or its
/// weekly and monthly rates) for the days away, or its hourly rate times
/// [hours].
double lineAmount(
  RateType type,
  double rate,
  DateTime pickup,
  DateTime ret, {
  int hours = 1,
  double weekRate = 0,
  double monthRate = 0,
}) => switch (type) {
  RateType.day => dayCharge(
    rentalDays(pickup, ret),
    rate,
    week: weekRate,
    month: monthRate,
  ),
  RateType.hour => rate * hours,
  RateType.event => rate,
};

/// Whether two bookings of the same item clash: their day ranges (pickup to
/// return, both included) share at least one day.
bool rangesOverlap(DateTime aFrom, DateTime aTo, DateTime bFrom, DateTime bTo) {
  final af = dayOf(aFrom), at = dayOf(aTo), bf = dayOf(bFrom), bt = dayOf(bTo);
  return !af.isAfter(bt) && !bf.isAfter(at);
}

/// The time an item is kept for a booking, from [from] up to but not including
/// [to] (so one booking can start the moment another ends). An hourly item
/// with both times set is kept from the pickup moment to the return moment;
/// anything else is kept for whole days, pickup day to return day.
({DateTime from, DateTime to}) heldWindow({
  required bool hourly,
  required DateTime pickup,
  required DateTime ret,
  String pickupTime = '',
  String returnTime = '',
}) {
  if (hourly && validHourlySpan(pickup, pickupTime, ret, returnTime)) {
    return (from: momentOf(pickup, pickupTime), to: momentOf(ret, returnTime));
  }
  return (
    from: dayOf(pickup),
    to: DateTime(ret.year, ret.month, ret.day + 1),
  );
}

/// Whether GST is charged, and whether the rates already contain it.
class GstConfig {
  const GstConfig({this.enabled = false, this.inclusive = false});
  final bool enabled;

  /// true: item rates already include GST; false: GST is added on top.
  final bool inclusive;

  static const off = GstConfig();
}

double r2(double v) => (v * 100).roundToDouble() / 100;

/// One item's share of the bill: the amount charged for the booked days, its
/// share of the discount, and the tax on what is left.
class LineMoney {
  const LineMoney({
    required this.amount,
    required this.discount,
    required this.taxable,
    required this.tax,
  });
  final double amount;
  final double discount;
  final double taxable;
  final double tax;

  /// What the customer pays for this item.
  double get total => r2(taxable + tax);
}

/// Works out every line. The discount is split between the lines in
/// proportion to their amounts (the last line takes the rounding left over, so
/// the shares always add up to the discount). With [GstConfig.enabled] each
/// line is taxed at its own rate; with [GstConfig.inclusive] the tax is taken
/// out of the amount instead of added to it.
List<LineMoney> splitMoney({
  required List<double> amounts,
  required List<double> gstRates,
  required double discount,
  required GstConfig gst,
}) {
  assert(amounts.length == gstRates.length);
  final sum = amounts.fold(0.0, (a, b) => a + b);
  final out = <LineMoney>[];
  var given = 0.0;
  for (var i = 0; i < amounts.length; i++) {
    final last = i == amounts.length - 1;
    final share = sum <= 0
        ? 0.0
        : (last ? r2(discount - given) : r2(discount * amounts[i] / sum));
    given += share;
    final gross = r2(amounts[i] - share);
    if (!gst.enabled || gstRates[i] <= 0) {
      out.add(LineMoney(amount: amounts[i], discount: share, taxable: gross, tax: 0));
    } else if (gst.inclusive) {
      final taxable = r2(gross / (1 + gstRates[i] / 100));
      out.add(LineMoney(
        amount: amounts[i],
        discount: share,
        taxable: taxable,
        tax: r2(gross - taxable),
      ));
    } else {
      out.add(LineMoney(
        amount: amounts[i],
        discount: share,
        taxable: gross,
        tax: r2(gross * gstRates[i] / 100),
      ));
    }
  }
  return out;
}
