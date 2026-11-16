import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/terms.dart';
import '../../core/theme.dart';
import '../../data/booking_models.dart';
import '../../data/booking_repo.dart';
import '../../l10n/strings.dart';
import '../common/widgets.dart';
import 'booking_detail_screen.dart';

/// The month as a calendar: each day shows how many bookings hold items on it.
/// Tap a day to see who has what. Choose an item to see only its days.
class AvailabilityCalendarScreen extends ConsumerStatefulWidget {
  const AvailabilityCalendarScreen({super.key});

  @override
  ConsumerState<AvailabilityCalendarScreen> createState() =>
      _AvailabilityCalendarScreenState();
}

class _AvailabilityCalendarScreenState
    extends ConsumerState<AvailabilityCalendarScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selected = dayOf(DateTime.now());
  int? _itemId;

  DateTime get _first => _month;
  DateTime get _last => DateTime(_month.year, _month.month + 1, 0);

  void _go(int months) => setState(() {
    _month = DateTime(_month.year, _month.month + months);
    _selected = null;
  });

  bool _holds(Booking b, DateTime day) {
    final today = dayOf(DateTime.now());
    var to = b.returnDate;
    // out and late: still held until it is back
    if (b.status.isOut && to.isBefore(today)) to = today;
    return !day.isBefore(b.pickupDate) && !day.isAfter(to);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_heldProvider((_first, _last)));
    final terms = ref.watch(termsProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(tr('Availability calendar'))),
      body: AuroraBackground(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(tr('Error: {e}', {'e': e}))),
          data: (all) {
            // the items that appear, to filter by
            final names = <int, String>{};
            for (final b in all) {
              for (final l in b.lines) {
                names[l.itemId] = l.name;
              }
            }
            final bookings = _itemId == null
                ? all
                : [
                    for (final b in all)
                      if (b.lines.any((l) => l.itemId == _itemId)) b,
                  ];
            int count(DateTime day) =>
                bookings.where((b) => _holds(b, day)).length;
            final lead = (_first.weekday + 6) % 7; // Monday first
            final days = _last.day;
            final cells = ((lead + days + 6) ~/ 7) * 7;
            final selected = _selected;
            final onDay = selected == null
                ? const <Booking>[]
                : [for (final b in bookings) if (_holds(b, selected)) b];

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: tr('Earlier month'),
                      onPressed: () => _go(-1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        monthYearText(_month),
                        textAlign: TextAlign.center,
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: tr('Later month'),
                      onPressed: () => _go(1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                if (names.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DropdownButtonFormField<int?>(
                      initialValue: _itemId != null && names.containsKey(_itemId)
                          ? _itemId
                          : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: tr('Show'),
                        isDense: true,
                      ),
                      items: [
                        DropdownMenuItem<int?>(
                          value: null,
                          child: Text(tr('Everything')),
                        ),
                        for (final e in names.entries)
                          DropdownMenuItem<int?>(
                            value: e.key,
                            child: Text(e.value, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => setState(() => _itemId = v),
                    ),
                  ),
                Row(
                  children: [
                    for (final w in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                      Expanded(
                        child: Center(
                          child: Text(
                            w,
                            style: text.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                for (var row = 0; row < cells ~/ 7; row++)
                  Row(
                    children: [
                      for (var col = 0; col < 7; col++)
                        Expanded(
                          child: Builder(
                            builder: (_) {
                              final n = row * 7 + col - lead + 1;
                              if (n < 1 || n > days) {
                                return const SizedBox(height: 52);
                              }
                              final day = DateTime(_month.year, _month.month, n);
                              final c = count(day);
                              final isSel = selected != null && day == selected;
                              final isToday = day == dayOf(DateTime.now());
                              return Padding(
                                padding: const EdgeInsets.all(2),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => setState(() => _selected = day),
                                  child: Container(
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: isSel
                                          ? scheme.primary
                                          : c > 0
                                          ? scheme.primaryContainer
                                          : scheme.surface,
                                      borderRadius: BorderRadius.circular(12),
                                      border: isToday && !isSel
                                          ? Border.all(color: scheme.primary)
                                          : null,
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          '$n',
                                          style: text.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: isSel ? scheme.onPrimary : null,
                                          ),
                                        ),
                                        if (c > 0)
                                          Text(
                                            '$c',
                                            style: text.labelSmall?.copyWith(
                                              color: isSel
                                                  ? scheme.onPrimary
                                                  : scheme.onPrimaryContainer,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 16),
                if (selected != null) ...[
                  Text(
                    dateText(selected),
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  if (onDay.isEmpty)
                    Text(
                      tr('Nothing is booked on this day.'),
                      style: text.bodyMedium,
                    )
                  else
                    for (final b in onDay)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text('#${b.number}  ${b.customerName}'),
                          subtitle: Text(
                            [
                              for (final l in b.lines)
                                if (_itemId == null || l.itemId == _itemId)
                                  l.label,
                            ].join(', '),
                          ),
                          trailing: StatusChip(
                            label: b.status.label,
                            color: scheme.primary,
                          ),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    BookingDetailScreen(bookingId: b.id),
                              ),
                            );
                            ref.invalidate(_heldProvider((_first, _last)));
                          },
                        ),
                      ),
                ] else
                  Text(
                    tr('Tap a day to see the {items} booked on it.', {
                      'items': terms.items.toLowerCase(),
                    }),
                    style: text.bodyMedium,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

final _heldProvider = FutureProvider.autoDispose
    .family<List<Booking>, (DateTime, DateTime)>(
      (ref, range) =>
          ref.watch(bookingRepoProvider).heldBetween(range.$1, range.$2),
    );
