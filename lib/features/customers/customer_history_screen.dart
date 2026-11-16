import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/booking_models.dart';
import '../../data/booking_repo.dart';
import '../../data/business_profile.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../bookings/booking_detail_screen.dart';
import '../bookings/bookings_screen.dart';

/// Every booking of one customer, with what they have been billed and what
/// they still owe, and the notes kept about them (preferences, measurements).
class CustomerHistoryScreen extends ConsumerWidget {
  const CustomerHistoryScreen({super.key, required this.customer});
  final Customer customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(customerBookingsProvider(customer.id!));
    final service =
        ref.watch(profileProvider).valueOrNull?.type.isService ?? false;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(customer.name)),
      body: AuroraBackground(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(tr('Error: {e}', {'e': e}))),
          data: (list) {
            final live = list.where((b) => b.status != BookingStatus.cancelled);
            final billed = live.fold(0.0, (a, b) => a + b.payable);
            final owed = live.fold(0.0, (a, b) => a + b.balanceDue);
            Widget stat(String label, String value, {Color? color}) => Expanded(
              child: Column(
                children: [
                  Text(
                    value,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  Text(label, style: text.bodySmall),
                ],
              ),
            );
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: AuroraStyle.of(context).softShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (customer.phone.isNotEmpty) Text(customer.phone),
                      if (customer.address.isNotEmpty)
                        Text(customer.address, style: text.bodySmall),
                      if (customer.phone.isNotEmpty ||
                          customer.address.isNotEmpty)
                        const SizedBox(height: 12),
                      Row(
                        children: [
                          stat(tr('Bookings'), '${live.length}'),
                          stat(tr('Billed'), money(billed)),
                          stat(
                            tr('Owes'),
                            money(owed),
                            color: owed > 0 ? Palette.danger : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (customer.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: AuroraStyle.of(context).softShadow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('Notes'),
                          style: text.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(customer.notes),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Text(
                  tr('Past bookings'),
                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(tr('This customer has no bookings yet.')),
                    ),
                  )
                else
                  for (final b in list) ...[
                    BookingTile(
                      booking: b,
                      service: service,
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => BookingDetailScreen(bookingId: b.id),
                          ),
                        );
                        ref.invalidate(customerBookingsProvider(customer.id!));
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }
}
