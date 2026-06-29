import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/clock_service.dart';
import '../../models/clock_entry.dart';
import '../../models/site_definition.dart';
import '../../providers/team_provider.dart';
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

class _StempelScreenState extends State<StempelScreen> {
  Timer? _ticker;

  static final _monthFormat = DateFormat('MMMM yyyy', 'de_DE');
  static final _timeFormat = DateFormat('HH:mm', 'de_DE');
  static final _dateFormat = DateFormat('dd.MM.yyyy', 'de_DE');

  @override
  void initState() {
    super.initState();
    // Live-Ticker für die laufende Buchung (alle 30 s neu rendern).
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
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
                ),
                if (provider.ongoingEntries.isNotEmpty) ...[
                  SizedBox(height: spacing.md),
                  _ActiveEmployeesCard(entries: provider.ongoingEntries),
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
    final sites = context.read<TeamProvider>().sites;
    SiteDefinition? site;
    if (sites.length == 1) {
      site = sites.first;
    } else if (sites.length > 1) {
      site = await _pickSite(sites);
      if (!mounted) return;
      // Abgebrochen → nicht stempeln.
      if (site == null) return;
    }
    await provider.clockIn(siteId: site?.id, siteName: site?.name);
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
  const _TimerCard({required this.openEntry, required this.runningMinutes});

  final ClockEntry? openEntry;
  final int runningMinutes;

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
                  '${entry.siteName != null ? ' · ${entry.siteName}' : ''}',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
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
