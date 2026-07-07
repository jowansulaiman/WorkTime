import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/clock_service.dart';
import '../../core/dienst_abgleich.dart';
import '../../core/shift_punch_matcher.dart';
import '../../models/clock_entry.dart';
import '../../models/site_definition.dart';
import '../../providers/auth_provider.dart';
import '../../providers/team_provider.dart';
import '../../providers/work_provider.dart';
import '../../providers/zeitwirtschaft_provider.dart';
import '../../ui/ui.dart';

/// Kommen und Gehen (AllTec-1:1, M3b-2) — persistente Stempel-Sessions.
///
/// Timer-Karte (laufende Buchung, Live-Ticker), „Wer ist eingestempelt"-Karte
/// (Manager/Admin), Monatsliste der eigenen Buchungen. Ein-/Ausstempeln über den
/// FAB (grün „Kommen" / rot „Gehen"), Laden-Auswahl bei mehreren Standorten.
class StempelScreen extends StatefulWidget {
  const StempelScreen({super.key, this.parentLabel = 'Zeitwirtschaft'});

  final String parentLabel;

  @override
  State<StempelScreen> createState() => _StempelScreenState();
}

class _StempelScreenState extends State<StempelScreen>
    with WidgetsBindingObserver {
  Timer? _ticker;

  static final _monthFormat = DateFormat('MMMM yyyy', 'de_DE');
  static final _timeFormat = DateFormat('HH:mm', 'de_DE');
  static final _dateFormat = DateFormat('dd.MM.yyyy', 'de_DE');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Live-Ticker für die laufende Buchung (alle 30 s neu rendern).
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ZV-1.4: bei Rückkehr in den Vordergrund die Einmal-Read-Sichten
    // (Monatsbuchungen, Snapshots) neu laden — der zuverlässige Sync-Pfad auf
    // allen Plattformen (Skill 21; Streams heilen sich ohnehin selbst).
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<ZeitwirtschaftProvider>().refetch();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ZeitwirtschaftProvider>();
    final spacing = context.spacing;
    final isClockedIn = provider.isClockedIn;

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: widget.parentLabel,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const BreadcrumbItem(label: 'Kommen und Gehen'),
        ],
      ),
      floatingActionButton: _ClockFab(
        isClockedIn: isClockedIn,
        openSiteName: provider.openEntry?.siteName,
        onClockIn: _handleClockIn,
        onClockOut: _handleClockOut,
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                  spacing.md, spacing.md, spacing.md, spacing.xl + spacing.xxl),
              children: [
                _TimerCard(
                  openEntry: provider.openEntry,
                  runningMinutes: provider.runningMinutes(),
                  pending: provider.openEntryPending,
                ),
                if (provider.ongoingEntries.isNotEmpty) ...[
                  SizedBox(height: spacing.md),
                  _ActiveEmployeesCard(entries: provider.ongoingEntries),
                ],
                if (_canManage(context)) ...[
                  SizedBox(height: spacing.md),
                  const _DienstHeuteCard(),
                ],
                if (_canManage(context) &&
                    provider.klaerungEntries.isNotEmpty) ...[
                  SizedBox(height: spacing.md),
                  _KlaerungInboxCard(
                    entries: provider.klaerungEntries,
                    onResolve: (e) => _handleResolveKlaerung(e),
                    onDismiss: (e) => _handleDismissKlaerung(e),
                    timeFormat: _timeFormat,
                    dateFormat: _dateFormat,
                  ),
                ],
                SizedBox(height: spacing.lg),
                _MonthHeader(
                  label: _monthFormat.format(provider.selectedMonth),
                  onPrevious: () => _changeMonth(provider, -1),
                  onNext: () => _changeMonth(provider, 1),
                ),
                SizedBox(height: spacing.sm),
                if (provider.monthEntries.isEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: spacing.lg),
                    child: const AppEmptyState(
                      icon: Icons.timer_off_outlined,
                      message: 'Keine Stempelzeiten in diesem Monat.',
                    ),
                  )
                else
                  for (final e in provider.monthEntries) ...[
                    _MonthEntryTile(
                      entry: e,
                      timeFormat: _timeFormat,
                      dateFormat: _dateFormat,
                    ),
                    SizedBox(height: spacing.sm),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _changeMonth(ZeitwirtschaftProvider provider, int delta) {
    final m = provider.selectedMonth;
    provider.selectMonth(DateTime(m.year, m.month + delta));
  }

  Future<void> _handleClockIn() async {
    final provider = context.read<ZeitwirtschaftProvider>();
    final work = context.read<WorkProvider>();
    final sites = context.read<TeamProvider>().sites;

    // Z1/E1 (hart): Einstempeln nur innerhalb einer geplanten Schicht. Die
    // passende Schicht des Nutzers für „jetzt" wird aufgelöst und als `shiftId`
    // mitgegeben (fließt beim Ausstempeln in `sourceShiftId`); ohne Treffer wird
    // das Kommen verweigert.
    final now = DateTime.now();
    final userId = work.currentUser?.uid ?? '';
    final dayShifts = await work.loadConfirmedShiftsForDay(now);
    if (!mounted) return;
    final matched = matchShiftForPunch(dayShifts, now, userId: userId);
    if (matched == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Einstempeln nur innerhalb einer geplanten Schicht möglich '
            '(±15 Min. vor Beginn). Ohne passenden Dienst bitte an die '
            'Leitung wenden.',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    SiteDefinition? site;
    if (sites.length == 1) {
      site = sites.first;
    } else if (sites.length > 1) {
      site = await _pickSite(sites);
      if (!mounted) return;
      // Abgebrochen → nicht stempeln.
      if (site == null) return;
    }
    // Standort aus der Schicht vorbelegen, wenn keiner gewählt wurde.
    await provider.clockIn(
      siteId: site?.id ?? matched.siteId,
      siteName: site?.name ?? matched.siteName,
      shiftId: matched.id,
    );
  }

  Future<SiteDefinition?> _pickSite(List<SiteDefinition> sites) {
    return showModalBottomSheet<SiteDefinition>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.all(context.spacing.lg),
              child: Text('Laden auswählen',
                  style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            for (final site in sites)
              ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: Text(site.name),
                onTap: () => Navigator.of(sheetContext).pop(site),
              ),
            SizedBox(height: context.spacing.md),
          ],
        ),
      ),
    );
  }

  Future<void> _handleClockOut() async {
    final provider = context.read<ZeitwirtschaftProvider>();
    final result = await showModalBottomSheet<_ClockOutResult>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _ClockOutSheet(),
    );
    if (result == null || !mounted) return;
    await provider.clockOut(
      pauseMinuten: result.pauseMinuten,
      anmerkung: result.anmerkung,
    );
  }

  bool _canManage(BuildContext context) =>
      context.read<AuthProvider>().profile?.canManageShifts ?? false;

  Future<void> _handleResolveKlaerung(ClockEntry entry) async {
    final result = await showModalBottomSheet<_ResolveResult>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ResolveKlaerungSheet(entry: entry),
    );
    if (result == null || !mounted) return;
    final provider = context.read<ZeitwirtschaftProvider>();
    await provider.resolveKlaerung(
      entry,
      kommen: result.kommen,
      gehen: result.gehen,
      pauseMinuten: result.pauseMinuten,
      grund: result.grund,
    );
  }

  Future<void> _handleDismissKlaerung(ClockEntry entry) async {
    final grund = await _askGrund(
      title: 'Klärung verwerfen',
      hint: 'Grund (z. B. Doppelbuchung)',
    );
    if (grund == null || !mounted) return;
    await context.read<ZeitwirtschaftProvider>().dismissKlaerung(
          entry,
          grund: grund,
        );
  }

  Future<String?> _askGrund({required String title, required String hint}) {
    final controller = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          context.spacing.lg,
          context.spacing.md,
          context.spacing.lg,
          MediaQuery.of(sheetContext).viewInsets.bottom + context.spacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(sheetContext).textTheme.titleMedium),
            SizedBox(height: context.spacing.md),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: hint,
                border: const OutlineInputBorder(),
              ),
            ),
            SizedBox(height: context.spacing.md),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isEmpty) return;
                Navigator.of(sheetContext).pop(text);
              },
              child: const Text('Bestätigen'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClockFab extends StatelessWidget {
  const _ClockFab({
    required this.isClockedIn,
    required this.openSiteName,
    required this.onClockIn,
    required this.onClockOut,
  });

  final bool isClockedIn;
  final String? openSiteName;
  final VoidCallback onClockIn;
  final VoidCallback onClockOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = theme.appColors;
    if (isClockedIn) {
      return FloatingActionButton.extended(
        heroTag: 'clock_fab',
        backgroundColor: theme.colorScheme.error,
        foregroundColor: theme.colorScheme.onError,
        onPressed: onClockOut,
        icon: const Icon(Icons.logout),
        label: Text(openSiteName == null ? 'Gehen' : 'Gehen · $openSiteName'),
      );
    }
    return FloatingActionButton.extended(
      heroTag: 'clock_fab',
      backgroundColor: appColors.success,
      foregroundColor: Colors.white,
      onPressed: onClockIn,
      icon: const Icon(Icons.login),
      label: const Text('Kommen'),
    );
  }
}

class _TimerCard extends StatelessWidget {
  const _TimerCard({
    required this.openEntry,
    required this.runningMinutes,
    this.pending = false,
  });

  final ClockEntry? openEntry;
  final int runningMinutes;

  /// Offline gepufferter, noch nicht server-bestätigter Schreibvorgang (ZV-1.2).
  final bool pending;

  static final _timeFormat = DateFormat('HH:mm', 'de_DE');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = theme.appColors;
    final spacing = context.spacing;
    final entry = openEntry;

    if (entry == null) {
      return AppCard(
        child: Row(
          children: [
            Icon(Icons.timer_off_outlined,
                color: theme.colorScheme.onSurfaceVariant),
            SizedBox(width: spacing.md),
            Text('Nicht eingestempelt',
                style: theme.textTheme.titleMedium),
          ],
        ),
      );
    }

    final overLong = runningMinutes > ClockService.defaultMaxOngoingMinutes;
    // Voller Kalendertag-Vergleich (nicht nur .day) — sonst greift das Banner
    // an Monats-/Jahresgrenzen nicht; identisch zur Provider-Klärungslogik.
    final fromYesterday = ClockService.needsClarification(
      kommen: entry.kommen,
      now: DateTime.now(),
    );
    final quelle = switch (entry.source) {
      'kiosk' => 'Tablet',
      'app' => 'App',
      _ => null,
    };
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timer, color: appColors.success),
              SizedBox(width: spacing.md),
              Expanded(
                child: Text(
                  'Eingestempelt seit ${_timeFormat.format(entry.kommen)}'
                  '${entry.siteName != null ? ' · ${entry.siteName}' : ''}'
                  '${quelle != null ? ' · $quelle' : ''}',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (pending) ...[
                SizedBox(width: spacing.sm),
                _PendingBadge(),
              ],
            ],
          ),
          SizedBox(height: spacing.sm),
          Text(
            _formatDuration(runningMinutes),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (overLong || fromYesterday) ...[
            SizedBox(height: spacing.md),
            _WarningBanner(
              message: overLong
                  ? 'Diese Buchung läuft seit über 10 Stunden. Das Ausstempeln wird als bestätigte Ausnahme gespeichert.'
                  : 'Eine Buchung vom Vortag läuft noch – bitte zur Klärung ausstempeln.',
            ),
          ],
        ],
      ),
    );
  }
}

/// „ausstehend"-Badge für optimistische, noch nicht server-bestätigte Writes
/// (ZV-1.2, Skill-21-Transparenz).
class _PendingBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.appColors.warning;
    final spacing = context.spacing;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: spacing.sm, vertical: spacing.xxs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(context.radii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sync, size: 13, color: color),
          SizedBox(width: spacing.xxs),
          Text('ausstehend',
              style: theme.textTheme.labelSmall?.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.appColors.warning;
    return Container(
      padding: EdgeInsets.all(context.spacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(context.radii.md),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: color, size: 18),
          SizedBox(width: context.spacing.sm),
          Expanded(
            child: Text(message, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _ActiveEmployeesCard extends StatelessWidget {
  const _ActiveEmployeesCard({required this.entries});

  final List<ClockEntry> entries;

  static final _timeFormat = DateFormat('HH:mm', 'de_DE');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = context.spacing;
    final sorted = [...entries]..sort((a, b) => a.kommen.compareTo(b.kommen));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.groups_outlined, color: theme.colorScheme.primary),
              SizedBox(width: spacing.sm),
              Text('Aktuell eingestempelt (${sorted.length})',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          SizedBox(height: spacing.sm),
          for (final e in sorted)
            Padding(
              padding: EdgeInsets.symmetric(vertical: spacing.xxs),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor:
                        theme.colorScheme.primaryContainer.withValues(alpha: 0.7),
                    child: Text(
                      _initials(e.userName),
                      style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onPrimaryContainer),
                    ),
                  ),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    child: Text(e.userName ?? 'Mitarbeiter',
                        style: theme.textTheme.bodyMedium),
                  ),
                  Text('seit ${_timeFormat.format(e.kommen)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _initials(String? name) {
    final trimmed = (name ?? '').trim();
    if (trimmed.isEmpty) return '–';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.label,
    required this.onPrevious,
    required this.onNext,
  });

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

class _MonthEntryTile extends StatelessWidget {
  const _MonthEntryTile({
    required this.entry,
    required this.timeFormat,
    required this.dateFormat,
  });

  final ClockEntry entry;
  final DateFormat timeFormat;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = theme.appColors;
    final color = switch (entry.status) {
      ClockStatus.completed => appColors.success,
      ClockStatus.ongoing => appColors.info,
      ClockStatus.klaerung => appColors.warning,
      ClockStatus.deaktiviert => theme.colorScheme.onSurfaceVariant,
    };
    final timeRange = entry.gehen == null
        ? '${timeFormat.format(entry.kommen)} – läuft'
        : '${timeFormat.format(entry.kommen)} – ${timeFormat.format(entry.gehen!)}';
    final hours = entry.isOngoing
        ? null
        : '${(entry.nettoMinutes / 60).toStringAsFixed(1)} h';

    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dateFormat.format(entry.kommen),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                SizedBox(height: context.spacing.xxs),
                Text(
                  '$timeRange${entry.siteName != null ? ' · ${entry.siteName}' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (hours != null)
            Padding(
              padding: EdgeInsets.only(right: context.spacing.sm),
              child: Text(hours,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(context.radii.sm),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Text(entry.status.label,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return '${h}h ${m.toString().padLeft(2, '0')}min';
}

class _ClockOutResult {
  const _ClockOutResult({this.pauseMinuten, this.anmerkung});
  final int? pauseMinuten;
  final String? anmerkung;
}

class _ClockOutSheet extends StatefulWidget {
  const _ClockOutSheet();

  @override
  State<_ClockOutSheet> createState() => _ClockOutSheetState();
}

class _ClockOutSheetState extends State<_ClockOutSheet> {
  // Leer = automatische Pflichtpause (ArbZG) gemäß Hilfetext; eine feste „30"
  // würde bei kurzen Schichten (<6 h) fälschlich 30 min abziehen.
  final TextEditingController _pauseCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _pauseCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        spacing.lg,
        spacing.sm,
        spacing.lg,
        spacing.lg + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Ausstempeln',
              style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: spacing.md),
          TextField(
            controller: _pauseCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Pause (Minuten)',
              prefixIcon: Icon(Icons.free_breakfast_outlined),
              helperText: 'Leer lassen für automatische Pflichtpause',
            ),
          ),
          SizedBox(height: spacing.md),
          TextField(
            controller: _noteCtrl,
            decoration: const InputDecoration(
              labelText: 'Anmerkung (optional)',
              prefixIcon: Icon(Icons.note_outlined),
            ),
            maxLines: 2,
          ),
          SizedBox(height: spacing.lg),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () {
              final raw = _pauseCtrl.text.trim();
              final pause = raw.isEmpty ? null : int.tryParse(raw);
              final note = _noteCtrl.text.trim();
              Navigator.of(context).pop(_ClockOutResult(
                pauseMinuten: pause,
                anmerkung: note.isEmpty ? null : note,
              ));
            },
            icon: const Icon(Icons.logout),
            label: const Text('Ausstempeln'),
          ),
        ],
      ),
    );
  }
}

// ── Klärungs-Inbox (ZV-3.1) ──────────────────────────────────────────────────
class _KlaerungInboxCard extends StatelessWidget {
  const _KlaerungInboxCard({
    required this.entries,
    required this.onResolve,
    required this.onDismiss,
    required this.timeFormat,
    required this.dateFormat,
  });

  final List<ClockEntry> entries;
  final void Function(ClockEntry) onResolve;
  final void Function(ClockEntry) onDismiss;
  final DateFormat timeFormat;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = context.spacing;
    final warning = theme.appColors.warning;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.help_outline, color: warning),
              SizedBox(width: spacing.sm),
              Expanded(
                child: Text('Klärung offen (${entries.length})',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          SizedBox(height: spacing.xs),
          Text(
            'Vergessene oder unklare Stempelungen. Bitte korrigieren, damit die '
            'Stunden im Monat vollständig sind.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          SizedBox(height: spacing.sm),
          for (final e in entries) ...[
            const Divider(height: 1),
            Padding(
              padding: EdgeInsets.symmetric(vertical: spacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${e.userName ?? 'Mitarbeiter'} · '
                    '${dateFormat.format(e.kommen)} ab '
                    '${timeFormat.format(e.kommen)}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (e.anmerkung != null && e.anmerkung!.isNotEmpty)
                    Text(e.anmerkung!,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  SizedBox(height: spacing.xs),
                  Row(
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () => onResolve(e),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Korrigieren'),
                      ),
                      SizedBox(width: spacing.sm),
                      TextButton.icon(
                        onPressed: () => onDismiss(e),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Verwerfen'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResolveResult {
  const _ResolveResult({
    required this.kommen,
    required this.gehen,
    required this.grund,
    this.pauseMinuten,
  });

  final DateTime kommen;
  final DateTime gehen;
  final String grund;
  final int? pauseMinuten;
}

/// Sheet zum Auflösen eines Klärungsfalls (ZV-3.1): korrekte Zeiten + Grund.
class _ResolveKlaerungSheet extends StatefulWidget {
  const _ResolveKlaerungSheet({required this.entry});

  final ClockEntry entry;

  @override
  State<_ResolveKlaerungSheet> createState() => _ResolveKlaerungSheetState();
}

class _ResolveKlaerungSheetState extends State<_ResolveKlaerungSheet> {
  late DateTime _kommen;
  late DateTime _gehen;
  final _pauseCtrl = TextEditingController();
  final _grundCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _kommen = widget.entry.kommen;
    // Vorschlag Gehen: bestehendes Gehen, sonst Kommen + 8 h (Manager passt an).
    _gehen = widget.entry.gehen ?? _kommen.add(const Duration(hours: 8));
  }

  @override
  void dispose() {
    _pauseCtrl.dispose();
    _grundCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool istKommen) async {
    final base = istKommen ? _kommen : _gehen;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
    );
    if (picked == null) return;
    setState(() {
      final next =
          DateTime(base.year, base.month, base.day, picked.hour, picked.minute);
      if (istKommen) {
        _kommen = next;
      } else {
        _gehen = next;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = context.spacing;
    final fmt = DateFormat('dd.MM.yyyy HH:mm', 'de_DE');
    final valid = _gehen.isAfter(_kommen) && _grundCtrl.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        spacing.lg,
        spacing.md,
        spacing.lg,
        MediaQuery.of(context).viewInsets.bottom + spacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Klärung korrigieren', style: theme.textTheme.titleMedium),
          SizedBox(height: spacing.md),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.login),
            title: const Text('Kommen'),
            subtitle: Text(fmt.format(_kommen)),
            trailing: TextButton(
                onPressed: () => _pickTime(true), child: const Text('Ändern')),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout),
            title: const Text('Gehen'),
            subtitle: Text(fmt.format(_gehen)),
            trailing: TextButton(
                onPressed: () => _pickTime(false), child: const Text('Ändern')),
          ),
          if (!_gehen.isAfter(_kommen))
            Text('Gehen muss nach Kommen liegen.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error)),
          SizedBox(height: spacing.sm),
          TextField(
            controller: _pauseCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Pause (Minuten)',
              helperText: 'Leer = automatische Pflichtpause',
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(height: spacing.md),
          TextField(
            controller: _grundCtrl,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Grund der Korrektur *',
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(height: spacing.lg),
          FilledButton.icon(
            onPressed: valid
                ? () {
                    final raw = _pauseCtrl.text.trim();
                    Navigator.of(context).pop(_ResolveResult(
                      kommen: _kommen,
                      gehen: _gehen,
                      pauseMinuten: raw.isEmpty ? null : int.tryParse(raw),
                      grund: _grundCtrl.text.trim(),
                    ));
                  }
                : null,
            icon: const Icon(Icons.check),
            label: const Text('Korrektur speichern'),
          ),
        ],
      ),
    );
  }
}

// ── Dienst heute (ZV-2.2b) ───────────────────────────────────────────────────
/// Manager-Tagessicht: Soll-Ist aus geplanten Schichten vs. Stempelungen
/// (verspätet / nicht erschienen / früher / ungeplant). Lädt einmalig + per
/// Refresh; org-weit via [ZeitwirtschaftProvider.loadDienstHeute].
class _DienstHeuteCard extends StatefulWidget {
  const _DienstHeuteCard();

  @override
  State<_DienstHeuteCard> createState() => _DienstHeuteCardState();
}

class _DienstHeuteCardState extends State<_DienstHeuteCard> {
  Future<List<DienstAbgleich>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = context.read<ZeitwirtschaftProvider>().loadDienstHeute();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = context.spacing;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.today_outlined, color: theme.colorScheme.primary),
              SizedBox(width: spacing.sm),
              Expanded(
                child: Text('Dienst heute',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: 'Aktualisieren',
                onPressed: () => setState(_load),
              ),
            ],
          ),
          SizedBox(height: spacing.xs),
          FutureBuilder<List<DienstAbgleich>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: spacing.md),
                  child: const Center(
                      child: CircularProgressIndicator.adaptive()),
                );
              }
              final all = snapshot.data ?? const <DienstAbgleich>[];
              // Offen/entschuldigt sind kein Handlungsbedarf → nur Auffällige +
              // Pünktliche zeigen; ganz leere Tage bekommen einen Hinweis.
              final rows = all
                  .where((d) =>
                      d.status != DienstStatus.offen &&
                      d.status != DienstStatus.abwesendEntschuldigt)
                  .toList();
              if (rows.isEmpty) {
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: spacing.xs),
                  child: Text('Keine Auffälligkeiten für heute.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                );
              }
              return Column(
                children: [
                  for (final d in rows) _DienstHeuteRow(entry: d),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DienstHeuteRow extends StatelessWidget {
  const _DienstHeuteRow({required this.entry});

  final DienstAbgleich entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = theme.appColors;
    final spacing = context.spacing;
    final (color, label) = switch (entry.status) {
      DienstStatus.puenktlich => (appColors.success, 'Pünktlich'),
      DienstStatus.verspaetet => (
          appColors.warning,
          'Verspätet · ${entry.abweichungMinuten} min'
        ),
      DienstStatus.frueherGegangen => (
          appColors.warning,
          'Früher · ${entry.abweichungMinuten} min'
        ),
      DienstStatus.nichtErschienen => (theme.colorScheme.error, 'Nicht erschienen'),
      DienstStatus.ungeplantAnwesend => (appColors.info, 'Ungeplant'),
      _ => (theme.colorScheme.onSurfaceVariant, entry.status.label),
    };
    return Padding(
      padding: EdgeInsets.symmetric(vertical: spacing.xxs),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: spacing.sm),
          Expanded(
            child: Text(entry.userName ?? 'Mitarbeiter',
                style: theme.textTheme.bodyMedium),
          ),
          Text(label,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
