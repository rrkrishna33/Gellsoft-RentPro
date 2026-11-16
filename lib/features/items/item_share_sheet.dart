import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/whatsapp_pdf.dart';
import '../../data/business_profile.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../l10n/strings.dart';
import '../bookings/messages.dart';

/// Asks who to send an item to, then opens WhatsApp with its pictures and a
/// short text (name, size, rent, deposit). The person can pick a customer, so
/// WhatsApp opens on their chat, or choose the chat inside WhatsApp.
Future<void> showItemShareSheet(BuildContext context, RentItem item) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _ShareSheet(item: item),
    );

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({required this.item});
  final RentItem item;

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  String _q = '';
  bool _sending = false;

  Future<void> _send(String phone) async {
    final shop = ref.read(profileProvider).valueOrNull;
    if (shop == null || _sending) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      final photos = await ref.read(itemRepoProvider).photosOf(widget.item.id!);
      await sendImagesOnWhatsApp(
        paths: [for (final p in photos) p.path],
        phone: phone,
        message: itemShareMessage(widget.item, shop),
      );
      nav.pop();
    } catch (_) {
      if (mounted) setState(() => _sending = false);
      messenger.showSnackBar(
        SnackBar(content: Text(tr('Could not open WhatsApp.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customersProvider).valueOrNull ?? const [];
    final q = _q.trim().toLowerCase();
    final shown = [
      for (final c in customers)
        if (q.isEmpty ||
            c.name.toLowerCase().contains(q) ||
            c.phone.contains(q))
          c,
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    tr('Send {name} on WhatsApp', {'name': widget.item.name}),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.chat_outlined),
                title: Text(tr('Choose the chat in WhatsApp')),
                enabled: !_sending,
                onTap: () => _send(''),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: tr('Or search a customer'),
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ),
              const SizedBox(height: 4),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in shown)
                      ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(c.name),
                        subtitle: c.phone.isEmpty
                            ? Text(tr('No phone number'))
                            : Text(c.phone),
                        enabled: !_sending && c.phone.trim().isNotEmpty,
                        onTap: () => _send(c.phone),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
