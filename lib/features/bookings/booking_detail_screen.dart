import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/share.dart';
import '../../core/whatsapp_pdf.dart';
import '../../core/terms.dart';
import '../../core/theme.dart';
import '../../data/booking_models.dart';
import '../../data/booking_repo.dart';
import '../../data/business_profile.dart';
import '../../data/invoice_repo.dart';
import '../../data/reminders.dart';
import '../../data/staff.dart';
import '../../l10n/strings.dart';
import '../../subscription/entitlement.dart';
import '../../subscription/gates.dart';
import '../../subscription/plan.dart';
import '../common/widgets.dart';
import '../invoices/invoice_detail_screen.dart';
import '../invoices/invoice_pdf.dart';
import 'booking_errors.dart';
import 'booking_form_screen.dart';
import 'booking_photos.dart';
import 'messages.dart';

/// One booking: who, when, what, the money, and the buttons that move it on.
class BookingDetailScreen extends ConsumerWidget {
  const BookingDetailScreen({super.key, required this.bookingId});
  final int bookingId;

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on BookingException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(bookingErrorText(e))));
      }
    }
    ref.invalidate(bookingProvider(bookingId));
    ref.invalidate(bookingsProvider);
    // a charge changes the invoice of the booking too
    ref.invalidate(bookingInvoiceProvider(bookingId));
    ref.invalidate(invoicesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(bookingProvider(bookingId));
    final repo = ref.read(bookingRepoProvider);
    final shop = ref.watch(profileProvider).valueOrNull;
    final invoice = ref.watch(bookingInvoiceProvider(bookingId)).valueOrNull;
    final perms = ref.watch(permsProvider);
    final service = shop?.type.isService ?? false;
    final terms = ref.watch(termsProvider);

    return async.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(tr('Error: {e}', {'e': e}))),
      ),
      data: (b) {
        if (b == null) {
          return Scaffold(
            appBar: AppBar(),
            body: EmptyState(
              icon: Icons.event_busy_outlined,
              message: tr('This booking was not found.'),
            ),
          );
        }
        final active = b.status.holdsItems;

        Future<void> whatsApp(String message) async {
          final ok = await sendWhatsApp(b.customerPhone, message);
          if (!ok && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  tr('Could not open WhatsApp. Check the customer phone number.'),
                ),
              ),
            );
          }
        }

        Future<void> makeInvoice() async {
          if (shop == null) return;
          await _run(context, ref, () async {
            final id = await ref
                .read(invoiceRepoProvider)
                .createForBooking(
                  b.id,
                  shopStateCode: shop.stateCode,
                  prefix: shop.invoicePrefix,
                  gstEnabled: shop.gstEnabled,
                  taxInclusive: shop.taxInclusive,
                );
            ref.invalidate(bookingInvoiceProvider(b.id));
            ref.invalidate(invoicesProvider);
            if (context.mounted) {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => InvoiceDetailScreen(invoiceId: id),
                ),
              );
              ref.invalidate(bookingProvider(b.id));
            }
          });
        }

        Future<void> receipt(Payment p, {required bool send}) async {
          if (shop == null) return;
          final bytes = await buildReceiptPdf(
            shop: shop,
            booking: b,
            payment: p,
            showLogo: ref.read(isProProvider),
          );
          if (send) {
            await sendPdfOnWhatsApp(
              bytes: bytes,
              fileName: 'receipt-${p.id}.pdf',
              phone: b.customerPhone,
              message: receiptMessage(p, b, shop),
            );
          } else {
            await sharePdf(bytes, 'receipt-${p.id}.pdf');
          }
        }

        ReminderKind? remindKind() => switch (b.status) {
          BookingStatus.booked => ReminderKind.sendItems,
          BookingStatus.pickedUp || BookingStatus.dispatched =>
            b.isOverdue(dayOf(DateTime.now()))
                ? ReminderKind.overdue
                : ReminderKind.returnDue,
          _ => null,
        };

        Future<void> take(PaymentKind kind) async {
          final p = await showDialog<_PaymentInput>(
            context: context,
            builder: (_) => _PaymentDialog(booking: b, kind: kind),
          );
          if (p == null) return;
          if (!context.mounted) return;
          await _run(
            context,
            ref,
            () => repo.addPayment(
              b.id,
              kind: p.kind,
              amount: p.amount,
              mode: p.mode,
              note: p.note,
            ),
          );
        }

        Future<void> pickUp() => _run(context, ref, () => repo.markPickedUp(b.id));
        Future<void> done() => _run(context, ref, () => repo.markDone(b.id));

        Future<void> dispatch() async {
          final c = await showDialog<_CourierInput>(
            context: context,
            builder: (_) => const _CourierDialog(dispatching: true),
          );
          if (c == null || !context.mounted) return;
          await _run(
            context,
            ref,
            () => repo.markDispatched(
              b.id,
              courierName: c.name,
              courierNo: c.number,
            ),
          );
        }

        Future<void> editCourier() async {
          final c = await showDialog<_CourierInput>(
            context: context,
            builder: (_) => _CourierDialog(
              dispatching: false,
              name: b.courierName,
              number: b.courierNo,
            ),
          );
          if (c == null || !context.mounted) return;
          await _run(
            context,
            ref,
            () => repo.updateCourier(
              b.id,
              courierName: c.name,
              courierNo: c.number,
            ),
          );
        }

        Future<void> addCharge({
          ChargeKind kind = ChargeKind.damage,
          String note = '',
        }) async {
          if (!await requirePro(context, ref, ProFeature.charges)) return;
          if (!context.mounted) return;
          final c = await showDialog<_ChargeInput>(
            context: context,
            builder: (_) => _ChargeDialog(kind: kind, note: note),
          );
          if (c == null || !context.mounted) return;
          await _run(
            context,
            ref,
            () => repo.addCharge(
              b.id,
              kind: c.kind,
              amount: c.amount,
              note: c.note,
            ),
          );
        }

        Future<void> removeCharge(BookingCharge c) async {
          final paidBack = b.rentPaid - (b.payable - c.amount);
          final ok = await confirmRemove(
            context,
            title: tr('Remove this charge?'),
            message: paidBack > 0.005
                ? tr(
                    'The customer has already paid this. It is taken off, and a refund of {amount} is noted in the payments. Please give that money back to them.',
                    {'amount': money(paidBack)},
                  )
                : tr(
                    'It is taken off what the customer owes. Use this if it was added by mistake or you decide not to charge it.',
                  ),
            action: tr('Remove'),
          );
          if (ok && context.mounted) {
            await _run(context, ref, () => repo.removeCharge(c.id));
          }
        }

        Future<void> back() async {
          // late: offer a late fee before the items are booked in
          final today = dayOf(DateTime.now());
          if (b.isOverdue(today) && ref.read(isProProvider)) {
            final days = today.difference(b.returnDate).inDays;
            final fee = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: Text(tr('Returned late')),
                content: Text(
                  tr(
                    'These items are {n} days late. Add a late fee for them?',
                    {'n': days},
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(tr('No late fee')),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(tr('Add late fee')),
                  ),
                ],
              ),
            );
            if (fee == null || !context.mounted) return;
            if (fee) {
              await addCharge(
                kind: ChargeKind.late,
                note: tr('{n} days late', {'n': days}),
              );
              if (!context.mounted) return;
            }
          }
          // the deposit is handed back as the items come in
          if (b.depositHeld > 0) {
            final p = await showDialog<_PaymentInput>(
              context: context,
              builder: (_) =>
                  _PaymentDialog(booking: b, kind: PaymentKind.refund),
            );
            if (p == null || !context.mounted) return;
            await _run(context, ref, () async {
              if (p.amount > 0) {
                await repo.addPayment(
                  b.id,
                  kind: PaymentKind.refund,
                  amount: p.amount,
                  mode: p.mode,
                  note: p.note,
                );
              }
              await repo.markReturned(b.id);
            });
          } else {
            await _run(context, ref, () => repo.markReturned(b.id));
          }
        }

        Future<void> cancel() async {
          final ok = await confirmRemove(
            context,
            title: tr('Cancel this booking?'),
            message: tr(
              'The items become free for these days. Money already taken stays in the list so you can refund it.',
            ),
            action: tr('Cancel booking'),
          );
          if (ok && context.mounted) {
            await _run(context, ref, () => repo.cancel(b.id));
          }
        }

        Future<void> edit() async {
          await Navigator.of(context).push(
            MaterialPageRoute<int>(
              builder: (_) => BookingFormScreen(booking: b),
            ),
          );
          ref.invalidate(bookingProvider(bookingId));
          ref.invalidate(bookingsProvider);
        }

        return Scaffold(
          appBar: AppBar(
            title: Text('#${b.number}'),
            actions: [
              if (active &&
                  (perms.can(Permission.book) ||
                      perms.can(Permission.cancelBookings)))
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') edit();
                    if (v == 'cancel') cancel();
                  },
                  itemBuilder: (_) => [
                    if (perms.can(Permission.book))
                      PopupMenuItem(value: 'edit', child: Text(tr('Edit'))),
                    if (b.status == BookingStatus.booked &&
                        perms.can(Permission.cancelBookings))
                      PopupMenuItem(
                        value: 'cancel',
                        child: Text(tr('Cancel booking')),
                      ),
                  ],
                ),
            ],
          ),
          body: AuroraBackground(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _Header(booking: b, service: service),
                const SizedBox(height: 16),
                _Card(
                  title: terms.items,
                  children: [
                    for (final l in b.lines)
                      ListTile(
                        title: Text(l.label),
                        subtitle: Text(
                          l.qty > 1
                              ? '${l.rateType.label} · ${money(l.rate)} × ${l.qty}'
                              : '${l.rateType.label} · ${money(l.rate)}',
                        ),
                        trailing: Text(
                          money(l.amount),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
                if (b.status == BookingStatus.dispatched ||
                    b.courierName.isNotEmpty ||
                    b.courierNo.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _Card(
                    title: tr('Courier'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: [
                            if (b.dispatchedAt != null)
                              _row(context, tr('Sent on'), dateText(b.dispatchedAt!)),
                            _row(
                              context,
                              tr('Courier'),
                              b.courierName.isEmpty ? '-' : b.courierName,
                            ),
                            _row(
                              context,
                              tr('Tracking number'),
                              b.courierNo.isEmpty ? '-' : b.courierNo,
                            ),
                          ],
                        ),
                      ),
                      if (perms.can(Permission.book) &&
                          (b.status == BookingStatus.dispatched ||
                              b.status == BookingStatus.returned))
                        _action(
                          Icons.edit_outlined,
                          tr('Change courier details'),
                          editCourier,
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                PhotosSection(booking: b),
                const SizedBox(height: 16),
                _Card(
                  title: tr('Money'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          _row(context, tr('Rent'), money(b.rentTotal)),
                          if (b.discount > 0)
                            _row(
                              context,
                              tr('Discount'),
                              '- ${money(b.discount)}',
                            ),
                          if (b.taxTotal > 0)
                            _row(context, tr('GST'), money(b.taxTotal)),
                          for (final c in b.charges)
                            _row(
                              context,
                              chargeLineName(c.kind, c.note),
                              money(c.amount),
                            ),
                          _row(context, tr('Total'), money(b.payable), bold: true),
                          _row(context, tr('Paid'), money(b.rentPaid)),
                          const Divider(height: 20),
                          _row(
                            context,
                            tr('Balance to collect'),
                            money(b.balanceDue),
                            bold: true,
                            color: b.balanceDue > 0 ? Palette.danger : Palette.success,
                          ),
                          if (b.depositTotal > 0) ...[
                            const SizedBox(height: 10),
                            _row(context, tr('Deposit to hold'), money(b.depositTotal)),
                            _row(context, tr('Deposit taken'), money(b.depositTaken)),
                            if (b.depositRefunded > 0)
                              _row(context, tr('Deposit given back'), money(b.depositRefunded)),
                            _row(context, tr('Deposit held now'), money(b.depositHeld), bold: true),
                          ],
                        ],
                      ),
                    ),
                    if (perms.can(Permission.collectPayments) &&
                        b.status != BookingStatus.cancelled &&
                        b.balanceDue > 0)
                      _action(
                        Icons.payments_outlined,
                        tr('Take payment'),
                        () => take(
                          b.rentPaid > 0
                              ? PaymentKind.balance
                              : PaymentKind.advance,
                        ),
                      ),
                    if (perms.can(Permission.collectPayments) &&
                        active &&
                        b.depositDue > 0)
                      _action(
                        Icons.lock_outline,
                        tr('Take deposit'),
                        () => take(PaymentKind.deposit),
                      ),
                    if (perms.can(Permission.collectPayments) &&
                        b.depositHeld > 0 &&
                        !active)
                      _action(
                        Icons.undo,
                        tr('Give deposit back'),
                        () => take(PaymentKind.refund),
                      ),
                    if (perms.can(Permission.collectPayments) &&
                        !service &&
                        (b.status.isOut || b.status == BookingStatus.returned))
                      _action(
                        Icons.add_card_outlined,
                        tr('Add late fee or damage charge'),
                        addCharge,
                      ),
                    if (perms.can(Permission.collectPayments))
                      for (final c in b.charges)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.remove_circle_outline),
                          title: Text(
                            tr('Remove {what}', {
                              'what': chargeLineName(c.kind, c.note),
                            }),
                          ),
                          trailing: Text(money(c.amount)),
                          onTap: () => removeCharge(c),
                        ),
                  ],
                ),
                if (b.status != BookingStatus.cancelled) ...[
                  const SizedBox(height: 16),
                  _Card(
                    title: tr('Invoice'),
                    children: [
                      if (invoice != null)
                        ListTile(
                          leading: const Icon(Icons.receipt_long_outlined),
                          title: Text(invoice.label),
                          subtitle: Text(
                            '${invoice.isTaxInvoice ? tr('Tax invoice') : tr('Rental bill')} · ${money(invoice.total)}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  InvoiceDetailScreen(invoiceId: invoice.id),
                            ),
                          ),
                        )
                      else if (perms.can(Permission.book))
                        _action(
                          Icons.receipt_long_outlined,
                          shop?.gstEnabled ?? false
                              ? tr('Create tax invoice')
                              : tr('Create bill'),
                          makeInvoice,
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                _Card(
                  title: tr('Message the customer'),
                  children: [
                    _action(
                      Icons.chat_outlined,
                      tr('Send booking details on WhatsApp'),
                      () => shop == null
                          ? null
                          : whatsApp(confirmationMessage(b, shop)),
                    ),
                    if (b.status == BookingStatus.dispatched && shop != null)
                      _action(
                        Icons.local_shipping_outlined,
                        tr('Send courier details on WhatsApp'),
                        () => whatsApp(dispatchMessage(b, shop)),
                      ),
                    if (remindKind() != null && shop != null)
                      _action(
                        Icons.notifications_active_outlined,
                        switch (remindKind()!) {
                          ReminderKind.sendItems =>
                            service
                                ? tr('Remind about the appointment')
                                : tr('Remind to collect the items'),
                          ReminderKind.overdue => tr('Remind: items are overdue'),
                          _ => tr('Remind to return the items'),
                        },
                        () => whatsApp(reminderMessage(remindKind()!, b, shop)),
                      ),
                    if (b.balanceDue > 0 &&
                        b.status != BookingStatus.cancelled &&
                        shop != null)
                      _action(
                        Icons.payments_outlined,
                        tr('Remind about the balance'),
                        () => whatsApp(
                          reminderMessage(ReminderKind.balance, b, shop),
                        ),
                      ),
                    if (b.customerPhone.isNotEmpty)
                      _action(
                        Icons.call_outlined,
                        tr('Call {name}', {'name': b.customerName}),
                        () => callPhone(b.customerPhone),
                      ),
                  ],
                ),
                if (b.payments.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _Card(
                    title: tr('Payments'),
                    children: [
                      for (final p in b.payments)
                        ListTile(
                          dense: true,
                          title: Text(
                            '${p.kind.label} · ${p.mode.label}',
                          ),
                          subtitle: Text(
                            [
                              dateText(p.paidAt),
                              if (p.note.isNotEmpty) p.note,
                            ].join(' · '),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                (p.kind == PaymentKind.refund ? '- ' : '') +
                                    money(p.amount),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (p.amount > 0)
                              PopupMenuButton<String>(
                                tooltip: tr('Receipt'),
                                icon: const Icon(Icons.receipt_outlined),
                                onSelected: (v) =>
                                    receipt(p, send: v == 'whatsapp'),
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'pdf',
                                    child: Text(tr('Share receipt PDF')),
                                  ),
                                  PopupMenuItem(
                                    value: 'whatsapp',
                                    child: Text(tr('Send receipt on WhatsApp')),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
                if (b.notes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _Card(
                    title: tr('Notes'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(b.notes),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                if (b.status == BookingStatus.booked &&
                    perms.can(Permission.book))
                  service
                      ? FilledButton.icon(
                          onPressed: done,
                          icon: const Icon(Icons.check_circle_outline),
                          label: Text(tr('Mark as done')),
                        )
                      : FilledButton.icon(
                          onPressed: pickUp,
                          icon: const Icon(Icons.outbox_outlined),
                          label: Text(tr('Mark as picked up')),
                        ),
                if (b.status == BookingStatus.booked &&
                    !service &&
                    perms.can(Permission.book)) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: dispatch,
                    icon: const Icon(Icons.local_shipping_outlined),
                    label: Text(tr('Dispatch by courier')),
                  ),
                ],
                if (b.status.isOut && perms.can(Permission.book))
                  FilledButton.icon(
                    onPressed: back,
                    icon: const Icon(Icons.move_to_inbox_outlined),
                    label: Text(tr('Mark as returned')),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _action(
    IconData icon,
    String label,
    FutureOr<void> Function() onTap,
  ) => ListTile(
    leading: Icon(icon),
    title: Text(label),
    onTap: () => onTap(),
  );

  static Widget _row(
    BuildContext context,
    String label,
    String value, {
    bool bold = false,
    Color? color,
  }) {
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      Card(child: Column(children: children)),
    ],
  );
}

/// The top card: customer, status and the three dates.
class _Header extends StatelessWidget {
  const _Header({required this.booking, required this.service});
  final Booking booking;
  final bool service;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final style = AuroraStyle.of(context);
    final text = Theme.of(context).textTheme;
    final overdue = b.isOverdue(dayOf(DateTime.now()));
    Widget date(String label, DateTime d) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.labelSmall?.copyWith(color: Colors.white70)),
          Text(
            dateText(d),
            style: text.bodyMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    return Container(
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
                  b.customerName,
                  style: text.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              StatusChip(
                label: overdue
                    ? tr('Overdue')
                    : b.status.labelFor(service: service),
                color: overdue ? const Color(0xFFFFB4AB) : Colors.white,
              ),
            ],
          ),
          if (b.customerPhone.isNotEmpty)
            Text(
              b.customerPhone,
              style: text.bodyMedium?.copyWith(color: Colors.white70),
            ),
          const SizedBox(height: 14),
          if (service)
            Row(
              children: [
                date(tr('Appointment'), b.eventDate),
                if (b.eventTime.isNotEmpty)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('Time'),
                          style: text.labelSmall?.copyWith(color: Colors.white70),
                        ),
                        Text(
                          timeText(b.eventTime),
                          style: text.bodyMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            )
          else
            Row(
              children: [
                date(tr('Pickup'), b.pickupDate),
                date(tr('Event'), b.eventDate),
                date(tr('Return'), b.returnDate),
              ],
            ),
          if (b.createdBy.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              tr('Booked by {name}', {'name': b.createdBy}),
              style: text.bodySmall?.copyWith(color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }
}

class _CourierInput {
  const _CourierInput(this.name, this.number);
  final String name;
  final String number;
}

/// Courier name and tracking number, both optional.
class _CourierDialog extends StatefulWidget {
  const _CourierDialog({
    required this.dispatching,
    this.name = '',
    this.number = '',
  });

  /// true when the items are being sent now; false when only correcting.
  final bool dispatching;
  final String name;
  final String number;

  @override
  State<_CourierDialog> createState() => _CourierDialogState();
}

class _CourierDialogState extends State<_CourierDialog> {
  late final _name = TextEditingController(text: widget.name);
  late final _number = TextEditingController(text: widget.number);

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.dispatching ? tr('Dispatch by courier') : tr('Courier details'),
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: tr('Courier name (optional)')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _number,
            decoration: InputDecoration(
              labelText: tr('Courier booking number (optional)'),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr('Cancel')),
      ),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
        onPressed: () =>
            Navigator.pop(context, _CourierInput(_name.text, _number.text)),
        child: Text(widget.dispatching ? tr('Mark as dispatched') : tr('Save')),
      ),
    ],
  );
}

class _ChargeInput {
  const _ChargeInput(this.kind, this.amount, this.note);
  final ChargeKind kind;
  final double amount;
  final String note;
}

/// A late-return or damage charge: what for, how much, and a note.
class _ChargeDialog extends StatefulWidget {
  const _ChargeDialog({required this.kind, this.note = ''});
  final ChargeKind kind;
  final String note;

  @override
  State<_ChargeDialog> createState() => _ChargeDialogState();
}

class _ChargeDialogState extends State<_ChargeDialog> {
  late ChargeKind _kind = widget.kind;
  final _amount = TextEditingController();
  late final _note = TextEditingController(text: widget.note);
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _ok() {
    final v = parseAmount(_amount.text);
    if (v <= 0) {
      setState(() => _error = tr('Enter an amount.'));
      return;
    }
    Navigator.pop(context, _ChargeInput(_kind, v, _note.text));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr('Add a charge')),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<ChargeKind>(
            initialValue: _kind,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('What for')),
            items: [
              for (final k in ChargeKind.values)
                DropdownMenuItem(value: k, child: Text(k.label)),
            ],
            onChanged: (k) => setState(() => _kind = k ?? _kind),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: tr('Amount (₹)'),
              errorText: _error,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: InputDecoration(labelText: tr('Note (optional)')),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr('Cancel')),
      ),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
        onPressed: _ok,
        child: Text(tr('Save')),
      ),
    ],
  );
}

class _PaymentInput {
  const _PaymentInput(this.kind, this.amount, this.mode, this.note);
  final PaymentKind kind;
  final double amount;
  final PayMode mode;
  final String note;
}

/// Asks how much, and how it was paid. For a refund it starts at everything
/// held; type less to keep some back, for example for damage.
class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.booking, required this.kind});
  final Booking booking;
  final PaymentKind kind;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final double _max = switch (widget.kind) {
    PaymentKind.advance || PaymentKind.balance => widget.booking.balanceDue,
    PaymentKind.deposit => widget.booking.depositDue,
    PaymentKind.refund => widget.booking.depositHeld,
  };
  late final _amount = TextEditingController(text: amountText(_max));
  final _note = TextEditingController();
  PayMode _mode = PayMode.cash;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  String get _title => switch (widget.kind) {
    PaymentKind.advance || PaymentKind.balance => tr('Take payment'),
    PaymentKind.deposit => tr('Take deposit'),
    PaymentKind.refund => tr('Give deposit back'),
  };

  void _ok() {
    final v = parseAmount(_amount.text);
    final refund = widget.kind == PaymentKind.refund;
    // a refund of nothing is allowed when the whole deposit is kept
    if ((refund ? v < 0 : v <= 0) || v > _max + 0.005) {
      setState(() => _error = tr('Enter an amount up to {max}.', {'max': money(_max)}));
      return;
    }
    Navigator.pop(
      context,
      _PaymentInput(widget.kind, v, _mode, _note.text),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: tr('Amount (₹)'),
              helperText: tr('Up to {max}', {'max': money(_max)}),
              errorText: _error,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<PayMode>(
            initialValue: _mode,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('By')),
            items: [
              for (final m in PayMode.values)
                DropdownMenuItem(value: m, child: Text(m.label)),
            ],
            onChanged: (m) => setState(() => _mode = m ?? _mode),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: InputDecoration(
              labelText: widget.kind == PaymentKind.refund
                  ? tr('Reason for keeping some (optional)')
                  : tr('Note (optional)'),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr('Cancel')),
      ),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
        onPressed: _ok,
        child: Text(tr('Save')),
      ),
    ],
  );
}
