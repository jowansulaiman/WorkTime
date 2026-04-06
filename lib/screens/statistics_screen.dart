import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/work_provider.dart';
import '../services/download_service.dart';
import '../theme/app_theme.dart';
import '../widgets/breadcrumb_app_bar.dart';

class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({
    super.key,
    this.parentLabel = 'Profil',
  });

  final String parentLabel;

  @override
  Widget build(BuildContext context) {
    final work = context.watch<WorkProvider>();
    final currentUser = work.currentUser;
    final entries = work.entries;
    final settings = work.settings;
    final selectedMonth = work.selectedMonth;

    if (!(currentUser?.canViewReports ?? false)) {
      return Scaffold(
        appBar: BreadcrumbAppBar(
          breadcrumbs: [
            BreadcrumbItem(
              label: parentLabel,
              onTap: () => Navigator.of(context).pop(),
            ),
            const BreadcrumbItem(label: 'Statistik'),
          ],
        ),
        body: const SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Die Statistik ist fuer dieses Profil deaktiviert.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    final totalHours = work.totalHoursThisMonth;
    final overtime = work.overtimeThisMonth;
    final workingDays = entries
        .map((e) => '${e.date.year}-${e.date.month}-${e.date.day}')
        .toSet()
        .length;
    final targetHours = workingDays * settings.dailyHours;

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: parentLabel,
            onTap: () => Navigator.of(context).pop(),
          ),
          const BreadcrumbItem(label: 'Statistik'),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _HeaderSection(
                  title: 'Statistik',
                  subtitle:
                      'Auswertungen und Diagramme fuer ${DateFormat('MMMM yyyy', 'de_DE').format(selectedMonth)}.',
                ),
                const SizedBox(height: 20),

                // Summary cards
                _SummaryCardsRow(
                  totalHours: totalHours,
                  overtime: overtime,
                  workingDays: workingDays,
                ),
                const SizedBox(height: 20),

                // Overtime traffic light
                _OvertimeTrafficLight(
                  totalHours: totalHours,
                  targetHours: targetHours,
                  dailyHours: settings.dailyHours,
                ),
                const SizedBox(height: 20),

                // Monthly hours bar chart
                _SectionCard(
                  title: 'Stunden pro Tag',
                  child: _MonthlyHoursChart(
                    entries: entries,
                    selectedMonth: selectedMonth,
                  ),
                ),
                const SizedBox(height: 20),

                // Year overview
                _SectionCard(
                  title: 'Jahresuebersicht ${selectedMonth.year}',
                  child: _YearOverviewChart(
                    work: work,
                  ),
                ),
                const SizedBox(height: 20),

                // CSV export
                Center(
                  child: FilledButton.icon(
                    onPressed: () => _exportCsv(context, work),
                    icon: const Icon(Icons.download),
                    label: const Text('CSV exportieren'),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _escapeCsvField(String value) {
    if (value.contains(';') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  Future<void> _exportCsv(BuildContext context, WorkProvider work) async {
    final entries = work.entries;
    if (entries.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Keine Eintraege zum Exportieren vorhanden.')),
        );
      }
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('Datum;Start;Ende;Pause (min);Stunden;Notiz');
    final dateFmt = DateFormat('dd.MM.yyyy');
    final timeFmt = DateFormat('HH:mm');
    for (final entry in entries) {
      final note = _escapeCsvField(entry.note ?? '');
      buffer.writeln(
        '${dateFmt.format(entry.date)};${timeFmt.format(entry.startTime)};${timeFmt.format(entry.endTime)};${entry.breakMinutes};${entry.workedHours.toStringAsFixed(2)};$note',
      );
    }
    final bytes = buffer.toString().codeUnits;
    await downloadPdfBytes(
      bytes: Uint8List.fromList(bytes),
      fileName:
          'arbeitszeit-${DateFormat('yyyy-MM').format(work.selectedMonth)}.csv',
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable layout widgets (mirroring home_screen.dart patterns)
// ---------------------------------------------------------------------------

class _HeaderSection extends StatelessWidget {
  const _HeaderSection({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary cards
// ---------------------------------------------------------------------------

class _SummaryCardsRow extends StatelessWidget {
  const _SummaryCardsRow({
    required this.totalHours,
    required this.overtime,
    required this.workingDays,
  });

  final double totalHours;
  final double overtime;
  final int workingDays;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;
        final cards = [
          _MetricCard(
            label: 'Gesamtstunden',
            value: '${totalHours.toStringAsFixed(1)} h',
            icon: Icons.access_time,
          ),
          _MetricCard(
            label: 'Ueberstunden',
            value: '${overtime.toStringAsFixed(1)} h',
            icon: Icons.trending_up,
          ),
          _MetricCard(
            label: 'Arbeitstage',
            value: '$workingDays',
            icon: Icons.calendar_today,
          ),
        ];

        if (isWide) {
          return Row(
            children: cards.map((card) => Expanded(child: card)).toList(),
          );
        }
        return Column(children: cards);
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colorScheme.primary),
            const SizedBox(height: 10),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overtime traffic light
// ---------------------------------------------------------------------------

class _OvertimeTrafficLight extends StatelessWidget {
  const _OvertimeTrafficLight({
    required this.totalHours,
    required this.targetHours,
    required this.dailyHours,
  });

  final double totalHours;
  final double targetHours;
  final double dailyHours;

  @override
  Widget build(BuildContext context) {
    final diff = totalHours - targetHours;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = theme.appColors;
    // Threshold: within one daily shift of target is "yellow"
    final Color statusColor;
    final String statusLabel;
    final IconData statusIcon;

    if (diff <= 0) {
      statusColor = appColors.success;
      statusLabel = 'Im Soll';
      statusIcon = Icons.check_circle;
    } else if (diff <= dailyHours) {
      statusColor = appColors.warning;
      statusLabel = 'Nahe am Soll (+${diff.toStringAsFixed(1)} h)';
      statusIcon = Icons.warning_amber_rounded;
    } else {
      statusColor = colorScheme.error;
      statusLabel = 'Ueberstunden (+${diff.toStringAsFixed(1)} h)';
      statusIcon = Icons.error;
    }

    return Card(
      color: statusColor.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.18 : 0.1,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(statusIcon, color: statusColor, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ueberstunden-Status',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    statusLabel,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  Text(
                    '${totalHours.toStringAsFixed(1)} h von ${targetHours.toStringAsFixed(1)} h Soll',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Monthly hours bar chart (hours per day)
// ---------------------------------------------------------------------------

class _MonthlyHoursChart extends StatelessWidget {
  const _MonthlyHoursChart({
    required this.entries,
    required this.selectedMonth,
  });

  final List entries;
  final DateTime selectedMonth;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final axisStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        );
    final tooltipBackground = colorScheme.inverseSurface;
    final tooltipForeground = colorScheme.onInverseSurface;
    final gridColor = colorScheme.outlineVariant.withValues(alpha: 0.65);
    final daysInMonth =
        DateTime(selectedMonth.year, selectedMonth.month + 1, 0).day;

    // Aggregate hours per day
    final hoursPerDay = List<double>.filled(daysInMonth, 0);
    for (final entry in entries) {
      final day = entry.date.day;
      if (day >= 1 && day <= daysInMonth) {
        hoursPerDay[day - 1] += entry.workedHours;
      }
    }

    final maxY = hoursPerDay.fold<double>(0, (a, b) => a > b ? a : b);
    final ceilingY = maxY < 1 ? 10.0 : (maxY + 2).ceilToDouble();

    if (entries.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: Text('Keine Daten fuer diesen Monat vorhanden.'),
        ),
      );
    }

    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: ceilingY,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => tooltipBackground,
              tooltipPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              tooltipMargin: 8,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final day = group.x + 1;
                return BarTooltipItem(
                  '$day. ${hoursPerDay[group.x].toStringAsFixed(1)} h',
                  TextStyle(
                    color: tooltipForeground,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final day = value.toInt() + 1;
                  // Show every 5th day and the 1st
                  if (day == 1 || day % 5 == 0) {
                    return SideTitleWidget(
                      axisSide: meta.axisSide,
                      child: Text(
                        '$day',
                        style: axisStyle,
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                getTitlesWidget: (value, meta) {
                  if (value == meta.max || value == meta.min) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(
                      '${value.toInt()}h',
                      style: axisStyle,
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: ceilingY > 12 ? 4 : 2,
            getDrawingHorizontalLine: (_) => FlLine(
              color: gridColor,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(daysInMonth, (i) {
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: hoursPerDay[i],
                  color: colorScheme.primary,
                  width: daysInMonth > 28 ? 6 : 8,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(3),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Year overview bar chart (hours per month)
// ---------------------------------------------------------------------------

class _YearOverviewChart extends StatelessWidget {
  const _YearOverviewChart({required this.work});

  final WorkProvider work;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final axisStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        );
    final tooltipBackground = colorScheme.inverseSurface;
    final tooltipForeground = colorScheme.onInverseSurface;
    final gridColor = colorScheme.outlineVariant.withValues(alpha: 0.65);
    final entries = work.entries;
    final selectedMonth = work.selectedMonth;
    final year = selectedMonth.year;

    // We only have the currently loaded month's entries. Build a sparse chart
    // showing the loaded month and zeroes elsewhere. A more complete
    // implementation would load all months, but the provider scopes data to
    // the selected month, so we display what is available.
    final hoursPerMonth = List<double>.filled(12, 0);
    for (final entry in entries) {
      if (entry.date.year == year) {
        hoursPerMonth[entry.date.month - 1] += entry.workedHours;
      }
    }

    final maxY = hoursPerMonth.fold<double>(0, (a, b) => a > b ? a : b);
    final ceilingY = maxY < 1 ? 200.0 : (maxY * 1.2).ceilToDouble();

    final monthLabels = [
      'Jan',
      'Feb',
      'Mrz',
      'Apr',
      'Mai',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Okt',
      'Nov',
      'Dez',
    ];

    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: ceilingY,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => tooltipBackground,
              tooltipPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              tooltipMargin: 8,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  '${monthLabels[group.x]}: ${hoursPerMonth[group.x].toStringAsFixed(1)} h',
                  TextStyle(
                    color: tooltipForeground,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index >= 0 && index < 12) {
                    return SideTitleWidget(
                      axisSide: meta.axisSide,
                      child: Text(
                        monthLabels[index],
                        style: axisStyle,
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (value, meta) {
                  if (value == meta.max || value == meta.min) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(
                      '${value.toInt()}h',
                      style: axisStyle,
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: ceilingY > 100 ? 40 : 20,
            getDrawingHorizontalLine: (_) => FlLine(
              color: gridColor,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(12, (i) {
            final isCurrentMonth = i == (selectedMonth.month - 1);
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: hoursPerMonth[i],
                  color: isCurrentMonth
                      ? colorScheme.primary
                      : colorScheme.primary.withValues(alpha: 0.35),
                  width: 14,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(3),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}
