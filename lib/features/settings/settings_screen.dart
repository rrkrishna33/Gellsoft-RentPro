import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/restart_widget.dart';
import '../../data/app_settings.dart';
import '../../data/business_profile.dart';
import '../../l10n/strings.dart';
import '../onboarding/onboarding_screen.dart';

/// Shop details, language, theme and the app version.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final language = AppLanguage.fromCode(settings?.language);
    final mode = settings?.themeMode ?? ThemeMode.system;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        Text(
          tr('Settings'),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
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
