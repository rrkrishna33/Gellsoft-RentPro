import 'package:flutter/material.dart';

import '../../core/constants.dart';

/// Startup page: logo, app name and a small progress indicator.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(36),
              child: Image.asset(
                'assets/icon/app_icon.png',
                width: 140,
                height: 140,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              AppInfo.appName,
              style: text.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1C2C54),
              ),
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}
