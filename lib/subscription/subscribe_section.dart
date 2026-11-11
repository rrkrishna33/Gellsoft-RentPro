import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/strings.dart';
import 'billing.dart';
import 'license_config.dart';

String billingNoteText(BillingNote n) => switch (n) {
  BillingNote.none => '',
  BillingNote.checking => tr('Checking your purchase…'),
  BillingNote.pending => tr(
    'Payment is pending. Pro starts as soon as it is confirmed.',
  ),
  BillingNote.activated => tr('Thank you! Pro is now active.'),
  BillingNote.notActivated => tr(
    'This purchase could not be activated on this phone. If you were charged, contact support and give your install ID.',
  ),
  BillingNote.offline => tr(
    'Your purchase is saved. Pro will start the next time the app can reach the internet.',
  ),
  BillingNote.cancelled => tr('Purchase cancelled'),
  BillingNote.failed => tr('Something went wrong. Please try again.'),
  BillingNote.restoredNothing => tr(
    'No earlier purchase was found for this Google account.',
  ),
};

String planTitle(PlanOption p) => switch (p.period) {
  'monthly' => tr('Monthly'),
  'yearly' => tr('Yearly'),
  _ => tr('Pro plan'),
};

String planPrice(PlanOption p) => switch (p.period) {
  'monthly' => tr('{price} / month', {'price': p.price}),
  'yearly' => tr('{price} / year', {'price': p.price}),
  _ => p.price,
};

Uri manageSubscriptionUrl() => Uri.parse(
  'https://play.google.com/store/account/subscriptions'
  '?sku=$proProductId&package=$licenseAudience',
);

/// The buying part of the Pro screen: plans from Google Play, Subscribe,
/// Restore purchases, and the result of the last purchase.
class SubscribeSection extends ConsumerStatefulWidget {
  const SubscribeSection({super.key, required this.isPro});
  final bool isPro;

  @override
  ConsumerState<SubscribeSection> createState() => _SubscribeSectionState();
}

class _SubscribeSectionState extends ConsumerState<SubscribeSection> {
  @override
  void initState() {
    super.initState();
    if (!widget.isPro) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(billingProvider.notifier).loadPlans();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = ref.watch(billingProvider);
    final ctl = ref.read(billingProvider.notifier);
    final note = billingNoteText(s.note);

    final children = <Widget>[];

    if (widget.isPro) {
      children.add(
        OutlinedButton.icon(
          icon: const Icon(Icons.open_in_new),
          label: Text(tr('Manage subscription')),
          onPressed: () => launchUrl(
            manageSubscriptionUrl(),
            mode: LaunchMode.externalApplication,
          ),
        ),
      );
    } else if (s.loading && s.plans == null) {
      children.add(
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    } else if (s.plans == null || s.plans!.isEmpty) {
      children.add(
        Text(
          tr(
            'Plans are not available on this device. Install the app from Google Play to subscribe.',
          ),
          style: theme.textTheme.bodyMedium,
        ),
      );
    } else {
      for (final p in s.plans!) {
        children.add(
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(planTitle(p), style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(planPrice(p), style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: s.busy ? null : () => ctl.buy(p),
                      child: Text(tr('Subscribe')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    if (note.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (s.busy)
                const Padding(
                  padding: EdgeInsets.only(right: 12, top: 2),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              Expanded(child: Text(note)),
            ],
          ),
        ),
      );
    }

    if (!widget.isPro) {
      children.add(
        TextButton(
          onPressed: s.busy ? null : ctl.restore,
          child: Text(tr('Restore purchases')),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
