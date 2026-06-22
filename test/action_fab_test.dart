import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/widgets/action_fab.dart';

void main() {
  testWidgets('Einzelaktion rendert genau einen beschrifteten FAB',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButton: ExpandableFab(
            heroTag: 'single',
            actions: [
              FabAction(icon: Icons.add, label: 'Kontakt', onPressed: () {}),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('Kontakt'), findsOneWidget);
  });

  testWidgets('Speed-Dial: Toggle fächert auf, Aktion klappt wieder ein',
      (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButton: ExpandableFab(
            heroTag: 'multi',
            actions: [
              FabAction(
                  icon: Icons.star, label: 'Alpha', onPressed: () => tapped++),
              FabAction(icon: Icons.bolt, label: 'Beta', onPressed: () {}),
            ],
          ),
        ),
      ),
    );

    // Eingeklappt: nur der Toggle, keine Aktions-Labels.
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);
    expect(find.text('Beta'), findsNothing);

    // Aufklappen.
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);

    // Aktion auslösen -> ruft onPressed und klappt wieder ein.
    await tester.tap(find.byIcon(Icons.star));
    await tester.pumpAndSettle();
    expect(tapped, 1);
    expect(find.text('Alpha'), findsNothing);
  });

  testWidgets(
      'Speed-Dial setzt Aufklappzustand zurück, wenn der FAB-Slot für einen '
      'anderen FAB wiederverwendet wird (Tabwechsel-Regression)',
      (tester) async {
    await tester.pumpWidget(const _SwapHarness());

    // Aufklappen.
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);

    // Auf den Einzelaktions-FAB wechseln und wieder zurück (gleicher Slot,
    // gleiche State-Instanz). Ohne Reset käme das Dial bereits geöffnet zurück.
    await tester.tap(find.text('toSingle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('toMulti'));
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsNothing);
    expect(find.text('Beta'), findsNothing);
  });
}

/// Tauscht im selben Scaffold-FAB-Slot zwischen einem mehrteiligen Speed-Dial
/// und einem Einzelaktions-FAB – wie beim Tabwechsel in der Warenwirtschaft.
class _SwapHarness extends StatefulWidget {
  const _SwapHarness();

  @override
  State<_SwapHarness> createState() => _SwapHarnessState();
}

class _SwapHarnessState extends State<_SwapHarness> {
  bool _multi = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        floatingActionButton: ExpandableFab(
          heroTag: _multi ? 'multi' : 'single',
          actions: _multi
              ? [
                  FabAction(icon: Icons.star, label: 'Alpha', onPressed: () {}),
                  FabAction(icon: Icons.bolt, label: 'Beta', onPressed: () {}),
                ]
              : [
                  FabAction(icon: Icons.add, label: 'Gamma', onPressed: () {}),
                ],
        ),
        body: Column(
          children: [
            TextButton(
              onPressed: () => setState(() => _multi = false),
              child: const Text('toSingle'),
            ),
            TextButton(
              onPressed: () => setState(() => _multi = true),
              child: const Text('toMulti'),
            ),
          ],
        ),
      ),
    );
  }
}
