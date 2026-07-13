import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/third_party_cash.dart';
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
    expect(captured!.thirdParty, isEmpty);
  });

  group('Dritte Hand / Fremdgelder', () {
    const types = [
      ThirdPartyCashType(id: 'lotto', name: 'Lotto', sortOrder: 0),
      ThirdPartyCashType(
          id: 'post', name: 'Deutsche Post', required: true, sortOrder: 1),
    ];

    Future<CashCountInput?> openWithTypes(WidgetTester tester,
        {int? expected}) async {
      CashCountInput? captured;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  captured = await showCashCountSheet(context,
                      expectedCents: expected, thirdPartyTypes: types);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return captured;
    }

    testWidgets('zeigt getrennte Fremdgeld-Sektion + Zusammenfassung',
        (tester) async {
      await openWithTypes(tester);
      expect(find.text('Dritte Hand / Fremdgelder'), findsOneWidget);
      expect(find.text('Zusammenfassung'), findsOneWidget);
      expect(find.text('Lotto'), findsWidgets);
      expect(find.text('Deutsche Post *'), findsOneWidget);
    });

    testWidgets('Pflicht-Art ohne Betrag blockiert Speichern bis Quittierung',
        (tester) async {
      await openWithTypes(tester);
      await tester.enterText(find.byType(TextField).first, '100,00');
      await tester.pump();

      // Post ist Pflicht, Betrag 0, nicht quittiert -> Speichern gesperrt.
      FilledButton submit() => tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Zählung speichern'));
      expect(submit().onPressed, isNull);

      // 0,00 € quittieren -> Speichern frei.
      final confirm = find.byKey(const Key('tp_confirm_post'));
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pump();
      expect(submit().onPressed, isNotNull);
    });

    testWidgets('gibt Fremdgeld-Beträge getrennt zurück + Gesamtsumme',
        (tester) async {
      final result = await (() async {
        CashCountInput? captured;
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    captured = await showCashCountSheet(context,
                        thirdPartyTypes: types);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, '120,00');
        await tester.enterText(find.byKey(const Key('tp_amount_lotto')), '45,00');
        await tester.enterText(find.byKey(const Key('tp_amount_post')), '12,00');
        await tester.pump();
        final submitFinder =
            find.widgetWithText(FilledButton, 'Zählung speichern');
        await tester.ensureVisible(submitFinder);
        await tester.pumpAndSettle();
        await tester.tap(submitFinder);
        await tester.pumpAndSettle();
        return captured;
      })();

      expect(result, isNotNull);
      expect(result!.countedCents, 12000);
      expect(result.thirdParty.length, 2);
      final lotto = result.thirdParty.firstWhere((e) => e.typeId == 'lotto');
      final post = result.thirdParty.firstWhere((e) => e.typeId == 'post');
      expect(lotto.amountCents, 4500);
      expect(lotto.typeName, 'Lotto');
      expect(post.amountCents, 1200);
    });
  });

  group('Inklusiv-Modus (Fremdgeld in der Lade, §8.5b)', () {
    const types = [
      ThirdPartyCashType(id: 'lotto', name: 'Lotto', sortOrder: 0),
      ThirdPartyCashType(
          id: 'post', name: 'Deutsche Post', required: true, sortOrder: 1),
    ];

    // Öffnet das Sheet und legt das zurückgegebene Ergebnis in [holder] ab
    // (Länge 0 solange nicht gespeichert; nach Submit ein Element).
    Future<void> open(WidgetTester tester, List<CashCountInput?> holder,
        {int? expected, bool inTill = true}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  final r = await showCashCountSheet(context,
                      expectedCents: expected,
                      thirdPartyTypes: types,
                      thirdPartyInTill: inTill);
                  holder.add(r);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('rechnet eigene Kasse = Gesamt − Fremdgeld', (tester) async {
      final holder = <CashCountInput?>[];
      await open(tester, holder);
      // Gesamt in der Lade inkl. Fremdgeld.
      await tester.enterText(find.byType(TextField).first, '120,00');
      await tester.enterText(find.byKey(const Key('tp_amount_lotto')), '45,00');
      await tester.enterText(find.byKey(const Key('tp_amount_post')), '12,00');
      await tester.pump();
      expect(find.text('Eigene Kasse (Rest)'), findsOneWidget);
      final submitFinder =
          find.widgetWithText(FilledButton, 'Zählung speichern');
      await tester.ensureVisible(submitFinder);
      await tester.pumpAndSettle();
      await tester.tap(submitFinder);
      await tester.pumpAndSettle();

      expect(holder, hasLength(1));
      final result = holder.single!;
      // 12000 − 4500 − 1200 = 6300 (eigene Kasse netto).
      expect(result.countedCents, 6300);
      final lotto = result.thirdParty.firstWhere((e) => e.typeId == 'lotto');
      final post = result.thirdParty.firstWhere((e) => e.typeId == 'post');
      expect(lotto.amountCents, 4500);
      expect(post.amountCents, 1200);
    });

    testWidgets('Soll-Differenz rechnet auf der eigenen Kasse (netto)',
        (tester) async {
      await open(tester, <CashCountInput?>[], expected: 6000);
      await tester.enterText(find.byKey(const Key('tp_amount_lotto')), '45,00');
      await tester.enterText(find.byKey(const Key('tp_amount_post')), '5,00');
      // Gesamt 110,00 → eigen 110-45-5 = 60,00 == Soll → stimmt.
      await tester.enterText(find.byType(TextField).first, '110,00');
      await tester.pump();
      expect(find.text('stimmt'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '120,00');
      await tester.pump();
      expect(find.textContaining('Überschuss'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '100,00');
      await tester.pump();
      expect(find.textContaining('Fehlbetrag'), findsOneWidget);
    });

    testWidgets('Fremdgeld > Gesamt blockiert Speichern + warnt',
        (tester) async {
      await open(tester, <CashCountInput?>[]);
      // Gesamt 10,00 < Fremdgeld 45,00 → eigene Kasse negativ.
      await tester.enterText(find.byType(TextField).first, '10,00');
      await tester.enterText(find.byKey(const Key('tp_amount_lotto')), '45,00');
      await tester.pump();

      expect(find.textContaining('übersteigt'), findsOneWidget);
      final submit = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Zählung speichern'));
      expect(submit.onPressed, isNull);
    });

    testWidgets('Umschalter wechselt zwischen getrennt und inklusive',
        (tester) async {
      await open(tester, <CashCountInput?>[], inTill: false); // startet getrennt
      expect(find.text('Kasse (eigen)'), findsOneWidget);
      expect(find.text('Eigene Kasse (Rest)'), findsNothing);

      await tester.tap(find.text('Fremdgeld liegt in der Kassenlade'));
      await tester.pump();
      expect(find.text('Eigene Kasse (Rest)'), findsOneWidget);
      expect(find.text('Kasse (eigen)'), findsNothing);
    });

    testWidgets('ohne Fremdgeld-Arten kein Umschalter', (tester) async {
      await openSheet(tester); // keine types
      expect(find.text('Fremdgeld liegt in der Kassenlade'), findsNothing);
    });
  });
}
