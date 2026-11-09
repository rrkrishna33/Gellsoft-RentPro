import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../l10n/strings.dart';
import '../common/widgets.dart';
import 'customer_form_screen.dart';

/// The shop's customers, with a search box and an add button.
class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customers = ref.watch(customersProvider);
    final searching = ref.watch(customerSearchProvider).trim().isNotEmpty;

    Future<void> open([Customer? c]) async {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => CustomerFormScreen(customer: c)),
      );
      ref.invalidate(customersProvider);
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tr('Customers'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
                  onPressed: open,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: Text(tr('Add customer')),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SearchField(
              hint: tr('Search by name or phone'),
              onChanged: (v) =>
                  ref.read(customerSearchProvider.notifier).state = v,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: customers.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(tr('Error: {e}', {'e': e}))),
              data: (list) {
                if (list.isEmpty) {
                  return EmptyState(
                    icon: Icons.people_alt_outlined,
                    message: searching
                        ? tr('No customer matches your search.')
                        : tr('Add your customers to book items for them.'),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _CustomerTile(
                    customer: list[i],
                    onTap: () => open(list[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({required this.customer, required this.onTap});
  final Customer customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: RentStyle.of(context).softShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  child: Text(
                    customer.name.isEmpty
                        ? '?'
                        : customer.name[0].toUpperCase(),
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (customer.phone.isNotEmpty)
                        Text(customer.phone, style: text.bodySmall),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
