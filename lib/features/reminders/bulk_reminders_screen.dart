import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/share.dart';
import '../../core/theme.dart';
import '../../data/booking_models.dart';
import '../../data/booking_repo.dart';
import '../../data/business_profile.dart';
import '../../data/reminders.dart';
import '../../l10n/strings.dart';
import '../bookings/messages.dart';
import '../common/widgets.dart';

/// Everyone who still owes rent, in one list, each with a WhatsApp message
/// ready. WhatsApp opens for one customer at a time (that is how WhatsApp
/// works); **Send next** takes the next one that has not been sent yet.
class BulkRemindersScreen extends ConsumerStatefulWidget {
  const BulkRemindersScreen({super.key});

  @override
  ConsumerState<BulkRemindersScreen> createState() =>
      _BulkRemindersScreenState();
}

class _BulkRemindersScreenState extends ConsumerState<BulkRemindersScreen> {
  /// Bookings whose message was opened in this visit.
  final _sent = <int>{};

  Future<void> _send(Booking b) async {
    final shop = ref.read(profileProvider).valueOrNull;
    if (shop == null) return;
    final ok = await sendWhatsApp(
      b.customerPhone,
      reminderMessage(ReminderKind.balance, b, shop),
    );
    if (!mounted) return;
    if (ok) {
      setState(() => _sent.add(b.id));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr('Could not open WhatsApp. Check the customer phone number.'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_owingProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Remind everyone who owes'))),
      body: AuroraBackground(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(tr('Error: {e}', {'e': e}))),
          data: (list) {
            if (list.isEmpty) {
              return EmptyState(
                icon: Icons.task_alt_outlined,
                message: tr('Nobody owes you anything right now.'),
              );
            }
            final total = list.fold(0.0, (a, b) => a + b.balanceDue);
            final next = list.cast<Booking?>().firstWhere(
              (b) => !_sent.contains(b!.id) && b.customerPhone.trim().isNotEmpty,
              orElse: () => null,
            );
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text(
                    tr('{n} bookings, {amount} to collect', {
                      'n': list.length,
                      'amount': money(total),
                    }),
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final b = list[i];
                      final done = _sent.contains(b.id);
                      final hasPhone = b.customerPhone.trim().isNotEmpty;
                      return Container(
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: AuroraStyle.of(context).softShadow,
                        ),
                        child: ListTile(
                          title: Text('#${b.number}  ${b.customerName}'),
                          subtitle: Text(
                            hasPhone
                                ? tr('Due {amount}', {
                                    'amount': money(b.balanceDue),
                                  })
                                : tr('No phone number'),
                          ),
                          trailing: done
                              ? Icon(Icons.check_circle, color: Palette.success)
                              : IconButton(
                                  tooltip: tr('Send on WhatsApp'),
                                  icon: const Icon(Icons.chat_outlined),
                                  onPressed: hasPhone ? () => _send(b) : null,
                                ),
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: next == null ? null : () => _send(next),
                        icon: const Icon(Icons.send_outlined),
                        label: Text(
                          next == null
                              ? tr('All reminders sent')
                              : tr('Send next: {name}', {
                                  'name': next.customerName,
                                }),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

final _owingProvider = FutureProvider.autoDispose<List<Booking>>(
  (ref) => ref.watch(bookingRepoProvider).list(filter: BookingFilter.due),
);
