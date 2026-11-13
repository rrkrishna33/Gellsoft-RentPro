import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/privacy.dart';
import '../../data/staff.dart';
import 'staff_login_screen.dart';

/// Covers the app with the "Who is using the app?" sign-in screen while staff
/// logins are on and nobody is signed in. With staff logins off it does
/// nothing at all. It also asks again after the app has been in the
/// background for [_relockAfter].
class LockGate extends ConsumerStatefulWidget {
  const LockGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate>
    with WidgetsBindingObserver {
  static const _relockAfter = Duration(seconds: 30);
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // no recent-apps preview while staff logins are on
    ref.listenManual(staffUsersProvider, (_, next) {
      final people = next.valueOrNull;
      if (people != null) Privacy.hideRecentsPreview(people.isNotEmpty);
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed && _pausedAt != null) {
      if (DateTime.now().difference(_pausedAt!) > _relockAfter) {
        // away for a while: whoever comes back signs in afresh
        ref.read(sessionProvider.notifier).logout();
      }
      _pausedAt = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final staff = ref.watch(staffUsersProvider);
    // nothing is shown until the list is known, so the app never flashes open
    if (staff.isLoading && !staff.hasValue) {
      return const ColoredBox(color: Colors.white);
    }
    final all = staff.valueOrNull ?? const <StaffUser>[];
    final signedIn = ref.watch(sessionProvider);
    Widget? cover;
    if (all.isNotEmpty && signedIn == null) {
      final people = [
        for (final u in all)
          if (u.active) u,
      ];
      // The gate sits above the app's own navigator, and the sign-in screen
      // opens dialogs (Forgot PIN, the recovery code), which need one: so it
      // gets a navigator of its own.
      cover = HeroControllerScope.none(
        child: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => StaffLoginScreen(
              users: people,
              onLoggedIn: (u) => ref.read(sessionProvider.notifier).login(u),
            ),
          ),
        ),
      );
    }
    return Stack(
      children: [
        widget.child,
        if (cover != null) Positioned.fill(child: cover),
      ],
    );
  }
}
