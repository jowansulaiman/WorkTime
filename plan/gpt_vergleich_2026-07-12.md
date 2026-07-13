# Vergleich Warenwirtschaft: KORONA POS, Tillhub und WorkTime

Stand: 2026-07-12  
Scope: Nur Warenwirtschaft, Inventur und DATEV-Übertragung. "Dativübertragung" im Auftrag wird als DATEV-Übertragung interpretiert.

## Kurzfazit

WorkTime hat bereits eine solide Warenwirtschaft: Artikel je Standort, Lieferanten, Bestellungen, Wareneingang, Bestandsbewegungen, geführte Inventur, Scanner, MHD-Chargen, Nachbestellhinweise, Bestellkorb, Bestands-/Nachbestell-Export und einen DATEV-EXTF-Export über das Finanzjournal.

KORONA POS ist in der Tiefe der professionellere Maßstab: Bestellvorlagen, Warenbestellungen aus Abverkäufen, offene Bestellmengen, Lieferavis, Wareneingang mit Ist-EK/Teilmenge/Preisprüfung, MDE-App, mehrere Inventurtypen, Zähllisten-Import, PDF-Zähllisten, Differenzlisten, Festschreibekennzeichen und DATEV-Mapping nach Sparten/Zahlarten/Kostenstellen.

Tillhub wirkt schlanker, aber sehr alltagstauglich: zentrale Multi-Filial-Warenwirtschaft, Echtzeit-Bestände, digitale Wareneingänge/Inventuren, Warehub-App für mobile Bestandsaufnahme, Ein-/Aus-/Umlagerungen, exportierbare Inventarbewegungen und ein bewusst einfacher DATEV-CSV-Export statt Live-Schnittstelle.

Die größte WorkTime-Erweiterung sollte daher nicht "alles neu bauen" sein, sondern:

1. Wareneingang professioneller machen.
2. Inventur zu echten Zählprozessen mit Import, Export, Mehrgeräte-Workflow und Abschlussstatus ausbauen.
3. Offene Bestellmengen, Bestellzyklen und datengetriebene Auto-Bestellvorschläge einführen.
4. DATEV von "vereinfachter Finanzstapel" zu "kassennaher Buchungsübergabe mit Mapping, Festschreibung und Prüflauf" ausbauen.

## Quellen

### KORONA POS

- KORONA POS Funktionen: Bestandsmitteilungen, Datenimport, konsolidiertes Inventar, Lieferungen scannen, Produktanalyse, Etiketten/Preisschilder, Auto-Bestellung, Versand verfolgen, mobile Inventur-App: https://koronapos.com/de/pos-funktionen/
- KORONA Warenbestellungen: Bestellung aus Vorlage, leerer Bestellung, Abverkäufen; knappe Artikel; Senden per PDF/CSV/XML; offene Bestellmenge und Abschluss: https://support.korona.de/warenbestellungen-erstellen/
- KORONA Wareneingänge: aus Bestellung, Lieferavis oder leer; Soll-/Ist-Mengen, Einzelpreis, Teilmengen, Durchschnitts-EK, PDF, Scanner, externe Kosten/Rabatte: https://support.korona.de/wareneingaenge-erstellen/
- KORONA Inventuren: permanente Inventur, Stichprobeninventur, Stichtagsinventur, Unregelmäßigkeiten; Listen, Handscanner, PDF-Zählliste, Zusammenfassen, Differenzliste, Kasse, CSV/Excel-Import: https://support.korona.de/inventuren-durchfuehren/
- KORONA MDE-App: Inventuren, Wareneingänge, Bestandsanpassungen, Filialbestellungen, Lieferavis und Artikelinformationen per Android/Handscanner: https://support.korona.de/korona-mde/
- KORONA DATEV-Export: KORONA.plus, DATEV-Buchungsstapel, Festschreibekennzeichen, Erlöskonten, Kostenstellen, Gruppierung nach Kasse/Organisationseinheit: https://support.korona.de/datev-export/

### Tillhub

- Tillhub Einzelhandel-Funktionen: Echtzeit-Dashboard, Bestandslisten als Excel/CSV, Multi-Filial-Warenwirtschaft, automatische Bestandsaktualisierung, digitale Wareneingänge/Inventuren, Lieferantenmanagement, DATEV-Export: https://www.tillhub.de/kassensystem/funktionen/
- Tillhub/Unzer Bestandsaufnahme mit Warehub: Dashboard-Prozess, Ort, Mitarbeiter, mobile App, Scanner-Modi, Warehub-Abschluss: https://help.unzer.com/de/support/solutions/articles/79000148132-bestandsaufnahme-mit-warehub
- Tillhub/Unzer Inventarbewegungen: Einlagerung, Auslagerung, Umlagerung, Bewegungsübersicht und Export: https://help.unzer.com/de/support/solutions/articles/79000148131-einlagerung-auslagerung-umlagerung-inventarbewegungen
- Tillhub DATEV: Export statt Live-Schnittstelle, CSV im DATEV-Format, monatlicher Download, Inhalte nach Kassenabschluss, MwSt.-Satz, Zahlart, Einlagen/Ausgaben/Differenzen: https://www.blog.tillhub.de/datev-schnittstelle-was-ist-das
- Tillhub Funktionsübersicht PDF: Inventur mit Smartphone/Scanner/Tablet über Warehub, Datenexporte, DATEV-Export: https://cdn2.hubspot.net/hubfs/3046528/Funktions%C3%BCbersicht.pdf

### WorkTime-Basis im Repo

- Warenwirtschaft-Übersicht: `README.md`
- Technische Warenwirtschaft: `docs/entwickler/dev-warenwirtschaft-technik.md`
- Warenwirtschaft-Plan: `plan/warenwirtschaft-verbesserung.md`
- Kernmodelle: `lib/models/product.dart`, `lib/models/purchase_order.dart`, `lib/models/stock_movement.dart`, `lib/models/product_batch.dart`
- Provider/Repository: `lib/providers/inventory_provider.dart`, `lib/repositories/inventory_repository.dart`, `lib/repositories/firestore_inventory_repository.dart`
- Inventur: `lib/screens/inventur_screen.dart`
- DATEV: `lib/core/datev_export.dart`, `lib/services/export_service.dart`, `lib/screens/finance_screen.dart`

## Anbieteranalyse

### KORONA POS: Warenwirtschaft

KORONA positioniert die Warenwirtschaft als vollwertiges Backoffice-System. Relevant sind:

- Bestandswarnungen für niedrige Bestände, Überbestände und fehlende Bestände.
- Inventar-Datenimport für neue Standorte oder Franchise.
- Konsolidiertes Inventar über Bereiche/Standorte.
- Wareneingang per Scan.
- Produktanalyse pro Artikel.
- Etiketten- und Preisschilddruck direkt aus der Warenwirtschaft.
- Auto-Bestellung auf Basis des Produktbestands.
- Versand-/Lieferstatus über Lieferantenverwaltung.
- Warenbestellungen aus Bestellvorlage, leerer Bestellung oder Abverkäufen.
- Bei leerer Bestellung Option "Nur knappe Artikel hinzufügen".
- Bestellung kann an Lieferanten gesendet werden; KORONA nennt PDF, CSV oder XML als Anhangstyp.
- Offene Bestellmengen bleiben sichtbar und schützen vor unnötigem Nachbestellen; Rest kann abgeschlossen werden.
- Wareneingänge können aus Bestellung, Lieferavis oder leer entstehen.
- Beim Wareneingang sind Soll-Menge, gelieferte Menge, bestellte Menge und Einzelpreis sichtbar/anpassbar.
- Durchschnittlicher Einkaufspreis wird beim Verbuchen aus Altbestand und Wareneingang berechnet.
- Externe Kosten/Rabatte am Wareneingang.

Bewertung für WorkTime: KORONA ist besonders stark in Einkaufsprozess, Bestellautomatik, Lieferavis, offenem Zulauf und sauberem Wareneingangsabschluss.

### KORONA POS: Inventur

KORONA bietet mehrere Inventurarten:

- Permanente Inventur über das Jahr.
- Stichprobeninventur.
- Stichtagsinventur.
- "Unregelmäßigkeiten erkennen", bei der die Cloud Artikel vorschlägt, z. B. negative Bestände oder Artikel ohne Verkauf.
- Inventurlisten mit Artikel-/Warengruppen-/Sortimentsauswahl.
- Handscanner-Unterstützung.
- PDF-Zählliste.
- Mehrere parallele Zähllisten können zusammengeführt werden.
- Differenzprüfung beim Verbuchen.
- Bewertete Inventurliste und Differenzliste als PDF.
- Inventur an der Kasse.
- Import einer Zählliste per Excel/CSV mit Artikelnummer, optionalem Artikelnamen, Lagernummer und Menge.
- MDE-App für Android/Handscanner: Inventuren, Wareneingänge, Bestandsanpassungen, Filialbestellungen, Lieferavis, Artikelinformationen.

Bewertung für WorkTime: KORONA liefert das Zielbild für "Inventur als Prozess" statt nur "Zählung als Screen".

### KORONA POS: DATEV

KORONA bietet einen DATEV-Buchungsstapel aus dem Backoffice. Relevante Punkte:

- DATEV-Export als Schnittstelle zu DATEV-Anwendungen.
- Festschreibekennzeichen für GoBD-nahe Datensicherung.
- Pflichtfelder wie Umsatz, Soll/Haben, Konto, Gegenkonto, Belegdatum, Buchungstext, KOST1.
- Export nach Sparten, Konten und Zahlungsmethoden.
- Gruppierung nach Gegenkonto/Kasse und Kostenstelle/Organisationseinheit.
- Erlöskonten-Mapping für Konten, Zahlungsmethoden, Steuern/Rabatterlöse und Sparten.
- Kostenstellen an Organisationseinheiten.

Bewertung für WorkTime: KORONA ist beim DATEV-Mapping deutlich näher an der Kasse: Zahlarten, Kassen, Steuersparten, Kostenstellen und Festschreibung sind zentral.

### Tillhub: Warenwirtschaft

Tillhub fokussiert auf einfache Bedienung und zentrale Cloud-Verwaltung:

- Echtzeit-Dashboard für Verkäufe und Bestände.
- Bestandsübersicht in Echtzeit.
- Bestandslisten als Excel/CSV.
- Multi-Filial-Warenwirtschaft mit zentraler Bestandsverwaltung.
- Automatische Bestandsaktualisierung beim Verkauf.
- Digitale Wareneingänge und Inventuren.
- Lieferantenmanagement.
- Einlagerung, Auslagerung und Umlagerung zwischen Filialen.
- Inventarbewegungen inklusive Verkäufen, Dashboard-Bewegungen, Filter und Export.

Bewertung für WorkTime: Tillhub ist bei Bewegungsübersicht, Exportierbarkeit und einfacher Multi-Filial-Bestandslogik stark. WorkTime hat ähnliche Grundlagen, braucht aber bessere Prozesssicht und Export-/Filter-Reife.

### Tillhub: Inventur

Tillhub nutzt Warehub als Inventur-/Bestandsaufnahme-App:

- Bestandsaufnahme-Prozess im Dashboard unter Bestandsverwaltung > Prozesse.
- Pflichtangaben: Prozessname, Ort, verantwortlicher Mitarbeiter.
- Mobile App auf Android/iOS.
- Verbindung über Lizenz/Gerätezuordnung.
- Scanner-Modi, Produkt-Scan, manuelle EAN als Notlösung.
- Liste gezählter Artikel mit Mengenbearbeitung.
- Prozessabschluss oder Abbruch.
- App-Store-Beschreibung: Scannen und Verarbeiten des Bestands, um Bestandsunterschiede zu erfassen.

Bewertung für WorkTime: Tillhub ist weniger tief als KORONA, aber UX-stark: ein benannter Prozess mit Ort, Mitarbeiter, Gerät und Abschlussstatus ist genau das, was WorkTime für den Ladenalltag ergänzen sollte.

### Tillhub: DATEV

Tillhub sagt ausdrücklich: kein DATEV-Live-API, sondern DATEV-Export.

- CSV-Datei im DATEV-Format.
- Export aus Dashboard-Berichten/Kassenabschlüssen.
- Zeitraum wählen, Export > DATEV, Datei an Steuerberater.
- Inhalte laut Tillhub: Umsätze pro Kassenabschluss nach MwSt.-Satz, Zahlarten, Transitkonto, Einlagen, Ausgaben und Differenzbuchungen.
- Monatliche oder quartalsweise Exporte.
- GoBD-konforme Erfassung wird beworben.

Bewertung für WorkTime: Tillhub ist ein gutes pragmatisches Ziel: zuerst ein verlässlicher, prüfbarer DATEV-Export aus Kassenabschlussdaten, keine teure Live-Schnittstelle.

## WorkTime: aktueller Stand

### Bereits vorhanden

Warenwirtschaft:

- Lieferantenverwaltung mit Kontakt, Bestell-E-Mail, Kundennummer und Lieferzeit.
- Artikel je Standort mit Bestand, Mindestbestand, Zielbestand, EK/VK, Steuersatz, Barcode, Warengruppe, Standard-Lieferant.
- Nachbestellwarnung bei Bestand <= Meldebestand.
- Bestellvorschlag aus unterschrittenen Artikeln.
- Bestellungen mit Entwurf, bestellt, Teillieferung, geliefert, storniert.
- Atomarer Wareneingang auf Bestellung mit Bestandsfortschreibung und StockMovement.
- Direkter Zugang ohne Bestellung.
- Abgang, Bestandskorrektur, Inventurbuchung.
- Umlagerung zwischen Standorten inklusive automatischer Zielartikel-Anlage.
- Bestandsbewegungen und Bewegungshistorie.
- Bestellkorb/Wochenliste: Gruppierung nach Lieferant erzeugt echte Bestellungen.
- Bestands- und Nachbestellliste als PDF/CSV.
- Preisverlauf.
- Scanner mit Barcode-Suche und Bestand buchen.
- MHD-Chargenmodell und Ablaufwarnung.
- OktoPOS-Anbindung für Kassenverkaufsdaten und Artikel-/Kunden-Push.

Inventur:

- Geführter Inventur-Screen `/inventur`.
- Standort- und Warengruppenfilter.
- Suche.
- Leere Zählfelder statt Vorbefüllung.
- Fortschritt.
- Differenz-Vorschau.
- EK-bewertete Differenz für Leitung.
- Buchen über `recordStocktake`.
- PopScope-Schutz bei ungebuchten Zählständen.

DATEV/Buchhaltung:

- Finanzjournal mit Kostenstellen und Kostenarten.
- DATEV-EXTF-Buchungsstapel Format 700.
- Beraternummer, Mandantennummer, Sachkontenlänge, Gegenkonto, Stapelbezeichnung.
- KOST1/KOST2.
- Tagesabschluss kann je USt-Satz auf Erlöskonto/Kostenart gebucht werden.
- Export als `EXTF_Buchungsstapel_<jahr>.csv`.

### Noch nicht auf Anbieter-Niveau

Warenwirtschaft:

- Keine Bestellvorlagen/Bestellkreisläufe wie KORONA.
- Keine echte Auto-Bestellung aus Abverkäufen/offenen Bestellrhythmen.
- Offene Bestellmengen werden nicht sichtbar in Nachbestellvorschläge einbezogen.
- Kein "Rest schließen" für ewige Teillieferungen.
- Kein Lieferavis.
- Wareneingang speichert noch keine Lieferschein-Nr., Ist-EK je Position, externe Kosten/Rabatte, Preisabweichungsprüfung oder Durchschnitts-EK-Fortschreibung.
- Bestellungen werden per PDF/mailto unterstützt, aber keine strukturierten Lieferanten-Anhangstypen CSV/XML.
- Kein Etiketten-/Preisschilddruck aus der Warenwirtschaft.
- Bewegungsübersicht ist vorhanden, aber nicht so prominent/filter-/exportfähig wie Tillhub.

Inventur:

- Keine persistenten Inventurprozesse mit Status, Name, Start/Ende, Ort, verantwortlicher Person.
- Keine Zähllisten als eigene Objekte.
- Keine parallelen Zähllisten/Mehrgeräte-Zählung mit Zusammenführen.
- Keine permanente Inventur, Stichtagsinventur, Stichprobeninventur als echte Typen.
- Kein Vorschlag "Unregelmäßigkeiten zählen" als Inventurtyp.
- Kein CSV/Excel-Import einer Zählliste.
- Kein PDF-Zähllisten-Export.
- Keine bewertete Inventurliste/Differenzliste als Abschlussdokument.
- Kein echter mobiler MDE-/Warehub-ähnlicher Flow mit Gerätebindung, Offline-Zählung und späterem Upload.

DATEV:

- Export ist vereinfacht: Konto = Kostenart, festes Gegenkonto, keine Steuerschlüssel.
- Kein Festschreibekennzeichen/Export-Lock.
- Keine Export-Historie mit Zeitraum, Status, Ersteller, Datei-Hash.
- Keine steuerberaterfreundliche Prüfansicht vor Export.
- Kassenabschlussdaten sind nur teilweise auf DATEV-Mapping gehoben.
- Zahlarten, Kassen, Einlagen/Ausgaben/Differenzen und Transitkonten sind noch nicht so explizit abgebildet wie bei Tillhub/KORONA.
- Keine Mandanten-/Standort-spezifischen DATEV-Profile.

## Gap-Matrix

| Bereich | KORONA POS | Tillhub | WorkTime heute | Lücke für WorkTime |
|---|---|---|---|---|
| Artikel/Bestand | Tief: Warnungen, Import, Produktberichte, Etiketten, Auto-Bestellung | Echtzeit-Bestand, Excel/CSV, Multi-Filiale | Artikel je Standort, Bestand, Mindest-/Zielbestand, Warenwert, Scanner, MHD | Etiketten, offene Bestellmengen, Bewegungs-Export, Import/Produktlisten-Tools |
| Lieferanten/Bestellung | Vorlagen, aus Abverkäufen, knappe Artikel, Sendung, PDF/CSV/XML | Lieferantenmanagement, digitaler Wareneingang | Lieferanten, Bestellkorb, Bestellungen, PDF/mailto | Bestellzyklen, strukturierter Lieferantenversand, Lieferavis, Rest schließen |
| Wareneingang | Aus Bestellung/Lieferavis/leer, Ist-EK, Teilmengen, Durchschnitts-EK, Rabatte/Kosten | Digitale Wareneingänge | Atomarer Wareneingang, Teillieferung, Direkt-Zugang | Lieferschein, Ist-EK je Position, Kosten/Rabatte, Preis-/EK-Historie |
| Umlagerung | Interne Warenbestellung/Wareneingang | Ein-/Aus-/Umlagerung zwischen Filialen | Umlagerung mit Zielartikel-Anlage | Mehr Monitoring, Export, Prozessstatus |
| Inventur | 4 Inventurtypen, Listen, PDF, Import, Zusammenfassen, Kasse, MDE | Warehub-Prozess mit Ort/Mitarbeiter/App/Abschluss | Geführter Inventur-Screen | Persistente Prozesse, Mehrgeräte, Import/Export, Abschlussdokumente |
| DATEV | Buchungsstapel, Festschreibung, Erlöskonten, Zahlarten, Kassen, KOST | DATEV-CSV aus Kassenabschluss, KMU-pragmatisch | EXTF aus Finanzjournal, Basis-Konfig | Kassenabschlussnahes Mapping, Zahlarten, Export-Lock, Prüflauf |

## Erweiterungsplan WorkTime

### AP1: Wareneingang auf Anbieter-Niveau

Ziel: Wareneingang wird vom "Mengen buchen" zum prüfbaren Lieferprozess.

Umsetzung:

- `PurchaseOrder` um Felder ergänzen: `deliveryNoteNumber`, `externalCostsCents`, `discountCents`, `closedAt`, `closedReason`.
- `PurchaseOrderItem` um `receivedUnitPriceCents`, `receivedTaxRatePercent`, optional `batchExpiryDate` erweitern.
- Wareneingang-Dialog:
  - Soll-Menge, bisher geliefert, offene Menge, jetzt geliefert anzeigen.
  - Ist-EK je Position editierbar.
  - Preisabweichung gegen Artikel-EK markieren.
  - MHD/Charge pro Position erfassen und `ProductBatch` anlegen.
  - Lieferschein-Nr. erfassen.
  - "Rest schließen" anbieten.
- Bei Wareneingang:
  - Bestand atomar buchen.
  - `StockMovement` mit Lieferschein-/Bestellbezug.
  - Preisänderung optional in `PriceHistoryEntry`.
  - Wareneinsatz-Finanzbuchung erst bei abgeschlossenem Rest.

Akzeptanz:

- Teillieferung lässt offene Menge stehen.
- "Rest schließen" entfernt offene Bestellmenge aus Nachbestelllogik.
- Abweichender Ist-EK wird sichtbar und optional übernommen.
- MHD aus Wareneingang erzeugt Charge.

Betroffene Stellen:

- `lib/models/purchase_order.dart`
- `lib/repositories/inventory_repository.dart`
- `lib/repositories/firestore_inventory_repository.dart`
- `lib/providers/inventory_provider.dart`
- `lib/screens/inventory_screen.dart`
- Tests: `test/inventory_provider_test.dart`, `test/product_batch_test.dart`, neuer `test/goods_receipt_flow_test.dart`

### AP2: Offene Bestellmengen und Auto-Bestellung

Ziel: Nachbestellung berücksichtigt Bestand, Meldebestand, Zielbestand, Verkaufstempo und Ware unterwegs.

Umsetzung:

- `incomingQuantityByProductId(siteId)` aus offenen Bestellungen ableiten.
- `Product.availableAfterIncoming = currentStock + incomingQty`.
- `lowStockProducts` und Nachbestellliste auf "Bestand + unterwegs" umstellen.
- Bestellvorschläge um Spalte "Unterwegs" ergänzen.
- Auto-Bestellvorschlag:
  - aus Meldebestand/Zielbestand,
  - aus `computeReorderSuggestions`,
  - aus Verkaufsfenster/Abverkäufen,
  - gruppiert nach Lieferant.
- Bestellvorlagen:
  - Standard-Wochenliste ist vorhanden; als "Bestellvorlage" sichtbar machen.
  - Optional Lieferant, Wochentag, Zielstandort, Mindestmengen.

Akzeptanz:

- Ein Artikel mit Bestand 2, Meldebestand 5, offener Bestellung 10 erscheint nicht als dringend nachzubestellen.
- Ein Artikel mit Absatztrend bekommt höheren Zielbestand-Vorschlag.
- Ein Klick erzeugt Bestellungen je Lieferant aus Vorschlag.

Betroffene Stellen:

- `lib/providers/inventory_provider.dart`
- `lib/core/reorder_suggestion.dart`
- `lib/core/order_frequency.dart`
- `lib/screens/inventory_screen.dart`
- `lib/widgets/dashboard_action_items_card.dart`

### AP3: Inventurprozesse persistent machen

Ziel: Inventur wird ein nachvollziehbarer Prozess wie bei KORONA/Tillhub.

Neue Modelle:

- `InventoryCountSession`
  - `id`, `orgId`, `siteId`, `name`, `type`, `status`, `startedAt`, `endedAt`, `responsibleUid`, `createdByUid`, `scopeCategory`, `showBookStock`, `autoPostAfterDays`.
- `InventoryCountList`
  - `id`, `sessionId`, `deviceId`, `assignedToUid`, `status`, `startedAt`, `completedAt`.
- `InventoryCountLine`
  - `productId`, `productName`, `bookStockAtStart`, `countedQty`, `note`, `countedByUid`, `countedAt`.

Inventurtypen:

- Stichtagsinventur.
- Stichprobeninventur.
- Permanente Inventur.
- Unregelmäßigkeiten zählen: negative Bestände, Nullbestand trotz Verkauf, lange nicht verkauft, starke Schwundsignale.

Funktionen:

- Session starten, pausieren, abschließen, abbrechen.
- Zähllisten je Person/Gerät.
- Listen zusammenführen.
- Differenzen prüfen.
- Abschluss verbuchen.
- CSV/Excel-Zähllisten-Import.
- PDF-Zählliste und Differenzliste.
- Bewertete Inventurliste nach EK.

Akzeptanz:

- Zwei Geräte können parallel zählen und die Listen werden summiert.
- Abschluss schreibt `stocktake`-Bewegungen und sperrt die Session.
- CSV-Import erzeugt Zähllinien und Differenzvorschau.

Betroffene Stellen:

- `lib/screens/inventur_screen.dart`
- `lib/providers/inventory_provider.dart`
- `lib/models/stock_movement.dart`
- neue Models/Repository-Methoden
- `firestore.rules`, `firestore.indexes.json`
- Tests: neue `inventory_count_session_test.dart`, Erweiterung `inventur_screen_test.dart`

### AP4: Mobile Inventur/MDE ohne separate App, aber mit App-Flow

Ziel: Tillhub Warehub/KORONA.mde als WorkTime-Flow nachbauen, ohne separate App zu pflegen.

Umsetzung:

- Scanner bekommt Modus "Inventurprozess".
- QR/Deep-Link öffnet Session/Geräteliste.
- Gerät erhält `deviceId` und schreibt in eine eigene `InventoryCountList`.
- Offline-Zählung im Hybrid-Modus lokal puffern.
- Upload/Sync mit Konfliktanzeige.
- "Abschließen" nur durch Leitung/Admin.

Akzeptanz:

- Mitarbeiter scannt Artikel, zählt Mengen, kann offline weiterzählen.
- Leitung sieht offene Geräte/Zähllisten.
- Upload erzeugt keine Bestandsbuchung, erst Abschluss verbucht.

Betroffene Stellen:

- `lib/screens/scanner_screen.dart`
- `lib/screens/inventur_screen.dart`
- `lib/models/scan_event.dart`
- `lib/services/barcode_scanner.dart`
- lokaler Speicher/Hybrid-Outbox

### AP5: Bewegungsjournal und Exporte stärken

Ziel: Tillhub-artige Nachvollziehbarkeit aller Inventarbewegungen.

Umsetzung:

- Neuer Tab "Bewegungen" oder eigener Screen:
  - Zeitraum,
  - Standort,
  - Artikel,
  - Bewegungstyp,
  - Mitarbeiter,
  - Quelle: manuell, Scanner, OktoPOS, Wareneingang, Inventur.
- Export CSV/PDF.
- Summen je Typ: Zugang, Abgang, Verkauf, Inventur, Schwund, Umlagerung.
- Detail-Link zum Artikel, Bestellung, Wareneingang oder Inventurprozess.

Akzeptanz:

- Admin kann Bewegungen eines Monats als CSV exportieren.
- Eine Inventurdifferenz ist bis zur Session/Zählliste zurückverfolgbar.

Betroffene Stellen:

- `lib/models/stock_movement.dart`
- `lib/repositories/inventory_repository.dart`
- `lib/providers/inventory_provider.dart`
- `lib/services/export_service.dart`

### AP6: DATEV-Export auf Kassenabschluss-Niveau

Ziel: Erst Tillhub-pragmatisch, später KORONA-tief.

Stufe 1: DATEV-Prüflauf

- Exportzeitraum wählen.
- Vor Export Validierung:
  - alle Kassenabschlüsse festgeschrieben,
  - alle USt-Sätze haben Erlöskonto,
  - Kostenstellen je Standort gesetzt,
  - Gegenkonto/Transitkonto vorhanden,
  - Differenzen/Einlagen/Ausgaben klassifiziert.
- Warnungen als Liste anzeigen.
- Nur fehlerfrei exportieren oder bewusst "mit Warnungen exportieren".

Stufe 2: Export-Lock/Festschreibung

- `DatevExportRun` speichern:
  - Zeitraum, Typ, Ersteller, erstellt am, Datei-Hash, Status, Notiz.
- Exportierte Kassenabschlüsse markieren.
- Re-Export erzeugt neue Version statt stiller Überschreibung.
- Optional "Festschreibekennzeichen" in EXTF-Header/Metadaten prüfen und dokumentieren.

Stufe 3: Kassennahe Buchungslogik

- Mapping nach:
  - Standort/Kostenstelle,
  - Kasse/Gegenkonto,
  - Zahlart,
  - USt-Satz/Erlöskonto,
  - Einlagen/Ausgaben/Differenzen,
  - Gutscheine/Fremdgeld, falls relevant.
- DATEV-Export aus Kassenabschlüssen statt nur aus dem allgemeinen Journal.
- Steuerberater-Profil je Organisation: SKR03/SKR04, Kontenrahmen, Berater-/Mandantennummer, Sachkontenlänge.

Akzeptanz:

- Monats-Export enthält Umsätze nach USt-Satz und Zahlart.
- Exportierte Periode ist sichtbar und nachvollziehbar.
- Eine fehlende Konto-Zuordnung blockiert den Export mit verständlicher Meldung.

Betroffene Stellen:

- `lib/core/datev_export.dart`
- `lib/core/daily_closing_posting.dart`
- `lib/screens/finance_screen.dart`
- `lib/screens/daily_closing_screen.dart`
- `lib/models/finance_models.dart`
- `lib/services/export_service.dart`
- Tests: `test/datev_export_test.dart`, `test/daily_closing_posting_test.dart`, neuer `datev_export_run_test.dart`

### AP7: Etiketten und Preisschilder

Ziel: KORONA-Funktion "Etiketten/Preisschilder aus Warenwirtschaft" als einfacher WorkTime-Nutzen.

Umsetzung:

- A4-Bogen PDF mit Artikelname, Preis, Barcode/EAN, Einheit, optional Warengruppe.
- Auswahl: einzelne Artikel, Warengruppe, geänderte Preise seit Datum, Nachbestellung.
- Später ESL-Integration aus `plan/esl-preisschilder-minew.md` andocken.

Akzeptanz:

- Nutzer kann aus markierten Artikeln ein Preisetiketten-PDF erzeugen.
- Preisänderungen der letzten 7 Tage lassen sich gezielt drucken.

## Priorisierung

| Priorität | Paket | Warum |
|---|---|---|
| P1 | AP1 Wareneingang | Höchster operativer Wert; behebt aktuelle Backlog-Lücken MHD, Ist-EK, Lieferschein. |
| P1 | AP2 Offene Bestellmengen | Verhindert Doppelbestellungen und macht Nachbestellung wirklich belastbar. |
| P2 | AP3 Inventurprozesse | Größter Sprung Richtung KORONA/Tillhub; braucht Datenmodell und Rules. |
| P2 | AP6 DATEV Prüflauf + Export-Lock | Steuerberater-/GoBD-Nähe; reduziert Risiko bei Monatsübergabe. |
| P3 | AP5 Bewegungsjournal | Macht vorhandene Daten sichtbar und exportierbar. |
| P3 | AP4 Mobile MDE | Stark für Praxis, aber erst nach persistenten Inventurprozessen sinnvoll. |
| P4 | AP7 Etiketten | Nützlich, aber nicht Kernlücke für Bestand/Inventur/DATEV. |

## Konkreter nächster Sprint

Empfohlenes Paket: AP1 + Teil von AP2.

Sprintumfang:

1. Wareneingang-Dialog mit Lieferschein-Nr., Ist-EK, MHD und Rest-schließen.
2. `ProductBatch`-Anlage beim Wareneingang.
3. Offene Bestellmenge je Artikel berechnen.
4. Nachbestellliste um "Unterwegs" erweitern.
5. Tests für Teillieferung, Rest-schließen, MHD-Charge und Nachbestelllogik.

Nicht in denselben Sprint:

- Inventurprozess-Datenmodell.
- DATEV-Export-Lock.
- Mobile MDE/Offline-Outbox.

## Entscheidungsnotizen

- WorkTime sollte DATEV zunächst als robusten Export lösen, nicht als Live-Schnittstelle. Das passt zu Tillhubs pragmatischem Ansatz und ist für kleine/mittlere Ladenbetriebe wahrscheinlich ausreichend.
- KORONA ist für Inventur das bessere Vorbild als Tillhub, weil dort Inventurtypen, Zähllisten, Import, Zusammenführen und Bewertungslisten sauber beschrieben sind.
- Tillhub ist für UX das bessere Vorbild: wenige Begriffe, klarer Prozess, mobile Bestandsaufnahme, Abschluss/Abbruch.
- WorkTime hat durch OktoPOS-Verkaufsdaten, MHD, Kühlschrank und Personal/Finanzen bereits mehr integrierte Domäne als beide Anbieterseiten im Scope zeigen. Der Ausbau sollte diese Stärke nutzen und nicht nur POS-Funktionen kopieren.
