import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_logger.dart';
import '../../core/zeitkonto_snapshot_builder.dart';
import '../../models/app_user.dart';
import '../../models/work_entry.dart';
import '../../models/zeitkonto_snapshot.dart';
import '../../providers/personal_provider.dart';
import '../../providers/work_provider.dart';
import '../../providers/zeitwirtschaft_provider.dart';
import '../../routing/shell_tab.dart';
import '../../ui/ui.dart';

/// Mitarbeiterabschluss-Hub (AllTec `AdminMonthClosingHubPage`, M5) — Admin-Sicht
/// **org-weit**: alle aktiven Mitarbeiter eines Abrechnungsmonats mit Status,
/// KPIs, Filter und Aktionen (offene Zeiteinträge prüfen, abschließen,
/// zurücknehmen, Auszahlung, Batch-Abschluss).
///
/// Liest org-weit über den [ZeitwirtschaftProvider] (eigene Lese-Helfer, durch
/// `firestore.rules` `canManageShifts` abgesichert), da [WorkProvider.entries]
/// self-gefiltert ist. Der Abschluss schreibt je MA einen gesperrten
/// [ZeitkontoSnapshot] + einen Entwurfs-Lohndatensatz.
class MitarbeiterabschlussScreen extends StatefulWidget {
  const MitarbeiterabschlussScreen(
      {super.key, this.parentLabel = 'Zeitwirtschaft'});

  final String parentLabel;

  @override
  State<MitarbeiterabschlussScreen> createState() =>
      _MitarbeiterabschlussScreenState();
}

class _MitarbeiterabschlussScreenState
    extends State<MitarbeiterabschlussScreen> {
  static const _monthNames = [
    'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
    'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
  ];

  late int _year;
  late int _month;
  bool _loading = true;
  List<_MitarbeiterMonat> _rows = const [];
  final Set<String> _busy = <String>{};

  final _searchCtrl = TextEditingController();
  String _search = '';
  bool _onlyOpen = false;
  bool _onlyClosed = false;
  bool _onlyWarnings = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _changeMonth(int delta) {
    var y = _year;
    var m = _month + delta;
    if (m < 1) {
      m = 12;
      y -= 1;
    } else if (m > 12) {
      m = 1;
      y += 1;
    }
    setState(() {
      _year = y;
      _month = m;
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final work = context.read<WorkProvider>();
      final zeit = context.read<ZeitwirtschaftProvider>();
      final personal = context.read<PersonalProvider>();
      final user = work.currentUser;
      if (user == null) {
        if (mounted) setState(() => _rows = const []);
        return;
      }

      final monthDate = DateTime(_year, _month);
      final entries = await zeit.loadOrgWorkEntriesForMonth(monthDate);
      final absences = await zeit.loadOrgApprovedAbsencesForMonth(monthDate);
      final snaps = await zeit.loadOrgSnapshotsForMonth(_year, _month);
      final prevMonth = _month == 1 ? 12 : _month - 1;
      final prevYear = _month == 1 ? _year - 1 : _year;
      final prevSnaps =
          await zeit.loadOrgSnapshotsForMonth(prevYear, prevMonth);

      final members = personal.members.where((m) => m.isActive).toList()
        ..sort((a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

      final rows = <_MitarbeiterMonat>[];
      for (final m in members) {
        final mEntries = entries.where((e) => e.userId == m.uid).toList();
        final mAbs = absences.where((a) => a.userId == m.uid).toList();
        final profiles = personal.sollzeitProfilesForUser(m.uid);
        final persisted = snaps.firstWhereOrNull((s) => s.userId == m.uid);
        final prev = prevSnaps.firstWhereOrNull((s) => s.userId == m.uid);

        final live = buildZeitkontoSnapshot(
          orgId: user.orgId,
          userId: m.uid,
          jahr: _year,
          monat: _month,
          profiles: profiles,
          entries: mEntries,
          approvedAbsences: mAbs,
          previous: prev,
          ausgezahltMinutes: persisted?.ausgezahltMinutes ?? 0,
        ).copyWith(createdAt: persisted?.createdAt);

        final open = mEntries
            .where((e) =>
                e.status == WorkEntryStatus.draft ||
                e.status == WorkEntryStatus.submitted)
            .toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

        rows.add(_MitarbeiterMonat(
          member: m,
          persisted: persisted,
          vormonat: prev,
          live: live,
          openEntries: open,
          hasSoll: profiles.isNotEmpty,
          hasPayroll:
              personal.payrollForUserPeriod(m.uid, _year, _month) != null,
        ));
      }

      if (mounted) setState(() => _rows = rows);
    } catch (error) {
      AppLogger.warning('Mitarbeiterabschluss: Laden fehlgeschlagen',
          error: error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_MitarbeiterMonat> get _filtered {
    final q = _search.trim().toLowerCase();
    return _rows.where((r) {
      if (q.isNotEmpty && !r.member.displayName.toLowerCase().contains(q)) {
        return false;
      }
      if (_onlyOpen && r.isLocked) return false;
      if (_onlyClosed && !r.isLocked) return false;
      if (_onlyWarnings && !r.hasOpenEntries && !r.hasWarnings) return false;
      return true;
    }).toList();
  }

  /// Nur **vollständig vergangene** Kalendermonate sind abschließbar — der
  /// laufende (unvollständige) Monat ist „Laufend", wie in der Self-Sicht.
  bool _isCompletedMonth() {
    final now = DateTime.now();
    return _year < now.year || (_year == now.year && _month < now.month);
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final closedCount = _rows.where((r) => r.isLocked).length;
    final payrollCount = _rows.where((r) => r.hasPayroll).length;

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: widget.parentLabel,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const BreadcrumbItem(label: 'Mitarbeiterabschluss'),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                  spacing.md, spacing.md, spacing.md, spacing.xl),
              children: [
                _MonthPicker(
                  label: '${_monthNames[_month - 1]} $_year',
                  onPrevious: () => _changeMonth(-1),
                  onNext: () => _changeMonth(1),
                  onToday: () {
                    final now = DateTime.now();
                    setState(() {
                      _year = now.year;
                      _month = now.month;
                    });
                    _load();
                  },
                ),
                SizedBox(height: spacing.md),
                _KpiRow(
                  total: _rows.length,
                  open: _rows.length - closedCount,
                  closed: closedCount,
                  payroll: payrollCount,
                ),
                SizedBox(height: spacing.md),
                _Filters(
                  controller: _searchCtrl,
                  onlyOpen: _onlyOpen,
                  onlyClosed: _onlyClosed,
                  onlyWarnings: _onlyWarnings,
                  onSearch: (v) => setState(() => _search = v),
                  onToggleOpen: (v) => setState(() {
                    _onlyOpen = v;
                    if (v) _onlyClosed = false;
                  }),
                  onToggleClosed: (v) => setState(() {
                    _onlyClosed = v;
                    if (v) _onlyOpen = false;
                  }),
                  onToggleWarnings: (v) => setState(() => _onlyWarnings = v),
                ),
                SizedBox(height: spacing.md),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator.adaptive()),
                  )
                else if (_filtered.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(spacing.lg),
                    child: AppEmptyState(
                      icon: Icons.groups_outlined,
                      message: _rows.isEmpty
                          ? 'Keine aktiven Mitarbeiter gefunden.'
                          : 'Keine Mitarbeiter im aktuellen Filter.',
                    ),
                  )
                else
                  for (final row in _filtered) ...[
                    _MemberCard(
                      row: row,
                      busy: _busy.contains(row.member.uid),
                      completed: _isCompletedMonth(),
                      onReview: () => _review(row),
                      onClose: () => _close(row),
                      onReopen: () => _reopen(row),
                      onPayout: () => _payout(row),
                    ),
                    SizedBox(height: spacing.sm),
                  ],
                SizedBox(height: spacing.md),
                _BatchActions(
                  canCloseAny: _isCompletedMonth() &&
                      _rows.any((r) => r.isCloseable),
                  onCloseAll: _closeAll,
                  onLohnlauf: () => context.push(AppRoutes.zeitLohnlauf),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Aktionen ────────────────────────────────────────────────────────────────
  Future<void> _review(_MitarbeiterMonat row) async {
    final work = context.read<WorkProvider>();
    await showAppBottomSheet<void>(
      context: context,
      builder: (_) => _OffeneEintraegeSheet(
        memberName: row.member.displayName,
        entries: row.openEntries,
        onApprove: (e) => work.approveWorkEntry(e),
        onReject: (e, reason) => work.rejectWorkEntry(e, reason: reason),
      ),
    );
    await _load();
  }

  Future<void> _close(_MitarbeiterMonat row) async {
    final work = context.read<WorkProvider>();
    final zeit = context.read<ZeitwirtschaftProvider>();
    final personal = context.read<PersonalProvider>();
    final actor = work.currentUser?.uid;

    final confirmed = await AppConfirmDialog.show(
      context,
      title: '${row.member.displayName} abschließen?',
      message:
          '${_monthNames[_month - 1]} $_year wird gesperrt und eine '
          'Lohnabrechnung als Entwurf erzeugt. Zeiteinträge werden für den '
          'Mitarbeiter gesperrt.',
      confirmLabel: 'Abschließen',
      destructive: false,
      icon: Icons.lock_outline,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy.add(row.member.uid));
    try {
      // Einträge frisch laden (nicht den `_load`-Stand) — zwischen Laden und
      // Abschluss könnte ein neuer offener Eintrag entstanden sein, den die
      // Validierung sonst nicht sähe.
      final fresh = (await zeit.loadOrgWorkEntriesForMonth(DateTime(_year, _month)))
          .where((e) => e.userId == row.member.uid)
          .toList();
      final draft = personal.buildDraftPayrollForMonth(
        userId: row.member.uid,
        year: _year,
        month: _month,
        istMinutes: row.live.istMinutes,
      );
      final validation = await zeit.closeMonth(
        liveSnapshot: row.live,
        monthEntries: fresh,
        vormonat: row.vormonat,
        draftPayroll: draft,
        actorUid: actor,
        // ZV-5.2: offene Klärungsfälle des MA blockieren den Abschluss.
        offeneKlaerungen: zeit.openKlaerungenCountForMonth(
            row.member.uid, DateTime(_year, _month)),
      );
      if (!mounted) return;
      if (!validation.canClose) {
        await _showErrors(validation.errors);
      } else if (draft == null) {
        // Abschluss ok, aber kein Lohn-Entwurf erzeugt → sonst bliebe der
        // Lohnlauf für diesen MA still leer, ohne dass der Grund sichtbar ist.
        _snack('${row.member.displayName}: abgeschlossen, aber kein '
            'Lohn-Entwurf — kein Festgehalt/Stundensatz im Vertrag oder keine '
            'erfassten Stunden im Monat.');
      }
    } finally {
      if (mounted) setState(() => _busy.remove(row.member.uid));
    }
    await _load();
  }

  Future<void> _reopen(_MitarbeiterMonat row) async {
    final zeit = context.read<ZeitwirtschaftProvider>();
    final persisted = row.persisted;
    if (persisted == null) return;
    final confirmed = await AppConfirmDialog.show(
      context,
      title: '${row.member.displayName} zurücknehmen?',
      message: 'Der Abschluss für ${_monthNames[_month - 1]} $_year wird '
          'aufgehoben — Zeiteinträge werden wieder bearbeitbar.',
      confirmLabel: 'Zurücknehmen',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy.add(row.member.uid));
    try {
      await zeit.reopenMonth(persisted);
    } finally {
      if (mounted) setState(() => _busy.remove(row.member.uid));
    }
    await _load();
  }

  Future<void> _payout(_MitarbeiterMonat row) async {
    final zeit = context.read<ZeitwirtschaftProvider>();
    final base = row.persisted ?? row.live;
    final result = await showAppBottomSheet<int>(
      context: context,
      builder: (_) => _AuszahlungSheet(
        memberName: row.member.displayName,
        ueberstundenMinutes: base.ueberstundenMinutes,
        aktuellAusgezahltMinutes: base.ausgezahltMinutes,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _busy.add(row.member.uid));
    try {
      // Saldo neu = Übertrag + Überstunden − Auszahlung.
      final neuerSaldo =
          base.uebertragMinutes + base.ueberstundenMinutes - result;
      await zeit.saveSnapshot(base.copyWith(
        ausgezahltMinutes: result,
        saldoMinutes: neuerSaldo,
      ));
    } finally {
      if (mounted) setState(() => _busy.remove(row.member.uid));
    }
    await _load();
  }

  Future<void> _closeAll() async {
    final zeit = context.read<ZeitwirtschaftProvider>();
    final personal = context.read<PersonalProvider>();
    final actor = context.read<WorkProvider>().currentUser?.uid;
    final targets = _rows.where((r) => r.isCloseable).toList();
    if (targets.isEmpty) return;
    final confirmed = await AppConfirmDialog.show(
      context,
      title: 'Batch-Abschluss',
      message:
          '${targets.length} abschließbare Mitarbeiter für '
          '${_monthNames[_month - 1]} $_year werden abgeschlossen und deren '
          'Lohnabrechnungen als Entwürfe erzeugt. Fortfahren?',
      confirmLabel: 'Alle abschließen',
      destructive: false,
    );
    if (!confirmed || !mounted) return;
    setState(() => _loading = true);
    // Einträge einmal frisch laden (statt des `_load`-Stands), damit die
    // Validierung pro MA neue offene Einträge erkennt.
    final allEntries =
        await zeit.loadOrgWorkEntriesForMonth(DateTime(_year, _month));
    final blocked = <String>[];
    final noDraft = <String>[];
    for (final row in targets) {
      final fresh =
          allEntries.where((e) => e.userId == row.member.uid).toList();
      final draft = personal.buildDraftPayrollForMonth(
        userId: row.member.uid,
        year: _year,
        month: _month,
        istMinutes: row.live.istMinutes,
      );
      final validation = await zeit.closeMonth(
        liveSnapshot: row.live,
        monthEntries: fresh,
        vormonat: row.vormonat,
        draftPayroll: draft,
        actorUid: actor,
        // ZV-5.2: offene Klärungsfälle blockieren auch den Sammelabschluss.
        offeneKlaerungen: zeit.openKlaerungenCountForMonth(
            row.member.uid, DateTime(_year, _month)),
      );
      if (!validation.canClose) {
        blocked.add('${row.member.displayName}: ${validation.errors.join(', ')}');
      } else if (draft == null) {
        noDraft.add(row.member.displayName);
      }
    }
    await _load();
    if (!mounted) return;
    if (blocked.isNotEmpty) {
      await _showErrors([
        'Nicht alle Monate konnten abgeschlossen werden:',
        ...blocked,
      ]);
    }
    // Abgeschlossen, aber ohne Lohn-Entwurf → sichtbar machen, sonst bleibt der
    // Lohnlauf für diese MA still leer.
    if (mounted && noDraft.isNotEmpty) {
      _snack('Abgeschlossen, aber ohne Lohn-Entwurf (kein Festgehalt/Stundensatz '
          'oder keine erfassten Stunden): ${noDraft.join(', ')}');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showErrors(List<String> errors) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.block, color: Theme.of(ctx).colorScheme.error),
        title: const Text('Abschluss nicht möglich'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final e in errors) Text('• $e')],
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
}

// ══════════════════════════════════════════════════════════════════════════════
//  Datenmodell
// ══════════════════════════════════════════════════════════════════════════════

class _MitarbeiterMonat {
  const _MitarbeiterMonat({
    required this.member,
    required this.persisted,
    required this.vormonat,
    required this.live,
    required this.openEntries,
    required this.hasSoll,
    required this.hasPayroll,
  });

  final AppUserProfile member;
  final ZeitkontoSnapshot? persisted;
  final ZeitkontoSnapshot? vormonat;
  final ZeitkontoSnapshot live;
  final List<WorkEntry> openEntries;
  final bool hasSoll;
  final bool hasPayroll;

  bool get isLocked => persisted?.abgeschlossen ?? false;
  bool get hasOpenEntries => openEntries.isNotEmpty;
  bool get hasWarnings =>
      (live.istMinutes == 0 && live.sollMinutes > 0) || live.kranktage > 20;

  /// Abschließbar: nicht gesperrt, keine offenen Einträge.
  bool get isCloseable => !isLocked && openEntries.isEmpty;
}

// ══════════════════════════════════════════════════════════════════════════════
//  UI-Bausteine
// ══════════════════════════════════════════════════════════════════════════════

class _MonthPicker extends StatelessWidget {
  const _MonthPicker({
    required this.label,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;

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
          TextButton.icon(
            onPressed: onToday,
            icon: const Icon(Icons.today, size: 18),
            label: const Text('Heute'),
          ),
        ],
      ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({
    required this.total,
    required this.open,
    required this.closed,
    required this.payroll,
  });

  final int total;
  final int open;
  final int closed;
  final int payroll;

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).appColors;
    final spacing = context.spacing.sm;
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 640 ? 4 : 2;
      final tileWidth = (constraints.maxWidth - spacing * (columns - 1)) / columns;
      final items = [
        (_kpiData('Mitarbeiter', '$total', Icons.people_alt, appColors.info)),
        (_kpiData('Offen', '$open', Icons.pending_actions, appColors.warning)),
        (_kpiData('Abgeschlossen', '$closed', Icons.lock, appColors.success)),
        (_kpiData('Lohn-Entwürfe', '$payroll / $total', Icons.receipt_long,
            Theme.of(context).colorScheme.primary)),
      ];
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final it in items)
            SizedBox(width: tileWidth, child: it),
        ],
      );
    });
  }

  Widget _kpiData(String title, String value, IconData icon, Color color) {
    return Builder(builder: (context) {
      final theme = Theme.of(context);
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 6),
            Text(value,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            Text(title,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    });
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.controller,
    required this.onlyOpen,
    required this.onlyClosed,
    required this.onlyWarnings,
    required this.onSearch,
    required this.onToggleOpen,
    required this.onToggleClosed,
    required this.onToggleWarnings,
  });

  final TextEditingController controller;
  final bool onlyOpen;
  final bool onlyClosed;
  final bool onlyWarnings;
  final ValueChanged<String> onSearch;
  final ValueChanged<bool> onToggleOpen;
  final ValueChanged<bool> onToggleClosed;
  final ValueChanged<bool> onToggleWarnings;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: context.spacing.sm,
      runSpacing: context.spacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 260,
          child: TextField(
            controller: controller,
            onChanged: onSearch,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Name suchen…',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        FilterChip(
          label: const Text('Nur offene'),
          selected: onlyOpen,
          onSelected: onToggleOpen,
        ),
        FilterChip(
          label: const Text('Nur abgeschlossene'),
          selected: onlyClosed,
          onSelected: onToggleClosed,
        ),
        FilterChip(
          label: const Text('Mit Hinweisen'),
          selected: onlyWarnings,
          onSelected: onToggleWarnings,
        ),
      ],
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.row,
    required this.busy,
    required this.completed,
    required this.onReview,
    required this.onClose,
    required this.onReopen,
    required this.onPayout,
  });

  final _MitarbeiterMonat row;
  final bool busy;
  final bool completed;
  final VoidCallback onReview;
  final VoidCallback onClose;
  final VoidCallback onReopen;
  final VoidCallback onPayout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = theme.appColors;
    final live = row.live;

    final (statusColor, statusLabel, statusIcon) = row.isLocked
        ? (appColors.success, 'Abgeschlossen', Icons.lock)
        : row.hasOpenEntries
            ? (appColors.warning, 'Offene Einträge', Icons.warning_amber)
            : (appColors.info, 'Bereit', Icons.check_circle_outline);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor:
                    theme.colorScheme.secondaryContainer,
                child: Text(
                  _initials(row.member.displayName),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSecondaryContainer),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(row.member.displayName,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              _StatusBadge(
                  color: statusColor, label: statusLabel, icon: statusIcon),
            ],
          ),
          SizedBox(height: context.spacing.sm),
          Wrap(
            spacing: context.spacing.sm,
            runSpacing: 4,
            children: [
              _StatChip(label: 'Ist', value: _h(live.istHours)),
              _StatChip(
                  label: 'Soll',
                  value: row.hasSoll ? _h(live.sollHours) : '—'),
              _StatChip(
                label: 'Überstunden',
                value: row.hasSoll ? _signed(live.ueberstundenHours) : '—',
                color: row.hasSoll
                    ? (live.ueberstundenMinutes >= 0
                        ? appColors.success
                        : theme.colorScheme.error)
                    : null,
              ),
              if (row.hasOpenEntries)
                _StatChip(
                    label: 'Offen',
                    value: '${row.openEntries.length}',
                    color: appColors.warning),
              if (row.persisted != null && row.persisted!.ausgezahltMinutes > 0)
                _StatChip(
                    label: 'Ausbezahlt',
                    value: _h(row.persisted!.ausgezahltHours)),
            ],
          ),
          SizedBox(height: context.spacing.sm),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            Wrap(
              spacing: context.spacing.sm,
              children: [
                if (row.hasOpenEntries)
                  OutlinedButton.icon(
                    onPressed: onReview,
                    icon: const Icon(Icons.fact_check, size: 18),
                    label: Text('Prüfen (${row.openEntries.length})'),
                  ),
                if (row.isLocked)
                  OutlinedButton.icon(
                    onPressed: onReopen,
                    icon: const Icon(Icons.lock_open, size: 18),
                    label: const Text('Zurücknehmen'),
                  )
                else if (completed && row.isCloseable)
                  FilledButton.tonalIcon(
                    onPressed: onClose,
                    icon: const Icon(Icons.lock_outline, size: 18),
                    label: const Text('Abschließen'),
                  ),
                if (row.persisted != null)
                  TextButton.icon(
                    onPressed: onPayout,
                    icon: const Icon(Icons.payments, size: 18),
                    label: const Text('Auszahlung'),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}

class _BatchActions extends StatelessWidget {
  const _BatchActions({
    required this.canCloseAny,
    required this.onCloseAll,
    required this.onLohnlauf,
  });

  final bool canCloseAny;
  final VoidCallback onCloseAll;
  final VoidCallback onLohnlauf;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: context.spacing.sm,
      runSpacing: context.spacing.sm,
      children: [
        FilledButton.tonalIcon(
          onPressed: canCloseAny ? onCloseAll : null,
          icon: const Icon(Icons.lock_outline),
          label: const Text('Alle abschließbaren schließen'),
        ),
        OutlinedButton.icon(
          onPressed: onLohnlauf,
          icon: const Icon(Icons.payments),
          label: const Text('Zum Lohnlauf'),
        ),
      ],
    );
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

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Text.rich(TextSpan(
        text: '$label: ',
        style: TextStyle(fontSize: 11, color: c),
        children: [
          TextSpan(
            text: value,
            style: TextStyle(
                fontSize: 11, color: c, fontWeight: FontWeight.w700),
          ),
        ],
      )),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Sub-Sheets
// ══════════════════════════════════════════════════════════════════════════════

class _OffeneEintraegeSheet extends StatefulWidget {
  const _OffeneEintraegeSheet({
    required this.memberName,
    required this.entries,
    required this.onApprove,
    required this.onReject,
  });

  final String memberName;
  final List<WorkEntry> entries;
  final Future<void> Function(WorkEntry entry) onApprove;
  final Future<void> Function(WorkEntry entry, String? reason) onReject;

  @override
  State<_OffeneEintraegeSheet> createState() => _OffeneEintraegeSheetState();
}

class _OffeneEintraegeSheetState extends State<_OffeneEintraegeSheet> {
  late List<WorkEntry> _entries;
  final Set<String> _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _entries = List.of(widget.entries);
  }

  Future<void> _approve(WorkEntry e) async {
    final id = e.id;
    if (id == null) return;
    setState(() => _busy.add(id));
    await widget.onApprove(e);
    if (!mounted) return;
    setState(() {
      _entries.removeWhere((x) => x.id == id);
      _busy.remove(id);
    });
  }

  Future<void> _reject(WorkEntry e) async {
    final id = e.id;
    if (id == null) return;
    final reason = await _askReason();
    if (reason == null || !mounted) return;
    setState(() => _busy.add(id));
    await widget.onReject(e, reason.isEmpty ? null : reason);
    if (!mounted) return;
    setState(() {
      _entries.removeWhere((x) => x.id == id);
      _busy.remove(id);
    });
  }

  Future<String?> _askReason() async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ablehnen'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Grund (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Ablehnen'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return reason;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppBottomSheetScaffold(
      title: 'Offene Zeiteinträge — ${widget.memberName}',
      child: _entries.isEmpty
          ? Padding(
              padding: EdgeInsets.all(context.spacing.lg),
              child: const AppEmptyState(
                icon: Icons.task_alt,
                message: 'Keine offenen Einträge mehr.',
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final e in _entries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${_date(e.date)} · ${e.workedHours.toStringAsFixed(1)} h',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${_time(e.startTime)}–${_time(e.endTime)}'
                      '${e.siteName != null ? ' · ${e.siteName}' : ''}'
                      ' · ${e.status.label}',
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: _busy.contains(e.id)
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.check,
                                    color: theme.appColors.success),
                                tooltip: 'Genehmigen',
                                onPressed: () => _approve(e),
                              ),
                              IconButton(
                                icon: Icon(Icons.close,
                                    color: theme.colorScheme.error),
                                tooltip: 'Ablehnen',
                                onPressed: () => _reject(e),
                              ),
                            ],
                          ),
                  ),
              ],
            ),
    );
  }

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.';
  String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _AuszahlungSheet extends StatefulWidget {
  const _AuszahlungSheet({
    required this.memberName,
    required this.ueberstundenMinutes,
    required this.aktuellAusgezahltMinutes,
  });

  final String memberName;
  final int ueberstundenMinutes;
  final int aktuellAusgezahltMinutes;

  @override
  State<_AuszahlungSheet> createState() => _AuszahlungSheetState();
}

class _AuszahlungSheetState extends State<_AuszahlungSheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
        text: (widget.aktuellAusgezahltMinutes / 60).toStringAsFixed(2));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ueber = widget.ueberstundenMinutes / 60.0;
    return AppBottomSheetScaffold(
      title: 'Auszahlung — ${widget.memberName}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Überstunden im Monat: ${_signed(ueber)}',
              style: theme.textTheme.bodyMedium),
          SizedBox(height: context.spacing.md),
          TextField(
            controller: _ctrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Auszahlung (Stunden)',
              border: OutlineInputBorder(),
              suffixText: 'h',
            ),
          ),
          SizedBox(height: context.spacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () {
                final hours =
                    double.tryParse(_ctrl.text.trim().replaceAll(',', '.')) ??
                        0;
                final minutes = (hours * 60).round();
                Navigator.of(context).pop(minutes < 0 ? 0 : minutes);
              },
              child: const Text('Speichern'),
            ),
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
