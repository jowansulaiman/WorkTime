import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../models/contact.dart';
import '../../models/contact_details.dart';
import '../../providers/auth_provider.dart';
import '../../providers/contact_provider.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/team_provider.dart';
import '../../routing/route_permissions.dart';
import '../../routing/shell_tab.dart';
import '../../theme/theme_extensions.dart';

/// Ein Treffer der globalen Suche: Label + Kategorie + Icon + optionale
/// Detailzeile + Navigationsziel (Anf. 24 „schnell finden" / 25 „wenige
/// Schritte").
class GlobalSearchItem {
  const GlobalSearchItem({
    required this.label,
    required this.category,
    required this.icon,
    required this.path,
    this.detail,
    this.isTab = false,
  });

  final String label;
  final String category;
  final IconData icon;
  final String path;

  /// Zweite, gedämpfte Zeile (z. B. Kurzbeschreibung eines Bereichs, Kundentyp,
  /// Rolle). `null` → keine Detailzeile.
  final String? detail;

  /// true → Tab-Wechsel (`go`), false → Hauptbereich-Route (`push`, Back → Hub).
  final bool isTab;

  void navigate(GoRouter router) {
    if (isTab) {
      router.go(path);
    } else {
      router.push(path);
    }
  }
}

/// Eine nach Relevanz sortierte Kategorie-Gruppe von Treffern.
class GlobalSearchGroup {
  const GlobalSearchGroup({
    required this.category,
    required this.title,
    required this.items,
    this.bestScore = 0,
    this.totalCount = 0,
  });

  /// Interner Kategorie-Schlüssel (`Bereich`/`Kontakt`/…).
  final String category;

  /// Angezeigter Gruppentitel (z. B. „Bereiche").
  final String title;

  /// Angezeigte (ggf. gedeckelte) Treffer dieser Gruppe.
  final List<GlobalSearchItem> items;

  /// Bester Score der Gruppe (bestimmt die Gruppen-Reihenfolge).
  final int bestScore;

  /// Gesamtzahl der Treffer vor dem Per-Gruppen-Limit (für „+N weitere").
  final int totalCount;
}

/// Alle navigierbaren **Bereiche/Module** (zuverlässige Deep-Links). Wird beim
/// Öffnen der Suche per [RoutePermissions] auf die Rechte des Nutzers gefiltert.
const List<GlobalSearchItem> _destinations = <GlobalSearchItem>[
  // Tabs
  GlobalSearchItem(label: 'Heute', category: 'Bereich', icon: Icons.today_rounded, path: '/', isTab: true, detail: 'Startseite & Tagesüberblick'),
  GlobalSearchItem(label: 'Plan', category: 'Bereich', icon: Icons.view_timeline_outlined, path: '/plan', isTab: true, detail: 'Schichtplanung'),
  GlobalSearchItem(label: 'Zeit', category: 'Bereich', icon: Icons.schedule_rounded, path: '/zeit', isTab: true, detail: 'Zeiterfassung & Stempeluhr'),
  GlobalSearchItem(label: 'Anfragen', category: 'Bereich', icon: Icons.inbox_outlined, path: '/anfragen', isTab: true, detail: 'Abwesenheiten & Benachrichtigungen'),
  GlobalSearchItem(label: 'Kontakte', category: 'Bereich', icon: Icons.contacts_outlined, path: '/kontakte', isTab: true, detail: 'Kunden, Lieferanten & Partner'),
  GlobalSearchItem(label: 'Laden', category: 'Bereich', icon: Icons.store_outlined, path: '/laden', isTab: true, detail: 'Laden-Übersicht & Bereiche'),
  GlobalSearchItem(label: 'Profil', category: 'Bereich', icon: Icons.person_outline, path: '/profil', isTab: true, detail: 'Konto & App-Einstellungen'),
  // Hauptbereich-Routen
  GlobalSearchItem(label: 'Warenwirtschaft', category: 'Bereich', icon: Icons.inventory_2_outlined, path: AppRoutes.inventory, detail: 'Bestand, Lieferanten & Bestellungen'),
  GlobalSearchItem(label: 'Kundenbestellungen', category: 'Bereich', icon: Icons.receipt_long_outlined, path: AppRoutes.customerOrders, detail: 'Sonderbestellungen von Kunden'),
  GlobalSearchItem(label: 'Scanner', category: 'Bereich', icon: Icons.qr_code_scanner_rounded, path: AppRoutes.scanner, detail: 'Artikel per Barcode finden'),
  GlobalSearchItem(label: 'Kundenwünsche', category: 'Bereich', icon: Icons.volunteer_activism_outlined, path: AppRoutes.customerWishes, detail: 'Eingegangene Wünsche'),
  GlobalSearchItem(label: 'Feedback-Eingang', category: 'Bereich', icon: Icons.feedback_outlined, path: AppRoutes.feedbackInbox, detail: 'Kundenfeedback & Beschwerden'),
  GlobalSearchItem(label: 'Inventur', category: 'Bereich', icon: Icons.fact_check_outlined, path: AppRoutes.inventur, detail: 'Geführte Bestandszählung'),
  GlobalSearchItem(label: 'Sortimentsanalyse', category: 'Bereich', icon: Icons.analytics_outlined, path: AppRoutes.sortiment, detail: 'Rohertrag & ABC-Analyse'),
  GlobalSearchItem(label: 'Bestand-Insights', category: 'Bereich', icon: Icons.insights_outlined, path: AppRoutes.bestandInsights, detail: 'Reichweite & Meldebestände'),
  GlobalSearchItem(label: 'Bestell-Auswertung', category: 'Bereich', icon: Icons.query_stats_outlined, path: AppRoutes.orderAnalytics, detail: 'Bestellhäufigkeit je Artikel'),
  GlobalSearchItem(label: 'Laden-Benchmark', category: 'Bereich', icon: Icons.leaderboard_outlined, path: AppRoutes.storeHealth, detail: 'Standort-Vergleich'),
  GlobalSearchItem(label: 'Kassierer-Prüfung', category: 'Bereich', icon: Icons.rule_folder_outlined, path: AppRoutes.cashierAnomaly, detail: 'Auffälligkeiten an der Kasse'),
  GlobalSearchItem(label: 'Personal', category: 'Bereich', icon: Icons.badge_outlined, path: AppRoutes.personal, detail: 'Mitarbeiter, Gehälter & Finanzen'),
  GlobalSearchItem(label: 'Buchhaltung', category: 'Bereich', icon: Icons.account_balance_outlined, path: AppRoutes.finance, detail: 'Kostenstellen, Buchungen & DATEV'),
  GlobalSearchItem(label: 'Tagesabschluss', category: 'Bereich', icon: Icons.point_of_sale_outlined, path: AppRoutes.dailyClosing, detail: 'Kassenzählung & Abschluss'),
  GlobalSearchItem(label: 'Statistik', category: 'Bereich', icon: Icons.bar_chart_rounded, path: AppRoutes.statistics, detail: 'Monats- & Jahresauswertungen'),
  GlobalSearchItem(label: 'Monatsbericht', category: 'Bereich', icon: Icons.summarize_outlined, path: AppRoutes.monthReport, detail: 'Stunden als PDF'),
  GlobalSearchItem(label: 'Besetzungs-Profil', category: 'Bereich', icon: Icons.event_seat_outlined, path: AppRoutes.staffingProfile, detail: 'Bedarf & Öffnungszeiten'),
  GlobalSearchItem(label: 'Änderungsprotokoll', category: 'Bereich', icon: Icons.history_rounded, path: AppRoutes.auditLog, detail: 'Wer hat was geändert'),
  GlobalSearchItem(label: 'Einstellungen', category: 'Bereich', icon: Icons.settings_outlined, path: AppRoutes.settings, detail: 'Profil, Theme & Standardwerte'),
  // Zeitwirtschaft
  GlobalSearchItem(label: 'Stempeluhr', category: 'Bereich', icon: Icons.punch_clock_outlined, path: AppRoutes.zeitStempeln, detail: 'Kommen & Gehen stempeln'),
  GlobalSearchItem(label: 'Zeiterfassung', category: 'Bereich', icon: Icons.more_time_outlined, path: AppRoutes.zeitErfassung, detail: 'Zeiten erfassen & freigeben'),
  GlobalSearchItem(label: 'Stundenkonto', category: 'Bereich', icon: Icons.savings_outlined, path: AppRoutes.zeitStundenkonto, detail: 'Saldo & Gleitzeit'),
  GlobalSearchItem(label: 'Abwesenheiten', category: 'Bereich', icon: Icons.beach_access_outlined, path: AppRoutes.zeitAbwesenheiten, detail: 'Urlaub & Krankheit'),
];

/// Baut die durchsuchbare Trefferliste: permission-gefilterte Bereiche +
/// Datensätze (Kontakte/Artikel/Mitarbeiter) aus den bereits geladenen
/// Providern. Datensätze deep-linken direkt auf ihre Detailseite, wo möglich.
List<GlobalSearchItem> buildGlobalSearchItems(
  BuildContext context,
  AppUserProfile? user,
) {
  final items = <GlobalSearchItem>[
    for (final d in _destinations)
      if (RoutePermissions.isLocationAllowed(d.path, user)) d,
  ];

  if (user?.canViewContacts ?? false) {
    for (final c in context.read<ContactProvider>().contacts) {
      final id = c.id;
      items.add(GlobalSearchItem(
        label: c.name,
        category: 'Kontakt',
        icon: c.kind == ContactKind.person
            ? Icons.person_outline
            : Icons.apartment_outlined,
        detail: [
          c.type.shortLabel,
          if ((c.city ?? '').trim().isNotEmpty) c.city!.trim(),
        ].join(' · '),
        // Deep-Link direkt in die Kontakt-Detailseite (falls die ID vorliegt),
        // sonst auf den Kontakte-Tab als Fallback.
        path: id != null ? AppRoutes.contactDetailPath(id) : '/kontakte',
        isTab: id == null,
      ));
    }
  }
  if (user?.canViewInventory ?? false) {
    for (final p in context.read<InventoryProvider>().products) {
      if (!p.isActive) continue;
      items.add(GlobalSearchItem(
        label: p.name,
        category: 'Artikel',
        icon: Icons.inventory_2_outlined,
        detail: [
          if ((p.category ?? '').trim().isNotEmpty) p.category!.trim(),
          if ((p.siteName ?? '').trim().isNotEmpty) p.siteName!.trim(),
        ].join(' · '),
        path: AppRoutes.inventory,
      ));
    }
  }
  if (user?.isAdmin ?? false) {
    for (final m in context.read<TeamProvider>().members) {
      items.add(GlobalSearchItem(
        label: m.displayName,
        category: 'Mitarbeiter',
        icon: Icons.badge_outlined,
        detail: m.role.label,
        // Direkt in die Personalakte des Mitarbeiters (9-Tab-Detail).
        path: AppRoutes.personalDetailPath(m.uid),
      ));
    }
  }
  return items;
}

// --- Reines, testbares Ranking ------------------------------------------------

/// Diakritik-/Groß-Kleinschreibung-unempfindliche, **längentreue** Normalisierung
/// (jedes Zeichen → genau ein Zeichen), damit Treffer-Indizes 1:1 auf das
/// Original-Label abbilden (für die Hervorhebung).
String foldSearch(String s) => s
    .toLowerCase()
    .split('')
    .map((c) => switch (c) {
          'ä' => 'a',
          'ö' => 'o',
          'ü' => 'u',
          'ß' => 's',
          _ => c,
        })
    .join();

final RegExp _wordSplit = RegExp(r'[\s/\-_.,()]+');

/// Relevanz-Score eines Labels für die (bereits gefaltete) Anfrage [q].
/// Höher = besser; `-1` = kein Treffer. Ranking-Stufen: exakt › Präfix ›
/// Wortanfang › Teilstring (früher = besser) › Fuzzy-Teilfolge.
int scoreSearch(String q, String label) {
  if (q.isEmpty) return 0;
  final l = foldSearch(label);
  if (l == q) return 1000;
  if (l.startsWith(q)) return 800;
  for (final w in l.split(_wordSplit)) {
    if (w.isNotEmpty && w.startsWith(q)) return 640;
  }
  final idx = l.indexOf(q);
  if (idx >= 0) return 480 - (idx > 40 ? 40 : idx);
  if (_isSubsequence(q, l)) return 200;
  return -1;
}

/// true, wenn alle Zeichen von [q] in [l] in Reihenfolge vorkommen (Fuzzy).
bool _isSubsequence(String q, String l) {
  if (q.isEmpty) return true;
  var i = 0;
  for (var j = 0; j < l.length && i < q.length; j++) {
    if (l[j] == q[i]) i++;
  }
  return i == q.length;
}

/// Original-Index-Bereich `[start, end)` des ersten Treffers von [query] in
/// [label] (für die Hervorhebung), oder `null` bei Teilfolgen-/keinem Treffer.
(int, int)? searchHighlightRange(String label, String query) {
  final q = foldSearch(query.trim());
  if (q.isEmpty) return null;
  final idx = foldSearch(label).indexOf(q);
  if (idx < 0) return null;
  return (idx, idx + q.length);
}

const List<String> _categoryOrder = <String>[
  'Bereich',
  'Kontakt',
  'Mitarbeiter',
  'Artikel',
];
const Map<String, String> _categoryTitle = <String, String>{
  'Bereich': 'Bereiche',
  'Kontakt': 'Kontakte',
  'Mitarbeiter': 'Mitarbeiter',
  'Artikel': 'Artikel',
};
const int _perGroupCap = 8;

int _categoryOrderIndex(String category) {
  final i = _categoryOrder.indexOf(category);
  return i < 0 ? _categoryOrder.length : i;
}

/// Rankt [items] gegen [query] und gruppiert sie nach Kategorie. Leere Anfrage →
/// nur die Bereiche (Schnellzugriff-Sprungbrett). Gruppen sind nach bestem Score
/// sortiert, Treffer innerhalb nach Score/Länge/Alphabet; je Gruppe auf
/// [_perGroupCap] gedeckelt (Rest via [GlobalSearchGroup.totalCount] sichtbar).
List<GlobalSearchGroup> rankGlobalSearch(
  List<GlobalSearchItem> items,
  String query,
) {
  final q = foldSearch(query.trim());
  if (q.isEmpty) {
    final areas = [for (final i in items) if (i.category == 'Bereich') i];
    return areas.isEmpty
        ? const <GlobalSearchGroup>[]
        : <GlobalSearchGroup>[
            GlobalSearchGroup(
              category: 'Bereich',
              title: _categoryTitle['Bereich']!,
              items: areas,
              totalCount: areas.length,
            ),
          ];
  }

  final byCategory = <String, List<(int, GlobalSearchItem)>>{};
  for (final item in items) {
    final score = scoreSearch(q, item.label);
    if (score < 0) continue;
    byCategory.putIfAbsent(item.category, () => []).add((score, item));
  }
  if (byCategory.isEmpty) return const <GlobalSearchGroup>[];

  final groups = <GlobalSearchGroup>[];
  byCategory.forEach((category, scored) {
    scored.sort((a, b) {
      final byScore = b.$1.compareTo(a.$1);
      if (byScore != 0) return byScore;
      final byLen = a.$2.label.length.compareTo(b.$2.label.length);
      if (byLen != 0) return byLen;
      return a.$2.label.toLowerCase().compareTo(b.$2.label.toLowerCase());
    });
    final shown = scored.length > _perGroupCap
        ? scored.sublist(0, _perGroupCap)
        : scored;
    groups.add(GlobalSearchGroup(
      category: category,
      title: _categoryTitle[category] ?? category,
      items: [for (final e in shown) e.$2],
      bestScore: scored.first.$1,
      totalCount: scored.length,
    ));
  });

  groups.sort((a, b) {
    final byScore = b.bestScore.compareTo(a.bestScore);
    if (byScore != 0) return byScore;
    return _categoryOrderIndex(a.category)
        .compareTo(_categoryOrderIndex(b.category));
  });
  return groups;
}

/// Öffnet die globale Such-Palette (Anf. 24/25). Liest Rechte + Datensätze aus
/// dem aktuellen Kontext und zeigt eine responsive Befehls-Palette
/// (Kommandozeilen-Stil): breit = zentriert, schmal = Vollbild.
Future<void> showGlobalSearch(BuildContext context) {
  final user = context.read<AuthProvider>().profile;
  final items = buildGlobalSearchItems(context, user);
  final router = GoRouter.of(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Suche schließen',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration:
        AppMotion.resolve(context, const Duration(milliseconds: 180)),
    pageBuilder: (_, __, ___) =>
        GlobalSearchPalette(items: items, router: router),
    transitionBuilder: (context, animation, _, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: FractionalTranslation(
          translation: Offset(0, (1 - curved.value) * -0.02),
          child: child,
        ),
      );
    },
  );
}

/// Responsive, tastatur-bedienbare globale Such-Palette (⌘K-Stil): gerankte,
/// nach Kategorie gruppierte Treffer mit Hervorhebung; ↑/↓ zum Navigieren,
/// ↵ öffnet den markierten Treffer, Esc schließt.
class GlobalSearchPalette extends StatefulWidget {
  const GlobalSearchPalette({
    super.key,
    required this.items,
    required this.router,
  });

  final List<GlobalSearchItem> items;
  final GoRouter router;

  @override
  State<GlobalSearchPalette> createState() => _GlobalSearchPaletteState();
}

class _GlobalSearchPaletteState extends State<GlobalSearchPalette> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _keyboardFocus = FocusNode(debugLabel: 'searchPaletteKeys');
  final ScrollController _scroll = ScrollController();

  List<GlobalSearchGroup> _groups = const [];
  List<GlobalSearchItem> _flat = const [];
  List<GlobalKey> _itemKeys = const [];
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _recompute('');
  }

  @override
  void dispose() {
    _controller.dispose();
    _keyboardFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _recompute(String query) {
    _groups = rankGlobalSearch(widget.items, query);
    _flat = [for (final g in _groups) ...g.items];
    _itemKeys = [for (var i = 0; i < _flat.length; i++) GlobalKey()];
    _selected = _flat.isEmpty ? -1 : 0;
  }

  void _onQueryChanged(String value) {
    setState(() => _recompute(value));
  }

  void _move(int delta) {
    if (_flat.isEmpty) return;
    setState(() {
      _selected = (_selected + delta).clamp(0, _flat.length - 1);
    });
    // Pfeiltasten bewegen sonst nur eine visuelle Auswahl — den neu markierten
    // Treffer für Screenreader (VoiceOver/TalkBack) ansagen.
    final item = _flat[_selected];
    final detail = (item.detail ?? '').isNotEmpty ? ', ${item.detail}' : '';
    // N3: announce ist deprecated (Multi-Window-inkompatibel) -> View-gebundene
    // sendAnnouncement-Variante.
    SemanticsService.sendAnnouncement(
      View.of(context),
      '${item.label}$detail',
      TextDirection.ltr,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _selected >= 0 && _selected < _itemKeys.length
          ? _itemKeys[_selected].currentContext
          : null;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.1,
          // Reduce-Motion respektieren (Duration.zero → sofortiger Sprung).
          duration: AppMotion.resolve(context, const Duration(milliseconds: 120)),
        );
      }
    });
  }

  void _activate(GlobalSearchItem item) {
    Navigator.of(context).pop();
    item.navigate(widget.router);
  }

  void _activateSelected() {
    if (_selected >= 0 && _selected < _flat.length) {
      _activate(_flat[_selected]);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _move(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _move(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 600;
    final colorScheme = Theme.of(context).colorScheme;

    final palette = Focus(
      focusNode: _keyboardFocus,
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: Column(
        mainAxisSize: wide ? MainAxisSize.min : MainAxisSize.max,
        children: [
          _SearchField(
            controller: _controller,
            onChanged: _onQueryChanged,
            onSubmitted: (_) => _activateSelected(),
            onClose: () => Navigator.of(context).pop(),
            wide: wide,
          ),
          Divider(height: 1, thickness: 1, color: colorScheme.outlineVariant),
          if (wide)
            Flexible(child: _results(shrinkWrap: true, showSelection: true))
          else
            Expanded(child: _results(shrinkWrap: false, showSelection: false)),
          if (wide) const _KeyboardHints(),
        ],
      ),
    );

    if (!wide) {
      // Schmal: Vollbild-Fläche.
      return Material(
        color: colorScheme.surface,
        child: SafeArea(child: palette),
      );
    }

    // Breit: zentrierte Karte im oberen Drittel (Spotlight-/⌘K-Anmutung).
    return SafeArea(
      child: Align(
        alignment: const Alignment(0, -0.55),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 640,
              maxHeight: size.height * 0.7,
            ),
            child: Material(
              color: colorScheme.surface,
              elevation: 8,
              shadowColor: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(context.radii.xl),
              clipBehavior: Clip.antiAlias,
              child: palette,
            ),
          ),
        ),
      ),
    );
  }

  Widget _results({required bool shrinkWrap, required bool showSelection}) {
    if (_flat.isEmpty && _controller.text.trim().isNotEmpty) {
      return _EmptyResults(query: _controller.text.trim());
    }

    // Zeilen aufbauen: je Gruppe ein Header + ihre (indizierten) Treffer.
    final rows = <Widget>[];
    var flatIndex = 0;
    for (final group in _groups) {
      rows.add(_GroupHeader(title: group.title, count: group.totalCount));
      for (final item in group.items) {
        final index = flatIndex;
        rows.add(_ResultTile(
          key: _itemKeys[index],
          item: item,
          query: _controller.text,
          // Auf Touch (schmal) nichts vorab hervorheben — die markierte Zeile +
          // ↵-Hinweis sind ein Tastatur-Idiom (breit).
          selected: showSelection && index == _selected,
          onHover: () {
            if (_selected != index) setState(() => _selected = index);
          },
          onTap: () => _activate(item),
        ));
        flatIndex++;
      }
      if (group.totalCount > group.items.length) {
        rows.add(_MoreHint(
          remaining: group.totalCount - group.items.length,
        ));
      }
    }

    return ListView(
      controller: _scroll,
      shrinkWrap: shrinkWrap,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: rows,
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClose,
    required this.wide,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClose;

  /// Breit = zentrierte Karte (Schließen-× rechts, Suchsymbol links); schmal =
  /// Vollbild (führende Zurück-Taste).
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Row(
        children: [
          if (wide)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.search_rounded,
                  color: colorScheme.onSurfaceVariant),
            )
          else
            IconButton(
              tooltip: 'Zurück',
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: onClose,
            ),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.go,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              style: theme.textTheme.titleMedium,
              decoration: InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                hintText: 'Suchen – Bereiche, Kontakte, Artikel, Mitarbeiter …',
                hintStyle: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
          // Eingabe leeren (nur bei Text) — gefülltes ⊗, klar von „Schließen".
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox(width: 4);
              return IconButton(
                tooltip: 'Suche leeren',
                icon: const Icon(Icons.cancel),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              );
            },
          ),
          // Sichtbare Schließen-Taste auch breit (Touch-Tablet ohne Tastatur
          // hätte sonst nur den undiscoverable Klick daneben).
          if (wide)
            IconButton(
              tooltip: 'Schließen',
              icon: const Icon(Icons.close_rounded),
              onPressed: onClose,
            ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Als Überschrift auszeichnen (Rotor-/Heading-Navigation) mit
    // selbsterklärendem Namen; die rohen Text-Knoten aus der A11y ausblenden.
    return Semantics(
      header: true,
      label: '$title, $count Treffer',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Row(
            children: [
              Text(
                title.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$count',
                style: theme.textTheme.labelSmall?.copyWith(
                  color:
                      theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    super.key,
    required this.item,
    required this.query,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  final GlobalSearchItem item;
  final String query;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return MouseRegion(
      onEnter: (_) => onHover(),
      child: Semantics(
        button: true,
        selected: selected,
        label: item.label,
        child: Material(
          color: selected
              ? colorScheme.secondaryContainer.withValues(alpha: 0.6)
              : Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: selected
                          ? colorScheme.primary.withValues(alpha: 0.16)
                          : colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(context.radii.sm),
                    ),
                    child: Icon(item.icon,
                        size: 20,
                        color: selected
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _HighlightedLabel(
                          label: item.label,
                          query: query,
                          selected: selected,
                        ),
                        if ((item.detail ?? '').isNotEmpty) ...[
                          const SizedBox(height: 1),
                          Text(
                            item.detail!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (selected)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(Icons.keyboard_return_rounded,
                          size: 16,
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.7)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Titel mit hervorgehobenem Treffer-Bereich (fett + Primärfarbe).
class _HighlightedLabel extends StatelessWidget {
  const _HighlightedLabel({
    required this.label,
    required this.query,
    required this.selected,
  });

  final String label;
  final String query;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final base = theme.textTheme.bodyLarge?.copyWith(
      fontWeight: FontWeight.w600,
      color: colorScheme.onSurface,
    );
    final range = searchHighlightRange(label, query);
    if (range == null) {
      return Text(label,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: base);
    }
    final (start, end) = range;
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          if (start > 0) TextSpan(text: label.substring(0, start)),
          TextSpan(
            text: label.substring(start, end),
            style: TextStyle(
              color: colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (end < label.length) TextSpan(text: label.substring(end)),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _MoreHint extends StatelessWidget {
  const _MoreHint({required this.remaining});

  final int remaining;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(64, 2, 20, 8),
      child: Text(
        '+$remaining weitere – Suche verfeinern',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded,
              size: 40, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            'Keine Treffer für „$query"',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Prüfe die Schreibweise oder suche nach einem anderen Begriff.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tastatur-Hinweiszeile (nur breite Layouts).
class _KeyboardHints extends StatelessWidget {
  const _KeyboardHints();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const _KeyCap(icon: Icons.keyboard_arrow_up_rounded),
          const SizedBox(width: 4),
          const _KeyCap(icon: Icons.keyboard_arrow_down_rounded),
          const SizedBox(width: 6),
          Text('navigieren',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant)),
          const SizedBox(width: 16),
          const _KeyCap(icon: Icons.keyboard_return_rounded),
          const SizedBox(width: 6),
          Text('öffnen',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant)),
          const SizedBox(width: 16),
          const _KeyCap(label: 'Esc'),
          const SizedBox(width: 6),
          Text('schließen',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _KeyCap extends StatelessWidget {
  const _KeyCap({this.label, this.icon}) : assert(label != null || icon != null);

  final String? label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 24, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: icon != null
          ? Icon(icon, size: 16, color: colorScheme.onSurfaceVariant)
          : Text(
              label!,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}
