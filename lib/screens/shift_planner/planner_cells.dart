// Teil von shift_planner_screen.dart (split-shift-planner-god-file, Strangler Schritt 2).
//
// Enthält die BuildContext-armen Leaf-Cell-Widgets des Schichtplan-Boards
// (_PlannerBoardRowData, _PlannerDayHeaderCell, _PlannerBoardShiftCard,
// _PlannerAbsencePill, _DashedRoundedBorderPainter) plus die reinen Farb-Helfer.
// Als 'part' gehalten, damit die file-private Sichtbarkeit erhalten bleibt und
// keine Imports dupliziert werden (die Library-Imports der Hauptdatei gelten).
part of '../shift_planner_screen.dart';

/// Gemeinsame Mindesthöhe der Board-Kopfzeile (Tages-Header + linke
/// SCHICHT-Zelle). Die Kopfzeile wächst intrinsisch mit der Textskalierung
/// (`IntrinsicHeight` in `_buildHeaderRow`) — die frühere feste Höhe 78
/// erzeugte ab textScale 1.0 einen RenderFlex-Overflow (Plan W5, Befund
/// „1-px-Overflow bewiesen").
const double _plannerHeaderRowMinHeight = 78.0;

/// Stunden-Format der Board-Pillen/Badges: ganzzahlig ohne Nachkommastelle,
/// sonst eine Nachkommastelle mit de_DE-Komma („7,5").
String _formatPlannerHours(double hours) {
  final rounded = (hours * 10).round() / 10;
  if (rounded == rounded.roundToDouble()) {
    return rounded.round().toString();
  }
  return rounded.toStringAsFixed(1).replaceFirst('.', ',');
}

String _formatOvertimeHours(int minutes) => _formatPlannerHours(minutes / 60);

class _PlannerBoardRowData {
  const _PlannerBoardRowData({
    required this.id,
    required this.title,
    required this.avatarLabel,
    this.memberId,
    this.location,
    this.subtitle,
    this.targetHours,
    this.weeklyMaxHours,
  });

  factory _PlannerBoardRowData.employee(
    AppUserProfile member, {
    double? targetHours,
    double? weeklyMaxHours,
  }) {
    final title = member.displayName;
    return _PlannerBoardRowData(
      id: member.uid,
      title: title,
      memberId: member.uid,
      avatarLabel: title.characters.take(1).toString().toUpperCase(),
      targetHours: targetHours,
      weeklyMaxHours: weeklyMaxHours,
      subtitle: member.role.label,
    );
  }

  factory _PlannerBoardRowData.fallbackEmployee({
    required String userId,
    required String employeeName,
    double? targetHours,
    double? weeklyMaxHours,
  }) {
    final title = employeeName.trim().isEmpty ? 'Unbekannt' : employeeName;
    return _PlannerBoardRowData(
      id: userId,
      title: title,
      memberId: userId,
      avatarLabel: title.characters.take(1).toString().toUpperCase(),
      targetHours: targetHours,
      weeklyMaxHours: weeklyMaxHours,
    );
  }

  factory _PlannerBoardRowData.location(String location) {
    final avatarLabel = location.characters.take(1).toString().toUpperCase();
    return _PlannerBoardRowData(
      id: 'location-$location',
      title: location,
      location: location == 'Ohne Standort' ? null : location,
      avatarLabel: avatarLabel,
      subtitle: 'Standort',
    );
  }

  final String id;
  final String title;
  final String avatarLabel;
  final String? memberId;
  final String? location;
  final String? subtitle;

  /// Wochen-Sollstunden der Pille (Sollzeit-Profil → Vertrag → Settings, W5).
  /// `null` bei Standort-Zeilen → neutrale Pille nur mit Ist.
  final double? targetHours;

  /// Vertragliche Wochen-Maximalstunden (`EmploymentContract.weeklyMaxHours`);
  /// Ist darüber → „ÜS“-Badge. `null` = keine Grenze bekannt.
  final double? weeklyMaxHours;

  bool matches(Shift shift) {
    if (memberId != null) {
      return shift.userId == memberId;
    }
    final normalized = location?.trim();
    final effectiveShiftLocation = shift.effectiveSiteLabel?.trim();
    if (normalized == null || normalized.isEmpty) {
      return effectiveShiftLocation == null || effectiveShiftLocation.isEmpty;
    }
    return effectiveShiftLocation == normalized;
  }

}

class _PlannerDayHeaderCell extends StatelessWidget {
  const _PlannerDayHeaderCell({
    required this.day,
    required this.width,
    required this.noteCount,
    required this.onTapNote,
  });

  final DateTime day;
  final double width;
  final int noteCount;
  final VoidCallback onTapNote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = theme.appColors;
    return Container(
      width: width,
      // Intrinsisches Layout statt fester Höhe: die Kopfzeile wächst mit der
      // Textskalierung (IntrinsicHeight in _buildHeaderRow), minHeight hält
      // die bisherige Optik bei kleiner Schrift (Overflow-Fix W5).
      constraints:
          const BoxConstraints(minHeight: _plannerHeaderRowMinHeight),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: colorScheme.outlineVariant),
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('EEE, dd. MMM', 'de_DE').format(day).toUpperCase(),
            style: theme.textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          InkWell(
            onTap: onTapNote,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              // Größeres Tap-Ziel (vorher nur Texthöhe).
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      noteCount > 0 ? '$noteCount Anmerkungen' : 'Anmerkungen',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: appColors.info,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.help_outline_rounded,
                    size: 14,
                    color: appColors.info,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _PlannerBoardShiftCard extends StatelessWidget {
  const _PlannerBoardShiftCard({
    required this.shift,
    required this.sameBucketCount,
    required this.onTap,
    required this.onDelete,
    this.onDeleteSeries,
    this.onCopyToDays,
  });

  final Shift shift;
  final int sameBucketCount;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback? onDeleteSeries;
  final VoidCallback? onCopyToDays;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = _resolveShiftColor(shift, theme);
    final titleStyle = theme.textTheme.labelLarge?.copyWith(
      color: baseColor,
      fontWeight: FontWeight.w700,
    );
    // 24h-Format mit Minuten in de_DE (vorher 'h a'/en_US -> "10 AM" und ohne
    // Minuten; verstiess gegen die de_DE-Invariante, probleme #15).
    final timeFmt = DateFormat('HH:mm', 'de_DE');
    // RepaintBoundary isoliert den per-Frame neu malenden Strichrahmen-Painter
    // (no-repaintboundary-shift-cards) vom restlichen Board beim Scrollen.
    return RepaintBoundary(
      child: CustomPaint(
        painter: _DashedRoundedBorderPainter(
          color: baseColor.withValues(alpha: 0.38),
        ),
        child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: _softenColor(
              baseColor,
              theme.colorScheme.surfaceContainerLowest,
              0.88,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border(
              left: BorderSide(color: baseColor, width: 4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      shift.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                  ),
                  if (sameBucketCount > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: baseColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$sameBucketCount',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: baseColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    // Größeres Tap-Ziel (vorher ~16px) — dichte Board-Karten,
                    // daher 40dp als Kompromiss statt der winzigen Icon-Fläche.
                    constraints:
                        const BoxConstraints(minWidth: 40, minHeight: 40),
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          onTap();
                        case 'copy_days':
                          onCopyToDays?.call();
                        case 'delete':
                          onDelete();
                        case 'delete_series':
                          onDeleteSeries?.call();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Bearbeiten'),
                      ),
                      if (onCopyToDays != null)
                        const PopupMenuItem(
                          value: 'copy_days',
                          child: Text('Kopieren (Mitarbeiter/Tage) ...'),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Einzeln löschen'),
                      ),
                      if (onDeleteSeries != null)
                        const PopupMenuItem(
                          value: 'delete_series',
                          child: Text('Serie löschen'),
                        ),
                    ],
                    child: const Center(
                      child: Icon(Icons.more_horiz, size: 20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${timeFmt.format(shift.startTime)} - ${timeFmt.format(shift.endTime)} · ${shift.workedHours.toStringAsFixed(0)}h',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                shift.effectiveSiteLabel?.trim().isNotEmpty == true
                    ? shift.effectiveSiteLabel!
                    : (shift.team?.trim().isNotEmpty == true
                        ? shift.team!
                        : 'Ohne Standort'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (shift.hasPlannedOvertime) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _PlannerOvertimeBadge(
                    overtimeMinutes: shift.overtimeMinutes,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      ),
    );
  }
}

/// Kleines Überstunden-Badge („+X,Xh ÜS“) für Schichtkarten/Monats-Tiles:
/// zeigt die am Shift persistierten **geplanten** Überstunden (E1) in
/// `appColors.warning` mit erklärendem Tooltip. [compact] lässt den
/// Stunden-Anteil weg (sehr enge Monats-Kacheln).
class _PlannerOvertimeBadge extends StatelessWidget {
  const _PlannerOvertimeBadge({
    required this.overtimeMinutes,
    this.compact = false,
  });

  final int overtimeMinutes;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warning = theme.appColors.warning;
    final hours = _formatOvertimeHours(overtimeMinutes);
    return Tooltip(
      message: 'Geplante Überstunden: $hours Std',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 4 : 6,
          vertical: compact ? 1 : 2,
        ),
        decoration: BoxDecoration(
          color: warning.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          compact ? 'ÜS' : '+${hours}h ÜS',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: warning,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _PlannerAbsencePill extends StatelessWidget {
  const _PlannerAbsencePill({
    required this.absence,
    this.showEmployeeName = false,
    this.compact = false,
  });

  final AbsenceRequest absence;
  final bool showEmployeeName;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dateFmt = DateFormat('dd.MM.yyyy', 'de_DE');
    final colors = switch (absence.status) {
      AbsenceStatus.pending => (
          background: colorScheme.secondaryContainer,
          foreground: colorScheme.onSecondaryContainer,
          accent: colorScheme.secondary,
        ),
      AbsenceStatus.approved => (
          background: colorScheme.tertiaryContainer,
          foreground: colorScheme.onTertiaryContainer,
          accent: colorScheme.tertiary,
        ),
      AbsenceStatus.rejected => (
          background: colorScheme.surfaceContainerHigh,
          foreground: colorScheme.onSurfaceVariant,
          accent: colorScheme.outline,
        ),
    };
    final icon = switch (absence.type) {
      AbsenceType.vacation => Icons.beach_access_rounded,
      AbsenceType.sickness || AbsenceType.childSick => Icons.healing_rounded,
      _ => Icons.block_rounded,
    };
    final label = showEmployeeName
        ? '${absence.employeeName}: ${absence.type.label} · ${absence.status.label}'
        : '${absence.type.label} · ${absence.status.label}';
    final tooltip = StringBuffer()
      ..write(label)
      ..write('\n')
      ..write(dateFmt.format(absence.startDate))
      ..write(' - ')
      ..write(dateFmt.format(absence.endDate));
    if (absence.note != null && absence.note!.trim().isNotEmpty) {
      tooltip
        ..write('\n')
        ..write(absence.note!.trim());
    }

    return Tooltip(
      message: tooltip.toString(),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: compact ? double.infinity : 320,
        ),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10,
            vertical: compact ? 6 : 7,
          ),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colors.accent.withValues(alpha: 0.22),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Icon(
                icon,
                size: compact ? 14 : 16,
                color: colors.accent,
              ),
              const SizedBox(width: 6),
              if (compact)
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedRoundedBorderPainter extends CustomPainter {
  _DashedRoundedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = Radius.circular(14);
    const dashWidth = 6.0;
    const dashSpace = 4.0;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, radius);
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (final metric in metrics) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0.0, metric.length)),
          paint,
        );
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundedBorderPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

/// Schichtkarte der mobilen Tagesliste (Tag/Woche < 840 dp, E6): Avatar/
/// Initiale, Name bzw. „Offene Schicht“, Zeitbereich, Standort, Status- und
/// ÜS-Badge. Tap = bestehender Editor-Flow; freie Schichten tragen zusätzlich
/// eine „Besetzen“-Affordanz (gleicher Tap-Flow).
class _PlannerMobileShiftCard extends StatelessWidget {
  const _PlannerMobileShiftCard({
    required this.shift,
    required this.onTap,
  });

  final Shift shift;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final baseColor = _resolveShiftColor(shift, theme);
    final timeFmt = DateFormat('HH:mm', 'de_DE');
    final isFree = shift.isUnassigned;
    final name = isFree ? 'Offene Schicht' : shift.employeeName;
    final initial = name.trim().isEmpty
        ? '?'
        : name.trim().characters.take(1).toString().toUpperCase();
    final site = shift.effectiveSiteLabel?.trim().isNotEmpty == true
        ? shift.effectiveSiteLabel!
        : (shift.team?.trim().isNotEmpty == true
            ? shift.team!
            : 'Ohne Standort');
    final statusTone = switch (shift.status) {
      ShiftStatus.planned => AppStatusTone.info,
      ShiftStatus.confirmed => AppStatusTone.success,
      ShiftStatus.completed => AppStatusTone.neutral,
      ShiftStatus.cancelled => AppStatusTone.error,
    };

    return Material(
      color: colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: baseColor.withValues(alpha: 0.16),
                foregroundColor: baseColor,
                child: isFree
                    ? Icon(
                        Icons.person_add_alt,
                        size: 18,
                        color: baseColor,
                      )
                    : Text(
                        initial,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (isFree) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Besetzen',
                                  style:
                                      theme.textTheme.labelMedium?.copyWith(
                                    color: colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 16,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      shift.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: baseColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${timeFmt.format(shift.startTime)} - '
                      '${timeFmt.format(shift.endTime)} · '
                      '${_formatPlannerHours(shift.workedHours)}h',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      site,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        AppStatusBadge(
                          label: shift.status.label,
                          tone: statusTone,
                        ),
                        if (shift.hasPlannedOvertime)
                          _PlannerOvertimeBadge(
                            overtimeMinutes: shift.overtimeMinutes,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _plannerAvatarColor(ThemeData theme, _PlannerBoardRowData row) {
  final appColors = theme.appColors;
  final palette = [
    theme.colorScheme.primary,
    theme.colorScheme.secondary,
    appColors.success,
    theme.colorScheme.tertiary,
    appColors.info,
  ];
  if (row.location != null || row.id.startsWith('location-')) {
    return appColors.info;
  }
  final index = row.id.hashCode.abs() % palette.length;
  return palette[index];
}

Color _resolveShiftColor(Shift shift, ThemeData theme) {
  final parsed = tryParseHexColor(shift.color);
  if (parsed != null) {
    return parsed;
  }
  final palette = [
    theme.appColors.success,
    theme.colorScheme.primary,
    theme.colorScheme.secondary,
    theme.colorScheme.tertiary,
    theme.appColors.info,
  ];
  final index = shift.title.hashCode.abs() % palette.length;
  return palette[index];
}

Color _softenColor(Color color, Color surface, double amount) {
  return Color.lerp(color, surface, amount) ?? color;
}
