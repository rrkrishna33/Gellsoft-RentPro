import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/share.dart';
import '../../core/whatsapp_pdf.dart';
import '../../core/theme.dart';
import '../../data/booking_repo.dart';
import '../../data/business_profile.dart';
import '../../data/invoice_models.dart';
import '../../data/invoice_repo.dart';
import '../../data/staff.dart';
import '../../l10n/strings.dart';
import '../bookings/booking_detail_screen.dart';
import '../bookings/messages.dart';
import '../common/widgets.dart';
import 'invoice_pdf.dart';

/// One invoice: the figures, and buttons to share it as a PDF, print it, send
/// it on WhatsApp, or cancel it.
class InvoiceDetailScreen extends ConsumerWidget {
  const InvoiceDetailScreen({super.key, required this.invoiceId});
  final int invoiceId;

  Future<Uint8List> _bytes(WidgetRef ref, Invoice inv) async {
    final shop = ref.read(profileProvider).valueOrNull!;
    final booking = await ref.read(bookingRepoProvider).get(inv.bookingId);
    return buildInvoicePdf(
      shop: shop,
      invoice: inv,
      payments: booking?.payments ?? const [],
      depositTotal: booking?.depositTotal ?? 0,
      depositHeld: booking?.depositHeld ?? 0,
      eventTime: booking?.eventTime ?? '',
    );
  }

  Future<void> _pdf(
    BuildContext context,
    WidgetRef ref,
    Invoice inv, {
    required bool print,
  }) async {
    if (ref.read(profileProvider).valueOrNull == null) return;
    final bytes = await _bytes(ref, inv);
    if (print) {
      await printPdf(bytes, inv.label);
    } else {
      await sharePdf(bytes, '${inv.label}.pdf');
    }
  }

  /// WhatsApp opens with the invoice PDF attached and the message written;
  /// without WhatsApp the share sheet opens with the same PDF.
  Future<void> _whatsApp(BuildContext context, WidgetRef ref, Invoice inv) async {
    final shop = ref.read(profileProvider).valueOrNull;
    if (shop == null) return;
    final bytes = await _bytes(ref, inv);
    await sendPdfOnWhatsApp(
      bytes: bytes,
      fileName: '${inv.label}.pdf',
      phone: inv.customerPhone,
      message: invoiceMessage(inv, shop),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(invoiceProvider(invoiceId));
    final shop = ref.watch(profileProvider).valueOrNull;
    final text = Theme.of(context).textTheme;
    final style = AuroraStyle.of(context);

    return async.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(tr('Error: {e}', {'e': e}))),
      ),
      data: (inv) {
        if (inv == null) {
          return Scaffold(
            appBar: AppBar(),
            body: EmptyState(
              icon: Icons.receipt_long_outlined,
              message: tr('This invoice was not found.'),
            ),
          );
        }
        Widget row(String k, String v, {bool bold = false, Color? color}) =>
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      k,
                      style: text.bodyLarge?.copyWith(
                        fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                        color: color,
                      ),
                    ),
                  ),
                  Text(
                    v,
                    style: text.bodyLarge?.copyWith(
                      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                      color: color,
                    ),
                  ),
                ],
              ),
            );

        return Scaffold(
          appBar: AppBar(
            title: Text(inv.label),
            actions: [
              if (!inv.cancelled &&
                  ref.watch(permsProvider).can(Permission.cancelBookings))
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v != 'cancel') return;
                    final ok = await confirmRemove(
                      context,
                      title: tr('Cancel this invoice?'),
                      message: tr(
                        'It stays in the list marked cancelled and its number is not used again. You can make a new invoice for the booking.',
                      ),
                      action: tr('Cancel invoice'),
                    );
                    if (!ok) return;
                    await ref.read(invoiceRepoProvider).cancel(inv.id);
                    ref.invalidate(invoiceProvider(inv.id));
                    ref.invalidate(invoicesProvider);
                    ref.invalidate(bookingInvoiceProvider(inv.bookingId));
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'cancel',
                      child: Text(tr('Cancel invoice')),
                    ),
                  ],
                ),
            ],
          ),
          body: AuroraBackground(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: style.hero,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: style.heroShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              inv.isTaxInvoice
                                  ? tr('Tax invoice')
                                  : tr('Rental bill'),
                              style: text.labelLarge?.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                          ),
                          if (inv.cancelled)
                            StatusChip(
                              label: tr('Cancelled'),
                              color: const Color(0xFFFFB4AB),
                            ),
                        ],
                      ),
                      Text(
                        money(inv.total),
                        style: text.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${inv.customerName}  ·  ${dateText(inv.date)}',
                        style: text.bodyMedium?.copyWith(color: Colors.white),
                      ),
                      Text(
                        '${tr('Booking')} #${inv.bookingNumber}',
                        style: text.bodySmall?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Column(
                    children: [
                      for (final l in inv.lines)
                        ListTile(
                          title: Text(l.name),
                          subtitle: Text(
                            [
                              if (l.days > 1) '${l.days} ${tr('days')}',
                              if (inv.gstEnabled)
                                'GST ${amountText(l.gstRate)}%'
                                    '${l.hsn.isEmpty ? '' : '  ·  ${l.hsn}'}',
                            ].join('  ·  '),
                          ),
                          trailing: Text(
                            money(l.total),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        if (inv.discount > 0)
                          row(tr('Discount'), '- ${money(inv.discount)}'),
                        if (inv.gstEnabled) ...[
                          row(tr('Taxable value'), money(inv.taxable)),
                          if (inv.interState)
                            row('IGST', money(inv.igst))
                          else ...[
                            row('CGST', money(inv.cgst)),
                            row('SGST', money(inv.sgst)),
                          ],
                        ],
                        const Divider(height: 20),
                        row(tr('Total'), money(inv.total), bold: true),
                        row(tr('Paid'), money(inv.paid)),
                        row(
                          tr('Balance due'),
                          money(inv.due),
                          bold: true,
                          color: inv.due > 0 ? Palette.danger : Palette.success,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => _pdf(context, ref, inv, print: false),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(tr('Share PDF')),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pdf(context, ref, inv, print: true),
                        icon: const Icon(Icons.print_outlined),
                        label: Text(tr('Print')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: shop == null
                            ? null
                            : () => _whatsApp(context, ref, inv),
                        icon: const Icon(Icons.chat_outlined),
                        label: const Text('WhatsApp'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          BookingDetailScreen(bookingId: inv.bookingId),
                    ),
                  ),
                  icon: const Icon(Icons.event_note_outlined),
                  label: Text(tr('Open the booking')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
