import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/share.dart';
import '../../core/terms.dart';
import '../../core/theme.dart';
import '../../core/whatsapp_pdf.dart';
import '../../data/business_profile.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../l10n/strings.dart';
import '../../subscription/entitlement.dart';
import '../common/widgets.dart';
import 'catalog_pdf.dart';
import 'item_photo_strip.dart';

/// Most items in one catalog (each picture adds to the size of the file).
const maxCatalogItems = 60;

/// Choose the items for a catalog, then send it as a PDF on WhatsApp (the
/// person chooses the chat there) or share it any other way.
class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key});

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  final _on = <int>{};
  bool _showRates = true;
  bool _building = false;
  bool _primed = false;

  Future<Uint8List> _pdf(List<RentItem> items, Map<int, String> covers) async {
    final shop = ref.read(profileProvider).valueOrNull!;
    final entries = <CatalogEntry>[];
    for (final i in items) {
      Uint8List? bytes;
      final path = covers[i.id];
      if (path != null) {
        try {
          bytes = await File(path).readAsBytes();
        } catch (_) {
          bytes = null; // the file is gone: a plain box is shown
        }
      }
      entries.add(CatalogEntry(i, bytes));
    }
    return buildCatalogPdf(
      shop: shop,
      entries: entries,
      showRates: _showRates,
      logo: ref.read(isProProvider) ? await shop.logoBytes() : null,
    );
  }

  Future<void> _go(
    List<RentItem> all,
    Map<int, String> covers, {
    required bool whatsApp,
  }) async {
    final chosen = [
      for (final i in all)
        if (_on.contains(i.id)) i,
    ];
    if (chosen.isEmpty || _building) return;
    setState(() => _building = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await _pdf(chosen, covers);
      final shop = ref.read(profileProvider).valueOrNull!;
      if (whatsApp) {
        await sendPdfOnWhatsApp(
          bytes: bytes,
          fileName: 'catalog.pdf',
          phone: '',
          message: tr('Our catalog - {shop}', {'shop': shop.name}),
        );
      } else {
        await sharePdf(bytes, 'catalog.pdf');
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(tr('Could not make the catalog: {e}', {'e': e}))),
      );
    } finally {
      if (mounted) setState(() => _building = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(itemsProvider).valueOrNull ?? const <RentItem>[];
    final covers = ref.watch(itemCoversProvider).valueOrNull ?? const {};
    final terms = ref.watch(termsProvider);
    final available = [
      for (final i in items)
        if (i.status.bookable) i,
    ];
    // start with every item that has a picture ticked
    if (!_primed && items.isNotEmpty) {
      _primed = true;
      for (final i in available.where((i) => covers.containsKey(i.id)).take(maxCatalogItems)) {
        _on.add(i.id!);
      }
    }
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Share a catalog'))),
      body: AuroraBackground(
        child: Column(
          children: [
            SwitchListTile(
              title: Text(tr('Show the rent and deposit')),
              value: _showRates,
              onChanged: (v) => setState(() => _showRates = v),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('{n} chosen', {'n': _on.length}),
                      style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _on
                        ..clear()
                        ..addAll(available.take(maxCatalogItems).map((i) => i.id!));
                    }),
                    child: Text(tr('Choose all')),
                  ),
                  TextButton(
                    onPressed: () => setState(_on.clear),
                    child: Text(tr('Clear')),
                  ),
                ],
              ),
            ),
            Expanded(
              child: available.isEmpty
                  ? EmptyState(
                      icon: Icons.checkroom_outlined,
                      message: terms.noItemsYet,
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 8),
                      children: [
                        for (final i in available)
                          CheckboxListTile(
                            value: _on.contains(i.id),
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                if (_on.length >= maxCatalogItems) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        tr('A catalog holds up to {n} items.', {
                                          'n': maxCatalogItems,
                                        }),
                                      ),
                                    ),
                                  );
                                } else {
                                  _on.add(i.id!);
                                }
                              } else {
                                _on.remove(i.id);
                              }
                            }),
                            secondary: covers[i.id] == null
                                ? null
                                : PhotoThumb(path: covers[i.id]!, size: 48),
                            title: Text(i.name),
                            subtitle: covers[i.id] == null
                                ? Text(tr('No picture yet'))
                                : null,
                          ),
                      ],
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _on.isEmpty || _building
                            ? null
                            : () => _go(available, covers, whatsApp: true),
                        icon: _building
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.chat_outlined),
                        label: Text(tr('Send on WhatsApp')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: _on.isEmpty || _building
                          ? null
                          : () => _go(available, covers, whatsApp: false),
                      icon: const Icon(Icons.ios_share_outlined),
                      label: Text(tr('Share')),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
