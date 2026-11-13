import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/restart_widget.dart';
import '../../core/theme.dart';
import '../../data/business_profile.dart';
import '../../data/photo_store.dart';
import '../../data/shops.dart';
import '../../data/staff.dart';
import '../../l10n/strings.dart';

/// First start: the shop's name, what it does and how to reach it.
/// Also used (with [editing]) from Settings to change them later, and (with
/// [newShop]) to add another shop.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.editing, this.newShop = false});

  /// The profile being changed, or null when setting up a new shop.
  final BusinessProfile? editing;

  /// Adding one more shop next to the ones already on the phone.
  final bool newShop;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.editing?.name);
  late final _phone = TextEditingController(text: widget.editing?.phone);
  late final _address = TextEditingController(text: widget.editing?.address);
  late ShopType _type = widget.editing?.type ?? ShopType.costume;
  late String _logo = widget.editing?.logoName ?? '';
  File? _logoFile;

  /// A logo picked in this visit; deleted again if the page is left unsaved.
  String? _picked;
  bool _saved = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    widget.editing?.logoFile().then((f) {
      if (mounted) setState(() => _logoFile = f);
    });
  }

  Future<void> _chooseLogo() async {
    final name = await PhotoStore.pickLogo();
    if (name == null) return;
    // a logo picked earlier in this visit and replaced is not kept
    final earlier = _picked;
    if (earlier != null) {
      await PhotoStore.delete(await PhotoStore.pathOf(earlier));
    }
    final file = File(await PhotoStore.pathOf(name));
    if (!mounted) return;
    setState(() {
      _picked = name;
      _logo = name;
      _logoFile = file;
    });
  }

  void _removeLogo() => setState(() {
    _logo = '';
    _logoFile = null;
  });

  @override
  void dispose() {
    final unsaved = _picked;
    if (!_saved && unsaved != null) {
      PhotoStore.pathOf(unsaved).then(PhotoStore.delete);
    }
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
      logoName: _logo,
    );
    if (widget.newShop) {
      // a new shop: its own details, then open it
      final id = await Shops.create();
      await profile.save(shop: id);
      _saved = true;
      forgetSignedInPerson();
      await Shops.activate(id);
      if (!mounted) return;
      RestartWidget.restart(context);
      return;
    }
    await ref.read(profileProvider.notifier).saveProfile(profile);
    _saved = true;
    // the logo that was replaced or removed is no longer needed
    if (old != null && old.logoName.isNotEmpty && old.logoName != _logo) {
      await PhotoStore.delete(await PhotoStore.pathOf(old.logoName));
    }
    if (mounted && old != null) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.editing != null;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: editing || widget.newShop
          ? AppBar(
              title: Text(
                widget.newShop ? tr('Add a shop') : tr('Shop details'),
              ),
            )
          : null,
      body: AuroraBackground(
        child: SafeArea(
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (!editing && !widget.newShop) ...[
                  const SizedBox(height: 12),
                  Text(
                    tr('Welcome to {app}', {'app': AppInfo.appName}),
                    style: text.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tr('Tell us about your shop. You can change this later.'),
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                ],
                _LogoPicker(
                  file: _logoFile,
                  onChoose: _chooseLogo,
                  onRemove: _logoFile == null ? null : _removeLogo,
                ),
                const SizedBox(height: 18),
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
                  decoration: InputDecoration(
                    labelText: tr('What does your shop do?'),
                  ),
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
                  child: Text(
                    widget.newShop
                        ? tr('Add shop')
                        : editing
                        ? tr('Save')
                        : tr('Get started'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


/// The shop's logo: a preview with buttons to choose or remove it.
class _LogoPicker extends StatelessWidget {
  const _LogoPicker({
    required this.file,
    required this.onChoose,
    this.onRemove,
  });
  final File? file;
  final VoidCallback onChoose;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: file == null
              ? Icon(
                  Icons.storefront_outlined,
                  size: 34,
                  color: theme.colorScheme.onSurfaceVariant,
                )
              : Image.file(
                  file!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.broken_image_outlined),
                ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Brand logo'), style: theme.textTheme.titleSmall),
              Text(
                tr('Printed on your invoices and receipts.'),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: onChoose,
                    icon: const Icon(Icons.image_outlined, size: 18),
                    label: Text(
                      file == null ? tr('Choose logo') : tr('Change'),
                    ),
                  ),
                  if (onRemove != null)
                    TextButton(onPressed: onRemove, child: Text(tr('Remove'))),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
