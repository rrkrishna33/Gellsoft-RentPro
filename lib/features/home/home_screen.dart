import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/pressable.dart';
import '../../core/theme.dart';
import '../../data/app_settings.dart';
import '../../data/booking_repo.dart';
import '../../data/business_profile.dart';
import '../../data/dashboard_repo.dart';
import '../../data/notifications.dart';
import '../../data/reminders.dart';
import '../../l10n/strings.dart';
import '../bookings/booking_detail_screen.dart';
import '../bookings/booking_form_screen.dart';
import '../bookings/bookings_screen.dart';
import '../customers/customers_screen.dart';
import '../invoices/invoice_list_screen.dart';
import '../items/items_screen.dart';
import '../reminders/reminders_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/billing_settings_screen.dart';
import '../settings/settings_screen.dart';
import 'app_drawer.dart';

/// Opens a page on top of the app frame.
Future<T?> openPage<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute<T>(builder: (_) => page));

/// The Settings page, with its own title bar.
Widget settingsPage() => Builder(
  builder: (context) => Scaffold(
    appBar: AppBar(title: Text(tr('Settings'))),
    body: const AuroraBackground(child: SettingsScreen()),
  ),
);

/// The app's frame: Home, Bookings, Items and Customers, with a floating bar
/// at the bottom to move between them and a big button to make a booking.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, required this.profile});
  final BusinessProfile profile;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => syncNotifications(ref));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  void _refresh() {
    ref.invalidate(bookingsProvider);
    ref.invalidate(dashboardProvider);
    ref.invalidate(remindersProvider);
    syncNotifications(ref);
  }

  Future<void> _newBooking() async {
    final id = await openPage<int>(context, const BookingFormScreen());
    _refresh();
    if (id != null && mounted) {
      await openPage<void>(context, BookingDetailScreen(bookingId: id));
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _HomeTab(
        profile: widget.profile,
        onTab: (i) => setState(() => _tab = i),
        onNewBooking: _newBooking,
      ),
      const BookingsScreen(),
      const ItemsScreen(),
      const CustomersScreen(),
    ];
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        drawer: AppDrawer(profile: widget.profile),
        body: Stack(
          children: [
            SafeArea(
              bottom: false,
              // tabs other than Home have no menu button, so give them one
              child: _tab == 0
                  ? pages[0]
                  : Column(
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Builder(
                            builder: (ctx) => Padding(
                              padding: const EdgeInsets.fromLTRB(8, 4, 0, 0),
                              child: IconButton(
                                tooltip: tr('Menu'),
                                icon: const Icon(Icons.menu),
                                onPressed: () => Scaffold.of(ctx).openDrawer(),
                              ),
                            ),
                          ),
                        ),
                        Expanded(child: pages[_tab]),
                      ],
                    ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 0,
              child: _NavBar(
                index: _tab,
                onTab: (i) {
                  setState(() => _tab = i);
                  if (i == 0) _refresh();
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
    final aurora = AuroraStyle.of(context);
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
                    gradient: aurora.cta,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: aurora.ctaShadow,
                  ),
                  child: Icon(Icons.add, size: 30, color: aurora.onCta),
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
  const _HomeTab({
    required this.profile,
    required this.onTab,
    required this.onNewBooking,
  });
  final BusinessProfile profile;
  final ValueChanged<int> onTab;
  final VoidCallback onNewBooking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminders = ref.watch(remindersProvider).valueOrNull ?? const [];
    final accents = Theme.of(context).extension<TileAccents>();
    final big = MediaQuery.textScalerOf(context).scale(1) > 1.25;

    final tiles = <_Tile>[
      _Tile(tr('Bookings'), Icons.event_available_outlined, () => onTab(1)),
      _Tile(tr('Items'), Icons.checkroom_outlined, () => onTab(2)),
      _Tile(tr('Customers'), Icons.people_alt_outlined, () => onTab(3)),
      _Tile(
        tr('Reminders'),
        Icons.notifications_active_outlined,
        () => openPage<void>(context, const RemindersScreen()),
        badge: reminders.length,
      ),
      _Tile(
        tr('Invoices'),
        Icons.receipt_long_outlined,
        () => openPage<void>(context, const InvoiceListScreen()),
      ),
      _Tile(
        tr('Reports'),
        Icons.bar_chart_rounded,
        () => openPage<void>(context, const ReportsScreen()),
      ),
      _Tile(
        tr('Billing and GST'),
        Icons.percent_rounded,
        () => openPage<void>(context, const BillingSettingsScreen()),
      ),
      _Tile(
        tr('Settings'),
        Icons.settings_outlined,
        () => openPage<void>(context, settingsPage()),
      ),
    ];

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(remindersProvider);
        ref.invalidate(dashboardProvider);
        await ref.read(dashboardProvider.future);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(profile: profile),
            const SizedBox(height: 14),
            const _Dashboard(),
            if (reminders.isNotEmpty) ...[
              const SizedBox(height: 14),
              _AttentionCard(items: reminders),
            ],
            const SizedBox(height: 20),
            Text(
              tr('Quick actions'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            _NewBookingBanner(onTap: onNewBooking),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: big ? 2 : 3,
              childAspectRatio: big ? 1.0 : 0.95,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: [
                for (final (i, t) in tiles.indexed)
                  _ShortcutTile(tile: t, color: accents?.at(i)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.profile});
  final BusinessProfile profile;

  String _greeting(DateTime now) => now.hour < 12
      ? tr('Good morning')
      : now.hour < 17
      ? tr('Good afternoon')
      : tr('Good evening');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aurora = AuroraStyle.of(context);
    final shopName = profile.name.trim();
    final initial = String.fromCharCode(
      (shopName.isEmpty ? '?' : shopName).runes.first,
    ).toUpperCase();

    return Row(
      children: [
        Builder(
          builder: (ctx) => Pressable(
            onTap: () => Scaffold.of(ctx).openDrawer(),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              boxShadow: aurora.softShadow,
            ),
            child: Icon(Icons.menu, color: theme.colorScheme.onSurface),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting(DateTime.now()),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              Text(
                profile.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Pressable(
          onTap: () => openPage<void>(context, settingsPage()),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: aurora.cta,
            boxShadow: aurora.ctaShadow,
          ),
          child: Center(
            child: Text(
              initial,
              style: theme.textTheme.titleMedium?.copyWith(
                color: aurora.onCta,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Dashboard extends ConsumerWidget {
  const _Dashboard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(dashboardProvider).valueOrNull;
    final hidden = ref.watch(hideAmountsProvider);
    final aurora = AuroraStyle.of(context);
    final text = Theme.of(context).textTheme;
    final c = counts ?? const DashboardCounts();

    const onCard = Colors.white;
    final soft = onCard.withValues(alpha: 0.78);
    // A light warm tone that stays readable on the purple card.
    const warn = Color(0xFFFFD9A8);
    String shown(double v) => hidden ? '₹ ••••••' : money(v);

    Widget stat(String label, String value, {Color? color}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(color: soft),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: text.titleMedium?.copyWith(color: color ?? onCard),
            ),
          ),
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        gradient: aurora.hero,
        borderRadius: BorderRadius.circular(26),
        boxShadow: aurora.heroShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          children: [
            // soft light blobs, for depth
            Positioned(
              right: -50,
              top: -60,
              child: _Glow(size: 190, opacity: 0.20),
            ),
            Positioned(
              left: -40,
              bottom: -70,
              child: _Glow(size: 160, opacity: 0.10),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          tr('Collected this month'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(color: soft),
                        ),
                      ),
                      IconButton(
                        tooltip: hidden
                            ? tr('Show amounts')
                            : tr('Hide amounts'),
                        onPressed: () =>
                            ref.read(hideAmountsProvider.notifier).toggle(),
                        icon: Icon(
                          hidden
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                          color: soft,
                        ),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 32,
                        ),
                      ),
                    ],
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      counts == null ? '...' : shown(c.collectedThisMonth),
                      style: text.headlineMedium?.copyWith(
                        color: onCard,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.only(top: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: onCard.withValues(alpha: 0.2)),
                      ),
                    ),
                    child: Row(
                      children: [
                        stat(
                          tr('To collect'),
                          counts == null ? '...' : shown(c.balanceDue),
                          color: c.balanceDue > 0 ? warn : null,
                        ),
                        stat(tr('Out today'), '${c.pickupsToday}'),
                        stat(tr('Back today'), '${c.returnsToday}'),
                        stat(
                          tr('Overdue'),
                          '${c.overdueReturns}',
                          color: c.overdueReturns > 0 ? warn : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.opacity});
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: opacity),
    ),
  );
}

/// The most urgent things from the reminders, and a way into the full list.
class _AttentionCard extends StatelessWidget {
  const _AttentionCard({required this.items});
  final List<ReminderItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aurora = AuroraStyle.of(context);
    final first = items.take(3).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: aurora.softShadow,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.notifications_active_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('{n} things need you today', {'n': items.length}),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              TextButton(
                onPressed: () =>
                    openPage<void>(context, const RemindersScreen()),
                child: Text(tr('See all')),
              ),
            ],
          ),
          for (final i in first)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => openPage<void>(
                context,
                BookingDetailScreen(bookingId: i.booking.id),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${reminderTitle(i.kind)}: #${i.booking.number} ${i.booking.customerName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      whenText(i.daysAway(DateTime.now())),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: i.kind == ReminderKind.overdue
                            ? Palette.danger
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NewBookingBanner extends StatelessWidget {
  const _NewBookingBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final aurora = AuroraStyle.of(context);
    final text = Theme.of(context).textTheme;
    return Pressable(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: aurora.cta,
        borderRadius: BorderRadius.circular(22),
        boxShadow: aurora.ctaShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: aurora.onCta.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(Icons.event_available, size: 26, color: aurora.onCta),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('New booking'),
                  style: text.titleMedium?.copyWith(
                    color: aurora.onCta,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  tr('Pick the customer, the items and the dates'),
                  style: text.bodySmall?.copyWith(
                    color: aurora.onCta.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: aurora.onCta.withValues(alpha: 0.2),
            ),
            child: Icon(Icons.chevron_right, size: 22, color: aurora.onCta),
          ),
        ],
      ),
    );
  }
}

class _Tile {
  const _Tile(this.label, this.icon, this.onTap, {this.badge = 0});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  /// A number shown on the tile (things waiting); 0 shows nothing.
  final int badge;
}

class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({required this.tile, required this.color});
  final _Tile tile;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aurora = AuroraStyle.of(context);
    final accent = color ?? theme.colorScheme.primary;
    return Pressable(
      onTap: tile.onTap,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: aurora.softShadow,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
        // Long (Tamil) names wrap; if it is still too tall, shrink to fit.
        child: LayoutBuilder(
          builder: (context, box) => FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: box.maxWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color.lerp(accent, Colors.white, 0.18)!,
                              accent,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(tile.icon, size: 26, color: Colors.white),
                      ),
                      if (tile.badge > 0)
                        Positioned(
                          right: -6,
                          top: -6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Palette.danger,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              '${tile.badge}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tile.label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
