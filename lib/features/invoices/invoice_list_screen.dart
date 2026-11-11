import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/invoice_models.dart';
import '../../data/invoice_repo.dart';
import '../../l10n/strings.dart';
import '../common/widgets.dart';
import 'invoice_detail_screen.dart';

/// Every invoice, newest first, with a search box.
class InvoiceListScreen extends ConsumerWidget {
  const InvoiceListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(invoicesProvider);
    final searching = ref.watch(invoiceSearchProvider).trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Invoices'))),
      body: AuroraBackground(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SearchField(
                hint: tr('Search by name, phone or number'),
                onChanged: (v) =>
                    ref.read(invoiceSearchProvider.notifier).state = v,
              ),
            ),
            Expanded(
              child: list.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Center(child: Text(tr('Error: {e}', {'e': e}))),
                data: (items) {
                  if (items.isEmpty) {
                    return EmptyState(
                      icon: Icons.receipt_long_outlined,
                      message: searching
                          ? tr('No invoice matches your search.')
                          : tr(
                              'Invoices you make from a booking will appear here.',
                            ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _InvoiceTile(
                      invoice: items[i],
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                InvoiceDetailScreen(invoiceId: items[i].id),
                          ),
                        );
                        ref.invalidate(invoicesProvider);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({required this.invoice, required this.onTap});
  final Invoice invoice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final i = invoice;
    final text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AuroraStyle.of(context).softShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${i.label}  ${i.customerName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${dateText(i.date)}  ·  ${i.isTaxInvoice ? tr('Tax invoice') : tr('Rental bill')}',
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      money(i.total),
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (i.cancelled)
                      StatusChip(
                        label: tr('Cancelled'),
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      )
                    else if (i.due > 0)
                      Text(
                        tr('Due {amount}', {'amount': money(i.due)}),
                        style: text.labelSmall?.copyWith(
                          color: Palette.danger,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    else
                      StatusChip(label: tr('Paid'), color: Palette.success),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
