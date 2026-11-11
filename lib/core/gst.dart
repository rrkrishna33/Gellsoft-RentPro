/// GST calculation for a single invoice line.
class LineTax {
  final double taxable;
  final double cgst;
  final double sgst;
  final double igst;
  const LineTax(this.taxable, this.cgst, this.sgst, this.igst);

  double get totalTax => cgst + sgst + igst;
  double get total => taxable + totalTax;
}

double _r2(double v) => (v * 100).roundToDouble() / 100;

/// [price] is the unit price. When [taxInclusive] is true the price already
/// contains GST. [interState] true => IGST, false => CGST + SGST split.
LineTax calcLineTax({
  required double price,
  required double qty,
  required double discount,
  required double gstRate,
  required bool taxInclusive,
  required bool interState,
}) {
  final gross = price * qty - discount;
  final taxable = taxInclusive ? gross / (1 + gstRate / 100) : gross;
  final tax = taxable * gstRate / 100;
  if (interState) {
    return LineTax(_r2(taxable), 0, 0, _r2(tax));
  }
  final half = _r2(tax / 2);
  return LineTax(_r2(taxable), half, half, 0);
}

/// Intra-state if the business state matches the place of supply.
bool isInterState(String businessStateCode, String? supplyStateCode) =>
    supplyStateCode != null &&
    supplyStateCode.isNotEmpty &&
    supplyStateCode != businessStateCode;

/// Validates the 15 character GSTIN format.
bool isValidGstin(String v) => RegExp(
  r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$',
).hasMatch(v.toUpperCase());
