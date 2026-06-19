import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/widgets/breadcrumb_app_bar.dart';
import 'package:worktime_app/widgets/info_chip.dart';
import 'package:worktime_app/widgets/section_card.dart';
import 'package:worktime_app/widgets/section_header.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  group('aus home_screen extrahierte Reuse-Widgets', () {
    testWidgets('SectionHeader zeigt Titel + Untertitel', (tester) async {
      await _pump(
        tester,
        const SectionHeader(title: 'Mein Titel', subtitle: 'Untertitel hier'),
      );
      expect(find.text('Mein Titel'), findsOneWidget);
      expect(find.text('Untertitel hier'), findsOneWidget);
    });

    testWidgets('SectionHeader rendert Breadcrumb wenn vorhanden',
        (tester) async {
      await _pump(
        tester,
        const SectionHeader(
          title: 'T',
          subtitle: 'S',
          breadcrumbs: [BreadcrumbItem(label: 'Start')],
        ),
      );
      expect(find.byType(ShellBreadcrumb), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('SectionCard zeigt Titel-Pill + Kind', (tester) async {
      await _pump(
        tester,
        const SectionCard(title: 'Abschnitt', child: Text('Inhalt')),
      );
      expect(find.text('Abschnitt'), findsOneWidget);
      expect(find.text('Inhalt'), findsOneWidget);
    });

    testWidgets('InfoChip zeigt Icon + Label', (tester) async {
      await _pump(
        tester,
        const InfoChip(icon: Icons.schedule, label: '8 Stunden'),
      );
      expect(find.text('8 Stunden'), findsOneWidget);
      expect(find.byIcon(Icons.schedule), findsOneWidget);
    });
  });
}
