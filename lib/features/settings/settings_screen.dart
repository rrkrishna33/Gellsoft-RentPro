import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/restart_widget.dart';
import '../../data/app_settings.dart';
import '../../data/business_profile.dart';
import '../../data/staff.dart';
import '../../l10n/strings.dart';
import '../../data/notifications.dart';
import '../../subscription/entitlement.dart';
import '../../subscription/plan.dart';
import '../../subscription/pro_prompt.dart';
import '../../subscription/pro_ui.dart';
import '../onboarding/onboarding_screen.dart';
import '../shops/shop_switcher.dart';
import 'account_screen.dart';
import 'backup_screen.dart';
import 'billing_settings_screen.dart';
import 'staff_screen.dart';

/// Shop details, language, theme and the app version.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final language = AppLanguage.fromCode(settings?.language);
    final mode = settings?.themeMode ?? ThemeMode.dark;
    final isPro = ref.watch(isProProvider);
    final notify = ref.watch(notifySettingsProvider).valueOrNull ?? const NotifySettings();

    Future<void> change(NotifySettings next) async {
      await ref.read(notifySettingsProvider.notifier).setSettings(next);
      if (next.daily || next.beforeEvent) await NotificationService.askPermission();
      await syncNotifications(ref);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: Text(profile?.name ?? ''),
                subtitle: Text(profile?.type.label ?? ''),
                trailing: const Icon(Icons.chevron_right),
                onTap: profile == null
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => OnboardingScreen(editing: profile),
                        ),
                      ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.language),
                title: Text(tr('Language')),
                trailing: DropdownButton<AppLanguage>(
                  value: language,
                  underline: const SizedBox(),
                  items: [
                    for (final l in AppLanguage.values)
                      DropdownMenuItem(value: l, child: Text(l.label)),
                  ],
                  onChanged: (l) async {
                    if (l == null) return;
                    await ref
                        .read(appSettingsProvider.notifier)
                        .setLanguage(l.code);
                    if (context.mounted) RestartWidget.restart(context);
                  },
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.brightness_6_outlined),
                title: Text(tr('Theme')),
                trailing: DropdownButton<ThemeMode>(
                  value: mode,
                  underline: const SizedBox(),
                  items: [
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text(tr('Same as phone')),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.light,
                      child: Text(tr('Light')),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.dark,
                      child: Text(tr('Dark')),
                    ),
                  ],
                  onChanged: (m) {
                    if (m != null) {
                      ref.read(appSettingsProvider.notifier).setThemeMode(m);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.store_mall_directory_outlined),
                title: Text(tr('Your shops')),
                subtitle: Text(
                  tr('Run more than one shop, each kept separately'),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showShopSwitcher(context),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.groups_2_outlined),
                title: Text(tr('Staff logins')),
                subtitle: Text(
                  (ref.watch(staffUsersProvider).valueOrNull?.isNotEmpty ??
                          false)
                      ? tr('On')
                      : tr('Admin, Staff and Cashier with their own PINs'),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const StaffScreen()),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.workspace_premium_outlined),
                title: const Text('GellSoft Pro'),
                subtitle: Text(
                  planSummary(
                    ref.watch(entitlementProvider),
                    DateTime.now(),
                    null,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showUpgradeScreen(context),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(tr('Account')),
                subtitle: Text(tr('Sign in with Google to back up and restore')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AccountScreen()),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: Text(tr('Backup and restore')),
            subtitle: Text(tr('Keep your data safe, or move it to a new phone')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const BackupScreen()),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.percent_rounded),
            title: Text(tr('Billing and GST')),
            subtitle: Text(
              profile?.gstEnabled ?? false
                  ? tr('GST is on')
                  : tr('GST is off'),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const BillingSettingsScreen(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: isPro
              ? Column(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.wb_sunny_outlined),
                      title: Text(tr('Morning summary')),
                      subtitle: Text(tr('What to send, collect and bring back today')),
                      value: notify.daily,
                      onChanged: (v) => change(notify.copyWith(daily: v)),
                    ),
                    const Divider(),
                    SwitchListTile(
                      secondary: const Icon(Icons.event_available_outlined),
                      title: Text(tr('Reminder before each event')),
                      subtitle: Text(
                        tr('Set on every booking: how many days before'),
                      ),
                      value: notify.beforeEvent,
                      onChanged: (v) => change(notify.copyWith(beforeEvent: v)),
                    ),
                    const Divider(),
                    for (final (i, m) in notify.times.indexed)
                      ListTile(
                        leading: const Icon(Icons.schedule),
                        title: Text(
                          i == 0 ? tr('Reminder time') : tr('Another reminder'),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              TimeOfDay(hour: m ~/ 60, minute: m % 60)
                                  .format(context),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (notify.times.length > 1)
                              IconButton(
                                tooltip: tr('Remove'),
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => change(
                                  notify.withTimes([
                                    for (final x in notify.times)
                                      if (x != m) x,
                                  ]),
                                ),
                              ),
                          ],
                        ),
                        onTap: () async {
                          final t = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
                          );
                          if (t == null) return;
                          await change(
                            notify.withTimes([
                              for (final x in notify.times)
                                if (x != m) x,
                              t.hour * 60 + t.minute,
                            ]),
                          );
                        },
                      ),
                    if (notify.times.length < NotifySettings.maxTimes)
                      ListTile(
                        leading: const Icon(Icons.add_alarm),
                        title: Text(tr('Add a reminder time')),
                        subtitle: Text(
                          tr('Be reminded more than once a day, up to {n} times', {
                            'n': NotifySettings.maxTimes,
                          }),
                        ),
                        onTap: () async {
                          final t = await showTimePicker(
                            context: context,
                            initialTime: const TimeOfDay(hour: 18, minute: 0),
                          );
                          if (t == null) return;
                          await change(
                            notify.withTimes([
                              ...notify.times,
                              t.hour * 60 + t.minute,
                            ]),
                          );
                        },
                      ),
                  ],
                )
              : ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: Text(tr('Reminder notifications')),
                  subtitle: Text(
                    tr('A morning summary and a reminder before each event. Part of Pro.'),
                  ),
                  trailing: const Icon(Icons.lock_outline),
                  onTap: () => showProPrompt(context, ProFeature.notifications),
                ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(AppInfo.appName),
            subtitle: Text('${tr('Version')} ${AppInfo.version}'),
          ),
        ),
      ],
    );
  }
}
