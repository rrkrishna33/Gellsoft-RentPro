import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'license_state.dart';
import 'plan.dart';
import 'pro_prompt.dart';

/// Returns true when [feature] is available. Otherwise explains what Pro adds
/// (with a way to buy it) and returns false.
Future<bool> requirePro(
  BuildContext context,
  WidgetRef ref,
  ProFeature feature,
) async {
  final license = await ref.read(licenseProvider.future);
  if (license.entitlement.allows(feature)) return true;
  if (!context.mounted) return false;
  await showProPrompt(context, feature);
  return false;
}
