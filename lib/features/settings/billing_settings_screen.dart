import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/gst.dart';
import '../../core/theme.dart';
import '../../data/business_profile.dart';
import '../../l10n/strings.dart';
import '../common/widgets.dart';

/// GST and invoice settings: whether tax is charged, the shop's GSTIN and
/// state, whether rents include GST, and how invoices are numbered.
class BillingSettingsScreen extends ConsumerStatefulWidget {
  const BillingSettingsScreen({super.key});

  @override
  ConsumerState<BillingSettingsScreen> createState() =>
      _BillingSettingsScreenState();
}

class _BillingSettingsScreenState extends ConsumerState<BillingSettingsScreen> {
  final _form = GlobalKey<FormState>();
  late BusinessProfile _p;
  late final TextEditingController _gstin;
  late final TextEditingController _prefix;
  late final TextEditingController _footer;
  late bool _on;
  late bool _incl;
  late String _state;
  late double _rate;

  @override
  void initState() {
    super.initState();
    _p =
        ref.read(profileProvider).valueOrNull ??
        const BusinessProfile(name: '', type: ShopType.other);
    _gstin = TextEditingController(text: _p.gstin);
    _prefix = TextEditingController(text: _p.invoicePrefix);
    _footer = TextEditingController(text: _p.invoiceFooter);
    _on = _p.gstEnabled;
    _incl = _p.taxInclusive;
    _state = indianStates.containsKey(_p.stateCode) ? _p.stateCode : '';
    _rate = gstSlabs.contains(_p.defaultGstRate) ? _p.defaultGstRate : 18;
  }

  @override
  void dispose() {
    _gstin.dispose();
    _prefix.dispose();
    _footer.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    await ref
        .read(profileProvider.notifier)
        .saveProfile(
          _p.copyWith(
            gstEnabled: _on,
            taxInclusive: _incl,
            gstin: _gstin.text.trim().toUpperCase(),
            stateCode: _state,
            defaultGstRate: _rate,
            invoicePrefix: _prefix.text.trim().toUpperCase(),
            invoiceFooter: _footer.text.trim(),
          ),
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Billing and GST'))),
      body: AuroraBackground(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: SwitchListTile(
                  title: Text(tr('Charge GST')),
                  subtitle: Text(
                    _on
                        ? tr('Invoices are tax invoices with GST.')
                        : tr('Invoices are plain bills, with no tax.'),
                  ),
                  value: _on,
                  onChanged: (v) => setState(() => _on = v),
                ),
              ),
              if (_on) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _gstin,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: tr('Your GSTIN'),
                    helperText: tr('15 characters. Printed on every tax invoice.'),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty || isValidGstin(v.trim()))
                      ? null
                      : tr('This GSTIN does not look right'),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _state,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: tr('Your state'),
                    helperText: tr(
                      'Decides between CGST + SGST and IGST on each invoice.',
                    ),
                  ),
                  items: [
                    DropdownMenuItem(value: '', child: Text(tr('Choose the state'))),
                    for (final e in indianStates.entries)
                      DropdownMenuItem(
                        value: e.key,
                        child: Text(
                          '${e.key} - ${e.value}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _state = v ?? ''),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<double>(
                  initialValue: _rate,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: tr('GST rate for new items'),
                    helperText: tr('You can change it on each item.'),
                  ),
                  items: [
                    for (final r in gstSlabs)
                      DropdownMenuItem(value: r, child: Text('${amountText(r)}%')),
                  ],
                  onChanged: (v) => setState(() => _rate = v ?? _rate),
                ),
                const SizedBox(height: 8),
                Card(
                  child: SwitchListTile(
                    title: Text(tr('Rents already include GST')),
                    subtitle: Text(
                      _incl
                          ? tr('GST is taken out of the rent, so the price does not rise.')
                          : tr('GST is added on top of the rent.'),
                    ),
                    value: _incl,
                    onChanged: (v) => setState(() => _incl = v),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                tr('Invoice'),
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _prefix,
                maxLength: 6,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                ],
                decoration: InputDecoration(
                  labelText: tr('Letters before the number'),
                  helperText: tr('For example RNT gives RNT-0001.'),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _footer,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: tr('Note at the bottom of an invoice'),
                  helperText: tr('Terms, thanks or your bank details.'),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: _save, child: Text(tr('Save'))),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
