// Teil von home_screen.dart (split-home-screen-god-file, Strangler Schritt 3).
//
// Die drei großen Tab-Feature-Bäume der Shell samt ihrer Sub-Widgets:
// Employee-Dashboard (Stempeluhr/Wochenfortschritt/Abwesenheiten),
// Admin-Dashboard (Team-Kalender) und Time-Tracking (Punch-Clock-Flow,
// Slide-to-Clock, Standort-Status). Als 'part' gehalten: die enge
// Provider-/file-private-Kopplung zur Hauptdatei bleibt unveraendert und es
// werden keine Imports dupliziert.
part of 'home_screen.dart';


class _EmployeeDashboardTab extends StatelessWidget {
  const _EmployeeDashboardTab({
    required this.canNavigateBack,
    this.onNavigateBack,
  });

  final bool canNavigateBack;
  final VoidCallback? onNavigateBack;

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AuthProvider>().profile;
    final work = context.watch<WorkProvider>();
    final schedule = context.watch<ScheduleProvider>();
    final canViewSchedule = currentUser?.canViewSchedule ?? false;
    final canViewWorkEntries = (currentUser?.canViewTimeTracking ?? false) ||
        (currentUser?.canViewReports ?? false);
    final canEditTimeEntries = currentUser?.canEditTimeEntries ?? false;
    final upcomingShifts = canViewSchedule
        ? (schedule.upcomingShiftsForCurrentUser()
          ..sort((a, b) => a.startTime.compareTo(b.startTime)))
        : <Shift>[];
    final ownAbsences = schedule.allAbsenceRequests
        .where((request) =>
            currentUser == null || request.userId == currentUser.uid)
        .toList(growable: false);
    final pendingAbsences =
        ownAbsences.where((r) => r.status == AbsenceStatus.pending).toList();
    final nextShift = upcomingShifts.isEmpty ? null : upcomingShifts.first;
    final recentEntries = canViewWorkEntries
        ? (work.entries.toList()
          ..sort((a, b) => b.startTime.compareTo(a.startTime)))
        : <WorkEntry>[];
    final pendingSwapCount =
        upcomingShifts.where((shift) => shift.swapStatus == 'pending').length;

    final screenPad = MobileBreakpoints.screenPadding(context);
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: screenPad.horizontal / 2,
              vertical: 16,
            ),
            children: [
              SectionHeader(
                title: 'Heute',
                subtitle:
                    'Naechste Schicht, Arbeitszeit und offene Aufgaben ohne Umwege.',
                breadcrumbs: const [BreadcrumbItem(label: 'Heute')],
                onBack: canNavigateBack ? onNavigateBack : null,
              ),
              const SizedBox(height: 20),
              _EmployeeHeroCard(
                nextShift: nextShift,
                provider: work,
              ),
              const SizedBox(height: 16),
              const DashboardActionItemsCard(parentLabel: 'Heute'),
              AdaptiveCardGrid(
                minItemWidth: 180,
                children: [
                  _QuickActionCard(
                    icon: Icons.local_hospital_outlined,
                    title: 'Krank melden',
                    subtitle: 'Heute oder morgen direkt absenden',
                    onTap: () => showAbsenceRequestSheet(
                      context,
                      defaultType: AbsenceType.sickness,
                      initialStart: DateTime.now(),
                      initialEnd: DateTime.now(),
                    ),
                  ),
                  _QuickActionCard(
                    icon: Icons.beach_access_outlined,
                    title: 'Urlaub anfragen',
                    subtitle: 'Antrag ohne Umweg stellen',
                    onTap: () => showAbsenceRequestSheet(
                      context,
                      defaultType: AbsenceType.vacation,
                      initialStart: DateTime.now(),
                      initialEnd: DateTime.now(),
                    ),
                  ),
                  if (canEditTimeEntries)
                    _QuickActionCard(
                      icon: Icons.edit_calendar_outlined,
                      title: 'Zeit erfassen',
                      subtitle: 'Manuellen Eintrag anlegen oder korrigieren',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const EntryFormScreen(
                            parentLabel: 'Heute',
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (canViewSchedule)
                _EmployeeWeekStrip(
                  upcomingShifts: upcomingShifts,
                  absences: ownAbsences,
                ),
              const SizedBox(height: 16),
              if (pendingAbsences.isNotEmpty || pendingSwapCount > 0)
                SectionCard(
                  title: 'Offene Aufgaben',
                  child: Column(
                    children: [
                      if (pendingAbsences.isNotEmpty)
                        _ActionStateTile(
                          icon: Icons.pending_actions,
                          title:
                              '${pendingAbsences.length} Abwesenheitsantraege offen',
                          subtitle:
                              'Deine Antraege sind eingereicht und warten auf Rueckmeldung.',
                          color: Theme.of(context).colorScheme.tertiary,
                        ),
                      if (pendingAbsences.isNotEmpty && pendingSwapCount > 0)
                        const Divider(height: 20),
                      if (pendingSwapCount > 0)
                        _ActionStateTile(
                          icon: Icons.swap_horiz,
                          title:
                              '$pendingSwapCount Tausch-Anfragen in Bearbeitung',
                          subtitle:
                              'Sobald entschieden wurde, erscheint die Rueckmeldung in Anfragen.',
                          color: Theme.of(context).colorScheme.primary,
                        ),
                    ],
                  ),
                ),
              if (pendingAbsences.isNotEmpty || pendingSwapCount > 0)
                const SizedBox(height: 16),
              _ClockInOutWidget(provider: work),
              const SizedBox(height: 20),
              _WeeklyProgressWidget(provider: work),
              const SizedBox(height: 16),
              _MonthlyShiftSummaryCards(provider: work),
              if (pendingAbsences.isNotEmpty) ...[
                const SizedBox(height: 16),
                _PendingAbsencesWidget(absences: pendingAbsences),
              ],
              const SizedBox(height: 20),
              SectionCard(
                title: 'Naechste Schichten',
                child: upcomingShifts.isEmpty
                    ? const _EmptyState(
                        icon: Icons.event_busy_outlined,
                        text:
                            'Keine kommenden Schichten im aktuell geladenen Zeitraum.',
                      )
                    : Column(
                        children: upcomingShifts.take(5).map((shift) {
                          return _ShiftPreviewTile(
                            shift: shift,
                            onTap: () => _showShiftDetailsSheet(
                              context,
                              shift: shift,
                              isPlanner: false,
                            ),
                          );
                        }).toList(),
                      ),
              ),
              const SizedBox(height: 20),
              SectionCard(
                title: 'Letzte Eintraege',
                child: recentEntries.isEmpty
                    ? const _EmptyState(
                        icon: Icons.inbox_outlined,
                        text: 'Noch keine Arbeitszeiteintraege vorhanden.',
                      )
                    : Column(
                        children: recentEntries.take(5).map((entry) {
                          return _RecentEntryTile(entry: entry);
                        }).toList(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClockInOutWidget extends StatelessWidget {
  const _ClockInOutWidget({required this.provider});

  final WorkProvider provider;

  @override
  Widget build(BuildContext context) {
    final team = context.watch<TeamProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = theme.appColors;
    final isClockedIn = provider.hasActiveClockSession;
    final durationLabel =
        _formatClockDuration(provider.effectiveClockedDuration);
    final primaryAssignment =
        _resolvePrimaryAssignment(team, provider.currentUser?.uid);
    final primarySite = _resolvePrimarySite(
      team.sites.isNotEmpty ? team.sites : provider.sites,
      primaryAssignment,
    );
    final activeShift = provider.activeShiftNow;
    final lastClockEntry = _resolveLastClockEntry(provider.entries);
    final canStartClock = primaryAssignment != null && activeShift != null;
    final canUseClock = isClockedIn || canStartClock;
    final startLabel = provider.effectiveClockStartTime != null
        ? DateFormat('HH:mm', 'de_DE').format(provider.effectiveClockStartTime!)
        : lastClockEntry == null
            ? '--:--'
            : DateFormat('HH:mm', 'de_DE').format(lastClockEntry.startTime);
    final endLabel = isClockedIn
        ? '--:--'
        : lastClockEntry == null
            ? '--:--'
            : DateFormat('HH:mm', 'de_DE').format(lastClockEntry.endTime);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isClockedIn
                        ? appColors.successContainer
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    isClockedIn ? Icons.timer : Icons.timer_outlined,
                    size: 28,
                    color: isClockedIn
                        ? appColors.success
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Stempeluhr',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        primarySite?.name ??
                            primaryAssignment?.siteName ??
                            'Kein Standort hinterlegt',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isClockedIn
                          ? appColors.successContainer
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      isClockedIn
                          ? (provider.isClockBackedByEntry
                              ? 'Aus Eintrag aktiv'
                              : 'Im Dienst')
                          : 'Nicht aktiv',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: isClockedIn
                                ? appColors.onSuccessContainer
                                : colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _ClockStatTile(
                    label: 'BEGINN',
                    time: startLabel,
                    icon: Icons.login_rounded,
                    color: appColors.success,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ClockStatTile(
                    label: 'ENDE',
                    time: endLabel,
                    icon: Icons.logout_rounded,
                    color: colorScheme.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isClockedIn
                    ? appColors.successContainer.withValues(alpha: 0.84)
                    : colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.75,
                      ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    durationLabel,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatClockBreakLabel(provider, lastClockEntry),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (!isClockedIn &&
                primaryAssignment != null &&
                activeShift == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  'Check-in ist nur waehrend einer laufenden Schicht moeglich.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: !canUseClock
                        ? null
                        : () => _handlePunchClockAction(context, provider),
                    icon: Icon(isClockedIn ? Icons.stop : Icons.play_arrow),
                    label: Text(isClockedIn ? 'Ausstempeln' : 'Einstempeln'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor:
                          isClockedIn ? colorScheme.error : appColors.success,
                      foregroundColor: isClockedIn
                          ? colorScheme.onError
                          : appColors.onSuccess,
                    ),
                  ),
                ),
                if (!isClockedIn && _hasRecentClockEntry(provider)) ...[
                  const SizedBox(width: 10),
                  Flexible(
                    child: OutlinedButton.icon(
                      onPressed: () => _showCorrectionDialog(context, provider),
                      icon: const Icon(Icons.edit_note, size: 18),
                      label: const Text(
                        'Korrigieren',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 52),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (!canUseClock) ...[
              const SizedBox(height: 12),
              Text(
                'Zum Einstempeln ist ein Primaerstandort erforderlich.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _hasRecentClockEntry(WorkProvider provider) {
    return provider.entries.any((e) => e.note?.contains('Stempeluhr') ?? false);
  }

  Future<void> _showCorrectionDialog(
    BuildContext context,
    WorkProvider provider,
  ) async {
    final clockEntries = provider.entries
        .where((e) => e.note?.contains('Stempeluhr') ?? false)
        .toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
    if (clockEntries.isEmpty) return;
    final entry = clockEntries.first;

    final result = await showDialog<_ClockCorrectionResult>(
      context: context,
      builder: (_) => _ClockCorrectionDialog(entry: entry),
    );
    if (result == null || !context.mounted) return;

    try {
      await provider.correctClockEntry(
        entryId: entry.id!,
        correctedStart: result.start,
        correctedEnd: result.end,
        reason: result.reason,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Eintrag korrigiert')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}

class _ClockCorrectionResult {
  const _ClockCorrectionResult({
    required this.start,
    required this.end,
    required this.reason,
  });
  final DateTime start;
  final DateTime end;
  final String reason;
}

class _ClockCorrectionDialog extends StatefulWidget {
  const _ClockCorrectionDialog({required this.entry});
  final WorkEntry entry;

  @override
  State<_ClockCorrectionDialog> createState() => _ClockCorrectionDialogState();
}

class _ClockCorrectionDialogState extends State<_ClockCorrectionDialog> {
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  final _reasonCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _startTime = TimeOfDay.fromDateTime(widget.entry.startTime);
    _endTime = TimeOfDay.fromDateTime(widget.entry.endTime);
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd.MM.yyyy', 'de_DE');
    return AlertDialog(
      title: const Text('Stempeluhr-Eintrag korrigieren'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Datum: ${dateFmt.format(widget.entry.date)}'),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.login),
              title: const Text('Start'),
              // Ganze Zeile antippbar (größeres Tap-Ziel als nur der Button).
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: _startTime,
                );
                if (picked != null) setState(() => _startTime = picked);
              },
              trailing: TextButton(
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: _startTime,
                  );
                  if (picked != null) setState(() => _startTime = picked);
                },
                child: Text(_startTime.format(context)),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.logout),
              title: const Text('Ende'),
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: _endTime,
                );
                if (picked != null) setState(() => _endTime = picked);
              },
              trailing: TextButton(
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: _endTime,
                  );
                  if (picked != null) setState(() => _endTime = picked);
                },
                child: Text(_endTime.format(context)),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Begruendung (Pflicht)',
                prefixIcon: Icon(Icons.comment_outlined),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            if (_reasonCtrl.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Bitte Begruendung angeben'),
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
              );
              return;
            }
            final date = widget.entry.date;
            final start = DateTime(
              date.year,
              date.month,
              date.day,
              _startTime.hour,
              _startTime.minute,
            );
            var end = DateTime(
              date.year,
              date.month,
              date.day,
              _endTime.hour,
              _endTime.minute,
            );
            // Über Mitternacht laufende Schicht: liegt die Endzeit nicht nach
            // der Startzeit, gehört sie auf den Folgetag.
            if (!end.isAfter(start)) {
              end = end.add(const Duration(days: 1));
            }
            Navigator.of(context).pop(_ClockCorrectionResult(
              start: start,
              end: end,
              reason: _reasonCtrl.text.trim(),
            ));
          },
          child: const Text('Korrigieren'),
        ),
      ],
    );
  }
}

class _WeeklyProgressWidget extends StatefulWidget {
  const _WeeklyProgressWidget({required this.provider});

  final WorkProvider provider;

  @override
  State<_WeeklyProgressWidget> createState() => _WeeklyProgressWidgetState();
}

class _WeeklyProgressWidgetState extends State<_WeeklyProgressWidget> {
  Future<_WeeklyShiftProgressData>? _future;
  String? _futureKey;

  void _refreshFuture() {
    final provider = widget.provider;
    final user = provider.currentUser;
    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final nextKey =
        '${user?.orgId}:${user?.uid}:${weekStart.toIso8601String()}';
    if (_futureKey == nextKey && _future != null) {
      return;
    }
    _futureKey = nextKey;
    _future = _loadWeeklyProgress(provider, weekStart);
  }

  Future<_WeeklyShiftProgressData> _loadWeeklyProgress(
    WorkProvider provider,
    DateTime weekStart,
  ) async {
    final weekEnd = weekStart.add(const Duration(days: 7));
    final results = await Future.wait<Object>([
      provider.loadShiftsForRange(
        start: weekStart,
        end: weekEnd,
      ),
      provider.loadEntriesForRange(
        start: weekStart,
        end: weekEnd,
      ),
    ]);

    final shifts = results[0] as List<Shift>;
    final entries = results[1] as List<WorkEntry>;
    final shiftIds = shifts
        .where((shift) => shift.id != null)
        .map((shift) => shift.id!)
        .toSet();
    final linkedEntries = entries.where((entry) {
      final shiftId = entry.sourceShiftId?.trim();
      return shiftId != null && shiftIds.contains(shiftId);
    }).length;

    return _WeeklyShiftProgressData(
      plannedHours: _sumShiftHours(shifts),
      actualHours: _sumEntryHours(entries),
      shiftCount: shifts.length,
      linkedEntryCount: linkedEntries,
    );
  }

  @override
  Widget build(BuildContext context) {
    _refreshFuture();
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).appColors;
    final fallbackTarget = widget.provider.settings.dailyHours * 5;

    return FutureBuilder<_WeeklyShiftProgressData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final weeklyTarget = data == null || data.plannedHours <= 0
            ? fallbackTarget
            : data.plannedHours;
        final weeklyHours = data?.actualHours ?? 0;
        final progress = weeklyTarget > 0
            ? (weeklyHours / weeklyTarget).clamp(0.0, 1.0)
            : 0.0;
        final diff = weeklyHours - weeklyTarget;
        final diffColor = diff >= 0 ? appColors.success : colorScheme.error;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.date_range,
                        color: colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Wochenfortschritt',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${weeklyHours.toStringAsFixed(1)} / ${weeklyTarget.toStringAsFixed(1)} h',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    color: progress >= 1.0
                        ? appColors.success
                        : colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    InfoChip(
                      icon: Icons.schedule_outlined,
                      label: data == null || data.shiftCount == 0
                          ? 'Kein Schichtplan'
                          : '${data.shiftCount} ${data.shiftCount == 1 ? 'Schicht' : 'Schichten'}',
                    ),
                    InfoChip(
                      icon: Icons.link_rounded,
                      label: data == null || data.linkedEntryCount == 0
                          ? 'Noch nicht verknuepft'
                          : '${data.linkedEntryCount} verknuepft',
                    ),
                    InfoChip(
                      icon: diff >= 0
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded,
                      label: _formatSignedHours(diff),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  data == null || data.plannedHours <= 0
                      ? 'Kein geplanter Wochenrahmen vorhanden. Fallback auf Sollstunden aus den Einstellungen.'
                      : 'Soll aus ${data.shiftCount} geplanten Schichten, Ist aus erfassten Arbeitszeiten.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    minHeight: 3,
                    backgroundColor: Colors.transparent,
                    color: diffColor.withValues(alpha: 0.65),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _WeeklyShiftProgressData {
  const _WeeklyShiftProgressData({
    required this.plannedHours,
    required this.actualHours,
    required this.shiftCount,
    required this.linkedEntryCount,
  });

  final double plannedHours;
  final double actualHours;
  final int shiftCount;
  final int linkedEntryCount;
}

class _PendingAbsencesWidget extends StatelessWidget {
  const _PendingAbsencesWidget({required this.absences});

  final List<AbsenceRequest> absences;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateFmt = DateFormat('dd.MM.yyyy', 'de_DE');

    return Card(
      color: colorScheme.tertiaryContainer.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.pending_actions, color: colorScheme.tertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Offene Abwesenheitsantraege (${absences.length})',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...absences.take(3).map((absence) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        absence.type == AbsenceType.vacation
                            ? Icons.beach_access
                            : absence.type == AbsenceType.sickness
                                ? Icons.local_hospital
                                : Icons.block,
                        size: 18,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${absence.type.label}: '
                          '${dateFmt.format(absence.startDate)} - ${dateFmt.format(absence.endDate)}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.tertiary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          absence.status.label,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: colorScheme.tertiary,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _AdminDashboardTab extends StatelessWidget {
  const _AdminDashboardTab({
    required this.onOpenPlan,
    required this.onOpenPlanForDate,
    required this.canNavigateBack,
    this.onNavigateBack,
  });

  final Future<void> Function() onOpenPlan;
  final Future<void> Function(DateTime focusDate) onOpenPlanForDate;
  final bool canNavigateBack;
  final VoidCallback? onNavigateBack;

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AuthProvider>().profile;
    final team = context.watch<TeamProvider>();
    final schedule = context.watch<ScheduleProvider>();
    final activeMembers =
        team.members.where((member) => member.isActive).length;
    final pendingAbsences = schedule.allAbsenceRequests
        .where((request) => request.status == AbsenceStatus.pending)
        .toList(growable: false);
    final pendingSwapRequests = schedule.shifts
        .where((shift) => shift.swapStatus == 'pending')
        .toList(growable: false);
    final upcomingShifts = [...schedule.shifts]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final todayStart = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final todayEnd = todayStart.add(const Duration(days: 1));
    final todayShifts = schedule.shifts.where((shift) {
      return !shift.startTime.isBefore(todayStart) &&
          shift.startTime.isBefore(todayEnd);
    }).toList(growable: false)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final unassignedToday = todayShifts.where((shift) => shift.isUnassigned);
    final completedToday = todayShifts
        .where((shift) => shift.status == ShiftStatus.completed)
        .length;
    final openToday = todayShifts
        .where((shift) =>
            shift.status != ShiftStatus.completed &&
            shift.status != ShiftStatus.cancelled &&
            !shift.isUnassigned)
        .length;
    final todaySites = todayShifts
        .map((shift) => shift.effectiveSiteLabel)
        .whereType<String>();

    final screenPad = MobileBreakpoints.screenPadding(context);
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1160),
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: screenPad.horizontal / 2,
              vertical: 16,
            ),
            children: [
              SectionHeader(
                title: 'Heute',
                subtitle:
                    'Filialbetrieb, Ausnahmen und Entscheidungen fuer den laufenden Tag.',
                breadcrumbs: const [BreadcrumbItem(label: 'Heute')],
                onBack: canNavigateBack ? onNavigateBack : null,
              ),
              const SizedBox(height: 20),
              _PlannerHeroCard(
                activeMembers: activeMembers,
                todayShiftCount: todayShifts.length,
                pendingAbsenceCount: pendingAbsences.length,
                pendingSwapCount: pendingSwapRequests.length,
                siteCount: todaySites.toSet().length,
              ),
              const SizedBox(height: 16),
              const DashboardActionItemsCard(parentLabel: 'Heute'),
              AdaptiveCardGrid(
                minItemWidth: 180,
                children: [
                  _QuickActionCard(
                    icon: Icons.view_timeline_outlined,
                    title: 'Plan oeffnen',
                    subtitle: 'Direkt in die mobile Tagesplanung springen',
                    onTap: onOpenPlan,
                  ),
                  if (currentUser?.isAdmin ?? false)
                    _QuickActionCard(
                      icon: Icons.badge_outlined,
                      title: 'Personal verwalten',
                      subtitle:
                          'Mitarbeiter, Rollen, Standorte und Organisation',
                      onTap: () => context.push(AppRoutes.personal),
                    ),
                  _QuickActionCard(
                    icon: Icons.inbox_outlined,
                    title: 'Anfragen pruefen',
                    subtitle:
                        'Krankmeldungen und Tausch ohne Umwege entscheiden',
                    // Tab-Ziel -> go (Branch wechseln), nicht push (kein Duplikat).
                    onTap: () => context.go(shellTabPaths[ShellTab.inbox]!),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AdaptiveCardGrid(
                minItemWidth: 155,
                children: [
                  _DashboardMetricCard(
                    label: 'Aktive Mitarbeiter',
                    value: '$activeMembers',
                    icon: Icons.people_alt_outlined,
                  ),
                  _DashboardMetricCard(
                    label: 'Offene Einladungen',
                    value: '${team.invites.length}',
                    icon: Icons.mark_email_unread_outlined,
                  ),
                  _DashboardMetricCard(
                    label: 'Schichten heute',
                    value: '${todayShifts.length}',
                    icon: Icons.view_timeline_outlined,
                  ),
                  _DashboardMetricCard(
                    label: 'Erledigt',
                    value: '$completedToday / ${todayShifts.length}',
                    icon: Icons.check_circle_outline,
                  ),
                  _DashboardMetricCard(
                    label: 'Noch offen',
                    value: '$openToday',
                    icon: Icons.pending_actions_outlined,
                  ),
                  _DashboardMetricCard(
                    label: 'Offene Abwesenheiten',
                    value: '${pendingAbsences.length}',
                    icon: Icons.event_note_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SectionCard(
                title: 'Heute priorisieren',
                child: Column(
                  children: [
                    _ActionStateTile(
                      icon: Icons.warning_amber_rounded,
                      title:
                          '${pendingAbsences.length + pendingSwapRequests.length} Entscheidungen offen',
                      subtitle:
                          'Abwesenheiten und Tauschanfragen sollten vor der naechsten Schicht geklaert werden.',
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                    const Divider(height: 20),
                    _ActionStateTile(
                      icon: Icons.person_off_outlined,
                      title:
                          '${unassignedToday.length} freie oder unbesetzte Schichten',
                      subtitle:
                          'Nicht zugewiesene Dienste fallen im Tagesbetrieb sofort auf.',
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SectionCard(
                title: 'Naechste Schichten',
                child: upcomingShifts.isEmpty
                    ? const _EmptyState(
                        icon: Icons.event_busy_outlined,
                        text: 'Keine Schichten im aktuellen Planungsfenster.',
                      )
                    : Column(
                        children: upcomingShifts.take(8).map((shift) {
                          return _ShiftPreviewTile(
                            shift: shift,
                            onTap: () => _showShiftDetailsSheet(
                              context,
                              shift: shift,
                              isPlanner: true,
                              onOpenPlanForDate: onOpenPlanForDate,
                            ),
                          );
                        }).toList(),
                      ),
              ),
              const SizedBox(height: 20),
              SectionCard(
                title: 'Naechste Entscheidungen',
                child: _ManagerDecisionList(
                  pendingAbsences: pendingAbsences,
                  pendingSwapRequests: pendingSwapRequests,
                ),
              ),
              const SizedBox(height: 20),
              _TeamCalendarWidget(
                members: team.members.where((m) => m.isActive).toList(),
                shifts: schedule.shifts,
                absences: schedule.absenceRequests,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamCalendarWidget extends StatefulWidget {
  const _TeamCalendarWidget({
    required this.members,
    required this.shifts,
    required this.absences,
  });

  final List<AppUserProfile> members;
  final List<Shift> shifts;
  final List<AbsenceRequest> absences;

  @override
  State<_TeamCalendarWidget> createState() => _TeamCalendarWidgetState();
}

class _TeamCalendarWidgetState extends State<_TeamCalendarWidget> {
  late DateTime _weekStart;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    final today = _startOfDay(DateTime.now());
    _weekStart = _startOfWeek(today);
    _selectedDay = today;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final today = _startOfDay(DateTime.now());
    final members = [...widget.members]
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final days =
        List.generate(7, (index) => _weekStart.add(Duration(days: index)));
    final dayKeys = days.map(_dayKey).toSet();
    final shiftsByUserDay = <String, List<Shift>>{};
    final absencesByUserDay = <String, List<AbsenceRequest>>{};

    for (final shift in widget.shifts) {
      final shiftDay = _startOfDay(shift.startTime);
      final keyPart = _dayKey(shiftDay);
      if (!dayKeys.contains(keyPart)) {
        continue;
      }
      final key = _userDayKey(shift.userId, shiftDay);
      (shiftsByUserDay[key] ??= <Shift>[]).add(shift);
    }

    for (final entries in shiftsByUserDay.values) {
      entries.sort((a, b) => a.startTime.compareTo(b.startTime));
    }

    for (final absence in widget.absences) {
      if (absence.status != AbsenceStatus.approved) {
        continue;
      }
      for (final day in days) {
        final dayStart = _startOfDay(day);
        final dayEnd = dayStart.add(const Duration(days: 1));
        if (!absence.overlaps(dayStart, dayEnd)) {
          continue;
        }
        final key = _userDayKey(absence.userId, dayStart);
        (absencesByUserDay[key] ??= <AbsenceRequest>[]).add(absence);
      }
    }

    final selectedDayStart = _startOfDay(_selectedDay);
    final selectedShifts = widget.shifts
        .where((shift) => _isSameDay(shift.startTime, selectedDayStart))
        .toList(growable: false)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final selectedAbsences = widget.absences
        .where((absence) =>
            absence.status == AbsenceStatus.approved &&
            absence.overlaps(
              selectedDayStart,
              selectedDayStart.add(const Duration(days: 1)),
            ))
        .toList(growable: false)
      ..sort((a, b) => a.employeeName.compareTo(b.employeeName));
    final onDutyMemberCount =
        selectedShifts.map((shift) => shift.userId).toSet().length;
    final absentMemberCount =
        selectedAbsences.map((absence) => absence.userId).toSet().length;
    final freeMemberCount = members.where((member) {
      final snapshot = _snapshotFor(
        member.uid,
        selectedDayStart,
        shiftsByUserDay,
        absencesByUserDay,
      );
      return snapshot.status == _TeamDayStatus.free;
    }).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_month, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Team-Kalender',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  tooltip: 'Vorherige Woche',
                  onPressed: () => _moveWeek(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                TextButton(
                  onPressed: _goToCurrentWeek,
                  child: const Text('Diese Woche'),
                ),
                IconButton(
                  tooltip: 'Naechste Woche',
                  onPressed: () => _moveWeek(1),
                  icon: const Icon(Icons.chevron_right),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _formatWeekLabel(days.first, days.last),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _TeamCalendarMetricPill(
                  icon: Icons.schedule_outlined,
                  label: '$onDutyMemberCount im Dienst',
                  color: colorScheme.primary,
                ),
                _TeamCalendarMetricPill(
                  icon: Icons.event_busy_outlined,
                  label: '$absentMemberCount abwesend',
                  color: colorScheme.tertiary,
                ),
                _TeamCalendarMetricPill(
                  icon: Icons.check_circle_outline,
                  label: '$freeMemberCount frei',
                  color: colorScheme.secondary,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _TeamCalendarMetricPill(
                  icon: Icons.badge_outlined,
                  label: 'Schicht',
                  color: colorScheme.primary,
                  compact: true,
                ),
                _TeamCalendarMetricPill(
                  icon: Icons.beach_access,
                  label: 'Urlaub',
                  color: colorScheme.tertiary,
                  compact: true,
                ),
                _TeamCalendarMetricPill(
                  icon: Icons.local_hospital,
                  label: 'Krank',
                  color: colorScheme.error,
                  compact: true,
                ),
                _TeamCalendarMetricPill(
                  icon: Icons.block,
                  label: 'Nicht verfuegbar',
                  color: colorScheme.secondary,
                  compact: true,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (members.isEmpty)
              const _EmptyState(
                icon: Icons.groups_outlined,
                text: 'Keine aktiven Mitarbeiter.',
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  // B4/§6.1: 700 → 840 (expandedWindow), damit iPad-Portrait
                  // (810/834 dp) die Kartenansicht statt der breiten Scroll-
                  // Tabelle bekommt (kein Horizontal-Scroll).
                  if (constraints.maxWidth < MobileBreakpoints.expandedWindow) {
                    return _buildMobileCalendar(
                      context,
                      members: members,
                      days: days,
                      today: today,
                      shiftsByUserDay: shiftsByUserDay,
                      absencesByUserDay: absencesByUserDay,
                    );
                  }
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Table(
                      defaultColumnWidth: const FixedColumnWidth(132),
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      columnWidths: const {
                        0: FixedColumnWidth(220),
                      },
                      border: TableBorder(
                        horizontalInside: BorderSide(
                          color:
                              colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      children: [
                        TableRow(
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                'Mitarbeiter',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            for (final day in days)
                              Padding(
                                padding: const EdgeInsets.all(10),
                                child: _DayHeaderCell(
                                  day: day,
                                  isToday: _isSameDay(day, today),
                                  isSelected: _isSameDay(day, _selectedDay),
                                ),
                              ),
                          ],
                        ),
                        for (final member in members)
                          TableRow(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: _buildMemberCell(member, days),
                              ),
                              for (final day in days)
                                Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: _buildDayCell(
                                    context,
                                    member.uid,
                                    day,
                                    shiftsByUserDay,
                                    absencesByUserDay,
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  );
                },
              ),
            const SizedBox(height: 16),
            _buildSelectedDayDetails(
              context,
              day: selectedDayStart,
              shifts: selectedShifts,
              absences: selectedAbsences,
            ),
          ],
        ),
      ),
    );
  }

  void _moveWeek(int direction) {
    final selectedOffset =
        _selectedDay.difference(_weekStart).inDays.clamp(0, 6);
    setState(() {
      _weekStart = _weekStart.add(Duration(days: 7 * direction));
      _selectedDay =
          _startOfDay(_weekStart.add(Duration(days: selectedOffset)));
    });
  }

  void _goToCurrentWeek() {
    final today = _startOfDay(DateTime.now());
    setState(() {
      _weekStart = _startOfWeek(today);
      _selectedDay = today;
    });
  }

  Widget _buildMobileCalendar(
    BuildContext context, {
    required List<AppUserProfile> members,
    required List<DateTime> days,
    required DateTime today,
    required Map<String, List<Shift>> shiftsByUserDay,
    required Map<String, List<AbsenceRequest>> absencesByUserDay,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        // Horizontal day selector strip
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final day in days)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _MobileDayChip(
                    day: day,
                    isToday: _isSameDay(day, today),
                    isSelected: _isSameDay(day, _selectedDay),
                    onTap: () =>
                        setState(() => _selectedDay = _startOfDay(day)),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Member list for selected day
        ...members.map((member) {
          final snapshot = _snapshotFor(
            member.uid,
            _selectedDay,
            shiftsByUserDay,
            absencesByUserDay,
          );
          final palette = _paletteFor(colorScheme, snapshot.status);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    child: Text(
                      member.displayName.characters.first.toUpperCase(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.displayName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              snapshot.icon,
                              size: 14,
                              color: palette.foreground,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${snapshot.title} · ${snapshot.subtitle}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: palette.foreground,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildMemberCell(AppUserProfile member, List<DateTime> days) {
    final weekEnd = days.last.add(const Duration(days: 1));
    final memberShifts = widget.shifts.where((shift) {
      return shift.userId == member.uid &&
          !shift.startTime.isBefore(days.first) &&
          shift.startTime.isBefore(weekEnd);
    }).toList(growable: false);
    final memberAbsenceDays = widget.absences.where((absence) {
      return absence.userId == member.uid &&
          absence.status == AbsenceStatus.approved &&
          absence.overlaps(days.first, weekEnd);
    }).length;
    final totalHours =
        memberShifts.fold<double>(0, (sum, shift) => sum + shift.workedHours);

    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          child: Text(member.displayName.characters.first.toUpperCase()),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                member.displayName,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                '${memberShifts.length} Schichten · ${totalHours.toStringAsFixed(1)} h'
                '${memberAbsenceDays > 0 ? ' · $memberAbsenceDays Abw.' : ''}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDayCell(
    BuildContext context,
    String userId,
    DateTime day,
    Map<String, List<Shift>> shiftsByUserDay,
    Map<String, List<AbsenceRequest>> absencesByUserDay,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final snapshot = _snapshotFor(
      userId,
      day,
      shiftsByUserDay,
      absencesByUserDay,
    );
    final isSelected = _isSameDay(day, _selectedDay);
    final isToday = _isSameDay(day, DateTime.now());
    final palette = _paletteFor(colorScheme, snapshot.status);

    return Tooltip(
      message: snapshot.tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _selectedDay = _startOfDay(day)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 122,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : isToday
                      ? colorScheme.primary.withValues(alpha: 0.35)
                      : colorScheme.outlineVariant.withValues(alpha: 0.6),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(snapshot.icon, size: 16, color: palette.foreground),
                  const SizedBox(width: 6),
                  if (isToday)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Heute',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                snapshot.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: palette.foreground,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                snapshot.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.foreground.withValues(alpha: 0.85),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _TeamDaySnapshot _snapshotFor(
    String userId,
    DateTime day,
    Map<String, List<Shift>> shiftsByUserDay,
    Map<String, List<AbsenceRequest>> absencesByUserDay,
  ) {
    final key = _userDayKey(userId, day);
    final dayAbsences = absencesByUserDay[key] ?? const [];
    final dayShifts = shiftsByUserDay[key] ?? const [];

    if (dayAbsences.isNotEmpty) {
      final type = dayAbsences.first.type;
      final status = switch (type) {
        AbsenceType.vacation => _TeamDayStatus.vacation,
        AbsenceType.sickness => _TeamDayStatus.sickness,
        // Jede sonstige genehmigte Abwesenheit (Sonderurlaub, unbezahlt …)
        // blockiert den Tag generisch.
        _ => _TeamDayStatus.unavailable,
      };
      return _TeamDaySnapshot(
        status: status,
        icon: switch (type) {
          AbsenceType.vacation => Icons.beach_access,
          AbsenceType.sickness => Icons.local_hospital,
          _ => Icons.event_busy,
        },
        title: type.label,
        subtitle: dayAbsences.length > 1
            ? '${dayAbsences.length} Eintraege'
            : 'Ganztags blockiert',
        tooltip: dayAbsences
            .map(
              (absence) => '${absence.employeeName}: ${absence.type.label} '
                  '(${DateFormat('dd.MM.yyyy', 'de_DE').format(absence.startDate)} - '
                  '${DateFormat('dd.MM.yyyy', 'de_DE').format(absence.endDate)})',
            )
            .join('\n'),
      );
    }

    if (dayShifts.isNotEmpty) {
      final first = dayShifts.first;
      final last = dayShifts.last;
      final totalHours =
          dayShifts.fold<double>(0, (sum, shift) => sum + shift.workedHours);
      return _TeamDaySnapshot(
        status: _TeamDayStatus.shift,
        icon: Icons.badge_outlined,
        title: dayShifts.length == 1
            ? first.title
            : '${dayShifts.length} Schichten',
        subtitle:
            '${DateFormat('HH:mm', 'de_DE').format(first.startTime)} - ${DateFormat('HH:mm', 'de_DE').format(last.endTime)} · ${totalHours.toStringAsFixed(1)} h',
        tooltip: dayShifts
            .map(
              (shift) => '${shift.employeeName}: ${shift.title} '
                  '${DateFormat('HH:mm', 'de_DE').format(shift.startTime)} - '
                  '${DateFormat('HH:mm', 'de_DE').format(shift.endTime)}',
            )
            .join('\n'),
      );
    }

    return const _TeamDaySnapshot(
      status: _TeamDayStatus.free,
      icon: Icons.check_circle_outline,
      title: 'Frei',
      subtitle: 'Keine Eintraege',
      tooltip: 'Keine Schicht oder genehmigte Abwesenheit',
    );
  }

  Widget _buildSelectedDayDetails(
    BuildContext context, {
    required DateTime day,
    required List<Shift> shifts,
    required List<AbsenceRequest> absences,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Details fuer ${DateFormat('EEEE, dd.MM.yyyy', 'de_DE').format(day)}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final useColumn = constraints.maxWidth < 860;
              final shiftPanel = _TeamDayDetailPanel(
                title: 'Schichten (${shifts.length})',
                icon: Icons.schedule_outlined,
                color: colorScheme.primary,
                child: shifts.isEmpty
                    ? const Text('Keine Schichten an diesem Tag.')
                    : Column(
                        children: shifts.map((shift) {
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 16,
                              child: Text(
                                shift.employeeName.characters.first
                                    .toUpperCase(),
                              ),
                            ),
                            title: Text(shift.employeeName),
                            subtitle: Text(
                              '${shift.title} · ${DateFormat('HH:mm', 'de_DE').format(shift.startTime)} - ${DateFormat('HH:mm', 'de_DE').format(shift.endTime)}',
                            ),
                            trailing: Text(
                              shift.status.label,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
              );
              final absencePanel = _TeamDayDetailPanel(
                title: 'Abwesenheiten (${absences.length})',
                icon: Icons.event_busy_outlined,
                color: colorScheme.tertiary,
                child: absences.isEmpty
                    ? const Text('Keine genehmigten Abwesenheiten.')
                    : Column(
                        children: absences.map((absence) {
                          final accent = switch (absence.type) {
                            AbsenceType.vacation => colorScheme.tertiary,
                            AbsenceType.sickness => colorScheme.error,
                            _ => colorScheme.secondary,
                          };
                          final icon = switch (absence.type) {
                            AbsenceType.vacation => Icons.beach_access,
                            AbsenceType.sickness => Icons.local_hospital,
                            _ => Icons.event_busy,
                          };
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(icon, color: accent),
                            title: Text(absence.employeeName),
                            subtitle: Text(
                              '${absence.type.label} · ${DateFormat('dd.MM.', 'de_DE').format(absence.startDate)} - ${DateFormat('dd.MM.', 'de_DE').format(absence.endDate)}',
                            ),
                          );
                        }).toList(),
                      ),
              );

              if (useColumn) {
                return Column(
                  children: [
                    shiftPanel,
                    const SizedBox(height: 12),
                    absencePanel,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: shiftPanel),
                  const SizedBox(width: 12),
                  Expanded(child: absencePanel),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  ({Color background, Color foreground}) _paletteFor(
    ColorScheme colorScheme,
    _TeamDayStatus status,
  ) {
    return switch (status) {
      _TeamDayStatus.shift => (
          background: colorScheme.primaryContainer.withValues(alpha: 0.65),
          foreground: colorScheme.primary,
        ),
      _TeamDayStatus.vacation => (
          background: colorScheme.tertiaryContainer.withValues(alpha: 0.75),
          foreground: colorScheme.tertiary,
        ),
      _TeamDayStatus.sickness => (
          background: colorScheme.errorContainer.withValues(alpha: 0.75),
          foreground: colorScheme.error,
        ),
      _TeamDayStatus.unavailable => (
          background: colorScheme.secondaryContainer.withValues(alpha: 0.75),
          foreground: colorScheme.secondary,
        ),
      _TeamDayStatus.free => (
          background: colorScheme.surface,
          foreground: colorScheme.onSurfaceVariant,
        ),
    };
  }

  DateTime _startOfDay(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  DateTime _startOfWeek(DateTime value) {
    final day = _startOfDay(value);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  String _dayKey(DateTime day) =>
      DateFormat('yyyyMMdd', 'de_DE').format(_startOfDay(day));

  String _userDayKey(String userId, DateTime day) => '$userId|${_dayKey(day)}';

  String _formatWeekLabel(DateTime start, DateTime end) {
    return '${DateFormat('dd.MM.', 'de_DE').format(start)} - '
        '${DateFormat('dd.MM.yyyy', 'de_DE').format(end)}';
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

enum _TeamDayStatus { free, shift, vacation, sickness, unavailable }

class _TeamDaySnapshot {
  const _TeamDaySnapshot({
    required this.status,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tooltip,
  });

  final _TeamDayStatus status;
  final IconData icon;
  final String title;
  final String subtitle;
  final String tooltip;
}

class _MobileDayChip extends StatelessWidget {
  const _MobileDayChip({
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime day;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: isSelected
          ? colorScheme.primaryContainer
          : isToday
              ? colorScheme.surfaceContainerHigh
              : colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 56,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : isToday
                      ? colorScheme.primary.withValues(alpha: 0.35)
                      : colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                DateFormat('E', 'de_DE').format(day).substring(0, 2),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight:
                      isSelected || isToday ? FontWeight.bold : FontWeight.w600,
                  color: isSelected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${day.day}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamCalendarMetricPill extends StatelessWidget {
  const _TeamCalendarMetricPill({
    required this.icon,
    required this.label,
    required this.color,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 16 : 18, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}

class _TeamDayDetailPanel extends StatelessWidget {
  const _TeamDayDetailPanel({
    required this.title,
    required this.icon,
    required this.color,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}


Future<void> _handlePunchClockAction(
  BuildContext context,
  WorkProvider provider, {
  bool viaQr = false,
}) async {
  try {
    final wasEntryBacked = provider.isClockBackedByEntry;
    if (provider.hasActiveClockSession) {
      try {
        await provider.clockOut();
      } on OvertimeApprovalRequired catch (approval) {
        if (!context.mounted) {
          return;
        }
        final approved = await _confirmPunchClockOvertime(context, approval);
        if (approved != true) {
          return;
        }
        await provider.clockOut(allowOvertime: true);
      }
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            viaQr
                ? 'QR-Checkout gespeichert'
                : (wasEntryBacked
                    ? 'Laufender Zeiteintrag beendet'
                    : 'Ausgestempelt und gespeichert'),
          ),
        ),
      );
    } else {
      await provider.clockIn();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            viaQr ? 'QR-Check-in gestartet' : 'Stempeluhr gestartet',
          ),
        ),
      );
    }
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_formatUserError(error)),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }
}

Future<bool?> _confirmPunchClockOvertime(
  BuildContext context,
  OvertimeApprovalRequired approval,
) {
  final timeFmt = DateFormat('HH:mm', 'de_DE');
  final lines = <String>[
    'Die geplante Schicht endet um '
        '${timeFmt.format(approval.shift.endTime)}.',
  ];
  if (approval.hasBeforeShiftOvertime) {
    lines.add(
      'Zusatzzeit vor der Schicht: '
      '${timeFmt.format(approval.beforeShiftStart!)} - '
      '${timeFmt.format(approval.beforeShiftEnd!)}',
    );
  }
  if (approval.hasAfterShiftOvertime) {
    lines.add(
      'Zusatzzeit nach der Schicht: '
      '${timeFmt.format(approval.afterShiftStart!)} - '
      '${timeFmt.format(approval.afterShiftEnd!)}',
    );
  }
  lines.add(
    'Die Schicht selbst bleibt unveraendert. Die Zusatzzeit wird als Ueberstunden gespeichert.',
  );

  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Arbeitszeit verlaengern?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines) ...[
              Text(line),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Als Ueberstunden speichern'),
        ),
      ],
    ),
  );
}

// Legacy-V1-Zeiterfassungs-Tab: seit dem Zeit-Hub (ZeitwirtschaftHubScreen an
// ShellTab.time) nicht mehr instanziiert; der frueher durchgereichte
// onNavigateBack-Parameter ist entfernt (N3, unused_element_parameter).
class _TimeTrackingTab extends StatefulWidget {
  const _TimeTrackingTab({
    required this.canNavigateBack,
  });

  final bool canNavigateBack;

  @override
  State<_TimeTrackingTab> createState() => _TimeTrackingTabState();
}

class _TimeTrackingTabState extends State<_TimeTrackingTab> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Future<List<Shift>>? _monthShiftsFuture;
  String? _monthShiftsKey;

  void _refreshMonthShiftsFuture(WorkProvider provider) {
    final user = provider.currentUser;
    final month = provider.selectedMonth;
    final nextKey = '${user?.orgId}:${user?.uid}:${month.year}-${month.month}';
    if (_monthShiftsKey == nextKey && _monthShiftsFuture != null) {
      return;
    }
    _monthShiftsKey = nextKey;
    _monthShiftsFuture = provider.loadShiftsForMonth(month);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WorkProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = theme.appColors;
    final monthFmt = DateFormat('MMMM yyyy', 'de_DE');
    final currentUser = provider.currentUser;
    _refreshMonthShiftsFuture(provider);

    return SafeArea(
      child: currentUser == null
          ? const Center(child: CircularProgressIndicator.adaptive())
          : !currentUser.canViewTimeTracking
              ? Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: SectionCard(
                        title: 'Kein Zugriff',
                        child: Text(
                          'Die Zeiterfassung ist fuer dieses Profil deaktiviert. '
                          'Ein Admin kann den Bereich bei Bedarf wieder freischalten.',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    ),
                  ),
                )
              : FutureBuilder<List<Shift>>(
                  future: _monthShiftsFuture,
                  builder: (context, snapshot) {
                    final monthShifts = snapshot.data ?? const <Shift>[];
                    final plannedHoursThisMonth = _sumShiftHours(monthShifts);
                    final plannedHoursByDay = <int, double>{};
                    final actualHoursByDay = <int, double>{};

                    for (final shift in monthShifts) {
                      final dayKey = _calendarDayKey(shift.startTime);
                      plannedHoursByDay[dayKey] =
                          (plannedHoursByDay[dayKey] ?? 0) + shift.workedHours;
                    }
                    for (final entry in provider.entries) {
                      // E3: nur genehmigte Zeiten in die „Ist"-Seite des
                      // Kalenders (Planseite bleibt Planzeit).
                      if (!countsAsIst(entry)) continue;
                      final dayKey = _calendarDayKey(entry.date);
                      actualHoursByDay[dayKey] =
                          (actualHoursByDay[dayKey] ?? 0) + entry.workedHours;
                    }

                    final selectedDayShifts = _selectedDay == null
                        ? const <Shift>[]
                        : _shiftsForDay(monthShifts, _selectedDay!);

                    return Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: CustomScrollView(
                          slivers: [
                            const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                                child: SectionHeader(
                                  title: 'Zeiterfassung',
                                  subtitle:
                                      'Monatsansicht, Kalendertage und Eintragsdetails fuer deine Arbeitszeiten.',
                                  breadcrumbs: [
                                    BreadcrumbItem(label: 'Zeit'),
                                    BreadcrumbItem(label: 'Zeiterfassung'),
                                  ],
                                  onBack: null,
                                ),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 16, 16, 0),
                                child: Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    if (currentUser.canViewReports)
                                      FilledButton.icon(
                                        onPressed: () =>
                                            context.push(AppRoutes.monthReport),
                                        icon: const Icon(
                                            Icons.description_outlined),
                                        label: const Text('Monatsbericht'),
                                      ),
                                    if (currentUser.canEditTimeEntries)
                                      OutlinedButton.icon(
                                        onPressed: () =>
                                            Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => EntryFormScreen(
                                              parentLabel: 'Zeit',
                                              initialDate: _selectedDay ??
                                                  DateTime.now(),
                                            ),
                                          ),
                                        ),
                                        icon: const Icon(Icons.add),
                                        label: const Text('Eintrag'),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.chevron_left),
                                      onPressed: provider.previousMonth,
                                    ),
                                    Expanded(
                                      child: Center(
                                        child: Text(
                                          monthFmt
                                              .format(provider.selectedMonth),
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.chevron_right),
                                      onPressed: provider.nextMonth,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: _SummaryCards(
                                  provider: provider,
                                  plannedHours: plannedHoursThisMonth > 0
                                      ? plannedHoursThisMonth
                                      : null,
                                  loadingPlannedHours:
                                      snapshot.connectionState ==
                                              ConnectionState.waiting &&
                                          !snapshot.hasData,
                                ),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    Card(
                                      child: TableCalendar(
                                        locale: 'de_DE',
                                        firstDay: DateTime(2020),
                                        lastDay: DateTime(2035),
                                        focusedDay: _focusedDay,
                                        selectedDayPredicate: (day) =>
                                            isSameDay(_selectedDay, day),
                                        calendarFormat: CalendarFormat.month,
                                        startingDayOfWeek:
                                            StartingDayOfWeek.monday,
                                        headerStyle: HeaderStyle(
                                          formatButtonVisible: false,
                                          titleCentered: true,
                                          titleTextStyle: theme
                                              .textTheme.titleMedium!
                                              .copyWith(
                                                  fontWeight: FontWeight.bold),
                                          leftChevronIcon: Icon(
                                            Icons.chevron_left,
                                            color: colorScheme.primary,
                                          ),
                                          rightChevronIcon: Icon(
                                            Icons.chevron_right,
                                            color: colorScheme.primary,
                                          ),
                                        ),
                                        calendarStyle: CalendarStyle(
                                          cellMargin:
                                              const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 6,
                                          ),
                                          todayDecoration: BoxDecoration(
                                            color:
                                                colorScheme.secondaryContainer,
                                            shape: BoxShape.circle,
                                          ),
                                          selectedDecoration: BoxDecoration(
                                            color: colorScheme.tertiary,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        onDaySelected:
                                            (selectedDay, focusedDay) {
                                          setState(() {
                                            _selectedDay = selectedDay;
                                            _focusedDay = focusedDay;
                                          });
                                        },
                                        onPageChanged: (focusedDay) {
                                          _focusedDay = focusedDay;
                                          provider.selectMonth(focusedDay);
                                        },
                                        calendarBuilders: CalendarBuilders(
                                          markerBuilder:
                                              (context, day, events) {
                                            final dayKey = _calendarDayKey(day);
                                            final plannedHours =
                                                plannedHoursByDay[dayKey] ?? 0;
                                            final actualHours =
                                                actualHoursByDay[dayKey] ?? 0;
                                            if (plannedHours <= 0 &&
                                                actualHours <= 0) {
                                              return null;
                                            }
                                            return Positioned(
                                              bottom: 3,
                                              child: _CalendarDayLoadMarker(
                                                plannedHours: plannedHours,
                                                actualHours: actualHours,
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        _CalendarLegendMarker(
                                          color: colorScheme.tertiary,
                                          outlined: true,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Geplant (Soll)',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        _CalendarLegendMarker(
                                          color: appColors.success,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Erfasst (Ist)',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_selectedDay != null)
                              SliverToBoxAdapter(
                                child: _DayEntries(
                                  day: _selectedDay!,
                                  entries:
                                      provider.getEntriesForDay(_selectedDay!),
                                  shifts: selectedDayShifts,
                                ),
                              ),
                            if (_selectedDay == null)
                              _EntriesList(entries: provider.entries),
                            const SliverToBoxAdapter(
                                child: SizedBox(height: 96)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _CalendarDayLoadMarker extends StatelessWidget {
  const _CalendarDayLoadMarker({
    required this.plannedHours,
    required this.actualHours,
  });

  final double plannedHours;
  final double actualHours;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).appColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (plannedHours > 0)
          _CalendarLegendMarker(
            color: colorScheme.tertiary,
            outlined: true,
            width: 10 +
                ((plannedHours < 2
                        ? 2
                        : plannedHours > 10
                            ? 10
                            : plannedHours) *
                    1.35),
          ),
        if (plannedHours > 0 && actualHours > 0) const SizedBox(height: 2),
        if (actualHours > 0)
          _CalendarLegendMarker(
            color: appColors.success,
            width: 10 +
                ((actualHours < 2
                        ? 2
                        : actualHours > 10
                            ? 10
                            : actualHours) *
                    1.35),
          ),
      ],
    );
  }
}

class _CalendarLegendMarker extends StatelessWidget {
  const _CalendarLegendMarker({
    required this.color,
    this.outlined = false,
    this.width = 18,
  });

  final Color color;
  final bool outlined;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 5,
      decoration: BoxDecoration(
        color: outlined ? color.withValues(alpha: 0.14) : color,
        borderRadius: BorderRadius.circular(999),
        border:
            outlined ? Border.all(color: color.withValues(alpha: 0.75)) : null,
      ),
    );
  }
}

EmployeeSiteAssignment? _resolvePrimaryAssignment(
  TeamProvider team,
  String? userId,
) {
  if (userId == null || userId.isEmpty) {
    return null;
  }
  final assignments = team.siteAssignments
      .where((assignment) => assignment.userId == userId)
      .toList(growable: false);
  for (final assignment in assignments) {
    if (assignment.isPrimary) {
      return assignment;
    }
  }
  return assignments.isEmpty ? null : assignments.first;
}

WorkEntry? _resolveLastClockEntry(Iterable<WorkEntry> entries) {
  final clockEntries = entries
      .where((entry) => entry.note?.contains('Stempeluhr') ?? false)
      .toList(growable: false)
    ..sort((a, b) => b.startTime.compareTo(a.startTime));
  return clockEntries.isEmpty ? null : clockEntries.first;
}

SiteDefinition? _resolvePrimarySite(
  Iterable<SiteDefinition> sites,
  EmployeeSiteAssignment? assignment,
) {
  if (assignment == null) {
    return null;
  }
  for (final site in sites) {
    if (site.id == assignment.siteId) {
      return site;
    }
  }
  return null;
}

class _ClockStatTile extends StatelessWidget {
  const _ClockStatTile({
    required this.label,
    required this.time,
    required this.icon,
    required this.color,
  });

  final String label;
  final String time;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final iconColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
            ? Colors.white
            : Theme.of(context).colorScheme.onSurface;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        letterSpacing: 0.5,
                      ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    time,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
