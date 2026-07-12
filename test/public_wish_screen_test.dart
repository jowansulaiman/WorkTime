import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:worktime_app/screens/public/public_ui.dart';
import 'package:worktime_app/screens/public/public_wish_screen.dart';
import 'package:worktime_app/services/firestore_service.dart';
import 'package:worktime_app/theme/app_theme.dart';

/// #66: Widget-Tests für den einzigen öffentlichen (anonymen) Schreibpfad.
/// Läuft bewusst OHNE Firebase-Init: der Screen prüft `Firebase.apps.isEmpty`
/// vor jedem Write und muss dann eine ehrliche Fehlermeldung zeigen statt zu
/// crashen — genau dieser Zweig plus die Formularvalidierung und der
/// Mengen-Stepper sind hier abgesichert.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late FirestoreService firestoreService;

  setUpAll(() async {
    await initializeDateFormatting('de_DE');
  });

  setUp(() {
    firestore = FakeFirebaseFirestore();
    firestoreService = FirestoreService(firestore: firestore);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    // Breites Fenster, damit das zweispaltige Public-Layout Platz hat.
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PublicWishScreen(firestoreService: firestoreService),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Wunsch absenden'));
    await tester.tap(find.text('Wunsch absenden'));
    await tester.pumpAndSettle();
  }

  testWidgets('leerer Wunschtext -> Validierungsfehler, kein Firestore-Write',
      (tester) async {
    await pumpScreen(tester);

    await submit(tester);

    expect(find.text('Bitte beschreibe deinen Wunsch.'), findsOneWidget);
    final wishes = await firestore
        .collectionGroup('customerWishes')
        .get()
        .then((snapshot) => snapshot.docs);
    expect(wishes, isEmpty,
        reason: 'ohne gueltiges Formular darf nichts geschrieben werden');
  });

  testWidgets(
      'Submit ohne Firebase-Init zeigt ehrliche Fehlermeldung im Banner '
      'statt zu crashen', (tester) async {
    await pumpScreen(tester);

    await tester.enterText(
      find.byType(TextFormField).first,
      'Spiegel Ausgabe 26',
    );
    await submit(tester);

    expect(find.byType(PublicErrorBanner), findsOneWidget);
    expect(
      find.textContaining('nicht mit dem Backend verbunden'),
      findsOneWidget,
      reason: 'ohne Firebase-Konfiguration muss die ehrliche Meldung '
          'erscheinen, nicht "Internetverbindung pruefen"',
    );
    // Kein Erfolgs-Screen, Formular bleibt stehen.
    expect(find.text('Wunsch absenden'), findsOneWidget);
  });

  testWidgets('Mengen-Stepper: Minus ist bei 1 gesperrt, Plus erhoeht',
      (tester) async {
    await pumpScreen(tester);

    final minusButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.remove),
    );
    expect(minusButton.onPressed, isNull,
        reason: 'Menge darf nicht unter 1 fallen');

    await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(PublicStepperTile),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );

    final minusAfter = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.remove),
    );
    expect(minusAfter.onPressed, isNotNull);
  });
}
