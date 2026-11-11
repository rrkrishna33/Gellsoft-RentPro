import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/booking_models.dart';
import '../../data/booking_repo.dart';
import '../../l10n/strings.dart';
import '../common/widgets.dart';
import 'booking_detail_screen.dart';

/// All bookings, by stage, with a search box.
class BookingsScreen extends ConsumerWidget {
  const BookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(bookingFilterProvider);
    final bookings = ref.watch(bookingsProvider);
    final searching = ref.watch(bookingSearchProvider).trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text(
            tr('Bookings'),
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SearchField(
            hint: tr('Search by name, phone or number'),
            onChanged: (v) =>
                ref.read(bookingSearchProvider.notifier).state = v,
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (final f in BookingFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(tr(f.en)),
                    selected: f == filter,
                    onSelected: (_) =>
                        ref.read(bookingFilterProvider.notifier).state = f,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: bookings.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(tr('Error: {e}', {'e': e}))),
            data: (list) {
              if (list.isEmpty) {
                return EmptyState(
                  icon: Icons.event_available_outlined,
                  message: searching
                      ? tr('No booking matches your search.')
                      : switch (filter) {
                          BookingFilter.upcoming => tr(
                            'No upcoming bookings. Tap + to make one.',
                          ),
                          BookingFilter.out => tr('Nothing is out right now.'),
                          BookingFilter.returned => tr(
                            'Returned bookings will appear here.',
                          ),
                          BookingFilter.cancelled => tr(
                            'Cancelled bookings will appear here.',
                          ),
                        },
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => BookingTile(
                  booking: list[i],
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            BookingDetailScreen(bookingId: list[i].id),
                      ),
                    );
                    ref.invalidate(bookingsProvider);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One booking in a list: who, when, what, and what is still due.
class BookingTile extends StatelessWidget {
  const BookingTile({super.key, required this.booking, required this.onTap});
  final Booking booking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final text = Theme.of(context).textTheme;
    final today = dayOf(DateTime.now());
    final overdue = b.isOverdue(today);
    final names = b.lines.map((l) => l.name).toList();
    final what = names.isEmpty
        ? ''
        : names.length == 1
        ? names.first
        : tr('{first} and {n} more', {
            'first': names.first,
            'n': names.length - 1,
          });
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AuroraStyle.of(context).softShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '#${b.number}  ${b.customerName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (overdue)
                      StatusChip(label: tr('Overdue'), color: Palette.danger)
                    else
                      StatusChip(
                        label: b.status.label,
                        color: switch (b.status) {
                          BookingStatus.booked => Theme.of(context).colorScheme.primary,
                          BookingStatus.pickedUp => Palette.warning,
                          BookingStatus.returned => Palette.success,
                          BookingStatus.cancelled => Theme.of(context).colorScheme.onSurfaceVariant,
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(what, style: text.bodyMedium),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.celebration_outlined, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      dateText(b.eventDate),
                      style: text.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (b.status != BookingStatus.cancelled &&
                        b.balanceDue > 0)
                      Text(
                        tr('Due {amount}', {'amount': money(b.balanceDue)}),
                        style: text.bodySmall?.copyWith(
                          color: Palette.danger,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
