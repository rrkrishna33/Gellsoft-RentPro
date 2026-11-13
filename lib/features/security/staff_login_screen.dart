import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/pin_lockout.dart';
import '../../data/staff.dart';
import '../../l10n/strings.dart';
import 'pin_dialog.dart';

String roleLabel(Role r) => switch (r) {
  Role.admin => tr('Admin'),
  Role.staff => tr('Staff'),
  Role.cashier => tr('Cashier'),
};

/// "Who is using the app?" then that person's PIN. Shown instead of the plain
/// PIN screen while staff logins are on and nobody is signed in.
class StaffLoginScreen extends ConsumerStatefulWidget {
  const StaffLoginScreen({
    super.key,
    required this.users,
    required this.onLoggedIn,
  });

  /// Everyone who may sign in (switched-off people are left out).
  final List<StaffUser> users;
  final void Function(StaffUser user) onLoggedIn;

  @override
  ConsumerState<StaffLoginScreen> createState() => _StaffLoginScreenState();
}

class _StaffLoginScreenState extends ConsumerState<StaffLoginScreen> {
  final _pin = TextEditingController();
  String? _error;
  StaffUser? _selected;
  PinLockout _lockout = PinLockout();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // One person only: no need to pick.
    if (widget.users.length == 1) _selected = widget.users.first;
    PinLockout.load().then((l) {
      if (!mounted) return;
      setState(() => _lockout = l);
      _watchLockout();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pin.dispose();
    super.dispose();
  }

  bool get _locked => _lockout.isLocked(DateTime.now());

  void _watchLockout() {
    _ticker?.cancel();
    if (!_locked) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (!_locked) t.cancel();
      setState(() {});
    });
  }

  Future<void> _failed(String message) async {
    _lockout.recordFailure(DateTime.now());
    await _lockout.save();
    if (!mounted) return;
    setState(() => _error = message);
    _pin.clear();
    _watchLockout();
  }

  Future<void> _submit() async {
    final user = _selected;
    if (user == null || _locked) return;
    if (user.checkPin(_pin.text.trim())) {
      _lockout.reset();
      await _lockout.save();
      widget.onLoggedIn(user);
      return;
    }
    await _failed(tr('Wrong PIN'));
  }

  /// An Admin who forgot the PIN: the recovery code lets them set a new one.
  Future<void> _forgot(StaffUser admin) async {
    if (_locked) return;
    final typed = await showDialog<String>(
      context: context,
      builder: (_) => const RecoveryCodeDialog(),
    );
    if (typed == null || !mounted) return;
    if (!await RecoveryCode.check(typed)) {
      return _failed(tr('Wrong recovery code'));
    }
    _lockout.reset();
    await _lockout.save();
    if (!mounted) return;
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => PinDialog(
        title: tr('Set a new PIN for {name}', {'name': admin.name}),
        confirm: true,
      ),
    );
    if (pin == null || !mounted) return;
    final repo = ref.read(staffRepoProvider);
    await repo.setPin(admin.uuid, pin);
    // the old code is used up: here is a fresh one
    final fresh = await RecoveryCode.issue();
    if (!mounted) return;
    await showRecoveryCode(context, fresh);
    ref.invalidate(staffUsersProvider);
    final updated = (await repo.list()).firstWhere((u) => u.uuid == admin.uuid);
    if (mounted) widget.onLoggedIn(updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = _selected;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 44),
                  const SizedBox(height: 10),
                  Text(AppInfo.appName, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 22),
                  if (user == null) ...[
                    Text(
                      tr('Who is using the app?'),
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    for (final u in widget.users)
                      Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text(u.name.characters.first.toUpperCase()),
                          ),
                          title: Text(u.name),
                          subtitle: Text(roleLabel(u.role)),
                          onTap: () => setState(() {
                            _selected = u;
                            _error = null;
                            _pin.clear();
                          }),
                        ),
                      ),
                  ] else ...[
                    CircleAvatar(
                      radius: 26,
                      child: Text(
                        user.name.characters.first.toUpperCase(),
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(user.name, style: theme.textTheme.titleMedium),
                    Text(
                      roleLabel(user.role),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _pin,
                      autofocus: true,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      enabled: !_locked,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 6,
                      decoration: InputDecoration(
                        labelText: tr('Enter PIN'),
                        counterText: '',
                        errorText: _locked
                            ? tr(
                                'Too many wrong attempts. Try again in {seconds} s',
                                {
                                  'seconds':
                                      (_lockout
                                                  .remaining(DateTime.now())
                                                  .inMilliseconds /
                                              1000)
                                          .ceil()
                                          .clamp(1, 1 << 30),
                                },
                              )
                            : _error,
                      ),
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _locked ? null : _submit,
                        child: Text(tr('Unlock')),
                      ),
                    ),
                    if (user.role == Role.admin)
                      TextButton(
                        onPressed: _locked ? null : () => _forgot(user),
                        child: Text(tr('Forgot PIN?')),
                      ),
                    if (widget.users.length > 1)
                      TextButton(
                        onPressed: () => setState(() {
                          _selected = null;
                          _error = null;
                          _pin.clear();
                        }),
                        child: Text(tr('Not you?')),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
