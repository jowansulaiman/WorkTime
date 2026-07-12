import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/price_deviation.dart';
import '../providers/auth_provider.dart';
import '../providers/inventory_provider.dart';
import '../theme/theme_extensions.dart';
import '../widgets/breadcrumb_app_bar.dart';
import 'inventory_screen.dart' show formatCents;

/// Automatischer Preisabgleich App-VK vs. Kasse (admin, OktoPOS-Menue der
/// Warenwirtschaft): zeigt Artikel, deren juengster TATSAECHLICH kassierter
/// Stueckpreis (aus den gesyncten Belegen) vom App-VK abweicht.
///
/// Je Abweichung zwei Wege: Kassen-Preis in die App uebernehmen (laeuft ueber
/// `updateProductPrices` -> Preisverlauf) oder den App-Preis an die Kasse
/// pushen (`pushOktoposArticles`, nur bei aktiviertem OktoPOS-Schalter).
class PriceDeviationScreen extends StatefulWidget {
  const PriceDeviationScreen({
    super.key,
    required this.siteId,
    required this.siteName,
  });

  final String siteId;
  final String siteName;

  @override
  State<PriceDeviationScreen> createState() => _PriceDeviationScreenState();
}

class _PriceDeviationScreenState extends State<PriceDeviationScreen> {
  bool _loading = true;
  bool _working = false;
  String? _error;
  List<PriceDeviation> _deviations = const [];

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
      final deviations = await context
          .read<InventoryProvider>()
          .loadPriceDeviations(siteId: widget.siteId);
      if (!mounted) return;
      setState(() {
        _deviations = deviations;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Preisabgleich fehlgeschlagen: $error';
      });
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Kassen-Preis als neuen App-VK uebernehmen (mit Preisverlauf-Eintrag).
  Future<void> _adoptPosPrice(PriceDeviation deviation) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await context.read<InventoryProvider>().updateProductPrices(
            deviation.product,
            newSellingCents: deviation.posUnitPriceCents,
          );
      _showSnack(
        'VK uebernommen: ${deviation.product.name} → '
        '${formatCents(deviation.posUnitPriceCents)}.',
      );
      await _load();
    } catch (error) {
      _showSnack('Fehler beim Uebernehmen: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// App-Preis an die Kasse pushen (change-prices via Cloud Function).
  Future<void> _pushAppPrice(PriceDeviation deviation) async {
    final productId = deviation.product.id;
    if (_working || productId == null) return;
    setState(() => _working = true);
    try {
      final result = await context.read<InventoryProvider>().pushOktoposArticles(
            siteId: widget.siteId,
            productIds: [productId],
          );
      final failed = (result['failed'] as num?)?.toInt() ?? 0;
      _showSnack(
        failed == 0
            ? 'App-Preis an die Kasse gesendet: ${deviation.product.name}.'
            : 'Kasse hat den Preis nicht angenommen — Details im Kassen-Log.',
      );
      await _load();
    } catch (error) {
      _showSnack('Fehler beim Senden an die Kasse: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAdmin = context.watch<AuthProvider>().profile?.isAdmin ?? false;
    final canPush = isAdmin && AppConfig.oktoposEnabled;
    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: 'Warenwirtschaft',
            onTap: () => Navigator.of(context).pop(),
          ),
          const BreadcrumbItem(label: 'Preisabgleich Kasse'),
        ],
        actions: [
          IconButton(
            tooltip: 'Neu laden',
            icon: const Icon(Icons.refresh),
            onPressed: _loading || _working ? null : _load,
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
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Laden: ${widget.siteName}',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Vergleicht den App-VK mit dem zuletzt an der '
                                'Kasse kassierten Stueckpreis (Belege der '
                                'letzten 30 Tage). Grundlage sind die per '
                                'Kassen-Sync uebernommenen Verkaeufe.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_error != null)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _error!,
                              style:
                                  TextStyle(color: theme.colorScheme.error),
                            ),
                          ),
                        )
                      else if (_deviations.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Text(
                            'Keine Preisabweichungen — App und Kasse stimmen '
                            'fuer alle zuletzt verkauften Artikel ueberein.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        for (final deviation in _deviations)
                          _buildDeviationCard(context, deviation, canPush),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeviationCard(
    BuildContext context,
    PriceDeviation deviation,
    bool canPush,
  ) {
    final theme = Theme.of(context);
    final colors = theme.appColors;
    final dateFormat = DateFormat('dd.MM.yyyy', 'de_DE');
    final diff = deviation.diffCents;
    final diffText =
        '${diff > 0 ? '+' : '−'}${formatCents(diff.abs())}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    deviation.product.name,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  diffText,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: diff > 0 ? colors.warning : theme.colorScheme.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'App: ${formatCents(deviation.appPriceCents)} · '
              'Kasse: ${formatCents(deviation.posUnitPriceCents)}'
              '${deviation.lastSoldAt != null ? ' · zuletzt ${dateFormat.format(deviation.lastSoldAt!)}' : ''}'
              ' · ${deviation.observations}× beobachtet',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  onPressed:
                      _working ? null : () => _adoptPosPrice(deviation),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Kassen-Preis uebernehmen'),
                ),
                if (canPush)
                  OutlinedButton.icon(
                    onPressed:
                        _working ? null : () => _pushAppPrice(deviation),
                    icon: const Icon(Icons.upload_outlined),
                    label: const Text('App-Preis an Kasse senden'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
