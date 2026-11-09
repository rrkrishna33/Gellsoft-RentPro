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
