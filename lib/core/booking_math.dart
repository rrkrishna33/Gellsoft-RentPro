import '../data/models.dart';
import 'format.dart';

/// How many calendar days the items are away, counting both the pickup day
/// and the return day (pick up Monday, return Wednesday = 3 days).
int rentalDays(DateTime pickup, DateTime ret) {
  final a = DateTime.utc(pickup.year, pickup.month, pickup.day);
  final b = DateTime.utc(ret.year, ret.month, ret.day);
  final days = b.difference(a).inDays + 1;
  return days < 1 ? 1 : days;
}

/// What one item costs for a booking: its flat rate, or its daily rate times
/// the days away.
double lineAmount(RateType type, double rate, DateTime pickup, DateTime ret) =>
    type == RateType.day ? rate * rentalDays(pickup, ret) : rate;

/// Whether two bookings of the same item clash: their day ranges (pickup to
/// return, both included) share at least one day.
bool rangesOverlap(DateTime aFrom, DateTime aTo, DateTime bFrom, DateTime bTo) {
  final af = dayOf(aFrom), at = dayOf(aTo), bf = dayOf(bFrom), bt = dayOf(bTo);
  return !af.isAfter(bt) && !bf.isAfter(at);
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
