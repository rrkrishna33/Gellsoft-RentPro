import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/business_profile.dart';
import '../../data/csv_export.dart';
import '../../data/report_repo.dart';
import '../../data/staff.dart';
import '../../l10n/strings.dart';
import '../common/widgets.dart';

enum _Period { today, month, lastMonth, year, custom }

/// Money and activity for a span of days, with spreadsheet export.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  _Period _period = _Period.month;

  String _label(_Period p) => switch (p) {
    _Period.today => tr('Today'),
    _Period.month => tr('This month'),
    _Period.lastMonth => tr('Last month'),
    _Period.year => tr('This financial year'),
    _Period.custom => tr('Custom'),
  };

  Future<void> _choose(_Period p) async {
    final notifier = ref.read(reportRangeProvider.notifier);
    if (p == _Period.custom) {
      final now = DateTime.now();
      final cur = ref.read(reportRangeProvider);
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 5),
        lastDate: DateTime(now.year + 3),
        initialDateRange: DateTimeRange(
          start: cur.from,
          end: cur.to.subtract(const Duration(days: 1)),
        ),
      );
      if (picked == null) return;
      notifier.state = (
        from: dayOf(picked.start),
        to: dayOf(picked.end).add(const Duration(days: 1)),
      );
    } else {
      notifier.state = switch (p) {
        _Period.today => todayRange(),
        _Period.month => thisMonthRange(),
        _Period.lastMonth => lastMonthRange(),
        _ => thisFinancialYearRange(),
      };
    }
    setState(() => _period = p);
  }

  Future<void> _export() async {
    final kind = await showModalBottomSheet<CsvKind>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  tr('Export a spreadsheet'),
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
              for (final (k, title, sub) in [
                (CsvKind.bookings, tr('Bookings'), tr('Every booking with its money')),
                (CsvKind.payments, tr('Payments'), tr('Money taken and given back')),
                (CsvKind.invoices, tr('Sales register'), tr('Every invoice and bill, with GST')),
                (CsvKind.gstr1B2b, tr('GSTR-1 B2B'), tr('Invoices to customers with a GSTIN')),
                (CsvKind.gstr1B2c, tr('GSTR-1 B2C'), tr('Other customers, by state and rate')),
                (CsvKind.gstr1Hsn, tr('GSTR-1 HSN summary'), tr('Value and tax by SAC / HSN code')),
                (CsvKind.customers, tr('Customers'), tr('Who owes what')),
                (CsvKind.items, tr('Items'), tr('How often each item was booked')),
              ])
                ListTile(
                  title: Text(title),
                  subtitle: Text(sub),
                  onTap: () => Navigator.pop(ctx, k),
                ),
            ],
          ),
        ),
      ),
    );
    if (kind == null || !mounted) return;
    final r = ref.read(reportRangeProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await CsvExport(
        ownState: ref.read(profileProvider).valueOrNull?.stateCode ?? '',
      ).build(kind, r);
      final saved = await FilePicker.saveFile(
        fileName: CsvExport.fileName(kind, r),
        bytes: bytes,
        dialogTitle: tr('Save file'),
      );
      if (saved != null) {
        messenger.showSnackBar(SnackBar(content: Text(tr('File saved'))));
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(tr('Export failed: {e}', {'e': e}))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = ref.watch(reportRangeProvider);
    final async = ref.watch(reportSummaryProvider);
    final shop = ref.watch(profileProvider).valueOrNull;
    final style = AuroraStyle.of(context);
    final text = Theme.of(context).textTheme;
    final fmt = DateFormat('dd MMM');
    final last = r.to.subtract(const Duration(days: 1));

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Reports')),
        actions: [
          if (ref.watch(permsProvider).can(Permission.exportData))
            IconButton(
              tooltip: tr('Export a spreadsheet'),
              icon: const Icon(Icons.ios_share_outlined),
              onPressed: _export,
            ),
        ],
      ),
      body: AuroraBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final p in _Period.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(_label(p)),
                        selected: p == _period,
                        onSelected: (_) => _choose(p),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '${fmt.format(r.from)} - ${fmt.format(last)}',
                style: text.bodySmall,
              ),
            ),
            async.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text(tr('Error: {e}', {'e': e})),
              data: (s) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: style.hero,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: style.heroShadow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('Rent billed'),
                          style: text.labelLarge?.copyWith(color: Colors.white70),
                        ),
                        Text(
                          money(s.billed),
                          style: text.headlineMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _HeroStat(tr('Collected'), money(s.collected)),
                            ),
                            Expanded(
                              child: _HeroStat(
                                tr('Still to collect'),
                                money(s.outstanding),
                                warn: s.outstanding > 0,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.9,
                    children: [
                      _Stat(tr('Bookings'), '${s.bookings}', Icons.event_available_outlined),
                      _Stat(tr('Cancelled'), '${s.cancelled}', Icons.event_busy_outlined),
                      if (shop?.gstEnabled ?? false)
                        _Stat(tr('GST in the bills'), money(s.tax), Icons.percent),
                      _Stat(tr('Deposits held'), money(s.depositsHeld), Icons.lock_outline),
                    ],
                  ),
                  if (s.topItems.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    _Title(tr('Top items')),
                    Card(
                      child: Column(
                        children: [
                          for (final i in s.topItems)
                            ListTile(
                              title: Text(i.name),
                              subtitle: Text(tr('{n} bookings', {'n': i.count})),
                              trailing: Text(
                                money(i.amount),
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (s.topCustomers.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    _Title(tr('Top customers')),
                    Card(
                      child: Column(
                        children: [
                          for (final c in s.topCustomers)
                            ListTile(
                              title: Text(c.name),
                              subtitle: Text(tr('{n} bookings', {'n': c.count})),
                              trailing: Text(
                                money(c.amount),
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (s.bookings == 0 && s.collected == 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: EmptyState(
                        icon: Icons.bar_chart_outlined,
                        message: tr('No bookings in this period.'),
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (ref.watch(permsProvider).can(Permission.exportData))
                    OutlinedButton.icon(
                      onPressed: _export,
                      icon: const Icon(Icons.ios_share_outlined),
                      label: Text(tr('Export a spreadsheet')),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
    ),
  );
}

class _HeroStat extends StatelessWidget {
  const _HeroStat(this.label, this.value, {this.warn = false});
  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.bodySmall?.copyWith(color: Colors.white70)),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: text.titleMedium?.copyWith(
              color: warn ? const Color(0xFFFFD98A) : Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AuroraStyle.of(context).softShadow,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
