import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/contact_provider.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/team_provider.dart';
import '../../routing/route_permissions.dart';
import '../../routing/shell_tab.dart';

/// Ein Treffer der globalen Suche: Label + Kategorie + Icon + Navigationsziel
/// (Anf. 24 „schnell finden" / 25 „wenige Schritte").
class GlobalSearchItem {
  const GlobalSearchItem({
    required this.label,
    required this.category,
    required this.icon,
    required this.path,
    this.isTab = false,
  });

  final String label;
  final String category;
  final IconData icon;
  final String path;

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

/// Alle navigierbaren **Bereiche/Module** (zuverlässige Deep-Links). Wird beim
/// Öffnen der Suche per [RoutePermissions] auf die Rechte des Nutzers gefiltert.
const List<GlobalSearchItem> _destinations = <GlobalSearchItem>[
  // Tabs
  GlobalSearchItem(
      label: 'Heute', category: 'Bereich', icon: Icons.today_rounded, path: '/', isTab: true),
  GlobalSearchItem(
      label: 'Plan', category: 'Bereich', icon: Icons.view_timeline_outlined, path: '/plan', isTab: true),
  GlobalSearchItem(
      label: 'Zeit', category: 'Bereich', icon: Icons.schedule_rounded, path: '/zeit', isTab: true),
  GlobalSearchItem(
      label: 'Anfragen', category: 'Bereich', icon: Icons.inbox_outlined, path: '/anfragen', isTab: true),
  GlobalSearchItem(
      label: 'Kontakte', category: 'Bereich', icon: Icons.contacts_outlined, path: '/kontakte', isTab: true),
  GlobalSearchItem(
      label: 'Laden', category: 'Bereich', icon: Icons.store_outlined, path: '/laden', isTab: true),
  GlobalSearchItem(
      label: 'Profil', category: 'Bereich', icon: Icons.person_outline, path: '/profil', isTab: true),
  // Hauptbereich-Routen
  GlobalSearchItem(label: 'Warenwirtschaft', category: 'Bereich', icon: Icons.inventory_2_outlined, path: AppRoutes.inventory),
  GlobalSearchItem(label: 'Kundenbestellungen', category: 'Bereich', icon: Icons.receipt_long_outlined, path: AppRoutes.customerOrders),
  GlobalSearchItem(label: 'Scanner', category: 'Bereich', icon: Icons.qr_code_scanner_rounded, path: AppRoutes.scanner),
  GlobalSearchItem(label: 'Kundenwünsche', category: 'Bereich', icon: Icons.volunteer_activism_outlined, path: AppRoutes.customerWishes),
  GlobalSearchItem(label: 'Feedback-Eingang', category: 'Bereich', icon: Icons.feedback_outlined, path: AppRoutes.feedbackInbox),
  GlobalSearchItem(label: 'Sortimentsanalyse', category: 'Bereich', icon: Icons.analytics_outlined, path: AppRoutes.sortiment),
  GlobalSearchItem(label: 'Bestand-Insights', category: 'Bereich', icon: Icons.insights_outlined, path: AppRoutes.bestandInsights),
  GlobalSearchItem(label: 'Bestell-Auswertung', category: 'Bereich', icon: Icons.query_stats_outlined, path: AppRoutes.orderAnalytics),
  GlobalSearchItem(label: 'Laden-Benchmark', category: 'Bereich', icon: Icons.leaderboard_outlined, path: AppRoutes.storeHealth),
  GlobalSearchItem(label: 'Kassierer-Prüfung', category: 'Bereich', icon: Icons.rule_folder_outlined, path: AppRoutes.cashierAnomaly),
  GlobalSearchItem(label: 'Team', category: 'Bereich', icon: Icons.groups_outlined, path: AppRoutes.team),
  GlobalSearchItem(label: 'Personal', category: 'Bereich', icon: Icons.badge_outlined, path: AppRoutes.personal),
  GlobalSearchItem(label: 'Buchhaltung', category: 'Bereich', icon: Icons.account_balance_outlined, path: AppRoutes.finance),
  GlobalSearchItem(label: 'Tagesabschluss', category: 'Bereich', icon: Icons.point_of_sale_outlined, path: AppRoutes.dailyClosing),
  GlobalSearchItem(label: 'Statistik', category: 'Bereich', icon: Icons.bar_chart_rounded, path: AppRoutes.statistics),
  GlobalSearchItem(label: 'Monatsbericht', category: 'Bereich', icon: Icons.summarize_outlined, path: AppRoutes.monthReport),
  GlobalSearchItem(label: 'Besetzungs-Profil', category: 'Bereich', icon: Icons.event_seat_outlined, path: AppRoutes.staffingProfile),
  GlobalSearchItem(label: 'Änderungsprotokoll', category: 'Bereich', icon: Icons.history_rounded, path: AppRoutes.auditLog),
  GlobalSearchItem(label: 'Einstellungen', category: 'Bereich', icon: Icons.settings_outlined, path: AppRoutes.settings),
  // Zeitwirtschaft
  GlobalSearchItem(label: 'Stempeluhr', category: 'Bereich', icon: Icons.punch_clock_outlined, path: AppRoutes.zeitStempeln),
  GlobalSearchItem(label: 'Zeiterfassung', category: 'Bereich', icon: Icons.more_time_outlined, path: AppRoutes.zeitErfassung),
  GlobalSearchItem(label: 'Stundenkonto', category: 'Bereich', icon: Icons.savings_outlined, path: AppRoutes.zeitStundenkonto),
  GlobalSearchItem(label: 'Abwesenheiten', category: 'Bereich', icon: Icons.beach_access_outlined, path: AppRoutes.zeitAbwesenheiten),
];

/// Baut die durchsuchbare Trefferliste: permission-gefilterte Bereiche +
/// Datensätze (Kontakte/Artikel/Mitarbeiter) aus den bereits geladenen
/// Providern. Datensätze springen zum jeweiligen Bereich (Deep-Link auf den
/// einzelnen Satz je Screen ist ein späterer Ausbau).
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
      items.add(GlobalSearchItem(
        label: c.name,
        category: 'Kontakt',
        icon: Icons.person_outline,
        path: '/kontakte',
        isTab: true,
      ));
    }
  }
  if (user?.canViewInventory ?? false) {
    for (final p in context.read<InventoryProvider>().products) {
      items.add(GlobalSearchItem(
        label: p.name,
        category: 'Artikel',
        icon: Icons.inventory_2_outlined,
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
        path: AppRoutes.team,
      ));
    }
  }
  return items;
}

/// Öffnet die globale Suche (Anf. 24/25). Liest Rechte + Datensätze aus dem
/// aktuellen Kontext und übergibt sie an das [SearchDelegate].
Future<void> showGlobalSearch(BuildContext context) {
  final user = context.read<AuthProvider>().profile;
  final items = buildGlobalSearchItems(context, user);
  return showSearch<void>(
    context: context,
    delegate: GlobalSearchDelegate(items),
  );
}

/// Vereinheitlichte, tokenisierte, screenreader-freundliche globale Suche.
class GlobalSearchDelegate extends SearchDelegate<void> {
  GlobalSearchDelegate(this.items) : super(searchFieldLabel: 'Suchen …');

  final List<GlobalSearchItem> items;

  String _fold(String s) => s
      .toLowerCase()
      .replaceAll('ä', 'a')
      .replaceAll('ö', 'o')
      .replaceAll('ü', 'u')
      .replaceAll('ß', 'ss');

  List<GlobalSearchItem> _filtered() {
    final q = _fold(query.trim());
    if (q.isEmpty) {
      // Leere Eingabe → schnelle Sprünge zu den Bereichen.
      return items.where((i) => i.category == 'Bereich').toList();
    }
    return items.where((i) => _fold(i.label).contains(q)).take(60).toList();
  }

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            tooltip: 'Suche leeren',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        tooltip: 'Zurück',
        icon: const BackButtonIcon(),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    final results = _filtered();
    if (results.isEmpty) {
      return Center(
        child: Text(
          'Keine Treffer für „$query"',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final item = results[index];
        return ListTile(
          leading: Icon(item.icon),
          title: Text(item.label),
          subtitle: Text(item.category),
          onTap: () {
            final router = GoRouter.of(context);
            close(context, null);
            item.navigate(router);
          },
        );
      },
    );
  }
}
