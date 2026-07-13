import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/site_definition.dart';
import '../providers/parcel_provider.dart';
import '../providers/team_provider.dart';
import '../theme/theme_extensions.dart';
import 'paket_einlagern_screen.dart';

/// Einstieg in den Paketshop (Section-Route `/paketshop` unter dem
/// „Laden"-Hub, Plan §7.6/§8). v1 zeigt den Überblick (Kennzahlen + offene
/// Pakete); die Einlagern-/Ausgeben-Flows kommen in P-5/P-6.
class PaketshopHubScreen extends StatelessWidget {
  const PaketshopHubScreen({super.key, this.parentLabel = 'Laden'});

  /// Label des übergeordneten Bereichs (für den Zurück-Kontext im Hub).
  final String parentLabel;

  @override
  Widget build(BuildContext context) {
    final parcel = context.watch<ParcelProvider>();
    final team = context.watch<TeamProvider>();
    final now = DateTime.now();

    final open = parcel.openParcels;
    final overdue = parcel.overdueParcels(now);
    final freeFaecher = parcel.freeCompartments;
    final arrivedToday = parcel.parcelsArrivedOn(now);
    final handedOutToday = parcel.parcelsHandedOutOn(now);
    final site = _resolveSite(team.sites, parcel.settings.paketshopSiteId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paketshop'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HinweisBanner(siteName: site?.name),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _KpiChip(label: 'Offen', value: open.length),
              _KpiChip(
                label: 'Überfällig',
                value: overdue.length,
                tone: overdue.isEmpty ? _Tone.neutral : _Tone.warning,
              ),
              _KpiChip(label: 'Freie Fächer', value: freeFaecher.length),
              _KpiChip(label: 'Heute angenommen', value: arrivedToday.length),
              _KpiChip(label: 'Heute ausgegeben', value: handedOutToday.length),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: site?.id == null
                ? null
                : () => Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => PaketEinlagernScreen(
                          siteId: site!.id!,
                          siteName: site.name,
                        ),
                      ),
                    ),
            icon: const Icon(Icons.add_box_outlined),
            label: const Text('Paket annehmen'),
          ),
          if (site?.id == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Paketshop-Standort in den Einstellungen festlegen, um Pakete '
                'anzunehmen.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 24),
          Text(
            'Offene Pakete',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (open.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('Keine offenen Pakete.')),
            )
          else
            ...open.map(
              (p) => Card(
                child: ListTile(
                  title: Text(p.recipientDisplayName),
                  subtitle: Text([
                    if (p.compartmentLabel != null) 'Fach ${p.compartmentLabel}',
                    if (p.senderName != null) p.senderName!,
                  ].join(' · ')),
                  trailing: overdue.contains(p)
                      ? Icon(
                          Icons.schedule,
                          color: Theme.of(context).appColors.warning,
                        )
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  SiteDefinition? _resolveSite(List<SiteDefinition> sites, String? siteId) {
    if (siteId != null) {
      for (final s in sites) {
        if (s.id == siteId) return s;
      }
    }
    // Fallback: bei genau einem Standort ist dieser der Paketshop-Standort.
    return sites.length == 1 ? sites.first : null;
  }
}

class _HinweisBanner extends StatelessWidget {
  const _HinweisBanner({this.siteName});

  final String? siteName;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).appColors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.info.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: colors.info),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  siteName == null
                      ? 'Internes Sortier- und Wiederfinde-Register.'
                      : 'Internes Register · Standort $siteName',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Der offizielle Ablauf des Paketdiensts (Annahme/Ausgabe am '
                  'Anbieter-Gerät, ggf. Ausweis/Unterschrift) bleibt zusätzlich '
                  'zwingend.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _Tone { neutral, warning }

class _KpiChip extends StatelessWidget {
  const _KpiChip({
    required this.label,
    required this.value,
    this.tone = _Tone.neutral,
  });

  final String label;
  final int value;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = tone == _Tone.warning
        ? theme.appColors.warning.withValues(alpha: 0.14)
        : scheme.surfaceContainerLow;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
