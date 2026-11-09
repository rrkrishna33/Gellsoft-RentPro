import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../data/business_profile.dart';
import '../../l10n/strings.dart';

/// First start: the shop's name, what it rents and how to reach it.
/// Also used (with [editing]) from Settings to change them later.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.editing});

  /// The profile being changed, or null when setting up a new shop.
  final BusinessProfile? editing;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.editing?.name);
  late final _phone = TextEditingController(text: widget.editing?.phone);
  late final _address = TextEditingController(text: widget.editing?.address);
  late ShopType _type = widget.editing?.type ?? ShopType.costume;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final old = widget.editing;
    final profile = (old ?? BusinessProfile(name: '', type: _type)).copyWith(
      name: _name.text.trim(),
      type: _type,
      phone: _phone.text.trim(),
      address: _address.text.trim(),
    );
    await ref.read(profileProvider.notifier).saveProfile(profile);
    if (mounted && old != null) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.editing != null;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: editing ? AppBar(title: Text(tr('Shop details'))) : null,
      body: RentBackground(
        child: SafeArea(
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (!editing) ...[
                  const SizedBox(height: 12),
                  Text(
                    tr('Welcome to {app}', {'app': AppInfo.appName}),
                    style: text.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Palette.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tr('Tell us about your shop. You can change this later.'),
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                ],
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: tr('Shop name')),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? tr('Enter the shop name')
                      : null,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<ShopType>(
                  initialValue: _type,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('What do you rent?')),
                  items: [
                    for (final t in ShopType.values)
                      DropdownMenuItem(value: t, child: Text(t.label)),
                  ],
                  onChanged: (t) => setState(() => _type = t ?? _type),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: tr('Phone')),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _address,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: tr('Address')),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(editing ? tr('Save') : tr('Get started')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
