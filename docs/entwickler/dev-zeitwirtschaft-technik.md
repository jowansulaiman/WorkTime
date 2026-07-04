# Zeitwirtschaft (technisch)

Die Zeitwirtschaft ist am `/zeit`-Tab als **Hub** organisiert (`lib/screens/zeitwirtschaft/zeitwirtschaft_hub_screen.dart`) mit `ZeitwirtschaftProvider` als State.

## Echtzeit-Stempeln

- `lib/core/clock_service.dart` + `ClockEntry` (`lib/models/clock_entry.dart`) – die Stempeluhr (Kommen/Gehen/Pause), Geräte-Sync.
- Der Stempelzustand ist **an die uid gebunden** (`{userId}`-open), nicht ans Gerät – Mehrgeräte-tauglich.

## Schicht ↔ Stempel

`lib/core/dienst_abgleich.dart` ist ein **purer** Kern, der geplante Schichten mit tatsächlichen Stempeln/Zeiteinträgen abgleicht (`shiftId`-Verknüpfung). Ergebnis speist die Klärungs-Inbox und markiert Schichten als erledigt.

## Zeitkonto

- `lib/core/zeitkonto_calculator.dart` – Soll/Ist/Saldo aus Zeiten + `SollzeitProfile`.
- `lib/core/zeitkonto_snapshot_builder.dart` + `ZeitkontoSnapshot` – festgeschriebene Stände.
- `lib/core/monatsabschluss_service.dart` – echte Monats-Festschreibung (sperrt Einträge, fixiert Konto-Beitrag).

## Screens im Hub

`zeiterfassung_screen.dart`, `stempel_screen.dart`, `stundenkonto_screen.dart`, `abwesenheiten_screen.dart`, `abwesenheitskalender_screen.dart`, `monatsabschluss_screen.dart`, `mitarbeiterabschluss_screen.dart`, `lohnlauf_screen.dart`. Die Sub-Routen (`AppRoutes.zeit*`) hängen unter dem Tab-Hub; mitarbeiterseitige Bereiche brauchen `canViewTimeTracking`, Admin-Bereiche (`zeitMitarbeiterabschluss`, `zeitLohnlauf`) `isAdmin`.

> [!NOTE]
> `WorkEntry` ist die Ausnahme der Zwei-Serialisierungs-Regel (wirft bei kaputtem Datum) – siehe [Zwei-Serialisierungs-Regel](article:dev-zwei-serialisierung). `date` ist auf 12:00 lokal normalisiert.

## Abwesenheiten

`AbsenceRequest` + `abwesenheit_matrix.dart`: Genehmigungslogik, und eine Krankmeldung gibt die Schicht frei (Manager-Selbstmeldung sofort, Mitarbeiter bei Genehmigung). Anträge immer über `showAbsenceRequestSheet(...)` (in `notification_screen.dart`).

## Weiter

- [Automatische Schichtverteilung](article:dev-auto-schichtverteilung)
- [Personal & Lohn (technisch)](article:dev-personal-lohn-technik)
