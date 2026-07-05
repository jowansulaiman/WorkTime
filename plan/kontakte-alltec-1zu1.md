# Kontaktbereich — UI/Tabs + Datenmodell genau 1:1 wie AllTec

**Stand:** 2026-07-04 · **Status:** **M1–M3 fertig+verifiziert** (Route + 7-Tab-Detail + komplettes Modell-Fundament: 4 Sub-Modelle + Person/Firma-Split + Status, alle dual-serialisiert + round-trip-getestet, rückwärtskompatibel; 61+ Tests grün, analyze clean); M4–M12 offen · **Priorität:** hoch
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
- **M4 — Tabs Übersicht/Adressen/Kommunikation/Bank (read).** Read-Karten über M2/M3-Daten; Kanäle gruppiert nach Kontext + Kopieren; Adressen typisiert; „Letzte Aktivitäten" in Übersicht (Erhalt).
- **M5 — Reicher „Bearbeiten"-Editor + Sub-Objekt-Dialoge.** ContactCreateForm-Äquivalent (Person/Firma-Toggle, Kategorie, Kanäle, Adresse, Notizen) + AddressDialog + BankAccountDialog + TagDialog. Provider-Convenience-Mutatoren (add/update/remove/setPrimary via `saveContact`).
- **M6 — Tab Ansprechpartner/Beziehungen.** `contactPersons[]` + `parentContactId`; RelationshipTile; ContactPersonDialog + Firma-Verknüpfungs-/Picker-Dialoge; Provider-Ops.
- **M7 — Tab Einwilligungen (DSGVO).** `ContactConsent` Model + Collection + Rules + Composite-Index + Provider (watch/grant/withdraw) + ConsentDialog + Status-Chips + Kaskade beim Löschen. *Deploy nötig.*
- **M8 — Avatar-Upload.** Storage-Pfad + Storage-Rules + Provider `uploadAvatar`/`removeAvatar` + `AvatarUploadWidget` (Web/Mobile-Zweig) + `avatarUrl`-Anzeige in VCard/Liste. *Deploy nötig.*
- **M9 — Kontakt-Organisationen.** `ContactOrganization` Model + Collection + Rules + Provider (watch/save/delete) + Organisationen-Liste + `_CreateOrganizationDialog` + Einstieg (AppBar-Aktion/Section-Route). *Deploy nötig.*
- **M10 — Liste-Umbau + Merge.** ContactListPage-Parität (Person/Firma-Segment, Kategorie-/Status-Filter, Karten mit Kategorie-Farbe + Status-Punkt, Suche über neue Felder); `mergeContacts` (Portierung `ContactMergeService.merge`) + Dubletten-UI.
- **M11 — Notizen/Verwalten + CSV/PDF.** Tab Notizen (notes + Tags-Chips + TagDialog); Verwalten-Aktionen (deactivate/blacklist/status/löschen + Meta); CSV-Import/Export + PDF um neue flache Felder (Debitor/Kreditor, Struktur) erweitern.
- **M12 — Quality Gates + Deploy.** `flutter analyze` clean, `flutter test` grün, de_DE, appColors; Deploy-Notizen (Rules `contactConsents`+`contactOrganizations`, Storage-Rules, Consent-Index); Commit.

## Offene Punkte / Restrisiken

- **`name`/Person-Firma-Split-Migration** ist die risikoreichste Kopplung (name ist Pflicht + Sortier-/Such-/CSV-/PDF-/Picker-Schlüssel). Additiv halten, name-Ableitung nur beim Speichern, Bestandsdaten unangetastet. Charakterisierungstests vorher.
- **Consent-Composite-Index** (`contactId`+`grantedAt desc`) muss vor Cloud-Nutzung deployt sein, sonst Laufzeitfehler.
- **Avatar-Storage** braucht Blaze + `storage.rules` (evtl. neu anzulegen). Im Offline/Demo-Modus No-op/Initialen-Fallback.
- **Organisationen** sind in AllTec Bildungsträger-spezifisch und NICHT mit Contacts verknüpft — 1:1 als eigenständiges Adressbuch übernommen (Betreiber wünscht es). Später ggf. optional an Contacts koppeln.
- `contacts_screen.dart` (1883 Z) hat viele file-private Bausteine → Heraushebung mit Merge-Risiko.
- Deploy (Rules/Index/Storage) bleibt extern/Blaze; nichts wird in diesem Plan deployt.
