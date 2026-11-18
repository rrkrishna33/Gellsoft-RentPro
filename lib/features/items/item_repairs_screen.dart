import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../l10n/strings.dart';
import '../common/widgets.dart';

/// What went wrong with an item and what it cost to put right. The total here
/// is what the profit report takes off the item's rent.
class ItemRepairsScreen extends ConsumerStatefulWidget {
  const ItemRepairsScreen({super.key, required this.item});
  final RentItem item;

  @override
  ConsumerState<ItemRepairsScreen> createState() => _ItemRepairsScreenState();
}

class _ItemRepairsScreenState extends ConsumerState<ItemRepairsScreen> {
  List<ItemRepair>? _rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await ref.read(itemRepoProvider).repairsOf(widget.item.id!);
    if (mounted) setState(() => _rows = rows);
  }

  Future<void> _add() async {
    final r = await showDialog<({DateTime at, String note, double cost})>(
      context: context,
      builder: (_) => const _RepairDialog(),
    );
    if (r == null) return;
    await ref
        .read(itemRepoProvider)
        .addRepair(widget.item.id!, at: r.at, note: r.note, cost: r.cost);
    await _load();
  }

  Future<void> _remove(ItemRepair r) async {
    final ok = await confirmRemove(
      context,
      title: tr('Remove this entry?'),
      message: tr('It will no longer count in the profit report.'),
    );
    if (!ok) return;
    await ref.read(itemRepoProvider).removeRepair(r.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final total = rows?.fold<double>(0, (a, r) => a + r.cost) ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text(widget.item.name)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: Text(tr('Add an entry')),
      ),
      body: AuroraBackground(
        child: rows == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  Card(
                    child: ListTile(
                      title: Text(tr('Spent on repairs and damage')),
                      trailing: Text(
                        money(total),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          tr('Nothing recorded yet. Note a damage or a repair here to see what each item really earns.'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    for (final r in rows)
                      Card(
                        child: ListTile(
                          title: Text(
                            r.note.isEmpty ? tr('Repair or damage') : r.note,
                          ),
                          subtitle: Text(dateText(r.at)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                money(r.cost),
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              IconButton(
                                tooltip: tr('Remove'),
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _remove(r),
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

class _RepairDialog extends StatefulWidget {
  const _RepairDialog();

  @override
  State<_RepairDialog> createState() => _RepairDialogState();
}

class _RepairDialogState extends State<_RepairDialog> {
  final _note = TextEditingController();
  final _cost = TextEditingController();
  DateTime _at = dayOf(DateTime.now());

  @override
  void dispose() {
    _note.dispose();
    _cost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Repair or damage')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(tr('Date')),
              trailing: Text(dateText(_at)),
              onTap: () async {
                final today = dayOf(DateTime.now());
                final d = await showDatePicker(
                  context: context,
                  initialDate: _at,
                  firstDate: today.subtract(const Duration(days: 365 * 3)),
                  lastDate: today,
                );
                if (d != null) setState(() => _at = dayOf(d));
              },
            ),
            TextField(
              controller: _note,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: tr('What happened'),
                hintText: tr('For example: torn hem, stitched'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _cost,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(labelText: tr('Cost to put right (₹)')),
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
          onPressed: () => Navigator.pop(context, (
            at: _at,
            note: _note.text,
            cost: parseAmount(_cost.text),
          )),
          child: Text(tr('Save')),
        ),
      ],
    );
  }
}
