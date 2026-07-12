# Scanner-Optimierung für den Praxis-Einsatz

**Datum:** 2026-07-11 · **Status:** code-fertig (12.07., inkl. Review-Fixes; analyze sauber, 1801 Tests grün, Web-Build ok) — offen: rules-Deploy, On-Device-Abnahme, Commit
**Anlass (Inhaber):** „Im echten Einsatz löst der Scanner den Barcode fast gar nicht — alles muss manuell eingegeben werden. Kleine und beschädigte Codes müssen erkannt werden." Plus 5 benannte Lücken: Scan-Statistik, harte Barcode-Eindeutigkeit, QR-Inhalte fachlich auswerten, geführter Wareneingang mit MHD, automatische Preisabweichung.

## Diagnose (verifiziert gegen mobile_scanner v7.2.0-Quelle)

1. **`scanWindow` ist die wahrscheinlichste Ursache fürs Nicht-Erkennen.** `MobileScannerAdapter.buildPreview` setzt auf Mobile `scanWindow: rect` (barcode_scanner.dart:270). Die native Umrechnung Widget→Textur (`_maybeUpdateScanWindow`, mobile_scanner.dart:232) rechnet beim allerersten Frame oft mit Textur-Größe 0 (Fallback-Ratio 1:1 in `ScanWindowUtils.calculateBoxFitRatio`) → falsches Analysefenster. Der gesetzte `scanWindowUpdateThreshold: 0.05` vergleicht **nur Breite/Höhe-Deltas, nie den Offset** — ein anfangs falsch platziertes Fenster wird NIE korrigiert. Bekannte Issues #1009/#633 (BoxFit.cover-Versatz). Die im alten Plan (`plan/archiv/scanner-verbesserung.md`) vorgesehene On-Device-Abnahme mit „Fallback overlay-only" fand nie statt.
2. **UPC-E fehlt in den Formaten** (`_formatsFor`: nur ean13/ean8/upcA) — gerade **kleine** Import-Artikel tragen UPC-E; die werden heute nie erkannt. Zusätzlich: `looksLikeEan` würde ein 8-stelliges UPC-E an der EAN-8-Prüfziffer scheitern lassen.
3. **Kein Zoom** für kleine/entfernte Codes (autoZoom ist Android-only und nur automatisch), **kein Foto-Fallback** (Standbild in voller Auflösung via `controller.analyzeImage` erkennt beschädigte/winzige Codes deutlich besser als der Video-Stream).
4. Statistik/Eindeutigkeit/QR-Semantik/geführter Wareneingang/Preisabgleich: existieren nicht (durch Code-Analyse bestätigt; products-Rules haben keinerlei Barcode-Constraint, `saveProduct` validiert nur orgId, MHD-Erfassung ist ein separater Button ohne Bestandsbuchung, OktoPOS hat keinen Artikel-Lese-Endpunkt).

## Meilensteine

### M1 — Erkennungs-Fix (Kern der Beschwerde)
- **scanWindow ENTFERNEN** (overlay-only Reticle, volle Frame-Analyse). MLKit/Apple Vision verkraften volle Frames problemlos; das Reticle bleibt als Ziel-Hilfe sichtbar. Eliminiert die ganze Koordinaten-Umrechnungs-Bugklasse.
- **UPC-E aufnehmen** (`BarcodeFormat.upcE` im Retail-Set) + `ean.dart`: UPC-E→UPC-A-Expansion (`upcEToUpcA`), Prüfziffern-Gate akzeptiert 8-Steller, die als UPC-E (expandiert) gültig sind; `gtinLookupVariants` liefert für UPC-E {raw, UPC-A-12, EAN-13-0+12} und für **GTIN-14** (ITF-14-Umkarton/GS1) die enthaltene GTIN-13 (Ziffern 2–13 + neu berechnete Prüfziffer).
- **Erweiterter Modus** statt reinem QR-Toggle: `ScannerTarget.extended` = zusätzlich qrCode + dataMatrix + itf14 + code128 (GS1-Kartons, Hauscodes). Standard bleibt das schnelle Retail-Set.
- **Zoom-Slider** über das Seam (`supportsZoom`/`setZoom`, `MobileScannerController.setZoomScale`) — Nutzer kann kleine Codes heranholen; autoZoom (Android) bleibt an.
- **Foto-Scan-Fallback**: neuer Button „Foto scannen" — `image_picker` (NEUE Abhängigkeit, Kamera-Still; iOS `NSCameraUsageDescription` existiert) → `controller.analyzeImage(path)` in voller Auflösung mit allen Formaten. Für beschädigte/sehr kleine Codes. Nur Android/iOS.
- detectionTimeoutMs 100 / DetectionSpeed.normal / tapToFocus bleiben; `noDuplicates`/`invertImage`/`returnImage` weiterhin bewusst NICHT (Android-Ausfälle #1252/#750).

### M2 — Scan-Statistik & Fehleranalyse
- Neues Model **`ScanEvent`** (dual serialisiert, 6 Stellen): orgId, siteId, code, outcome (`matched/multi_match/not_found/invalid_checksum`), mode (`order/book/stocktake`), source (`camera/manual/photo`), timeToHitMs, productId?, platform, createdByUid, createdAt.
- **Fire-and-forget-Logging** im Scanner (nie blockierend/werfend, Muster AuditSink): local = gecappte Liste (max 500) in SharedPreferences (`scan_events`, org-skopiert); cloud/hybrid = append-only `organizations/{orgId}/scanEvents` (+ lokaler Spiegel bei hybrid).
- **Rules:** neuer Block `scanEvents` (create: sameOrg + Feld-Allowlist + createdByUid-Self-Pin; read: canManageInventory; update/delete: false — Muster stockMovements). **Kein Composite-Index nötig** (nur orderBy createdAt).
- Pure Engine **`lib/core/scan_stats.dart`** `computeScanStats(events, {now})`: Trefferquote, Ø/Median Zeit-bis-Treffer, Fehlversuche je Code (Top-Fehlschläge), Verteilung nach Quelle/Plattform/Modus, 7/30-Tage-Fenster.
- Screen **„Scan-Statistik"** (`lib/screens/scan_statistik_screen.dart`, Manager/Admin, imperativ vom Scanner-Menü) inkl. **Duplikat-Report** (M3) und Hinweis auf viel manuelle Eingabe (= Kamera versagt in der Praxis).

### M3 — Harte Barcode-Eindeutigkeit (je Laden)
- **Enforcement in `InventoryProvider.saveProduct`** (einziger Schreibpfad von Editor+Scanner): nicht-leerer Barcode, der (inkl. `gtinLookupVariants`-Normalisierung, includeInactive) mit einem ANDEREN Produkt desselben Ladens kollidiert → `StateError` mit deutscher Meldung. **Bestandsschutz:** geprüft wird nur bei neuem Produkt oder geändertem Barcode (Altbestands-Duplikate bleiben editierbar und erscheinen im Duplikat-Report).
- Produkt-Editor (`_ProductDialog`): Validator am Barcode-Feld (freundliche Meldung vor dem Submit); Scanner-`_createNew`: bisheriger „Trotzdem anlegen"-Dialog entfällt (Neuanlage mit Duplikat ist jetzt hart verboten → Hinweis statt Wahl).
- Pure Helfer `findDuplicateBarcodes(products)` (core) für den Report. Grenze (dokumentiert): Race zweier Geräte bleibt möglich (direkter Firestore-Write per Design, Rules können Cross-Doc-Eindeutigkeit nicht prüfen) — der Report macht Rest-Duplikate sichtbar.

### M4 — QR-/GS1-Inhalte fachlich auswerten
- **`lib/core/gs1.dart`** (pure): parst GS1 Element-Strings (FNC1/GS-Separatoren, Symbology-Prefixe `]C1`/`]d2`/`]Q3`, Klammer-Notation `(01)…(17)…(10)…`), **GS1 Digital Links** (id.gs1.org-artige URLs) und nackte GTINs. Extrahiert: AI 01/02 (GTIN, 14→13-Normalisierung), 17/15 (MHD, YYMMDD inkl. `DD=00`→Monatsende), 10 (Charge), 30/37 (Menge). Ergebnis `Gs1ScanData`.
- Scanner (erweiterter Modus): QR/DataMatrix-Inhalt → GS1-Parse → GTIN-Lookup → **Trefferkarte mit MHD/Charge vorbefüllt** → ein Tap in den geführten Wareneingang (M5). Nicht-GS1-QR: Inhalt-Karte mit „Kopieren" (kein Blind-Lookup mehr wie bisher).

### M5 — Geführter Wareneingang mit MHD/Charge (EIN Ablauf)
- Neues Sheet **`showGoodsReceiptSheet`** (`lib/widgets/goods_receipt_sheet.dart`): Menge (vorbelegt) + MHD (optionales Datum) + Charge/Notiz (optional, → `ProductBatch.note`; bewusst KEIN neues Model-Feld). Ein „Buchen": `adjustStock(receipt, clientMutationId)` und — falls MHD gesetzt — `saveBatch` in einem Zug (Teil-Fehler wird explizit gemeldet: „Bestand gebucht, MHD fehlgeschlagen").
- Scanner-Buchen-Modus: „Wareneingang"-Button öffnet das Sheet (statt Sofort-Buchung); GS1-Scans befüllen MHD/Charge vor. Der separate „MHD erfassen"-Button bleibt für nachträgliche Chargen.

### M6 — Automatische Preisabweichung (gegen die Kasse)
- **Faktenlage:** OktoPOS bietet im Code keinen Artikel-Lese-Endpunkt (kein GET /articles). Die **tatsächlich kassierten Preise** liegen aber bereits in `posReceipts.lines[].unitPriceCents` (Nightly-Pull). → Abgleich **App-VK vs. zuletzt an der Kasse kassierter Preis**, rein aus vorhandenen Daten, ohne neue Function.
- Pure Engine **`lib/core/price_deviation.dart`**: `computePriceDeviations(products, receipts)` → je Produkt letzter Kassen-VK (jüngste Verkaufszeile, Refunds ignoriert), Abweichung in Cent/Prozent.
- Provider: `loadPriceDeviations({siteId, days})` über vorhandenes `getPosReceiptsInRange` (cloud-only wie posReceipts selbst).
- Screen **„Preisabgleich Kasse"** (admin, via OktoPOS-Menü der Warenwirtschaft, Gate `AppConfig.oktoposEnabled`): Liste der Abweichungen mit Aktionen „Kassen-Preis übernehmen" (`updateProductPrices` → Preisverlauf) und „App-Preis an Kasse pushen" (`pushOktoposArticles([id])`).
- „Regalpreis"/externe Preisdaten: bewusst NICHT in diesem Schritt (Regalpreis = ESL-Thema, siehe `plan/esl-preisschilder-minew.md`).

## Kopplungs-Checkliste (CLAUDE.md)
- Neues Model `ScanEvent` → 6 Stellen (kein Callable → kein JS). Neue lokale Collection `scan_events` → DatabaseService `_orgScopedCollectionKeys` + `_load/_saveCollection`.
- Neue Firestore-Collection `scanEvents` → Rules-Block; **kein** Composite-Index. `firebase deploy --only firestore:rules` nach Merge.
- Keine Änderung an Compliance/Enums/Callables/functions-index.js → Spiegel-Kopplungen nicht betroffen.
- Neue Abhängigkeit: `image_picker` (Foto-Scan). Keine neuen Permissions (Kamera existiert für mobile_scanner).
- Screens Scan-Statistik/Preisabgleich = Detail-Screens, imperativ (`Navigator.push`) — keine Router-/Tab-Kopplung.

## Definition of Done
`flutter analyze` sauber · `flutter test` komplett grün (neue Tests: ean-Erweiterungen, gs1-Parser, scan_stats, price_deviation, ScanEvent-Roundtrip, saveProduct-Eindeutigkeit, Scanner-Widget-Flows Wareneingang-Sheet/GS1/Statistik-Logging) · Review-Durchlauf. **On-Device-Abnahme bleibt offen** (Kamera nicht test-automatisierbar): Trefferzeit real, Foto-Scan, Zoom, UPC-E-Artikel.

## Review-Ergebnis (12.07., adversarial; Verify-Agenten liefen ins Session-Limit → alle 9 Befunde manuell am Code verifiziert und gefixt)

1. **GS1-Parser schluckte numerische Hauscodes** (z.B. 7-Steller „0123456" → Phantom-GTIN „23456"): Fix-Felder werden nicht mehr abgeschnitten übernommen; rein numerische Eingaben gelten nur als GS1, wenn der Parse sie VOLLSTÄNDIG konsumiert (+3 Tests).
2. **Charge ohne MHD wurde still verworfen**, obwohl die Trefferkarte automatische Übernahme versprach: Chargen-Feld im Wareneingang-Sheet jetzt immer sichtbar, Hinweis erklärt „Charge nur mit MHD" (Warnfarbe bei Eingabe ohne MHD).
3. **Kamera scannte hinter offenen Sheets/Dialogen weiter** (Sheet-Stapel, Zustandswechsel unterm Dialog): `_withDialogGuard` blockiert Kamera-Codes während JEDER modalen Interaktion des Scanners.
4. **start/stop-Race im Adapter**: ein langsames `start()` konnte ein zwischenzeitliches `stop()` überschreiben → `_lifecycleEpoch`-Guard.
5. **Hybrid-Spiegel der Telemetrie wurde nie geladen** und vom ersten Scan der Session überschrieben (hybrid ruft `_loadLocalData` nicht): `_ensureScanEventsLoaded()` + Session-Wechsel-Reset (+Hybrid-Test mit fehlschlagendem Cloud-Write).
6. **Umlagerung umging die Eindeutigkeit**: `findTransferTarget` matcht jetzt schreibweisen-tolerant (`gtinLookupVariants`), sonst entstünde am Ziel ein Variant-Duplikat direkt übers Repo.
7. **Poison-Doc-Risiko** (append-only, unlöschbar): `ScanEvent.fromFirestore` parst voll tolerant (`?.toString()` statt Casts), Rules erzwingen Typen + Größen (code ≤200, mode/source/platform ≤32, timeToHitMs number).
8. **DSGVO — QR-Inhalte**: Nicht-Produkt-QR-Inhalte (URLs/Freitext) werden NICHT mehr geloggt; Codes generell auf 128 Zeichen gecappt.
9. **DSGVO — Leistungskontrolle**: `createdByUid` wird bewusst NICHT mehr geschrieben (Statistik wertet Geräte/Quellen aus, keine Personen); Modell-Feld + Rules-Pin bleiben für die Zukunft.

## Offen / Folgeschritte
- Deploy: `firestore:rules` (scanEvents) zusammen mit dem bestehenden Deploy-Stau (`plan/deploy-checkliste.md`).
- On-Device-Abnahme im Laden (beide Geräteklassen), danach ggf. Feintuning (z.B. initialZoom).
- Später denkbar: Server-TTL/Pruning für `scanEvents`; Wareneingang-Sheet auch im Bestell-Wareneingang (`_ReceiveDialog`); echter Kassen-Artikel-GET, falls die OktoPOS-Swagger einen bietet.
