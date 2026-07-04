# Test-Konventionen

Es gibt **keine CI** und kein Makefile. Die Quality Gates führen Sie vor jedem Commit selbst aus. Die Tests laufen **komplett offline** mit Fakes.

## Quality Gates (Definition of Done)

```bash
flutter analyze    # Lint: nur package:flutter_lints/flutter.yaml — NICHT ohne Auftrag erweitern
flutter test       # ~16+ Files, offline (fakes)
flutter test test/work_provider_test.dart --plain-name 'teil des testnamens'
flutter test --coverage   # coverage/lcov.info; Ziel: kritische Provider/Services >= 70 %
```

## Nie echtes Firebase

> [!IMPORTANT]
> `FirestoreService(firestore: FakeFirebaseFirestore())` (`fake_cloud_firestore`). Der Konstruktor nimmt optional `firestore`, `functions`, `cloudFunctionInvoker`, `uuid`.

Callables simulieren: `cloudFunctionInvoker: (name, payload) async => ...`. `FirebaseFunctionsException(code:'not-found'|'unavailable', …)` werfen, um direkte-Write-/Hybrid-Fallbacks zu testen.

## Pflicht-Setup

```dart
TestWidgetsFlutterBinding.ensureInitialized();
await initializeDateFormatting('de_DE');
SharedPreferences.setMockInitialValues({});
DatabaseService.resetCachedPrefs();   // statischer Cache!
```

Provider-Tests: `await provider.updateSession(user)`, dann `provider.updateReferenceData(sites:, contracts:, siteAssignments:, ruleSets:, travelTimeRules:)` (Schedule auch `members:`). `ruleSets` meist `[ComplianceRuleSet.defaultRetail('org-1')]`. Nach Moduswechsel `await Future<void>.delayed(Duration.zero)` (ggf. 2×).

## Weitere Fallen

- Seam zum Abfangen von Writes = **Subklasse** (`_TestWorkProvider extends WorkProvider`), **kein Mockito** (nicht vorhanden – nicht einführen).
- Compliance auf `.code` asserten, nicht auf Message.
- `FakeFirebaseFirestore` gibt Zahlen als `double` zurück (`breakMinutes == 30.0`) – keine int-Gleichheit.
- „Current week"-Tests via `dayInCurrentWeek(offset)` (Wall-Clock), keine harten Daten. Reine Compliance-Tests dürfen feste Daten nutzen.
- Widget/Shell-Tests über `test/support/router_harness.dart` (`pumpApp`).
- `assets/fonts/NotoSans-*.ttf` sind harte Abhängigkeit (PdfService wirft sonst). CSV (`ExportService.buildShiftPlanCsv`) hat UTF-8-BOM + `;`-Delimiter – BOM nicht entfernen.

## Weiter

- [Die Zwei-Serialisierungs-Regel](article:dev-zwei-serialisierung)
- [Beitragen & Konventionen](article:dev-beitragen-konventionen)
