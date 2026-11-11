import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../subscription/account.dart';

String signInMessage(SignInResult r) => switch (r) {
  SignInResult.signedIn => tr('Signed in'),
  // Android also reports "that account needs signing in again" as cancelled
  SignInResult.cancelled => tr(
    'Sign-in was cancelled or did not finish. If you chose an account and nothing happened, sign in to that account again in the phone Settings, under Passwords & accounts > Google.',
  ),
  SignInResult.offline => tr(
    'Could not reach the server. Check your internet and try again.',
  ),
  SignInResult.failed => tr('Sign-in did not work. Please try again.'),
};

String deleteMessage(DeleteResult r) => switch (r) {
  DeleteResult.deleted => tr('Your account was deleted'),
  DeleteResult.cancelled => '',
  DeleteResult.offline => tr(
    'Could not reach the server. Check your internet and try again.',
  ),
  DeleteResult.failed => tr(
    'The account was not deleted. Choose the same Google account you signed in with and try again.',
  ),
};

/// Optional Google sign-in, with what it is for. Billing never needs it.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _busy = false;

  void _msg(String s) {
    if (s.isEmpty) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _signIn() async {
    setState(() => _busy = true);
    final r = await ref.read(accountProvider.notifier).signIn();
    if (!mounted) return;
    setState(() => _busy = false);
    _msg(signInMessage(r));
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Sign out?')),
        content: Text(
          tr(
            'Your bills and data stay on this phone. Your free trial stays as it is; Pro stays active while your subscription is.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Sign out')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    await ref.read(accountProvider.notifier).signOut();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Delete your account?')),
        content: Text(
          tr(
            'This erases your email, name and sign-in from our server. Your bills, customers and products stay on this phone. Your Pro subscription is not cancelled: manage it in Google Play. You will be asked to choose your Google account once more to confirm.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              tr('Delete account'),
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final r = await ref.read(accountProvider.notifier).deleteAccount();
    if (!mounted) return;
    setState(() => _busy = false);
    _msg(deleteMessage(r));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = ref.watch(accountProvider).valueOrNull;

    Widget bullet(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(tr('Account'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (account != null) ...[
            Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(
                  account.name.isEmpty ? account.email : account.name,
                ),
                subtitle: account.name.isEmpty ? null : Text(account.email),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              tr(
                'Signed in with Google. Your free trial is tied to this account, so reinstalling or changing phone does not restart it.',
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _busy ? null : _signOut,
              icon: const Icon(Icons.logout),
              label: Text(tr('Sign out')),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _busy ? null : _delete,
              icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
              label: Text(
                tr('Delete account'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ] else ...[
            Text(
              tr('Sign in with Google (optional)'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            bullet(
              tr(
                'Back up your data to your own Google Drive and restore it on a new phone',
              ),
            ),
            bullet(tr('Your free trial follows you if you change phone')),
            const SizedBox(height: 16),
            Text(
              tr(
                'Billing works without signing in. We keep only your email and name, never your bills, customers or products.',
              ),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _signIn,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: Text(tr('Sign in with Google')),
            ),
          ],
        ],
      ),
    );
  }
}

/// A short invitation on the Pro screen. Hidden once signed in.
class AccountPrompt extends ConsumerWidget {
  const AccountPrompt({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(accountProvider);
    if (state.valueOrNull != null || state.isLoading) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        leading: const Icon(Icons.account_circle_outlined),
        title: Text(tr('Sign in for backup and restore')),
        subtitle: Text(
          tr(
            'Back up to your Google Drive and restore on a new phone. Optional.',
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const AccountScreen())),
      ),
    );
  }
}
