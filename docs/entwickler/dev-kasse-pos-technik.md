# Kasse/POS (technisch)

Das Kassenmodul kombiniert **pure Core-Engines** mit Firestore-Persistenz und serverseitigen Tagesaggregaten.

## Pure Engines

- `lib/core/kasse_report.dart` – Kassenbericht (Umsatz/Käufe/Rohertrag, Woche/Monat/Jahr).
- `lib/core/cash_state.dart` – Kassenzustand (Soll aus Anfang + Einnahmen).
- `lib/core/daily_closing.dart` + `lib/core/daily_closing_posting.dart` – Tagesabschluss + Buchung.
- `lib/core/cash_difference_posting.dart` – Kassendifferenz-Autobuchung (`pos-diff-{day}-{site}`).
- `lib/core/cashier_anomaly.dart` – Kassierer-Prüfung (admin, mitbestimmungssensibel).
- `lib/core/lohnquote.dart` – Lohnquote/Betriebsergebnis (`PayrollRecord.employerTotalCents ÷ Umsatz`).

## Modelle

`cashCounts`, `cashClosings`, `posDailyStats`, `posReceipts` (`lib/models/pos_receipt.dart`, `pos_daily_stat.dart`, `cash_count.dart`, `cash_closing.dart`). Die **Dritte-Hand-/Fremdgeld-Kasse** ist ein **separater additiver `thirdParty`-Block** an `SiteDefinition` (`lib/models/third_party_cash.dart`, `functions/third_party_cash.js`) – so bleibt die reguläre Kassendifferenz beweisbar unverändert.

## Server-Tagesaggregate

> [!IMPORTANT]
> `functions/oktopos_stats.js` ist der **Spiegel** der Dart-Report-Engine: Es schreibt `posDailyStats` beim Sync fort und stellt `rebuildPosDailyStats` (Callable, Backfill) bereit. Der Client **bevorzugt Server-Stats** für die volle Monats-/Jahres-Historie. Ändern Sie die Aggregationslogik, ziehen Sie beide Seiten mit (`node --test` deckt die JS-Seite).

## Rollen

- Zählen/Tagesabschluss ansehen: Admin + Teamleitung (deckungsgleich mit `posReceipts`-Rules).
- Abschließen/buchen, Kassenbericht, Kassierer-Prüfung: admin-only.
- Kiosk-Zählung: `kioskSaveCashCount` (session-validiertes Callable).

## Weiter

- [OktoPOS-Kassenanbindung](article:dev-oktopos)
- [Warenwirtschaft (technisch)](article:dev-warenwirtschaft-technik)
- [Personal & Lohn (technisch)](article:dev-personal-lohn-technik)
