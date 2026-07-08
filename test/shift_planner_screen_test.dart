import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/compliance_rule_set.dart';
import 'package:worktime_app/models/employee_site_assignment.dart';
import 'package:worktime_app/models/employment_contract.dart';
import 'package:worktime_app/models/shift.dart';
import 'package:worktime_app/models/site_definition.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/auth_provider.dart';
import 'package:worktime_app/providers/schedule_provider.dart';
import 'package:worktime_app/providers/team_provider.dart';
import 'package:worktime_app/screens/shift_planner_screen.dart';
import 'package:worktime_app/services/auth_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('de_DE');
  });

  testWidgets(
    'admin planner shows pending and approved absences for all employees',
    (tester) async {
      await _pumpAdminPlanner(
        tester,
        absences: [
          const _SeededAbsence(
            id: 'absence-pending',
            userId: 'employee-anna',
            employeeName: 'Anna',
            type: 'vacation',
            status: 'pending',
          ),
          const _SeededAbsence(
            id: 'absence-approved',
            userId: 'employee-ben',
            employeeName: 'Ben',
            type: 'vacation',
            status: 'approved',
          ),
          const _SeededAbsence(
            id: 'absence-rejected',
            userId: 'employee-ben',
            employeeName: 'Ben',
            type: 'vacation',
            status: 'rejected',
          ),
        ],
      );

      expect(find.text('Anna'), findsOneWidget);
      expect(find.text('Ben'), findsOneWidget);
      expect(find.text('Urlaub · Offen'), findsOneWidget);
      expect(find.text('Urlaub · Genehmigt'), findsOneWidget);
      expect(find.textContaining('Abgelehnt'), findsNothing);
    },
  );

  testWidgets(
    'admin planner filters absences by selected employee and can reset to all',
    (tester) async {
      final harness = await _pumpAdminPlanner(
        tester,
        absences: [
          const _SeededAbsence(
            id: 'absence-anna',
            userId: 'employee-anna',
            employeeName: 'Anna',
            type: 'vacation',
            status: 'approved',
          ),
          const _SeededAbsence(
            id: 'absence-ben',
            userId: 'employee-ben',
            employeeName: 'Ben',
            type: 'vacation',
            status: 'approved',
          ),
        ],
      );

      expect(find.text('Anna'), findsOneWidget);
      expect(find.text('Ben'), findsOneWidget);

      harness.scheduleProvider.setSelectedUserId('employee-anna');
      await _settlePlanner(tester);

      expect(find.text('Anna'), findsOneWidget);
      expect(find.text('Ben'), findsNothing);

      harness.scheduleProvider.setSelectedUserId(null);
      await _settlePlanner(tester);

      expect(find.text('Anna'), findsOneWidget);
      expect(find.text('Ben'), findsOneWidget);
    },
  );

  testWidgets(
    'admin planner filters calendar absences to vacation entries',
    (tester) async {
      await _pumpAdminPlanner(
        tester,
        absences: [
          const _SeededAbsence(
            id: 'absence-vacation',
            userId: 'employee-anna',
            employeeName: 'Anna',
            type: 'vacation',
            status: 'approved',
          ),
          const _SeededAbsence(
            id: 'absence-sickness',
            userId: 'employee-ben',
            employeeName: 'Ben',
            type: 'sickness',
            status: 'approved',
          ),
        ],
      );

      expect(find.text('Urlaub · Genehmigt'), findsOneWidget);
      expect(find.text('Krank · Genehmigt'), findsOneWidget);

      await _openFilterMenu(tester, 'Abwesenheiten');
      await tester.tap(find.text('Urlaub anzeigen').last);
      await _settlePlanner(tester);

      expect(find.text('Urlaub · Genehmigt'), findsOneWidget);
      expect(find.text('Krank · Genehmigt'), findsNothing);
    },
  );

  testWidgets(
    'mobile month view exposes employee and location menu',
    (tester) async {
      await _pumpAdminPlanner(
        tester,
        absences: const [],
        shifts: const [
          _SeededShift(
            id: 'shift-anna',
            userId: 'employee-anna',
            employeeName: 'Anna',
            title: 'Fruehschicht',
            siteName: 'Berlin HQ',
          ),
        ],
        viewMode: ScheduleViewMode.month,
        physicalSize: const Size(390, 844),
      );

      expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
      expect(find.text('Standort'), findsOneWidget);
      expect(find.text('Mitarbeiter'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await _settlePlanner(tester);

      expect(find.text('Kalender-Menü'), findsOneWidget);
      expect(
        find.text(
            'Mitarbeiter und Standorte für die Monatsansicht auswählen.'),
        findsOneWidget,
      );
      expect(find.text('Anna'), findsWidgets);
      expect(find.text('MITARBEITER'), findsOneWidget);
      expect(find.text('STANDORTE'), findsOneWidget);

      // Geplante Monatsstunden je Mitarbeiter neben der Filter-Checkbox:
      // Anna hat eine 7,5h-Schicht im Monat, Soll-Fallback 8h×5×4,33.
      expect(find.text('7,5h/173,2h'), findsOneWidget);
      expect(find.text('0h/173,2h'), findsWidgets);
    },
  );

  testWidgets(
    'Monatsansicht: Sidebar zeigt geplante Stunden je Mitarbeiter',
    (tester) async {
      await _pumpAdminPlanner(
        tester,
        absences: const [],
        shifts: const [
          _SeededShift(
            id: 'shift-anna',
            userId: 'employee-anna',
            employeeName: 'Anna',
            title: 'Fruehschicht',
            siteName: 'Berlin HQ',
          ),
        ],
        viewMode: ScheduleViewMode.month,
        physicalSize: const Size(1600, 1200),
      );

      // Desktop-Sidebar: Anna 7,5h geplant, Soll-Fallback 8h×5×4,33 = 173,2h;
      // Mitglieder ohne Schichten zeigen 0h.
      expect(find.text('7,5h/173,2h'), findsOneWidget);
      expect(find.text('0h/173,2h'), findsWidgets);
    },
  );

  testWidgets(
    'Monatsansicht: viele Schichten an einem Tag laufen nicht ueber',
    (tester) async {
      // Reproduziert den gemeldeten Pixel-Overflow: an einem Tag liegen mehr
      // Schichten als in die feste Monats-Zellenhoehe passen.
      await _pumpAdminPlanner(
        tester,
        absences: const [],
        shifts: List.generate(
          7,
          (i) => _SeededShift(
            id: 'shift-many-$i',
            userId: 'employee-anna',
            employeeName: 'Anna',
            title: 'Schicht $i',
            siteName: 'Berlin HQ',
          ),
        ),
        viewMode: ScheduleViewMode.month,
        physicalSize: const Size(1600, 1200),
      );

      // Kein RenderFlex-Overflow in der Tageszelle.
      expect(tester.takeException(), isNull);
      // Overflow-Schutz greift: nicht alle Kacheln sichtbar -> "+N weitere".
      expect(find.textContaining('weitere'), findsWidgets);
    },
  );

  testWidgets(
    'Kompakte Monatsansicht: viele Schichten an einem Tag laufen nicht ueber',
    (tester) async {
      await _pumpAdminPlanner(
        tester,
        absences: const [],
        shifts: List.generate(
          6,
          (i) => _SeededShift(
            id: 'shift-cmany-$i',
            userId: 'employee-anna',
            employeeName: 'Anna',
            title: 'Schicht $i',
            siteName: 'Berlin HQ',
          ),
        ),
        viewMode: ScheduleViewMode.month,
        physicalSize: const Size(390, 844),
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('mehr'), findsWidgets);
    },
  );

  testWidgets(
    'Monatsansicht: Tag nur mit Abwesenheit laeuft horizontal nicht ueber',
    (tester) async {
      // Reproduziert den zweiten Pixel-Overflow: eine Tageszelle ohne Schicht,
      // aber mit Abwesenheit, zeigt im Fuss "Abwesenheiten vorhanden". Bei
      // schmalen, nicht-kompakten Zellen + realer Textgroesse lief diese Zeile
      // horizontal ueber (kein Flexible/Ellipsis).
      await _pumpAdminPlanner(
        tester,
        absences: const [
          _SeededAbsence(
            id: 'absence-only',
            userId: 'employee-anna',
            employeeName: 'Anna',
            type: 'sickness',
            status: 'approved',
          ),
        ],
        viewMode: ScheduleViewMode.month,
        physicalSize: const Size(1280, 1000),
        textScale: 1,
      );

      expect(tester.takeException(), isNull);
      // Der (jetzt ellipsisfaehige) Hinweis ist weiterhin als Datentext da.
      expect(find.text('Abwesenheiten vorhanden'), findsWidgets);
    },
  );

  testWidgets(
    'admin planner exports only completed shifts when status filter is completed',
    (tester) async {
      late ShiftPlanExportFormat capturedFormat;
      List<Shift> exportedShifts = const [];

      final harness = await _pumpAdminPlanner(
        tester,
        absences: const [],
        shifts: const [
          _SeededShift(
            id: 'shift-completed',
            userId: 'employee-anna',
            employeeName: 'Anna',
            title: 'Erledigte Schicht',
            siteName: 'Berlin HQ',
            status: ShiftStatus.completed,
          ),
          _SeededShift(
            id: 'shift-planned',
            userId: 'employee-ben',
            employeeName: 'Ben',
            title: 'Geplante Schicht',
            siteName: 'Hamburg',
            status: ShiftStatus.planned,
          ),
        ],
        onShiftPlanExport: (format, shifts) async {
          capturedFormat = format;
          exportedShifts = shifts;
        },
      );

      harness.scheduleProvider.setStatusFilter(ShiftStatus.completed);
      await _settlePlanner(tester);

      await tester.tap(find.text('AKTIONEN'));
      await _settlePlanner(tester);
      await tester.tap(find.text('Als PDF exportieren').last);
      await _settlePlanner(tester);

      expect(capturedFormat, ShiftPlanExportFormat.pdf);
      expect(exportedShifts, hasLength(1));
      expect(exportedShifts.single.status, ShiftStatus.completed);
      expect(exportedShifts.single.title, 'Erledigte Schicht');
    },
  );

  testWidgets(
    'admin planner exports the currently filtered location selection',
    (tester) async {
      List<Shift> exportedShifts = const [];

      await _pumpAdminPlanner(
        tester,
        absences: const [],
        shifts: const [
          _SeededShift(
            id: 'shift-berlin',
            userId: 'employee-anna',
            employeeName: 'Anna',
            title: 'Fruehschicht',
            siteName: 'Berlin HQ',
          ),
          _SeededShift(
            id: 'shift-hamburg',
            userId: 'employee-ben',
            employeeName: 'Ben',
            title: 'Spaetschicht',
            siteName: 'Hamburg',
          ),
        ],
        onShiftPlanExport: (format, shifts) async {
          exportedShifts = shifts;
        },
      );

      await _openFilterMenu(tester, 'Standort');
      await tester.tap(find.text('Berlin HQ').last);
      await _settlePlanner(tester);

      await tester.tap(find.text('AKTIONEN'));
      await _settlePlanner(tester);
      await tester.tap(find.text('Als PDF exportieren').last);
      await _settlePlanner(tester);

      expect(exportedShifts, hasLength(1));
      expect(exportedShifts.single.effectiveSiteLabel, 'Berlin HQ');
      expect(exportedShifts.single.title, 'Fruehschicht');
    },
  );

  testWidgets(
    'Neue Schicht oeffnet Editor mit Mehrtage-Picker (kein Crash)',
    (tester) async {
      await _pumpAdminPlanner(tester, absences: const []);

      expect(find.text('Neue Schicht'), findsOneWidget);
      await tester.tap(find.text('Neue Schicht'));
      await _settlePlanner(tester);

      // Editor offen: Titel-Feld + Tage-Tile (statt Datum) im Anlege-Modus.
      expect(find.text('Schichttitel'), findsOneWidget);
      expect(find.text('Tage'), findsWidgets);
      expect(find.text('Datum'), findsNothing);

      // Mehrtage-Picker oeffnen (Tile ggf. unten im scrollbaren Sheet).
      final tageTile = find.text('Tage').first;
      await tester.ensureVisible(tageTile);
      await _settlePlanner(tester);
      await tester.tap(tageTile);
      await _settlePlanner(tester);

      expect(find.text('Tage wählen'), findsOneWidget);
      expect(find.text('Mo'), findsWidgets);
      expect(find.text('Übernehmen'), findsOneWidget);

      // Wochentag waehlen + uebernehmen darf nicht werfen.
      await tester.tap(find.text('Mo').first);
      await _settlePlanner(tester);
      await tester.tap(find.text('Übernehmen'));
      await _settlePlanner(tester);
    },
  );

  testWidgets(
    'Neue Schicht: kompakte Mitarbeiter-Liste statt Verfuegbarkeits-Grosskarten',
    (tester) async {
      await _pumpAdminPlanner(tester, absences: const []);

      await tester.tap(find.text('Neue Schicht'));
      await _settlePlanner(tester);

      // Neuer Besetzungs-Abschnitt + kompakte Status-Badges (z. B. "0 frei").
      expect(find.text('Besetzung'), findsOneWidget);
      expect(find.textContaining('frei'), findsWidgets);
      // Mitarbeiter erscheinen als kompakte Zeilen.
      expect(find.text('Anna'), findsWidgets);
      expect(find.text('Ben'), findsWidgets);
      // Die alte, lange Verfuegbarkeits-Darstellung ist entfernt.
      expect(find.text('Verfuegbar im gewaehlten Zeitraum'), findsNothing);
      expect(find.text('Nicht verfügbar'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Editor ohne Standort: Inline-Hinweis statt Per-Person-Sperrgruenden (W6)',
    (tester) async {
      // Zwei Standorte -> keine automatische Vorbelegung, der Editor öffnet
      // ohne gewählten Standort.
      await _pumpAdminPlanner(
        tester,
        absences: const [],
        sites: const [
          SiteDefinition(id: 'site-a', orgId: 'org-1', name: 'Laden A'),
          SiteDefinition(id: 'site-b', orgId: 'org-1', name: 'Laden B'),
        ],
      );

      await tester.tap(find.text('Neue Schicht'));
      await _settlePlanner(tester);

      // Inline-Hinweis am Standort-Dropdown statt "0 frei / alle gesperrt".
      expect(
        find.text('Standort wählen, um Verfügbarkeiten zu prüfen.'),
        findsOneWidget,
      );
      // Neutrale Badges statt irreführender Zählung.
      expect(find.text('– frei'), findsOneWidget);
      expect(find.text('– gesperrt'), findsOneWidget);
      expect(find.textContaining('0 frei'), findsNothing);
      // Keine Per-Person-Sperrgründe, sondern neutraler Ungeprüft-Status.
      expect(find.text('Nicht verfügbar'), findsNothing);
      expect(
        find.text('Verfügbarkeit ungeprüft – bitte Standort wählen'),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Editor zeigt Überstunden-Hinweis, Kandidat bleibt wählbar (W6/E3)',
    (tester) async {
      // Ein Standort -> automatische Vorbelegung; Anna hat ein Wochen-Maximum
      // von 1h, die 8h-Draft-Schicht projiziert also geplante Überstunden.
      final validFrom = DateTime(2020, 1, 1);
      await _pumpAdminPlanner(
        tester,
        absences: const [],
        sites: const [
          SiteDefinition(id: 'site-1', orgId: 'org-1', name: 'Berlin HQ'),
        ],
        contracts: [
          EmploymentContract(
            id: 'contract-anna',
            orgId: 'org-1',
            userId: 'employee-anna',
            validFrom: validFrom,
            weeklyMaxHours: 1,
          ),
        ],
        siteAssignments: const [
          EmployeeSiteAssignment(
            id: 'assign-admin',
            orgId: 'org-1',
            userId: 'admin-1',
            siteId: 'site-1',
            siteName: 'Berlin HQ',
          ),
          EmployeeSiteAssignment(
            id: 'assign-anna',
            orgId: 'org-1',
            userId: 'employee-anna',
            siteId: 'site-1',
            siteName: 'Berlin HQ',
          ),
          EmployeeSiteAssignment(
            id: 'assign-ben',
            orgId: 'org-1',
            userId: 'employee-ben',
            siteId: 'site-1',
            siteName: 'Berlin HQ',
          ),
        ],
      );

      await tester.tap(find.text('Neue Schicht'));
      await _settlePlanner(tester);
      // Verfügbarkeits-Load abwarten (async Fake-Firestore-Query).
      await _settlePlanner(tester);

      // Nicht-blockierende Überstunden-Zeile am Kandidaten-Tile (nur Anna).
      final overtimeHint = find.textContaining('Über Vertragsmaximum:');
      expect(overtimeHint, findsOneWidget);
      expect(
        find.textContaining('werden als Überstunden geplant'),
        findsOneWidget,
      );
      // Kein Inline-Standort-Hinweis (Standort ist vorbelegt).
      expect(
        find.text('Standort wählen, um Verfügbarkeiten zu prüfen.'),
        findsNothing,
      );

      // Kandidat bleibt trotz Überstunden WÄHLBAR (E3): Tipp auf das Tile
      // toggelt die Auswahl (Checkbox-Anzahl ändert sich, kein Fehler).
      final checkedBefore =
          tester.widgetList(find.byIcon(Icons.check_box)).length;
      await tester.ensureVisible(overtimeHint);
      await _settlePlanner(tester);
      await tester.tap(overtimeHint);
      await _settlePlanner(tester);
      final checkedAfter =
          tester.widgetList(find.byIcon(Icons.check_box)).length;
      expect(checkedAfter, isNot(checkedBefore));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Toolbar laeuft bei schmaler Breite nicht ueber',
    (tester) async {
      await _pumpAdminPlanner(
        tester,
        absences: const [],
        physicalSize: const Size(1080, 800),
      );
      // Kein RenderFlex-Overflow beim Rendern der erweiterten Toolbar.
      expect(tester.takeException(), isNull);
      expect(find.text('Neue Schicht'), findsOneWidget);
    },
  );

  testWidgets(
    'Editor + Mehrtage-Picker auf Phone-Breite ohne Overflow',
    (tester) async {
      await _pumpAdminPlanner(
        tester,
        absences: const [],
        physicalSize: const Size(390, 844),
      );
      expect(tester.takeException(), isNull);

      // Kompakte Toolbar: "+" (Neue Schicht) per Tooltip finden und tippen.
      final addButton = find.byTooltip('Neue Schicht');
      expect(addButton, findsOneWidget);
      await tester.tap(addButton);
      await _settlePlanner(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Schichttitel'), findsOneWidget);

      // Tage-Tile sichtbar machen + Mehrtage-Picker oeffnen (kein Overflow).
      final tageTile = find.text('Tage').first;
      await tester.ensureVisible(tageTile);
      await _settlePlanner(tester);
      await tester.tap(tageTile);
      await _settlePlanner(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Tage wählen'), findsOneWidget);
    },
  );

  testWidgets(
    'Editor im Bearbeiten-Modus oeffnet auf Phone-Breite ohne Overflow',
    (tester) async {
      await _pumpAdminPlanner(
        tester,
        absences: const [],
        shifts: const [
          _SeededShift(
            id: 'shift-edit',
            userId: 'employee-anna',
            employeeName: 'Anna',
            title: 'Fruehschicht',
            siteName: 'Berlin HQ',
          ),
        ],
        physicalSize: const Size(390, 844),
      );

      await tester.tap(find.text('Fruehschicht').first);
      await _settlePlanner(tester);
      expect(tester.takeException(), isNull);
      // Edit-Modus: einzelnes "Datum" (kein Mehrtage), Aktualisieren-Button.
      expect(find.text('Datum'), findsOneWidget);
      expect(find.text('Aktualisieren'), findsOneWidget);
    },
  );

  testWidgets(
    'Long-Press-Drag einer Schichtkarte wirft keine Exception',
    (tester) async {
      await _pumpAdminPlanner(
        tester,
        absences: const [],
        shifts: const [
          _SeededShift(
            id: 'shift-drag',
            userId: 'employee-anna',
            employeeName: 'Anna',
            title: 'Fruehschicht',
            siteName: 'Berlin HQ',
          ),
        ],
      );

      final card = find.text('Fruehschicht').first;
      final gesture = await tester.startGesture(tester.getCenter(card));
      // Long-Press ausloesen, dann nach unten in eine andere Zeile ziehen.
      await tester.pump(const Duration(milliseconds: 700));
      await gesture.moveBy(const Offset(0, 220));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 220));
      await tester.pump();
      await gesture.up();
      await _settlePlanner(tester);

      // Drag/Drop darf den Board nicht zum Absturz bringen (Fehler beim
      // Kopier-Schreibpfad werden abgefangen und als Hinweis gezeigt).
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Desktop: sofortiges Klick-Drag (Draggable) wirft keine Exception',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await _pumpAdminPlanner(
          tester,
          absences: const [],
          shifts: const [
            _SeededShift(
              id: 'shift-mouse',
              userId: 'employee-anna',
              employeeName: 'Anna',
              title: 'Fruehschicht',
              siteName: 'Berlin HQ',
            ),
          ],
        );

        final card = find.text('Fruehschicht').first;
        // Sofortiges Ziehen OHNE Long-Press (Maus-Verhalten).
        final gesture = await tester.startGesture(tester.getCenter(card));
        await tester.pump(const Duration(milliseconds: 20));
        await gesture.moveBy(const Offset(0, 220));
        await tester.pump();
        await gesture.moveBy(const Offset(0, 220));
        await tester.pump();
        await gesture.up();
        await _settlePlanner(tester);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'Karten-Menue "Kopieren" oeffnet Sheet mit Mitarbeiter-Auswahl',
    (tester) async {
      await _pumpAdminPlanner(
        tester,
        absences: const [],
        shifts: const [
          _SeededShift(
            id: 'shift-copy',
            userId: 'employee-anna',
            employeeName: 'Anna',
            title: 'Fruehschicht',
            siteName: 'Berlin HQ',
          ),
        ],
      );

      await tester.tap(find.byIcon(Icons.more_horiz).first);
      await _settlePlanner(tester);
      expect(find.text('Kopieren (Mitarbeiter/Tage) ...'), findsOneWidget);

      await tester.tap(find.text('Kopieren (Mitarbeiter/Tage) ...'));
      await _settlePlanner(tester);

      // Kopier-Sheet: Mitarbeiter-Chips (z.B. Ben waehlbar) + Kopieren-Button.
      expect(find.text('Schicht kopieren'), findsOneWidget);
      expect(find.text('Ben'), findsWidgets);
      expect(find.widgetWithText(FilledButton, 'Kopieren'), findsOneWidget);
    },
  );

  testWidgets(
    'Mobile Wochenansicht (390 dp): Tagesabschnitte statt Grid (W5/E6)',
    (tester) async {
      await _pumpAdminPlanner(
        tester,
        absences: const [],
        shifts: const [
          _SeededShift(
            id: 'shift-mobile',
            userId: 'employee-anna',
            employeeName: 'Anna',
            title: 'Fruehschicht',
            siteName: 'Berlin HQ',
          ),
        ],
        viewMode: ScheduleViewMode.week,
        physicalSize: const Size(390, 844),
      );

      expect(tester.takeException(), isNull);
      // Kein Quer-Scroll-Grid: die Grid-Abschnittslabels fehlen.
      expect(find.text('FREIE SCHICHTEN'), findsNothing);
      expect(find.text('PLANMÄSSIGE SCHICHTEN'), findsNothing);
      // Tagesabschnitt des heutigen Tages + Schichtkarte vorhanden.
      final today = DateTime.now();
      expect(
        find.text(DateFormat('EEE, d. MMM', 'de_DE').format(today)),
        findsOneWidget,
      );
      expect(find.text('Fruehschicht'), findsWidgets);
      expect(find.text('Anna'), findsWidgets);
      // Prominenter Veröffentlichen-Button im Kompakt-Modus (W5).
      expect(
        find.widgetWithText(FilledButton, 'Veröffentlichen'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Stunden-Pille nutzt Vertrags-Wochenstunden als Soll (W5)',
    (tester) async {
      await _pumpAdminPlanner(
        tester,
        absences: const [],
        shifts: const [
          _SeededShift(
            id: 'shift-pille',
            userId: 'employee-anna',
            employeeName: 'Anna',
            title: 'Fruehschicht',
            siteName: 'Berlin HQ',
          ),
        ],
        teamContracts: [
          EmploymentContract(
            id: 'contract-anna',
            orgId: 'org-1',
            userId: 'employee-anna',
            validFrom: DateTime(2020, 1, 1),
            weeklyHours: 30,
          ),
        ],
        // Wochensoll gehört zur WOCHEN-Ansicht (die Tag-Ansicht zeigt die
        // Pille bewusst neutral ohne Soll — eigener Test unten).
        viewMode: ScheduleViewMode.week,
      );

      // Soll = contract.weeklyHours (30) statt settings.dailyHours×Werktage.
      expect(find.textContaining('/30h'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Tag-Ansicht: Stunden-Pille neutral nur mit Ist, ohne Wochensoll (W5)',
    (tester) async {
      await _pumpAdminPlanner(
        tester,
        absences: const [],
        shifts: const [
          _SeededShift(
            id: 'shift-pille-tag',
            userId: 'employee-anna',
            employeeName: 'Anna',
            title: 'Fruehschicht',
            siteName: 'Berlin HQ',
          ),
        ],
        teamContracts: [
          EmploymentContract(
            id: 'contract-anna',
            orgId: 'org-1',
            userId: 'employee-anna',
            validFrom: DateTime(2020, 1, 1),
            weeklyHours: 30,
          ),
        ],
        viewMode: ScheduleViewMode.day,
      );

      // Tages-Ist gegen WOCHEN-Soll wäre falsch (8h/30h) — die Pille zeigt in
      // der Tag-Ansicht nur das Ist („7,5h“, 8h minus 30 min Pause).
      expect(find.text('7,5h'), findsWidgets);
      expect(find.textContaining('/30h'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Schichtkarte zeigt ÜS-Badge bei geplanten Überstunden (W5/E1)',
    (tester) async {
      await _pumpAdminPlanner(
        tester,
        absences: const [],
        shifts: const [
          _SeededShift(
            id: 'shift-ueberstunden',
            userId: 'employee-anna',
            employeeName: 'Anna',
            title: 'Fruehschicht',
            siteName: 'Berlin HQ',
            overtimeMinutes: 150,
          ),
        ],
      );

      expect(find.text('+2,5h ÜS'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Wochenansicht ohne Overflow bei Textskalierung 1.0 und 1.3 (W5)',
    (tester) async {
      for (final scale in const [1.0, 1.3]) {
        await _pumpAdminPlanner(
          tester,
          absences: const [
            _SeededAbsence(
              id: 'absence-scale',
              userId: 'employee-anna',
              employeeName: 'Anna',
              type: 'vacation',
              status: 'approved',
            ),
          ],
          shifts: const [
            _SeededShift(
              id: 'shift-scale',
              userId: 'employee-anna',
              employeeName: 'Anna',
              title: 'Fruehschicht',
              siteName: 'Berlin HQ',
            ),
          ],
          viewMode: ScheduleViewMode.week,
          textScale: scale,
        );

        // Kein RenderFlex-Overflow — insbesondere nicht in der Board-
        // Kopfzeile (frühere feste Höhe 78, „1-px-Overflow bewiesen").
        expect(
          tester.takeException(),
          isNull,
          reason: 'Overflow bei Textskalierung $scale',
        );
      }
    },
  );
}

Future<_PlannerHarness> _pumpAdminPlanner(
  WidgetTester tester, {
  required List<_SeededAbsence> absences,
  List<_SeededShift> shifts = const [],
  List<SiteDefinition> sites = const [],
  List<EmploymentContract> contracts = const [],
  List<EmploymentContract> teamContracts = const [],
  List<EmployeeSiteAssignment> siteAssignments = const [],
  ScheduleViewMode viewMode = ScheduleViewMode.day,
  Size physicalSize = const Size(1600, 1200),
  // Reale Standard-Skalierung — die frühere 0.78 maskierte den 1-px-Overflow
  // der Board-Kopfzeile (Plan W5, Befund „1-px-Overflow bewiesen").
  double textScale = 1.0,
  ShiftPlanExportCallback? onShiftPlanExport,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = physicalSize;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  // Statischer UI-Komfort-Merker: darf nicht zwischen Tests leaken (er würde
  // sonst den Standort im Editor unerwartet vorbelegen).
  ScheduleProvider.lastUsedSiteId = null;

  const admin = AppUserProfile(
    uid: 'admin-1',
    orgId: 'org-1',
    email: 'admin@example.com',
    role: UserRole.admin,
    isActive: true,
    settings: UserSettings(name: 'Admin'),
  );
  const anna = AppUserProfile(
    uid: 'employee-anna',
    orgId: 'org-1',
    email: 'anna@example.com',
    role: UserRole.employee,
    isActive: true,
    settings: UserSettings(name: 'Anna'),
  );
  const ben = AppUserProfile(
    uid: 'employee-ben',
    orgId: 'org-1',
    email: 'ben@example.com',
    role: UserRole.employee,
    isActive: true,
    settings: UserSettings(name: 'Ben'),
  );

  final firestore = FakeFirebaseFirestore();
  final firestoreService = FirestoreService(firestore: firestore);

  Future<void> seedUser(AppUserProfile profile) {
    return firestore
        .collection('users')
        .doc(profile.uid)
        .set(profile.toFirestoreMap());
  }

  await seedUser(admin);
  await seedUser(anna);
  await seedUser(ben);

  final today = DateTime.now();
  final day = DateTime(today.year, today.month, today.day, 12);
  final absenceCollection = firestore
      .collection('organizations')
      .doc(admin.orgId)
      .collection('absenceRequests');
  final shiftCollection = firestore
      .collection('organizations')
      .doc(admin.orgId)
      .collection('shifts');

  for (final absence in absences) {
    await absenceCollection.doc(absence.id).set({
      'orgId': admin.orgId,
      'userId': absence.userId,
      'employeeName': absence.employeeName,
      'startDate': Timestamp.fromDate(day),
      'endDate': Timestamp.fromDate(day),
      'type': absence.type,
      'status': absence.status,
      'createdAt': Timestamp.fromDate(day),
      'updatedAt': Timestamp.fromDate(day),
    });
  }

  final siteCollection = firestore
      .collection('organizations')
      .doc(admin.orgId)
      .collection('sites');
  for (final site in sites) {
    await siteCollection.doc(site.id).set(site.toFirestoreMap());
  }

  for (final shift in shifts) {
    await shiftCollection.doc(shift.id).set({
      'orgId': admin.orgId,
      'userId': shift.userId,
      'employeeName': shift.employeeName,
      'title': shift.title,
      'startTime': Timestamp.fromDate(day),
      'endTime': Timestamp.fromDate(day.add(const Duration(hours: 8))),
      'breakMinutes': 30.0,
      'siteId': 'site-${shift.id}',
      'siteName': shift.siteName,
      'location': shift.siteName,
      'requiredQualificationIds': const <String>[],
      'status': shift.status.value,
      'overtimeMinutes': shift.overtimeMinutes,
      'createdAt': Timestamp.fromDate(day),
      'updatedAt': Timestamp.fromDate(day),
    });
  }

  // Verträge für die Stunden-Pille (W5): TeamProvider streamt
  // employmentContracts org-weit (admin) — hier direkt in Firestore seeden.
  final contractCollection = firestore
      .collection('organizations')
      .doc(admin.orgId)
      .collection('employmentContracts');
  for (final contract in teamContracts) {
    await contractCollection
        .doc(contract.id ?? 'contract-${contract.userId}')
        .set(contract.toFirestoreMap());
  }

  final authProvider = _TestAuthProvider(
    firestoreService: firestoreService,
    profile: admin,
  );
  final scheduleProvider = ScheduleProvider(
    firestoreService: firestoreService,
  );
  final teamProvider = TeamProvider(
    firestoreService: firestoreService,
  );

  await teamProvider.updateSession(admin);
  await scheduleProvider.updateSession(admin);
  if (contracts.isNotEmpty || siteAssignments.isNotEmpty) {
    scheduleProvider.updateReferenceData(
      members: const [admin, anna, ben],
      contracts: contracts,
      siteAssignments: siteAssignments,
      ruleSets: [ComplianceRuleSet.defaultRetail(admin.orgId)],
      travelTimeRules: const [],
      sites: sites,
    );
  }
  scheduleProvider.setViewMode(viewMode);
  scheduleProvider.setVisibleDate(day);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<ScheduleProvider>.value(
          value: scheduleProvider,
        ),
        ChangeNotifierProvider<TeamProvider>.value(value: teamProvider),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: Scaffold(
              body: ShiftPlannerScreen(
                onShiftPlanExport: onShiftPlanExport,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await _settlePlanner(tester);
  if (shifts.isNotEmpty) {
    for (var i = 0; i < 6 && scheduleProvider.shifts.isEmpty; i++) {
      await _settlePlanner(tester);
    }
  }
  return _PlannerHarness(scheduleProvider: scheduleProvider);
}

Future<void> _settlePlanner(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _openFilterMenu(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

class _SeededAbsence {
  const _SeededAbsence({
    required this.id,
    required this.userId,
    required this.employeeName,
    required this.type,
    required this.status,
  });

  final String id;
  final String userId;
  final String employeeName;
  final String type;
  final String status;
}

class _SeededShift {
  const _SeededShift({
    required this.id,
    required this.userId,
    required this.employeeName,
    required this.title,
    required this.siteName,
    this.status = ShiftStatus.planned,
    this.overtimeMinutes = 0,
  });

  final String id;
  final String userId;
  final String employeeName;
  final String title;
  final String siteName;
  final ShiftStatus status;

  /// Geplante Überstunden (W1/E1) — für die ÜS-Badge-Tests.
  final int overtimeMinutes;
}

class _PlannerHarness {
  const _PlannerHarness({
    required this.scheduleProvider,
  });

  final ScheduleProvider scheduleProvider;
}

class _TestAuthProvider extends AuthProvider {
  _TestAuthProvider({
    required super.firestoreService,
    AppUserProfile? profile,
  })  : _profile = profile,
        super(authService: AuthService());

  AppUserProfile? _profile;

  @override
  AppUserProfile? get profile => _profile;

  void setProfile(AppUserProfile? value) {
    _profile = value;
    notifyListeners();
  }
}
