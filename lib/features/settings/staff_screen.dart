import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/staff.dart';
import '../../l10n/strings.dart';
import '../../subscription/gates.dart';
import '../../subscription/license_state.dart';
import '../../subscription/plan.dart';
import '../security/pin_dialog.dart';
import '../security/staff_login_screen.dart' show roleLabel;

String _roleInfo(Role r) => switch (r) {
  Role.admin => tr(
    'Everything: settings, backup, reports, GST files, cancelling and managing people.',
  ),
  Role.staff => tr(
    'Day-to-day work: bookings, payments, discounts, items, customers and reports. No GST files, settings or cancelling.',
  ),
  Role.cashier => tr(
    'Bookings and taking payments only. Cannot see reports, change items or give discounts.',
  ),
};

String _errorText(StaffException e) => switch (e.error) {
  StaffError.nameTaken => tr('That name is already used'),
  StaffError.nameEmpty => tr('Enter a name'),
  StaffError.lastAdmin => tr('There must always be an active Admin'),
  StaffError.badPin => tr('Use 4 to 6 digits'),
};

/// Settings → Security & backup → Staff logins. Admin only.
class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

  void _say(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _turnOn(BuildContext context, WidgetRef ref) async {
    if (!await requirePro(context, ref, ProFeature.staff)) return;
    if (!context.mounted) return;
    final r = await showDialog<_Person>(
      context: context,
      builder: (_) => _PersonDialog(
        title: tr('Set up the Admin'),
        fixedRole: Role.admin,
        needPin: true,
      ),
    );
    if (r == null || !context.mounted) return;
    try {
      final admin = await ref
          .read(staffRepoProvider)
          .add(name: r.name, role: Role.admin, pin: r.pin!);
      final code = await RecoveryCode.issue();
      // signed in first, so turning it on does not lock the Admin out
      ref.read(sessionProvider.notifier).login(admin);
      ref.invalidate(staffUsersProvider);
      if (context.mounted) await showRecoveryCode(context, code);
    } on StaffException catch (e) {
      if (context.mounted) _say(context, _errorText(e));
    }
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    // Adding people needs Pro. (Signing in, switching people off and turning
    // logins off never do, so a lapsed plan cannot lock anyone out.)
    if (!await requirePro(context, ref, ProFeature.staff)) return;
    if (!context.mounted) return;
    final r = await showDialog<_Person>(
      context: context,
      builder: (_) => _PersonDialog(title: tr('Add a person'), needPin: true),
    );
    if (r == null || !context.mounted) return;
    try {
      await ref
          .read(staffRepoProvider)
          .add(name: r.name, role: r.role, pin: r.pin!);
      ref.invalidate(staffUsersProvider);
    } on StaffException catch (e) {
      if (context.mounted) _say(context, _errorText(e));
    }
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    StaffUser u,
    bool isMe,
  ) async {
    final r = await showDialog<_Person>(
      context: context,
      builder: (_) => _PersonDialog(
        title: tr('Edit {name}', {'name': u.name}),
        existing: u,
        canSwitchOff: !isMe,
        canRemove: !isMe,
      ),
    );
    if (r == null || !context.mounted) return;
    // Taking someone's access away is always allowed. Any other change
    // (a name, a role, a new PIN, letting someone back in) needs Pro.
    final unchanged =
        !r.remove &&
        r.name == u.name &&
        r.role == u.role &&
        r.pin == null &&
        r.active == u.active;
    final revoking =
        r.remove ||
        (u.active &&
            !r.active &&
            r.name == u.name &&
            r.role == u.role &&
            r.pin == null);
    if (unchanged) return;
    if (!revoking && !await requirePro(context, ref, ProFeature.staff)) return;
    if (!context.mounted) return;
    final repo = ref.read(staffRepoProvider);
    try {
      if (r.remove) {
        await repo.remove(u.uuid);
      } else {
        await repo.update(u.uuid, name: r.name, role: r.role, active: r.active);
        if (r.pin != null) await repo.setPin(u.uuid, r.pin!);
      }
      ref.invalidate(staffUsersProvider);
    } on StaffException catch (e) {
      if (context.mounted) _say(context, _errorText(e));
    }
  }

  Future<void> _turnOff(
    BuildContext context,
    WidgetRef ref,
    StaffUser me,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Turn off staff logins?')),
        content: Text(
          tr(
            'Everyone is removed and the app opens without signing in. Past bookings keep the name of who made them.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Keep')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Turn off')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    // the Admin's own PIN, once more
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => PinDialog(title: tr('Enter your PIN')),
    );
    if (pin == null || !context.mounted) return;
    if (!me.checkPin(pin)) return _say(context, tr('Wrong PIN'));
    await ref.read(staffRepoProvider).clearAll();
    await RecoveryCode.clear();
    ref.read(sessionProvider.notifier).logout();
    ref.invalidate(staffUsersProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perms = ref.watch(permsProvider);
    final me = ref.watch(sessionProvider);
    final users = ref.watch(staffUsersProvider);
    final theme = Theme.of(context);

    if (!perms.can(Permission.manageStaff)) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Staff logins'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(tr('Only the Admin can manage staff logins')),
          ),
        ),
      );
    }

    // Pro has ended: the logins still work, but changing people needs Pro.
    final proActive =
        ref
            .watch(licenseProvider)
            .valueOrNull
            ?.entitlement
            .allows(ProFeature.staff) ??
        true;

    Widget roles() => Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final r in Role.values) ...[
              Text(
                roleLabel(r),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(_roleInfo(r), style: theme.textTheme.bodySmall),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(tr('Staff logins'))),
      floatingActionButton: (users.valueOrNull?.isNotEmpty ?? false)
          ? FloatingActionButton.extended(
              onPressed: () => _add(context, ref),
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(tr('Add a person')),
            )
          : null,
      body: users.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(tr('Error: {e}', {'e': e}))),
        data: (list) => list.isEmpty
            ? ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      tr(
                        'Give each person their own PIN and a role. Everyone signs in before using the app, and each booking shows who made it.',
                      ),
                    ),
                  ),
                  roles(),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton.icon(
                      onPressed: () => _turnOn(context, ref),
                      icon: const Icon(Icons.groups_2_outlined),
                      label: Text(tr('Turn on staff logins')),
                    ),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: 96),
                children: [
                  if (!proActive)
                    Card(
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      color: theme.colorScheme.tertiaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          tr(
                            'Pro has ended. Everyone can still sign in, and you can switch people off or turn logins off. Adding people or changing a role, name or PIN needs Pro.',
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onTertiaryContainer,
                          ),
                        ),
                      ),
                    ),
                  for (final u in list)
                    ListTile(
                      leading: CircleAvatar(
                        child: Text(u.name.characters.first.toUpperCase()),
                      ),
                      title: Text(
                        me?.uuid == u.uuid
                            ? '${u.name} (${tr('You')})'
                            : u.name,
                      ),
                      subtitle: Text(
                        u.active
                            ? roleLabel(u.role)
                            : '${roleLabel(u.role)} · ${tr('Switched off')}',
                      ),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => _edit(context, ref, u, me?.uuid == u.uuid),
                    ),
                  const Divider(),
                  ExpansionTile(
                    title: Text(tr('What each role can do')),
                    children: [roles()],
                  ),
                  if (me != null)
                    ListTile(
                      leading: Icon(
                        Icons.power_settings_new,
                        color: theme.colorScheme.error,
                      ),
                      title: Text(tr('Turn off staff logins')),
                      onTap: () => _turnOff(context, ref, me),
                    ),
                ],
              ),
      ),
    );
  }
}

/// What the add/edit dialog hands back.
class _Person {
  const _Person({
    required this.name,
    required this.role,
    this.pin,
    this.active = true,
    this.remove = false,
  });
  final String name;
  final Role role;
  final String? pin; // null = keep the current PIN
  final bool active;
  final bool remove;
}

class _PersonDialog extends StatefulWidget {
  const _PersonDialog({
    required this.title,
    this.existing,
    this.fixedRole,
    this.needPin = false,
    this.canSwitchOff = true,
    this.canRemove = false,
  });
  final String title;
  final StaffUser? existing;

  /// Set when the role is not a choice (the first person is the Admin).
  final Role? fixedRole;

  /// A new person must have a PIN; when editing it is optional.
  final bool needPin;
  final bool canSwitchOff;
  final bool canRemove;

  @override
  State<_PersonDialog> createState() => _PersonDialogState();
}

class _PersonDialogState extends State<_PersonDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  final _pin = TextEditingController();
  final _pin2 = TextEditingController();
  late Role _role = widget.fixedRole ?? widget.existing?.role ?? Role.cashier;
  late bool _active = widget.existing?.active ?? true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    _pin2.dispose();
    super.dispose();
  }

  void _ok() {
    final name = _name.text.trim();
    if (name.isEmpty) return setState(() => _error = tr('Enter a name'));
    final pin = _pin.text.trim();
    final wantsPin = widget.needPin || pin.isNotEmpty;
    if (wantsPin) {
      if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
        return setState(() => _error = tr('Use 4 to 6 digits'));
      }
      if (_pin2.text.trim() != pin) {
        return setState(() => _error = tr('PINs do not match'));
      }
    }
    Navigator.pop(
      context,
      _Person(
        name: name,
        role: _role,
        pin: wantsPin ? pin : null,
        active: _active,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: !editing,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: tr('Name')),
            ),
            if (widget.fixedRole == null) ...[
              const SizedBox(height: 12),
              Text(tr('Role'), style: theme.textTheme.labelLarge),
              RadioGroup<Role>(
                groupValue: _role,
                onChanged: (v) => setState(() => _role = v!),
                child: Column(
                  children: [
                    for (final r in Role.values)
                      RadioListTile<Role>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: r,
                        title: Text(roleLabel(r)),
                        subtitle: Text(
                          _roleInfo(r),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _pin,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              maxLength: 6,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: editing
                    ? tr('New PIN (leave empty to keep)')
                    : tr('PIN'),
                counterText: '',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pin2,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              maxLength: 6,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: tr('Confirm PIN'),
                counterText: '',
              ),
            ),
            if (editing && widget.canSwitchOff)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Can sign in')),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (editing && widget.canRemove)
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              _Person(name: widget.existing!.name, role: _role, remove: true),
            ),
            child: Text(
              tr('Remove'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Cancel')),
        ),
        TextButton(onPressed: _ok, child: Text(tr('Save'))),
      ],
    );
  }
}
