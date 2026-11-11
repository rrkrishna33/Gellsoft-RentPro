import '../l10n/strings.dart';

class AppInfo {
  static const company = 'GellSoft';
  static const appName = 'GellSoft RentPro';
  static const website = 'https://www.gellsoft.com';
  static const supportEmail = 'support@gellsoft.com';
  static const currencySymbol = '₹';

  /// Keep in step with `version:` in pubspec.yaml (without the build number).
  static const version = '0.1.0';
}

/// What the shop rents out. It only picks the starting item categories and
/// the wording hints; every shop can add its own categories later.
enum ShopType {
  costume('Costume / Dress rental', [
    'Sherwani',
    'Lehenga',
    'Saree',
    'Gown',
    'Jewellery',
    'Accessories',
  ]),
  equipment('Equipment / Tools rental', [
    'Sound system',
    'Camera',
    'Lights',
    'Tools',
    'Other',
  ]),
  decor('Party / Event decor', [
    'Stage',
    'Chairs and tables',
    'Flowers and decor',
    'Utensils',
    'Other',
  ]),
  vehicle('Vehicle / Bike rental', ['Bike', 'Car', 'Cycle', 'Other']),
  other('Other', ['General']);

  /// English name; also the translation key (see `tr`).
  final String en;

  /// Item categories offered first for this kind of shop (translation keys).
  final List<String> categories;
  const ShopType(this.en, this.categories);

  String get label => tr(en);
}

/// Standard GST slabs in India.
const gstSlabs = <double>[0, 5, 12, 18, 28];

const indianStates = <String, String>{
  '01': 'Jammu & Kashmir',
  '02': 'Himachal Pradesh',
  '03': 'Punjab',
  '04': 'Chandigarh',
  '05': 'Uttarakhand',
  '06': 'Haryana',
  '07': 'Delhi',
  '08': 'Rajasthan',
  '09': 'Uttar Pradesh',
  '10': 'Bihar',
  '11': 'Sikkim',
  '12': 'Arunachal Pradesh',
  '13': 'Nagaland',
  '14': 'Manipur',
  '15': 'Mizoram',
  '16': 'Tripura',
  '17': 'Meghalaya',
  '18': 'Assam',
  '19': 'West Bengal',
  '20': 'Jharkhand',
  '21': 'Odisha',
  '22': 'Chhattisgarh',
  '23': 'Madhya Pradesh',
  '24': 'Gujarat',
  '26': 'Dadra & Nagar Haveli and Daman & Diu',
  '27': 'Maharashtra',
  '29': 'Karnataka',
  '30': 'Goa',
  '31': 'Lakshadweep',
  '32': 'Kerala',
  '33': 'Tamil Nadu',
  '34': 'Puducherry',
  '35': 'Andaman & Nicobar Islands',
  '36': 'Telangana',
  '37': 'Andhra Pradesh',
  '38': 'Ladakh',
};
