import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/terms.dart';
import '../../data/business_profile.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../l10n/strings.dart';
import '../common/widgets.dart';

/// Marks "type my own category" in the category list.
const _ownCategory = '\u0000own';

/// Add a new item (or service), or change or remove an existing one.
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
  late final _quantity = TextEditingController(
    text: '${widget.item?.quantity ?? 1}',
  );
  late final _notes = TextEditingController(text: widget.item?.notes);
  late final _hsn = TextEditingController(text: widget.item?.hsn);
  late double _gst = widget.item?.gstRate ??
      ref.read(profileProvider).valueOrNull?.defaultGstRate ??
      18;
  late RateType _rateType = widget.item?.rateType ?? RateType.event;
  late ItemStatus _status = widget.item?.status ?? ItemStatus.active;
  List<String> _used = const [];

  /// true while the person is typing a category of their own.
  bool _typing = false;
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
    for (final c in [
      _name,
      _category,
      _size,
      _rate,
      _deposit,
      _quantity,
      _notes,
      _hsn,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The categories in the list: the ones for this kind of shop, then any
  /// the shop has used before, and the one this item already has.
  List<String> get _options {
    final type = ref.read(profileProvider).valueOrNull?.type;
    final seen = <String>{};
    return [
      for (final c in [
        ...?type?.categories,
        ..._used,
        if (_category.text.trim().isNotEmpty && !_typing) _category.text.trim(),
      ])
        if (seen.add(c)) c,
    ];
  }

  /// What the list shows as chosen.
  String get _choice {
    if (_typing) return _ownCategory;
    final c = _category.text.trim();
    return c.isEmpty ? '' : c;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final service =
        ref.read(profileProvider).valueOrNull?.type.isService ?? false;
    final old = widget.item;
    final qty = int.tryParse(_quantity.text.trim()) ?? 1;
    final item = RentItem(
      id: old?.id,
      uuid: old?.uuid ?? '',
      name: _name.text,
      category: _category.text,
      size: _size.text,
      // a service is charged once per booking
      rateType: service ? RateType.event : _rateType,
      rate: parseAmount(_rate.text),
      deposit: service ? 0 : parseAmount(_deposit.text),
      hsn: _hsn.text,
      gstRate: _gst,
      quantity: service ? 1 : (qty < 1 ? 1 : qty),
      notes: _notes.text,
      status: _status,
      createdAt: old?.createdAt ?? DateTime.now(),
    );
    await ref.read(itemRepoProvider).save(item);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    final terms = ref.read(termsProvider);
    final ok = await confirmRemove(
      context,
      title: terms.removeItemTitle,
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
    final terms = ref.watch(termsProvider);
    final service = terms.service;
    final options = _options;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? terms.editItem : terms.addItem),
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
              decoration: InputDecoration(labelText: terms.itemName),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? tr('Enter the item name')
                  : null,
            ),
            const SizedBox(height: 14),
            // Pick a category from the list, or choose "Type my own" and
            // write one.
            DropdownButtonFormField<String>(
              key: ValueKey('cat-$_typing-${options.length}'),
              initialValue: options.contains(_choice) || _choice.isEmpty ||
                      _choice == _ownCategory
                  ? _choice
                  : '',
              isExpanded: true,
              decoration: InputDecoration(labelText: tr('Category')),
              items: [
                DropdownMenuItem(value: '', child: Text(tr('No category'))),
                for (final c in options)
                  DropdownMenuItem(value: c, child: Text(tr(c))),
                DropdownMenuItem(
                  value: _ownCategory,
                  child: Text(
                    tr('Type my own category...'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              onChanged: (v) => setState(() {
                if (v == _ownCategory) {
                  _typing = true;
                  _category.clear();
                } else {
                  _typing = false;
                  _category.text = v ?? '';
                }
              }),
            ),
            if (_typing) ...[
              const SizedBox(height: 10),
              TextFormField(
                controller: _category,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: tr('Category name')),
              ),
            ],
            if (!service) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _size,
                      decoration: InputDecoration(
                        labelText: tr('Size (optional)'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _quantity,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: tr('Quantity'),
                        helperText: tr('Pieces you have'),
                      ),
                      validator: (v) => (int.tryParse((v ?? '').trim()) ?? 0) < 1
                          ? tr('At least 1')
                          : null,
                    ),
                  ),
                ],
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
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _rate,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: service
                          ? tr('Price (₹)')
                          : tr('Rent for one piece (₹)'),
                    ),
                    validator: (v) => parseAmount(v ?? '') <= 0
                        ? tr('Enter the rent')
                        : null,
                  ),
                ),
                if (!service) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _deposit,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: tr('Deposit for one piece (₹)'),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (ref.watch(profileProvider).valueOrNull?.gstEnabled ??
                false) ...[
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
                          DropdownMenuItem(
                            value: r,
                            child: Text('${amountText(r)}%'),
                          ),
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
                        hintText: service ? '9987' : '9973',
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
