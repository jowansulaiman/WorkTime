import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/sfn_lage.dart';
import '../../core/zeitkonto_snapshot_builder.dart';
import '../../models/absence_request.dart';
import '../../models/sollzeit_profile.dart';
import '../../models/work_entry.dart';
import '../../models/zeitkonto_snapshot.dart';
import '../../providers/personal_provider.dart';
import '../../providers/schedule_provider.dart';
import '../../providers/work_provider.dart';
import '../../providers/zeitwirtschaft_provider.dart';
import '../../ui/ui.dart';

/// Stundenkonto (AllTec `HourAccountPage`, M4b) — Soll/Ist/Saldo des eigenen
/// Monats + Jahres-Übersicht. Der laufende Monat wird live über
/// [buildZeitkontoSnapshot] berechnet (Sollzeit + WorkEntries + Abwesenheiten),
/// abgeschlossene Monate kommen aus den persistierten [ZeitkontoSnapshot]s.
///
/// Self-View: Soll braucht Zugriff auf das `SollzeitProfile` (admin-gepflegt) —
/// für Mitarbeiter ohne Self-Read (bis M7) zeigt der Screen Ist + Hinweis.
class StundenkontoScreen extends StatefulWidget {
  const StundenkontoScreen({super.key, this.parentLabel = 'Zeitwirtschaft'});

  final String parentLabel;

  @override
  State<StundenkontoScreen> createState() => _StundenkontoScreenState();
}

class _StundenkontoScreenState extends State<StundenkontoScreen> {
  static final _monthFormat = DateFormat('MMMM yyyy', 'de_DE');
  static const _monthAbbr = [
    'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun',
    'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final work = context.read<WorkProvider>();
      final zeit = context.read<ZeitwirtschaftProvider>();
      zeit.loadSnapshots(work.selectedMonth.year);
      // Übertragsquelle (Vormonat) laden — deckt die Jahresgrenze (Januar →
      // Dezember Vorjahr) ab, die der Jahres-Cache nicht enthält.
      zeit.loadCarryover(work.selectedMonth);
    });
  }

  @override
  Widget build(BuildContext context) {
    final work = context.watch<WorkProvider>();
    final zeit = context.watch<ZeitwirtschaftProvider>();
    // watch (nicht read): Sollzeit-Profile/Abwesenheiten kommen asynchron per
    // Stream — sonst zeigt der Screen fälschlich „keine Sollzeit" bis zum nächsten
    // fremden notify.
    final personal = context.watch<PersonalProvider>();
    final schedule = context.watch<ScheduleProvider>();
    final spacing = context.spacing;
    final user = work.currentUser;
    final month = work.selectedMonth;

    final profiles = user == null
        ? const <SollzeitProfile>[]
        : personal.sollzeitProfilesForUser(user.uid);
    final absences = user == null
        ? const <AbsenceRequest>[]
        : schedule.absenceRequests
            .where((a) => a.userId == user.uid)
            .toList();
    final prevMonth = month.month == 1 ? 12 : month.month - 1;
    final prevYear = month.month == 1 ? month.year - 1 : month.year;
    // Im selben Jahr aus dem Cache; an der Jahresgrenze (Januar) aus dem gezielt
    // geladenen Übertrag (sonst fehlte der Dezember-Übertrag → Saldo zu niedrig).
    final persistedPrev = prevYear == month.year
        ? zeit.snapshotFor(prevYear, prevMonth)
        : zeit.carryover;

    final live = user == null
        ? null
        : buildZeitkontoSnapshot(
            orgId: user.orgId,
            userId: user.uid,
            jahr: month.year,
            monat: month.month,
            profiles: profiles,
            entries: work.entries,
            approvedAbsences: absences,
            previous: persistedPrev,
          );
    final hasSoll = profiles.isNotEmpty;

    // §3b-Transparenz (ZV-5.3): aus den genehmigten Monats-Einträgen abgeleitete
    // Nacht-/Sonn-/Feiertagsstunden — reine Anzeige „deine Zuschlagszeiten sind
    // erfasst" (Verrechnung bleibt im Lohnlauf). Bundesland-Default SH (Kiel);
    // Nacht/Sonntag sind ohnehin bundeslandunabhängig.
    final sfnLage = user == null
        ? SfnLage.zero
        : computeSfnLage(
            work.entries.where((e) =>
                e.userId == user.uid &&
                e.date.year == month.year &&
                e.date.month == month.month &&
                e.status == WorkEntryStatus.approved),
            bundesland: 'SH',
          );

    // ArbZG §3 (vereinfacht): wöchentlicher Schnitt des Monats > 48 h.
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final weeks = daysInMonth / 7.0;
    final weeklyAvg = (live != null && weeks > 0) ? live.istHours / weeks : 0.0;
    final exceeds48 = hasSoll && weeklyAvg > 48;

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: widget.parentLabel,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const BreadcrumbItem(label: 'Stundenkonto'),
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
                _MonthHeader(
                  label: _monthFormat.format(month),
                  onPrevious: () => _changeMonth(work, zeit, -1),
                  onNext: () => _changeMonth(work, zeit, 1),
                ),
                SizedBox(height: spacing.md),
                if (exceeds48) ...[
                  _Banner(
                    color: Theme.of(context).appColors.warning,
                    icon: Icons.warning_amber,
                    message:
                        'Die wöchentliche Durchschnittsarbeitszeit überschreitet 48 Stunden (ArbZG §3). Bitte den Ausgleichszeitraum prüfen.',
                  ),
                  SizedBox(height: spacing.md),
                ],
                if (!hasSoll) ...[
                  _Banner(
                    color: Theme.of(context).colorScheme.primary,
                    icon: Icons.info_outline,
                    message:
                        'Für dieses Profil ist (noch) keine Sollzeit hinterlegt – es wird nur die Ist-Zeit angezeigt. Das Soll pflegt ein Admin in der Stammakte.',
                  ),
                  SizedBox(height: spacing.md),
                ],
                if (live != null)
                  _SummaryCard(snapshot: live, hasSoll: hasSoll),
                if (!sfnLage.isZero) ...[
                  SizedBox(height: spacing.md),
                  _Sfn3bCard(lage: sfnLage),
                ],
                SizedBox(height: spacing.lg),
                Text('Jahresübersicht ${month.year}',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                SizedBox(height: spacing.sm),
                _YearTable(
                  year: month.year,
                  liveMonth: month.month,
                  live: live,
                  snapshots: zeit.yearSnapshots,
                  hasSoll: hasSoll,
                  monthAbbr: _monthAbbr,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _changeMonth(
      WorkProvider work, ZeitwirtschaftProvider zeit, int delta) {
    final m = work.selectedMonth;
    final next = DateTime(m.year, m.month + delta);
    work.selectMonth(next);
    if (next.year != zeit.snapshotYear) {
      zeit.loadSnapshots(next.year);
    }
    zeit.loadCarryover(next);
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.snapshot, required this.hasSoll});

  final ZeitkontoSnapshot snapshot;
  final bool hasSoll;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: spacing.lg,
            runSpacing: spacing.md,
            children: [
              _Metric(
                  label: 'Soll',
                  value: hasSoll ? _h(snapshot.sollHours) : '—'),
              _Metric(label: 'Ist', value: _h(snapshot.istHours)),
              _Metric(
                label: 'Überstunden',
                value: hasSoll ? _signed(snapshot.ueberstundenHours) : '—',
              ),
              _Metric(
                label: 'Saldo',
                value: hasSoll ? _signed(snapshot.saldoHours) : '—',
                emphasize: true,
              ),
            ],
          ),
          if (hasSoll) ...[
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                      label: 'Übertrag Vormonat',
                      value: _signed(snapshot.uebertragHours)),
                ),
                Expanded(
                  child: _MiniStat(
                      label: 'Ausbezahlt',
                      value: _h(snapshot.ausgezahltHours)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// §3b-Zuschlagsstunden-Transparenz (ZV-5.3): zeigt dem Mitarbeiter, dass seine
/// Nacht-/Sonn-/Feiertagsstunden erfasst sind (die Verrechnung macht der Lohnlauf).
class _Sfn3bCard extends StatelessWidget {
  const _Sfn3bCard({required this.lage});

  final SfnLage lage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = context.spacing;
    final parts = <String>[
      if (lage.nachtMinuten > 0) 'Nacht ${_h(lage.nachtStunden)}',
      if (lage.sonntagMinuten > 0) 'Sonntag ${_h(lage.sonntagStunden)}',
      if (lage.feiertagMinuten > 0) 'Feiertag ${_h(lage.feiertagStunden)}',
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.nightlight_round,
                  size: 18, color: theme.colorScheme.primary),
              SizedBox(width: spacing.sm),
              Text('Zuschlagszeiten (§3b)',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          SizedBox(height: spacing.xs),
          Text(
            'davon ${parts.join(' · ')}',
            style: theme.textTheme.bodyMedium,
          ),
          SizedBox(height: spacing.xxs),
          Text(
            'Aus deinen genehmigten Zeiten abgeleitet – die Auszahlung erfolgt im Lohnlauf.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(
      {required this.label, required this.value, this.emphasize = false});

  final String label;
  final String value;
  final bool emphasize;

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
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: emphasize ? theme.colorScheme.primary : null,
          ),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

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
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _YearTable extends StatelessWidget {
  const _YearTable({
    required this.year,
    required this.liveMonth,
    required this.live,
    required this.snapshots,
    required this.hasSoll,
    required this.monthAbbr,
  });

  final int year;
  final int liveMonth;
  final ZeitkontoSnapshot? live;
  final List<ZeitkontoSnapshot> snapshots;
  final bool hasSoll;
  final List<String> monthAbbr;

  ZeitkontoSnapshot? _forMonth(int monat) {
    for (final s in snapshots) {
      if (s.monat == monat) return s;
    }
    if (monat == liveMonth) return live;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = theme.appColors;
    return AppCard(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: context.spacing.lg,
          columns: const [
            DataColumn(label: Text('Monat')),
            DataColumn(label: Text('Soll'), numeric: true),
            DataColumn(label: Text('Ist'), numeric: true),
            DataColumn(label: Text('Saldo'), numeric: true),
            DataColumn(label: Text('Status')),
          ],
          rows: [
            for (var m = 1; m <= 12; m++)
              _row(context, m, _forMonth(m), appColors),
          ],
        ),
      ),
    );
  }

  DataRow _row(BuildContext context, int monat, ZeitkontoSnapshot? snap,
      AppThemeColors appColors) {
    final theme = Theme.of(context);
    final persisted = snapshots.any((s) => s.monat == monat);
    if (snap == null) {
      return DataRow(cells: [
        DataCell(Text(monthAbbr[monat - 1])),
        const DataCell(Text('—')),
        const DataCell(Text('—')),
        const DataCell(Text('—')),
        DataCell(Text('offen',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
      ]);
    }
    return DataRow(cells: [
      DataCell(Text(monthAbbr[monat - 1])),
      DataCell(Text(hasSoll ? _h(snap.sollHours) : '—')),
      DataCell(Text(_h(snap.istHours))),
      DataCell(Text(hasSoll ? _signed(snap.saldoHours) : '—')),
      DataCell(
        snap.abgeschlossen
            ? Icon(Icons.lock, size: 16, color: appColors.success)
            : (persisted
                ? Icon(Icons.lock_open,
                    size: 16, color: theme.colorScheme.onSurfaceVariant)
                : Text('laufend',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: appColors.info, fontWeight: FontWeight.w600))),
      ),
    ]);
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader(
      {required this.label, required this.onPrevious, required this.onNext});

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
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
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Nächster Monat',
          onPressed: onNext,
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner(
      {required this.color, required this.icon, required this.message});

  final Color color;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(context.spacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(context.radii.md),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          SizedBox(width: context.spacing.sm),
          Expanded(
            child: Text(message,
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

String _h(double hours) => '${hours.toStringAsFixed(1)} h';

String _signed(double hours) {
  final prefix = hours > 0.05 ? '+' : '';
  return '$prefix${hours.toStringAsFixed(1)} h';
}
