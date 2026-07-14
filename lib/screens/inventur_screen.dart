import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/money.dart';
import '../models/inventory_count_session.dart';
import '../models/product.dart';
import '../models/site_definition.dart';
import '../providers/auth_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/team_provider.dart';
import '../theme/theme_extensions.dart';
import '../widgets/breadcrumb_app_bar.dart';
import '../widgets/empty_state.dart';

/// **Geführter Inventur-Modus (Bestandszählung).** Zähl-Liste aller aktiven
/// Artikel eines Standorts (optional je Warengruppe): der Zähler trägt je
/// Artikel den gezählten Bestand ein (bewusst OHNE Vorbefüllung — echtes
/// Zählen statt Abnicken), prüft die Abweichungen in einer Differenz-Vorschau
/// und bucht sie dann artikelweise über [InventoryProvider.recordStocktake]
/// (StockMovement vom Typ `stocktake`).
///
/// Gate = `canManageInventory` (er bucht Bestand) — gespiegelt in
/// `RoutePermissions` (Route [AppRoutes.inventur], kritische Kopplung #7).
/// Artikel ohne Eingabe gelten als „nicht gezählt" und werden NIE gebucht.
class InventurScreen extends StatefulWidget {
  const InventurScreen({super.key, this.parentLabel = 'Warenwirtschaft'});

  final String parentLabel;

  @override
  State<InventurScreen> createState() => _InventurScreenState();
}

class _InventurScreenState extends State<InventurScreen> {
  String? _selectedSiteId;

  /// Warengruppen-Filter; `''` = alle Warengruppen.
  String _categoryFilter = '';

  final TextEditingController _searchController = TextEditingController();
  String _search = '';

  /// Eingabefelder je Artikel-ID. Lazy angelegt, leben über Site-/Filter-
  /// Wechsel hinweg (die Zähl-Session gehört zum Artikel, nicht zur Ansicht).
  final Map<String, TextEditingController> _countControllers = {};

  /// In dieser Session „erledigte" Artikel: erfolgreich gebuchte Differenzen
  /// (Feld geleert) sowie gezählte Artikel ohne Abweichung nach einer Buchung.
  final Set<String> _doneIds = {};

  /// **WW-8:** aktive, persistente Zählsession (optional). `null` = flüchtiger
  /// Schnell-Zähl-Modus (die Buchung läuft dann über die Differenz-Vorschau).
  InventoryCountSession? _session;

  /// Debounce-Timer je Artikel für die Session-Persistenz (kein Write pro
  /// Tastendruck).
  final Map<String, Timer> _persistTimers = {};

  /// Unterdrückt die Persistenz während die Controller aus einer fortgesetzten
  /// Session vorbelegt werden (sonst redundante Re-Writes des Ladewerts).
  bool _suppressPersist = false;
  bool _completing = false;

  @override
  void dispose() {
    _searchController.dispose();
    for (final timer in _persistTimers.values) {
      timer.cancel();
    }
    for (final controller in _countControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String productId) {
    return _countControllers.putIfAbsent(productId, () {
      final controller = TextEditingController();
      controller.addListener(() {
        // Jede neue Eingabe öffnet einen bereits erledigten Artikel wieder.
        _doneIds.remove(productId);
        _schedulePersist(productId);
        if (mounted) {
          setState(() {});
        }
      });
      return controller;
    });
  }

  /// **WW-8:** persistiert die eigene Zählung debounced (~600 ms) in die aktive
  /// Session. No-op im flüchtigen Modus oder während der Session-Vorbelegung.
  void _schedulePersist(String productId) {
    final session = _session;
    if (session == null || _suppressPersist) return;
    _persistTimers[productId]?.cancel();
    _persistTimers[productId] =
        Timer(const Duration(milliseconds: 600), () => _persistNow(productId));
  }

  Future<void> _persistNow(String productId) async {
    final session = _session;
    if (session == null || !mounted) return;
    final value = _countedValue(productId);
    if (value == null) return;
    final inventory = context.read<InventoryProvider>();
    final product = inventory.productById(productId);
    if (product == null) return;
    await inventory.recordCount(
      sessionId: session.id!,
      productId: productId,
      productName: product.name,
      quantity: value,
      stockAtCount: product.currentStock,
    );
  }

  /// Schreibt alle noch ausstehenden Debounce-Werte sofort (vor dem Abschluss).
  Future<void> _flushPersists() async {
    final pending = _persistTimers.keys.toList();
    for (final timer in _persistTimers.values) {
      timer.cancel();
    }
    _persistTimers.clear();
    for (final productId in pending) {
      await _persistNow(productId);
    }
  }

  /// Gezählter Wert eines Artikels oder `null` = nicht gezählt (leeres Feld).
  int? _countedValue(String productId) {
    final text = _countControllers[productId]?.text.trim() ?? '';
    if (text.isEmpty) {
      return null;
    }
    return int.tryParse(text);
  }

  bool _isCounted(Product product) {
    final id = product.id;
    if (id == null) {
      return false;
    }
    return _countedValue(id) != null || _doneIds.contains(id);
  }

  /// Ungebuchte Eingaben (Feld gefüllt, Artikel nicht erledigt) — speist den
  /// Verlassen-Schutz.
  bool get _hasUnbookedCounts => _countControllers.entries.any((entry) =>
      entry.value.text.trim().isNotEmpty && !_doneIds.contains(entry.key));

  // --- Abgeleitete Sichten --------------------------------------------------

  /// Zähl-Umfang: alle aktiven Artikel des Standorts, optional auf eine
  /// Warengruppe verengt, alphabetisch. Das Suchfeld verengt nur die ANZEIGE,
  /// nicht den Umfang (Fortschritt/Differenzen zählen über den Umfang).
  List<Product> _scopeProducts(
    InventoryProvider inventory,
    String? siteId,
    String category,
  ) {
    final list = inventory
        .productsForSite(siteId)
        .where((product) => product.isActive)
        .where((product) =>
            category.isEmpty || (product.category?.trim() ?? '') == category)
        .toList();
    list.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  List<String> _categoriesFor(InventoryProvider inventory, String? siteId) {
    final result = <String>{};
    for (final product in inventory.productsForSite(siteId)) {
      if (!product.isActive) {
        continue;
      }
      final category = product.category?.trim();
      if (category != null && category.isNotEmpty) {
        result.add(category);
      }
    }
    final list = result.toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  List<_CountDiff> _computeDiffs(List<Product> scope) {
    final diffs = <_CountDiff>[];
    for (final product in scope) {
      final id = product.id;
      if (id == null) {
        continue;
      }
      final counted = _countedValue(id);
      if (counted == null || counted == product.currentStock) {
        continue;
      }
      diffs.add(_CountDiff(product: product, counted: counted));
    }
    return diffs;
  }

  /// Gezählte Artikel OHNE Abweichung (werden nach einer Buchung bzw. beim
  /// Abschließen als erledigt markiert, aber nie gebucht).
  Set<String> _matchedIds(List<Product> scope) {
    final result = <String>{};
    for (final product in scope) {
      final id = product.id;
      if (id == null) {
        continue;
      }
      final counted = _countedValue(id);
      if (counted != null && counted == product.currentStock) {
        result.add(id);
      }
    }
    return result;
  }

  // --- Aktionen -------------------------------------------------------------

  Future<void> _openDiffPreview(List<Product> scope, bool showValuation) async {
    final diffs = _computeDiffs(scope);
    final matchedIds = _matchedIds(scope);

    int? valuationCents;
    if (showValuation) {
      var sum = 0;
      var anyPrice = false;
      for (final diff in diffs) {
        final purchase = diff.product.purchasePriceCents;
        if (purchase != null) {
          anyPrice = true;
          sum += diff.delta * purchase;
        }
      }
      valuationCents = anyPrice ? sum : null;
    }

    final result = await showModalBottomSheet<_BookingResult>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _DiffPreviewSheet(
        diffs: diffs,
        matchedCount: matchedIds.length,
        valuationCents: valuationCents,
        onBook: () => _bookDiffs(diffs),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    setState(() {
      // Erfolgreich gebuchte aus der Session entfernen (Feld leeren) und als
      // erledigt markieren; Zählstände ohne Differenz ebenfalls erledigt.
      for (final id in result.bookedIds) {
        _countControllers[id]?.clear();
        _doneIds.add(id);
      }
      _doneIds.addAll(matchedIds);
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.message)));
  }

  /// Bucht die Abweichungen sequenziell (je Artikel eigener try/catch — ein
  /// Fehler stoppt die übrigen Buchungen nicht) und baut die deutsche
  /// Zusammenfassung für die SnackBar.
  Future<_BookingResult> _bookDiffs(List<_CountDiff> diffs) async {
    final inventory = context.read<InventoryProvider>();
    final bookedIds = <String>[];
    var failed = 0;
    for (final diff in diffs) {
      try {
        await inventory.recordStocktake(
          product: diff.product,
          countedStock: diff.counted,
        );
        bookedIds.add(diff.product.id!);
      } catch (_) {
        failed++;
      }
    }
    final booked = bookedIds.length;
    final okText = switch (booked) {
      0 => 'Keine Differenz gebucht',
      1 => '1 Differenz gebucht',
      _ => '$booked Differenzen gebucht',
    };
    final message = failed > 0 ? '$okText, $failed Fehler.' : '$okText.';
    return _BookingResult(bookedIds: bookedIds, message: message);
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Zählung verwerfen?'),
        content: const Text(
          'Es gibt ungebuchte Zählstände. Beim Verlassen gehen sie verloren.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Weiter zählen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Verwerfen'),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) {
      return;
    }
    setState(() {
      for (final controller in _countControllers.values) {
        controller.clear();
      }
      _doneIds.clear();
    });
    // Bedingungslos poppen: PopScopes canPopNotifier wird erst beim NAECHSTEN
    // Rebuild aktualisiert — ein maybePop() saehe hier noch canPop=false und
    // riefe _confirmDiscard erneut auf (Dialog erschiene doppelt). Der Nutzer
    // hat das Verwerfen bereits bestaetigt.
    Navigator.of(context).pop();
  }

  // --- Session-Aktionen (WW-8/WW-9) -----------------------------------------

  Future<void> _startSession(String siteId) async {
    final inventory = context.read<InventoryProvider>();
    final scopeCount = _scopeProducts(inventory, siteId, '').length;
    final label = DateFormat('d. MMM y, HH:mm', 'de_DE').format(DateTime.now());
    final session = await inventory.startCountSession(
      siteId: siteId,
      title: 'Inventur $label',
      categoryFilter: _categoryFilter.isEmpty ? null : _categoryFilter,
      totalProducts: scopeCount,
    );
    if (!mounted || session == null) return;
    setState(() => _session = session);
    _toast('Zählung gestartet — Fortschritt wird gespeichert.');
  }

  Future<void> _resumeSession(InventoryCountSession session) async {
    final inventory = context.read<InventoryProvider>();
    await inventory.loadCountLines(session.id!);
    if (!mounted) return;
    final latest = inventory.latestCountByProduct(session.id!);
    _suppressPersist = true;
    setState(() {
      _session = session;
      latest.forEach((productId, event) {
        _controllerFor(productId).text = event.countedQuantity.toString();
        _doneIds.remove(productId);
      });
    });
    _suppressPersist = false;
    _toast('Zählung fortgesetzt (${latest.length} bereits gezählt).');
  }

  Future<void> _completeSession() async {
    final session = _session;
    if (session == null || _completing) return;
    setState(() => _completing = true);
    final inventory = context.read<InventoryProvider>();
    try {
      await _flushPersists();
      var resolved = <String, String>{};
      var targets = <String, int>{};
      while (true) {
        final result = await inventory.completeCountSession(
          sessionId: session.id!,
          resolvedCounts: resolved,
          recomputedTargets: targets,
        );
        if (result.completed) {
          if (mounted) {
            _toast('Inventur abgeschlossen — '
                '${result.bookedCount} Differenz(en) gebucht.');
            Navigator.of(context).maybePop();
          }
          return;
        }
        if (result.unresolvedConflicts.isNotEmpty) {
          final picked = await _resolveConflicts(
              inventory, session, result.unresolvedConflicts);
          if (picked == null) return; // abgebrochen
          resolved = {...resolved, ...picked};
          continue;
        }
        if (result.staleProductIds.isNotEmpty) {
          final decision =
              await _resolveStale(inventory, session, result.staleProductIds);
          if (decision == null) return;
          if (decision.isEmpty) {
            // Neuzählung gewählt → Controller aus (neu geladenen) Ständen frisch.
            if (mounted) {
              _toast('Bitte die markierten Artikel neu zählen.');
            }
            return;
          }
          targets = {...targets, ...decision};
          continue;
        }
        if (result.failedProductIds.isNotEmpty) {
          if (mounted) {
            _toast('${result.failedProductIds.length} Buchung(en) '
                'fehlgeschlagen — bitte erneut abschließen.');
          }
          return;
        }
        return;
      }
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  /// Lässt je Konflikt-Artikel die maßgebliche Zählung wählen. `null` = Abbruch.
  Future<Map<String, String>?> _resolveConflicts(
    InventoryProvider inventory,
    InventoryCountSession session,
    List<String> productIds,
  ) async {
    final conflicts = inventory.conflictsFor(session.id!);
    final chosen = <String, String>{};
    for (final productId in productIds) {
      final events = conflicts[productId] ?? const [];
      if (events.isEmpty) continue;
      final lineId = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Zählkonflikt'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Artikel „${events.first.productName}" wurde abweichend '
                  'gezählt. Maßgebliche Zählung wählen:'),
              const SizedBox(height: 8),
              for (final e in events)
                ListTile(
                  dense: true,
                  title: Text('${e.countedQuantity} Stück'),
                  subtitle: Text(e.countedByLabel ?? 'unbekannt'),
                  onTap: () => Navigator.pop(ctx, e.id),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Abbrechen')),
          ],
        ),
      );
      if (lineId == null) return null;
      chosen[productId] = lineId;
    }
    return chosen;
  }

  /// Fragt bei Stale-Artikeln eine Entscheidung ab. Rückgabe: leere Map =
  /// „Neuzählung", gefüllte Map = Verrechnungs-Ziele je Artikel, `null` = Abbruch.
  Future<Map<String, int>?> _resolveStale(
    InventoryProvider inventory,
    InventoryCountSession session,
    List<String> productIds,
  ) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bestand hat sich geändert'),
        content: Text('${productIds.length} Artikel wurden nach der Zählung '
            'bewegt (Verkauf/Wareneingang). Eine absolute Buchung der Zählung '
            'würde diese Bewegungen überschreiben.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Abbrechen')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'recount'),
              child: const Text('Neu zählen')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'reconcile'),
              child: const Text('Bewegungen verrechnen')),
        ],
      ),
    );
    if (choice == null) return null;
    if (choice == 'recount') return const {};
    // Verrechnen: Ziel = gezählte Menge + (aktueller Bestand − Bestand bei Zählung).
    final latest = inventory.latestCountByProduct(session.id!);
    final targets = <String, int>{};
    for (final productId in productIds) {
      final event = latest[productId];
      final product = inventory.productById(productId);
      if (event == null || product == null) continue;
      final delta = product.currentStock - event.stockAtCount;
      targets[productId] = event.countedQuantity + delta;
    }
    return targets;
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// **WW-8:** Session-Leiste. Aktive Session → Info + Konflikt-Hinweis;
  /// sonst fortsetzbare Sessions + „Neue Zählung". Der flüchtige Schnellmodus
  /// bleibt möglich (einfach ohne Session weiterzählen).
  Widget _buildSessionBar(InventoryProvider inventory, String? siteId) {
    final theme = Theme.of(context);
    final appColors = theme.appColors;
    final active = _session;
    if (active != null) {
      final conflicts = inventory.conflictsFor(active.id!);
      return Container(
        width: double.infinity,
        color: appColors.infoContainer,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Icon(Icons.playlist_add_check, size: 18, color: appColors.info),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Zählung läuft: ${active.title}',
                      style: theme.textTheme.labelLarge),
                  if (conflicts.isNotEmpty)
                    Text('${conflicts.length} Zählkonflikt(e) — beim Abschluss '
                        'maßgebliche Zählung wählen',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: appColors.warning)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final resumeable =
        siteId == null ? const [] : inventory.resumeableSessions(siteId: siteId);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: resumeable.isEmpty
                ? const Text('Schnellzählung — oder als speicherbare Session '
                    'starten (fortsetzbar, mehrgerätefähig).')
                : Text('${resumeable.length} offene Zählung(en) fortsetzbar'),
          ),
          const SizedBox(width: 8),
          if (resumeable.isNotEmpty)
            TextButton(
              onPressed: () => _resumeSession(resumeable.first),
              child: const Text('Fortsetzen'),
            ),
          if (siteId != null)
            FilledButton.tonal(
              onPressed: () => _startSession(siteId),
              child: const Text('Session'),
            ),
        ],
      ),
    );
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthProvider>().profile;
    final breadcrumbs = [
      BreadcrumbItem(
        label: widget.parentLabel,
        onTap: () => Navigator.of(context).maybePop(),
      ),
      const BreadcrumbItem(label: 'Inventur'),
    ];

    if (profile == null || !profile.canManageInventory) {
      return Scaffold(
        appBar: BreadcrumbAppBar(breadcrumbs: breadcrumbs),
        body: const EmptyState(
          icon: Icons.lock_outline,
          title: 'Keine Berechtigung',
          message:
              'Die Inventur bucht Bestände und ist nur für Nutzer mit '
              'Bestandsverwaltung (Admin oder Schichtleitung) verfügbar.',
        ),
      );
    }

    final inventory = context.watch<InventoryProvider>();
    final team = context.watch<TeamProvider>();
    final sites = team.sites;
    // Bei genau einem Laden ist der Standort eindeutig; bei mehreren ist die
    // Auswahl Pflicht (Zählung ist immer je Standort).
    final effectiveSiteId =
        _selectedSiteId ?? (sites.length == 1 ? sites.first.id : null);
    final needsSiteChoice = sites.length > 1 && effectiveSiteId == null;

    final categories = _categoriesFor(inventory, effectiveSiteId);
    // Filter still zurücksetzen, wenn die Warengruppe am gewählten Standort
    // nicht (mehr) vorkommt (kein setState im Build).
    final effectiveCategory =
        categories.contains(_categoryFilter) ? _categoryFilter : '';

    final scope = needsSiteChoice
        ? const <Product>[]
        : _scopeProducts(inventory, effectiveSiteId, effectiveCategory);
    final query = _search.trim().toLowerCase();
    final visible = query.isEmpty
        ? scope
        : scope
            .where((product) => product.name.toLowerCase().contains(query))
            .toList(growable: false);
    final countedCount = scope.where(_isCounted).length;
    final anyCountedInput = scope.any((product) =>
        product.id != null && _countedValue(product.id!) != null);

    return PopScope<void>(
      canPop: !_hasUnbookedCounts,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _confirmDiscard();
        }
      },
      child: Scaffold(
        appBar: BreadcrumbAppBar(breadcrumbs: breadcrumbs),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              if (sites.length > 1)
                _SiteChoiceChips(
                  sites: sites,
                  selectedSiteId: effectiveSiteId,
                  onChanged: (value) =>
                      setState(() => _selectedSiteId = value),
                ),
              if (!needsSiteChoice) ...[
                _buildSessionBar(inventory, effectiveSiteId),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    children: [
                      if (categories.isNotEmpty) ...[
                        DropdownButtonFormField<String>(
                          // Standortwechsel setzt den Formfeld-State zurück
                          // (initialValue greift nur beim Neuaufbau).
                          key: ValueKey(
                              'inventur-category-${effectiveSiteId ?? ''}'),
                          initialValue: effectiveCategory,
                          decoration: const InputDecoration(
                            labelText: 'Warengruppe',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('Alle Warengruppen'),
                            ),
                            for (final category in categories)
                              DropdownMenuItem(
                                value: category,
                                child: Text(category),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _categoryFilter = value ?? ''),
                        ),
                        const SizedBox(height: 8),
                      ],
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          labelText: 'Artikel suchen',
                          prefixIcon: const Icon(Icons.search),
                          isDense: true,
                          border: const OutlineInputBorder(),
                          suffixIcon: _search.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Suche leeren',
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _search = '');
                                  },
                                ),
                        ),
                        onChanged: (value) => setState(() => _search = value),
                      ),
                    ],
                  ),
                ),
                _ProgressHeader(counted: countedCount, total: scope.length),
              ],
              Expanded(
                child: needsSiteChoice
                    ? const EmptyState(
                        icon: Icons.store_outlined,
                        title: 'Standort wählen',
                        message:
                            'Die Inventur wird je Standort gezählt. Bitte oben '
                            'einen Laden auswählen.',
                      )
                    : scope.isEmpty
                        ? const EmptyState(
                            icon: Icons.inventory_2_outlined,
                            message:
                                'Keine aktiven Artikel für diese Auswahl. '
                                'Warengruppe oder Standort prüfen.',
                          )
                        : visible.isEmpty
                            ? const EmptyState(
                                icon: Icons.search_off,
                                message: 'Keine Artikel zur Suche gefunden.',
                              )
                            : ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 4, 16, 16),
                                itemCount: visible.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final product = visible[index];
                                  final id = product.id;
                                  return _CountRow(
                                    product: product,
                                    controller: id == null
                                        ? null
                                        : _controllerFor(id),
                                    isCounted: _isCounted(product),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: _session != null
                ? Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.fact_check_outlined),
                          label: const Text('Vorschau'),
                          onPressed: anyCountedInput
                              ? () => _openDiffPreview(
                                  scope, profile.canManageInventory)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          icon: _completing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.done_all),
                          label: const Text('Abschließen'),
                          onPressed: _completing ? null : _completeSession,
                        ),
                      ),
                    ],
                  )
                : FilledButton.icon(
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Differenzen prüfen'),
                    onPressed: anyCountedInput
                        ? () =>
                            _openDiffPreview(scope, profile.canManageInventory)
                        : null,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Eine Abweichung: Artikel + gezählter Bestand (Differenz = gezählt − Buch).
class _CountDiff {
  const _CountDiff({required this.product, required this.counted});

  final Product product;
  final int counted;

  int get delta => counted - product.currentStock;
}

class _BookingResult {
  const _BookingResult({required this.bookedIds, required this.message});

  /// IDs der erfolgreich gebuchten Artikel (Felder leeren + erledigt).
  final List<String> bookedIds;

  /// Deutsche Zusammenfassung für die SnackBar.
  final String message;
}

/// Standort-Pflichtauswahl (nur bei > 1 Standort sichtbar). Bewusst OHNE
/// „Alle Läden"-Chip — gezählt wird immer genau ein Laden.
class _SiteChoiceChips extends StatelessWidget {
  const _SiteChoiceChips({
    required this.sites,
    required this.selectedSiteId,
    required this.onChanged,
  });

  final List<SiteDefinition> sites;
  final String? selectedSiteId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final site in sites) ...[
              ChoiceChip(
                label: Text(site.name),
                selected: selectedSiteId == site.id,
                onSelected: (_) => onChanged(site.id),
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
              const SizedBox(width: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.counted, required this.total});

  final int counted;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$counted von $total gezählt',
            style: theme.textTheme.labelLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : counted / total,
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Eine Zähl-Zeile: Status-Icon, Artikel (Name, Einheit, Buchbestand) und das
/// Eingabefeld „Gezählt" (initial leer, nur Ziffern).
class _CountRow extends StatelessWidget {
  const _CountRow({
    required this.product,
    required this.controller,
    required this.isCounted,
  });

  final Product product;
  final TextEditingController? controller;
  final bool isCounted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = theme.appColors;
    final subtitleParts = <String>[
      'Buchbestand: ${product.currentStock} ${product.unit}',
      if ((product.category ?? '').trim().isNotEmpty)
        product.category!.trim(),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          // Nicht nur Farbe: die Icon-FORM wechselt (Kreis -> Häkchen).
          Icon(
            isCounted ? Icons.check_circle : Icons.radio_button_unchecked,
            color:
                isCounted ? appColors.success : theme.colorScheme.outline,
            semanticLabel: isCounted ? 'Gezählt' : 'Noch nicht gezählt',
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitleParts.join(' · '),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 104,
            child: TextField(
              key: product.id == null
                  ? null
                  : ValueKey('inventur-count-${product.id}'),
              controller: controller,
              enabled: controller != null,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.end,
              decoration: const InputDecoration(
                labelText: 'Gezählt',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Differenz-Vorschau (Bottom-Sheet): nur die Abweichungen, farbcodierte
/// Differenz, optionale EK-Bewertung und der Buchen-Knopf. Artikel ohne
/// Eingabe tauchen hier nie auf und werden nie gebucht.
class _DiffPreviewSheet extends StatefulWidget {
  const _DiffPreviewSheet({
    required this.diffs,
    required this.matchedCount,
    required this.valuationCents,
    required this.onBook,
  });

  final List<_CountDiff> diffs;

  /// Gezählte Artikel ohne Abweichung (nur informativ).
  final int matchedCount;

  /// Summe der Differenzen nach EK in Cent; `null` = nicht anzeigen (kein
  /// EK gepflegt oder keine Berechtigung).
  final int? valuationCents;

  final Future<_BookingResult> Function() onBook;

  @override
  State<_DiffPreviewSheet> createState() => _DiffPreviewSheetState();
}

class _DiffPreviewSheetState extends State<_DiffPreviewSheet> {
  bool _busy = false;

  Future<void> _book() async {
    setState(() => _busy = true);
    final result = await widget.onBook();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = theme.appColors;
    final diffs = widget.diffs;
    final valuation = widget.valuationCents;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Differenz-Vorschau', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            diffs.isEmpty
                ? 'Keine Abweichungen — Buchbestand und Zählung stimmen '
                    'überein (${widget.matchedCount} gezählt).'
                : '${diffs.length} ${diffs.length == 1 ? 'Abweichung' : 'Abweichungen'}'
                    '${widget.matchedCount > 0 ? ' · ${widget.matchedCount} ohne Differenz' : ''}',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (valuation != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text('Differenz nach EK',
                      style: theme.textTheme.bodyMedium),
                ),
                Text(
                  Money.formatCents(valuation),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: valuation < 0
                        ? theme.colorScheme.error
                        : appColors.success,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          if (diffs.isNotEmpty)
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: diffs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final diff = diffs[index];
                  final delta = diff.delta;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                diff.product.name,
                                style: theme.textTheme.bodyLarge
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Buchbestand ${diff.product.currentStock} · '
                                'gezählt ${diff.counted} ${diff.product.unit}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          delta > 0 ? '+$delta' : '$delta',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: delta < 0
                                ? theme.colorScheme.error
                                : appColors.success,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
          if (diffs.isEmpty)
            FilledButton.icon(
              icon: const Icon(Icons.task_alt),
              label: const Text('Zählung abschließen'),
              onPressed: () => Navigator.of(context).pop(
                const _BookingResult(
                  bookedIds: [],
                  message:
                      'Keine Abweichungen – Zählung ohne Buchung abgeschlossen.',
                ),
              ),
            )
          else
            FilledButton.icon(
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.task_alt),
              label: Text(
                '${diffs.length} ${diffs.length == 1 ? 'Differenz' : 'Differenzen'} buchen',
              ),
              onPressed: _busy ? null : _book,
            ),
        ],
      ),
    );
  }
}
