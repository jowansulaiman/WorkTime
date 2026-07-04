import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/theme/app_theme.dart';
import 'package:worktime_app/ui/ui.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool disableAnimations = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightV2,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: disableAnimations),
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    ),
  );
}

void main() {
  group('AppCard', () {
    testWidgets('zeigt Kind und ruft onTap', (tester) async {
      var tapped = false;
      await _pump(
        tester,
        AppCard(onTap: () => tapped = true, child: const Text('Inhalt')),
      );
      expect(find.text('Inhalt'), findsOneWidget);
      await tester.tap(find.text('Inhalt'));
      expect(tapped, isTrue);
    });
  });

  group('AppSectionCard', () {
    testWidgets('zeigt Titel + Kind', (tester) async {
      await _pump(
        tester,
        const AppSectionCard(title: 'Abschnitt', child: Text('Body')),
      );
      expect(find.text('Abschnitt'), findsOneWidget);
      expect(find.text('Body'), findsOneWidget);
    });
  });

  group('AppMetricCard', () {
    testWidgets('zeigt Label + Wert (Icon optional)', (tester) async {
      await _pump(
        tester,
        const AppMetricCard(
          label: 'Stunden',
          value: '12,5 h',
          icon: Icons.access_time,
        ),
      );
      expect(find.text('Stunden'), findsOneWidget);
      expect(find.text('12,5 h'), findsOneWidget);
      expect(find.byIcon(Icons.access_time), findsOneWidget);
    });
  });

  group('AppStatCard', () {
    testWidgets('zeigt Label/Wert/Untertitel/Icon', (tester) async {
      await _pump(
        tester,
        const AppStatCard(
          label: 'Ueberstunden',
          value: '3,0 h',
          subtitle: 'oberhalb der Vorgabe',
          icon: Icons.trending_up,
          color: Color(0xFF0E7C7B),
        ),
      );
      expect(find.text('Ueberstunden'), findsOneWidget);
      expect(find.text('3,0 h'), findsOneWidget);
      expect(find.text('oberhalb der Vorgabe'), findsOneWidget);
      expect(find.byIcon(Icons.trending_up), findsOneWidget);
    });
  });

  group('AppComparisonStatCard (Mathematik 1:1 erhalten)', () {
    testWidgets('ueber Soll: +Differenz, Soll/Ist-Text', (tester) async {
      await _pump(
        tester,
        const AppComparisonStatCard(
          plannedHours: 10,
          actualHours: 12,
          loading: false,
        ),
      );
      expect(find.text('Soll / Ist'), findsOneWidget);
      expect(find.text('+2.0 h'), findsOneWidget);
      expect(find.text('12.0 h Ist von 10.0 h Soll'), findsOneWidget);
    });

    testWidgets('unter Soll: negative Differenz', (tester) async {
      await _pump(
        tester,
        const AppComparisonStatCard(
          plannedHours: 10,
          actualHours: 8,
          loading: false,
        ),
      );
      expect(find.text('-2.0 h'), findsOneWidget);
    });

    testWidgets('exakt auf Soll: 0.0 h ohne Vorzeichen', (tester) async {
      await _pump(
        tester,
        const AppComparisonStatCard(
          plannedHours: 10,
          actualHours: 10,
          loading: false,
        ),
      );
      expect(find.text('0.0 h'), findsOneWidget);
    });

    testWidgets('loading: exakte deutsche Lade-Texte', (tester) async {
      await _pump(
        tester,
        const AppComparisonStatCard(
          plannedHours: null,
          actualHours: 0,
          loading: true,
        ),
      );
      expect(find.text('Laedt...'), findsOneWidget);
      expect(find.text('Geplante Schichten werden geladen'), findsOneWidget);
    });

    testWidgets('Vorzeichen-Grenzfall: > 0.05 zeigt +, sonst kein +',
        (tester) async {
      // diff ~0.04 -> kein Vorzeichen, '0.0 h'
      await _pump(
        tester,
        const AppComparisonStatCard(
            plannedHours: 10, actualHours: 10.04, loading: false),
      );
      expect(find.text('0.0 h'), findsOneWidget);
      // diff ~0.06 -> Vorzeichen, '+0.1 h'
      await _pump(
        tester,
        const AppComparisonStatCard(
            plannedHours: 10, actualHours: 10.06, loading: false),
      );
      expect(find.text('+0.1 h'), findsOneWidget);
    });

    testWidgets('Akzentfarbe folgt der Schwellen-Logik (loading/over/under/on)',
        (tester) async {
      // lightV2: tertiary #7A5BD6, error #BA5C67, success #187A58, primary #0E7C7B
      Color progressColor() => tester
          .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator))
          .color!;

      await _pump(
        tester,
        const AppComparisonStatCard(
            plannedHours: 10, actualHours: 11, loading: false),
      );
      expect(progressColor(),
          const Color(0xFF187A58)); // ueber Soll -> success (gruen, §4.11 G2)

      await _pump(
        tester,
        const AppComparisonStatCard(
            plannedHours: 10, actualHours: 9, loading: false),
      );
      expect(progressColor(), const Color(0xFFBA5C67)); // unter Soll -> error

      await _pump(
        tester,
        const AppComparisonStatCard(
            plannedHours: 10, actualHours: 10, loading: false),
      );
      expect(progressColor(), const Color(0xFF187A58)); // auf Soll -> success

      await _pump(
        tester,
        const AppComparisonStatCard(
            plannedHours: null, actualHours: 0, loading: true),
      );
      expect(progressColor(), const Color(0xFF0E7C7B)); // loading -> primary
    });
  });

  group('AppStatusBadge', () {
    testWidgets('weich + gefuellt zeigen Label', (tester) async {
      await _pump(
        tester,
        const Column(
          children: [
            AppStatusBadge(label: 'Geplant', tone: AppStatusTone.tertiary),
            AppStatusBadge(
              label: 'Standort aktiv',
              tone: AppStatusTone.success,
              filled: true,
            ),
          ],
        ),
      );
      expect(find.text('Geplant'), findsOneWidget);
      expect(find.text('Standort aktiv'), findsOneWidget);
    });
  });

  group('AppStatusBanner', () {
    testWidgets('zeigt Nachricht + Aktion', (tester) async {
      await _pump(
        tester,
        AppStatusBanner(
          icon: Icons.cloud_upload_outlined,
          message: '1 ausstehende Loeschung',
          tone: AppStatusTone.tertiary,
          action: TextButton(onPressed: () {}, child: const Text('Jetzt')),
        ),
      );
      expect(find.text('1 ausstehende Loeschung'), findsOneWidget);
      expect(find.text('Jetzt'), findsOneWidget);
    });
  });

  group('AppSegmented', () {
    testWidgets('aktiviert: Auswahl ruft onChanged', (tester) async {
      int? picked;
      await _pump(
        tester,
        AppSegmented<int>(
          segments: const [
            AppSegment(value: 0, label: 'Tag'),
            AppSegment(value: 1, label: 'Woche'),
          ],
          selected: 0,
          onChanged: (value) => picked = value,
        ),
      );
      await tester.tap(find.text('Woche'));
      expect(picked, 1);
    });

    testWidgets('deaktiviert: Tippen ruft onChanged NICHT', (tester) async {
      int? picked;
      await _pump(
        tester,
        AppSegmented<int>(
          enabled: false,
          segments: const [
            AppSegment(value: 0, label: 'Tag'),
            AppSegment(value: 1, label: 'Woche'),
          ],
          selected: 0,
          onChanged: (value) => picked = value,
        ),
      );
      await tester.tap(find.text('Woche'), warnIfMissed: false);
      expect(picked, isNull);
    });
  });

  group('AppFilterChip', () {
    testWidgets('zeigt Label und meldet Auswahl', (tester) async {
      bool? value;
      await _pump(
        tester,
        AppFilterChip(
          label: 'Nur offene',
          selected: false,
          onSelected: (v) => value = v,
        ),
      );
      expect(find.text('Nur offene'), findsOneWidget);
      await tester.tap(find.text('Nur offene'));
      expect(value, isTrue);
    });
  });

  group('AppQuickAction*', () {
    testWidgets('Card zeigt Titel/Untertitel und ruft onTap', (tester) async {
      var tapped = false;
      await _pump(
        tester,
        AppQuickActionCard(
          icon: Icons.add,
          title: 'Eintrag',
          subtitle: 'Zeit erfassen',
          onTap: () => tapped = true,
        ),
      );
      expect(find.text('Eintrag'), findsOneWidget);
      expect(find.text('Zeit erfassen'), findsOneWidget);
      await tester.tap(find.text('Eintrag'));
      expect(tapped, isTrue);
    });

    testWidgets('Tile zeigt Titel/Untertitel und ruft onTap', (tester) async {
      var tapped = false;
      await _pump(
        tester,
        AppQuickActionTile(
          icon: Icons.add,
          title: 'Schicht',
          subtitle: 'Neu planen',
          onTap: () => tapped = true,
        ),
      );
      expect(find.text('Schicht'), findsOneWidget);
      await tester.tap(find.text('Schicht'));
      expect(tapped, isTrue);
    });
  });

  group('AppHeroCard', () {
    testWidgets('rendert Kind in neutraler + Akzent-Tonalitaet', (tester) async {
      await _pump(
        tester,
        const Column(
          children: [
            AppHeroCard(child: Text('Neutral')),
            AppHeroCard(tone: AppHeroTone.accent, child: Text('Akzent')),
          ],
        ),
      );
      expect(find.text('Neutral'), findsOneWidget);
      expect(find.text('Akzent'), findsOneWidget);
    });
  });

  group('AppEmptyState (Alias)', () {
    testWidgets('rendert Nachricht', (tester) async {
      await _pump(
        tester,
        const AppEmptyState(
          icon: Icons.inbox_outlined,
          message: 'Nichts vorhanden',
        ),
      );
      expect(find.text('Nichts vorhanden'), findsOneWidget);
    });
  });

  group('AppBottomSheetScaffold', () {
    testWidgets('zeigt Titel + Kind', (tester) async {
      await _pump(
        tester,
        const AppBottomSheetScaffold(
          title: 'Stempeluhr',
          subtitle: 'Ein- und ausstempeln',
          child: Text('Sheet-Inhalt'),
        ),
      );
      expect(find.text('Stempeluhr'), findsOneWidget);
      expect(find.text('Sheet-Inhalt'), findsOneWidget);
    });
  });

  group('AppFormField', () {
    testWidgets('zeigt Label und meldet Eingabe', (tester) async {
      String? changed;
      await _pump(
        tester,
        AppFormField(
          label: 'Notiz',
          onChanged: (v) => changed = v,
        ),
      );
      expect(find.text('Notiz'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Hallo');
      expect(changed, 'Hallo');
    });
  });

  group('AppConfirmDialog', () {
    testWidgets('liefert true bei Bestaetigung, false bei Abbruch',
        (tester) async {
      Future<void> openAndConfirm(String tapLabel) async {
        bool? result;
        await _pump(
          tester,
          Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  result = await AppConfirmDialog.show(
                    context,
                    title: 'Eintrag löschen?',
                    message: 'Unwiderruflich.',
                    confirmLabel: 'Löschen',
                  );
                },
                child: const Text('Oeffnen'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Oeffnen'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(tapLabel));
        await tester.pumpAndSettle();
        if (tapLabel == 'Löschen') {
          expect(result, isTrue);
        } else {
          expect(result, isFalse);
        }
      }

      await openAndConfirm('Löschen');
      await openAndConfirm('Abbrechen');
    });

    testWidgets('non-destructive + eigene Labels werden gezeigt',
        (tester) async {
      bool? result;
      await _pump(
        tester,
        Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async {
                result = await AppConfirmDialog.show(
                  context,
                  title: 'Veroeffentlichen?',
                  message: 'Plan freigeben.',
                  confirmLabel: 'Freigeben',
                  cancelLabel: 'Spaeter',
                  destructive: false,
                );
              },
              child: const Text('Oeffnen'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Oeffnen'));
      await tester.pumpAndSettle();
      expect(find.text('Freigeben'), findsOneWidget);
      expect(find.text('Spaeter'), findsOneWidget);
      await tester.tap(find.text('Freigeben'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });
  });

  group('Reduce Motion', () {
    testWidgets('disableAnimations=true -> Duration.zero', (tester) async {
      late Duration resolved;
      await _pump(
        tester,
        Builder(
          builder: (context) {
            resolved = AppMotion.resolve(context, context.motion.medium);
            return const SizedBox();
          },
        ),
        disableAnimations: true,
      );
      expect(resolved, Duration.zero);
    });

    testWidgets('disableAnimations=false -> unveraenderte Dauer (300ms)',
        (tester) async {
      late Duration resolved;
      late Duration token;
      await _pump(
        tester,
        Builder(
          builder: (context) {
            token = context.motion.medium;
            resolved = AppMotion.resolve(context, token);
            return const SizedBox();
          },
        ),
      );
      expect(token, const Duration(milliseconds: 300));
      expect(resolved, const Duration(milliseconds: 300));
    });
  });

  group('AppErrorState', () {
    testWidgets('zeigt Titel + Nachricht, Retry ruft Rueckruf', (tester) async {
      var retried = false;
      await _pump(
        tester,
        AppErrorState(
          message: 'Keine Verbindung zum Server.',
          onRetry: () => retried = true,
        ),
      );
      expect(find.text('Etwas ist schiefgelaufen'), findsOneWidget);
      expect(find.text('Keine Verbindung zum Server.'), findsOneWidget);
      await tester.tap(find.text('Erneut versuchen'));
      expect(retried, isTrue);
    });

    testWidgets('ohne onRetry: kein Button; eigener Titel wird gezeigt',
        (tester) async {
      await _pump(
        tester,
        const AppErrorState(message: 'Fehler.', title: 'Laden gescheitert'),
      );
      expect(find.text('Laden gescheitert'), findsOneWidget);
      expect(find.text('Erneut versuchen'), findsNothing);
    });
  });

  group('AppOfflineBanner', () {
    testWidgets('offline: zeigt Warnung + cloud_off-Icon', (tester) async {
      await _pump(tester, const AppOfflineBanner(offline: true));
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
      expect(find.textContaining('Offline'), findsOneWidget);
    });

    testWidgets('online: kein Banner-Inhalt', (tester) async {
      await _pump(tester, const AppOfflineBanner(offline: false));
      expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
    });
  });

  group('AppSearchField', () {
    testWidgets('meldet Eingabe und zeigt Löschen-Button erst bei Text',
        (tester) async {
      String? changed;
      final controller = TextEditingController();
      await _pump(
        tester,
        AppSearchField(
          controller: controller,
          hint: 'Kontakte suchen',
          onChanged: (v) => changed = v,
        ),
      );
      expect(find.text('Kontakte suchen'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
      await tester.enterText(find.byType(TextField), 'Meier');
      await tester.pump();
      expect(changed, 'Meier');
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets('Löschen leert Feld und meldet leeren String + onClear',
        (tester) async {
      String? changed;
      var cleared = false;
      final controller = TextEditingController(text: 'Meier');
      await _pump(
        tester,
        AppSearchField(
          controller: controller,
          onChanged: (v) => changed = v,
          onClear: () => cleared = true,
        ),
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      expect(controller.text, isEmpty);
      expect(changed, '');
      expect(cleared, isTrue);
    });
  });
}
