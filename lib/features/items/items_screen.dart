import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../l10n/strings.dart';
import '../common/widgets.dart';
import 'item_form_screen.dart';

/// The things the shop rents out, with a search box and an add button.
class ItemsScreen extends ConsumerWidget {
  const ItemsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(itemsProvider);
    final searching = ref.watch(itemSearchProvider).trim().isNotEmpty;

    Future<void> open([RentItem? item]) async {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ItemFormScreen(item: item)),
      );
      ref.invalidate(itemsProvider);
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
                    tr('Items'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
                  onPressed: open,
                  icon: const Icon(Icons.add),
                  label: Text(tr('Add item')),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SearchField(
              hint: tr('Search items'),
              onChanged: (v) => ref.read(itemSearchProvider.notifier).state = v,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: items.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(tr('Error: {e}', {'e': e}))),
              data: (list) {
                if (list.isEmpty) {
                  return EmptyState(
                    icon: Icons.checkroom_outlined,
                    message: searching
                        ? tr('No item matches your search.')
                        : tr('Add the things you rent out, with their rate.'),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _ItemTile(
                    item: list[i],
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

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.onTap});
  final RentItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final sub = [
      if (item.category.isNotEmpty) tr(item.category),
      if (item.size.isNotEmpty) item.size,
    ].join(' · ');
    final unit = item.rateType == RateType.day ? tr('a day') : tr('an event');
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
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
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                  child: Text(
                    item.name.isEmpty ? '?' : item.name[0].toUpperCase(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
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
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (sub.isNotEmpty)
                        Text(sub, style: text.bodySmall, maxLines: 1),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      money(item.rate),
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(unit, style: text.labelSmall),
                    if (!item.status.bookable) ...[
                      const SizedBox(height: 4),
                      StatusChip(
                        label: item.status.label,
                        color: Palette.warning,
                      ),
                    ],
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
