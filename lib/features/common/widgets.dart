import 'package:flutter/material.dart';

import '../../l10n/strings.dart';

/// Asks "are you sure?" before something is removed. True when confirmed.
Future<bool> confirmRemove(
  BuildContext context, {
  required String title,
  required String message,
  String? action,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            minimumSize: const Size(64, 44),
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action ?? tr('Remove')),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// The search box at the top of a list.
class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.hint, required this.onChanged});
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    onChanged: onChanged,
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: const Icon(Icons.search),
      isDense: true,
    ),
  );
}

/// Shown when a list has nothing in it.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 56,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    ),
  );
}

/// A small coloured label such as "In repair".
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// Turns what the user typed into a number. Empty or invalid gives 0.
double parseAmount(String s) =>
    double.tryParse(s.replaceAll(',', '').trim()) ?? 0;

/// A number without a trailing ".0", for filling a text box.
String amountText(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
