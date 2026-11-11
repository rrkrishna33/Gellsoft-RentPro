import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/restart_widget.dart';
import '../../data/cloud_backup.dart';
import '../../l10n/strings.dart';
import '../../subscription/account.dart';
import '../../subscription/gates.dart';
import '../../subscription/license_state.dart';
import '../../subscription/plan.dart';
import 'account_screen.dart';

String cloudMessage(CloudOutcome o) => switch (o.result) {
  CloudResult.done => '',
  CloudResult.cancelled => '',
  CloudResult.notSignedIn => tr('Sign in with Google first.'),
  CloudResult.notConnected => tr(
    'Drive backup is not allowed yet. Turn it on and allow access.',
  ),
  CloudResult.wrongAccount => tr(
    'Choose the same Google account you signed in with.',
  ),
  CloudResult.offline => tr(
    'Could not reach Google Drive. Check your internet and try again.',
  ),
  CloudResult.driveFull => tr(
    'Your Google Drive is full. Free some space and try again.',
  ),
  CloudResult.failed => tr('Drive backup did not work. Please try again.'),
  CloudResult.notFound => tr('No backup was found in this Google account.'),
  CloudResult.badBackup =>
    (o.message == null || o.message!.isEmpty)
        ? tr('This backup could not be read.')
        : o.message!,
};

String _size(int bytes) => bytes >= 1024 * 1024
    ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
    : '${(bytes / 1024).ceil()} KB';

/// Signs in if needed, lets the person allow Drive, picks a backup and
/// restores it. Used on the Backup screen and on a brand-new install.
Future<void> restoreFromDrive(BuildContext context, WidgetRef ref) async {
  void say(String s) {
    if (s.isEmpty || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s)));
  }

  final cloud = ref.read(cloudBackupProvider);

  if (ref.read(accountProvider).valueOrNull == null) {
    final r = await ref.read(accountProvider.notifier).signIn();
    if (r != SignInResult.signedIn) return say(signInMessage(r));
  }
  final connected = await cloud.connect();
  if (!connected.ok) return say(cloudMessage(connected));

  final found = await cloud.versions(interactive: true);
  if (!found.outcome.ok) return say(cloudMessage(found.outcome));
  if (!context.mounted) return;

  final file = found.files.length == 1
      ? found.files.first
      : await showDialog<DriveFile>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text(tr('Choose a backup')),
            children: [
              for (final f in found.files)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, f),
                  child: Text('${dateTimeText(f.modified)}   ${_size(f.size)}'),
                ),
            ],
          ),
        );
  if (file == null || !context.mounted) return;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Restore this backup?')),
      content: Text(
        '${dateTimeText(file.modified)}\n\n${tr('This replaces ALL current data on this phone (items, customers, bookings, photos and settings). This cannot be undone.')}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(tr('Cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tr('Restore')),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  final done = await cloud.restore(file, interactive: true);
  if (!context.mounted) return;
  if (!done.ok) return say(cloudMessage(done));
  say(tr('Backup restored'));
  RestartWidget.restart(context);
}

/// Google Drive backup: what it is, and the buttons for it.
class CloudBackupSection extends ConsumerStatefulWidget {
  const CloudBackupSection({super.key});

  @override
  ConsumerState<CloudBackupSection> createState() => _CloudBackupSectionState();
}

class _CloudBackupSectionState extends ConsumerState<CloudBackupSection> {
  bool _busy = false;
  CloudStatus? _status;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final s = await ref.read(cloudBackupProvider).status();
    if (mounted) setState(() => _status = s);
  }

  void _say(String s) {
    if (s.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _guard(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } finally {
      if (mounted) setState(() => _busy = false);
      await _reload();
    }
  }

  Future<void> _signIn() => _guard(() async {
    final r = await ref.read(accountProvider.notifier).signIn();
    _say(signInMessage(r));
  });

  Future<void> _turnOn() => _guard(() async {
    final r = await ref.read(cloudBackupProvider).connect();
    if (!r.ok) return _say(cloudMessage(r));
    // the first copy right away, so the person sees it work
    final b = await ref.read(cloudBackupProvider).backupNow(interactive: true);
    _say(b.ok ? tr('Backed up to Google Drive') : cloudMessage(b));
  });

  Future<void> _backupNow() => _guard(() async {
    final b = await ref.read(cloudBackupProvider).backupNow(interactive: true);
    _say(b.ok ? tr('Backed up to Google Drive') : cloudMessage(b));
  });

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      await restoreFromDrive(context, ref);
    } finally {
      if (mounted) setState(() => _busy = false);
      if (mounted) await _reload();
    }
  }

  Future<void> _setAuto(bool on) async {
    if (on && !await requirePro(context, ref, ProFeature.autoBackup)) return;
    await ref.read(cloudBackupProvider).setAuto(on);
    await _reload();
  }

  Future<void> _turnOff() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Turn off Drive backup?')),
        content: Text(
          tr(
            'Your data stays on this phone. You can also remove the backups already in your Google Drive.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'off'),
            child: Text(tr('Turn off')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'delete'),
            child: Text(
              tr('Turn off and delete backups'),
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (choice == null) return;
    await _guard(() async {
      final r = await ref
          .read(cloudBackupProvider)
          .disconnect(deleteBackups: choice == 'delete');
      _say(cloudMessage(r));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = ref.watch(accountProvider).valueOrNull;
    final status = _status;
    final on = status?.on ?? false;
    final entitlement =
        ref.watch(licenseProvider).value?.entitlement ?? unlockedWhileLoading;
    final proAuto = entitlement.allows(ProFeature.autoBackup);

    final spinner = _busy
        ? const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Center(child: CircularProgressIndicator()),
          )
        : const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tr('Google Drive backup'),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              tr(
                'Keeps an encrypted copy of your data in a private, hidden folder in your own Google Drive. Only this app can open it, and we never see it. Restore it on a new phone after signing in with the same Google account.',
              ),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (account == null) ...[
              FilledButton.icon(
                onPressed: _busy ? null : _signIn,
                icon: const Icon(Icons.login),
                label: Text(tr('Sign in with Google')),
              ),
            ] else if (!on) ...[
              FilledButton.icon(
                onPressed: _busy ? null : _turnOn,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(tr('Turn on Drive backup')),
              ),
            ] else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history),
                title: Text(tr('Last Drive backup')),
                subtitle: Text(
                  status?.last == null
                      ? tr('Never')
                      : dateTimeText(status!.last!),
                ),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : _backupNow,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(tr('Back up now')),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Automatic daily backup')),
                subtitle: Text(
                  proAuto
                      ? tr('Backs up once a day when you open the app')
                      : tr('Included in Pro'),
                ),
                value: proAuto && (status?.auto ?? true),
                onChanged: _busy ? null : _setAuto,
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _restore,
              icon: const Icon(Icons.cloud_download_outlined),
              label: Text(tr('Restore from Google Drive')),
            ),
            if (on)
              TextButton(
                onPressed: _busy ? null : _turnOff,
                child: Text(tr('Turn off Drive backup')),
              ),
            spinner,
          ],
        ),
      ),
    );
  }
}
