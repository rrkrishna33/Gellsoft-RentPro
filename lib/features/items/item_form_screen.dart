import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/business_profile.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../l10n/strings.dart';
import '../common/widgets.dart';

/// Add a new item, or change or remove an existing one.
class ItemFormScreen extends ConsumerStatefulWidget {
  const ItemFormScreen({super.key, this.item});

  /// The item being changed, or null for a new one.
  final RentItem? item;

  @override
  ConsumerState<ItemFormScreen> createState() => _ItemFormScreenState();
}

class _ItemFormScreenState extends ConsumerState<ItemFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item?.name);
  late final _category = TextEditingController(text: widget.item?.category);
  late final _size = TextEditingController(text: widget.item?.size);
  late final _rate = TextEditingController(
    text: widget.item == null ? '' : amountText(widget.item!.rate),
  );
  late final _deposit = TextEditingController(
    text: widget.item == null ? '' : amountText(widget.item!.deposit),
  );
  late final _notes = TextEditingController(text: widget.item?.notes);
  late final _hsn = TextEditingController(text: widget.item?.hsn);
  late double _gst = widget.item?.gstRate ??
      ref.read(profileProvider).valueOrNull?.defaultGstRate ??
      18;
  late RateType _rateType = widget.item?.rateType ?? RateType.event;
  late ItemStatus _status = widget.item?.status ?? ItemStatus.active;
  List<String> _used = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    ref.read(itemRepoProvider).categoriesInUse().then((c) {
      if (mounted) setState(() => _used = c);
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _category, _size, _rate, _deposit, _notes, _hsn]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Categories to offer: the ones for this kind of shop, then any the shop
  /// has typed itself.
  List<String> get _suggestions {
    final type = ref.read(profileProvider).valueOrNull?.type;
    final seen = <String>{};
    return [
      for (final c in [...?type?.categories, ..._used])
        if (seen.add(c)) c,
    ];
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final old = widget.item;
    final item = RentItem(
      id: old?.id,
      uuid: old?.uuid ?? '',
      name: _name.text,
      category: _category.text,
      size: _size.text,
      rateType: _rateType,
      rate: parseAmount(_rate.text),
      deposit: parseAmount(_deposit.text),
      hsn: _hsn.text,
      gstRate: _gst,
      notes: _notes.text,
      status: _status,
      createdAt: old?.createdAt ?? DateTime.now(),
    );
    await ref.read(itemRepoProvider).save(item);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    final ok = await confirmRemove(
      context,
      title: tr('Remove this item?'),
      message: tr(
        'It will no longer be offered for new bookings. Old bookings keep it.',
      ),
    );
    if (!ok || !mounted) return;
    await ref.read(itemRepoProvider).delete(widget.item!.id!);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.item != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? tr('Edit item') : tr('Add item')),
        actions: [
          if (editing)
            IconButton(
              tooltip: tr('Remove'),
              icon: const Icon(Icons.delete_outline),
              onPressed: _remove,
            ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          // room under the last button for the phone's own bar
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: tr('Item name')),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? tr('Enter the item name')
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _category,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: tr('Category')),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final c in _suggestions)
                  ActionChip(
                    label: Text(tr(c)),
                    onPressed: () => setState(() => _category.text = c),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _size,
              decoration: InputDecoration(labelText: tr('Size (optional)')),
            ),
            const SizedBox(height: 18),
            SegmentedButton<RateType>(
              segments: [
                for (final r in RateType.values)
                  ButtonSegment(value: r, label: Text(r.label)),
              ],
              selected: {_rateType},
              onSelectionChanged: (s) => setState(() => _rateType = s.first),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _rate,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(labelText: tr('Rent (₹)')),
                    validator: (v) => parseAmount(v ?? '') <= 0
                        ? tr('Enter the rent')
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _deposit,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(labelText: tr('Deposit (₹)')),
                  ),
                ),
              ],
            ),
            if (ref.watch(profileProvider).valueOrNull?.gstEnabled ?? false) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<double>(
                      initialValue: gstSlabs.contains(_gst) ? _gst : 18,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: tr('GST rate')),
                      items: [
                        for (final r in gstSlabs)
                          DropdownMenuItem(value: r, child: Text('${amountText(r)}%')),
                      ],
                      onChanged: (r) => setState(() => _gst = r ?? _gst),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _hsn,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: tr('SAC / HSN code'),
                        hintText: '9973',
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (editing) ...[
              const SizedBox(height: 14),
              DropdownButtonFormField<ItemStatus>(
                initialValue: _status,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Status')),
                items: [
                  for (final s in ItemStatus.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (s) => setState(() => _status = s ?? _status),
              ),
            ],
            const SizedBox(height: 14),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: tr('Notes (optional)')),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(tr('Save')),
            ),
          ],
        ),
      ),
    );
  }
}
