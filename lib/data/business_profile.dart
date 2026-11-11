import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/booking_math.dart';
import '../core/constants.dart';

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
  );

  Future<void> save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('b_name', name);
    await sp.setString('b_type', type.name);
    await sp.setString('b_phone', phone);
    await sp.setString('b_address', address);
    await sp.setInt('b_remind', remindDays);
    await sp.setBool('b_gst', gstEnabled);
    await sp.setBool('b_incl', taxInclusive);
    await sp.setString('b_gstin', gstin);
    await sp.setString('b_state', stateCode);
    await sp.setDouble('b_gstrate', defaultGstRate);
    await sp.setString('b_prefix', invoicePrefix);
    await sp.setString('b_footer', invoiceFooter);
  }

  static Future<BusinessProfile?> load() async {
    final sp = await SharedPreferences.getInstance();
    final name = sp.getString('b_name');
    if (name == null) return null;
    return BusinessProfile(
      name: name,
      type: ShopType.values.firstWhere(
        (t) => t.name == sp.getString('b_type'),
        orElse: () => ShopType.other,
      ),
      phone: sp.getString('b_phone') ?? '',
      address: sp.getString('b_address') ?? '',
      remindDays: sp.getInt('b_remind') ?? 2,
      gstEnabled: sp.getBool('b_gst') ?? false,
      taxInclusive: sp.getBool('b_incl') ?? false,
      gstin: sp.getString('b_gstin') ?? '',
      stateCode: sp.getString('b_state') ?? '',
      defaultGstRate: sp.getDouble('b_gstrate') ?? 18,
      invoicePrefix: sp.getString('b_prefix') ?? 'RNT',
      invoiceFooter: sp.getString('b_footer') ?? '',
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

final profileProvider =
    AsyncNotifierProvider<ProfileNotifier, BusinessProfile?>(
      ProfileNotifier.new,
    );
