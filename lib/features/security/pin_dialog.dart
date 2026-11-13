import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';

/// 4-6 digit PIN entry. With [confirm], asks twice. Pops the PIN or null.
class PinDialog extends StatefulWidget {
  const PinDialog({super.key, required this.title, this.confirm = false});
  final String title;
  final bool confirm;

  @override
  State<PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<PinDialog> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _ok() {
    final pin = _a.text.trim();
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      return setState(() => _error = tr('Use 4 to 6 digits'));
    }
    if (widget.confirm && _b.text.trim() != pin) {
      return setState(() => _error = tr('PINs do not match'));
    }
    Navigator.pop(context, pin);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _a,
            autofocus: true,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            maxLength: 6,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: tr('PIN'), counterText: ''),
            onSubmitted: (_) => widget.confirm ? null : _ok(),
          ),
          if (widget.confirm) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _b,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              maxLength: 6,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: tr('Confirm PIN'),
                counterText: '',
              ),
              onSubmitted: (_) => _ok(),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Cancel')),
        ),
        TextButton(onPressed: _ok, child: Text(tr('OK'))),
      ],
    );
  }
}

/// Asks for the 8-digit recovery code. Pops what was typed, or null.
class RecoveryCodeDialog extends StatefulWidget {
  const RecoveryCodeDialog({super.key});

  @override
  State<RecoveryCodeDialog> createState() => _RecoveryCodeDialogState();
}

class _RecoveryCodeDialogState extends State<RecoveryCodeDialog> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Recovery code')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tr(
              'Enter the 8-digit recovery code you saved when staff logins were turned on.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            maxLength: 9,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d ]')),
            ],
            decoration: InputDecoration(
              labelText: tr('Recovery code'),
              counterText: '',
            ),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _code.text),
          child: Text(tr('OK')),
        ),
      ],
    );
  }
}

/// Shows a new recovery code once. It cannot be dismissed by accident: the
/// code is not kept anywhere, so this is the only time it can be read.
Future<void> showRecoveryCode(
  BuildContext context,
  String code,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (ctx) => AlertDialog(
    title: Text(tr('Your recovery code')),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: SelectableText(
            code,
            style: Theme.of(ctx).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          tr(
            'Write this down and keep it safe. If the Admin forgets the PIN, this code is the only way back in. It will not be shown again.',
          ),
        ),
      ],
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(ctx),
        child: Text(tr('I have written it down')),
      ),
    ],
  ),
);
