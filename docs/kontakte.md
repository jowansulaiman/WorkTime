# Kontakte (Adressbuch)

Modul zur Verwaltung wichtiger Kontakte der beiden Läden (Kunden, Lieferanten,
Geschäftspartner, Behörden, Dienstleister …). Gebaut als eigenständiges,
mandantenfähiges Modul nach dem Vorbild der Warenwirtschaft – inkl. Filter,
Kategorien, Standort-Zuordnung sowie PDF-/CSV-Export.

> Drei Namen, kein Bug: UI-Begriff **„Kontakte"**, Firestore-Collection
> `contacts`, Dart-Typ `Contact`.

---

## 1. Zweck & fachlicher Kontext

Mit der Übernahme der beiden Kieler Läden (**Tabak Börse**, **Strichmännchen**,
zwei Standorte **einer** Organisation) wächst die Zahl externer Ansprechpartner:
Tabak-Großhändler, Pressevertrieb, Getränke-/Service-Dienstleister, das
Hauptzollamt (Tabaksteuer), Steuerberater, Vermieter, Bank/Versicherung sowie
Stamm- und Geschäftskunden mit Sonderbestellungen.

Das Kontakte-Modul ist das zentrale **Adressbuch** dafür: ein durchsuchbares,
filterbares, kategorisiertes Verzeichnis, das organisationsweit gilt und sich
optional pro Laden einschränken lässt. Es ist bewusst **getrennt** vom
`Supplier`-Modell der Warenwirtschaft: Lieferanten dort dienen dem konkreten
Bestellvorgang (Bestell-E-Mail, Lieferzeit, Kundennummer), die `Contact`-Einträge
hier sind das allgemeine, kategorienübergreifende Adressbuch. Ein Großhändler darf
in beiden auftauchen.

---

## 2. Zugriff & Einstieg

- **Navigation:** Eigener **Haupt-Tab „Kontakte"** in der App-Shell
  (Bottom-Navigation bzw. Navigationsschiene auf breiten Layouts). Damit ist das
  Modul – anders als z. B. die Warenwirtschaft, die im Verwaltungs-Menü liegt –
  dauerhaft sichtbar.
- **Sichtbarkeit des Tabs:** an `AppUserProfile.canViewContacts` gekoppelt (jedes
  aktive Mitglied). Fehlt das Recht, erscheint der Tab gar nicht.
- **Eigene Symbolik:** Icon `contacts_outlined` / `contacts`.

| Rolle | Ansehen | Anlegen / Bearbeiten / Löschen |
|---|---|---|
| Admin | ✅ | ✅ |
| Teamleiter / MA mit Schicht-Bearbeitungsrecht | ✅ | ✅ |
| Mitarbeiter | ✅ | ❌ (nur lesen) |

Die UI blendet alle schreibenden Aktionen (FAB „Kontakt", Bearbeiten, Löschen,
Favoriten-Umschalten) aus, wenn `canManageContacts` fehlt – synchron zu den
`firestore.rules` (siehe §10).

---

## 3. Funktionsumfang (UI)

Datei: [`lib/screens/contacts_screen.dart`](../lib/screens/contacts_screen.dart).
Visuelle Sprache: Signal-Teal-Redesign (V2) – Karten, Filter-Chips,
Bottom-Sheets, Design-Tokens (`context.spacing/radii/iconSizes`), `AppStatusBadge`,
`AppMetricCard`, `AppFormField`. Funktioniert auch im V1-Theme (Tokens haben
Fallbacks).

### 3.1 Kopf & Kennzahlen
- `SectionHeader` „Kontakte" mit Breadcrumb und In-Shell-Zurück.
- Drei Kennzahl-Kacheln (`AppMetricCard`): **Aktiv**, **Kunden**, **Lieferanten**
  (= Lieferant + Großhändler).

### 3.2 Suche & Filter
- **Volltextsuche** über Name, Ansprechpartner, E-Mail, Telefon/Mobil, Ort,
  Kunden-/Lieferantennummer und Schlagworte.
- **Kategorie-Filter** (Chips): „Alle" plus je ein Chip pro tatsächlich
  vorhandener Kontaktart mit Anzahl, z. B. `Kunde (3)`.
- **Standort-Filter** (Chips): „Alle Standorte", „Allgemein" (Kontakte ohne
  Laden) sowie ein Chip je Standort (z. B. Tabak Börse / Strichmännchen).
- **Schnell-Umschalter:** „Wichtig" (nur Favoriten), „Archivierte zeigen"
  (inaktive einblenden). Inaktive sind standardmäßig ausgeblendet.
- Eine Ergebniszeile zeigt „X von Y Kontakten" und bietet **„Filter
  zurücksetzen"**.

### 3.3 Liste
- Karten (`AppCard`), je Eintrag: Avatar mit kategoriespezifischem Icon, Name,
  Kategorie-Badge (farbcodiert), optional Standort-Chip, „Archiviert"-Badge,
  Favoriten-Stern sowie eine Zeile mit Ansprechpartner · Telefon · E-Mail.
- **Sortierung:** Favoriten zuerst, danach alphabetisch nach Name.
- Verwalter sehen je Karte ein Kontextmenü (als wichtig markieren · bearbeiten ·
  löschen). Tippen öffnet die Detailansicht.
- Leerzustände: „Noch keine Kontakte" (mit Anlege-Button für Verwalter) bzw.
  „Keine Treffer" (mit Filter-Reset), wenn nur die Filter zu eng sind.

### 3.4 Detail-Sheet
Modales Bottom-Sheet (`showAppBottomSheet` / `AppBottomSheetScaffold`) mit allen
Feldern als Info-Zeilen, Kategorie-Badge, Standort- und Schlagwort-Chips.
Telefon, Mobil, E-Mail, Website, Adresse und USt-IdNr. lassen sich per Tipp in die
**Zwischenablage kopieren** (kein externes Paket nötig). Verwalter haben unten
**Bearbeiten** und **Löschen**.

### 3.5 Anlegen / Bearbeiten
Bottom-Sheet-Formular (`_ContactEditorSheet`) mit Validierung (Name = Pflichtfeld)
für: Name/Firma, Kategorie (Dropdown), Ansprechpartner, Telefon, Mobil, E-Mail,
Website, Straße, PLZ, Ort, USt-IdNr., Kunden-/Lieferantennummer, **Standort**
(Dropdown inkl. „Allgemein"), **Schlagworte** (Komma-getrennt), Notiz sowie zwei
Schalter **„Als wichtig markieren"** und **„Aktiv"**.

### 3.6 FAB & Export
- **FAB „Kontakt"** (nur Verwalter) öffnet das Anlege-Formular. Der schicht-/
  zeitbezogene Shell-FAB ist auf diesem Tab bewusst aus (`showFab: false`); der
  Kontakte-FAB hat einen eigenen `heroTag` (`contacts_add_fab`), um Hero-Tag-
  Kollisionen im Lazy-Tab-Stack zu vermeiden.
- **Export-Button** (Teilen-Icon) im Kopf bietet **PDF** oder **CSV** der aktuell
  **gefilterten** Liste; der aktive Filter wird als Untertitel mitgegeben.

---

## 4. Datenmodell

Datei: [`lib/models/contact.dart`](../lib/models/contact.dart). Reine Datenklasse
ohne Codegen, mit der projektweiten **Zwei-Serialisierungs-Regel**.

### 4.1 `Contact`

| Feld | Typ | Bedeutung |
|---|---|---|
| `id` | `String?` | Firestore-Doc-Id (null beim Anlegen) |
| `orgId` | `String` | Mandant (Pflicht, Partitionsschlüssel) |
| `name` | `String` | Firmen-/Kontaktname (Pflicht, Sortier-/Suchschlüssel) |
| `type` | `ContactType` | Kategorie (siehe 4.2) |
| `contactPerson` | `String?` | Ansprechpartner (Person bei Firmen) |
| `email`, `phone`, `mobile`, `website` | `String?` | Kommunikationswege |
| `street`, `postalCode`, `city` | `String?` | Adresse |
| `taxId` | `String?` | USt-IdNr. / Steuernummer |
| `customerNumber` | `String?` | eigene Kunden-/Lieferantennummer |
| `notes` | `String?` | Freitext |
| `siteId`, `siteName` | `String?` | optionale Standort-Zuordnung (null = „Allgemein") |
| `tags` | `List<String>` | freie Schlagworte zum Filtern |
| `isFavorite` | `bool` | „Wichtig"-Markierung |
| `isActive` | `bool` | aktiv vs. archiviert |
| `createdByUid`, `createdAt`, `updatedAt` | Audit | Anleger & Zeitstempel |

Abgeleitete Getter: `initials` (Avatar), `hasAddress`, `displayAddress`
(„Straße, PLZ Ort"), `primaryPhone` (Festnetz vor Mobil).

**Serialisierung – die zwei nicht austauschbaren Formate:**

| Methoden | Keys | Datum | Verwendung |
|---|---|---|---|
| `toFirestoreMap()` / `fromFirestore(id, map)` | **camelCase** | `Timestamp` / `serverTimestamp` | direkte Firestore-Writes, Fakes in Tests |
| `toMap()` / `fromMap(map)` | **snake_case** | ISO-8601-String | SharedPreferences / Export |

- `toFirestoreMap()` ergänzt `nameLower` (für `orderBy('nameLower')`), trimmt
  Strings und setzt leere Strings auf `null`; `updatedAt` ist immer
  `serverTimestamp()`. `createdAt` setzt erst die Repository-Schicht beim Anlegen.
- `fromFirestore` bekommt die Doc-Id als separates erstes Argument; `fromMap`
  liest `map['id']`.
- `copyWith` besitzt `clearX`-Flags für alle optionalen Felder; **`clearSite`
  leert `siteId` und `siteName` gemeinsam**. Audit-Felder folgen – wie in den
  übrigen Modellen (`Supplier`, `Product`) – bewusst dem `?? this.x`-Muster ohne
  Clear-Flag.

### 4.2 `ContactType` (Kategorien)

Enum mit Erweiterungs-Gettern `value` (stabiler Speicherwert, snake_case),
`label` (deutsche UI-Beschriftung), `shortLabel` (für enge Badges/PDF-Spalten)
und `fromValue` mit Default-Branch (`other`, wirft nie).

| `value` | Label |
|---|---|
| `customer` | Kunde |
| `supplier` | Lieferant |
| `wholesaler` | Großhändler |
| `company` | Unternehmen / Partner |
| `service_provider` | Dienstleister |
| `authority` | Behörde |
| `landlord` | Vermieter |
| `bank_insurance` | Bank / Versicherung |
| `tax_advisor` | Steuerberater |
| `other` | Sonstige |

`ContactTypeX.ordered` (= `ContactType.values`) liefert die stabile Reihenfolge
für Filter-Chips und die Gruppierung im PDF.

---

## 5. Architektur & Datenzugriff

```
ContactsScreen ──watch──> ContactProvider ──> ContactRepository (Interface)
                                                     │
                                       FirestoreContactRepository (Cloud)
                                                     │
                            DatabaseService.loadLocalContacts/saveLocalContacts (lokal)
```

### 5.1 Repository-Schicht (DIP)
- [`lib/repositories/contact_repository.dart`](../lib/repositories/contact_repository.dart) –
  Abstraktion: `watchContacts`, `saveContact`, `deleteContact`.
- [`lib/repositories/firestore_contact_repository.dart`](../lib/repositories/firestore_contact_repository.dart) –
  einzige Stelle mit Kontakt-Cloud-Zugriff. Collection
  `organizations/{orgId}/contacts`, gelesen als vollständiger, nach `nameLower`
  sortierter Stream; Schreiben via `set(..., merge:true)` und `createdAt` nur beim
  Anlegen.
- In [`firestore_service.dart`](../lib/services/firestore_service.dart) als
  `late final contactRepository`-Getter exponiert (analog `inventoryRepository`).

### 5.2 Provider
[`lib/providers/contact_provider.dart`](../lib/providers/contact_provider.dart),
Struktur identisch zur `InventoryProvider`. Exponiert `contacts`, `loading`,
`errorMessage` sowie abgeleitete Sichten (`activeContacts`, `favorites`,
`countsByType`, `tagsInUse`, `contactById`). CRUD: `saveContact`, `deleteContact`,
`toggleFavorite`, `setActive`.

> **Wichtig – Cloud-Repo lazy auflösen:** Der Provider speichert nur die
> `FirestoreService`-Referenz und einen optionalen injizierten Repo; das echte
> Cloud-Repository wird **erst im Getter** `_contacts` aufgelöst, nie im
> Konstruktor. Andernfalls würde `FirestoreService.contactRepository`
> (`late final`) sofort `FirebaseFirestore.instance` auswerten und im
> `APP_DISABLE_AUTH=true`/Web-Modus (kein Firebase) schon bei der
> Provider-Konstruktion crashen → „fast alle Seiten rot". Im Local-Modus wird der
> Getter nie aufgerufen.

### 5.3 Drei Speichermodi
Wie im Rest der App über den `StorageModeProvider` gesteuert:

- **local:** nur SharedPreferences (In-Memory-Liste + Persistenz).
- **cloud:** nur Firestore-Stream.
- **hybrid (Default):** Cloud-Reads; bei Schreibfehler **lokaler Fallback** statt
  Datenverlust. Muster über `_tryFirestore(label, action)`: Cloud-Erfolg → fertig;
  Hybrid-Fehler → `false` (lokaler Upsert + Persistenz + Notify); Cloud-only →
  Fehler durchreichen. Alle Notify-Aufrufe laufen über `_safeNotify()` (prüft
  `_disposed`).

### 5.4 Standort-Zuordnung (org-weit + optional)
Kontakte gelten **organisationsweit**. `siteId`/`siteName` ist eine **optionale**
Markierung (`null` = „Allgemein / beide Läden"). Die Standort-Liste für Picker und
Filter kommt aus dem `TeamProvider` (`sites`). Filter-Semantik im Screen:
`null` = alle, Sentinel `__general__` = ohne Laden, sonst exakter `siteId`-Treffer.

---

## 6. Provider-Verdrahtung (`main.dart`)

`ContactProvider` hängt nur an **Auth** und **StorageMode** und wird als
`ChangeNotifierProxyProvider2` **nach** `InventoryProvider` (und vor den
abhängigen Providern) in die Kette eingefügt:

```dart
ChangeNotifierProxyProvider2<AuthProvider, StorageModeProvider, ContactProvider>(
  create: (_) => ContactProvider(firestoreService: firestoreService),
  update: (_, auth, storage, provider) {
    provider ??= ContactProvider(firestoreService: firestoreService);
    _dispatchProviderUpdate(
      provider.updateSession(
        auth.profile,
        localStorageOnly: storage.isLocalOnly,
        hybridStorageEnabled: storage.isHybrid,
      ),
      'ContactProvider.updateSession',
      onError: provider.surfaceSessionError,
    );
    return provider;
  },
),
```

`updateSession` ist fire-and-forget (Fehler über `surfaceSessionError` →
`errorMessage`), reagiert auf Wechsel von Nutzer **und** Speichermodus und
startet/beendet das Cloud-Abo bzw. lädt lokal.

---

## 7. Lokale Persistenz

In [`lib/services/database_service.dart`](../lib/services/database_service.dart):

- Collection-Key `contacts`, registriert in `_orgScopedCollectionKeys` (**org-**,
  nicht user-skopiert).
- `loadLocalContacts` / `saveLocalContacts` (sortiert nach Name), Round-Trip über
  `Contact.toMap` / `fromMap`.
- Bewusst **ohne** Legacy-Migration (neue Collection, kein Altbestand) – analog
  Warenwirtschaft und Personal.

---

## 8. Export (PDF & CSV)

UI: Export-Menü im Screen-Kopf (PDF / CSV) auf die **gefilterte** Liste, mit
Lade-/Fehler-Snackbar.

- **PDF** – [`PdfService.generateContactListReport`](../lib/services/pdf_service.dart):
  A4, NotoSans-Fonts, Kopf mit Filter-Untertitel, drei Kennzahl-Karten (Kontakte /
  Kategorien / Wichtig), danach **gruppiert nach Kontaktart** (stabile Reihenfolge
  `ContactTypeX.ordered`) je eine Tabelle (Name · Ansprechpartner · Telefon ·
  E-Mail · Ort · Standort), Favoriten mit „★". Wiederverwendet die geteilten
  Helfer `_summaryCard` / `_cell` / `_buildFooter`. Der geteilte `_buildFooter`
  hat dafür einen optionalen `label`-Parameter (Default „Arbeitszeiterfassung")
  bekommen – die Kontaktliste setzt **„Kontaktliste"**.
- **CSV** – [`ExportService.buildContactsCsv`](../lib/services/export_service.dart):
  UTF-8-**BOM**, `;`-Trennzeichen (deutsches Excel), RFC-4180-Escaping über
  `_escapeCsv`. Spalten: Name; Kategorie; Ansprechpartner; Telefon; Mobil; E-Mail;
  Website; Straße; PLZ; Ort; USt-IdNr.; Kunden-/Lief.-Nr.; Standort; Schlagworte;
  Wichtig; Aktiv; Notiz.
- Dateinamen: `kontakte-JJJJ-MM-TT.{pdf,csv}` (`DateFormat('yyyy-MM-dd','de_DE')`).
- Download/Teilen über die plattformneutrale `download_service`-Abstraktion
  (Share-Sheet mobil/Desktop, Blob-Download Web).

---

## 9. Berechtigungen (`AppUserProfile`)

In [`lib/models/app_user.dart`](../lib/models/app_user.dart):

```dart
/// Kontakte ansehen darf jedes aktive Mitglied.
bool get canViewContacts => isActive;

/// Kontakte verwalten dürfen Admins und Schichtleiter (analog Warenwirtschaft).
bool get canManageContacts => isActive && (isAdmin || canManageShifts);
```

Diese Getter gaten **sowohl die UI** (Tab-Sichtbarkeit, FAB, Bearbeiten/Löschen)
**als auch** – sinngemäß gespiegelt – die `firestore.rules`.

---

## 10. Firestore – Regeln, Indizes, Sicherheit

`firestore.rules` (org-skopiert unter `organizations/{orgId}/contacts`):

```
function canManageContacts() {
  return isAdmin() || canManageShifts();
}

match /contacts/{contactId} {
  allow read: if sameOrg(orgId);
  allow create, update: if sameOrg(orgId)
      && canManageContacts()
      && request.resource.data.orgId == orgId;
  allow delete: if sameOrg(orgId) && canManageContacts();
}
```

- **Lesen:** alle aktiven Mitglieder derselben Org (`sameOrg`).
- **Schreiben/Löschen:** nur Verwalter (`canManageContacts()` = Admin oder
  Schichtleiter). Bei create/update muss `data.orgId == orgId` gelten →
  Schutz vor org-übergreifenden Writes (Muster wie `suppliers`/`customerOrders`).
- **Keine Cloud Function nötig:** Kontakte sind **direkte** Client-Writes
  (camelCase `toFirestoreMap`), wie Teams/Lieferanten – nur Schichten und
  Zeiteinträge laufen über Callables.
- **Kein Composite-Index nötig:** Die Liste nutzt nur `orderBy('nameLower')`
  (Single-Field → automatisch indexiert). Erst ein zusätzliches
  `where(...).orderBy(...)` würde einen Index in `firestore.indexes.json`
  erfordern.

> Die `canManageContacts()`-Regel muss mit dem Dart-Getter `canManageContacts`
> synchron bleiben (gleiche Bedeutung: Admin oder Schichtleiter).

---

## 11. Demodaten (Offline-Modus)

[`LocalDemoData.contactsForOrg`](../lib/core/local_demo_data.dart) seedet im
lokalen/Offline-Modus für Demo-Nutzer einmalig sieben realistische Kieler
Kontakte (Tabak-Großhändler, Pressevertrieb, Getränke-Service mit Standortbezug,
Hauptzollamt, Steuerkanzlei, Hausverwaltung, Stammkunde) – inkl. Favoriten,
Schlagworten und Standort-Markierungen. Das Seeding greift nur, wenn der lokale
Bestand leer ist; echte lokale Daten bleiben unberührt.

---

## 12. Tests

Vier neue Test-Dateien, alle offline (`fake_cloud_firestore`, SharedPreferences-
Mock), deutsch:

| Datei | Inhalt |
|---|---|
| [`test/contact_model_test.dart`](../test/contact_model_test.dart) | Enum `value/fromValue` (inkl. Default), `toMap/fromMap`- und `fromFirestore`-Round-Trip, `nameLower`/Trim, `copyWith`-Clear-Flags (`clearSite`), abgeleitete Getter |
| [`test/firestore_contact_repository_test.dart`](../test/firestore_contact_repository_test.dart) | Anlegen (mit `nameLower`/`orgId`), nach `nameLower` sortierter Stream, Merge-Update, Löschen |
| [`test/contact_provider_test.dart`](../test/contact_provider_test.dart) | Lokal: IDs/Sortierung, Persistenz über „Neustart", `toggleFavorite`, Löschen, `countsByType`, Reset; Hybrid-Offline-Fallback; Cloud-Load und Stream-`onError` |
| [`test/contacts_screen_test.dart`](../test/contacts_screen_test.dart) | Widget: Liste + FAB für Verwalter, kein FAB für Mitarbeiter, Kategorie-Filter, Suche |
| [`test/export_service_contacts_test.dart`](../test/export_service_contacts_test.dart) | CSV: BOM, Kopfzeile, `;`-Escaping, Standort/Favorit, Filter-Label |

Quality Gates: `flutter analyze` ohne Befunde, gesamte `flutter test`-Suite grün
(inkl. dieser Fälle).

> Test-Stolperstein: Die Demo-E-Mails (`admin@demo.local`, `peter@example.com`)
> lösen `_maybeSeedLocalDemo` aus → in Tests bewusst **Nicht-Demo-Identitäten**
> verwenden, sonst sind die Zählungen nicht deterministisch.

---

## 13. Bewusste Entscheidungen

- **Eigener Haupt-Tab** statt Verwaltungs-Menü – Kontakte sind im Alltag häufig
  und sollen ein Tippen entfernt sein (Nutzerentscheidung).
- **Org-weit mit optionalem Standort** statt strenger Pro-Laden-Trennung – ein
  Lieferant/Steuerberater gilt für beide Läden; Standort ist nur ein Filter.
- **Getrennt von `Supplier`** – das Adressbuch ist kategorienübergreifend; eine
  Verschmelzung würde die schlanke Bestelllogik der Warenwirtschaft verwässern.
- **Cloud-Repo lazy** – verhindert den disableAuth/Web-Crash (siehe §5.2).
- **Audit-Felder ohne Clear-Flag** in `copyWith` – konsistent zu allen anderen
  Modellen; sie werden nie aktiv genullt.
- **Clipboard statt `url_launcher`** im Detail-Sheet – kein neues Paket, keine
  Plattform-Sonderfälle.

---

## 14. Betroffene Dateien (Übersicht)

**Neu**
- `lib/models/contact.dart`
- `lib/repositories/contact_repository.dart`
- `lib/repositories/firestore_contact_repository.dart`
- `lib/providers/contact_provider.dart`
- `lib/screens/contacts_screen.dart`
- `test/contact_model_test.dart`, `test/firestore_contact_repository_test.dart`,
  `test/contact_provider_test.dart`, `test/contacts_screen_test.dart`,
  `test/export_service_contacts_test.dart`
- `docs/kontakte.md` (dieses Dokument)

**Geändert**
- `lib/main.dart` – `ContactProvider` in die Provider-Kette
- `lib/services/firestore_service.dart` – `contactRepository`-Getter
- `lib/services/database_service.dart` – Key `contacts`, `load/saveLocalContacts`
- `lib/models/app_user.dart` – `canViewContacts` / `canManageContacts`
- `lib/services/pdf_service.dart` – `generateContactListReport`, parametrisierter
  `_buildFooter`
- `lib/services/export_service.dart` – `exportContactsPdf/Csv`, `buildContactsCsv`
- `lib/core/local_demo_data.dart` – `contactsForOrg`
- `lib/screens/home_screen.dart` – Shell-Tab `kontakte`
- `firestore.rules` – `canManageContacts()` + `/contacts`-Block

---

## 15. Lokal ausprobieren

```bash
flutter pub get
flutter run --dart-define=APP_DISABLE_AUTH=true
# Login z. B. admin@demo.local / demo1234
# Unten/seitlich den Tab „Kontakte" öffnen – die Demo-Kontakte sind vorbefüllt.
```

Suche, Kategorie-/Standort-Filter, Anlegen/Bearbeiten und PDF-/CSV-Export lassen
sich direkt offline testen.

---

## 16. Deployment-Hinweise

```bash
firebase deploy --only firestore:rules
```

Ein Index-Deploy ist **nicht** nötig (keine neuen Composite-Indizes). Beim
Erweitern um gefilterte Queries (`where + orderBy`) einen passenden Index in
`firestore.indexes.json` ergänzen.

---

## 17. Mögliche Erweiterungen (offen)

- Direktwahl/E-Mail/Karten-Links (würde `url_launcher` einführen).
- Verknüpfung Kontakt ↔ Kundenbestellung / Lieferant (Warenwirtschaft).
- Mehrere Standorte je Kontakt statt eines optionalen Standorts.
- Import (CSV/vCard) als Gegenstück zum Export.
- Letzter-Kontakt-/Aktivitätsverlauf je Eintrag.
