import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/gst.dart';
import '../../data/business_profile.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../l10n/strings.dart';
import '../common/widgets.dart';

/// Add a new customer, or change or remove an existing one.
class CustomerFormScreen extends ConsumerStatefulWidget {
  const CustomerFormScreen({super.key, this.customer});

  /// The customer being changed, or null for a new one.
  final Customer? customer;

  @override
  ConsumerState<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends ConsumerState<CustomerFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.customer?.name);
  late final _phone = TextEditingController(text: widget.customer?.phone);
  late final _address = TextEditingController(text: widget.customer?.address);
  late final _gstin = TextEditingController(text: widget.customer?.gstin);
  late String _state = widget.customer?.stateCode ?? '';
  late final _idNote = TextEditingController(text: widget.customer?.idNote);
  late final _notes = TextEditingController(text: widget.customer?.notes);
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _gstin, _idNote, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final old = widget.customer;
    final repo = ref.read(customerRepoProvider);

    // the same phone number twice is almost always the same person
    final twin = await repo.byPhone(_phone.text, exceptId: old?.id);
    if (twin != null) {
      if (!mounted) return;
      final goOn = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Same phone number')),
          content: Text(
            tr('{name} already has this phone number. Save anyway?', {
              'name': twin.name,
            }),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Save anyway')),
            ),
          ],
        ),
      );
      if (goOn != true) return;
    }

    setState(() => _saving = true);
    await repo.save(
      Customer(
        id: old?.id,
        uuid: old?.uuid ?? '',
        name: _name.text,
        phone: _phone.text,
        address: _address.text,
        gstin: _gstin.text,
        stateCode: _state,
        idNote: _idNote.text,
        notes: _notes.text,
        createdAt: old?.createdAt ?? DateTime.now(),
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    final ok = await confirmRemove(
      context,
      title: tr('Remove this customer?'),
      message: tr('Their old bookings stay. They will leave the customer list.'),
    );
    if (!ok || !mounted) return;
    await ref.read(customerRepoProvider).delete(widget.customer!.id!);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.customer != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? tr('Edit customer') : tr('Add customer')),
        actions: [
          if (editing)
            IconButton(
              tooltip: tr('Remove'),
              icon: const Icon(Icons.delete_outline),
              onPressed: _remove,
            ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: tr('Customer name')),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? tr('Enter the customer name')
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: tr('Phone')),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _address,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: tr('Address')),
            ),
            if (ref.watch(profileProvider).valueOrNull?.gstEnabled ?? false) ...[
              const SizedBox(height: 14),
              TextFormField(
                controller: _gstin,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: tr('Customer GSTIN (optional)'),
                  helperText: tr('Only for a business customer'),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty || isValidGstin(v.trim()))
                    ? null
                    : tr('This GSTIN does not look right'),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: indianStates.containsKey(_state) ? _state : '',
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: tr('State of the customer'),
                  helperText: tr('Leave empty for the same state as your shop'),
                ),
                items: [
                  DropdownMenuItem(value: '', child: Text(tr('Same as my shop'))),
                  for (final e in indianStates.entries)
                    DropdownMenuItem(
                      value: e.key,
                      child: Text('${e.key} - ${e.value}', overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _state = v ?? ''),
              ),
            ],
            const SizedBox(height: 14),
            TextFormField(
              controller: _idNote,
              decoration: InputDecoration(
                labelText: tr('ID shown (optional)'),
                helperText: tr('For example: Aadhaar ending 1234'),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: tr('Notes (optional)')),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(tr('Save')),
            ),
          ],
        ),
      ),
    );
  }
}
