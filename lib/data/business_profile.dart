import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/booking_math.dart';
import '../core/constants.dart';
import 'photo_store.dart';
import 'shops.dart';

/// The shop: its name, what it rents and how to reach it. Shown on receipts
/// and invoices, together with its GST details.
class BusinessProfile {
  final String name;
  final ShopType type;
  final String phone;
  final String address;

  /// How many days before the event the shop wants the "send the items"
  /// reminder (the default for each new booking).
  final int remindDays;

  /// Whether GST is charged and shown. Off: a plain rental bill.
  final bool gstEnabled;

  /// true: item rents already include GST. false: GST is added on top.
  final bool taxInclusive;

  /// The shop's own GSTIN (15 characters), printed on tax invoices.
  final String gstin;

  /// Two-digit GST state code of the shop, to tell CGST+SGST from IGST.
  final String stateCode;

  /// GST rate (percent) new items start with.
  final double defaultGstRate;

  /// Letters before the invoice number, for example RNT in RNT-0001.
  final String invoicePrefix;

  /// A line at the bottom of every invoice (terms, thanks).
  final String invoiceFooter;

  /// File name of the shop's logo in the app's own folder, or '' for none.
  /// Only the name is kept (the folder differs between phones).
  final String logoName;

  const BusinessProfile({
    required this.name,
    required this.type,
    this.phone = '',
    this.address = '',
    this.remindDays = 2,
    this.gstEnabled = false,
    this.taxInclusive = false,
    this.gstin = '',
    this.stateCode = '',
    this.defaultGstRate = 18,
    this.invoicePrefix = 'RNT',
    this.invoiceFooter = '',
    this.logoName = '',
  });

  GstConfig get gst => GstConfig(enabled: gstEnabled, inclusive: taxInclusive);

  BusinessProfile copyWith({
    String? name,
    ShopType? type,
    String? phone,
    String? address,
    int? remindDays,
    bool? gstEnabled,
    bool? taxInclusive,
    String? gstin,
    String? stateCode,
    double? defaultGstRate,
    String? invoicePrefix,
    String? invoiceFooter,
    String? logoName,
  }) => BusinessProfile(
    name: name ?? this.name,
    type: type ?? this.type,
    phone: phone ?? this.phone,
    address: address ?? this.address,
    remindDays: remindDays ?? this.remindDays,
    gstEnabled: gstEnabled ?? this.gstEnabled,
    taxInclusive: taxInclusive ?? this.taxInclusive,
    gstin: gstin ?? this.gstin,
    stateCode: stateCode ?? this.stateCode,
    defaultGstRate: defaultGstRate ?? this.defaultGstRate,
    invoicePrefix: invoicePrefix ?? this.invoicePrefix,
    invoiceFooter: invoiceFooter ?? this.invoiceFooter,
    logoName: logoName ?? this.logoName,
  );

  /// The logo file, when the shop has one and it is still on the phone.
  Future<File?> logoFile() async {
    if (logoName.isEmpty) return null;
    final f = File(await PhotoStore.pathOf(logoName));
    return await f.exists() ? f : null;
  }

  Future<Uint8List?> logoBytes() async {
    try {
      return await (await logoFile())?.readAsBytes();
    } catch (_) {
      return null; // a missing logo must never stop an invoice
    }
  }

  /// Saves the details of a shop (the open one unless [shop] is given).
  Future<void> save({String? shop}) async {
    final sp = await SharedPreferences.getInstance();
    String k(String n) => Shops.key('b', n, shop: shop);
    await sp.setString(k('name'), name);
    await sp.setString(k('type'), type.name);
    await sp.setString(k('phone'), phone);
    await sp.setString(k('address'), address);
    await sp.setInt(k('remind'), remindDays);
    await sp.setBool(k('gst'), gstEnabled);
    await sp.setBool(k('incl'), taxInclusive);
    await sp.setString(k('gstin'), gstin);
    await sp.setString(k('state'), stateCode);
    await sp.setDouble(k('gstrate'), defaultGstRate);
    await sp.setString(k('prefix'), invoicePrefix);
    await sp.setString(k('footer'), invoiceFooter);
    await sp.setString(k('logo'), logoName);
  }

  /// The details of a shop (the open one unless [shop] is given), or null
  /// when it has none yet.
  static Future<BusinessProfile?> load({String? shop}) async {
    final sp = await SharedPreferences.getInstance();
    String k(String n) => Shops.key('b', n, shop: shop);
    final name = sp.getString(k('name'));
    if (name == null) return null;
    return BusinessProfile(
      name: name,
      type: ShopType.values.firstWhere(
        (t) => t.name == sp.getString(k('type')),
        orElse: () => ShopType.other,
      ),
      phone: sp.getString(k('phone')) ?? '',
      address: sp.getString(k('address')) ?? '',
      remindDays: sp.getInt(k('remind')) ?? 2,
      gstEnabled: sp.getBool(k('gst')) ?? false,
      taxInclusive: sp.getBool(k('incl')) ?? false,
      gstin: sp.getString(k('gstin')) ?? '',
      stateCode: sp.getString(k('state')) ?? '',
      defaultGstRate: sp.getDouble(k('gstrate')) ?? 18,
      invoicePrefix: sp.getString(k('prefix')) ?? 'RNT',
      invoiceFooter: sp.getString(k('footer')) ?? '',
      logoName: sp.getString(k('logo')) ?? '',
    );
  }
}

class ProfileNotifier extends AsyncNotifier<BusinessProfile?> {
  @override
  Future<BusinessProfile?> build() => BusinessProfile.load();

  Future<void> saveProfile(BusinessProfile p) async {
    await p.save();
    state = AsyncData(p);
  }
}

/// The details of all the shops on this phone, by shop id (for the switcher).
/// A shop that has no details yet is left out.
final shopNamesProvider = FutureProvider<Map<String, BusinessProfile>>((
  ref,
) async {
  // reread when the open shop's details change
  ref.watch(profileProvider);
  final out = <String, BusinessProfile>{};
  for (final id in Shops.all) {
    final p = await BusinessProfile.load(shop: id);
    if (p != null) out[id] = p;
  }
  return out;
});

/// The open shop's logo file, or null.
final logoFileProvider = FutureProvider<File?>((ref) async {
  final p = ref.watch(profileProvider).valueOrNull;
  return p?.logoFile();
});

final profileProvider =
    AsyncNotifierProvider<ProfileNotifier, BusinessProfile?>(
      ProfileNotifier.new,
    );
