import '../../core/constants.dart';
import '../../core/format.dart';
import '../../data/booking_models.dart';
import '../../data/business_profile.dart';
import '../../data/invoice_models.dart';
import '../../data/models.dart';
import '../../data/reminders.dart';
import '../../l10n/strings.dart';

String _items(Booking b) => b.lines.map((l) => l.label).join(', ');

/// "02:30 PM" after the date for a booking that has a time, else ''.
String _at(Booking b) =>
    b.eventTime.isEmpty ? '' : ' ${tr('at')} ${timeText(b.eventTime)}';

/// The pickup day, with its time when the booking has one.
String _pickup(Booking b) => b.hasHourly && b.pickupTime.isNotEmpty
    ? '${dateText(b.pickupDate)} ${timeText(b.pickupTime)}'
    : dateText(b.pickupDate);

/// The return day, with its time when the booking has one.
String _return(Booking b) => b.hasHourly && b.returnTime.isNotEmpty
    ? '${dateText(b.returnDate)} ${timeText(b.returnTime)}'
    : dateText(b.returnDate);

/// A line with the UPI pay link when the shop has a UPI id and money is due.
String _payLine(BusinessProfile shop, Booking b) {
  final link = shop.upiLink(amount: b.balanceDue, note: '#${b.number}');
  return link == null || b.balanceDue <= 0.005
      ? ''
      : '\n${tr('Pay by UPI')}: $link';
}

String _sign(BusinessProfile shop) => shop.phone.trim().isEmpty
    ? shop.name
    : '${shop.name}, ${shop.phone.trim()}';

/// Sent to the customer when a booking is made: what, when and what is due.
String confirmationMessage(Booking b, BusinessProfile shop) =>
    shop.type == ShopType.vehicle
    ? tr(
        'Hello {name}, your booking #{n} with {shop} is confirmed.\nVehicles: {items}\nPickup: {pickup}\nReturn: {ret}\nTotal: {total}. Paid: {paid}. Balance: {balance}.\nThank you!\n{sign}',
        {
          'name': b.customerName,
          'n': b.number,
          'shop': shop.name,
          'items': _items(b),
          'pickup': _pickup(b),
          'ret': _return(b),
          'total': money(b.payable),
          'paid': money(b.rentPaid),
          'balance': money(b.balanceDue),
          'sign': _sign(shop),
        },
      )
    : shop.type.isService
    ? tr(
        'Hello {name}, your appointment #{n} with {shop} is confirmed.\nServices: {items}\nDate: {event}{at}\nTotal: {total}. Paid: {paid}. Balance: {balance}.\nThank you!\n{sign}',
        {
          'name': b.customerName,
          'n': b.number,
          'shop': shop.name,
          'items': _items(b),
          'event': dateText(b.eventDate),
          'at': _at(b),
          'total': money(b.payable),
          'paid': money(b.rentPaid),
          'balance': money(b.balanceDue),
          'sign': _sign(shop),
        },
      )
    : tr(
        'Hello {name}, your booking #{n} with {shop} is confirmed.\nItems: {items}\nPickup: {pickup}\nEvent: {event}\nReturn: {ret}\nTotal: {total}. Paid: {paid}. Balance: {balance}.\nThank you!\n{sign}',
        {
          'name': b.customerName,
          'n': b.number,
          'shop': shop.name,
          'items': _items(b),
          'pickup': _pickup(b),
          'event': dateText(b.eventDate),
          'ret': _return(b),
          'total': money(b.payable),
          'paid': money(b.rentPaid),
          'balance': money(b.balanceDue),
          'sign': _sign(shop),
        },
      );

/// Sent to the customer when the items are sent by courier. The courier's
/// name and tracking number are added when they were entered.
String dispatchMessage(Booking b, BusinessProfile shop) {
  final courier = [
    if (b.courierName.isNotEmpty)
      tr('Courier: {name}', {'name': b.courierName}),
    if (b.courierNo.isNotEmpty)
      tr('Tracking number: {no}', {'no': b.courierNo}),
  ].join('\n');
  return tr(
    'Hello {name}, your items for booking #{n} have been sent from {shop}.{courier}\nPlease keep them safe and return them by {ret}. Thank you!\n{sign}',
    {
      'name': b.customerName,
      'n': b.number,
      'shop': shop.name,
      'courier': courier.isEmpty ? '' : '\n$courier',
      'ret': _return(b),
      'sign': _sign(shop),
    },
  );
}

/// Goes with the pictures of an item sent to a customer: what it is and what
/// it costs.
String itemShareMessage(RentItem i, BusinessProfile shop) => [
  i.name,
  if (i.size.trim().isNotEmpty) tr('Size: {size}', {'size': i.size.trim()}),
  tr('Rent: {amount} ({rate})', {
    'amount': money(i.rate),
    'rate': i.rateType.label,
  }),
  if (i.deposit > 0) tr('Deposit: {amount}', {'amount': money(i.deposit)}),
  _sign(shop),
].join('\n');

/// The message for a reminder of the given kind, to the customer.
String reminderMessage(ReminderKind kind, Booking b, BusinessProfile shop) =>
    switch (kind) {
      ReminderKind.sendItems when shop.type.isService => tr(
        'Hello {name}, a reminder of your appointment with {shop} on {event}{at}. Balance to pay: {balance}.\n{sign}',
        {
          'name': b.customerName,
          'shop': shop.name,
          'event': dateText(b.eventDate),
          'at': _at(b),
          'balance': money(b.balanceDue),
          'sign': _sign(shop),
        },
      ),
      ReminderKind.sendItems when shop.type == ShopType.vehicle => tr(
        'Hello {name}, a reminder that your booking #{n} at {shop} starts on {pickup}. Balance to pay: {balance}.\n{sign}',
        {
          'name': b.customerName,
          'n': b.number,
          'shop': shop.name,
          'pickup': _pickup(b),
          'balance': money(b.balanceDue),
          'sign': _sign(shop),
        },
      ),
      ReminderKind.sendItems => tr(
        'Hello {name}, your items for the event on {event} are ready at {shop}. Please collect them on {pickup}. Balance to pay: {balance}.\n{sign}',
        {
          'name': b.customerName,
          'event': dateText(b.eventDate),
          'shop': shop.name,
          'pickup': _pickup(b),
          'balance': money(b.balanceDue),
          'sign': _sign(shop),
        },
      ),
      ReminderKind.returnDue => tr(
        'Hello {name}, a gentle reminder to return the items from booking #{n} on {ret}. Thank you!\n{sign}',
        {
          'name': b.customerName,
          'n': b.number,
          'ret': _return(b),
          'sign': _sign(shop),
        },
      ),
      ReminderKind.overdue => tr(
        'Hello {name}, the items from booking #{n} were due back on {ret}. Please return them as soon as you can. Thank you!\n{sign}',
        {
          'name': b.customerName,
          'n': b.number,
          'ret': _return(b),
          'sign': _sign(shop),
        },
      ),
      ReminderKind.balance =>
        tr(
          'Hello {name}, {balance} is pending for booking #{n} at {shop}. Please pay at your earliest. Thank you!\n{sign}',
          {
            'name': b.customerName,
            'balance': money(b.balanceDue),
            'n': b.number,
            'shop': shop.name,
            'sign': _sign(shop),
          },
        ) +
            _payLine(shop, b),
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
