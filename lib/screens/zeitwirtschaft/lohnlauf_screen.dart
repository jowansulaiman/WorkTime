import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/datev_lohn_export.dart';
import '../../core/money.dart';
import '../../models/datev_export_run.dart';
import '../../models/employee_profile.dart';
import '../../models/payroll_record.dart';
import '../../providers/finance_provider.dart';
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
                  Wrap(
                    spacing: spacing.sm,
                    runSpacing: spacing.sm,
                    children: [
                      OutlinedButton.icon(
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
                      // PERSONAL-3: DATEV-Lohn-Export nur bei Flag + Admin.
                      if (AppConfig.datevLohnEnabled && personal.isAdmin)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('DATEV-Lohn (Export)'),
                          onPressed:
                              _busy ? null : () => _exportDatevLohn(personal),
                        ),
                      if (AppConfig.datevLohnEnabled && personal.isAdmin)
                        TextButton.icon(
                          icon: const Icon(Icons.settings_outlined, size: 18),
                          label: const Text('DATEV-Lohn-Einstellungen'),
                          onPressed: () => showAppBottomSheet(
                            context: context,
                            builder: (_) => _DatevLohnConfigSheet(
                              config: context
                                  .read<FinanceProvider>()
                                  .datevLohnConfig,
                            ),
                          ),
                        ),
                    ],
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

  /// **PERSONAL-3:** DATEV-Lohn-Export — Config-Prüfung → `buildBewegungsdaten`
  /// → Vorprüfungs-Dialog (Probleme + DSGVO) → Run in `datevExportRuns` (Q2,
  /// `exportArt: lohn`, mit `rowsSnapshot`) → Download. Reihenfolge: Run VOR
  /// Download; hybrid-offline blockiert (Q2-Semantik).
  Future<void> _exportDatevLohn(PersonalProvider personal) async {
    final finance = context.read<FinanceProvider>();
    final config = finance.datevLohnConfig;
    if (!config.isConfigured) {
      _snack('Bitte zuerst die DATEV-Lohn-Einstellungen (Berater-/Mandanten-'
          'nummer, Grundlohn-Lohnart) hinterlegen.');
      return;
    }

    final records = personal.payrollForPeriod(_year, _month);
    final profilesByUserId = <String, EmployeeProfile>{
      for (final p in personal.employeeProfiles) p.userId: p,
    };
    final ergebnis = buildBewegungsdaten(
      config: config,
      records: records,
      profilesByUserId: profilesByUserId,
      payLineTypes: personal.activePayLineTypes,
      jahr: _year,
      monat: _month,
    );
    if (ergebnis.zeilenAnzahl == 0 && ergebnis.probleme.isEmpty) {
      _snack('Keine freigegebenen Lohnabrechnungen für diesen Monat.');
      return;
    }

    // Vorprüfungs-Dialog (Probleme + DSGVO-Hinweis + Override bei Problemen).
    final proceed = await showAppBottomSheet<bool>(
      context: context,
      builder: (_) => _DatevLohnVorpruefungSheet(ergebnis: ergebnis),
    );
    if (proceed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final content = ergebnis.content;
      final fileName =
          'DATEV_Lohn_${_year}_${_month.toString().padLeft(2, '0')}.txt';
      final run = DatevExportRun(
        orgId: '',
        exportArt: DatevExportArt.lohn,
        kind: config.format.value == 'lodas'
            ? 'lodas_bewegungsdaten'
            : 'lohn_und_gehalt_bewegungsdaten',
        periodYear: _year,
        periodMonth: _month,
        createdByUid: '',
        entryCount: ergebnis.zeilenAnzahl,
        summeCents: ergebnis.summeCents,
        fileName: fileName,
        fileSha256: ExportService.sha256Hex(content),
        configSnapshot: config.toFirestoreMap(),
        rowsSnapshot: ergebnis.rows,
        snapshotRowCount: ergebnis.rows.length,
        subjectUserIds: ergebnis.subjectUserIds,
        problemeAnzahl: ergebnis.probleme.length,
        overrideBestaetigt: ergebnis.probleme.isNotEmpty,
      );

      if (finance.supportsExportHistory) {
        try {
          await finance.logDatevExportRun(run);
        } catch (error) {
          if (mounted) {
            _snack('Export nicht möglich: die Historie kann offline nicht '
                'geschrieben werden. Erst wieder online exportieren.');
          }
          return;
        }
      }
      await ExportService.downloadDatevBuchungsstapel(
        content: content,
        fileName: fileName,
      );
      if (mounted) {
        _snack(finance.supportsExportHistory
            ? 'DATEV-Lohn erstellt + in der Historie erfasst.'
            : 'DATEV-Lohn erstellt (ohne Historie im lokalen Modus).');
      }
    } catch (error) {
      if (mounted) _snack('DATEV-Lohn-Export fehlgeschlagen: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
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

// ══════════════════════════════════════════════════════════════════════════════
// PERSONAL-3: DATEV-Lohn Vorprüfung + Konfiguration
// ══════════════════════════════════════════════════════════════════════════════

/// Vorprüfungs-Dialog: zeigt gesammelte Probleme + DSGVO-Hinweis; Rückgabe
/// `true` = exportieren. Probleme blockieren NICHT (Override), werden aber
/// deutlich gezeigt.
class _DatevLohnVorpruefungSheet extends StatelessWidget {
  const _DatevLohnVorpruefungSheet({required this.ergebnis});

  final DatevLohnExportErgebnis ergebnis;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final probleme = ergebnis.probleme;
    return AppBottomSheetScaffold(
      title: 'DATEV-Lohn — Vorprüfung',
      subtitle: '${ergebnis.zeilenAnzahl} Zeile(n) · '
          '${ergebnis.subjectUserIds.length} Mitarbeiter',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (probleme.isEmpty)
            const AppStatusBanner(
              icon: Icons.check_circle_outline,
              tone: AppStatusTone.success,
              message: 'Keine Probleme gefunden.',
            )
          else ...[
            AppStatusBanner(
              icon: Icons.warning_amber_rounded,
              tone: AppStatusTone.warning,
              message: '${probleme.length} Hinweis(e) — betroffene Zeilen '
                  'werden NICHT exportiert:',
            ),
            SizedBox(height: spacing.sm),
            for (final p in probleme.take(20))
              Padding(
                padding: EdgeInsets.only(bottom: spacing.xxs),
                child: Text('• ${p.message}',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            if (probleme.length > 20)
              Text('… und ${probleme.length - 20} weitere',
                  style: Theme.of(context).textTheme.bodySmall),
          ],
          SizedBox(height: spacing.md),
          const AppStatusBanner(
            icon: Icons.privacy_tip_outlined,
            tone: AppStatusTone.info,
            message: 'Die Datei enthält Lohn-Personendaten. Nur an den '
                'Steuerberater weitergeben; die App speichert keinen '
                'Datei-Inhalt (nur revisionssichere Metadaten).',
          ),
          SizedBox(height: spacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Abbrechen'),
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(probleme.isEmpty
                      ? 'Exportieren'
                      : 'Trotzdem exportieren'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Editor für die [DatevLohnConfig] (Format, Berater-/Mandantennummer,
/// Grundlohn-Lohnart). Speichert über [FinanceProvider.saveDatevLohnConfig].
class _DatevLohnConfigSheet extends StatefulWidget {
  const _DatevLohnConfigSheet({required this.config});

  final DatevLohnConfig config;

  @override
  State<_DatevLohnConfigSheet> createState() => _DatevLohnConfigSheetState();
}

class _DatevLohnConfigSheetState extends State<_DatevLohnConfigSheet> {
  late DatevLohnFormat _format;
  late final TextEditingController _berater;
  late final TextEditingController _mandant;
  late final TextEditingController _grundlohn;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _format = widget.config.format;
    _berater = TextEditingController(text: widget.config.beraterNr);
    _mandant = TextEditingController(text: widget.config.mandantenNr);
    _grundlohn =
        TextEditingController(text: widget.config.festeLohnartGrundlohn);
  }

  @override
  void dispose() {
    _berater.dispose();
    _mandant.dispose();
    _grundlohn.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<FinanceProvider>().saveDatevLohnConfig(
            widget.config.copyWith(
              format: _format,
              beraterNr: _berater.text.trim(),
              mandantenNr: _mandant.text.trim(),
              festeLohnartGrundlohn: _grundlohn.text.trim(),
            ),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Speichern fehlgeschlagen: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    return AppBottomSheetScaffold(
      title: 'DATEV-Lohn-Einstellungen',
      subtitle: 'Vorgaben des Steuerberaters',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Format', style: Theme.of(context).textTheme.labelLarge),
          SizedBox(height: spacing.xs),
          AppSegmented<DatevLohnFormat>(
            segments: const [
              AppSegment(value: DatevLohnFormat.lodas, label: 'LODAS'),
              AppSegment(
                  value: DatevLohnFormat.lohnUndGehalt, label: 'Lohn & Gehalt'),
            ],
            selected: _format,
            onChanged: (v) => setState(() => _format = v),
          ),
          SizedBox(height: spacing.md),
          AppFormField(
            controller: _berater,
            label: 'Beraternummer',
            keyboardType: TextInputType.number,
          ),
          SizedBox(height: spacing.md),
          AppFormField(
            controller: _mandant,
            label: 'Mandantennummer',
            keyboardType: TextInputType.number,
          ),
          SizedBox(height: spacing.md),
          AppFormField(
            controller: _grundlohn,
            label: 'Lohnart Grundlohn (z. B. 100)',
            keyboardType: TextInputType.number,
          ),
          SizedBox(height: spacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Speichern'),
            ),
          ),
        ],
      ),
    );
  }
}
