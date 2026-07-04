import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/kasse_report.dart';
import '../core/lohnquote.dart';
import '../core/money.dart';
import '../core/order_frequency.dart' show isoWeekNumber;
import '../core/third_party_report.dart';
import '../providers/auth_provider.dart';
import '../providers/feature_flag_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/personal_provider.dart';
import '../providers/team_provider.dart';
import '../services/export_service.dart';
import '../theme/theme_extensions.dart';
import '../widgets/breadcrumb_app_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/section_card.dart';

/// **Kassenbericht (Kassen-Modul M4).** Umsatz, Käufe und Rohertrag je ISO-Woche
/// / Monat / Jahr mit Vergleich zur Vorperiode und zum Vorjahr, als Diagramm +
/// Tabelle, plus CSV-Export. Admin-only (zeigt EK/Marge/Gewinn).
///
/// **Übergangsvariante bis M5:** Die Aggregate werden clientseitig aus einem
/// Belege-Fenster von ≤ 92 Tagen berechnet — die **Wochen-Sicht ist voll**, die
/// **Monats-Sicht auf 3 Buckets** begrenzt, die **Jahres-Sicht** braucht die
/// serverseitigen Tagesaggregate (Hinweis). Buckets ohne Datendeckung erscheinen
/// als „keine Daten", nie als stille 0.
///
/// **Richtwert** — Kassendaten sind Swagger-unverifiziert (§8, A2/A8).
class KassenberichtScreen extends StatefulWidget {
  const KassenberichtScreen({super.key, this.parentLabel = 'Warenwirtschaft'});

  final String parentLabel;

  @override
  State<KassenberichtScreen> createState() => _KassenberichtScreenState();
}

class _KassenberichtScreenState extends State<KassenberichtScreen> {
  ReportGranularity _granularity = ReportGranularity.week;
  String? _siteId;
  bool _loading = false;
  bool _exporting = false;
  String? _error;
  List<KassenPeriode> _perioden = const [];
  ThirdPartySummary _thirdParty = ThirdPartySummary.empty;
  bool _started = false;
  int _loadSeq = 0;

  /// Tage-Fenster für die Fremdgeld-Aggregation, grob passend zur Granularität.
  int _thirdPartyWindowDays(ReportGranularity g) => switch (g) {
        ReportGranularity.week => 84,
        ReportGranularity.month => 366,
        ReportGranularity.year => 1098,
      };

  int _bucketCount(ReportGranularity g) => switch (g) {
        ReportGranularity.week => 12,
        // Volle Anzahl anfragen: mit Server-Aggregaten (M5) gefüllt, sonst
        // bleiben ältere Buckets „keine Daten" (Belege-Fenster ≤ 92 Tage).
        ReportGranularity.month => 12,
        ReportGranularity.year => 3,
      };

  /// Zeigt den Langzeit-Hinweis nur, wenn die älteste dargestellte Periode
  /// tatsächlich ohne Daten ist (Übergang vor dem Server-Backfill) — nach M5
  /// füllen die Server-Aggregate ältere Perioden und der Hinweis verschwindet.
  bool get _showLangzeitHinweis =>
      _granularity != ReportGranularity.week &&
      _perioden.isNotEmpty &&
      !_perioden.first.hatDaten;

  Future<void> _load() async {
    // Sequenz-Token: deckt ALLE Trigger (postFrame-Erstlauf, Segment-/Site-
    // Wechsel, Refresh) — ein veralteter Lauf darf ein neueres Ergebnis nie
    // überschreiben (Muster wie SalesInsightsProvider).
    final seq = ++_loadSeq;
    final granularity = _granularity;
    final siteId = _siteId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final includeVat =
          context.read<FeatureFlagProvider>().purchasePricesIncludeVat;
      final inventory = context.read<InventoryProvider>();
      final perioden = await inventory.loadKassenbericht(
        granularity: granularity,
        purchasePricesIncludeVat: includeVat,
        siteId: siteId,
        bucketCount: _bucketCount(granularity),
      );
      // Fremdgeld getrennt aus den festgeschriebenen Abschlüssen (§5) —
      // berührt keine Umsatz-Aggregate.
      final closings = await inventory.loadCashClosings(
        siteId: siteId,
        windowDays: _thirdPartyWindowDays(granularity),
      );
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _perioden = perioden;
        _thirdParty = computeThirdPartySummary(closings);
        _loading = false;
      });
    } catch (_) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _error = 'Kassenbericht konnte nicht geladen werden.';
        _loading = false;
      });
    }
  }

  Future<void> _export(String? siteLabel) async {
    if (_perioden.isEmpty) return;
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ExportService.exportKassenberichtCsv(
        perioden: _perioden,
        granularity: _granularity,
        siteLabel: siteLabel,
        thirdParty: _thirdParty,
      );
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Export fehlgeschlagen.')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthProvider>().profile;
    final breadcrumbs = [
      BreadcrumbItem(
        label: widget.parentLabel,
        onTap: () => Navigator.of(context).maybePop(),
      ),
      const BreadcrumbItem(label: 'Kassenbericht'),
    ];
    if (profile == null || !profile.isAdmin) {
      return Scaffold(
        appBar: BreadcrumbAppBar(breadcrumbs: breadcrumbs),
        body: const Center(child: Text('Nur für Administratoren.')),
      );
    }

    final sites = [
      for (final s in context.watch<TeamProvider>().sites)
        if (s.id != null) (id: s.id!, name: s.name),
    ];
    final siteLabel = _siteId == null
        ? null
        : sites.where((s) => s.id == _siteId).map((s) => s.name).firstOrNull;

    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: breadcrumbs,
        actions: [
          IconButton(
            tooltip: 'Als CSV exportieren',
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_outlined),
            onPressed:
                _exporting || _perioden.isEmpty ? null : () => _export(siteLabel),
          ),
          IconButton(
            tooltip: 'Aktualisieren',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: _buildBody(context, sites),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<({String id, String name})> sites,
  ) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (sites.length > 1) ...[
          DropdownButtonFormField<String?>(
            initialValue: _siteId,
            decoration: const InputDecoration(
              labelText: 'Laden',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(
                  value: null, child: Text('Alle Läden')),
              for (final s in sites)
                DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
            ],
            onChanged: (value) {
              setState(() => _siteId = value);
              _load();
            },
          ),
          const SizedBox(height: 12),
        ],
        SegmentedButton<ReportGranularity>(
          segments: const [
            ButtonSegment(
                value: ReportGranularity.week,
                label: Text('Woche'),
                icon: Icon(Icons.view_week_outlined)),
            ButtonSegment(
                value: ReportGranularity.month,
                label: Text('Monat'),
                icon: Icon(Icons.calendar_month_outlined)),
            ButtonSegment(
                value: ReportGranularity.year,
                label: Text('Jahr'),
                icon: Icon(Icons.calendar_today_outlined)),
          ],
          selected: {_granularity},
          onSelectionChanged: (selection) {
            setState(() => _granularity = selection.first);
            _load();
          },
        ),
        const SizedBox(height: 16),
        const _RichtwertBanner(),
        const SizedBox(height: 12),
        if (_showLangzeitHinweis) ...[
          const _LangzeitHinweis(),
          const SizedBox(height: 12),
        ],
        if (_error != null)
          EmptyState(
            icon: Icons.error_outline,
            title: 'Fehlgeschlagen',
            message: _error!,
            action: FilledButton.tonal(
                onPressed: _load, child: const Text('Erneut versuchen')),
          )
        else if (_loading && _perioden.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_perioden.every((p) => !p.hatDaten))
          const EmptyState(
            icon: Icons.point_of_sale_outlined,
            title: 'Noch keine Kassendaten',
            message: 'Für den Zeitraum liegen keine Belege vor. Der Sync läuft '
                'über die Kasse-Einstellungen.',
          )
        else ...[
          Builder(builder: (context) {
            final current = _currentPeriode();
            if (current == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Aktuelle Periode: ${_fullPeriodLabel(current, _granularity)}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            );
          }),
          _KpiGrid(periode: _currentPeriode()),
          const SizedBox(height: 16),
          // Eigene Kasse vs. externe Dienste (§5) — getrennt, keine Vermischung
          // mit dem Umsatz. Nur sichtbar, wenn Fremdgeld erfasst wurde.
          if (!_thirdParty.isEmpty) ...[
            _ThirdPartyReportCard(
              summary: _thirdParty,
              ownRevenueGrossCents: _currentPeriode()?.umsatzBruttoCents,
            ),
            const SizedBox(height: 16),
          ],
          SectionCard(
            title: 'Umsatz pro ${_granularity.label}',
            child: _UmsatzBarChart(
                perioden: _perioden, granularity: _granularity),
          ),
          const SizedBox(height: 16),
          _DatenqualitaetHinweis(perioden: _perioden),
          const SizedBox(height: 16),
          // Lohnquote/Betriebsergebnis (M6-D): org-weit, nur Monat/Jahr, nur
          // ohne Standort-Filter (Personalkosten sind nicht standort-attribuierbar).
          if (_granularity != ReportGranularity.week && _siteId == null)
            ..._buildLohnkennzahl(context),
          SectionCard(
            title: 'Alle Perioden',
            child: _PeriodenTabelle(
                perioden: _perioden, granularity: _granularity),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildLohnkennzahl(BuildContext context) {
    final current = _currentPeriode();
    if (current == null) return const [];
    // watch (nicht read): ein asynchron eintreffender Payroll-Stream löst dann
    // einen Rebuild aus (der Screen abonniert PersonalProvider sonst nicht).
    final payrolls = context.watch<PersonalProvider>().payrollRecords;
    final kennzahlen = computeLohnkennzahlen(
      perioden: _perioden,
      payrolls: payrolls,
      granularity: _granularity,
    );
    Lohnkennzahl? k;
    for (final x in kennzahlen) {
      if (x.start == current.start) {
        k = x;
        break;
      }
    }
    if (k == null || !k.hatPersonalkosten) return const [];
    return [_LohnquoteCard(kennzahl: k), const SizedBox(height: 16)];
  }

  KassenPeriode? _currentPeriode() {
    for (var i = _perioden.length - 1; i >= 0; i--) {
      if (_perioden[i].hatDaten) return _perioden[i];
    }
    return _perioden.isEmpty ? null : _perioden.last;
  }
}

String periodLabel(KassenPeriode p, ReportGranularity g) => switch (g) {
      ReportGranularity.week => 'KW${isoWeekNumber(p.start)}',
      ReportGranularity.month => DateFormat('MMM yy', 'de_DE').format(p.start),
      ReportGranularity.year => '${p.start.year}',
    };

/// Ausgeschriebenes Periodenlabel (mit Jahr) für die KPI-Überschrift.
String _fullPeriodLabel(KassenPeriode p, ReportGranularity g) => switch (g) {
      ReportGranularity.week => 'KW${isoWeekNumber(p.start)} ${p.start.year}',
      ReportGranularity.month => DateFormat('MMMM yyyy', 'de_DE').format(p.start),
      ReportGranularity.year => '${p.start.year}',
    };

class _RichtwertBanner extends StatelessWidget {
  const _RichtwertBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.appColors.infoContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: theme.appColors.info),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Richtwert: Die Kassen-Geldfelder sind noch nicht endgültig '
              'verifiziert. Der Steuerberater bleibt maßgeblich.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _LangzeitHinweis extends StatelessWidget {
  const _LangzeitHinweis();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Neutral formuliert: das Signal (älteste Periode leer) kann nicht zwischen
    // „Server-Backfill fehlt noch" und „Laden hat legitim keine so alten Daten"
    // unterscheiden — daher keine Aussage über ein ausstehendes Server-Update.
    const text = 'Für ältere Zeiträume liegen noch keine ausgewerteten '
        'Kassendaten vor.';
    return Row(
      children: [
        Icon(Icons.schedule_outlined,
            size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}

/// KPI-Reihe der aktuellen Periode (max. 6 Karten, §7.4).
class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.periode});
  final KassenPeriode? periode;

  @override
  Widget build(BuildContext context) {
    final p = periode;
    if (p == null) return const SizedBox.shrink();
    final rohertragBrutto = p.rohertragBruttoCents;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 3 : 2;
        const spacing = 12.0;
        final width =
            (constraints.maxWidth - (columns - 1) * spacing) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final kpi in <_Kpi>[
              _Kpi('Umsatz brutto', Money.formatCents(p.umsatzBruttoCents)),
              _Kpi('Umsatz netto', Money.formatCents(p.umsatzNettoCents)),
              _Kpi(
                'Käufe netto',
                Money.formatCents(p.kaeufeNettoCents),
                subtitle: p.kaeufeBruttoCents != p.kaeufeNettoCents
                    ? 'brutto ${Money.formatCents(p.kaeufeBruttoCents)} (inkl. USt)'
                    : null,
              ),
              _Kpi(
                'Rohertrag netto',
                Money.formatCents(p.rohertragNettoCents),
                subtitle: rohertragBrutto == null
                    ? 'Gewinn vor Personal- & Fixkosten'
                    : 'brutto ${Money.formatCents(rohertragBrutto)} (enthält USt) · vor Personal-/Fixkosten',
                emphasized: true,
              ),
              _Kpi.delta('Δ Vorperiode', p.deltaVorperiodePct),
              _Kpi.delta('Δ Vorjahr', p.deltaVorjahrPct),
            ])
              SizedBox(width: width, child: _KpiCard(kpi: kpi)),
          ],
        );
      },
    );
  }
}

/// **Dritte Hand / Fremdgelder (§5).** Getrennte Darstellung „eigene Kasse vs.
/// externe Dienste" — visuell und datentechnisch abgesetzt von den Umsatz-KPIs
/// (kein gemischter „Gesamtumsatz inkl. Fremdgeld"-Wert).
class _ThirdPartyReportCard extends StatelessWidget {
  const _ThirdPartyReportCard({
    required this.summary,
    required this.ownRevenueGrossCents,
  });

  final ThirdPartySummary summary;
  final int? ownRevenueGrossCents;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final own = ownRevenueGrossCents;
    return SectionCard(
      title: 'Dritte Hand / Fremdgelder',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Treuhandgelder externer Dienste — getrennt vom eigenen Umsatz.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          for (final t in summary.byType)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(t.typeName)),
                  Text(Money.formatCents(t.totalCents),
                      style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Fremdgeld gesamt', style: theme.textTheme.titleMedium),
              Text(Money.formatCents(summary.totalCents),
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.appColors.info,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          if (own != null && own > 0) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Eigener Umsatz (brutto, akt. Periode)',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                Text(Money.formatCents(own),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Kpi {
  const _Kpi(this.label, this.value, {this.subtitle, this.emphasized = false})
      : deltaPct = null;
  _Kpi.delta(this.label, this.deltaPct)
      : value = deltaPct == null
            ? '—'
            : '${deltaPct >= 0 ? '+' : ''}${deltaPct.toStringAsFixed(0)} %',
        subtitle = null,
        emphasized = false;

  final String label;
  final String value;
  final String? subtitle;
  final bool emphasized;
  final double? deltaPct;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.kpi});
  final _Kpi kpi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color? valueColor;
    if (kpi.deltaPct != null) {
      valueColor = kpi.deltaPct! > 0
          ? theme.appColors.success
          : (kpi.deltaPct! < 0
              ? theme.colorScheme.error
              : theme.colorScheme.onSurfaceVariant);
    } else if (kpi.emphasized) {
      valueColor = theme.colorScheme.primary;
    }
    return Card(
      margin: EdgeInsets.zero,
      color: kpi.emphasized ? theme.colorScheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(kpi.label,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(
              kpi.value,
              style: (kpi.emphasized
                      ? theme.textTheme.headlineSmall
                      : theme.textTheme.titleLarge)
                  ?.copyWith(fontWeight: FontWeight.bold, color: valueColor),
            ),
            if (kpi.subtitle != null) ...[
              const SizedBox(height: 2),
              Text(kpi.subtitle!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Lohnquote & Betriebsergebnis (M6-D, §8a). Org-weit, Richtwert.
class _LohnquoteCard extends StatelessWidget {
  const _LohnquoteCard({required this.kennzahl});
  final Lohnkennzahl kennzahl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final k = kennzahl;
    final quote = k.lohnquotePct;
    return SectionCard(
      title: 'Lohnquote & Betriebsergebnis (Richtwert, alle Läden)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row(theme, 'Personalkosten (AG-gesamt)',
              Money.formatCents(k.personalkostenCents)),
          const SizedBox(height: 6),
          _row(
            theme,
            'Lohnquote (Personal ÷ Umsatz)',
            quote == null ? '—' : '${quote.toStringAsFixed(1)} %',
            emphasize: true,
          ),
          const SizedBox(height: 6),
          _row(
            theme,
            'Betriebsergebnis',
            Money.formatCents(k.betriebsergebnisCents),
            // Nur färben, wenn ein Wert vorliegt — sonst bliebe der „–"-
            // Platzhalter (Rohertrag unbewertet) fälschlich grün.
            valueColor: k.betriebsergebnisCents == null
                ? null
                : (k.betriebsergebnisCents! < 0
                    ? theme.colorScheme.error
                    : theme.appColors.success),
          ),
          const SizedBox(height: 6),
          Text(
            'Betriebsergebnis = Rohertrag netto − Personalkosten (vor Miete & '
            'sonstigen Fixkosten). Personalkosten aus freigegebenen '
            'Lohnabrechnungen, org-weit.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _row(ThemeData theme, String label, String value,
      {bool emphasize = false, Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(child: Text(label, style: theme.textTheme.bodyMedium)),
        Text(
          value,
          style: (emphasize
                  ? theme.textTheme.titleMedium
                  : theme.textTheme.bodyMedium)
              ?.copyWith(
                  fontWeight: emphasize ? FontWeight.bold : FontWeight.w600,
                  color: valueColor),
        ),
      ],
    );
  }
}

class _DatenqualitaetHinweis extends StatelessWidget {
  const _DatenqualitaetHinweis({required this.perioden});
  final List<KassenPeriode> perioden;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Aggregierte Datenqualität über die gedeckten Perioden.
    var bruttoSum = 0;
    var nettoUnsicher = 0;
    var cogsCovered = 0;
    var positiveRefunds = 0;
    var hasCogs = false;
    for (final p in perioden) {
      if (!p.hatDaten) continue;
      bruttoSum += p.umsatzBruttoCents;
      nettoUnsicher += p.nettoUnsicherCents;
      positiveRefunds += p.positiveErstattungen;
      if (p.wareneinsatzCents != null) {
        hasCogs = true;
        // EK-Abdeckung rück-rechnen: Anteil × Brutto der Periode.
        final pct = p.wareneinsatzAbdeckungPct ?? 0;
        cogsCovered += (p.umsatzBruttoCents * pct / 100).round();
      }
    }
    final ekPct = bruttoSum > 0 && hasCogs
        ? (cogsCovered / bruttoSum * 100).clamp(0, 100)
        : null;
    final nettoPct = bruttoSum > 0
        ? ((bruttoSum - nettoUnsicher) / bruttoSum * 100).clamp(0, 100)
        : null;

    final parts = <String>[
      if (nettoPct != null) 'Netto-Abdeckung ${nettoPct.toStringAsFixed(0)} %',
      if (ekPct != null) 'EK-Abdeckung ${ekPct.toStringAsFixed(0)} %',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (parts.isNotEmpty)
          Text(
            'Datenqualität: ${parts.join(' · ')}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        if (positiveRefunds > 0) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.warning_amber_outlined,
                  size: 16, color: theme.appColors.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$positiveRefunds Erstattungs-Beleg(e) mit positivem Betrag '
                  '— Vorzeichen der Kasse vor produktiver Nutzung prüfen.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.appColors.warning),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _UmsatzBarChart extends StatelessWidget {
  const _UmsatzBarChart({required this.perioden, required this.granularity});
  final List<KassenPeriode> perioden;
  final ReportGranularity granularity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final labels = [for (final p in perioden) periodLabel(p, granularity)];
    final values = [
      for (final p in perioden) p.umsatzBruttoCents.toDouble() / 100,
    ];
    if (values.isEmpty || values.every((v) => v == 0)) {
      return const EmptyState(
        icon: Icons.bar_chart_outlined,
        message: 'Kein Umsatz im Zeitraum.',
      );
    }
    final maxV = values.fold<double>(0, (a, b) => a > b ? a : b);
    final minV = values.fold<double>(0, (a, b) => a < b ? a : b);
    final ceiling = maxV <= 0 ? 1.0 : maxV * 1.25;
    // Erstattungs-lastige Perioden (A8: Refund-Vorzeichen unverifiziert) können
    // negativen Umsatz erzeugen — dann bis unter die Nulllinie zeichnen, sonst
    // wäre der Balken unsichtbar.
    final floor = minV < 0 ? minV * 1.25 : 0.0;
    final count = values.length;
    final euroFmt = NumberFormat.currency(
        locale: 'de_DE', symbol: '€', decimalDigits: 0);

    return SizedBox(
      height: 240,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: ceiling,
          minY: floor,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => colorScheme.inverseSurface,
              getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                '${labels[group.x]}\n${euroFmt.format(rod.toY)}',
                TextStyle(
                  color: colorScheme.onInverseSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= labels.length) {
                    return const SizedBox.shrink();
                  }
                  if (count > 8 && i.isOdd) return const SizedBox.shrink();
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(labels[i], style: theme.textTheme.labelSmall),
                  );
                },
              ),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(count, (i) {
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: values[i],
                  color: colorScheme.primary,
                  width: count > 8 ? 10 : 16,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _PeriodenTabelle extends StatelessWidget {
  const _PeriodenTabelle({required this.perioden, required this.granularity});
  final List<KassenPeriode> perioden;
  final ReportGranularity granularity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Neueste zuerst.
    final rows = perioden.reversed.toList();
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 64),
            Expanded(
                child: Text('Umsatz',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelMedium)),
            Expanded(
                child: Text('Rohertrag',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelMedium)),
            SizedBox(
                width: 64,
                child: Text('Δ',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelMedium)),
          ],
        ),
        const Divider(),
        for (final p in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                    width: 64,
                    child: Text(periodLabel(p, granularity),
                        style: theme.textTheme.bodyMedium)),
                Expanded(
                  child: Text(
                    p.hatDaten ? Money.formatCents(p.umsatzBruttoCents) : '—',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: p.hatDaten ? null : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    Money.formatCents(p.rohertragNettoCents),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    p.deltaVorperiodePct == null
                        ? '—'
                        : '${p.deltaVorperiodePct! >= 0 ? '+' : ''}${p.deltaVorperiodePct!.toStringAsFixed(0)}%',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: p.deltaVorperiodePct == null
                          ? theme.colorScheme.onSurfaceVariant
                          : (p.deltaVorperiodePct! >= 0
                              ? theme.appColors.success
                              : theme.colorScheme.error),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
