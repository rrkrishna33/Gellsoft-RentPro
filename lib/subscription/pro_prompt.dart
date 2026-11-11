import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import 'plan.dart';
import 'pro_ui.dart';

/// Tells the user that something needs Pro and what Pro adds, with a button
/// to the Pro screen where it can be bought.
Future<void> showProPrompt(BuildContext context, ProFeature feature) async {
  final seePro = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(
        Icons.workspace_premium,
        color: Theme.of(ctx).colorScheme.secondary,
      ),
      title: Text(tr('This needs Pro')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_why(feature)),
          const SizedBox(height: 12),
          for (final f in ProFeature.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(f.label)),
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(tr('Not now')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tr('See Pro')),
        ),
      ],
    ),
  );
  if (seePro == true && context.mounted) {
    await showUpgradeScreen(context, feature: feature);
  }
}

String _why(ProFeature f) => switch (f) {
  ProFeature.unlimitedBookings => tr(
    'The free plan allows {n} new bookings a month. You have used them all.',
    {'n': FreePlan.bookingsPerMonth},
  ),
  ProFeature.unlimitedPhotos => tr(
    'The free plan keeps {n} photos on a booking.',
    {'n': FreePlan.photosPerBooking},
  ),
  ProFeature.notifications => tr('Reminder notifications are part of Pro.'),
};
