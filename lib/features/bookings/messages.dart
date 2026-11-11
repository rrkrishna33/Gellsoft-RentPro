import '../../core/format.dart';
import '../../data/booking_models.dart';
import '../../data/business_profile.dart';
import '../../data/invoice_models.dart';
import '../../data/reminders.dart';
import '../../l10n/strings.dart';

String _items(Booking b) => b.lines.map((l) => l.name).join(', ');

String _sign(BusinessProfile shop) => shop.phone.trim().isEmpty
    ? shop.name
    : '${shop.name}, ${shop.phone.trim()}';

/// Sent to the customer when a booking is made: what, when and what is due.
String confirmationMessage(Booking b, BusinessProfile shop) => tr(
  'Hello {name}, your booking #{n} with {shop} is confirmed.\nItems: {items}\nPickup: {pickup}\nEvent: {event}\nReturn: {ret}\nTotal: {total}. Paid: {paid}. Balance: {balance}.\nThank you!\n{sign}',
  {
    'name': b.customerName,
    'n': b.number,
    'shop': shop.name,
    'items': _items(b),
    'pickup': dateText(b.pickupDate),
    'event': dateText(b.eventDate),
    'ret': dateText(b.returnDate),
    'total': money(b.payable),
    'paid': money(b.rentPaid),
    'balance': money(b.balanceDue),
    'sign': _sign(shop),
  },
);

/// The message for a reminder of the given kind, to the customer.
String reminderMessage(ReminderKind kind, Booking b, BusinessProfile shop) =>
    switch (kind) {
      ReminderKind.sendItems => tr(
        'Hello {name}, your items for the event on {event} are ready at {shop}. Please collect them on {pickup}. Balance to pay: {balance}.\n{sign}',
        {
          'name': b.customerName,
          'event': dateText(b.eventDate),
          'shop': shop.name,
          'pickup': dateText(b.pickupDate),
          'balance': money(b.balanceDue),
          'sign': _sign(shop),
        },
      ),
      ReminderKind.returnDue => tr(
        'Hello {name}, a gentle reminder to return the items from booking #{n} on {ret}. Thank you!\n{sign}',
        {
          'name': b.customerName,
          'n': b.number,
          'ret': dateText(b.returnDate),
          'sign': _sign(shop),
        },
      ),
      ReminderKind.overdue => tr(
        'Hello {name}, the items from booking #{n} were due back on {ret}. Please return them as soon as you can. Thank you!\n{sign}',
        {
          'name': b.customerName,
          'n': b.number,
          'ret': dateText(b.returnDate),
          'sign': _sign(shop),
        },
      ),
      ReminderKind.balance => tr(
        'Hello {name}, {balance} is pending for booking #{n} at {shop}. Please pay at your earliest. Thank you!\n{sign}',
        {
          'name': b.customerName,
          'balance': money(b.balanceDue),
          'n': b.number,
          'shop': shop.name,
          'sign': _sign(shop),
        },
      ),
    };

/// Sent with (or instead of) the invoice PDF.
String invoiceMessage(Invoice inv, BusinessProfile shop) => tr(
  'Hello {name}, here is your {kind} {label} from {shop}.\nTotal: {total}. Paid: {paid}. Balance: {due}.\nThank you!\n{sign}',
  {
    'name': inv.customerName,
    'kind': inv.isTaxInvoice ? tr('tax invoice') : tr('bill'),
    'label': inv.label,
    'shop': shop.name,
    'total': money(inv.total),
    'paid': money(inv.paid),
    'due': money(inv.due),
    'sign': _sign(shop),
  },
);

/// Sent when a payment is taken or given back.
String receiptMessage(Payment p, Booking b, BusinessProfile shop) =>
    p.kind == PaymentKind.refund
    ? tr(
        'Hello {name}, we have returned {amount} (deposit) for booking #{n}. Thank you!\n{sign}',
        {
          'name': b.customerName,
          'amount': money(p.amount),
          'n': b.number,
          'sign': _sign(shop),
        },
      )
    : tr(
        'Hello {name}, we received {amount} ({kind}) for booking #{n} on {date}. Balance: {balance}. Thank you!\n{sign}',
        {
          'name': b.customerName,
          'amount': money(p.amount),
          'kind': p.kind.label,
          'n': b.number,
          'date': dateText(p.paidAt),
          'balance': money(b.balanceDue),
          'sign': _sign(shop),
        },
      );
