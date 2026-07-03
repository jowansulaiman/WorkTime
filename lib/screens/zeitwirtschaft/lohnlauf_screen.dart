import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../models/payroll_record.dart';
import '../../providers/personal_provider.dart';
import '../../routing/shell_tab.dart';
import '../../services/export_service.dart';
import '../../ui/ui.dart';

/// Lohnlauf (AllTec `PayrollRunPage`, M6) — dedizierte **Batch-Run-Seite** eines
/// Abrechnungsmonats im Zeitwirtschafts-Hub. Zeigt die im Monatsabschluss (M5)
/// erzeugten Entwurfs-Lohndatensätze, ihre Summen-KPIs und erlaubt die
/// **Sammel-Freigabe** aller Entwürfe, Einzel-Status, PDF-Export.
///
/// Reine **Reuse**-Seite: alle Berechnungen/Freigaben laufen über den
/// [PersonalProvider] (`payrollForPeriod`/`finalizeAllDrafts`/`setPayrollStatus`,
/// Freigabe bucht via H-A1-Poster die Personalkosten) und [ExportService]. Das
/// **Bearbeiten** einzelner Abrechnungen bleibt im Personal-Bereich.
class LohnlaufScreen extends StatefulWidget {
  const LohnlaufScreen({super.key, this.parentLabel = 'Zeitwirtschaft'});

  final String parentLabel;

  @override
  State<LohnlaufScreen> createState() => _LohnlaufScreenState();
}

class _LohnlaufScreenState extends State<LohnlaufScreen> {
  static const _monthNames = [
    'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
    'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
  ];

  late int _year;
  late int _month;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Lohnlauf betrifft den zuletzt abgeschlossenen (Vor-)Monat → Default.
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 1);
    _year = start.year;
    _month = start.month;
  }

  void _changeMonth(int delta) {
    final next = DateTime(_year, _month + delta);
    setState(() {
      _year = next.year;
      _month = next.month;
    });
  }

  @override
  Widget build(BuildContext context) {
    final personal = context.watch<PersonalProvider>();
    final spacing = context.spacing;
    final records = personal.payrollForPeriod(_year, _month)
      ..sort((a, b) {
        final an = personal.memberById(a.userId)?.displayName ?? a.userId;
        final bn = personal.memberById(b.userId)?.displayName ?? b.userId;
        return an.toLowerCase().compareTo(bn.toLowerCase());
      });
    final drafts =
        records.where((r) => r.status == PayrollStatus.entwurf).length;

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: widget.parentLabel,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const BreadcrumbItem(label: 'Lohnlauf'),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                  spacing.md, spacing.md, spacing.md, spacing.xl),
              children: [
                _MonthPicker(
                  label: '${_monthNames[_month - 1]} $_year',
                  onPrevious: () => _changeMonth(-1),
                  onNext: () => _changeMonth(1),
                ),
                SizedBox(height: spacing.md),
                _Summary(
                  records: records,
                  monthLabel: '${_monthNames[_month - 1]} $_year',
                ),
                if (records.isNotEmpty) ...[
                  SizedBox(height: spacing.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.table_view_outlined),
                      label: const Text('Lohnjournal (CSV)'),
                      onPressed: () => ExportService.exportLohnjournalCsv(
                        records: records,
                        employeeName: (uid) =>
                            personal.memberById(uid)?.displayName ?? uid,
                        monthLabel: '${_monthNames[_month - 1]} $_year',
                        fileStamp:
                            '$_year-${_month.toString().padLeft(2, '0')}',
                      ),
                    ),
                  ),
                ],
                if (drafts > 0) ...[
                  SizedBox(height: spacing.md),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: _busy ? null : () => _finalizeAll(drafts),
                      icon: const Icon(Icons.verified_outlined, size: 18),
                      label: Text('Alle Entwürfe freigeben ($drafts)'),
                    ),
                  ),
                ],
                SizedBox(height: spacing.lg),
                if (records.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(spacing.lg),
                    child: const AppEmptyState(
                      icon: Icons.receipt_long_outlined,
                      message:
                          'Für diesen Monat liegen keine Lohnabrechnungen vor. '
                          'Entwürfe entstehen beim Mitarbeiterabschluss.',
                    ),
                  )
                else
                  for (final record in records) ...[
                    Builder(builder: (context) {
                      final name =
                          personal.memberById(record.userId)?.displayName ??
                              'Unbekannt';
                      return _PayrollCard(
                        record: record,
                        name: name,
                        busy: _busy,
                        onStatus: (status) => _setStatus(record, status),
                        onPdf: () => _exportPdf(record, name),
                      );
                    }),
                    SizedBox(height: spacing.sm),
                  ],
                SizedBox(height: spacing.md),
                OutlinedButton.icon(
                  onPressed: () =>
                      context.push(AppRoutes.zeitMitarbeiterabschluss),
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: const Text('Zum Mitarbeiterabschluss'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Aktionen ────────────────────────────────────────────────────────────────
  Future<void> _finalizeAll(int drafts) async {
    final confirmed = await AppConfirmDialog.show(
      context,
      title: 'Alle Entwürfe freigeben',
      message: '$drafts noch nicht freigegebene Lohnabrechnungen für '
          '${_monthNames[_month - 1]} $_year werden freigegeben und die '
          'Personalkosten gebucht.',
      confirmLabel: 'Freigeben',
      destructive: false,
      icon: Icons.verified_outlined,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<PersonalProvider>().finalizeAllDrafts(_year, _month);
    } catch (error) {
      if (mounted) _snack('Freigabe fehlgeschlagen: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(PayrollRecord record, PayrollStatus status) async {
    if (status == record.status) return;
    setState(() => _busy = true);
    try {
      await context.read<PersonalProvider>().setPayrollStatus(record, status);
    } catch (error) {
      if (mounted) _snack('Statusänderung fehlgeschlagen: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportPdf(PayrollRecord record, String name) async {
    try {
      await ExportService.exportPayrollPdf(record: record, employeeName: name);
    } catch (error) {
      if (mounted) _snack('PDF-Export fehlgeschlagen: $error');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

// ══════════════════════════════════════════════════════════════════════════════

AppStatusTone _statusTone(PayrollStatus status) => switch (status) {
      PayrollStatus.entwurf => AppStatusTone.neutral,
      PayrollStatus.freigegeben => AppStatusTone.info,
      PayrollStatus.bezahlt => AppStatusTone.success,
      PayrollStatus.storniert => AppStatusTone.error,
    };

class _Summary extends StatelessWidget {
  const _Summary({required this.records, required this.monthLabel});

  final List<PayrollRecord> records;
  final String monthLabel;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final appColors = Theme.of(context).appColors;

    var grossSum = 0, deductionsSum = 0, netSum = 0, employerSum = 0;
    var drafts = 0, released = 0, paid = 0, cancelled = 0;
    for (final r in records) {
      if (r.status == PayrollStatus.storniert) {
        cancelled++;
        continue;
      }
      grossSum += r.grossCents;
      deductionsSum += r.totalDeductionsCents;
      netSum += r.netCents;
      employerSum += r.employerTotalCents;
      switch (r.status) {
        case PayrollStatus.entwurf:
          drafts++;
        case PayrollStatus.freigegeben:
          released++;
        case PayrollStatus.bezahlt:
          paid++;
        case PayrollStatus.storniert:
          break;
      }
    }

    final aktiveCount = drafts + released + paid; // ohne stornierte

    return AppSectionCard(
      title: 'Lohnlauf $monthLabel',
      icon: Icons.account_balance_wallet_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: AppStatCard(
                  label: 'Brutto gesamt',
                  value: Money.formatCents(grossSum),
                  subtitle: '$aktiveCount Abrechnungen',
                  icon: Icons.arrow_upward,
                  color: appColors.info,
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: AppStatCard(
                  label: 'Abzüge gesamt',
                  value: Money.formatCents(deductionsSum),
                  subtitle: 'Steuer + SV (AN)',
                  icon: Icons.arrow_downward,
                  color: appColors.warning,
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.sm),
          Row(
            children: [
              Expanded(
                child: AppStatCard(
                  label: 'Netto gesamt',
                  value: Money.formatCents(netSum),
                  subtitle: 'Auszahlung',
                  icon: Icons.payments_outlined,
                  color: appColors.success,
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: AppStatCard(
                  label: 'AG-Kosten gesamt',
                  value: Money.formatCents(employerSum),
                  subtitle: 'inkl. AG-SV',
                  icon: Icons.business_outlined,
                  color: appColors.info,
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.sm),
          Text(
            '${records.length} Abrechnungen · $drafts Entwurf · '
            '$released freigegeben · $paid bezahlt'
            '${cancelled > 0 ? ' · $cancelled storniert' : ''}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _PayrollCard extends StatelessWidget {
  const _PayrollCard({
    required this.record,
    required this.name,
    required this.busy,
    required this.onStatus,
    required this.onPdf,
  });

  final PayrollRecord record;
  final String name;
  final bool busy;
  final ValueChanged<PayrollStatus> onStatus;
  final VoidCallback onPdf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              AppStatusBadge(
                label: record.status.label,
                tone: _statusTone(record.status),
                filled: true,
              ),
              SizedBox(width: context.spacing.xs),
              AppStatusBadge(
                label: record.kind == PayrollEmploymentKind.minijob
                    ? 'Minijob'
                    : record.taxClass.shortLabel,
                tone: AppStatusTone.neutral,
                filled: true,
              ),
              if (record.journalEntryId != null) ...[
                SizedBox(width: context.spacing.xs),
                const AppStatusBadge(
                  label: 'Gebucht',
                  tone: AppStatusTone.success,
                  filled: true,
                ),
              ],
            ],
          ),
          SizedBox(height: context.spacing.sm),
          Row(
            children: [
              Expanded(
                child: _Amount(
                    label: 'Brutto', value: Money.formatCents(record.grossCents)),
              ),
              Expanded(
                child: _Amount(
                  label: 'Netto',
                  value: Money.formatCents(record.netCents),
                  color: theme.appColors.success,
                ),
              ),
              Expanded(
                child: _Amount(
                    label: 'AG-Kosten',
                    value: Money.formatCents(record.employerTotalCents)),
              ),
            ],
          ),
          SizedBox(height: context.spacing.sm),
          Row(
            children: [
              PopupMenuButton<PayrollStatus>(
                enabled: !busy,
                tooltip: 'Status ändern',
                onSelected: onStatus,
                itemBuilder: (_) => [
                  for (final status in PayrollStatus.values)
                    PopupMenuItem(
                      value: status,
                      enabled: status != record.status,
                      child: Row(
                        children: [
                          Icon(
                            status == record.status
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: 18,
                          ),
                          SizedBox(width: context.spacing.sm),
                          Text(status.label),
                        ],
                      ),
                    ),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.flag_outlined, size: 18),
                    SizedBox(width: context.spacing.xs),
                    Text('Status', style: theme.textTheme.labelLarge),
                    const Icon(Icons.arrow_drop_down, size: 18),
                  ],
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('PDF'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Amount extends StatelessWidget {
  const _Amount({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
      ],
    );
  }
}

class _MonthPicker extends StatelessWidget {
  const _MonthPicker(
      {required this.label, required this.onPrevious, required this.onNext});

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Vorheriger Monat',
            onPressed: onPrevious,
          ),
          Expanded(
            child: Center(
              child: Text(label,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Nächster Monat',
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}
