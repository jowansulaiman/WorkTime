import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/staffing_profile.dart';
import '../models/site_definition.dart';
import '../models/site_schedule.dart';
import '../providers/auth_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/team_provider.dart';
import '../theme/theme_extensions.dart';
import '../widgets/breadcrumb_app_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/section_card.dart';

/// **Besetzungs-Profil (P3.1).** Admin-Auswertung: anonymes Beleg-pro-Stunde-
/// Profil (Wochentag×Stunde) je Standort + abgeleiteter Besetzungs-Vorschlag für
/// die Stoßzeiten — informiert die Schichtplanung. Reine Anzeige (Beleg-Anzahl,
/// kein Personenbezug); „Vorschlag übernehmen" in `StaffingDemand` ist ein
/// späterer Schritt (StaffingDemand trägt heute kein Quellfeld).
class StaffingProfileScreen extends StatefulWidget {
  const StaffingProfileScreen({super.key, this.parentLabel = 'Schichtplan'});

  final String parentLabel;

  @override
  State<StaffingProfileScreen> createState() => _StaffingProfileScreenState();
}

class _StaffingProfileScreenState extends State<StaffingProfileScreen> {
  static const _weekdayLabels = ['', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

  String? _siteId;
  bool _loading = false;
  bool _applying = false;
  String? _error;
  StaffingProfile? _profile;
  bool _started = false;

  Future<void> _load(String siteId) async {
    setState(() {
      _siteId = siteId;
      _loading = true;
      _error = null;
    });
    try {
      final profile = await context
          .read<InventoryProvider>()
          .loadStaffingProfile(siteId: siteId, windowDays: 28);
      if (!mounted || siteId != _siteId) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || siteId != _siteId) return;
      setState(() {
        _error = 'Besetzungs-Profil konnte nicht geladen werden.';
        _loading = false;
      });
    }
  }

  /// Übernimmt den Besetzungs-Vorschlag der Stoßzeit-Stunde [cell] in den
  /// `StaffingDemand.requiredCount` des Standorts (1-Stunden-Fenster; vorhandene
  /// Demand gleichen Wochentags+Fensters wird ersetzt). Speichert den Standort.
  Future<void> _apply(HourlyDemand cell, StaffingProfile profile) async {
    final siteId = _siteId;
    if (siteId == null || _applying) return;
    final messenger = ScaffoldMessenger.of(context);
    final team = context.read<TeamProvider>();
    SiteDefinition? site;
    for (final s in team.sites) {
      if (s.id == siteId) {
        site = s;
        break;
      }
    }
    if (site == null) return;

    final demand = StaffingDemand(
      weekday: cell.weekday,
      window: TimeWindow(startMinute: cell.hour * 60, endMinute: (cell.hour + 1) * 60),
      requiredCount: profile.suggestRequiredCount(
        weekday: cell.weekday,
        startMinute: cell.hour * 60,
        endMinute: (cell.hour + 1) * 60,
      ),
    );
    final updated = [...site.staffingDemands];
    final idx = updated.indexWhere((d) =>
        d.weekday == demand.weekday &&
        d.window.startMinute == demand.window.startMinute &&
        d.window.endMinute == demand.window.endMinute);
    if (idx >= 0) {
      updated[idx] = demand;
    } else {
      updated.add(demand);
    }

    setState(() => _applying = true);
    try {
      await team.saveSite(site.copyWith(staffingDemands: updated));
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          content: Text('Bedarf für ${_weekdayLabels[cell.weekday]} '
              '${cell.hour}–${cell.hour + 1} Uhr übernommen.')));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
          const SnackBar(content: Text('Übernehmen fehlgeschlagen.')));
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileUser = context.watch<AuthProvider>().profile;
    final breadcrumbs = [
      BreadcrumbItem(
        label: widget.parentLabel,
        onTap: () => Navigator.of(context).maybePop(),
      ),
      const BreadcrumbItem(label: 'Besetzungs-Profil'),
    ];
    if (profileUser == null || !profileUser.isAdmin) {
      return Scaffold(
        appBar: BreadcrumbAppBar(breadcrumbs: breadcrumbs),
        body: const Center(child: Text('Nur für Administratoren.')),
      );
    }

    final sites = [
      for (final s in context.watch<TeamProvider>().sites)
        if (s.id != null) (id: s.id!, name: s.name),
    ];
    if (_siteId == null && sites.isNotEmpty) {
      _siteId = sites.first.id;
    }
    if (!_started && _siteId != null) {
      _started = true;
      final siteId = _siteId!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(siteId);
      });
    }

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: breadcrumbs,
        actions: [
          IconButton(
            tooltip: 'Aktualisieren',
            icon: const Icon(Icons.refresh),
            onPressed: _siteId == null ? null : () => _load(_siteId!),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (sites.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: DropdownButton<String>(
                    value: _siteId,
                    onChanged: (value) {
                      if (value != null) _load(value);
                    },
                    items: [
                      for (final s in sites)
                        DropdownMenuItem(value: s.id, child: Text(s.name)),
                    ],
                  ),
                ),
              ),
            Expanded(child: _buildBody(context, sites.isEmpty)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, bool noSites) {
    if (noSites) {
      return const EmptyState(
        icon: Icons.store_outlined,
        title: 'Keine Standorte',
        message: 'Lege zuerst Standorte an.',
      );
    }
    if (_error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Analyse fehlgeschlagen',
        message: _error!,
        action: FilledButton.tonal(
          onPressed: _siteId == null ? null : () => _load(_siteId!),
          child: const Text('Erneut versuchen'),
        ),
      );
    }
    final profile = _profile;
    if (_loading && profile == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (profile == null || profile.cells.isEmpty) {
      return const EmptyState(
        icon: Icons.point_of_sale_outlined,
        title: 'Noch kein Kassenabgleich',
        message: 'Sobald Verkäufe vorliegen, erscheint hier das '
            'Stoßzeiten-Profil.',
      );
    }

    final peaks = [...profile.cells]
      ..sort((a, b) => b.avgReceipts.compareTo(a.avgReceipts));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Datenbasis: letzte 28 Tage · Ø Belege je Wochentag-Stunde · '
          'Vorschlag = Stoßzeit ÷ ${profile.receiptsPerStaffPerHour} Belege/Kraft.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Stoßzeiten & Besetzungs-Vorschlag',
          child: Column(
            children: [
              for (final c in peaks.take(6))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.trending_up,
                      color: Theme.of(context).appColors.info),
                  title: Text('${_weekdayLabels[c.weekday]} '
                      '${c.hour.toString().padLeft(2, '0')}–'
                      '${(c.hour + 1).toString().padLeft(2, '0')} Uhr'),
                  subtitle: Text('Ø ${c.avgReceipts.toStringAsFixed(1)} Belege/Std'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${profile.suggestRequiredCount(weekday: c.weekday, startMinute: c.hour * 60, endMinute: (c.hour + 1) * 60)} '
                        'Kräfte',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _applying ? null : () => _apply(c, profile),
                        child: const Text('übernehmen'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Heatmap (Ø Belege/Std)',
          child: _Heatmap(profile: profile, weekdayLabels: _weekdayLabels),
        ),
      ],
    );
  }
}

class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.profile, required this.weekdayLabels});

  final StaffingProfile profile;
  final List<String> weekdayLabels;

  @override
  Widget build(BuildContext context) {
    final cells = profile.cells;
    final minHour = cells.map((c) => c.hour).reduce((a, b) => a < b ? a : b);
    final maxHour = cells.map((c) => c.hour).reduce((a, b) => a > b ? a : b);
    final peak = profile.peakAvgReceipts;
    final colors = Theme.of(context).appColors;
    final scheme = Theme.of(context).colorScheme;

    Widget cellBox(String text, double intensity) => Container(
          width: 34,
          height: 30,
          margin: const EdgeInsets.all(1),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Color.lerp(
                scheme.surfaceContainerHighest, colors.info, intensity * 0.85),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(text,
              style: TextStyle(
                fontSize: 11,
                color: intensity > 0.6 ? colors.onInfo : scheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 34),
              for (var h = minHour; h <= maxHour; h++)
                SizedBox(
                  width: 36,
                  child: Text('$h',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall),
                ),
            ],
          ),
          for (var wd = 1; wd <= 7; wd++)
            Row(
              children: [
                SizedBox(
                  width: 34,
                  child: Text(weekdayLabels[wd],
                      style: Theme.of(context).textTheme.labelMedium),
                ),
                for (var h = minHour; h <= maxHour; h++)
                  Builder(builder: (_) {
                    final cell = profile.cellAt(wd, h);
                    final avg = cell?.avgReceipts ?? 0;
                    final intensity = peak > 0 ? (avg / peak) : 0.0;
                    return cellBox(
                        avg <= 0 ? '' : avg.toStringAsFixed(0), intensity);
                  }),
              ],
            ),
        ],
      ),
    );
  }
}
