// Teil von home_screen.dart (Signal-Teal-Redesign, redesign_v2).
//
// Flag-gegatete V2-Varianten der „today"-Tab-Dashboards (Employee + Admin).
// Datenlogik, Provider-Watches, Helfer-Aufrufe und deutsche Texte sind
// byte-gleich zu den V1-Tabs in home_screen_tabs.dart; nur die Praesentation
// nutzt die lib/ui-Komponenten + V2-Tokens. Die tief-stateful Widgets
// (_ClockInOutWidget mit Zeit-Korrektur/Slide, _WeeklyProgressWidget,
// _PendingAbsencesWidget) werden bewusst unveraendert wiederverwendet
// (Funktions-Erhalt: Timer/Gesten/Korrektur-Dialog).
part of 'home_screen.dart';

class _EmployeeDashboardTabV2 extends StatelessWidget {
  const _EmployeeDashboardTabV2({
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
    final spacing = context.spacing;
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: screenPad.horizontal / 2,
              vertical: spacing.md,
            ),
            children: [
              SectionHeader(
                title: 'Heute',
                subtitle:
                    'Nächste Schicht, Arbeitszeit und offene Aufgaben ohne Umwege.',
                breadcrumbs: const [BreadcrumbItem(label: 'Heute')],
                onBack: canNavigateBack ? onNavigateBack : null,
              ),
              SizedBox(height: spacing.lg),
              _EmployeeHeroCardV2(nextShift: nextShift, provider: work),
              SizedBox(height: spacing.md),
              const DashboardActionItemsCard(parentLabel: 'Heute'),
              AdaptiveCardGrid(
                minItemWidth: 180,
                children: [
                  AppQuickActionCard(
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
                  AppQuickActionCard(
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
                    AppQuickActionCard(
                      icon: Icons.edit_calendar_outlined,
                      title: 'Zeit erfassen',
                      subtitle: 'Manuellen Eintrag anlegen oder korrigieren',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const EntryFormScreen(parentLabel: 'Heute'),
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: spacing.md),
              if (canViewSchedule)
                _EmployeeWeekStripV2(
                  upcomingShifts: upcomingShifts,
                  absences: ownAbsences,
                ),
              SizedBox(height: spacing.md),
              if (pendingAbsences.isNotEmpty || pendingSwapCount > 0)
                AppSectionCard(
                  title: 'Offene Aufgaben',
                  child: Column(
                    children: [
                      if (pendingAbsences.isNotEmpty)
                        _ActionStateTile(
                          icon: Icons.pending_actions,
                          title:
                              '${pendingAbsences.length} Abwesenheitsanträge offen',
                          subtitle:
                              'Deine Anträge sind eingereicht und warten auf Rückmeldung.',
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
                              'Sobald entschieden wurde, erscheint die Rückmeldung in Anfragen.',
                          color: Theme.of(context).colorScheme.primary,
                        ),
                    ],
                  ),
                ),
              if (pendingAbsences.isNotEmpty || pendingSwapCount > 0)
                SizedBox(height: spacing.md),
              _ClockInOutWidget(provider: work),
              SizedBox(height: spacing.lg),
              _WeeklyProgressWidget(provider: work),
              SizedBox(height: spacing.md),
              _MonthlyShiftSummaryCardsV2(provider: work),
              if (pendingAbsences.isNotEmpty) ...[
                SizedBox(height: spacing.md),
                _PendingAbsencesWidget(absences: pendingAbsences),
              ],
              SizedBox(height: spacing.lg),
              AppSectionCard(
                title: 'Nächste Schichten',
                child: upcomingShifts.isEmpty
                    ? const EmptyState(
                        icon: Icons.event_busy_outlined,
                        message:
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
              SizedBox(height: spacing.lg),
              AppSectionCard(
                title: 'Letzte Einträge',
                child: recentEntries.isEmpty
                    ? const EmptyState(
                        icon: Icons.inbox_outlined,
                        message: 'Noch keine Arbeitszeiteinträge vorhanden.',
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

/// V2-Hero des Mitarbeiter-Dashboards: gleiche Stempeluhr-/Nächste-Schicht-
/// Logik wie [_EmployeeHeroCard], aber in der [AppHeroCard]-Huelle.
class _EmployeeHeroCardV2 extends StatelessWidget {
  const _EmployeeHeroCardV2({required this.nextShift, required this.provider});

  final Shift? nextShift;
  final WorkProvider provider;

  @override
  Widget build(BuildContext context) {
    final team = context.watch<TeamProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final spacing = context.spacing;
    final nextShift = this.nextShift;
    // Frei stempelbare, persistente Stempeluhr (ZeitwirtschaftProvider) — wie
    // V1. Der Button führt zum dedizierten Stempel-Screen (kein Schicht-Gate).
    final isClockActive = context.watch<ZeitwirtschaftProvider>().isClockedIn;
    final primaryAssignment =
        _resolvePrimaryAssignment(team, provider.currentUser?.uid);
    final primarySite = _resolvePrimarySite(
      team.sites.isNotEmpty ? team.sites : provider.sites,
      primaryAssignment,
    );
    final siteLabel = primarySite?.name ??
        primaryAssignment?.siteName ??
        'Kein Standort hinterlegt';

    return AppHeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            nextShift == null
                ? 'Heute ohne geplante Schicht'
                : 'Nächste Schicht',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: spacing.sm),
          if (nextShift == null)
            Text(
              primaryAssignment != null
                  ? 'Arbeitszeit kann nur während einer geplanten Schicht erfasst werden.'
                  : 'Zum Einstempeln fehlt aktuell ein zugewiesener Standort.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            )
          else ...[
            Text(
              '${DateFormat('EEEE, dd.MM.', 'de_DE').format(nextShift.startTime)} · '
              '${DateFormat('HH:mm', 'de_DE').format(nextShift.startTime)} - ${DateFormat('HH:mm', 'de_DE').format(nextShift.endTime)}',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: spacing.xs + spacing.xxs),
            Wrap(
              spacing: spacing.sm,
              runSpacing: spacing.sm,
              children: [
                InfoChip(
                  icon: Icons.storefront_outlined,
                  label: nextShift.effectiveSiteLabel ?? 'Standort offen',
                ),
                InfoChip(icon: Icons.badge_outlined, label: nextShift.title),
                InfoChip(
                  icon: Icons.hourglass_bottom_outlined,
                  label: '${nextShift.workedHours.toStringAsFixed(1)} h',
                ),
              ],
            ),
          ],
          SizedBox(height: spacing.md + spacing.xxs),
          Wrap(
            spacing: spacing.sm + spacing.xs,
            runSpacing: spacing.sm + spacing.xs,
            children: [
              FilledButton.icon(
                onPressed: () => context.push(AppRoutes.zeitStempeln),
                icon: Icon(
                  isClockActive ? Icons.stop_circle : Icons.play_circle,
                ),
                label: Text(isClockActive ? 'Ausstempeln' : 'Einstempeln'),
                style: isClockActive
                    ? FilledButton.styleFrom(
                        backgroundColor: colorScheme.error,
                        foregroundColor: colorScheme.onError,
                      )
                    : null,
              ),
              OutlinedButton.icon(
                onPressed: nextShift == null
                    ? null
                    : () => _showShiftDetailsSheet(
                          context,
                          shift: nextShift,
                          isPlanner: false,
                        ),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Details'),
              ),
            ],
          ),
          if (nextShift == null) ...[
            SizedBox(height: spacing.sm + spacing.xs),
            Text(
              'Stempeluhr-Standort: $siteLabel',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// V2-Wochenstreifen: gleiche Tages-/Abwesenheits-Logik wie [_EmployeeWeekStrip],
/// in [AppSectionCard] mit tokenisierten Tageszellen.
class _EmployeeWeekStripV2 extends StatelessWidget {
  const _EmployeeWeekStripV2({
    required this.upcomingShifts,
    required this.absences,
  });

  final List<Shift> upcomingShifts;
  final List<AbsenceRequest> absences;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final spacing = context.spacing;
    final today = DateTime.now();
    final days = List.generate(
      7,
      (index) => DateTime(today.year, today.month, today.day + index),
    );

    // Höhe an das Text-Scaling koppeln, sonst schneidet die feste 110px-Höhe
    // die Tageszellen bei großer Schrift ab (vertikaler Overflow).
    final textScale =
        MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    return AppSectionCard(
      title: 'Deine Woche',
      child: SizedBox(
        height: 110 * textScale,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemBuilder: (context, index) {
            final day = days[index];
            final dayShifts = upcomingShifts.where((shift) {
              return shift.startTime.year == day.year &&
                  shift.startTime.month == day.month &&
                  shift.startTime.day == day.day;
            }).toList(growable: false);
            final dayAbsences = absences.where((absence) {
              return absence.overlaps(day, day.add(const Duration(days: 1)));
            }).toList(growable: false);
            final hasItems = dayShifts.isNotEmpty || dayAbsences.isNotEmpty;
            final label = DateFormat('EEE', 'de_DE').format(day).toUpperCase();
            final detail = dayAbsences.isNotEmpty
                ? dayAbsences.first.type.label
                : dayShifts.isNotEmpty
                    ? DateFormat('HH:mm', 'de_DE').format(dayShifts.first.startTime)
                    : 'Frei';
            return Container(
              width: 88,
              padding: EdgeInsets.all(spacing.sm + spacing.xs),
              decoration: BoxDecoration(
                color: hasItems
                    ? colorScheme.primaryContainer.withValues(alpha: 0.45)
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(context.radii.lg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: spacing.xs),
                  Text(
                    DateFormat('dd.MM.', 'de_DE').format(day),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    dayShifts.isEmpty && dayAbsences.isEmpty
                        ? 'Keine'
                        : '${dayShifts.length + dayAbsences.length} ${dayShifts.length + dayAbsences.length == 1 ? 'Eintrag' : 'Einträge'}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          },
          separatorBuilder: (_, __) => SizedBox(width: spacing.sm + spacing.xxs),
          itemCount: days.length,
        ),
      ),
    );
  }
}

/// V2-Variante der Monats-Summary-Karten: identische Future-/Schichtstunden-
/// Logik wie [_MonthlyShiftSummaryCards], rendert [_SummaryCardsV2].
class _MonthlyShiftSummaryCardsV2 extends StatefulWidget {
  const _MonthlyShiftSummaryCardsV2({required this.provider});

  final WorkProvider provider;

  @override
  State<_MonthlyShiftSummaryCardsV2> createState() =>
      _MonthlyShiftSummaryCardsV2State();
}

class _MonthlyShiftSummaryCardsV2State
    extends State<_MonthlyShiftSummaryCardsV2> {
  Future<List<Shift>>? _future;
  String? _futureKey;

  void _refreshFuture() {
    final provider = widget.provider;
    final user = provider.currentUser;
    final month = provider.selectedMonth;
    final nextKey = '${user?.orgId}:${user?.uid}:${month.year}-${month.month}';
    if (_futureKey == nextKey && _future != null) {
      return;
    }
    _futureKey = nextKey;
    _future = provider.loadShiftsForMonth(month);
  }

  @override
  Widget build(BuildContext context) {
    _refreshFuture();
    return FutureBuilder<List<Shift>>(
      future: _future,
      builder: (context, snapshot) {
        final plannedHours = _sumShiftHours(snapshot.data ?? const <Shift>[]);
        final cards = _SummaryCardsV2(
          provider: widget.provider,
          plannedHours: plannedHours > 0 ? plannedHours : null,
          loadingPlannedHours:
              snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData,
        );
        // Ladefehler nicht still verschlucken (sonst wirkt es wie „0 Stunden").
        if (snapshot.hasError) {
          final theme = Theme.of(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              cards,
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Geplante Stunden konnten nicht geladen werden.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          );
        }
        return cards;
      },
    );
  }
}

/// V2-Summary-Karten auf [AppStatCard]/[AppComparisonStatCard]. Werte/Logik
/// identisch zu [_SummaryCards].
class _SummaryCardsV2 extends StatelessWidget {
  const _SummaryCardsV2({
    required this.provider,
    this.plannedHours,
    this.loadingPlannedHours = false,
  });

  final WorkProvider provider;
  final double? plannedHours;
  final bool loadingPlannedHours;

  @override
  Widget build(BuildContext context) {
    final settings = provider.settings;
    final colorScheme = Theme.of(context).colorScheme;
    final hasPlannedHours = plannedHours != null && plannedHours! > 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final children = <Widget>[
          AppStatCard(
            label: 'Stunden',
            value: '${provider.totalHoursThisMonth.toStringAsFixed(1)} h',
            subtitle: hasPlannedHours
                ? '${plannedHours!.toStringAsFixed(1)} h geplant'
                : 'Erfasste Arbeitszeit im Monat',
            icon: Icons.access_time,
            color: colorScheme.secondary,
          ),
          if (hasPlannedHours || loadingPlannedHours)
            AppComparisonStatCard(
              plannedHours: plannedHours,
              actualHours: provider.totalHoursThisMonth,
              loading: loadingPlannedHours,
            ),
          AppStatCard(
            label: 'Überstunden',
            value: '${provider.overtimeThisMonth.toStringAsFixed(1)} h',
            subtitle: 'Zeit oberhalb deiner Tagesvorgabe',
            icon: Icons.trending_up,
            color: colorScheme.tertiary,
          ),
          if (settings.hourlyRate > 0)
            AppStatCard(
              label: 'Bruttolohn',
              value: NumberFormat.currency(
                locale: 'de_DE',
                symbol: settings.currency,
              ).format(provider.totalWageThisMonth),
              subtitle: 'Auf Basis der erfassten Stunden',
              icon: Icons.euro,
              color: colorScheme.primary,
            ),
        ];

        final wideColumns = children.length < 4 ? children.length : 4;
        final columns = constraints.maxWidth >= 1080
            ? wideColumns
            : constraints.maxWidth >= 720
                ? 2
                : 1;
        const spacing = 12.0;
        final itemWidth = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

class _AdminDashboardTabV2 extends StatelessWidget {
  const _AdminDashboardTabV2({
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
    final colorScheme = Theme.of(context).colorScheme;
    final spacing = context.spacing;
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
              vertical: spacing.md,
            ),
            children: [
              SectionHeader(
                title: 'Heute',
                subtitle:
                    'Filialbetrieb, Ausnahmen und Entscheidungen für den laufenden Tag.',
                breadcrumbs: const [BreadcrumbItem(label: 'Heute')],
                onBack: canNavigateBack ? onNavigateBack : null,
              ),
              SizedBox(height: spacing.lg),
              _PlannerHeroCardV2(
                activeMembers: activeMembers,
                todayShiftCount: todayShifts.length,
                pendingAbsenceCount: pendingAbsences.length,
                pendingSwapCount: pendingSwapRequests.length,
                siteCount: todaySites.toSet().length,
              ),
              SizedBox(height: spacing.md),
              const DashboardActionItemsCard(parentLabel: 'Heute'),
              AdaptiveCardGrid(
                minItemWidth: 180,
                children: [
                  AppQuickActionCard(
                    icon: Icons.view_timeline_outlined,
                    title: 'Plan öffnen',
                    subtitle: 'Direkt in die mobile Tagesplanung springen',
                    onTap: onOpenPlan,
                  ),
                  if (currentUser?.isAdmin ?? false)
                    AppQuickActionCard(
                      icon: Icons.groups_outlined,
                      title: 'Team verwalten',
                      subtitle: 'Standorte, Rollen und Qualifikationen pflegen',
                      onTap: () => context.push(AppRoutes.team),
                    ),
                  AppQuickActionCard(
                    icon: Icons.inbox_outlined,
                    title: 'Anfragen prüfen',
                    subtitle:
                        'Krankmeldungen und Tausch ohne Umwege entscheiden',
                    // Tab-Ziel -> go (Branch wechseln), nicht push (kein Duplikat).
                    onTap: () => context.go(shellTabPaths[ShellTab.inbox]!),
                  ),
                ],
              ),
              SizedBox(height: spacing.md),
              AdaptiveCardGrid(
                minItemWidth: 155,
                children: [
                  AppMetricCard(
                    label: 'Aktive Mitarbeiter',
                    value: '$activeMembers',
                    icon: Icons.people_alt_outlined,
                  ),
                  AppMetricCard(
                    label: 'Offene Einladungen',
                    value: '${team.invites.length}',
                    icon: Icons.mark_email_unread_outlined,
                  ),
                  AppMetricCard(
                    label: 'Schichten heute',
                    value: '${todayShifts.length}',
                    icon: Icons.view_timeline_outlined,
                  ),
                  AppMetricCard(
                    label: 'Erledigt',
                    value: '$completedToday / ${todayShifts.length}',
                    icon: Icons.check_circle_outline,
                  ),
                  AppMetricCard(
                    label: 'Noch offen',
                    value: '$openToday',
                    icon: Icons.pending_actions_outlined,
                  ),
                  AppMetricCard(
                    label: 'Offene Abwesenheiten',
                    value: '${pendingAbsences.length}',
                    icon: Icons.event_note_outlined,
                  ),
                ],
              ),
              SizedBox(height: spacing.lg),
              AppSectionCard(
                title: 'Heute priorisieren',
                child: Column(
                  children: [
                    _ActionStateTile(
                      icon: Icons.warning_amber_rounded,
                      title:
                          '${pendingAbsences.length + pendingSwapRequests.length} Entscheidungen offen',
                      subtitle:
                          'Abwesenheiten und Tauschanfragen sollten vor der nächsten Schicht geklärt werden.',
                      color: colorScheme.tertiary,
                      onTap: (pendingAbsences.isEmpty &&
                              pendingSwapRequests.isEmpty)
                          ? null
                          : () => context.go(shellTabPaths[ShellTab.inbox]!),
                    ),
                    const Divider(height: 20),
                    _ActionStateTile(
                      icon: Icons.person_off_outlined,
                      title:
                          '${unassignedToday.length} freie oder unbesetzte Schichten',
                      subtitle:
                          'Nicht zugewiesene Dienste fallen im Tagesbetrieb sofort auf.',
                      color: colorScheme.error,
                    ),
                  ],
                ),
              ),
              SizedBox(height: spacing.lg),
              AppSectionCard(
                title: 'Nächste Schichten',
                child: upcomingShifts.isEmpty
                    ? const EmptyState(
                        icon: Icons.event_busy_outlined,
                        message: 'Keine Schichten im aktuellen Planungsfenster.',
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
              SizedBox(height: spacing.lg),
              AppSectionCard(
                title: 'Nächste Entscheidungen',
                child: _ManagerDecisionList(
                  pendingAbsences: pendingAbsences,
                  pendingSwapRequests: pendingSwapRequests,
                  onOpenDecision: () =>
                      context.go(shellTabPaths[ShellTab.inbox]!),
                ),
              ),
              SizedBox(height: spacing.lg),
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

/// V2-Hero des Admin-Dashboards (Akzent-Tonalitaet), gleiche Kennzahl-Texte wie
/// [_PlannerHeroCard].
class _PlannerHeroCardV2 extends StatelessWidget {
  const _PlannerHeroCardV2({
    required this.activeMembers,
    required this.todayShiftCount,
    required this.pendingAbsenceCount,
    required this.pendingSwapCount,
    required this.siteCount,
  });

  final int activeMembers;
  final int todayShiftCount;
  final int pendingAbsenceCount;
  final int pendingSwapCount;
  final int siteCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final spacing = context.spacing;
    return AppHeroCard(
      tone: AppHeroTone.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Filialbetrieb im Blick',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: spacing.sm),
          Text(
            '$todayShiftCount Schichten heute in $siteCount Standorten. '
            '$pendingAbsenceCount Abwesenheiten und $pendingSwapCount Tausch-Anfragen brauchen Aufmerksamkeit.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: spacing.md - spacing.xxs),
          Wrap(
            spacing: spacing.sm + spacing.xxs,
            runSpacing: spacing.sm + spacing.xxs,
            children: [
              InfoChip(
                icon: Icons.people_alt_outlined,
                label: '$activeMembers aktiv',
              ),
              InfoChip(
                icon: Icons.event_note_outlined,
                label: '$pendingAbsenceCount offen',
              ),
              InfoChip(icon: Icons.swap_horiz, label: '$pendingSwapCount Tausch'),
            ],
          ),
        ],
      ),
    );
  }
}
