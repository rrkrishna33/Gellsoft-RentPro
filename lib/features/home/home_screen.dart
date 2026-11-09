import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/app_settings.dart';
import '../../data/booking_repo.dart';
import '../../data/business_profile.dart';
import '../../data/dashboard_repo.dart';
import '../../l10n/strings.dart';
import '../../core/pressable.dart';
import '../bookings/booking_detail_screen.dart';
import '../bookings/booking_form_screen.dart';
import '../bookings/bookings_screen.dart';
import '../customers/customers_screen.dart';
import '../items/items_screen.dart';
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

  Future<void> _newBooking() async {
    final id = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(builder: (_) => const BookingFormScreen()),
    );
    ref.invalidate(bookingsProvider);
    ref.invalidate(dashboardProvider);
    if (id != null && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BookingDetailScreen(bookingId: id),
        ),
      );
      ref.invalidate(bookingsProvider);
      ref.invalidate(dashboardProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _HomeTab(profile: widget.profile),
      const BookingsScreen(),
      const ItemsScreen(),
      const CustomersScreen(),
    ];
    return RentBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            SafeArea(bottom: false, child: pages[_tab]),
            Positioned(
              left: 16,
              right: 16,
              bottom: 0,
              child: _NavBar(
                index: _tab,
                onTab: (i) {
                  setState(() => _tab = i);
                  if (i == 0) ref.invalidate(dashboardProvider);
                },
                onNew: _newBooking,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The floating bar at the bottom: the screens used most, and a big button in
/// the middle to make a new booking.
class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.index,
    required this.onTab,
    required this.onNew,
  });
  final int index;
  final ValueChanged<int> onTab;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = RentStyle.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;

    Widget item(IconData icon, String label, int i) {
      final on = index == i;
      final color = on
          ? theme.colorScheme.primary
          : theme.colorScheme.onSurfaceVariant;
      return Expanded(
        child: InkWell(
          onTap: () => onTab(i),
          borderRadius: BorderRadius.circular(16),
          child: Semantics(
            label: label,
            button: true,
            selected: on,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 24, color: color),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: 12 + bottom),
      child: SizedBox(
        height: 64,
        // A Material, not a plain box: the button's gradient is painted on the
        // nearest Material, and must land above the bar.
        child: Material(
          color: theme.colorScheme.surface,
          elevation: 10,
          shadowColor: const Color(0x66000000),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              item(Icons.home_rounded, tr('Home'), 0),
              item(Icons.event_available_outlined, tr('Bookings'), 1),
              Tooltip(
                message: tr('New booking'),
                child: Pressable(
                  onTap: onNew,
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: style.cta,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: style.heroShadow,
                  ),
                  child: Icon(Icons.add, size: 30, color: style.onCta),
                ),
              ),
              item(Icons.checkroom_outlined, tr('Items'), 2),
              item(Icons.people_alt_outlined, tr('Customers'), 3),
            ],
          ),
        ),
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
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
              IconButton(
                tooltip: tr('Settings'),
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: Text(tr('Settings'))),
                      body: const RentBackground(child: SettingsScreen()),
                    ),
                  ),
                ),
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
