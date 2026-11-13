import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/booking_math.dart';
import '../../core/format.dart';
import '../../core/terms.dart';
import '../../core/theme.dart';
import '../../data/booking_models.dart';
import '../../data/booking_repo.dart';
import '../../data/business_profile.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../data/staff.dart';
import '../../l10n/strings.dart';
import '../../subscription/entitlement.dart';
import '../../subscription/plan.dart';
import '../../subscription/pro_prompt.dart';
import '../common/widgets.dart';
import '../customers/customer_form_screen.dart';
import 'booking_errors.dart';

/// Make a new booking, or change one that has not been returned or cancelled.
/// Pops with the booking's id once saved.
class BookingFormScreen extends ConsumerStatefulWidget {
  const BookingFormScreen({super.key, this.booking});

  /// The booking being changed, or null for a new one.
  final Booking? booking;

  @override
  ConsumerState<BookingFormScreen> createState() => _BookingFormScreenState();
}

class _BookingFormScreenState extends ConsumerState<BookingFormScreen> {
  Customer? _customer;
  late DateTime _event;
  late DateTime _pickup;
  late DateTime _return;
  bool _datesTouched = false;
  final _chosen = <int, RentItem>{};

  /// How many of each chosen item (item id -> pieces).
  final _qty = <int, int>{};

  /// The appointment time ("14:30") of a service booking, or ''.
  late String _time = widget.booking?.eventTime ?? '';
  late final _discount = TextEditingController(
    text: widget.booking == null || widget.booking!.discount == 0
        ? ''
        : amountText(widget.booking!.discount),
  );
  final _advance = TextEditingController();
  late final _notes = TextEditingController(text: widget.booking?.notes);
  PayMode _mode = PayMode.cash;
  int _remind = 2;
  Map<int, ItemConflict> _clash = const {};
  int? _freeLeft;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.booking != null;

  /// A service business (makeup artist): one appointment, nothing to pick up
  /// or return, and no limit on how many bookings share a day.
  bool get _service =>
      ref.read(profileProvider).valueOrNull?.type.isService ?? false;

  int _qtyOf(RentItem i) => _qty[i.id] ?? 1;

  @override
  void initState() {
    super.initState();
    final b = widget.booking;
    final today = dayOf(DateTime.now());
    _event = b?.eventDate ?? today.add(const Duration(days: 7));
    _pickup = b?.pickupDate ?? _event.subtract(const Duration(days: 1));
    _return = b?.returnDate ?? _event.add(const Duration(days: 1));
    if (_service) {
      _event = b?.eventDate ?? today.add(const Duration(days: 1));
      _pickup = _event;
      _return = _event;
    }
    _remind =
        b?.remindDays ?? ref.read(profileProvider).valueOrNull?.remindDays ?? 2;
    _load();
  }

  Future<void> _load() async {
    final b = widget.booking;
    final items = ref.read(itemRepoProvider);
    final customers = ref.read(customerRepoProvider);
    if (b != null) {
      final c = await customers.get(b.customerId);
      for (final l in b.lines) {
        _qty[l.itemId] = l.qty;
        // a removed item keeps its place so the page still shows it
        _chosen[l.itemId] =
            await items.get(l.itemId) ??
            RentItem(
              id: l.itemId,
              name: l.name,
              rateType: l.rateType,
              rate: l.rate,
              deposit: l.deposit,
              createdAt: DateTime.now(),
            );
      }
      _customer =
          c ??
          Customer(
            id: b.customerId,
            name: b.customerName,
            phone: b.customerPhone,
            createdAt: DateTime.now(),
          );
    } else if (!ref.read(isProProvider)) {
      _freeLeft = await ref.read(bookingRepoProvider).freeLeft();
    }
    await _recheck();
  }

  @override
  void dispose() {
    _discount.dispose();
    _advance.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Looks again at which chosen items are already taken on these days.
  Future<void> _recheck() async {
    if (_service) return; // a service is not held back by other bookings
    final clash = await ref
        .read(bookingRepoProvider)
        .conflicts(
          itemIds: _chosen.keys.toList(),
          pickup: _pickup,
          ret: _return,
          quantities: {for (final i in _chosen.values) i.id!: _qtyOf(i)},
          exceptBookingId: widget.booking?.id,
        );
    if (mounted) setState(() => _clash = clash);
  }

  /// What one chosen item comes to for the dates shown and its quantity.
  double _lineAmount(RentItem i) =>
      r2(lineAmount(i.rateType, i.rate, _pickup, _return) * _qtyOf(i));

  GstConfig get _gst =>
      ref.read(profileProvider).valueOrNull?.gst ?? GstConfig.off;

  /// Each chosen item's money for the dates shown, with discount and GST.
  List<LineMoney> get _lines {
    final list = _chosen.values.toList();
    return splitMoney(
      amounts: [for (final i in list) _lineAmount(i)],
      gstRates: [for (final i in list) i.gstRate],
      discount: _disc > 0 && _disc <= _rent ? _disc : 0,
      gst: _gst,
    );
  }

  double get _rent =>
      r2(_chosen.values.fold(0.0, (a, i) => a + _lineAmount(i)));
  double get _tax => r2(_lines.fold(0.0, (a, l) => a + l.tax));
  double get _payable => r2(_lines.fold(0.0, (a, l) => a + l.total));
  double get _deposit =>
      _chosen.values.fold(0.0, (a, i) => a + i.deposit * _qtyOf(i));
  double get _disc => parseAmount(_discount.text);
  double get _adv => parseAmount(_advance.text);

  Future<DateTime?> _askDate(DateTime initial) {
    final today = dayOf(DateTime.now());
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today.subtract(const Duration(days: 365)),
      lastDate: today.add(const Duration(days: 365 * 3)),
    );
  }

  Future<void> _pickTime() async {
    final parts = _time.split(':');
    final at = await showTimePicker(
      context: context,
      initialTime: parts.length == 2
          ? TimeOfDay(
              hour: int.tryParse(parts[0]) ?? 10,
              minute: int.tryParse(parts[1]) ?? 0,
            )
          : const TimeOfDay(hour: 10, minute: 0),
    );
    if (at == null) return;
    setState(() {
      _time =
          '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _pickEvent() async {
    final d = await _askDate(_event);
    if (d == null) return;
    setState(() {
      _event = dayOf(d);
      if (_service) {
        _pickup = _event;
        _return = _event;
      } else if (!_datesTouched) {
        _pickup = _event.subtract(const Duration(days: 1));
        _return = _event.add(const Duration(days: 1));
      }
    });
    _recheck();
  }

  Future<void> _pickPickup() async {
    final d = await _askDate(_pickup);
    if (d == null) return;
    setState(() {
      _pickup = dayOf(d);
      _datesTouched = true;
    });
    _recheck();
  }

  Future<void> _pickReturn() async {
    final d = await _askDate(_return);
    if (d == null) return;
    setState(() {
      _return = dayOf(d);
      _datesTouched = true;
    });
    _recheck();
  }

  Future<void> _chooseCustomer() async {
    final c = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CustomerPicker(),
    );
    if (c != null) setState(() => _customer = c);
  }

  Future<void> _chooseItems() async {
    final picked = await showModalBottomSheet<List<RentItem>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ItemPicker(
        chosen: _chosen.keys.toSet(),
        pickup: _pickup,
        ret: _return,
        service: _service,
        exceptBookingId: widget.booking?.id,
      ),
    );
    if (picked == null) return;
    setState(() {
      _chosen
        ..clear()
        ..addEntries(picked.map((i) => MapEntry(i.id!, i)));
      _qty.removeWhere((id, _) => !_chosen.containsKey(id));
    });
    _recheck();
  }

  /// Shows why the booking was not saved: on the page, and in a message at
  /// the bottom that cannot be missed.
  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = message;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    if (_customer == null) {
      _fail(tr('Choose the customer.'));
      return;
    }
    if (_chosen.isEmpty) {
      _fail(ref.read(termsProvider).chooseOne);
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    final draft = BookingDraft(
      customerId: _customer!.id!,
      eventDate: _event,
      pickupDate: _pickup,
      returnDate: _return,
      itemIds: _chosen.keys.toList(),
      quantities: {for (final i in _chosen.values) i.id!: _qtyOf(i)},
      discount: _disc,
      notes: _notes.text,
      remindDays: _remind,
      eventTime: _service ? _time : '',
      createdBy: ref.read(permsProvider).name,
    );
    final repo = ref.read(bookingRepoProvider);
    try {
      final int id;
      if (_editing) {
        id = widget.booking!.id;
        await repo.update(
          id,
          draft,
          gst: _gst,
          checkAvailability: !_service,
        );
      } else {
        id = await repo.create(
          draft,
          isPro: ref.read(isProProvider),
          advance: _adv,
          advanceMode: _mode,
          gst: _gst,
          checkAvailability: !_service,
        );
      }
      if (mounted) Navigator.of(context).pop(id);
    } on BookingException catch (e) {
      if (!mounted) return;
      if (e.error == BookingError.limitReached) {
        setState(() => _saving = false);
        await showProPrompt(context, ProFeature.unlimitedBookings);
      } else {
        _fail(bookingErrorText(e));
      }
    } catch (e) {
      // anything unexpected (a database problem, for example): say so, and
      // let the person try again instead of leaving a dead button
      _fail(tr('Could not save the booking: {e}', {'e': e}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final balance = _payable - _adv;
    final terms = ref.watch(termsProvider);
    final canDiscount = ref.watch(permsProvider).can(Permission.giveDiscount);

    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title,
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Card(child: Column(children: children)),
        ],
      ),
    );

    Widget dateRow(String label, DateTime v, VoidCallback onTap) => ListTile(
      leading: const Icon(Icons.calendar_today_outlined),
      title: Text(label),
      trailing: Text(
        dateText(v),
        style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      onTap: onTap,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? tr('Edit booking') : tr('New booking')),
      ),
      body: AuroraBackground(
        child: ListView(
          // room under the last button for the phone's own bar
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            if (_freeLeft != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _freeLeft == 0
                      ? tr('You have used all {n} free bookings this month.', {
                          'n': FreePlan.bookingsPerMonth,
                        })
                      : tr('{n} free bookings left this month.', {
                          'n': _freeLeft,
                        }),
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            section(tr('Customer'), [
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(_customer?.name ?? tr('Choose the customer')),
                subtitle: _customer == null || _customer!.phone.isEmpty
                    ? null
                    : Text(_customer!.phone),
                trailing: const Icon(Icons.chevron_right),
                onTap: _chooseCustomer,
              ),
            ]),
            section(_service ? tr('Appointment') : tr('Dates'), [
              dateRow(terms.eventDate, _event, _pickEvent),
              if (_service) ...[
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: Text(tr('Appointment time')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _time.isEmpty
                            ? tr('Not set')
                            : timeText(_time),
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (_time.isNotEmpty)
                        IconButton(
                          tooltip: tr('Clear'),
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _time = ''),
                        ),
                    ],
                  ),
                  onTap: _pickTime,
                ),
              ] else ...[
                const Divider(),
                dateRow(tr('Pickup date'), _pickup, _pickPickup),
                const Divider(),
                dateRow(tr('Return date'), _return, _pickReturn),
              ],
            ]),
            section(terms.items, [
              for (final i in _chosen.values) ...[
                ListTile(
                  title: Text(i.name),
                  subtitle: Text(
                    '${i.rateType.label} · ${money(i.rate)}'
                    '${i.deposit > 0 ? ' · ${tr('Deposit')} ${money(i.deposit)}' : ''}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _QtyStepper(
                        value: _qtyOf(i),
                        // a rental item cannot be booked past what the shop has
                        max: _service ? 99 : i.quantity,
                        onChanged: (n) {
                          setState(() => _qty[i.id!] = n);
                          _recheck();
                        },
                      ),
                      IconButton(
                        tooltip: tr('Remove'),
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _chosen.remove(i.id);
                            _qty.remove(i.id);
                          });
                          _recheck();
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(),
              ],
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: Text(
                  _chosen.isEmpty ? terms.chooseItems : terms.changeItems,
                ),
                onTap: _chooseItems,
              ),
            ]),
            if (_clash.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Palette.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final c in _clash.values)
                      Text(
                        c.stock > 1 || (_qty[c.itemId] ?? 1) > 1
                            ? tr(
                                'Only {free} of {stock} {item} are free for these days.',
                                {
                                  'free': c.free,
                                  'stock': c.stock,
                                  'item': _chosen[c.itemId]?.name ?? '',
                                },
                              )
                            : tr(
                                '{item} is booked by {name} (#{n}) from {from} to {to}.',
                                {
                                  'item': _chosen[c.itemId]?.name ?? '',
                                  'name': c.customerName,
                                  'n': c.bookingNumber,
                                  'from': dateText(c.pickupDate),
                                  'to': dateText(c.returnDate),
                                },
                              ),
                        style: text.bodyMedium?.copyWith(color: Palette.danger),
                      ),
                  ],
                ),
              ),
            section(tr('Money'), [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    _line(context, tr('Rent'), money(_rent)),
                    const SizedBox(height: 10),
                    if (canDiscount)
                      TextField(
                        controller: _discount,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: tr('Discount (₹)'),
                        ),
                      )
                    else if (_disc > 0)
                      _line(context, tr('Discount'), money(_disc)),
                    if (_gst.enabled) ...[
                      const SizedBox(height: 10),
                      _line(
                        context,
                        _gst.inclusive ? tr('GST (included)') : tr('GST'),
                        money(_tax),
                      ),
                      const SizedBox(height: 6),
                      _line(context, tr('Total'), money(_payable), bold: true),
                    ],
                    if (!_editing) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _advance,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                labelText: tr('Advance paid (₹)'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<PayMode>(
                              initialValue: _mode,
                              isExpanded: true,
                              decoration: InputDecoration(labelText: tr('By')),
                              items: [
                                for (final m in PayMode.values)
                                  DropdownMenuItem(
                                    value: m,
                                    child: Text(m.label),
                                  ),
                              ],
                              onChanged: (m) =>
                                  setState(() => _mode = m ?? _mode),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const Divider(height: 24),
                    _line(
                      context,
                      tr('Balance to collect'),
                      money(balance < 0 ? 0 : balance),
                      bold: true,
                    ),
                    if (_deposit > 0) ...[
                      const SizedBox(height: 6),
                      _line(
                        context,
                        tr('Deposit to hold'),
                        money(_deposit),
                      ),
                    ],
                  ],
                ),
              ),
            ]),
            section(tr('Reminder and notes'), [
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: Text(
                  _service
                      ? tr('Remind me before the appointment')
                      : tr('Remind me before the event'),
                ),
                trailing: DropdownButton<int>(
                  value: _remind,
                  underline: const SizedBox(),
                  items: [
                    for (final n in [0, 1, 2, 3, 5, 7])
                      DropdownMenuItem(
                        value: n,
                        child: Text(
                          n == 0
                              ? tr('On the day')
                              : tr('{n} days before', {'n': n}),
                        ),
                      ),
                  ],
                  onChanged: (n) => setState(() => _remind = n ?? _remind),
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(14),
                child: TextField(
                  controller: _notes,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: tr('Notes (optional)'),
                  ),
                ),
              ),
            ]),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: text.bodyMedium?.copyWith(
                    color: Palette.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : Text(_editing ? tr('Save changes') : tr('Save booking')),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _line(BuildContext context, String label, String value,
      {bool bold = false}) {
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
    );
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style),
      ],
    );
  }
}

/// Search the customers, or add a new one on the spot.
class _CustomerPicker extends ConsumerStatefulWidget {
  const _CustomerPicker();

  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  String _q = '';
  List<Customer> _list = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final l = await ref.read(customerRepoProvider).list(query: _q);
    if (mounted) setState(() => _list = l);
  }

  Future<void> _add() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CustomerFormScreen()),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            SearchField(
              hint: tr('Search by name or phone'),
              onChanged: (v) {
                _q = v;
                _reload();
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.person_add_alt_1),
              title: Text(tr('Add customer')),
              onTap: _add,
            ),
            const Divider(),
            Expanded(
              child: _list.isEmpty
                  ? EmptyState(
                      icon: Icons.people_alt_outlined,
                      message: tr('No customer matches your search.'),
                    )
                  : ListView(
                      children: [
                        for (final c in _list)
                          ListTile(
                            title: Text(c.name),
                            subtitle: c.phone.isEmpty ? null : Text(c.phone),
                            onTap: () => Navigator.of(context).pop(c),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tick the items for the booking. Items already taken for the booking's days
/// are greyed out and say who has them.
class _ItemPicker extends ConsumerStatefulWidget {
  const _ItemPicker({
    required this.chosen,
    required this.pickup,
    required this.ret,
    required this.service,
    this.exceptBookingId,
  });
  final Set<int> chosen;
  final DateTime pickup;
  final DateTime ret;
  final bool service;
  final int? exceptBookingId;

  @override
  ConsumerState<_ItemPicker> createState() => _ItemPickerState();
}

class _ItemPickerState extends ConsumerState<_ItemPicker> {
  late final Set<int> _on = {...widget.chosen};
  String _q = '';
  List<RentItem> _all = const [];
  Map<int, ItemAvailability> _avail = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = (await ref.read(itemRepoProvider).list())
        .where((i) => i.status.bookable)
        .toList();
    final avail = widget.service
        ? const <int, ItemAvailability>{}
        : await ref
              .read(bookingRepoProvider)
              .availability(
                itemIds: [for (final i in items) i.id!],
                pickup: widget.pickup,
                ret: widget.ret,
                exceptBookingId: widget.exceptBookingId,
              );
    if (mounted) {
      setState(() {
        _all = items;
        _avail = avail;
      });
    }
  }

  /// The line under an item: its rate, and how many are free on those days.
  String _pickerNote(RentItem i) {
    final a = _avail[i.id];
    final rate = '${i.rateType.label} · ${money(i.rate)}';
    if (a == null) return rate;
    if (a.free == 0) {
      final h = a.holder;
      return h == null || h.bookingNumber == 0
          ? tr('None free on these days')
          : tr('Booked by {name} (#{n})', {
              'name': h.customerName,
              'n': h.bookingNumber,
            });
    }
    return a.stock > 1
        ? '$rate · ${tr('{free} of {stock} free', {'free': a.free, 'stock': a.stock})}'
        : rate;
  }

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final i in _all)
        if (_q.isEmpty || i.name.toLowerCase().contains(_q.toLowerCase())) i,
    ];
    final terms = ref.watch(termsProvider);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            SearchField(
              hint: terms.searchItems,
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: shown.isEmpty
                  ? EmptyState(
                      icon: Icons.checkroom_outlined,
                      message: _all.isEmpty
                          ? terms.noItemsYet
                          : tr('No item matches your search.'),
                    )
                  : ListView(
                      children: [
                        for (final i in shown)
                          CheckboxListTile(
                            value: _on.contains(i.id),
                            // nothing free on those days: it cannot be ticked
                            enabled: (_avail[i.id]?.free ?? 1) > 0,
                            onChanged: (v) => setState(() {
                              v == true ? _on.add(i.id!) : _on.remove(i.id);
                            }),
                            title: Text(i.name),
                            subtitle: Text(_pickerNote(i)),
                          ),
                      ],
                    ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop([
                for (final i in _all)
                  if (_on.contains(i.id)) i,
              ]),
              child: Text(tr('Done ({n})', {'n': _on.length})),
            ),
          ],
        ),
      ),
    );
  }
}


/// A small "- 2 +" control for how many pieces.
class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
    required this.value,
    required this.max,
    required this.onChanged,
  });
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget button(IconData icon, VoidCallback? onTap, String tip) => InkResponse(
      onTap: onTap,
      radius: 20,
      child: Tooltip(
        message: tip,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 22,
            color: onTap == null ? scheme.outline : scheme.primary,
          ),
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(
          Icons.remove_circle_outline,
          value > 1 ? () => onChanged(value - 1) : null,
          tr('Fewer'),
        ),
        SizedBox(
          width: 28,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        button(
          Icons.add_circle_outline,
          value < max ? () => onChanged(value + 1) : null,
          tr('More'),
        ),
      ],
    );
  }
}
