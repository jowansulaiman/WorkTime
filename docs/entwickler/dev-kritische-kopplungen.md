# Kritische Kopplungen

„Wenn du X änderst, ändere auch Y." Diese Kopplungen sind die häufigste Fehlerquelle bei Änderungen. Sie stammen aus `CLAUDE.md` und sind hier mit Bezug ausformuliert.

## 1. Feld zu Model hinzufügen → 6 Stellen

`toFirestoreMap`, `fromFirestore`, `toMap`, `fromMap`, `copyWith` (+ `clearX` wenn nullable) und – falls es durch Callables geht – snake_case parse/serialize in `functions/index.js`. Siehe [Zwei-Serialisierungs-Regel](article:dev-zwei-serialisierung).

## 2. Compliance-Regel/Schwelle/Code ändern

In `compliance_service.dart` **und** `functions/index.js` (+ `ComplianceRuleSet.defaultRetail()` ↔ `defaultRuleSet('DE Einzelhandel Standard')`). Siehe [Compliance-Engine](article:dev-compliance-engine).

## 3. Enum-Wert hinzufügen/umbenennen

`.value`-Getter + `fromValue`-Default + deutsches `label` + ggf. passender String in `functions/index.js`/`firestore.rules` (z. B. `normalizeRole` mappt `teamleiter`→`teamlead` in beiden).

## 4. Neuer abhängiger Provider

Nach Auth/Team/Schedule/Storage in die `main.dart`-Kette einfügen (Reihenfolge tragend). Siehe [Provider-Kette](article:dev-provider-kette).

## 5. Neue lokal-persistierte Collection

Key in `DatabaseService` registrieren, org- vs. user-skopiert via `_orgScopedCollectionKeys`, über `_load/_saveCollection` laufen lassen, `toMap`/`fromMap` muss round-trippen. Siehe [Speichermodi](article:dev-storage-modi).

## 6. Neuer Firestore-Write-Pfad → 3 Enforcement-Punkte

Callable (falls shift/entry), `firestore.rules` (erlauben direkte Writes!) und Payload-Format (Callable=snake_case, direkt=camelCase). Siehe [Sicherheit & Mandantentrennung](article:dev-sicherheit-multi-tenancy).

## 7. Neuer Root-UI-State / neuer Tab

Root-State: Gate-Route + Zweig in `_gateRedirect`. Neuer Tab: `ShellTab`-Enum (Reihenfolge = Branch-Index!) + `StatefulShellBranch` + `_destinationMeta`/`_isTabVisible`/`buildHomeTab` + Permission im Redirect. Neuer Hauptbereich-Screen: `AppRoutes`-Konstante + `_sectionRoute` + `RoutePermissions`. Siehe [Routing](article:dev-routing).

## 8. FIREBASE_FUNCTIONS_REGION ändern

Muss `const REGION` in `functions/index.js` entsprechen – sonst schlagen Callables fehl (`not-found`/`unavailable`) und triggern still den direkten Fallback (umgeht Compliance).

> [!WARNING]
> Diese Liste ist nicht optional. Fast jeder „mysteriöse" Bug in diesem Projekt ist eine halb gezogene Kopplung.

## Weiter

- [Beitragen & Konventionen](article:dev-beitragen-konventionen)
- [Test-Konventionen](article:dev-testing)
