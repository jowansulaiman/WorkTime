# WorkTime — Code-Review: Bugs & Probleme

_Stand: 2026-06-21 · Automatisierter Multi-Agent-Review (Finder → adversariale Verifikation → Synthese), ergänzt um manuelle Verifikation der wichtigsten Befunde._

## Methodik

- **17 Review-Bereiche** (pro Modul + querschnittliche Lenses), jeder Befund mit `datei:zeile` belegt.
- Befunde aus den Hauptläufen wurden **adversarial verifiziert** (ein zweiter Agent versuchte, jeden Befund am echten Code zu widerlegen; widerlegte Befunde sind nicht enthalten).
- Ein Teil der Bereiche musste wegen temporärer API-Ausfälle in einem **Einzelpass ohne zweite Verifikation** laufen — diese sind als _„Einzelpass (unverifiziert)“_ markiert; die wichtigsten davon wurden **manuell am Code nachgeprüft** (_„selbst verifiziert“_).
- **Baseline:** `flutter analyze` ist sauber (bis auf 2 triviale Hinweise), **alle 453 Tests grün** — die folgenden Befunde sind also Dinge, die Lint/Tests **nicht** fangen.

## Schweregrad-Übersicht

| Schweregrad | Anzahl |
|---|---|
| 🔴 Kritisch | 1 |
| 🟠 Hoch | 4 |
| 🟡 Mittel | 17 |
| ⚪ Niedrig | 54 |
| **Summe** | **76** |

Verifizierungsstatus: adversarial verifiziert: 36, Einzelpass (unverifiziert): 32, selbst verifiziert: 8.

## Dateien

- [01-kritisch-hoch.md](01-kritisch-hoch.md) — **alle kritischen & hohen Befunde gebündelt (hier anfangen)**
- [compliance.md](compliance.md) — Compliance-Spiegel (Dart ↔ Cloud Function)
- [services-firestore.md](services-firestore.md) — FirestoreService / Callables · Repositories
- [services-persistenz.md](services-persistenz.md) — DatabaseService / lokale Persistenz · Export / PDF / Scanner / Download
- [provider-state.md](provider-state.md) — Work- & Schedule-Provider · Team- / Personal- / Auth-Provider · Inventory- / Contact- / Audit-Provider
- [bestellkorb-kundenwuensche.md](bestellkorb-kundenwuensche.md) — Wochen-Bestellkorb & Kundenwünsche (neues Modul)
- [sicherheit.md](sicherheit.md) — Sicherheit: Firestore-Rules & Permissions
- [modelle-serialisierung.md](modelle-serialisierung.md) — Modelle & Serialisierung
- [core-lohn.md](core-lohn.md) — Core-Logik (Config, Parser, Lohn, Steuer)
- [navigation-bootstrap.md](navigation-bootstrap.md) — Shell / Navigation / Bootstrap
- [screens-ui.md](screens-ui.md) — Screens: Schichtplaner & Team · Screens: Inventar / Scanner / Bestellkorb / Wünsche · Screens: Personal / Zeit / Reports / Settings
- [test-luecken.md](test-luecken.md) — Test-Qualität & Lücken

## Top-Prioritäten

1. **Server-Compliance prüft nur 4 von ~12 Regeln (Spiegel-Drift)** — Direkte Client-Writes sind ohnehin möglich (Design-Lücke); die Cloud-Function als „validierter Pfad“ deckt für Zeiteinträge die meisten Regeln nicht ab → Compliance-Verstöße landen unbemerkt in Firestore.  ([Details](compliance.md))
2. **Duplikat-Dokumente bei verlorenem Callable-Ack** — Server nutzt deterministische Doc-ID, der direkte Fallback eine zufällige → doppelte Zeiteinträge/Schichten → falsche Stunden/Lohn/Compliance.  ([Details](services-firestore.md))
3. **Stunden-Rundung Dart vs. minutengenau JS** — Client-Preview und Server-Validierung können unterschiedlich entscheiden → Schichten/Einträge werden mal blockiert, mal nicht.  ([Details](compliance.md))
4. **parseEuroToCents: Punkt = Tausendertrenner** — „1.99“ wird zu 199,00 € — stiller 100×-Preisfehler in EK/VK-Eingabe (Inventar, Scanner, Kundenbestellung).  ([Details](screens-ui.md))
5. **Übernacht-Schichten nicht anlegbar** — Editor weist Endzeit < Startzeit ab, obwohl die Compliance-Logik Nachtarbeit (23–06) modelliert → Spät-/Nachtschichten über Mitternacht unmöglich.  ([Details](screens-ui.md))
6. **orderCarts-Rules ohne Feld-Allowlist** — Jedes Mitglied kann beliebige Felder/`updatedByUid` fälschen (Mass Assignment / Audit-Spoofing) — abweichend vom sonst durchgezogenen Allowlist-Muster.  ([Details](sicherheit.md))
7. **PersonalProvider startet Admin-Streams für alle** — Jeder Nicht-Admin-Login löst permission-denied auf Lohn-Streams aus + Ladespinner bleibt hängen.  ([Details](provider-state.md))
8. **customerWishes: Cross-Tenant-/Spam-Write** — Jeder authentifizierte Nutzer (auch fremder Org) kann unbegrenzt in main-org schreiben, solange App Check nicht aktiv ist.  ([Details](sicherheit.md))
9. **Statistik-CSV ohne UTF-8/BOM** — `.codeUnits` + kein BOM → Umlaute in deutschem Excel kaputt (ExportService macht es korrekt — hier nicht).  ([Details](screens-ui.md))
10. **Stream-Leak: _allAbsenceSubscription nicht gecancelt** — dispose() lässt eine Subscription offen → Speicher-/Callback-Leak nach Provider-Wechsel.  ([Details](provider-state.md))

## Querschnittliche Themen

- **Compliance-Spiegel driftet** — `compliance_service.dart` (Client) und `functions/index.js` (Server) sollen identisch validieren, weichen aber in Regelumfang, Rundung (Stunden vs. Minuten), Pausenabzug, Dedup und Nachtfenster ab.
- **Provider gaten Admin-Streams nicht & setzen `loading` bei Fehlern nicht zurück** — PersonalProvider/TeamProvider/InventoryProvider/ContactProvider starten Streams ohne Rollen-/Fehler-Guards → permission-denied-Spam und dauerhaft hängende Ladespinner.
- **`DateFormat` ohne `'de_DE'`** — An vielen UI-Stellen (Schichtplaner, Statistik, Reports, PDF) fehlt das laut CLAUDE.md verpflichtende explizite Locale → AM/PM-Anzeige bzw. potenzieller Absturz auf nicht-deutschen Geräten.
- **Geld-Parsing behandelt den Punkt als Tausendertrenner** — `parseEuroToCents`/`Money.parseCents` machen aus „1.99“ stillschweigend 199 € — über mehrere Eingabepfade hinweg.
- **Idempotenz/Fallback der Callables unvollständig** — Verlorene Acks, deadline-exceeded und gemischte orgIds in Batches führen zu Duplikaten, harten Fehlern statt Fallback bzw. Fehl-Org-Writes.
- **Neuer Bestellkorb-Schreibpfad ist bewusst breit, aber unter-validiert** — Leeres `siteId` → `.doc('')`-Absturz; keine Feld-Allowlist in den Rules; Stream-Fehler überschreiben die globale Fehleranzeige; viele Pfade ungetestet.

## Hinweis zur Vollständigkeit

Die Bereiche FirestoreService, einige Screens und das neue Bestellkorb-/Wunsch-Modul wurden teils unter erschwerten Infrastrukturbedingungen (API-Ausfälle) reviewt. Die als _kritisch_/_hoch_ eingestuften Befunde sind durchgehend (auch manuell) am Code verifiziert; bei _niedrig_/_mittel_ mit Status _„Einzelpass“_ empfiehlt sich vor dem Fix ein kurzer Gegen-Check. Keine Code-Änderungen wurden vorgenommen — dies ist ein reiner Review.
