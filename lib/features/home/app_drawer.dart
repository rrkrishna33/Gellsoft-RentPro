import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../data/business_profile.dart';
import '../../l10n/strings.dart';
import '../invoices/invoice_list_screen.dart';
import '../reminders/reminders_screen.dart';
import '../reports/reports_screen.dart';
import '../../subscription/pro_ui.dart';
import '../settings/account_screen.dart';
import '../settings/backup_screen.dart';
import '../settings/billing_settings_screen.dart';
import 'home_screen.dart';

/// The left menu: where everything that is not on the bottom bar lives.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key, required this.profile});
  final BusinessProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final aurora = AuroraStyle.of(context);

    void go(Widget page) {
      Navigator.of(context).pop(); // close the menu
      openPage<void>(context, page);
    }

    Widget item(IconData icon, String label, Widget page) => ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: () => go(page),
    );

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: aurora.hero,
                borderRadius: BorderRadius.circular(22),
                boxShadow: aurora.heroShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    profile.type.label,
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  if (profile.gstEnabled && profile.gstin.isNotEmpty)
                    Text(
                      'GSTIN ${profile.gstin}',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  item(Icons.notifications_active_outlined, tr('Reminders'), const RemindersScreen()),
                  item(Icons.receipt_long_outlined, tr('Invoices'), const InvoiceListScreen()),
                  item(Icons.bar_chart_rounded, tr('Reports'), const ReportsScreen()),
                  const Divider(),
                  item(Icons.percent_rounded, tr('Billing and GST'), const BillingSettingsScreen()),
                  item(Icons.cloud_upload_outlined, tr('Backup and restore'), const BackupScreen()),
                  item(Icons.account_circle_outlined, tr('Account'), const AccountScreen()),
                  ListTile(
                    leading: const Icon(Icons.workspace_premium_outlined),
                    title: const Text('GellSoft Pro'),
                    onTap: () {
                      Navigator.of(context).pop();
                      showUpgradeScreen(context);
                    },
                  ),
                  item(Icons.settings_outlined, tr('Settings'), settingsPage()),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${AppInfo.appName}  ·  ${tr('Version')} ${AppInfo.version}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
