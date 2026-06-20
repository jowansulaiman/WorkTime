# Plan: AllTec-Erkenntnisse in WorkTime übernehmen + Bestehendes verbessern

> **Status (Stand 2026-06-21):** Sofort-Scope **M0 + M1 umgesetzt & verifiziert**
> (`flutter analyze` sauber, `flutter test` = 400 grün). Nächster Schritt: **M2**.
> Vollständiger Fahrplan unten; Governance = Ausblick, Audit-Trail fest in M5.

## Kontext

`/Users/jowan/Documents/dev/AllTec` (`alltec_suite`) ist eine ausgereifte Schwester-Codebasis
desselben Entwicklers: eine sicherheitsgehärtete Clean-Architecture-Suite für einen IT-Bildungsträger
(~928 Dart-Dateien, 40 Module). Viele ihrer Module überlappen **exakt** das, was WorkTime gerade
ausbaut: **CRM ↔ Kontakte**, **Inventory ↔ Warenwirtschaft**, **Personnel/Finance/Cost ↔ Personal-Modul**,
Time-Tracking/Scheduling/Tasks, plus Querschnitts-Technik (Audit, DSGVO, Benachrichtigungen, Reporting/PDF).

Die Architekturen sind **bewusst inkompatibel**: AllTec = bloc/Cubit · GetIt · GoRouter · Freezed · Hive ·
fpdart · TS-Functions. WorkTime = provider · kein Router · Hand-Dual-Serialisierung · SharedPreferences ·
Spark-Free-Tier · de_DE. **Übernahme heißt deshalb: Domänenmodelle, Geschäftslogik (v. a. korrekte
deutsche Lohnsteuer) und UX-Muster per Hand re-implementieren — niemals Code/Architektur transplantieren.**

Parallel hat die Analyse mehrere **konkrete Fehler/Lücken** in den frisch gebauten WorkTime-Modulen
gefunden (Bestand driftet nach oben, Personal-Modul auf Default-Installation unerreichbar, Lohnsteuer
massiv überschätzt, Kontakte sind eine Insel). Dieser Plan behebt diese zuerst und übernimmt dann
gezielt das Wertvollste aus AllTec.

**Ergebnis:** korrektere Zahlen (Bestand, Lohn), sichtbare/erreichbare Module, sichtbarer Geschäftswert
(Warenwert, Nachbestellung, Benachrichtigungen) und ein verbundenes System (Bestellungen ↔ Kontakte) —
alles in WorkTimes schlanken Konventionen und Spark-sparsam.

---

## 1. Leitplanken — was wir NICHT übernehmen (Anti-Over-Engineering)

- **Keine Architektur-Transplantation:** kein fpdart/Either, kein bloc/Cubit, kein GetIt/injectable,
  kein GoRouter, kein Freezed/json_serializable-Codegen, kein Hive, kein EventBus, keine SyncQueue,
  kein Functions-Fanout. Nur Modelle + Algorithmen, von Hand neu typisiert.
- **Spark-Frugalität:** Benachrichtigungen, Audit-Einträge, Aktivitäten clientseitig erzeugen und in
  SharedPreferences spiegeln (wie bestehender *userContent*) — **nicht** pro Read/Event nach Firestore schreiben.
- **Geld immer `int` Cent.** AllTecs `cost_calculation` nutzt ausnahmsweise `double` Euro — **nicht** übernehmen.
  AllTecs `german_tax_service` rechnet intern in `double` Euro, liefert aber `int`-Cent — Tarif-Mathe portieren,
  Cent-Grenzen behalten.
- **Modellierungsfehler nicht erben:** `supplierArticleNumber`/`packagingUnit` gehören an die Produkt-Lieferant-
  Relation (→ ans Produkt), nicht an den Lieferanten; keine parallele `ContactOrganization` — WorkTimes flaches
  `Contact` bleibt die einzige Wahrheit.
- **Governance schlank halten:** kein Server-Hash-Chain-Audit, kein KMS, keine 4-Augen-Export-Jobs, keine
  Permission-Scope-Hierarchie, keine 85-Permission-Matrix.
- **Dual-Serialisierungs-Regel (CLAUDE.md Kopplung 1):** jedes neue Feld = 6 Touchpoints
  (`toFirestoreMap`/`fromFirestore` camelCase+Timestamp, `toMap`/`fromMap` snake_case+ISO, `copyWith` + `clearX` falls nullable).
- **Lazy Cloud-Repo (Memory `provider-lazy-cloud-repo`):** neue Provider lösen Cloud-Repos nie im Konstruktor auf.

---

## 2. ✅ ERLEDIGT — Meilenstein 0 + 1 (Korrektheit & Sichtbarkeit)

### ✅ M0.1 — Personal-Modul im V1-Profil-Hub sichtbar machen · [P0 · ux · klein]
`isAdmin`-gegatete Kachel „Personal" im `_ProfileHubTab` von `lib/screens/home_screen.dart` ergänzt
(öffnet `PersonalScreen` per `Navigator.push`). Das fertige HR-Modul ist jetzt auch ohne V2-Flag erreichbar.

### ✅ M0.2 — „Abgang buchen" + Negativbestand-Guard · [P0 · correctness · klein]
`issueStock()` + `validateStockIssue()` in `lib/providers/inventory_provider.dart` (nutzt die bestehende
atomare `adjustStock`-Transaktion, Typ `StockMovementType.issue`); harte Überzugs-Sperre mit deutscher
Meldung. „Abgang buchen"-Menüpunkt + Dialog in `lib/screens/inventory_screen.dart`. Test:
`issueStock blockt Bestandsueberzug und bucht sonst einen Abgang`.

### ✅ M1.1 — Lohnsteuer auf §32a-EStG-Tarif gehoben · [P1 · correctness · mittel]
Neuer reiner Tarif `lib/core/german_tax.dart` (`TaxTariff.year2026`, Grundfreibetrag, 5-Zonen-Progression,
Vorsorgepauschale, Soli-Milderungszone, Splittingtarif Kl. III). Eingebunden in
`lib/core/payroll_calculator.dart` über `settings.taxTariff` (`lib/models/payroll_settings.dart`).
Verifiziert (Tests `german_tax_test`, `payroll_calculator_test`): 1.000 €→0 € · 3.000 € Kl. I→304 € ·
8.000 € Kl. I→1.854 €. Richtwert-Disclaimer bleibt in UI + PDF.

### ✅ M1.2 — Lohn-Stammdaten je Mitarbeiter (`PayrollProfile`) · [P1 · correctness/ux · mittel]
Neues `lib/models/payroll_profile.dart` (Doc-ID = userId, admin-only), Plumbing in
`firestore_service`/`database_service`/`personal_provider` (+ write-frugales `rememberPayrollProfile`),
`firestore.rules`-Block `payrollProfiles`. Lohn-Editor erfasst jetzt das **Bundesland** (KiSt 8/9 %) und
**vorbefüllt** Steuerklasse/Art/Kirchensteuer/Bundesland/Brutto aus dem Profil. Tests: `payroll_profile_test`,
`personal_provider_test` (rememberPayrollProfile).

> **Deployment-Hinweis:** Die neue `payrollProfiles`-Regel braucht vor Cloud-Nutzung
> `firebase deploy --only firestore:rules` (lokal/Demo läuft sofort).

---

## 3. ANSCHLUSS-FAHRPLAN (offen, Meilenstein für Meilenstein, jeweils Check-in)

### M2 — Geschäftswert sichtbar machen · [P1, mehrheitlich klein]  ← NÄCHSTER SCHRITT
- **Warenwert + Marge** [Übernahme: AllTec `costPriceCents`-Intent]: reine Getter auf `InventoryProvider`
  `totalStockValueCents({siteId})` = Σ(`currentStock` × `purchasePriceCents`) je Standort + gesamt; Marge-Getter
  auf `Product` (WorkTime hat zusätzlich `sellingPriceCents`). Keine Schema-/Firestore-Änderung. Anzeige im
  Inventar-Header + V2-Admin-Dashboard („Warenwert Strichmännchen: 1.240,50 €").
- **Export erweitern** [Verbesserung]: Bestandsliste, Nachbestell-Liste und Lieferantenbestellungen als PDF+CSV
  (heute nur Kundenbestellungen). Bestehendes `PdfService`/`ExportService`-Muster (UTF-8-BOM, `;`) wiederverwenden.
  „Bestellt" zur echten Aktion machen: PO-PDF + vorausgefüllter `mailto:` an `supplier.effectiveOrderEmail`.
- **Zwei-Schwellen-Nachbestellung** [Übernahme: AllTec `Article.targetStock`]: `targetStock` („Zielbestand", int=0)
  an `Product`; `suggestedReorderQuantity` bevorzugt `(targetStock − currentStock)` statt `minStock*2`-Schätzung.
- **Proaktive Nachbestell-Warnung** [Verbesserung, klein]: `lowStockProducts` in **exakt** das bewährte
  `ordersDueSoonNotPrepared`-Muster einspeisen (Listen-Banner + Home-Dashboard + Benachrichtigungs-Center).

### M3 — Navigation + Benachrichtigungs-Rückgrat · [P1, mittel]
- **Persistenter `NotificationProvider` + `ReminderScheduler`** [Übernahme: AllTec `Reminder`/`AppNotification`]:
  dauerhafte, abhakbare Hinweise statt pro-Frame berechneter Inbox. Clientseitig erzeugt,
  SharedPreferences-persistiert, deterministische IDs (`order-<id>-pickup`). Kein Functions-Fanout.
- **Module als echte Shell-Tabs** [Verbesserung, CLAUDE.md Kopplung 7]: Warenwirtschaft/Kundenbestellungen/Personal
  zu permission-gegateten `_ShellDestinationId`-Einträgen heben (via `destinations.indexWhere`).
- **„Hinweise & Aktionspunkte"-Karte** [Übernahme: AllTec `DashboardWarning`/`WarningListCard`]: severity-sortierte
  Sammelkarte statt verstreuter Banner; Farben via `appColors`, „link" = Tab-ID statt Route.

### M4 — CRM-Verknüpfung + Konsistenz · [P1/P2]
- **`contactId` an `CustomerOrder`** [#1 offene Erweiterung in `docs/kundenbestellungen.md`]: optionales
  `contactId` + wiederverwendbares `ContactPickerField` (`lib/widgets/`) liest In-Memory-`ContactProvider`.
- **Dublettenerkennung** [Übernahme: AllTec `ContactMergeService.findDuplicates`]: reine Funktion nach
  `lib/core/contact_dedup.dart` (Bigramm-Jaccard), „Möglicherweise doppelt"-Hinweis im Anlegen-Sheet.
- **Kontakte-CSV-Import** [Übernahme: AllTec `ContactCsvService.import`]: reiner `;`+BOM-Parser, zeilenweise Fehler.
- **`CustomerOrderScreen` auf `ui/`-Kit angleichen** [Verbesserung]: rohes Material → Shared-Widgets,
  **Umlaute reparieren** („Laeden/faellig" → korrekt); datei-private Reuse-Widgets nach `lib/widgets/` heben.

### M5 — Geteilte Primitive + Governance (Audit fest) · [P2]
- **`lib/core/money.dart`** [Übernahme]: getestetes Cent-Helfer-Objekt (`formatEuro()`, `Money.parse`).
- **`WorkTimePdfTheme` + Berichte-Hub** [Übernahme: AllTec `AzavPdfTheme`]: `PdfColor`-Tokens + Widget-Factories.
- **Leichter Audit-Trail (fest eingeplant)** [Übernahme: AllTec `AuditLogEntry`, **ohne** Hash-Chain]:
  Append-only „wer/wann/was" für Lohn-/Preis-/Bestands-/Kontakt-Mutationen, dual-serialisiert unter
  `organizations/{orgId}/auditLog`, clientseitig via `AuditProvider`, in SharedPreferences gespiegelt, `isAdmin`-Viewer.
- **Minijob/Mindestlohn/AG-Kosten-Korrekturen** [Verbesserung]: Mindestlohn-Warnung, Minijob-AG-Aufschlüsselung,
  AG-SV als markierte Schätzung auch ohne `PayrollRecord`.

### M6 — Tests + Doku-Hygiene · [P2]
- Widget-Tests für `inventory_screen`/`purchase_order_screens`/`customer_order_screen`; billige Personal-Logik-Fälle.
- **CLAUDE.md Provider-Kette aktualisieren** (FeatureFlag/Inventory/Contact/Personal) + `updateSession`-Boilerplate extrahieren.

### M7 — Tiefere Retail-Features · [P2/P3]
- **Standort-übergreifender Bestand + Umlagerung** [Übernahme: AllTec `MovementType.transfer`]: paarige
  Buchung Abgang@A + Eingang@B in einer Transaktion, über den M0.2-Guard abgesichert.
- **Bestellpositionen ↔ Artikel** [Verbesserung]: Produkt-Picker (`productId/sku` existieren), optional
  Bestand bei „abgeholt" dekrementieren.
- **Zielbestand/Lieferanten-Felder/Kontakt-Aktivitäten-Cluster** (kleine additive Felder).
- **Serien-Schicht-Bearbeitung** „Nur diesen / Diesen und folgende / Alle" [Übernahme: AllTec `SeriesUpdateMode`].
- **iCal-Export** [Übernahme: AllTec `ical_schedule_export.dart`], In-App-PDF-Vorschau [AllTec `PdfActions`].
- **`PayrollRecord`-Status** (Offen→Geprüft→Freigegeben) + optionales **Stundenkonto** (Soll/Ist/Saldo).

---

## 4. Governance — Ausblick (nicht jetzt bauen, Auslöser „erst wenn nötig")

Schlanke, rein clientseitige Optionen — bewusst aufgeschoben, **kein** Server-/KMS-/4-Augen-Aufwand:
- **DSGVO Art. 15/17** [Übernahme: AllTec `DataExportService`/`AnonymizationService`/`RetentionService`]:
  Auskunft + Recht-auf-Löschung (PII anonymisieren, aufbewahrungspflichtige Zeilen behalten) + Aufbewahrungs-Katalog.
  Auslöser: sobald reale DSGVO-Anfrage ansteht.
- **Echtes Rechte-Matrix-Modell** [Übernahme, reduziert]: Ad-hoc-Getter in `UserPermissions` mit Rollen-Defaults
  heben — erst wenn die Grob-Gates wirklich stören (Refactor, kein Feature).
- **Cents in Secure Storage** [Verbesserung]: `flutter_secure_storage` für die Cent-tragenden lokalen Collections.

---

## 5. Verifikation

Nach jedem Meilenstein die Quality-Gates fahren (CLAUDE.md):

```bash
flutter analyze                                   # sauber, keine neuen Warnungen
flutter test                                      # alle Tests grün (inkl. neuer)
flutter run --dart-define=APP_DISABLE_AUTH=true   # Offline-Demo, Login admin@demo.local / demo1234
```

**Wichtig:** Bei jeder Modelländerung alle 6 Serialisierungs-Touchpoints prüfen; `firestore.rules` synchron halten;
keine neuen Composite-Indizes nötig (alle Queries index-frei lösbar).
