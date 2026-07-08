import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/contact.dart';
import 'package:worktime_app/models/contact_details.dart';
import 'package:worktime_app/screens/contacts/contact_editor_sheet.dart';
import 'package:worktime_app/theme/app_theme.dart';
import 'package:worktime_app/ui/ui.dart';

Future<Contact?> _openEditor(WidgetTester tester, {Contact? initial}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1000, 2200);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  Contact? captured;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolveLight(useV2: true),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () async {
                captured = await showAppBottomSheet<Contact>(
                  context: ctx,
                  builder: (_) => ContactEditorSheet(
                    contact: initial,
                    sites: const [],
                    orgId: 'org-1',
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return captured;
}

void main() {
  testWidgets('Firma ist Default; Umschalten auf Person zeigt Namensfelder',
      (tester) async {
    await _openEditor(tester);

    // Default = Firma → Firmenname-Feld sichtbar, keine Personenfelder.
    expect(find.text('Firmenname *'), findsOneWidget);
    expect(find.text('Nachname *'), findsNothing);

    // Auf Person umschalten.
    await tester.tap(find.text('Person'));
    await tester.pumpAndSettle();
    expect(find.text('Nachname *'), findsOneWidget);
    expect(find.text('Vorname'), findsOneWidget);
    expect(find.text('Firmenname *'), findsNothing);
  });

  testWidgets('Rückgabe: Person-Contact mit abgeleitetem Namen', (tester) async {
    Contact? result;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 2200);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.resolveLight(useV2: true),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showAppBottomSheet<Contact>(
                    context: ctx,
                    builder: (_) => const ContactEditorSheet(
                      contact: null,
                      sites: [],
                      orgId: 'org-1',
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Person'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Vorname'), 'Anna');
    await tester.enterText(
        find.widgetWithText(TextField, 'Nachname *'), 'Meier');
    final saveBtn = find.text('Kontakt anlegen');
    await tester.ensureVisible(saveBtn);
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.kind, ContactKind.person);
    expect(result!.firstName, 'Anna');
    expect(result!.lastName, 'Meier');
    expect(result!.name, 'Anna Meier'); // abgeleitet
    expect(result!.orgId, 'org-1');
  });
}
