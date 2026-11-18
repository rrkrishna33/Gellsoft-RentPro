import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/format.dart';
import '../../core/terms.dart';
import '../../data/business_profile.dart';
import '../../data/booking_repo.dart' show BookingException;
import '../../data/models.dart';
import '../../data/photo_store.dart';
import '../../data/repositories.dart';
import '../../l10n/strings.dart';
import '../../subscription/entitlement.dart';
import '../../subscription/gates.dart';
import '../../subscription/plan.dart';
import '../../subscription/pro_prompt.dart';
import '../common/widgets.dart';
import 'item_photo_strip.dart';
import 'item_repairs_screen.dart';

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
  late final _minHours = TextEditingController(
    text: '${widget.item?.minHours ?? 1}',
  );
  late final _notes = TextEditingController(text: widget.item?.notes);
  late final _hsn = TextEditingController(text: widget.item?.hsn);
  late double _gst = widget.item?.gstRate ??
      ref.read(profileProvider).valueOrNull?.defaultGstRate ??
      18;
  late RateType _rateType =
      widget.item?.rateType ?? ref.read(termsProvider).defaultRateType;
  late ItemStatus _status = widget.item?.status ?? ItemStatus.active;

  /// When an item that is in repair or at cleaning is back in service.
  late DateTime? _until = widget.item?.statusUntil;
  late final _buffer = TextEditingController(
    text: '${widget.item?.bufferHours ?? 0}',
  );
  late final _week = TextEditingController(
    text: widget.item == null || widget.item!.weekRate == 0
        ? ''
        : amountText(widget.item!.weekRate),
  );
  late final _month = TextEditingController(
    text: widget.item == null || widget.item!.monthRate == 0
        ? ''
        : amountText(widget.item!.monthRate),
  );
  late final _lateFee = TextEditingController(
    text: widget.item == null || widget.item!.lateFee == 0
        ? ''
        : amountText(widget.item!.lateFee),
  );
  List<String> _used = const [];

  /// true while the person is typing a category of their own.
  bool _typing = false;
  bool _saving = false;

  /// The pictures as they are on screen, the cover first. [id] is null for
  /// one picked in this visit that is not saved yet.
  final List<({int? id, String path})> _photos = [];

  /// Saved pictures taken off in this visit; removed for good on Save.
  final List<({int id, String path})> _removed = [];

  /// Files picked in this visit; deleted again if the page is left unsaved.
  final List<String> _picked = [];
  bool _kept = false;

  @override
  void initState() {
    super.initState();
    ref.read(itemRepoProvider).categoriesInUse().then((c) {
      if (mounted) setState(() => _used = c);
    });
    final id = widget.item?.id;
    if (id != null) {
      ref.read(itemRepoProvider).photosOf(id).then((list) {
        if (mounted) {
          setState(() {
            _photos
              ..clear()
              ..addAll([for (final p in list) (id: p.id, path: p.path)]);
          });
        }
      });
    }
  }

  int get _limit => ref.read(isProProvider) ? proPhotosPerItem : FreePlan.photosPerItem;

  Future<void> _addPicture() async {
    final room = _limit - _photos.length;
    if (room <= 0) {
      // the free plan's picture is used: Pro keeps more
      if (!ref.read(isProProvider)) {
        await showProPrompt(context, ProFeature.itemPhotos);
      }
      return;
    }
    final camera = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(tr('Take a photo')),
              onTap: () => Navigator.pop(ctx, true),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(tr('Choose from the gallery')),
              onTap: () => Navigator.pop(ctx, false),
            ),
          ],
        ),
      ),
    );
    if (camera == null || !mounted) return;
    final List<String> got;
    if (camera) {
      final one = await PhotoStore.take(camera: true, maxWidth: 1200);
      got = [?one];
    } else {
      got = await PhotoStore.takeMany(limit: room, maxWidth: 1200);
    }
    if (!mounted) {
      for (final path in got) {
        await PhotoStore.delete(path);
      }
      return;
    }
    // only as many as fit; a picker that returned more has the rest dropped
    final keep = got.take(room).toList();
    for (final path in got.skip(room)) {
      await PhotoStore.delete(path);
    }
    setState(() {
      for (final path in keep) {
        _picked.add(path);
        _photos.add((id: null, path: path));
      }
    });
    if (got.length > room && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr('Only {n} pictures fit. The rest were left out.', {'n': room}),
          ),
        ),
      );
    }
  }

  void _removePicture(int i) {
    final p = _photos[i];
    setState(() {
      _photos.removeAt(i);
      if (p.id != null) _removed.add((id: p.id!, path: p.path));
    });
  }

  void _makeCover(int i) => setState(() {
    final p = _photos.removeAt(i);
    _photos.insert(0, p);
  });

  /// Writes the picture changes once the item itself is saved.
  Future<void> _savePictures(int itemId) async {
    final repo = ref.read(itemRepoProvider);
    final isPro = ref.read(isProProvider);
    for (final r in _removed) {
      await repo.removePhoto(r.id);
      await PhotoStore.delete(r.path);
    }
    final order = <int>[];
    for (final p in _photos) {
      if (p.id != null) {
        order.add(p.id!);
        continue;
      }
      try {
        order.add(await repo.addPhoto(itemId, p.path, isPro: isPro));
      } on BookingException {
        await PhotoStore.delete(p.path); // over the limit: not kept
      }
    }
    await repo.setPhotoOrder(itemId, order);
    _kept = true;
  }

  @override
  void dispose() {
    if (!_kept) {
      for (final path in _picked) {
        PhotoStore.delete(path);
      }
    }
    for (final c in [
      _name,
      _category,
      _size,
      _rate,
      _deposit,
      _quantity,
      _minHours,
      _buffer,
      _week,
      _month,
      _lateFee,
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
      minHours: !service && _rateType.isHourly
          ? (int.tryParse(_minHours.text.trim()) ?? 1).clamp(1, 1 << 30)
          : 1,
      notes: _notes.text,
      status: _status,
      statusUntil: _status.bookable || _status == ItemStatus.retired
          ? null
          : _until,
      bufferHours: service
          ? 0
          : (int.tryParse(_buffer.text.trim()) ?? 0).clamp(0, 24 * 60),
      weekRate: !service && _rateType == RateType.day
          ? parseAmount(_week.text)
          : 0,
      monthRate: !service && _rateType == RateType.day
          ? parseAmount(_month.text)
          : 0,
      lateFee: service ? 0 : parseAmount(_lateFee.text),
      createdAt: old?.createdAt ?? DateTime.now(),
    );
    final savedId = await ref.read(itemRepoProvider).save(item);
    await _savePictures(savedId);
    if (mounted) Navigator.of(context).pop();
  }

  /// Wraps a field that is part of Pro: without Pro it cannot be typed in,
  /// and a tap offers Pro.
  Widget _proField(ProFeature feature, Widget field) {
    final isPro = ref.watch(isProProvider);
    if (isPro) return field;
    return InkWell(
      onTap: () => showProPrompt(context, feature),
      child: IgnorePointer(child: Opacity(opacity: 0.6, child: field)),
    );
  }

  /// The settings that give a shop more control over an item.
  List<Widget> _moreControl(Terms terms, bool editing) {
    final text = Theme.of(context).textTheme;
    final unit = _rateType.isHourly ? tr('hour') : tr('day');
    return [
      const SizedBox(height: 22),
      Row(
        children: [
          Expanded(
            child: Text(
              tr('More control'),
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          if (!ref.watch(isProProvider))
            Chip(
              avatar: const Icon(Icons.lock_outline, size: 16),
              label: Text(tr('Part of Pro')),
            ),
        ],
      ),
      const SizedBox(height: 10),
      if (_rateType == RateType.day) ...[
        Row(
          children: [
            Expanded(
              child: _proField(
                ProFeature.longRates,
                TextFormField(
                  controller: _week,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: tr('Weekly rate (₹)'),
                    helperText: tr('For 7 days'),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _proField(
                ProFeature.longRates,
                TextFormField(
                  controller: _month,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: tr('Monthly rate (₹)'),
                    helperText: tr('For 30 days'),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
      _proField(
        ProFeature.lateRule,
        TextFormField(
          controller: _lateFee,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: tr('Late fee for each late {unit} (₹)', {'unit': unit}),
            helperText: tr('Filled in for you when a late return is booked in'),
          ),
        ),
      ),
      const SizedBox(height: 12),
      _proField(
        ProFeature.buffer,
        TextFormField(
          controller: _buffer,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: tr('Gap after each return (hours)'),
            helperText: tr('Kept free for cleaning or servicing'),
          ),
        ),
      ),
      if (editing && widget.item?.id != null) ...[
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.build_circle_outlined),
          title: Text(tr('Repair and damage log')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            if (!await requirePro(context, ref, ProFeature.repairLog)) return;
            if (!mounted) return;
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ItemRepairsScreen(item: widget.item!),
              ),
            );
          },
        ),
      ],
    ];
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
    // the shop's type may load after this page opened: a new vehicle starts
    // as a day rate, not "per event"
    if (!editing && !terms.rateTypes.contains(_rateType)) {
      _rateType = terms.defaultRateType;
    }
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
            ItemPhotoStrip(
              paths: [for (final p in _photos) p.path],
              canAddMore: _photos.length < _limit,
              locked: _photos.length >= FreePlan.photosPerItem &&
                  !ref.watch(isProProvider),
              onAdd: _addPicture,
              onRemove: _removePicture,
              onMakeCover: _makeCover,
            ),
            const SizedBox(height: 16),
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
                        labelText: terms.sizeLabel,
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
                        helperText: terms.quantityHelp,
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
                  // a vehicle is rented by the day or the hour; an item that
                  // already has another rate keeps showing it
                  for (final r in terms.rateTypes)
                    ButtonSegment(value: r, label: Text(r.label)),
                  if (!terms.rateTypes.contains(_rateType))
                    ButtonSegment(value: _rateType, label: Text(_rateType.label)),
                ],
                selected: {_rateType},
                onSelectionChanged: (s) => setState(() => _rateType = s.first),
              ),
              if (_rateType.isHourly) ...[
                const SizedBox(height: 14),
                TextFormField(
                  controller: _minHours,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: tr('Minimum hours'),
                    helperText: tr(
                      'Even a shorter use is charged for this many hours',
                    ),
                  ),
                  validator: (v) => (int.tryParse((v ?? '').trim()) ?? 0) < 1
                      ? tr('At least 1')
                      : null,
                ),
              ],
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
                          : terms.rentLabel,
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
                        labelText: terms.depositLabel,
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
                onChanged: (s) => setState(() {
                  _status = s ?? _status;
                  if (_status.bookable || _status == ItemStatus.retired) {
                    _until = null;
                  }
                }),
              ),
              if (!_status.bookable && _status != ItemStatus.retired)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_available_outlined),
                  title: Text(tr('Back in service on')),
                  subtitle: Text(
                    _until == null
                        ? tr('No date: it stays out until you change the status')
                        : dateText(_until!),
                  ),
                  trailing: _until == null
                      ? null
                      : IconButton(
                          tooltip: tr('Clear'),
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _until = null),
                        ),
                  onTap: () async {
                    final today = dayOf(DateTime.now());
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _until ?? today.add(const Duration(days: 3)),
                      firstDate: today,
                      lastDate: today.add(const Duration(days: 365 * 2)),
                    );
                    if (d != null) setState(() => _until = dayOf(d));
                  },
                ),
            ],
            if (!service) ..._moreControl(terms, editing),
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
