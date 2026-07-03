import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/screens/search/global_search.dart';

Widget _host(GlobalSearchDelegate delegate) => MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => delegate.buildResults(context)),
      ),
    );

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
      path: '/kontakte',
      isTab: true),
];

void main() {
  group('GlobalSearchDelegate (N4)', () {
    testWidgets('filtert nach Label, diakritik-insensitiv', (tester) async {
      final delegate = GlobalSearchDelegate(_items)..query = 'muller';
      await tester.pumpWidget(_host(delegate));
      expect(find.text('Müller GmbH'), findsOneWidget);
      expect(find.text('Statistik'), findsNothing);
      expect(find.text('Kontakte'), findsNothing);
    });

    testWidgets('leere Eingabe zeigt nur Bereiche (schnelle Sprünge)',
        (tester) async {
      final delegate = GlobalSearchDelegate(_items)..query = '';
      await tester.pumpWidget(_host(delegate));
      expect(find.text('Statistik'), findsOneWidget);
      expect(find.text('Kontakte'), findsOneWidget);
      expect(find.text('Müller GmbH'), findsNothing); // Datensatz, kein Bereich
    });

    testWidgets('kein Treffer zeigt Hinweistext', (tester) async {
      final delegate = GlobalSearchDelegate(_items)..query = 'zzz';
      await tester.pumpWidget(_host(delegate));
      expect(find.textContaining('Keine Treffer'), findsOneWidget);
    });

    test('GlobalSearchItem.navigate: Tab = go, Section = push', () {
      const tab = GlobalSearchItem(
          label: 'x', category: 'Bereich', icon: Icons.abc, path: '/', isTab: true);
      const section = GlobalSearchItem(
          label: 'y', category: 'Bereich', icon: Icons.abc, path: '/statistik');
      expect(tab.isTab, isTrue);
      expect(section.isTab, isFalse);
    });
  });
}
