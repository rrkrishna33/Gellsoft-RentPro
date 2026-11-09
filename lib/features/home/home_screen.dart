import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/app_settings.dart';
import '../../data/business_profile.dart';
import '../../data/dashboard_repo.dart';
import '../../l10n/strings.dart';
import '../settings/settings_screen.dart';

/// The app's frame: Home, Bookings, Items, Customers and More, with a bar at
/// the bottom to move between them.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, required this.profile});
  final BusinessProfile profile;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _HomeTab(profile: widget.profile),
      _SoonTab(
        title: tr('Bookings'),
        icon: Icons.event_available_outlined,
        line: tr('Bookings will appear here.'),
      ),
      _SoonTab(
        title: tr('Items'),
        icon: Icons.checkroom_outlined,
        line: tr('The things you rent out will appear here.'),
      ),
      _SoonTab(
        title: tr('Customers'),
        icon: Icons.people_alt_outlined,
        line: tr('Your customers will appear here.'),
      ),
      const SettingsScreen(),
    ];
    return Scaffold(
      body: RentBackground(child: SafeArea(child: pages[_tab])),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: tr('Home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.event_available_outlined),
            selectedIcon: const Icon(Icons.event_available),
            label: tr('Bookings'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.checkroom_outlined),
            selectedIcon: const Icon(Icons.checkroom),
            label: tr('Items'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.people_alt_outlined),
            selectedIcon: const Icon(Icons.people_alt),
            label: tr('Customers'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: tr('Settings'),
          ),
        ],
      ),
    );
  }
}

class _HomeTab extends ConsumerWidget {
  const _HomeTab({required this.profile});
  final BusinessProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(dashboardProvider).valueOrNull;
    final hide = ref.watch(hideAmountsProvider);
    final style = RentStyle.of(context);
    final text = Theme.of(context).textTheme;
    String amount(double v) => hide ? '••••' : money(v);
    final c = counts ?? const DashboardCounts();

    return RefreshIndicator(
      onRefresh: () => ref.refresh(dashboardProvider.future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: hide ? tr('Show amounts') : tr('Hide amounts'),
                icon: Icon(hide ? Icons.visibility_off : Icons.visibility),
                onPressed: () => ref.read(hideAmountsProvider.notifier).toggle(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: style.hero,
              borderRadius: BorderRadius.circular(24),
              boxShadow: style.heroShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Collected this month'),
                  style: text.labelLarge?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 6),
                Text(
                  amount(c.collectedThisMonth),
                  style: text.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  tr('Balance to collect'),
                  style: text.labelLarge?.copyWith(color: Colors.white70),
                ),
                Text(
                  amount(c.balanceDue),
                  style: text.titleLarge?.copyWith(
                    color: const Color(0xFFFFD98A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.7,
            children: [
              _Stat(
                label: tr('Pickups today'),
                value: c.pickupsToday,
                icon: Icons.outbox_outlined,
              ),
              _Stat(
                label: tr('Returns today'),
                value: c.returnsToday,
                icon: Icons.move_to_inbox_outlined,
              ),
              _Stat(
                label: tr('Overdue returns'),
                value: c.overdueReturns,
                icon: Icons.warning_amber_rounded,
                color: c.overdueReturns > 0 ? Palette.danger : null,
              ),
              _Stat(
                label: tr('Events this week'),
                value: c.eventsThisWeek,
                icon: Icons.celebration_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: RentStyle.of(context).softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: c),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ],
          ),
          Text(
            '$value',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: c,
            ),
          ),
        ],
      ),
    );
  }
}

class _SoonTab extends StatelessWidget {
  const _SoonTab({required this.title, required this.icon, required this.line});
  final String title;
  final IconData icon;
  final String line;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 56, color: scheme.primary.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                Text(line, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
