import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/widgets/breadcrumb_app_bar.dart';

/// Pusht einen Screen mit [BreadcrumbAppBar] über eine Wurzel, damit
/// `Navigator.canPop() == true` (echte gepushte-Screen-Situation).
Future<void> _pumpPushed(
  WidgetTester tester, {
  required List<BreadcrumbItem> breadcrumbs,
  List<Widget>? actions,
  Size size = const Size(400, 800),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: BreadcrumbAppBar(
                      breadcrumbs: breadcrumbs,
                      actions: actions,
                    ),
                    body: const SizedBox.shrink(),
                  ),
                ),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
}

void main() {
  group('BreadcrumbAppBar (professioneller Kopf)', () {
    testWidgets('schmal: prominenter Titel + Eltern-Eyebrow, EINE Zurück-Taste',
        (tester) async {
      await _pumpPushed(
        tester,
        breadcrumbs: [
          BreadcrumbItem(label: 'Personal', onTap: () {}),
          const BreadcrumbItem(label: 'Jowan'),
        ],
      );

      // Titel (aktuelle Seite) + Eltern-Zeile sichtbar.
      expect(find.text('Jowan'), findsOneWidget);
      expect(find.text('Personal'), findsOneWidget);

      // Genau EINE Zurück-Affordanz (kein doppelter Pfeil + Krümel-Button).
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      // Kein Chevron-Gewusel auf schmalen Screens.
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });

    testWidgets('Zurück-Taste poppt den Screen', (tester) async {
      await _pumpPushed(
        tester,
        breadcrumbs: const [
          BreadcrumbItem(label: 'Personal'),
          BreadcrumbItem(label: 'Jowan'),
        ],
      );
      expect(find.text('Jowan'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      // Zurück auf der Wurzel: Titel weg, Start-Button wieder da.
      expect(find.text('Jowan'), findsNothing);
      expect(find.text('go'), findsOneWidget);
    });

    testWidgets('einzelner Krümel: nur Titel, keine Eyebrow', (tester) async {
      await _pumpPushed(
        tester,
        breadcrumbs: const [BreadcrumbItem(label: 'Einstellungen')],
      );
      expect(find.text('Einstellungen'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });

    testWidgets('breit: volle klickbare Breadcrumb-Kette mit Chevron',
        (tester) async {
      await _pumpPushed(
        tester,
        size: const Size(1000, 800),
        breadcrumbs: [
          BreadcrumbItem(label: 'Personal', onTap: () {}),
          const BreadcrumbItem(label: 'Jowan'),
        ],
      );

      expect(find.text('Personal'), findsOneWidget);
      expect(find.text('Jowan'), findsOneWidget);
      // Auf breiten Screens erscheint die Chevron-Kette.
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    });

    testWidgets('actions werden durchgereicht', (tester) async {
      await _pumpPushed(
        tester,
        breadcrumbs: const [
          BreadcrumbItem(label: 'Laden'),
          BreadcrumbItem(label: 'Kasse'),
        ],
        actions: [
          IconButton(
            tooltip: 'Test',
            icon: const Icon(Icons.point_of_sale_outlined),
            onPressed: () {},
          ),
        ],
      );
      expect(find.byIcon(Icons.point_of_sale_outlined), findsOneWidget);
    });
  });
}
