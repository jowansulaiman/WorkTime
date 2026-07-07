import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/shift.dart';
import '../../providers/work_provider.dart';
import '../../routing/shell_tab.dart';
import '../../ui/ui.dart';

/// Rollen-adaptiver Einstieg in die **Zeitwirtschaft** (Meilenstein M1).
///
/// Bildet den `/zeit`-Tab-Inhalt (ersetzt die frühere Monats-Zeiterfassung, die
/// jetzt unter [AppRoutes.zeitErfassung] erreichbar ist) und spiegelt AllTecs
/// Zeitwirtschafts-Dashboard: eine Kennzahl-Reihe (Soll/Ist, Überstunden) plus
/// ein Kachel-Grid zu den acht Bereichen. Admin-Kacheln (Mitarbeiterabschluss,
/// Lohnlauf) sind nur für Admins sichtbar.
///
/// Reine Lese-Ansicht — KPI kommen aus den bereits vorhandenen, mitarbeiter-
/// sichtbaren Daten (`WorkProvider`-Getter + geplante Schichten); das
/// persistente Stundenkonto/Resturlaub liegt im Stundenkonto-Bereich.
class ZeitwirtschaftHubScreen extends StatefulWidget {
  const ZeitwirtschaftHubScreen({
    super.key,
    this.canNavigateBack = false,
    this.onNavigateBack,
  });

  final bool canNavigateBack;
  final VoidCallback? onNavigateBack;

  @override
  State<ZeitwirtschaftHubScreen> createState() =>
      _ZeitwirtschaftHubScreenState();
}

class _ZeitwirtschaftHubScreenState extends State<ZeitwirtschaftHubScreen> {
  Future<List<Shift>>? _monthShiftsFuture;
  String? _monthShiftsKey;

  static final _monthFormat = DateFormat('MMMM yyyy', 'de_DE');

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
    final currentUser = provider.currentUser;

    if (currentUser == null) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (!currentUser.canViewTimeTracking) {
      return SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: EdgeInsets.all(context.spacing.lg),
              child: SectionCard(
                title: 'Kein Zugriff',
                child: Text(
                  'Die Zeitwirtschaft ist für dieses Profil deaktiviert. '
                  'Ein Admin kann den Bereich bei Bedarf wieder freischalten.',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            ),
          ),
        ),
      );
    }

    _refreshMonthShiftsFuture(provider);
    final isAdmin = currentUser.isAdmin;
    final canManageShifts = currentUser.canManageShifts;
    final spacing = context.spacing;

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: FutureBuilder<List<Shift>>(
            future: _monthShiftsFuture,
            builder: (context, snapshot) {
              final monthShifts = snapshot.data ?? const <Shift>[];
              final plannedHours = monthShifts.fold<double>(
                0,
                (sum, shift) => sum + shift.workedHours,
              );
              final loadingPlanned = snapshot.connectionState ==
                      ConnectionState.waiting &&
                  !snapshot.hasData;

              return ListView(
                padding: EdgeInsets.fromLTRB(
                  spacing.md,
                  spacing.md,
                  spacing.md,
                  spacing.xl,
                ),
                children: [
                  SectionHeader(
                    title: 'Zeitwirtschaft',
                    subtitle:
                        'Kommen/Gehen, Zeiterfassung, Stundenkonto, Abwesenheiten und Abschlüsse — an einem Ort.',
                    breadcrumbs: const [BreadcrumbItem(label: 'Zeit')],
                    onBack:
                        widget.canNavigateBack ? widget.onNavigateBack : null,
                  ),
                  SizedBox(height: spacing.md),
                  _MonthNavigation(
                    label: _monthFormat.format(provider.selectedMonth),
                    onPrevious: provider.previousMonth,
                    onNext: provider.nextMonth,
                  ),
                  SizedBox(height: spacing.md),
                  AppComparisonStatCard(
                    plannedHours: plannedHours > 0 ? plannedHours : null,
                    actualHours: provider.totalHoursThisMonth,
                    loading: loadingPlanned,
                  ),
                  SizedBox(height: spacing.sm + spacing.xs),
                  AppMetricCard(
                    label: 'Überstunden (Monat)',
                    value: _signedHours(provider.overtimeThisMonth),
                    icon: Icons.trending_up,
                  ),
                  SizedBox(height: spacing.lg),
                  _HubTileGrid(
                      isAdmin: isAdmin, canManageShifts: canManageShifts),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

String _signedHours(double value) {
  final prefix = value > 0.05 ? '+' : '';
  return '$prefix${value.toStringAsFixed(1)} h';
}

class _MonthNavigation extends StatelessWidget {
  const _MonthNavigation({
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
            child: Text(
              label,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
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

/// Gruppen des Hub-Kachel-Grids (ZV-6.2): rollengerechte Bündelung statt acht
/// gleichrangiger Kacheln. Nicht berechtigte Gruppen werden ausgeblendet.
enum _HubGroup { meinTag, meineKonten, teamAbschluss }

extension _HubGroupLabel on _HubGroup {
  String get label => switch (this) {
        _HubGroup.meinTag => 'Mein Tag',
        _HubGroup.meineKonten => 'Meine Konten',
        _HubGroup.teamAbschluss => 'Team & Abschluss',
      };
}

/// Eintrag im Kachel-Grid des Hubs.
class _HubDestination {
  const _HubDestination({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
    required this.group,
    this.adminOnly = false,
    this.reviewerOnly = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  final _HubGroup group;
  final bool adminOnly;

  /// Sichtbar für Freigeber (Admin **und** Teamleiter, `canManageShifts`) —
  /// Zeit-Freigabe (Z7/E2). Vs. [adminOnly] = nur Admin.
  final bool reviewerOnly;
}

const List<_HubDestination> _hubDestinations = [
  _HubDestination(
    icon: Icons.login,
    title: 'Kommen und Gehen',
    subtitle: 'Ein- und ausstempeln, laufende Buchung',
    route: AppRoutes.zeitStempeln,
    group: _HubGroup.meinTag,
  ),
  _HubDestination(
    icon: Icons.edit_calendar,
    title: 'Zeiterfassung',
    subtitle: 'Arbeitszeiten, Urlaub und Krankmeldungen',
    route: AppRoutes.zeitErfassung,
    group: _HubGroup.meinTag,
  ),
  _HubDestination(
    icon: Icons.beach_access,
    title: 'Abwesenheiten',
    subtitle: 'Urlaub, Krankheit und Anträge',
    route: AppRoutes.zeitAbwesenheiten,
    group: _HubGroup.meinTag,
  ),
  _HubDestination(
    icon: Icons.account_balance_wallet,
    title: 'Stundenkonto',
    subtitle: 'Soll, Ist, Saldo und Überstunden',
    route: AppRoutes.zeitStundenkonto,
    group: _HubGroup.meineKonten,
  ),
  _HubDestination(
    icon: Icons.calendar_month,
    title: 'Abwesenheitskalender',
    subtitle: 'Monatsübersicht aller Abwesenheiten',
    route: AppRoutes.zeitAbwesenheitenKalender,
    group: _HubGroup.meineKonten,
  ),
  _HubDestination(
    icon: Icons.event_available,
    title: 'Mein Monatsabschluss',
    subtitle: 'Eigenes Stundenkonto abschließen',
    route: AppRoutes.zeitMonatsabschluss,
    group: _HubGroup.meineKonten,
  ),
  _HubDestination(
    icon: Icons.fact_check,
    title: 'Mitarbeiterabschluss',
    subtitle: 'Monatsabschlüsse aller Mitarbeiter',
    route: AppRoutes.zeitMitarbeiterabschluss,
    group: _HubGroup.teamAbschluss,
    reviewerOnly: true,
  ),
  _HubDestination(
    icon: Icons.payments,
    title: 'Lohnlauf',
    subtitle: 'Monatliche Lohnabrechnung im Batch',
    route: AppRoutes.zeitLohnlauf,
    group: _HubGroup.teamAbschluss,
    adminOnly: true,
  ),
];

class _HubTileGrid extends StatelessWidget {
  const _HubTileGrid({required this.isAdmin, required this.canManageShifts});

  final bool isAdmin;
  final bool canManageShifts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = context.spacing;
    final sections = <Widget>[];
    for (final group in _HubGroup.values) {
      final tiles = _hubDestinations
          .where((d) =>
              d.group == group &&
              (isAdmin || !d.adminOnly) &&
              (canManageShifts || !d.reviewerOnly))
          .toList(growable: false);
      if (tiles.isEmpty) continue; // Leere (nicht berechtigte) Gruppe ausblenden.
      if (sections.isNotEmpty) {
        sections.add(SizedBox(height: spacing.lg));
      }
      sections.add(
        Padding(
          padding: EdgeInsets.only(bottom: spacing.sm),
          child: Text(
            group.label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
      sections.add(_HubTileWrap(tiles: tiles));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sections,
    );
  }
}

class _HubTileWrap extends StatelessWidget {
  const _HubTileWrap({required this.tiles});

  final List<_HubDestination> tiles;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing.md;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1000
            ? 4
            : width >= 700
                ? 3
                : width >= 480
                    ? 2
                    : 1;
        final tileWidth = (width - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final tile in tiles)
              SizedBox(
                width: tileWidth,
                child: AppQuickActionCard(
                  icon: tile.icon,
                  title: tile.title,
                  subtitle: tile.subtitle,
                  onTap: () => context.push(tile.route),
                ),
              ),
          ],
        );
      },
    );
  }
}
