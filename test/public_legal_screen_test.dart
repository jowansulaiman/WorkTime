import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:worktime_app/core/legal_info.dart';
import 'package:worktime_app/screens/public/public_feedback_screen.dart';
import 'package:worktime_app/screens/public/public_legal_app.dart';
import 'package:worktime_app/screens/public/public_legal_screen.dart';
import 'package:worktime_app/screens/public/public_wish_screen.dart';
import 'package:worktime_app/services/firestore_service.dart';
import 'package:worktime_app/theme/app_theme.dart';

/// Render- und Verhaltens-Tests der rechtlichen Pflichtseiten (Impressum,
/// Datenschutzerklärung) sowie der Footer-Verlinkung von /wunsch und /feedback.
/// Deckt drei Risiken ab, die `flutter analyze` nicht sieht: Layout-Overflow
/// über die ganze Breitenspanne, der „noch-zu-hinterlegen"-Schutz bei fehlenden
/// Pflichtangaben und die Navigation Formular -> Rechtsseite -> Cross-Link.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('de_DE');
  });

  Widget wrap(Widget home, Brightness brightness) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightV2,
        darkTheme: AppTheme.darkV2,
        themeMode:
            brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        home: home,
      );

  // Vollständige Beispiel-Stammdaten (für den „veröffentlichungsbereit"-Zweig).
  const completeInfo = LegalInfo(
    operatorName: 'Erika Mustermann',
    street: 'Holstenstraße 1',
    postalCity: '24103 Kiel',
    email: 'kontakt@example.de',
    phone: '0431 1234567',
    vatId: 'DE123456789',
  );

  const sizes = <Size>[
    Size(360, 800), // schmales Handy
    Size(600, 900), // großes Handy / kleines Tablet
    Size(880, 900), // Tablet / Split-Breakpoint
    Size(1000, 800), // Desktop
    Size(1440, 900), // sehr breiter Desktop
  ];

  Future<void> pumpAt(
    WidgetTester tester,
    Widget home,
    Size size,
    Brightness brightness,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(home, brightness));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  for (final size in sizes) {
    testWidgets('Impressum rendert bei $size (hell) ohne Overflow',
        (tester) async {
      await pumpAt(
        tester,
        const PublicLegalScreen(
            page: PublicLegalPage.impressum, info: completeInfo),
        size,
        Brightness.light,
      );
      expect(find.text('Impressum'), findsOneWidget);
      expect(find.text('Angaben gemäß § 5 DDG'), findsOneWidget);
    });

    testWidgets('Datenschutz rendert bei $size (hell) ohne Overflow',
        (tester) async {
      await pumpAt(
        tester,
        const PublicLegalScreen(
            page: PublicLegalPage.datenschutz, info: completeInfo),
        size,
        Brightness.light,
      );
      expect(find.text('Datenschutzerklärung'), findsOneWidget);
      expect(find.text('1. Verantwortlicher'), findsOneWidget);
    });
  }

  // Dunkelmodus an je einem schmalen und einem breiten Punkt.
  for (final size in const <Size>[Size(360, 800), Size(1280, 900)]) {
    testWidgets('Impressum rendert bei $size (dunkel) ohne Overflow',
        (tester) async {
      await pumpAt(
        tester,
        const PublicLegalScreen(
            page: PublicLegalPage.impressum, info: completeInfo),
        size,
        Brightness.dark,
      );
    });

    testWidgets('Datenschutz rendert bei $size (dunkel) ohne Overflow',
        (tester) async {
      await pumpAt(
        tester,
        const PublicLegalScreen(
            page: PublicLegalPage.datenschutz, info: completeInfo),
        size,
        Brightness.dark,
      );
    });
  }

  testWidgets('Ohne Pflichtangaben zeigt das Impressum den Setup-Hinweis',
      (tester) async {
    await pumpAt(
      tester,
      const PublicLegalScreen(page: PublicLegalPage.impressum, info: LegalInfo()),
      const Size(1000, 1000),
      Brightness.light,
    );
    expect(find.byType(PublicLegalSetupNotice), findsOneWidget);
    expect(find.textContaining('noch nicht vollständig hinterlegt'),
        findsOneWidget);
    // Platzhalter machen die fehlenden Felder sichtbar.
    expect(find.textContaining('[Name des Betreibers'), findsOneWidget);
  });

  testWidgets(
      'Mit vollständigen Daten verschwindet der Hinweis und echte Angaben '
      'erscheinen', (tester) async {
    await pumpAt(
      tester,
      const PublicLegalScreen(
          page: PublicLegalPage.impressum, info: completeInfo),
      const Size(1000, 1000),
      Brightness.light,
    );
    expect(find.byType(PublicLegalSetupNotice), findsNothing);
    expect(find.text('Erika Mustermann'), findsWidgets);
    expect(find.text('24103 Kiel'), findsWidgets);
    // Keine Platzhalter-Klammern mehr.
    expect(find.textContaining('[Name'), findsNothing);
    // USt-IdNr-Sektion erscheint nur, wenn gesetzt.
    expect(find.text('Umsatzsteuer-ID'), findsOneWidget);
  });

  testWidgets('Datenschutz nennt Aufsichtsbehörde, Auftragsverarbeiter, Rechte',
      (tester) async {
    await pumpAt(
      tester,
      const PublicLegalScreen(
          page: PublicLegalPage.datenschutz, info: completeInfo),
      const Size(1000, 2400),
      Brightness.light,
    );
    expect(
      find.textContaining('Unabhängiges Landeszentrum für Datenschutz'),
      findsOneWidget,
    );
    expect(find.text('5. Empfänger und Auftragsverarbeiter'), findsOneWidget);
    expect(find.text('7. Deine Rechte'), findsOneWidget);
    expect(find.text('8. Beschwerderecht bei der Aufsichtsbehörde'),
        findsOneWidget);
  });

  testWidgets('Impressum-Seite verlinkt auf Datenschutz, nicht auf sich selbst',
      (tester) async {
    await pumpAt(
      tester,
      const PublicLegalScreen(
          page: PublicLegalPage.impressum, info: completeInfo),
      const Size(1000, 1200),
      Brightness.light,
    );
    // Footer-Link „Datenschutz" vorhanden, „Impressum"-Link unterdrückt.
    final datenschutzLink = find.widgetWithText(TextButton, 'Datenschutz');
    expect(datenschutzLink, findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Impressum'), findsNothing);

    await tester.ensureVisible(datenschutzLink);
    await tester.tap(datenschutzLink);
    await tester.pumpAndSettle();
    expect(find.text('Datenschutzerklärung'), findsOneWidget);
  });

  testWidgets('Wunsch-Seite zeigt Footer-Links und öffnet das Impressum',
      (tester) async {
    final service = FirestoreService(firestore: FakeFirebaseFirestore());
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(
      PublicWishScreen(firestoreService: service, onSelectThemeMode: (_) {}),
      Brightness.light,
    ));
    await tester.pumpAndSettle();

    final impressumLink = find.widgetWithText(TextButton, 'Impressum');
    final datenschutzLink = find.widgetWithText(TextButton, 'Datenschutz');
    expect(impressumLink, findsOneWidget);
    expect(datenschutzLink, findsOneWidget);

    await tester.ensureVisible(impressumLink);
    await tester.tap(impressumLink);
    await tester.pumpAndSettle();
    expect(find.text('Angaben gemäß § 5 DDG'), findsOneWidget);
    // Footer-Push nutzt info: null ⇒ LegalInfo.fromConfig(); im Test-Env sind
    // die APP_LEGAL_* leer ⇒ der Setup-Hinweis MUSS erscheinen (safe-by-default,
    // keine halbleere Rechtsseite ohne Warnung).
    expect(find.byType(PublicLegalSetupNotice), findsOneWidget);
  });

  testWidgets('§ 18 MStV-Block erscheint nur bei gesetztem contentResponsible',
      (tester) async {
    await pumpAt(
      tester,
      const PublicLegalScreen(
          page: PublicLegalPage.impressum, info: completeInfo),
      const Size(1000, 1200),
      Brightness.light,
    );
    // completeInfo hat keinen contentResponsible ⇒ Block ausgeblendet
    // (reine Formularseiten lösen § 18 Abs. 2 MStV nicht aus).
    expect(find.text('Verantwortlich für den Inhalt nach § 18 Abs. 2 MStV'),
        findsNothing);

    await pumpAt(
      tester,
      const PublicLegalScreen(
        page: PublicLegalPage.impressum,
        info: LegalInfo(
          operatorName: 'Erika Mustermann',
          street: 'Holstenstraße 1',
          postalCity: '24103 Kiel',
          email: 'kontakt@example.de',
          phone: '0431 1234567',
          contentResponsible: 'Erika Mustermann',
        ),
      ),
      const Size(1000, 1200),
      Brightness.light,
    );
    expect(find.text('Verantwortlich für den Inhalt nach § 18 Abs. 2 MStV'),
        findsOneWidget);
  });

  testWidgets('PublicLegalApp (Standalone) rendert und schaltet Hell/Dunkel um',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // Eigenständige Web-Hülle (wie /impressum) — bringt eigene MaterialApp mit.
    await tester.pumpWidget(
      const PublicLegalApp(page: PublicLegalPage.impressum),
    );
    await tester.pumpAndSettle();

    expect(find.text('Impressum'), findsOneWidget);
    // System-Default ist hell ⇒ Umschalter bietet „Dunkler Modus" an.
    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.dark_mode_outlined));
    await tester.pumpAndSettle();
    // Nach dem Umschalten zeigt der Button die Gegenrichtung.
    expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);
    expect(Theme.of(tester.element(find.text('Impressum'))).brightness,
        Brightness.dark);
  });

  testWidgets('Feedback-Seite zeigt Footer-Links und öffnet den Datenschutz',
      (tester) async {
    final service = FirestoreService(firestore: FakeFirebaseFirestore());
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(
      PublicFeedbackScreen(firestoreService: service, onSelectThemeMode: (_) {}),
      Brightness.light,
    ));
    await tester.pumpAndSettle();

    final datenschutzLink = find.widgetWithText(TextButton, 'Datenschutz');
    expect(find.widgetWithText(TextButton, 'Impressum'), findsOneWidget);
    expect(datenschutzLink, findsOneWidget);

    await tester.ensureVisible(datenschutzLink);
    await tester.tap(datenschutzLink);
    await tester.pumpAndSettle();
    expect(find.text('1. Verantwortlicher'), findsOneWidget);
  });
}
