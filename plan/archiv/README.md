# Archivierte Pläne

Pläne, deren **fachlicher Kern im Code gebaut+getestet** ist (am Code re-verifiziert
2026-07-04, Multi-Agent). Hier nur zur Historie; etwaige Restpunkte sind entweder rein
**extern** (Blaze-Deploy, Commit, On-Device-/Emulator-Abnahme, OktoPOS-Swagger-Verifikation)
oder bewusst **user-gated** und im [Plan-Index](../README.md) vermerkt.

## Warenwirtschaft / Kasse / POS

- **kassen-modul.md** — Kassenzustand, Tagesabschluss mit Zählung/Festschreibung, Käufe/Verkäufe & Gewinn (Rohertrag netto/brutto), Woche/Monat/Jahr. V1+M1–M6 code-fertig+getestet (Engines kasse_report/cash_state, cashCounts/cashClosings/posDailyStats, /kassenbericht, Rules/Indexe). Offen nur Blaze-Deploy (inkl. rebuildPosDailyStats-Backfill VOR erster Nightly) + Swagger-Verifik.
- **oktopos-kassenanbindung.md** — OktoPOS-Anbindung: Verkaufs-Pull→Bestand, Artikel-/Kunden-Push (5 Cloud Functions, Secret X-API-KEY). M1–M6a code-fertig+getestet, M6b (Order-Import) bewusst nicht gebaut. Offen nur Betreiber-Setup/Deploy.
- **oktopos-datenwert-plan.md** — Maximaler Datenwert aus Kassendaten P0–P4 (Velocity, Dead-Stock, Meldebestand, ABC/Rohertrag, Warenkorb, Saison, Server-Aggregate). Alle Phasen code-fertig+getestet (PosReceipt-Layer, 10+ pure Cores, SalesInsightsProvider, BestandInsights/Sortiment-Screens, 14 Tests). Offen nur extern + user-gated (P3.2 Mitbestimmung, P4.3 Wetter).
- **oktopos-datenwert-deploy.md** — Deploy-Runbook der OktoPOS-Datenwert-Strecke (posReceipts-Layer). Code/Rules/Index/Functions verifiziert vorhanden; offen nur Blaze-Deploy, OKTOPOS_API_KEYS-Secret, config/oktoposSync, Swagger-Geldfeld-Verifik.
- **oktopos-naechste-schritte.md** — OktoPOS-Roadmap: Kern (M1–M6a) + P1a/P1b im Code. Offen nur Deploy + user-gated P2/P3; einziger Bau-Rest P1c (fetch-gemocktes Pull/Push-Test-Harness).
- **mhd-ablauf-warnung.md** — MHD-/Ablaufwarnung: ProductBatch-Chargen, computeExpiryWarnings, Scanner-Erfassung, Inbox/Kiosk-Tile, Push-Nightly. M1–M4 code-fertig+committet (450db87). Offen nur Deploy + Emulator-/On-Device-Abnahme.
- **kuehlschrank-nachfuell-automatik.md** — Soll-Ist-Nachfüllautomatik (fridgeStock⊆currentStock, POS-Decrement, Deeplink `?tab=kuehl`). Phase 1+2 code-fertig+getestet. Offen nur Blaze-Deploy + OktoPOS-Go-Live für Phase-2-Wirksamkeit.
- **dritte-hand-fremdgeld-kassenzaehlen.md** — Fremdgeld-/Dritte-Hand-Beträge beim Kassenzählen (Tablet). Code-fertig+getestet+committet (2ee9c63); v1-Minimal an SiteDefinition. Offen nur Blaze-Deploy + Numpad-Abnahme. Kern deckt sich mit passwortmanager-und-dritthand-kasse.md.
- **scanner-verbesserung.md** — Scanner schneller/zuverlässiger: scanWindow/Reticle, Timeout 100ms, autoZoom, QR-Toggle, UPC-A↔EAN-13-Fix. M1–M8 code-fertig+committet (c7079de). Offen nur manuelle On-Device-Kamera-Abnahme.

## HR / Zeit / Finanzen

- **zeitwirtschaft-alltec-1zu1.md** — Zeitwirtschaft-Hub 1:1 wie AllTec (8 Screens: Stempeln/Zeiterfassung/Stundenkonto/Abwesenheiten+Kalender/Monatsabschluss/Mitarbeiterabschluss/Lohnlauf). M1–M6+M7a+M8 code-fertig+getestet. Offen nur rules/indexes-Deploy + user-gated M7b (Callable-Härtung Stempeln).
- **zeitwirtschaft-verbesserung.md** — Geräte-Sync, Datenvollständigkeit, Kassen-Zuordnung, Rollen (dienst_abgleich, Klärungs-Inbox, ConnectivityStatus, CashCount.countedByUserId). ZV-1…ZV-7 code-fertig+getestet, rules/indexes/functions bereits deployt. Offen nur extern + vertagte Reste (ZV-4.2/4.3, ZV-5.1).
- **personal-finanz-ausbau.md** — Personal-/Finanz-Ausbau auf AllTec-Niveau: EmployeeProfile (Stammakte), Lohnlauf/PayrollStatus, FinanceProvider + DATEV-EXTF + Finanz-PDF. A/B/C code-fertig+committet+getestet, /buchhaltung. Offen nur firestore:rules-Deploy + bewusst aufgeschobene Optionals (EPC-QR, CSV/DATEV-Import).
- **alltec-uebernahme.md** — AllTec-Erkenntnisse M0–M7: Steuer 2026, Payroll-Profile, Bestandsausgabe/-umlagerung, Money, zentrales Audit-Trail, Kontakt-Dedup, iCal-Export. Code-fertig+getestet (438 Tests). Offen nur git-Push + bewusst aufgeschobene Kosmetik (M5b PdfTheme, M7d SeriesUpdateMode, M7f).
- **ida-hr-zeit-uebernahme-VERIFIKATION.md** — Analyse-Artefakt: adversariale Quelltreue-Prüfung des IDA-Plans (141 Aussagen, 28 problematisch). Alle HOCH/MITTEL-Korrekturen sind in ida-hr-zeit-uebernahme.md eingearbeitet, keine eigene Bauarbeit. (Der Zielplan selbst bleibt aktiv.)

## Passwörter

- **passwortmanager-und-dritthand-kasse.md** — Passwortmanager (Cloud KMS Envelope-Verschlüsselung, harte Server-Reauth, listPasswordEntries) + Dritte-Hand-/Fremdgeld-Kasse. Kern komplett gebaut+getestet, committet (2ee9c63). Offen nur Blaze-Deploy (KMS-Keyring/IAM, Rules→Functions→App, APP_PASSWORD_MANAGER_ENABLED=true).

## Benachrichtigungen

- **push-benachrichtigungen-plan.md** — Mobile FCM-Pushes, server-getriggert (fanOutPush + 6 onDocument-Trigger, 5 Kanäle, NotificationPrefs, Web-SW). M1–M7 code-fertig+getestet, Emulator-E2E 6/6. Offen nur Blaze-Deploy + APNs-Key/VAPID + APP_PUSH_ENABLED=true.

## UI / Redesign

- **redesign-signal-teal.md** — Redesign-Fundament (redesign_flags, lib/ui-Barrel, V2-Tokens, resolveLight/Dark, Flip-/Component-Tests). V2 ist Auslieferungsstandard (defaultEnabled=true); der Screen-für-Screen-Restyle-Rest läuft im Nachfolgeplan [redesign-gesamt.md](../redesign-gesamt.md) weiter (+ Marken-Rebrand auf Strichmännchen statt Teal).

## Querschnitt / Audit

- **skills-alignment.md** — Skills-Audit gegen die 19 claude-skills: ~78/90 Gaps gebaut+getestet+committet (CI, Logger/ErrorReporter/Retry, Tombstones, Inventory-Repository/DIP, Force-Update, Security-Header/Rules, God-File-Splits). Offen nur bewusst zurückgestellte Gaps (Outbox/Delta-Sync/Golden/Flavors = Over-Engineering für 2 Läden).
- **analyse-5-tabs-behebung.md** — Tiefenanalyse+Behebung Heute/Plan/Anfragen/Kontakte/Laden + Handy-UI. M1–M6 code-fertig+getestet (Crash-Fixes Avatar/Farbe, Q1-Fehlerbehandlung, InfoChip/TabBar-Overflow, Touch-Targets, V2-Default). Offen nur functions-Deploy + Commit.

## Früher archiviert (bis 2026-06-29)

- **auto-schichtverteilung.md** — Bedarfsgesteuerte Schicht-Generierung + Auto-Zuweisung + Stundengrenzen. Vollständig.
- **scanner-modul.md** — Barcode/EAN-Scanner inkl. Preis-Historie, fester Tab. Vollständig.
- **bestellhaeufigkeit.md** — Häufig bestellte Artikel zuerst + Auswertungs-Screen. Vollständig.
- **schichttausch.md** — Tauschanfragen + Gutschriften, Chef-Bestätigung. Vollständig.
- **wochen-bestellkorb.md** — Wochen-Bestellkorb + Standard-Wochenliste. Vollständig.
