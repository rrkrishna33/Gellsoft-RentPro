import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/device.dart';
import '../l10n/strings.dart';
import 'license_state.dart';
import 'license_sync.dart';
import 'trusted_clock.dart';

/// Keeps watching whether the phone's date and time can still be trusted, and
/// (on the same beat) renews the license when its Pro period has run out.
///
/// It re-checks every few seconds and whenever the app comes back to the
/// front, so a changed date is noticed straight away, with or without internet
/// (see [assessClock]).
class ClockGuard extends Notifier<ClockStatus> {
  static const every = Duration(seconds: 15);

  bool _busy = false;

  @override
  ClockStatus build() {
    final timer = Timer.periodic(every, (_) => check());
    ref.onDispose(timer.cancel);
    Future.microtask(check);
    return ClockStatus(
      problem: ClockProblem.none,
      now: DateTime.now(),
      verified: false,
    );
  }

  /// Looks at the clocks. With [allowSync], a phone that was restarted (so the
  /// check cannot be made offline) asks the server for the real time first.
  Future<void> check({bool allowSync = false}) async {
    if (_busy) return;
    _busy = true;
    try {
      final sync = ref.read(licenseSyncProvider);
      // While the app stays open, a Pro period can run out (or a subscription
      // renew): ask the server again, so the plan on screen is the real one.
      if (await sync.renewIfNeeded()) ref.invalidate(licenseProvider);
      var s = await sync.clockStatus();
      if (allowSync && s.problem == ClockProblem.unverifiable) {
        await sync.refresh();
        s = await sync.clockStatus();
      }
      state = s;
    } catch (_) {
      // never let a failed check break the app
    } finally {
      _busy = false;
    }
  }

  /// "Check again": ask the server for the real time, then look again.
  Future<void> checkAgainOnline() async {
    try {
      final r = await ref.read(licenseSyncProvider).refresh();
      if (r.result == SyncResult.updated) ref.invalidate(licenseProvider);
    } catch (_) {
      // offline: the check below still works from what the app remembers
    }
    _busy = false;
    await check();
  }
}

final clockGuardProvider = NotifierProvider<ClockGuard, ClockStatus>(
  ClockGuard.new,
);

/// Wraps the whole app: a thin clock at the top of every screen, and, once the
/// paywall is on, a screen that stops the app while the phone's time is wrong.
class ClockGate extends ConsumerStatefulWidget {
  const ClockGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<ClockGate> createState() => _ClockGateState();
}

class _ClockGateState extends ConsumerState<ClockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(clockGuardProvider.notifier).check();
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(clockGuardProvider);
    final enforced =
        ref.watch(licenseProvider).value?.entitlement.enforced ?? false;
    final blocked = enforced && !status.ok;

    return Column(
      children: [
        ClockBar(status: status),
        Expanded(
          // the clock already uses up the space under the status bar
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: Stack(
              children: [
                widget.child,
                if (blocked) const Positioned.fill(child: TimeAlignScreen()),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

final _barFormat = DateFormat('EEE, dd MMM yyyy · hh:mm a');

/// The thin strip at the top: the date and time the app trusts.
class ClockBar extends StatelessWidget {
  const ClockBar({super.key, required this.status});
  final ClockStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = !status.ok
        ? Icons.warning_amber_rounded
        : status.verified
        ? Icons.verified_outlined
        : Icons.schedule;
    final color = !status.ok
        ? scheme.error
        : status.verified
        ? scheme.tertiary
        : scheme.onSurfaceVariant;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: SafeArea(
        bottom: false,
        child: Semantics(
          label: status.verified
              ? tr('Time confirmed with the GellSoft server')
              : tr('Phone time, not yet confirmed with the server'),
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.0,
            child: SizedBox(
              height: 24,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 14, color: color),
                      const SizedBox(width: 6),
                      Text(
                        _barFormat.format(status.now),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown over the whole app while the phone's date and time is wrong: nothing
/// can be done until it is corrected, then everything is exactly as it was.
class TimeAlignScreen extends ConsumerStatefulWidget {
  const TimeAlignScreen({super.key});

  @override
  ConsumerState<TimeAlignScreen> createState() => _TimeAlignScreenState();
}

class _TimeAlignScreenState extends ConsumerState<TimeAlignScreen> {
  bool _checking = false;
  bool _triedAgain = false;

  Future<void> _again() async {
    setState(() => _checking = true);
    await ref.read(clockGuardProvider.notifier).checkAgainOnline();
    if (mounted) {
      setState(() {
        _checking = false;
        _triedAgain = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(clockGuardProvider);
    final theme = Theme.of(context);
    final fmt = DateFormat('dd MMM yyyy, hh:mm a');

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.access_time_filled,
                  size: 64,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  tr('The date and time on this phone is not correct'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  status.problem == ClockProblem.unverifiable
                      ? tr(
                          'The phone was restarted and Automatic date & time is off, so the app cannot confirm the time. Connect to the internet and tap Check again, or turn on Automatic date & time.',
                        )
                      : tr(
                          'GellSoft BillPro uses the real time to keep your plan and your bill count fair. Turn on Automatic date & time in your phone settings, then tap Check again.',
                        ),
                  textAlign: TextAlign.center,
                ),
                if (status.verified) ...[
                  const SizedBox(height: 16),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          _line(
                            tr('Correct time'),
                            fmt.format(status.now),
                            theme,
                          ),
                          const SizedBox(height: 6),
                          _line(
                            tr('Phone time'),
                            fmt.format(DateTime.now()),
                            theme,
                            color: theme.colorScheme.error,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () =>
                        ref.read(deviceInfoProvider).openDateSettings(),
                    icon: const Icon(Icons.settings),
                    label: Text(tr('Open date & time settings')),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _checking ? null : _again,
                    icon: _checking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(tr('Check again')),
                  ),
                ),
                if (_triedAgain && !_checking) ...[
                  const SizedBox(height: 12),
                  Text(
                    tr(
                      'The time is still not correct. Fix it in settings, then check again.',
                    ),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _line(String label, String value, ThemeData theme, {Color? color}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(color: color),
          ),
        ],
      );
}
