import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants.dart';
import 'core/restart_widget.dart';
import 'core/theme.dart';
import 'data/app_settings.dart';
import 'data/business_profile.dart';
import 'features/home/home_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/splash/splash_screen.dart';
import 'l10n/strings.dart';
import 'subscription/clock_gate.dart';
import 'subscription/startup.dart';

void main() {
  runApp(
    const RestartWidget(child: ProviderScope(child: GellsoftRentProApp())),
  );
}

class GellsoftRentProApp extends ConsumerStatefulWidget {
  const GellsoftRentProApp({super.key});

  @override
  ConsumerState<GellsoftRentProApp> createState() => _GellsoftRentProAppState();
}

class _GellsoftRentProAppState extends ConsumerState<GellsoftRentProApp>
    with WidgetsBindingObserver {
  /// Keeps the splash up briefly even when the profile loads instantly.
  bool _minSplashDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _minSplashDone = true);
    });
    // the plan check runs in the background and never holds the app up
    startSubscriptionServices(ref).whenComplete(() => runAutoBackup(ref));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) runAutoBackup(ref);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    // Keep the text language in step before any screen builds.
    final language = AppLanguage.fromCode(settings?.language);
    Lang.current = language;
    return MaterialApp(
      title: AppInfo.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings?.themeMode ?? ThemeMode.system,
      locale: Locale(language.code),
      supportedLocales: [for (final l in AppLanguage.values) Locale(l.code)],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // the clock check sits above everything
      builder: (context, child) => ClockGate(child: child ?? const SizedBox()),
      home: !_minSplashDone
          ? const SplashScreen()
          : profile.when(
              loading: () => const SplashScreen(),
              error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
              data: (p) =>
                  p == null ? const OnboardingScreen() : HomeScreen(profile: p),
            ),
    );
  }
}
