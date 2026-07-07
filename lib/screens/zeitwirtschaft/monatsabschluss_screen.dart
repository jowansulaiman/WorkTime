import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/monatsabschluss_service.dart';
import '../../core/zeitkonto_snapshot_builder.dart';
import '../../models/zeitkonto_snapshot.dart';
import '../../providers/personal_provider.dart';
import '../../providers/schedule_provider.dart';
import '../../providers/work_provider.dart';
import '../../providers/zeitwirtschaft_provider.dart';
import '../../ui/ui.dart';

/// „Mein Monatsabschluss" (AllTec `MonthClosingPage`, M5) — Self-Service-Sicht auf
/// das **eigene** Stundenkonto: 12-Monats-Übersicht eines Jahres mit Status,
/// Abschließen/Zurücknehmen.
///
/// Der Abschluss schreibt einen [ZeitkontoSnapshot] (gesperrt) und erzeugt einen
/// Entwurfs-Lohndatensatz. Da Snapshots laut `firestore.rules` nur von
/// Manager/Admin geschrieben werden dürfen (`canManageShifts`), sind die
/// Aktionen für reine Mitarbeiter ausgeblendet — ihr Abschluss läuft über die
/// Leitung im Mitarbeiterabschluss-Hub. Mitarbeiter sehen hier ihren Status.
class MonatsabschlussScreen extends StatefulWidget {
  const MonatsabschlussScreen({super.key, this.parentLabel = 'Zeitwirtschaft'});

  final String parentLabel;

  @override
  State<MonatsabschlussScreen> createState() => _MonatsabschlussScreenState();
}

class _MonatsabschlussScreenState extends State<MonatsabschlussScreen> {
  static const _monthNames = [
    'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
    'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
  ];

  late int _year;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _year = DateTime.now().year;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ZeitwirtschaftProvider>().loadSnapshots(_year);
    });
  }

  void _changeYear(int delta) {
    setState(() => _year += delta);
    context.read<ZeitwirtschaftProvider>().loadSnapshots(_year);
  }

  @override
  Widget build(BuildContext context) {
    final work = context.watch<WorkProvider>();
    final zeit = context.watch<ZeitwirtschaftProvider>();
    final spacing = context.spacing;
    final user = work.currentUser;
    final canManage = user?.canManageShifts ?? false;

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: widget.parentLabel,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const BreadcrumbItem(label: 'Mein Monatsabschluss'),
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
                _YearHeader(
                  year: _year,
                  onPrevious: () => _changeYear(-1),
                  onNext: () => _changeYear(1),
                ),
                SizedBox(height: spacing.md),
                if (!canManage) ...[
                  _Banner(
                    color: Theme.of(context).colorScheme.primary,
                    icon: Icons.info_outline,
                    message:
                        'Den Monatsabschluss nimmt deine Leitung im '
                        'Mitarbeiterabschluss vor. Hier siehst du den Status '
                        'deiner Monate.',
                  ),
                  SizedBox(height: spacing.md),
                ],
                if (_busy) ...[
                  const LinearProgressIndicator(),
                  SizedBox(height: spacing.sm),
                ],
                _MonthTable(
                  year: _year,
                  snapshots: zeit.yearSnapshots,
                  canManage: canManage,
                  monthNames: _monthNames,
                  onClose: _busy ? null : (m) => _close(m),
                  onReopen: _busy ? null : (s) => _reopen(s),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Aktionen ────────────────────────────────────────────────────────────────
  Future<void> _close(int monat) async {
    final work = context.read<WorkProvider>();
    final zeit = context.read<ZeitwirtschaftProvider>();
    final personal = context.read<PersonalProvider>();
    final schedule = context.read<ScheduleProvider>();
    final user = work.currentUser;
    // Defense-in-depth: Snapshot-Writes sind managergebunden (firestore.rules
    // `canManageShifts`); die Aktion ist ohnehin nur für Manager sichtbar.
    if (user == null || !user.canManageShifts) return;

    final confirmed = await AppConfirmDialog.show(
      context,
      title: '${_monthNames[monat - 1]} $_year abschließen?',
      message:
          'Das Stundenkonto wird gesperrt und ein Lohn-Entwurf erzeugt. '
          'Du kannst den Abschluss bei Bedarf wieder zurücknehmen.',
      confirmLabel: 'Abschließen',
      destructive: false,
      icon: Icons.lock_outline,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      final start = DateTime(_year, monat);
      final end = DateTime(_year, monat + 1);
      final entries = await work.loadEntriesForRange(start: start, end: end);
      // Z9/E6: Planzeit des Monats für den persistierten Snapshot mitziehen.
      final monthShifts = await work.loadShiftsForRange(start: start, end: end);
      final profiles = personal.sollzeitProfilesForUser(user.uid);
      final absences = schedule.absenceRequests
          .where((a) => a.userId == user.uid)
          .toList();
      final prevMonth = monat == 1 ? 12 : monat - 1;
      final prevYear = monat == 1 ? _year - 1 : _year;
      // Vormonats-Snapshot für die Lücken-Prüfung. Innerhalb des angezeigten
      // Jahres aus dem geladenen Cache; beim Jahreswechsel (Januar) liegt der
      // Dezember im Vorjahr → gezielt org-weit laden (Self-Close ist ohnehin
      // managergebunden, darf also org-weit lesen).
      final previous = monat == 1
          ? (await zeit.loadOrgSnapshotsForMonth(prevYear, prevMonth))
              .where((s) => s.userId == user.uid)
              .firstOrNull
          : zeit.snapshotFor(prevYear, prevMonth);
      final persisted = zeit.snapshotFor(_year, monat);

      final live = buildZeitkontoSnapshot(
        orgId: user.orgId,
        userId: user.uid,
        jahr: _year,
        monat: monat,
        profiles: profiles,
        entries: entries,
        approvedAbsences: absences,
        previous: previous,
        ausgezahltMinutes: persisted?.ausgezahltMinutes ?? 0,
        plannedMinutes: plannedMinutesForMonth(
          shifts: monthShifts,
          userId: user.uid,
          jahr: _year,
          monat: monat,
        ),
      ).copyWith(createdAt: persisted?.createdAt);

      final draft = personal.buildDraftPayrollForMonth(
        userId: user.uid,
        year: _year,
        month: monat,
        istMinutes: live.istMinutes,
      );

      final validation = await zeit.closeMonth(
        liveSnapshot: live,
        monthEntries: entries,
        vormonat: previous,
        draftPayroll: draft,
        actorUid: user.uid,
        // ZV-5.2: offene Klärungsfälle des Monats blockieren den Abschluss.
        offeneKlaerungen:
            zeit.openKlaerungenCountForMonth(user.uid, DateTime(_year, monat)),
      );
      if (!mounted) return;
      if (!validation.canClose) {
        await _showValidation(validation, blocked: true);
      } else {
        await zeit.loadSnapshots(_year);
        if (validation.hasWarnings && mounted) {
          await _showValidation(validation, blocked: false);
        } else if (mounted) {
          // Hinweis, wenn kein Lohn-Entwurf erzeugt wurde (kein Festgehalt/
          // Stundensatz oder keine Stunden) — sonst wirkt der leere Lohnlauf
          // wie ein Fehler.
          _snack(draft == null
              ? '${_monthNames[monat - 1]} $_year abgeschlossen — kein '
                  'Lohn-Entwurf (kein Festgehalt/Stundensatz oder keine '
                  'erfassten Stunden).'
              : '${_monthNames[monat - 1]} $_year abgeschlossen.');
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reopen(ZeitkontoSnapshot snapshot) async {
    final zeit = context.read<ZeitwirtschaftProvider>();
    if (!(context.read<WorkProvider>().currentUser?.canManageShifts ?? false)) {
      return;
    }
    final confirmed = await AppConfirmDialog.show(
      context,
      title: '${_monthNames[snapshot.monat - 1]} ${snapshot.jahr} zurücknehmen?',
      message: 'Der Abschluss wird aufgehoben — Zeiteinträge werden wieder '
          'bearbeitbar.',
      confirmLabel: 'Zurücknehmen',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await zeit.reopenMonth(snapshot);
      await zeit.loadSnapshots(_year);
      if (mounted) {
        _snack('Abschluss ${_monthNames[snapshot.monat - 1]} ${snapshot.jahr} '
            'zurückgenommen.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showValidation(MonatsabschlussValidation v,
      {required bool blocked}) async {
    final appColors = Theme.of(context).appColors;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(blocked ? Icons.block : Icons.warning_amber,
            color: blocked ? Theme.of(ctx).colorScheme.error : appColors.warning),
        title: Text(blocked
            ? 'Abschluss nicht möglich'
            : 'Abgeschlossen — mit Hinweisen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in v.errors) Text('• $e'),
            if (v.errors.isNotEmpty && v.warnings.isNotEmpty)
              const SizedBox(height: 8),
            for (final w in v.warnings)
              Text('• $w',
                  style: TextStyle(color: appColors.warning)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

// ══════════════════════════════════════════════════════════════════════════════

enum _MonatStatus {
  zukuenftig,
  laufend,
  offen,
  bereit,
  abgeschlossen,
}

class _MonthTable extends StatelessWidget {
  const _MonthTable({
    required this.year,
    required this.snapshots,
    required this.canManage,
    required this.monthNames,
    required this.onClose,
    required this.onReopen,
  });

  final int year;
  final List<ZeitkontoSnapshot> snapshots;
  final bool canManage;
  final List<String> monthNames;
  final void Function(int monat)? onClose;
  final void Function(ZeitkontoSnapshot snapshot)? onReopen;

  ZeitkontoSnapshot? _forMonth(int monat) {
    for (final s in snapshots) {
      if (s.monat == monat) return s;
    }
    return null;
  }

  _MonatStatus _status(int monat, ZeitkontoSnapshot? snap) {
    final now = DateTime.now();
    if (year > now.year || (year == now.year && monat > now.month)) {
      return _MonatStatus.zukuenftig;
    }
    if (snap != null && snap.abgeschlossen) return _MonatStatus.abgeschlossen;
    if (year == now.year && monat == now.month) return _MonatStatus.laufend;
    if (snap != null) return _MonatStatus.bereit;
    return _MonatStatus.offen;
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: context.spacing.lg,
          columns: const [
            DataColumn(label: Text('Monat')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Ist'), numeric: true),
            DataColumn(label: Text('Saldo'), numeric: true),
            DataColumn(label: Text('Aktion')),
          ],
          rows: [
            for (var m = 1; m <= 12; m++) _row(context, m),
          ],
        ),
      ),
    );
  }

  DataRow _row(BuildContext context, int monat) {
    final theme = Theme.of(context);
    final appColors = theme.appColors;
    final snap = _forMonth(monat);
    final status = _status(monat, snap);

    final (color, label, icon) = switch (status) {
      _MonatStatus.zukuenftig => (
          theme.colorScheme.onSurfaceVariant,
          'Zukünftig',
          Icons.schedule,
        ),
      _MonatStatus.laufend => (appColors.info, 'Laufend', Icons.play_circle),
      _MonatStatus.offen => (
          appColors.warning,
          'Offen',
          Icons.pending_actions,
        ),
      _MonatStatus.bereit => (
          appColors.success,
          'Bereit',
          Icons.check_circle_outline,
        ),
      _MonatStatus.abgeschlossen => (appColors.success, 'Abgeschlossen', Icons.lock),
    };

    return DataRow(cells: [
      DataCell(Text(monthNames[monat - 1])),
      DataCell(_StatusBadge(color: color, label: label, icon: icon)),
      DataCell(Text(snap != null ? _h(snap.istHours) : '—')),
      DataCell(Text(
        snap != null ? _signed(snap.saldoHours) : '—',
        style: snap != null
            ? TextStyle(
                color: snap.saldoMinutes >= 0
                    ? appColors.success
                    : theme.colorScheme.error,
                fontWeight: FontWeight.w700)
            : null,
      )),
      DataCell(_actions(context, monat, snap, status)),
    ]);
  }

  Widget _actions(
    BuildContext context,
    int monat,
    ZeitkontoSnapshot? snap,
    _MonatStatus status,
  ) {
    if (!canManage) return const Text('—');
    final appColors = Theme.of(context).appColors;
    if (status == _MonatStatus.abgeschlossen && snap != null) {
      return IconButton(
        icon: Icon(Icons.lock_open, size: 18, color: appColors.warning),
        tooltip: 'Abschluss zurücknehmen',
        visualDensity: VisualDensity.compact,
        onPressed: onReopen == null ? null : () => onReopen!(snap),
      );
    }
    // Nur vergangene Monate sind abschließbar (der laufende Monat ist „Laufend").
    if (status == _MonatStatus.offen || status == _MonatStatus.bereit) {
      return IconButton(
        icon: Icon(Icons.lock_outline, size: 18, color: appColors.success),
        tooltip: 'Monat abschließen',
        visualDensity: VisualDensity.compact,
        onPressed: onClose == null ? null : () => onClose!(monat),
      );
    }
    return const Text('—');
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(
      {required this.color, required this.label, required this.icon});

  final Color color;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(context.radii.sm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

class _YearHeader extends StatelessWidget {
  const _YearHeader(
      {required this.year, required this.onPrevious, required this.onNext});

  final int year;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Vorheriges Jahr',
          onPressed: onPrevious,
        ),
        Expanded(
          child: Center(
            child: Text('$year',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Nächstes Jahr',
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
            child:
                Text(message, style: Theme.of(context).textTheme.bodySmall),
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
