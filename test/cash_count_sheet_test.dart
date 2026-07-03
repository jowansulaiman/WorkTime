import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/widgets/cash_count_sheet.dart';

/// Widget-Test des geteilten Zähl-Sheets (Kassen-Modul M3): blind vs. mit Soll.
void main() {
  Future<CashCountInput?> openSheet(WidgetTester tester, {int? expected}) async {
    CashCountInput? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showCashCountSheet(context,
                    expectedCents: expected);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('blind: kein Soll/Differenz, gibt gezählten Betrag zurück',
      (tester) async {
    await openSheet(tester); // expected == null

    expect(find.text('Kasse zählen'), findsOneWidget);
    expect(find.textContaining('Soll'), findsNothing);
    // Submit erst nach gültiger Eingabe aktiv.
    final submit = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Zählung speichern'));
    expect(submit.onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, '150,50');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Zählung speichern'));
    await tester.pumpAndSettle();

    // Sheet geschlossen — Ergebnis geprüft via erneutes Öffnen ist nicht nötig;
    // hier reicht: das Sheet ist weg.
    expect(find.text('Kasse zählen'), findsNothing);
  });

  testWidgets('mit Soll: zeigt Differenz live (Fehlbetrag/Überschuss/stimmt)',
      (tester) async {
    await openSheet(tester, expected: 20000);

    expect(find.textContaining('Soll'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '199,00');
    await tester.pump();
    expect(find.textContaining('Fehlbetrag'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '201,00');
    await tester.pump();
    expect(find.textContaining('Überschuss'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '200,00');
    await tester.pump();
    expect(find.text('stimmt'), findsOneWidget);
  });

  testWidgets('gibt CashCountInput mit Betrag + Notiz zurück', (tester) async {
    CashCountInput? captured;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                captured = await showCashCountSheet(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '88,00');
    await tester.enterText(find.byType(TextField).at(1), 'Wechselgeld');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Zählung speichern'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.countedCents, 8800);
    expect(captured!.note, 'Wechselgeld');
  });
}
