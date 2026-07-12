import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/barcode_duplicates.dart';
import '../core/scan_stats.dart';
import '../models/scan_event.dart';
import '../models/site_definition.dart';
import '../providers/inventory_provider.dart';
import '../providers/team_provider.dart';
import '../theme/theme_extensions.dart';
import '../widgets/breadcrumb_app_bar.dart';

/// Scan-Statistik & Fehleranalyse (Manager/Admin): Trefferquote, Zeit bis
/// Treffer, oft fehlschlagende Codes, Quelle/Plattform-Verteilung — plus der
/// Duplikat-Report (Barcodes, die im selben Laden mehrfach vergeben sind).
///
/// Reine Auswertungs-Ansicht: laedt die Ereignisse einmalig on demand
/// ([InventoryProvider.fetchScanEvents]) und rechnet clientseitig
/// ([computeScanStats]) — kein Live-Stream, keine Firestore-Extra-Indexe.
class ScanStatistikScreen extends StatefulWidget {
  const ScanStatistikScreen({super.key, this.initialSiteId});

  /// Vorauswahl des Ladens (kommt vom Scanner); `null` = alle Laeden.
  final String? initialSiteId;

  @override
  State<ScanStatistikScreen> createState() => _ScanStatistikScreenState();
}

class _ScanStatistikScreenState extends State<ScanStatistikScreen> {
  late String? _siteId = widget.initialSiteId;
  int _windowDays = 7;
  bool _loading = true;
  String? _error;
  List<ScanEvent> _events = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final events =
          await context.read<InventoryProvider>().fetchScanEvents();
      if (!mounted) return;
      setState(() {
        _events = events;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Scan-Statistik konnte nicht geladen werden: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final sites = context.watch<TeamProvider>().sites;
    final stats = computeScanStats(
      _events,
      now: DateTime.now(),
      windowDays: _windowDays,
      siteId: _siteId,
    );
    final duplicates = findDuplicateBarcodes(inventory.products)
        .where((d) => _siteId == null || d.siteId == _siteId)
        .toList(growable: false);

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: 'Scanner',
            onTap: () => Navigator.of(context).pop(),
          ),
          const BreadcrumbItem(label: 'Scan-Statistik'),
        ],
        actions: [
          IconButton(
            tooltip: 'Neu laden',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      _buildFilters(context, sites),
                      const SizedBox(height: 12),
                      if (_error != null)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        )
                      else if (stats.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Text(
                            'Noch keine Scans im gewaehlten Zeitraum. '
                            'Die Statistik fuellt sich automatisch beim Scannen.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      else ...[
                        _buildKpiCard(context, stats),
                        const SizedBox(height: 12),
                        _buildFailingCodes(context, stats),
                        const SizedBox(height: 12),
                        _buildBreakdown(context, stats),
                      ],
                      const SizedBox(height: 12),
                      _buildDuplicates(context, duplicates, sites),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilters(BuildContext context, List<SiteDefinition> sites) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 7, label: Text('7 Tage')),
            ButtonSegment(value: 30, label: Text('30 Tage')),
          ],
          selected: {_windowDays},
          onSelectionChanged: (selection) =>
              setState(() => _windowDays = selection.first),
        ),
        if (sites.length > 1) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            initialValue: _siteId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Laden'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Alle Laeden'),
              ),
              for (final site in sites)
                DropdownMenuItem<String?>(
                  value: site.id,
                  child: Text(site.name),
                ),
            ],
            onChanged: (value) => setState(() => _siteId = value),
          ),
        ],
      ],
    );
  }

  Widget _buildKpiCard(BuildContext context, ScanStats stats) {
    final theme = Theme.of(context);
    final colors = theme.appColors;
    final hitPercent = (stats.hitRate * 100).toStringAsFixed(0);
    final manualPercent = (stats.manualShare * 100).toStringAsFixed(0);
    String ms(int? value) => value == null ? '–' : '${(value / 1000).toStringAsFixed(1)} s';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Erkennung', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _Kpi(label: 'Scans', value: '${stats.total}'),
                _Kpi(
                  label: 'Trefferquote',
                  value: '$hitPercent %',
                  color: stats.hitRate >= 0.8
                      ? colors.success
                      : (stats.hitRate >= 0.5 ? colors.warning : theme.colorScheme.error),
                ),
                _Kpi(label: 'Ø bis Treffer', value: ms(stats.averageTimeToHitMs)),
                _Kpi(label: 'Median', value: ms(stats.medianTimeToHitMs)),
                _Kpi(
                  label: 'Manuell eingegeben',
                  value: '${stats.manualEntries} ($manualPercent %)',
                  color: stats.manualShare > 0.25 ? colors.warning : null,
                ),
                _Kpi(label: 'Foto-Scans', value: '${stats.photoScans}'),
                _Kpi(label: 'Nicht gefunden', value: '${stats.notFound}'),
                _Kpi(label: 'Pruefziffer ungueltig', value: '${stats.invalidChecksum}'),
              ],
            ),
            if (stats.manualShare > 0.25) ...[
              const SizedBox(height: 12),
              Text(
                'Hoher Anteil manueller Eingaben — die Kamera-Erkennung '
                'versagt im Alltag. Zoom/Foto-Scan nutzen oder Etiketten '
                'pruefen.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.warning),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFailingCodes(BuildContext context, ScanStats stats) {
    final theme = Theme.of(context);
    if (stats.failingCodes.isEmpty) {
      return const SizedBox.shrink();
    }
    final dateFormat = DateFormat('dd.MM. HH:mm', 'de_DE');
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Codes mit Fehlversuchen',
              style: theme.textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Oft gescannt, aber kein Artikel — Kandidaten fuer fehlende '
              'Barcodes, beschaedigte Etiketten oder Fremdsortiment.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final failing in stats.failingCodes)
            ListTile(
              dense: true,
              title: Text(failing.code),
              subtitle: Text(
                '${failing.notFound}× nicht gefunden'
                '${failing.invalidChecksum > 0 ? ' · ${failing.invalidChecksum}× Pruefziffer' : ''}'
                '${failing.lastTriedAt != null ? ' · zuletzt ${dateFormat.format(failing.lastTriedAt!)}' : ''}',
              ),
              trailing: Text(
                '${failing.attempts}×',
                style: theme.textTheme.titleMedium,
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildBreakdown(BuildContext context, ScanStats stats) {
    final theme = Theme.of(context);
    Widget chips(String title, Map<String, int> data, Map<String, String> labels) {
      if (data.isEmpty) return const SizedBox.shrink();
      final entries = data.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final entry in entries)
                  Chip(
                    label:
                        Text('${labels[entry.key] ?? entry.key}: ${entry.value}'),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Verteilung', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            chips('Quelle', stats.bySource, const {
              'camera': 'Kamera',
              'manual': 'Manuell',
              'photo': 'Foto',
            }),
            chips('Geraeteklasse', stats.byPlatform, const {
              'android': 'Android',
              'ios': 'iPhone/iPad',
              'web': 'Web',
              'macos': 'Mac',
            }),
            chips('Modus', stats.byMode, const {
              'order': 'Bestellen',
              'book': 'Buchen',
              'stocktake': 'Inventur',
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDuplicates(
    BuildContext context,
    List<BarcodeDuplicate> duplicates,
    List<SiteDefinition> sites,
  ) {
    final theme = Theme.of(context);
    final colors = theme.appColors;
    String siteName(String siteId) {
      for (final site in sites) {
        if (site.id == siteId) return site.name;
      }
      return siteId;
    }

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                Icon(
                  duplicates.isEmpty
                      ? Icons.verified_outlined
                      : Icons.warning_amber_outlined,
                  color: duplicates.isEmpty ? colors.success : colors.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Doppelte Barcodes',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
          if (duplicates.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text('Keine Duplikate — jeder Barcode ist je Laden eindeutig.'),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Neue Duplikate werden beim Speichern hart abgelehnt; diese '
                'Altbestaende bitte bereinigen (Barcode an einem der Artikel '
                'aendern oder Artikel zusammenfuehren).',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final duplicate in duplicates)
              ListTile(
                dense: true,
                leading: const Icon(Icons.qr_code_2_outlined),
                title: Text(duplicate.canonicalCode),
                subtitle: Text(
                  '${siteName(duplicate.siteId)} · '
                  '${duplicate.products.map((p) => p.name + (p.isActive ? '' : ' (deaktiviert)')).join(' · ')}',
                ),
              ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}
