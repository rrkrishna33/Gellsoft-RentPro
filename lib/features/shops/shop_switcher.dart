import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/restart_widget.dart';
import '../../data/business_profile.dart';
import '../../data/shops.dart';
import '../../data/staff.dart';
import '../../l10n/strings.dart';
import '../../subscription/gates.dart';
import '../../subscription/plan.dart';
import '../common/widgets.dart';
import '../onboarding/onboarding_screen.dart';

/// Opens another shop: its own items, customers, bookings, invoices and
/// people. Everyone is signed out, and every screen starts again on the new
/// shop.
Future<void> switchShop(BuildContext context, String id) async {
  if (id == Shops.activeId) return;
  forgetSignedInPerson();
  await Shops.activate(id);
  if (context.mounted) RestartWidget.restart(context);
}

/// The list of shops on this phone: tap one to open it, add a new one (Pro),
/// or press and hold one to delete it.
Future<void> showShopSwitcher(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => const ShopSwitcher(),
);

class ShopSwitcher extends ConsumerWidget {
  const ShopSwitcher({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    if (!await requirePro(context, ref, ProFeature.multiShop)) return;
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const OnboardingScreen(newShop: true),
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    String id,
    String name,
  ) async {
    final ok = await confirmRemove(
      context,
      title: tr('Delete {name}?', {'name': name}),
      message: tr(
        'All of this shop\'s items, customers, bookings and invoices are deleted from this phone. This cannot be undone.',
      ),
    );
    if (!ok || !context.mounted) return;
    final wasOpen = id == Shops.activeId;
    forgetSignedInPerson();
    await Shops.remove(id);
    ref.invalidate(shopNamesProvider);
    if (!context.mounted) return;
    if (wasOpen) {
      RestartWidget.restart(context);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shops = ref.watch(shopNamesProvider).valueOrNull ?? const {};
    final canManage = ref.watch(permsProvider).can(Permission.settings);
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Your shops'),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tr('Each shop keeps its own items, customers, bookings and invoices.'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final e in shops.entries)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: e.key == Shops.activeId
                            ? theme.colorScheme.primary
                            : theme.colorScheme.surfaceContainerHighest,
                        foregroundColor: e.key == Shops.activeId
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface,
                        child: Text(
                          e.value.name.trim().isEmpty
                              ? '?'
                              : String.fromCharCode(
                                  e.value.name.trim().runes.first,
                                ).toUpperCase(),
                        ),
                      ),
                      title: Text(e.value.name),
                      subtitle: Text(e.value.type.label),
                      trailing: e.key == Shops.activeId
                          ? Icon(
                              Icons.check_circle,
                              color: theme.colorScheme.primary,
                            )
                          : null,
                      onTap: () async {
                        Navigator.of(context).pop();
                        await switchShop(context, e.key);
                      },
                      onLongPress: canManage && e.key != Shops.mainId
                          ? () => _delete(context, ref, e.key, e.value.name)
                          : null,
                    ),
                ],
              ),
            ),
            if (canManage) ...[
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.add_business_outlined),
                title: Text(tr('Add a shop')),
                subtitle: Text(tr('Part of Pro')),
                onTap: () => _add(context, ref),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
