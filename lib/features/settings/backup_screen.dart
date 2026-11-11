import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/format.dart';
import '../../core/restart_widget.dart';
import '../../data/backup_service.dart';
import '../../l10n/strings.dart';
import 'cloud_backup_section.dart';

/// Export everything to a file and restore it later (or on a new phone).
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  DateTime? _last;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((sp) {
      final ms = sp.getInt(BackupService.lastBackupKey);
      if (ms != null && mounted) {
        setState(() => _last = DateTime.fromMillisecondsSinceEpoch(ms));
      }
    });
  }

  void _msg(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> _backup() async {
    setState(() => _busy = true);
    try {
      final bytes = await BackupService.create();
      final saved = await FilePicker.saveFile(
        fileName: BackupService.suggestedName(),
        bytes: bytes,
        mimeType: 'application/json',
        dialogTitle: tr('Save backup'),
      );
      if (saved == null) return; // cancelled
      final sp = await SharedPreferences.getInstance();
      final now = DateTime.now();
      await sp.setInt(BackupService.lastBackupKey, now.millisecondsSinceEpoch);
      if (mounted) {
        setState(() => _last = now);
        _msg(
          tr('Backup saved. Keep a copy somewhere safe, like Google Drive.'),
        );
      }
    } catch (e) {
      if (mounted) _msg(tr('Backup failed: {e}', {'e': e}));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final file = await FilePicker.pickFile(
      dialogTitle: tr('Choose a backup file'),
    );
    if (file == null || !mounted) return;
    final size = file.lengthSync() ?? await file.length() ?? 0;
    if (!mounted) return;
    if (size > BackupService.maxBackupBytes) {
      return _msg(tr('The backup file is too large'));
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Restore this backup?')),
        content: Text(
          '${file.name}\n\n${tr('This replaces ALL current data on this phone (items, customers, bookings, photos and settings). This cannot be undone.')}',
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
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await BackupService.restore(await file.readAsBytes());
      if (!mounted) return;
      _msg(tr('Backup restored'));
      RestartWidget.restart(context);
    } on FormatException catch (e) {
      if (mounted) _msg(e.message);
    } catch (e) {
      if (mounted) _msg(tr('Restore failed: {e}', {'e': e}));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Backup & restore'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const CloudBackupSection(),
          const SizedBox(height: 24),
          Text(
            tr('Backup to a file'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.history),
              title: Text(tr('Last backup')),
              subtitle: Text(
                _last == null ? tr('Never') : dateTimeText(_last!),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _backup,
            icon: const Icon(Icons.upload_file),
            label: Text(tr('Create backup')),
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              'Saves items, customers, bookings, payments, photos and settings to one file. Pick a folder or Google Drive in the next screen.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _busy ? null : _restore,
            icon: const Icon(Icons.download),
            label: Text(tr('Restore from backup')),
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              'Use this on a new phone or after reinstalling. It replaces all data currently in the app.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
