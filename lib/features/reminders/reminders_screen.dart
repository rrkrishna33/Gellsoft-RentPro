import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/share.dart';
import '../../core/theme.dart';
import '../../data/booking_repo.dart';
import '../../data/business_profile.dart';
import '../../data/reminders.dart';
import '../../l10n/strings.dart';
import '../bookings/booking_detail_screen.dart';
import '../bookings/messages.dart';
import '../common/widgets.dart';

/// "Today": what to send, what is due back, what is late and who still owes
/// money, each with a button that opens WhatsApp with the message ready.
class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(remindersProvider);
    final service =
        ref.watch(profileProvider).valueOrNull?.type.isService ?? false;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Reminders'))),
      body: AuroraBackground(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(tr('Error: {e}', {'e': e}))),
          data: (items) {
            if (items.isEmpty) {
              return EmptyState(
                icon: Icons.task_alt_outlined,
                message: tr('Nothing needs your attention right now.'),
              );
            }
            final sections = <ReminderKind, List<ReminderItem>>{};
            for (final i in items) {
              sections.putIfAbsent(i.kind, () => []).add(i);
            }
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(remindersProvider);
                await ref.read(remindersProvider.future);
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  for (final kind in _order)
                    if (sections[kind] != null) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                        child: Text(
                          reminderTitle(kind, service: service),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      for (final i in sections[kind]!)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: ReminderTile(item: i),
                        ),
                    ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The most urgent first.
const _order = [
  ReminderKind.overdue,
  ReminderKind.returnDue,
  ReminderKind.sendItems,
  ReminderKind.balance,
];

String reminderTitle(ReminderKind k, {bool service = false}) => switch (k) {
  ReminderKind.overdue => tr('Overdue returns'),
  ReminderKind.returnDue => tr('Due back soon'),
  ReminderKind.sendItems =>
    service ? tr('Appointments coming up') : tr('Send the items'),
  ReminderKind.balance => tr('Money to collect'),
};

/// "today", "tomorrow", "in 3 days", "2 days ago".
String whenText(int days) => days == 0
    ? tr('today')
    : days == 1
    ? tr('tomorrow')
    : days > 1
    ? tr('in {n} days', {'n': days})
    : tr('{n} days ago', {'n': -days});

class ReminderTile extends ConsumerWidget {
  const ReminderTile({super.key, required this.item});
  final ReminderItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = item.booking;
    final shop = ref.watch(profileProvider).valueOrNull;
    final text = Theme.of(context).textTheme;
    final days = item.daysAway(DateTime.now());
    final service = shop?.type.isService ?? false;
    final sub = switch (item.kind) {
      ReminderKind.sendItems when service =>
        '${tr('Appointment')} ${whenText(days)} · ${dateText(item.date)}'
            '${b.eventTime.isEmpty ? '' : ' · ${timeText(b.eventTime)}'}',
      ReminderKind.sendItems => '${tr('Pickup')} ${whenText(days)} · ${dateText(item.date)}',
      ReminderKind.balance => tr('Due {amount}', {'amount': money(b.balanceDue)}),
      _ => '${tr('Return')} ${whenText(days)} · ${dateText(item.date)}',
    };
    final urgent = item.kind == ReminderKind.overdue ||
        (item.kind == ReminderKind.sendItems && days <= 0);
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
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => BookingDetailScreen(bookingId: b.id),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '#${b.number}  ${b.customerName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        sub,
                        style: text.bodySmall?.copyWith(
                          color: urgent ? Palette.danger : null,
                          fontWeight: urgent ? FontWeight.w700 : null,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: tr('Send on WhatsApp'),
                  icon: const Icon(Icons.chat_outlined),
                  onPressed: shop == null
                      ? null
                      : () async {
                          final ok = await sendWhatsApp(
                            b.customerPhone,
                            reminderMessage(item.kind, b, shop),
                          );
                          if (!ok && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  tr('Could not open WhatsApp. Check the customer phone number.'),
                                ),
                              ),
                            );
                          }
                        },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
