import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:worktime_app/screens/public/public_feedback_screen.dart';
import 'package:worktime_app/screens/public/public_ui.dart';
import 'package:worktime_app/screens/public/public_wish_screen.dart';
import 'package:worktime_app/services/firestore_service.dart';
import 'package:worktime_app/theme/app_theme.dart';

/// Render-Smoke-Test der öffentlichen Seiten (/wunsch, /feedback): Das flache
/// Signal-Teal-Split-Layout (seitliche Marken-Schiene <-> Marken-Band) muss
/// vom schmalen Handy bis zum breiten Desktop, hell wie dunkel, ohne
/// Layout-Ausnahme rendern. Fängt Overflow / unbounded-constraints ab, die
/// `flutter analyze` und die reinen Service-/Model-Tests nicht sehen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('de_DE');
  });

  final firestore = FakeFirebaseFirestore();
  final service = FirestoreService(firestore: firestore);

  Widget wrap(Widget home, Brightness brightness) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightV2,
        darkTheme: AppTheme.darkV2,
        themeMode:
            brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        home: home,
      );

  // Phone, große Telefon-/Tablet-Breite, exakt am Split-Breakpoint, breiter
  // Desktop, sehr breiter Desktop.
  const sizes = <Size>[
    Size(360, 800), // schmales Handy (Einspalter, Paare gestapelt)
    Size(600, 900), // großes Handy / kleines Tablet
    Size(700, 900), // Tablet schmal — Feldpaare nebeneinander
    Size(880, 900), // exakt am Split-Breakpoint
    Size(1000, 800), // Desktop (Split, Paare gestapelt)
    Size(1280, 900), // breiter Desktop — Feldpaare nebeneinander
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
    testWidgets('Wunsch-Seite rendert bei $size (hell) ohne Overflow',
        (tester) async {
      await pumpAt(
        tester,
        PublicWishScreen(firestoreService: service, onSelectThemeMode: (_) {}),
        size,
        Brightness.light,
      );
      expect(find.text('Wunsch absenden'), findsOneWidget);
    });

    testWidgets('Feedback-Seite rendert bei $size (hell) ohne Overflow',
        (tester) async {
      await pumpAt(
        tester,
        PublicFeedbackScreen(
            firestoreService: service, onSelectThemeMode: (_) {}),
        size,
        Brightness.light,
      );
      expect(find.text('Absenden'), findsOneWidget);
    });
  }

  // Erfolgs-Ansicht (Referenznummer-Block) separat, schmal und breit.
  for (final size in const <Size>[Size(360, 800), Size(1280, 900)]) {
    testWidgets('Erfolgs-Ansicht rendert bei $size ohne Overflow',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(wrap(
        Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: PublicSuccessView(
              code: 'K7Q-9X2',
              headline: 'Wunsch erhalten – danke!',
              lead: 'Nenne diese Nummer im Laden, dann finden wir deinen '
                  'Wunsch sofort:',
              codeCaption: 'DEINE WUNSCH-NUMMER',
              copyLabel: 'Nummer kopieren',
              onCopy: () {},
              resetLabel: 'Weiteren Wunsch abgeben',
              onReset: () {},
            ),
          ),
        ),
        Brightness.light,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('K7Q-9X2'), findsOneWidget);
      expect(find.text('Nummer kopieren'), findsOneWidget);
    });
  }

  // Dunkelmodus an je einem schmalen und einem breiten Punkt (Marken-Fläche
  // wechselt dort auf primaryContainer/onPrimaryContainer).
  for (final size in const <Size>[Size(360, 800), Size(1200, 900)]) {
    testWidgets('Wunsch-Seite rendert bei $size (dunkel) ohne Overflow',
        (tester) async {
      await pumpAt(
        tester,
        PublicWishScreen(firestoreService: service, onSelectThemeMode: (_) {}),
        size,
        Brightness.dark,
      );
    });

    testWidgets('Feedback-Seite rendert bei $size (dunkel) ohne Overflow',
        (tester) async {
      await pumpAt(
        tester,
        PublicFeedbackScreen(
            firestoreService: service, onSelectThemeMode: (_) {}),
        size,
        Brightness.dark,
      );
    });
  }
}
