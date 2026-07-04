# Firestore-Datenmodell

Firestore ist die Cloud-Quelle. Der Zugriff läuft ausschließlich über `FirestoreService` (`lib/services/firestore_service.dart`) – **Pfade nie hardcoden**, immer die Collection-Getter nutzen.

## Struktur

- **Top-Level**: `users/{uid}` (trägt das `orgId`-Feld!) und `userInvites/{emailLower}` (Doc-ID = getrimmte lowercase-E-Mail, `/`→`_`).
- **Org-skopiert** unter `organizations/{orgId}/`: `workEntries`, `workTemplates`, `shifts`, `shiftTemplates`, `absenceRequests`, `teams`, `sites`, `qualifications`, `employmentContracts`, `employeeSiteAssignments`, `ruleSets`, `travelTimeRules` (u. a.).
- **Config-Singletons** unter `config/`: `appFlags` (FeatureFlagProvider) und `orgSettings` (org-weite Einstellungen der Auto-Schichtverteilung). Beide deckt der generische `config/{configId}`-Rules-Block (sameOrg-read/admin-write).

## Org-Isolation

Die Mandantentrennung liegt an **zwei** Stellen, die synchron bleiben müssen:

- `firestore.rules` (`sameOrg`)
- Functions (`assertSameOrg`)

Details: [Sicherheit & Mandantentrennung](article:dev-sicherheit-multi-tenancy).

## Transiente Modelle

`ComplianceViolation` ist **transient** – keine Collection, nur in-memory.

## Enums serialisieren zu snake_case

Enums serialisieren via `.value`-Getter zu snake_case-Strings ≠ Dart-Name:

- `RecurrencePattern.biWeekly` → `bi_weekly`
- `EmploymentType.fullTime` → `full_time`, `miniJob` → `mini_job`
- `ShiftStatus` = `planned/confirmed/completed/cancelled`

`fromValue` hat immer einen Default-Branch (wirft nie) → ein falscher String fällt still auf den Default.

## Composite-Indexe

> [!WARNING]
> Ein neuer `where`+`orderBy`-Query braucht einen passenden Composite-Index in `firestore.indexes.json` (Bestand: 14) + Deploy, sonst Laufzeitfehler.

## fromFirestore bekommt die Doc-ID separat

`fromFirestore(doc.id, doc.data())` – Firestore-Maps enthalten die `id` **nie** selbst. Siehe [Die Zwei-Serialisierungs-Regel](article:dev-zwei-serialisierung).

## Weiter

- [Die Zwei-Serialisierungs-Regel](article:dev-zwei-serialisierung)
- [Sicherheit & Mandantentrennung](article:dev-sicherheit-multi-tenancy)
- [Cloud Functions](article:dev-cloud-functions)
