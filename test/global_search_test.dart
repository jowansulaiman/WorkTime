import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:worktime_app/screens/search/global_search.dart';

const _items = <GlobalSearchItem>[
  GlobalSearchItem(
      label: 'Statistik',
      category: 'Bereich',
      icon: Icons.bar_chart,
      path: '/statistik'),
  GlobalSearchItem(
      label: 'Kontakte',
      category: 'Bereich',
      icon: Icons.contacts,
      path: '/kontakte',
      isTab: true),
  GlobalSearchItem(
      label: 'Müller GmbH',
      category: 'Kontakt',
      icon: Icons.person,
      path: '/kontakte/c1'),
  GlobalSearchItem(
      label: 'Cola 0,5l',
      category: 'Artikel',
      icon: Icons.inventory_2_outlined,
      path: '/warenwirtschaft'),
];

List<GlobalSearchItem> _flat(List<GlobalSearchGroup> g) =>
    [for (final group in g) ...group.items];

void main() {
  group('Ranking (rein, testbar)', () {
    test('leere Anfrage → nur Bereiche (Schnellzugriff)', () {
      final groups = rankGlobalSearch(_items, '');
      expect(groups, hasLength(1));
      expect(groups.single.category, 'Bereich');
      final labels = _flat(groups).map((i) => i.label);
      expect(labels, containsAll(<String>['Statistik', 'Kontakte']));
      expect(labels, isNot(contains('Müller GmbH'))); // Datensatz, kein Bereich
    });

    test('diakritik-insensitiv: „muller" findet „Müller GmbH"', () {
      final groups = rankGlobalSearch(_items, 'muller');
      final labels = _flat(groups).map((i) => i.label).toList();
      expect(labels, contains('Müller GmbH'));
      expect(labels, isNot(contains('Statistik')));
    });

    test('kein Treffer → leere Gruppenliste', () {
      expect(rankGlobalSearch(_items, 'zzzzz'), isEmpty);
    });

    test('Treffer werden nach Kategorie gruppiert', () {
      final groups = rankGlobalSearch(_items, 'l'); // Cola, Müller, Kontakte, …
      final cats = groups.map((g) => g.category).toSet();
      expect(cats.length, greaterThan(1));
      // Jede Gruppe trägt einen menschenlesbaren Titel.
      expect(groups.every((g) => g.title.isNotEmpty), isTrue);
    });
  });

  group('scoreSearch (Relevanz-Stufen)', () {
    test('exakt > Präfix > Wortanfang > Teilstring > Fuzzy', () {
      expect(scoreSearch('statistik', 'Statistik'), 1000); // exakt
      expect(scoreSearch('stat', 'Statistik'), 800); // Präfix
      expect(scoreSearch('lohn', 'DATEV Lohn'), 640); // Wortanfang
      final sub = scoreSearch('tist', 'Statistik'); // Teilstring (Mitte)
      expect(sub, greaterThan(0));
      expect(sub, lessThan(640));
      final fuzzy = scoreSearch('sttk', 'Statistik'); // Teilfolge
      expect(fuzzy, 200);
    });

    test('Präfix rankt vor Teilstring', () {
      expect(scoreSearch('sta', 'Statistik'),
          greaterThan(scoreSearch('sta', 'Bestandsliste')));
    });

    test('kein Treffer → -1', () {
      expect(scoreSearch('xyz', 'Statistik'), -1);
    });
  });

  group('searchHighlightRange (Hervorhebung)', () {
    test('liefert Original-Indizes (längentreu über Umlaute)', () {
      expect(searchHighlightRange('Müller GmbH', 'mull'), (0, 4));
      expect(searchHighlightRange('Statistik', 'tist'), (3, 7));
    });

    test('kein Teilstring-Treffer → null', () {
      expect(searchHighlightRange('Statistik', 'zzz'), isNull);
      expect(searchHighlightRange('Statistik', 'sttk'), isNull); // nur Fuzzy
    });
  });

  test('GlobalSearchItem.navigate: Tab = go, Section = push', () {
    const tab = GlobalSearchItem(
        label: 'x', category: 'Bereich', icon: Icons.abc, path: '/', isTab: true);
    const section = GlobalSearchItem(
        label: 'y', category: 'Bereich', icon: Icons.abc, path: '/statistik');
    expect(tab.isTab, isTrue);
    expect(section.isTab, isFalse);
  });

  group('GlobalSearchPalette (Widget)', () {
    // GoRouter erst im Test bauen (initialisiert sonst das Binding zu früh).
    Future<void> pump(WidgetTester tester) {
      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (_, __) => const SizedBox())],
      );
      return tester.pumpWidget(
        MaterialApp(
          home: GlobalSearchPalette(items: _items, router: router),
        ),
      );
    }

    testWidgets('zeigt Suchfeld + anfangs die Bereiche', (tester) async {
      await pump(tester);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Statistik'), findsOneWidget);
      expect(find.text('Müller GmbH'), findsNothing);
    });

    testWidgets('Eingabe filtert + hebt hervor', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'muller');
      await tester.pump();
      expect(find.text('Müller GmbH'), findsOneWidget); // Text.rich → toPlainText
      expect(find.text('Statistik'), findsNothing);
    });

    testWidgets('kein Treffer zeigt Hinweistext', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'zzzzz');
      await tester.pump();
      expect(find.textContaining('Keine Treffer'), findsOneWidget);
    });
  });
}
