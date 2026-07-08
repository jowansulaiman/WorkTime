# Kontaktbereich — UI/Tabs + Datenmodell genau 1:1 wie AllTec

**Stand:** 2026-07-07 · **Status:** **M1–M12 CODE-FERTIG+VERIFIZIERT** (kompletter Kontaktbereich 1:1 wie AllTec) · **Priorität:** hoch
> **Verifikation:** `flutter analyze` clean (nur 2 vorbestehende Baseline-Warnungen), **volle Suite `flutter test` = 1668 Tests grün**. Uncommitted.
> **Deploy nötig vor Cloud-Nutzung (extern/Blaze):** (1) `firebase deploy --only firestore:rules` — neuer Block `contactOrganizations` (M9). (2) `firebase deploy --only storage` — neue Avatar-Regel `organizations/{orgId}/contacts/{contactId}/{fileName}` (M8, read=aktives Mitglied, write=admin/teamlead, <5 MB image/*). Adressen/Bank/Kanäle/Consents sind **eingebettet** (kein Deploy). Kein neuer Composite-Index nötig.
> **Bewusste Abweichungen von AllTecs Storage (WorkTime-Konventionen):** Consents **eingebettet** statt eigene Collection (Spark-frugal wie Activities). **Strukturierte Tags** (ContactTag mit Farbe/Gruppe) NICHT übernommen — `List<String>`-Schlagworte bleiben (funktional äquivalent für Filter/Suche/Anzeige; hohe Ripple-Gefahr auf CSV/PDF/Editor bei minimalem Mehrwert). GdB/DSGVO-Art.9-Sonderkategorien wie beim Personal weggelassen.
**Auftrag (Betreiber):** „Die Kontakte bzw. der Kontaktbereich soll auch 1:1 wie in AllTec sein." (analog zum bereits umgesetzten Personalbereich, siehe `plan/personal-alltec-1zu1.md`).

AllTec (`/Users/jowan/Documents/dev/AllTec`, `lib/features/crm/…`, Schwester-App desselben Entwicklers, Clean Architecture/bloc/GoRouter/freezed) hat das Muster **Liste → Kontakt-Detail mit 7 Tabs**. Wird in WorkTime **per Hand** in dessen Konventionen re-implementiert (provider + go_router, Zwei-Serialisierung von Hand, Material 3, AllTec-Farbpalette bereits app-weit, Deutsch-only, Spark-frugal/eingebettete Arrays statt Sub-Collections). **Kein** bloc/Freezed/GoRouter-Transplant.

## Betreiber-Entscheidungen (2026-07-04, fixiert)

1. **Volle Feld-Parität** (wie beim Personalbereich). Das `Contact`-Datenmodell wird auf AllTec-Niveau ausgebaut: Person/Firma-Split, 15 Kategorien, Status, Mehrfach-Adressen, Ansprechpartner-Liste (Firma↔Person), Bankverbindungen, typisierte Kommunikationskanäle, strukturierte Tags. Die exakten 7 AllTec-Tabs.
2. **Alle drei optionalen Bausteine JA:** (a) **Einwilligungen (DSGVO)** — eigenes Model + Collection + Rules + Grant/Withdraw. (b) **Kontakt-Organisationen** — eigene Liste + Model + Collection (Agentur/Jobcenter/Behörde; in AllTec eigenständiges Adressbuch, NICHT mit Contacts verknüpft). (c) **Avatar-Upload** — Firebase Storage + `avatarUrl`.
3. **Bestehende WorkTime-Besonderheiten bleiben erhalten** (additiv, nicht destruktiv): `siteId`/`siteName`-Zwei-Läden-Skopierung, `isFavorite`, die eingebettete `activities`-Historie (in AllTec hat der Detail-Screen KEINEN Aktivitäten-Tab → WorkTime-Historie wird **erhaltend** in der Übersicht als „Letzte Aktivitäten"-Sektion gezeigt, analog zur „erhaltenden Verlagerung" der Personal-Aggregat-Tabs).

## Ziel-IA (AllTec 1:1)

```
/kontakte (Shell-Tab, canViewContacts = jedes aktive Mitglied)
  └─ Kontaktliste: SegmentedButton Person/Firma + Kategorie-/Status-Filter + Suche + Karten
        └─ Karte-Tap → context.push('/kontakte/{id}')
  └─ AppBar-Aktion „Organisationen" → Organisationen-Liste (eigenes Adressbuch)
/kontakte/:id  (NEU, canViewContacts, Top-Level deep-linkbar)
  └─ ContactDetailScreen: BreadcrumbAppBar + Kopf-VCard (Avatar + Kategorie-/Status-Chips + Tags)
       + scrollbare TabBar (Icon+Text) mit EXAKT 7 Tabs (AllTec-Reihenfolge):
       Übersicht · Adressen · Kommunikation · Ansprechpartner · Einwilligungen · Bank · Notizen
```

**Berechtigung:** Lesen = `canViewContacts` (= aktiver Nutzer; NICHT admin-only wie Personal!). Verwaltungs-Aktionen (Bearbeiten/Löschen/Consent/Beziehung/Bank/Avatar) = `canManageContacts` (Admin + Schichtleiter) — im Screen gegatet, nicht im URL-Gate. Deckt sich mit `firestore.rules` (`contacts read: sameOrg`).

Editoren bleiben imperativ (`showModalBottomSheet`/`showDialog`). Der Detail-Screen ist die einzige neue URL. Der reiche „Bearbeiten"-Editor (AllTec `ContactCreateForm`) pflegt Stammdaten/Adresse/Kanäle/Notizen; Sub-Objekte (Adressen/Bank/Tags/Ansprechpartner/Consents) über eigene Dialoge pro Tab.

## AllTec-Tab → WorkTime-Datenquelle (belegt via Analyse-Workflow, wf_478dc94b-8f4)

| Tab (AllTec) | Icon | Inhalt | WorkTime heute | Für 1:1 zu tun |
|---|---|---|---|---|
| Übersicht | info_outline | VCard + Geschäftsdaten + Hauptadresse + Kommunikation-Quickview | 🟡 flach | + Geschäftsdaten-Felder, VCard, (+ erhaltene „Letzte Aktivitäten") |
| Adressen | place_outlined | Hauptadresse + Zusatzadressen (Rechnung/Liefer/NL) | ❌ 1 flache Adresse | `ContactAddress`-Sub-Model + `addresses[]` + AddressDialog |
| Kommunikation | phone_outlined | typisierte Kanäle gruppiert nach Kontext, Primär, Kopieren | ❌ flache email/phone/mobile/website | `CommunicationChannel`-Sub-Model + `channels[]` + gruppierte Ansicht |
| Ansprechpartner | people_outline | Firma↔Person-Beziehungen, Rolle, Hauptkontakt, parentCompany | ❌ 1 String `contactPerson` | `ContactPerson`-Sub-Model + `contactPersons[]` + `parentContactId` + Dialoge |
| Einwilligungen | shield_outlined | DSGVO-Consents (Datenverarbeitung/E-Mail/Telefon/Weitergabe) | ❌ fehlt | `ContactConsent`-Model + Collection + Rules + grant/withdraw |
| Bank | account_balance_outlined | Bankverbindungen (IBAN/BIC/Bank/Inhaber/aktiv) | ❌ fehlt | `BankAccount`-Sub-Model + `bankAccounts[]` + BankAccountDialog |
| Notizen | notes | interne Freitext-Notizen + Tags-Chips | 🟡 notes + `List<String>` tags | `ContactTag`-Sub-Model (Label/Farbe/Gruppe) + TagDialog |

## Modell-Parität (Kern der Arbeit)

**Neue eingebettete Sub-Modelle am `Contact`** (je volle Zwei-Serialisierung `toFirestoreMap`/`fromFirestoreMap` + `toMap`/`fromMap`, eingebettet als Arrays wie `ContactActivity` — Spark-frugal, KEINE Sub-Collections):
- `ContactAddress` (type: AddressType, label?, street/houseNumber/zip/city/country/addressExtra/postbox/postboxZip, placeId/lat/long?).
- `CommunicationChannel` (type: ChannelType, value, context: CommunicationContext, label?, availability?, isPrimary).
- `ContactPerson` (id, personContactId, role?, isPrimary) — **Referenz** auf einen Person-Kontakt, keine eingebetteten Personendaten.
- `BankAccount` (id, iban, bic?, bankName?, accountHolder?, deactivated).
- `ContactTag` (id, label, color?, group?) — ersetzt `List<String>` (Migration: alte String-Tags → `ContactTag(label)`).

**Contact-Feld-Ausbau:** `contactKind` (Enum `{person, company}`, getrennt vom bestehenden `ContactType`/Kategorie), person-Felder (firstName/lastName/title/gender/birthday/position/department), firma-Felder (companyName/legalName/ustId/registrationNumber/companyAnniversary), Nummern (debitorNumber/creditorNumber; `customerNumber`/`taxId` existieren), `status` (Enum `ContactStatus {aktiv, inaktiv, gesperrt}`), `deactivated`/`blacklisted` (bool), `avatarUrl`, `customerSince`, `parentContactId`, `alias`, Geo (placeId/lat/long) an der Hauptadresse. Listen: `addresses[]`, `channels[]`, `contactPersons[]`, `bankAccounts[]`, neue `tags: List<ContactTag>`.

**`name`-Migration (heikel):** `name` bleibt Pflicht + Sortier-/Suchschlüssel (+ `nameLower`). Bei gesetzten Struktur-Feldern wird `name` beim Speichern abgeleitet (`alias ?? companyName ?? '$firstName $lastName'`), sonst frei. So bleiben CSV/PDF/Picker/Liste rückwärtskompatibel.

**Neue Enums** (je `.value`-Getter snake_case + `fromValue`-Default + deutsches `label`): `ContactKind`, `ContactStatus`, `AddressType`, `ChannelType`, `CommunicationContext`, `ConsentType`, `OrganizationType`, `Gender` (falls nicht vorhanden). Bestehender `ContactType` (Kunde/Lieferant/… 10 Werte) bleibt als **Kategorie** (⇒ deckt AllTecs `ContactCategory` funktional; NICHT gegen AllTecs 15 tauschen, um WorkTime-Daten/CSV/PDF-Gruppierung zu erhalten — Mapping dokumentieren).

**Neue Entities/Collections** (echte Collections, org-skopiert, Rules + lokale Persistenz-Registrierung):
- `ContactConsent` → `organizations/{orgId}/contactConsents/{id}` (Feld `contactId`). Query `where contactId + orderBy grantedAt desc` → **Composite-Index** nötig. Kaskade: bei `deleteContact` zugehörige Consents mitlöschen.
- `ContactOrganization` → `organizations/{orgId}/contactOrganizations/{id}` (name, type: OrganizationType, city?, website?, isActive).

**Avatar:** `avatarUrl` am Contact; Upload nach Firebase Storage `organizations/{orgId}/contacts/{contactId}/avatar.{ext}` (Storage-Rules + Web/Mobile-Zweig; Personalbereich hat Storage bereits eingeführt).

## Provider-/Repository-Surface (zu ergänzen)

`ContactRepository` heute 3 Methoden (`watchContacts`/`saveContact`/`deleteContact`). Neu:
- Sub-Objekt-Mutationen (Adresse/Person/Bank/Kanal/Tag) laufen **eingebettet über `saveContact(copyWith(...))`** → reine Provider-Convenience-Mutatoren, KEIN neuer Firestore-Pfad.
- **Consent-Collection:** `watchConsents`/`grantConsent`/`withdrawConsent` (echte Repo-Methoden + Rules + Index).
- **Organizations-Collection:** `watchOrganizations`/`saveOrganization`/`deleteOrganization` (echte Repo-Methoden + Rules).
- **Avatar-Storage:** `uploadContactAvatar`/`deleteContactAvatar` (neuer Storage-Seam).
- **Merge:** `mergeContacts(primary, duplicate)` — portiere AllTecs `ContactMergeService.merge` (heute nur `ContactDedup.findDuplicates`, Erkennung).
- **deleteContact-Kaskade:** zugehörige Consents mitlöschen (WriteBatch/Best-effort).
- Jeder neue fachliche Mutator → `_audit?.call(...)` nur auf Erfolgs-Pfad, deutsche Summary, `entityType:'Kontakt'` (bzw. `Kontakt-Einwilligung`/`Kontakt-Organisation`).

## Reuse (vorhanden, aus Personal-Arbeit) vs. neu

**Vorhanden (direkt nutzbar):** `BreadcrumbAppBar`/`BreadcrumbItem`, `AppSectionCard`, `AppStatusBadge`/`AppStatusTone`, `AppMetricCard`, `SummaryCardRow`/`SummaryCardItem`, `InfoRow` (aus Personal gehoben), `EmptyState`, `AppSearchField`, `AppFilterChip`, `AppConfirmDialog`, `showAppBottomSheet`/`AppBottomSheetScaffold`, `ExpandableFab`, appColors/spacing/radii. Template: `lib/screens/personal/employee_detail_screen.dart` + `lib/screens/personal/tabs/*`.

**Neu bauen:** `ContactDetailScreen` (7-Tab, uid-basiert) + 7 Tab-Widgets unter `lib/screens/contacts/tabs/`; 5 neue Sub-Model-Klassen + 2 neue Entities; Editor-Sheets (reicher „Bearbeiten"-Editor + AddressDialog/BankAccountDialog/ConsentDialog/TagDialog/ContactPersonDialog); `AvatarUploadWidget`; Organisationen-Liste + Dialog; `mergeContacts`. File-private Bausteine aus `contacts_screen.dart` (`_ContactEditorSheet`, `_DetailRow`, `_typeIcon`/`_typeTone`, `_activityIcon`/`_formatActivityDate`) nach `lib/screens/contacts/` bzw. `lib/widgets/` heben (heben statt kopieren).

## Sicherheit / kritische Kopplungen

- **Deep-Link-Gate (M1):** `/kontakte/{id}` matcht keinen exakten `case` in `RoutePermissions.isLocationAllowed` → fiele auf `default:true`. Fix: `if (loc.startsWith('/kontakte/')) return p?.canViewContacts ?? false;` VOR dem `switch` (Kopplung #7). In `firestore.rules` (contacts read=sameOrg) bereits gedeckt.
- **Path-Parameter:** explizite `GoRoute(path:'/kontakte/:id', parentNavigatorKey: rootNavigatorKey, builder: liest state.pathParameters['id'])` — NICHT `_sectionRoute` (reicht keine `:id` durch).
- **Jedes neue Model-Feld = 6 Stellen** (`toFirestoreMap`/`fromFirestore`/`toMap`/`fromMap`/`copyWith`+`clearX`/Listen-Handling) + Round-Trip-Test (Kopplung #1). Contacts schreiben **direkt** (kein Callable) → keine `functions/index.js`-Änderung.
- **Neue Collections** (ContactConsent, ContactOrganization) = Kopplung #5: local-Key + `_orgScopedCollectionKeys` in `DatabaseService` + `firestore.rules` `sameOrg` (+ Consent-Composite-Index in `firestore.indexes.json`).
- **Neue Enums** = Kopplung #3: `.value`/`fromValue`-Default + deutsches Label.
- **Storage-Rules** für Avatar-Pfad (neu; ggf. `storage.rules` anlegen/erweitern).
- **Drei Speichermodi:** neue Consents/Organizations auch local/hybrid persistieren; Sub-Objekt-Arrays fahren über `saveContact` (bereits Modus-bewusst).

## Meilensteine (kleinste offline-testbare Schritte)

- **M1 — Routing + Sicherheit + Detail-Gerüst. ✅ FERTIG (04.07.).** `AppRoutes.contactDetail='/kontakte/:id'` + `contactDetailPath` (`shell_tab.dart`); explizite `GoRoute` mit `rootNavigatorKey` (`app_router.dart`); `/kontakte/`-Prefix-Guard = `canViewContacts` VOR dem switch (`route_permissions.dart`); `ContactDetailScreen` (`lib/screens/contacts/contact_detail_screen.dart`, DefaultTabController 7, BreadcrumbAppBar, Kopf-VCard, scrollbare TabBar, In-Screen-Gate canViewContacts, Loading/Not-Found); Listen-Karte → `_openContact` → `context.push` (Fallback Sheet für id-lose Kontakte, altes `_openDetail`-Sheet bleibt erhalten). Tabs über heutiges Modell gefüllt (Übersicht/Adressen/Kommunikation/Ansprechpartner/Notizen mit realen Daten; Einwilligungen/Bank als Platzhalter). Tests: `route_permissions_test` (+1 Kontakt-Deep-Link-Case), `contact_detail_screen_test` (7 Tabs + Gate + Übersicht-Daten). `flutter analyze` clean (nur 2 Baseline-Warnungen).
- **M2 — Kern-Sub-Modelle. ✅ FERTIG (04.07.).** Neue Datei `lib/models/contact_details.dart`: `ContactAddress`, `CommunicationChannel`, `ContactPerson`, `BankAccount` + Enums `AddressType`/`ChannelType`/`CommunicationContext` — je volle Zwei-Serialisierung. In `Contact` eingebettet als `List<...>` (addresses/channels/contactPersons/bankAccounts) über alle 6 Stellen (Konstruktor/fromFirestore/fromMap/toFirestoreMap/toMap/copyWith + Parse-Helfer). **Rein additiv** — Hauptadress-Scalars + flache email/phone/… + `List<String> tags` bleiben unangetastet (kein Bruch von CSV/PDF/Picker). `tags`→`ContactTag`-Migration bewusst nach M11 verschoben. Round-Trip-Tests `test/contact_details_test.dart`. *(ContactTag-Sub-Model noch offen → M11.)*
- **M3 — Person/Firma-Split + Status. ✅ FERTIG (04.07.).** `Contact` +19 Felder: `kind` (`ContactKind{person,company}`, Default company), `status` (`ContactStatus`), `blacklisted`, `alias`, person (firstName/lastName/title/gender(`Gender`)/birthday/position/department), firma (companyName/legalName/registrationNumber/companyAnniversary), debitor/creditorNumber, avatarUrl, customerSince — alle 6 Stellen + 15 clearX-Flags. 3 Datumsfelder via `FirestoreDateParser`. `displayName`-Getter (alias→Firma→Person→`name`-Fallback). **Rückwärtskompatibel** (alte Kontakte → sinnvolle Defaults). Bestehender `ContactType` bleibt Kategorie (kein 15-Werte-Tausch). Round-Trip-/Default-/clearX-Tests. *Modell-Fundament damit vollständig; M4 zeigt die Daten.*
- **M4 — Tabs Übersicht/Adressen/Kommunikation/Bank (read). ✅ FERTIG (06.07.).** `contact_detail_screen.dart` neu: VCard mit `displayName` + Avatar (avatarUrl/Initialen) + Chip-Reihe (Person/Firma · Status · Blacklist · Archiviert · Favorit); Übersicht = Stammdaten (Person/Firma-abhängig) + Geschäftsdaten (Kundennr./Debitor/Kreditor/USt/HR/Kunde-seit) + Zuordnung + Kommunikation-Quickview + Hauptadresse + Letzte Aktivitäten; Adressen = Hauptadresse (flach) + `contact.addresses` typisiert; Kommunikation = `_effectiveChannels` (strukturiert sonst aus flachen Feldern) gruppiert nach Kontext + Primär-Badge + Kopieren; Bank = `contact.bankAccounts`. Status-Farben via `AppStatusTone`. Tests erweitert (VCard-Chips/Person-Stammdaten, Bank+strukturierte Adresse). *Sichtbar wird die Parität voll, sobald der Editor (M5) die Felder befüllt.*
- **M5a — Reicher „Bearbeiten"-Editor. ✅ FERTIG (07.07.).** `_ContactEditorSheet` aus `contacts_screen.dart` gehoben → **public `ContactEditorSheet`** (`lib/screens/contacts/contact_editor_sheet.dart`), von Liste UND Detail geteilt. Erweitert um **Person/Firma-`SegmentedButton`** mit passenden Stammdaten (Anrede/Titel/Vorname/Nachname*/Position/Abteilung bzw. Firmenname*/offizieller Name/Handelsregister), `status`-Dropdown, `alias`, Debitoren-/Kreditoren-Nr., Blacklist-Switch. `name` wird beim Speichern **abgeleitet** (Alias→Firma→Person, mit Legacy-Prefill beim Bearbeiten alter Kontakte). `_typeIcon`/`_typeTone` → geteiltes `lib/screens/contacts/contact_visuals.dart` (`contactTypeIcon`/`contactTypeTone`). „Bearbeiten"-Aktion (`edit_outlined`, `canManageContacts`) in der Detail-AppBar. Tests `contact_editor_sheet_test` (Toggle + abgeleiteter Name). *Datumsfelder (Geburtstag/Jubiläum/Kunde-seit) + Sub-Objekt-Dialoge noch nicht editierbar → M5b.*
- **M5b — Sub-Objekt-Dialoge. ✅ FERTIG (07.07.).** `contact_subobject_dialogs.dart`: AddressDialog + BankAccountDialog + ChannelDialog. „+"-/Bearbeiten-/Entfernen-Aktionen in den Tabs Adressen/Kommunikation/Bank (`_ItemMenu`), Mutation via `copyWith`+`saveContact` (Storage-Modus-bewusst, Audit). Test: Manager fügt Adresse hinzu (end-to-end).
- **M6 — Tab Ansprechpartner/Beziehungen. ✅ FERTIG (07.07.).** `contactPersons[]` (Firma→Person, RelationshipTile mit Name-Lookup, Rolle, Hauptkontakt, Einzel-Primär erzwungen) + `parentContactId` (Person→Firma, +Model-Feld über 6 Stellen). `showContactPersonDialog` + `showCompanyPickerDialog`.
- **M7 — Tab Einwilligungen (DSGVO). ✅ FERTIG (07.07.).** `ContactConsent` **eingebettet** (nicht eigene Collection — Spark-frugal wie Activities) + `ConsentType`-Enum; Tab mit Status-Chips + Erfassen (`showConsentDialog`) + Widerrufen (setzt `withdrawnAt`). Kein Deploy/Index nötig.
- **M8 — Avatar-Upload. ✅ FERTIG (07.07.).** `getDownloadUrl` an `DocumentStorage`-Seam; `ContactAvatarUploader` (file_picker + FirebaseDocumentStorage, gated auf `!disableAuth && DefaultFirebaseOptions.isConfigured`); Kamera-Badge in der VCard (Manager) → Upload nach `organizations/{orgId}/contacts/{id}/avatar.*` → `avatarUrl`. **Storage-Rule ergänzt** (`storage.rules`). *Deploy nötig.*
- **M9 — Kontakt-Organisationen. ✅ FERTIG (07.07.).** `ContactOrganization` Model + `OrganizationType` + Repo (watch/save/delete `contactOrganizations`) + DatabaseService-Key + Provider (2. Stream/local, save/delete + Audit `Kontakt-Organisation`) + `firestore.rules`-Block + `OrganizationsScreen` (Liste + Dialog) + „Organisationen"-Aktion in der Kontaktliste. Tests (Model + Provider local). *Deploy nötig.*
- **M10 — Liste-Umbau + Merge. ✅ FERTIG (07.07.).** Person/Firma-`SegmentedButton`-Filter + Karten/Suche via `displayName` (+firstName/lastName/companyName im Haystack). `ContactDedup.mergeContacts` (Portierung `ContactMergeService.merge`, Master füllt Lücken + vereinigt Listen dedupliziert + Notizen-Concat) + „Zusammenführen"-Option im Dubletten-Dialog. Merge-Unit-Test.
- **M11 — CSV + Datumsfelder. ✅ FERTIG (07.07.).** CSV-Export/Import um Art/Vorname/Nachname/Firmenname/Debitor/Kreditor/Status erweitert (angehängte Spalten → bestehende Reihenfolge stabil). Datums-Picker Geburtstag/Firmen-Jubiläum/Kunde-seit im Editor (`_DateField`). **Strukturierte Tags bewusst weggelassen** (siehe Abweichungen oben) — kein separater Verwalten-Tab (AllTec-Detail hat nur 7 Tabs).
- **M12 — Quality Gates + Deploy. ✅ Gates FERTIG (07.07.).** `flutter analyze` clean (2 Baseline-Warnungen), `flutter test` = **1668 grün**, Deutsch-only, appColors. Storage- + Firestore-Rules aktualisiert. Offen: **Deploy** (`firestore:rules` + `storage`) + **Commit** (extern/user).

## Offene Punkte / Restrisiken

- **`name`/Person-Firma-Split-Migration** ist die risikoreichste Kopplung (name ist Pflicht + Sortier-/Such-/CSV-/PDF-/Picker-Schlüssel). Additiv halten, name-Ableitung nur beim Speichern, Bestandsdaten unangetastet. Charakterisierungstests vorher.
- **Consent-Composite-Index** (`contactId`+`grantedAt desc`) muss vor Cloud-Nutzung deployt sein, sonst Laufzeitfehler.
- **Avatar-Storage** braucht Blaze + `storage.rules` (evtl. neu anzulegen). Im Offline/Demo-Modus No-op/Initialen-Fallback.
- **Organisationen** sind in AllTec Bildungsträger-spezifisch und NICHT mit Contacts verknüpft — 1:1 als eigenständiges Adressbuch übernommen (Betreiber wünscht es). Später ggf. optional an Contacts koppeln.
- `contacts_screen.dart` (1883 Z) hat viele file-private Bausteine → Heraushebung mit Merge-Risiko.
- Deploy (Rules/Index/Storage) bleibt extern/Blaze; nichts wird in diesem Plan deployt.
