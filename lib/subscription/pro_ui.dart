import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../features/settings/account_screen.dart';
import '../l10n/strings.dart';
import 'billing.dart';
import 'license_state.dart';
import 'plan.dart';
import 'subscribe_section.dart';

/// One line for the menu and the Pro screen describing the current plan.
String planSummary(Entitlement e, DateTime now, int? bookingsUsed) {
  if (!e.enforced) {
    return tr('All features are unlocked during the launch period');
  }
  switch (e.tier) {
    case Tier.pro:
      return tr('Pro is active');
    case Tier.trial:
      final days = e.trialDaysLeft(now) ?? 0;
      return days == 1
          ? tr('Free trial: 1 day left')
          : tr('Free trial: {days} days left', {'days': days});
    case Tier.free:
      return bookingsUsed == null
          ? tr('Free plan')
          : tr('Free plan: {used} of {limit} bookings used this month', {
              'used': bookingsUsed,
              'limit': FreePlan.bookingsPerMonth,
            });
  }
}

/// Opens the Pro screen. [feature] says which locked thing the user tried.
Future<void> showUpgradeScreen(BuildContext context, {ProFeature? feature}) =>
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => UpgradeScreen(feature: feature)));

class UpgradeScreen extends ConsumerStatefulWidget {
  const UpgradeScreen({super.key, this.feature});
  final ProFeature? feature;

  @override
  ConsumerState<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends ConsumerState<UpgradeScreen> {
  @override
  void initState() {
    super.initState();
    // A message from an earlier visit ("Pro is now active") is out of date.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(billingProvider.notifier).clearNote();
    });
  }

  @override
  Widget build(BuildContext context) => _UpgradeBody(feature: widget.feature);
}

class _UpgradeBody extends ConsumerWidget {
  const _UpgradeBody({this.feature});
  final ProFeature? feature;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final aurora = AuroraStyle.of(context);
    final license = ref.watch(licenseProvider).value;
    final e = license?.entitlement ?? unlockedWhileLoading;
    final used = (e.enforced && e.tier == Tier.free)
        ? ref.watch(bookingsThisMonthProvider).value
        : null;
    final now = license?.now ?? DateTime.now();

    Widget bullet(IconData icon, String text, Color color) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );

    final proItems = [
      tr('Unlimited bookings every month'),
      tr('Unlimited photos on every booking'),
      tr('Daily and custom reminder notifications'),
      tr('Several reminder times a day'),
      tr('Automatic daily backup to Google Drive'),
      tr('More than one shop, each kept separately'),
      tr('Staff logins (Admin, Staff, Cashier)'),
    ];
    final freeItems = [
      tr('{n} new bookings every month', {'n': FreePlan.bookingsPerMonth}),
      tr('{n} photos on each booking', {'n': FreePlan.photosPerBooking}),
      tr('Items, customers, invoices and GST'),
      tr('WhatsApp messages and reminders to customers'),
      tr('Reports and export to Excel (CSV)'),
      tr('Backup and restore, Tamil and English'),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(tr('GellSoft Pro'))),
      body: AuroraBackground(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: aurora.hero,
                borderRadius: BorderRadius.circular(24),
                boxShadow: aurora.heroShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    planSummary(e, now, used),
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (e.enforced &&
                      e.tier == Tier.pro &&
                      (e.paidUntil ?? e.proUntil) != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      tr('Pro until {date}', {
                        'date': DateFormat(
                          'dd MMM yyyy',
                        ).format((e.paidUntil ?? e.proUntil)!),
                      }),
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ],
              ),
            ),
            if (feature != null && !e.allows(feature!)) ...[
              const SizedBox(height: 12),
              Card(
                color: theme.colorScheme.errorContainer,
                child: ListTile(
                  leading: Icon(
                    Icons.lock_outline,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  title: Text(
                    tr('{feature} needs Pro', {'feature': feature!.label}),
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text(tr('With Pro'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            for (final item in proItems)
              bullet(Icons.check_circle, item, theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(tr('Always free'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            for (final item in freeItems)
              bullet(Icons.check, item, theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              tr(
                'Your data always stays yours: you can view and export everything, even on the free plan.',
              ),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            if (e.enforced) ...[
              const AccountPrompt(),
              SubscribeSection(isPro: e.tier == Tier.pro),
            ] else
              FilledButton(
                onPressed: null, // buying opens when the paywall is switched on
                child: Text(tr('Subscriptions are coming soon')),
              ),
            if (license != null) ...[
              const SizedBox(height: 24),
              Card(
                child: ListTile(
                  title: Text(tr('Your install ID')),
                  subtitle: Text(
                    '${license.installId}\n${tr('Give this to support if you need help.')}',
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    tooltip: tr('Copy'),
                    icon: const Icon(Icons.copy),
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: license.installId),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(tr('Copied'))));
                      }
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
