# Hermes-Paketshop — Sortieren & Ausgeben

**Plandokument · Stand: 2026-07-13 · Status: ENTWURF (alle Meilensteine offen)**

> Finalisierte Fassung. Alle berechtigten Review-Befunde (Architektur-Fit, Vollständigkeit, Domäne/UX) sind eingearbeitet; die zwei Blocker (Ausgabe-Undo/Recovery, Namensdubletten-Disambiguierung) und die vier Major-Punkte (Postgeheimnis-Rules-Ehrlichkeit, robuste DSGVO-Löschung, Audit-PII, siteId-Herkunft) sind gelöst. Änderungen ggü. Entwurf sind an den betroffenen Stellen markiert.
>
> **Revision 13.07. (final):** Betreiber-Entscheidungen eingearbeitet (§0) — (1) **alle aktiven Mitarbeiter** zugriffsberechtigt, (2) **dauerhaftes Kunden-Namensregister** (`ParcelCustomer`), (3) **volle, unbefristete Aufbewahrung beider Ebenen — KEINE automatische Anonymisierung/Löschung** (nur manuelle Löschung auf Wunsch, Art. 17/21), (4) Überfällig **6 Kalendertage**. Der Betreiber bestätigt Vertrags-/AVV-Deckung + Zulässigkeit des Registers und verpflichtet das Personal aufs Datengeheimnis. **Folge:** v1 braucht **keine Cloud Function** (reiner Firestore-CRUD). Das erhöht die Datenschutz-Last erheblich; das Restrisiko ist als **ausdrückliche, informierte Betreiber-Entscheidung** in §13 dokumentiert.

## 0. Betreiber-Entscheidungen (13.07.2026, final)

Vom Betreiber bestätigt und in den folgenden Abschnitten eingearbeitet:

1. **Zugriff:** **Alle aktiven Mitarbeiter** dürfen annehmen/ausgeben (`canManageParcels => isActive`, `canViewParcels => isActive`). **Auflage:** Personal schriftlich auf das **Daten-/Postgeheimnis** (§ 206 StGB) verpflichten. (Ändert die ursprünglich empfohlene Manager-Beschränkung.)
2. **Stammkunden-Wiedererkennung: JA** → neues, dauerhaftes, **name-only** Kunden-Namensregister (`ParcelCustomer`, §6.3) speist den Typeahead auch für Kunden **ohne** aktuell offenes Paket. (Ändert die ursprünglich empfohlene „nur offene Pakete, keine Historie"-Lösung.)
3. **Aufbewahrung: KEINE automatische Anonymisierung/Löschung.** Sowohl das Namensregister als auch die **Paket-Vorgänge** (inkl. `trackingCode`, `senderName`, Empfänger-Snapshot, Abholverlauf) bleiben **dauerhaft**. Gelöscht wird **nur manuell auf Wunsch** (Art. 17/21: „Kunde löschen" / „Vorgang löschen"). Ein Anonymisierungs-Mechanismus ist als **optionaler, standardmäßig ausgeschalteter** Schalter vorgesehen, falls die Rechtslage später doch eine Frist verlangt. (Ändert den ursprünglichen Purge **und** den Zwei-Ebenen-Anonymisierungs-Kompromiss.)
4. **Überfällig:** nach **6 Kalendertagen** (rein interne Warnung, keine Zwangs-Rücksendung).

**Betreiber-Bestätigungen (§0):** (1) Hermes-Vertrag/AVV erlaubt die parallele Speicherung. (2) Das dauerhafte Namensregister ist aus Betreibersicht zulässig. (3) Der Betreiber verpflichtet alle Mitarbeiter aufs Post-/Datengeheimnis.

> ⚠️ **Restrisiko (ausdrückliche, informierte Betreiber-Entscheidung):** Die **unbefristete** Speicherung von Postgeheimnis-Daten steht in Spannung zu Art. 5 Abs. 1 lit. e (Speicherbegrenzung); der breite Zugriffskreis erhöht die Last zusätzlich. Der Betreiber hat (1)/(2) bestätigt und übernimmt die Verantwortung. **Unabhängig davon gesetzlich Pflicht** (Art. 5 Abs. 2 Rechenschaft): dokumentierte **Interessenabwägung + VVT (Art. 30)** und funktionierende **Löschung auf Wunsch** — diese Nachweise sind im Plan (§13) als Auflage geführt. Empfehlung: (1)/(2) vom DSB/Anwalt **schriftlich** bestätigen lassen.

## 1. Kurzfazit

Neues, org-skopiertes CRUD-Modul für den Hermes-ProfiPaketShop im Laden **Tabak Börse** (Kiel). Es ist ein **rein internes Sortier- und Wiederfinde-Werkzeug** für das Personal: Paket per Barcode annehmen → an ein festes Fach per **Fach-Barcode-Scan** binden → Empfänger zuordnen (Typeahead aus dem **dauerhaften Kunden-Namensregister** + offenen Paketen, sonst neu anlegen); beim Abholen Paket per Barcode/Kundenhandy-Code oder Namenssuche finden, Fach + gebündelte Pakete des Kunden anzeigen und mit **einem Tap „Ausgegeben"** intern abschließen (Zeitstempel + Mitarbeiter automatisch via AuditSink), inkl. **Rückgängig-Funktion** bei Fehl-Tap. Vorbild ist DHLs Lager-App PLAPP (Paket↔Regalplatz per Doppelscan).

**Ehrliche Einordnung des „besser als DHL"-Anspruchs (korrigiert):** Wir sind beim **Wiederfinden/Ausgeben** besser (Fach-Bindung + Freifach-Führung + Fremd-Doppelbelegungs-Warnung + Mehrpaket-Bündelung + Fuzzy-Namenssuche + Kundenhandy-Code). Beim **Einlagern** sind wir **nicht** schneller als DHL: DHL zieht den Empfängernamen aus dem Zentralsystem-Scan, wir haben keine Namensauto­füllung → das Personal tippt den Empfänger vom Etikett ab. Da Einlagern Back-Office ist (Kunde nicht anwesend), ist Tempo dort weniger kritisch; die Tipp-Last ist dennoch der reale Flaschenhals einer 20–40-Paket-Anlieferung (Milderung: OCR als spätere Option, s. §9).

Baut auf den bestehenden Bausteinen Scanner-, Warenwirtschaft- und Kontakte-Modul auf. **Ohne Callables, ohne Cloud Functions** — reiner Firestore-CRUD (kein Blaze-Job in v1). Es wird nichts automatisch anonymisiert/gelöscht; Löschung nur **manuell auf Wunsch** (Betreiber-Entscheidung §0; Restrisiko in §13 dokumentiert).

## 2. Problem & Ziel

**Schmerz:** Im Hermes-Shop stapeln sich täglich ~8–30 (in Spitzen mehr) Pakete auf ≤2 m². Ohne Ortungssystem sucht das Personal beim Abholen händisch — langsam, fehleranfällig, Namensbeschriftung auf Paketseite, ständige Regal-Neueinteilung bei schwankender Menge. Der Betreiber **haftet persönlich bei Fehlausgabe**, findet aber kein Paket zuverlässig wieder.

**Ziel v1:**
- **Sortieren/Einlagern schlank:** Paket-Barcode scannen → Fach-Barcode scannen (Kamera bleibt in einer Session, s. §5a) → Empfänger tippen. Kein Beschriften, keine physische Sortierlogik (chaotische Einlagerung wie DHL PLAPP).
- **Wiederfinden in Sekunden:** Barcode-Scan (Paket **oder Kundenhandy-Code**) **oder** Fuzzy-Namenssuche → System zeigt Fach + alle Pakete des Kunden gebündelt.
- **Ausgeben mit Sicherheitsnetz:** finden → „Ausgegeben" (ein Tap) mit **Undo** (Rückgängig). Zeitstempel + Mitarbeiter automatisch (Rechenschaft via AuditSink, kein Nachweis der Empfängeridentität — bewusst, s. §13).
- **Überblick:** Fach-Auslastung (frei/belegt), Überfällig-/Ladenhüter-Liste (konfigurierbare Frist), Reverse-Lookup „was liegt in Fach X?", **Tages-Reconciliation** (heute angenommen / ausgegeben) zum Abgleich mit dem offiziellen Hermes-Gerät, **Rücklauf-Sammelaktion**.

**Abgrenzung (ehrlich):** Unser Modul ersetzt **NICHT** den offiziellen Hermes-Prozess. Das offizielle Annehmen/Ausgeben (Hermes-Scanner/PADEA, Ausweisprüfung, Unterschrift) macht das Personal weiterhin am Hermes-Gerät. Wir sind ein **paralleles internes Bestandsregister**. Die UI kommuniziert das per persistentem Hinweisbanner unmissverständlich.

## 3. Wie macht es DHL/Hermes (Ist-Vorbild)

| Prozess | DHL/Hermes heute | Was wir übernehmen | Was wir bewusst weglassen / besser machen |
|---|---|---|---|
| **Annahme** | Android-Gerät scannt Paket/QR, zeigt Sendungsnr./Empfänger (aus Zentralsystem), druckt Beleg. | Barcode-Scan als **interner Schlüssel** + manuell getippter Empfängername. | Kein Druck/Label. **Ehrlich:** ohne Zentralsystem keine Namensauto­füllung → langsamer im Anlegen (Back-Office, unkritisch). |
| **Sortieren/Wiederfinden** | **DHL PLAPP:** Sendungsnr. scannen → Regalplatz-Strichcode scannen → App verknüpft beides; chaotische Einlagerung. Wiederfinden per Sendungsnr. → Regalplatz. | **1:1** unser Fach-Barcode-Flow (Paket-Scan → Fach-Scan → Bindung; Rücksuche per Paket → Fach). Validierter Best-Practice. | **Aktive Freifach-Führung**, **Namenssuche**, **Reverse-Lookup**, **Mehrpaket-Bündelung** — hier sind wir besser. |
| **Ausgabe** | Kunde bringt Benachrichtigung + Sendungsnr. + **Ausweis**; Personal prüft ID (Haftung!), scannt, lässt unterschreiben. | Schneller interner Abschluss + Audit + **Undo**. Optional **Code vom Kundenhandy scannen**. | **Kein** ID/PIN/Unterschrift/Abholcode in v1 (Hermes verantwortet Legitimation). Haftungslücke offen dokumentiert (§13). |
| **Lagerfrist/Rücklauf** | Paketshop-Frist in **Werktagen** (Quellen widersprüchlich: 7/10 WT, teils 14 KT), danach Rücklauf an Absender. | **Überfällig-Warnung** vor Fristablauf + **Rücklauf-Sammelaktion**. | **Keine** feste Frist hardcoden, **kein** Auto-Rücklauf — Liste rein **intern/beratend**. Frist konfigurierbar, konservativer Default. |
| **Kundenbenachrichtigung** | Hermes benachrichtigt per E-Mail. | — | v1 benachrichtigt **nicht** (nur intern). Spätere Ausbaustufe. |

**Nicht öffentlich verifizierbar:** DHLs Namenssuche/Überfällig-Handling sind nicht dokumentiert → unsere Name-Suche/Überfällig-Features sind Eigenentwicklung (machbar, aber nicht als „so macht es DHL" verkaufen).

## 4. Scope v1 (bestätigt) + Nicht-Ziele

**In Scope (freigegeben 2026-07-13):**
- Nur **Hermes**; `carrier`-Feld ab v1 vorhanden (fix `hermes`), erweiterbar.
- Nur **Standort Tabak Börse** (siteId-Pflichtfeld; Strichmännchen ist kein Hermes-Shop). Herkunft der siteId: aus `TeamProvider.sites`, aufgelöst über `hermesSiteId` im Config-Doc (s. §6.6/§7).
- Rein intern: **keine** Kundenbenachrichtigung.
- Ausgabe = **einfach bestätigen** (ein Tap „Ausgegeben") **+ Undo/Rückgängig** + Doppelabschluss-Schutz.
- **Optionaler Absender/Shop** (`senderName`, z. B. „Amazon") als Disambiguator bei Namensgleichheit **(neu, Blocker-Fix)**.
- **Zugriff für alle aktiven Mitarbeiter** (`canManageParcels => isActive`, `canViewParcels => isActive`); Personal aufs Daten-/Postgeheimnis verpflichtet **(Betreiber-Entscheidung §0)**.
- **Dauerhaftes Kunden-Namensregister** `ParcelCustomer` (name-only) für den Typeahead über Besuche hinweg **(Betreiber-Entscheidung §0)**.
- **Feste Fächer mit eigenen Barcodes**, manuell angelegt; Paket↔Fach per Fach-Scan; Freifach-Vorschlag + Fremd-Doppelbelegungs-Warnung; Mehrpaket-Bündel je Kunde erlaubt.
- Einlagern-, Ausgeben-/Suchen-, Fach-Verwaltungs-Flow; Überfällig-/Auslastungs-Übersicht; **Rücklauf-Sammelaktion**; **Tages-Reconciliation**; **Ad-hoc-Nacherfassung** ungetrackter Pakete.
- **Config-Doc** `config/paketshopSettings` (Überfällig-Frist, `hermesSiteId`, optionaler Anonymisierungs-Schalter **Default aus**) **(neu)**.
- **Keine Cloud Functions in v1** — reiner Firestore-CRUD, kein Blaze-Job. Auto-Anonymisierung bewusst ausgeschaltet (Betreiber-Entscheidung §0).
- Drei Storage-Modi (local/cloud/hybrid), offline lauffähig.

**Explizite NICHT-Ziele (später/nie):**
- ❌ Multi-Carrier (DHL/DPD/GLS/UPS) — nur Datenmodell erweiterbar halten.
- ❌ Kundenbenachrichtigung (SMS/E-Mail/Push/Abholcode-Versand).
- ❌ Unterschrift, PIN, Abholcode, Ausweisprüfung, Empfänger-Identitätsnachweis.
- ❌ Auto-Rücklauf / Fristdurchsetzung (Hermes-Prozess).
- ❌ **Callables / Cloud Functions** in v1 (reiner Firestore-CRUD; kein snake_case in `functions/index.js`).
- ❌ **Automatische Anonymisierung/Löschung** (Betreiber-Entscheidung §0) — Löschung nur manuell auf Wunsch; Anonymisierung als optionaler, standardmäßig ausgeschalteter Schalter für später vorgesehen.
- ❌ Drucker/Label-Erzeugung.
- ❌ Personenbezogenes Freitextfeld (DSGVO, §13).
- ❌ Größensortierung/Fach-Kapazitätsmodell (`sizeHint` v1 weggelassen — bewusste Einschränkung, s. §14/§15).
- ❌ Multi-Site-Filter/-Index (nur ein Standort; siteId wird trotzdem geführt).
- ❌ OCR-Namenserkennung (spätere Option, s. §9).

## 5. Kern-Workflows (Schritt für Schritt, mit UX & Fehlerfällen)

Gemeinsames Fundament: das **neu zu extrahierende** Widget/Helfer **`showBarcodeScanSheet(context, {target, title}) → Future<String?>`** (aus `ScannerScreen` gehobene Kamera-/Dedup-/Guard-Logik, s. §7.4). Es liefert den **rohen** Code (keine Retail-Prüfziffer-Validierung), bietet **Torch/Zoom/Foto-Fallback + manuelle Eingabe** und läuft mit `ScannerTarget.extended` (dekodiert bereits ean13/ean8/upcA/upcE + qr + dataMatrix + itf14 + code128 — **kein neuer `logistics`-Target nötig**).

### (a) Einlagern / Sortieren — Scan-Sequenz minimal (korrigiert: Fach vor Name)
Die Kamera bleibt für **Paket→Fach in einer Session** offen; der Name (zweihändige Tipp-Eingabe) kommt zuletzt.
1. **Einstieg:** Hub-Kachel „Paket annehmen" → `PaketEinlagernScreen`. Großer Button „Paket scannen".
2. **Paket-Barcode scannen** → roher Code als `trackingCode`.
   - *Doppelscan:* Code existiert bereits als **offenes** Paket → Warn-Sheet „Bereits eingelagert (Fach A2, seit 11.07.)". „Trotzdem neu" / „Zum bestehenden springen". (Duplikat-Schutz via clientseitigem Lookup wie `productByBarcode`, **ohne** `isPlausibleRetailCode`-Gate.)
   - *Bereits ausgegeben:* Hinweis „Wurde am … ausgegeben" → optional Wieder-Einlagern.
   - *Kein/kaputter Barcode:* manuelle Eingabe im Scan-Sheet oder „ohne Barcode" → Paket bekommt generierte interne ID, `trackingCode == null`.
3. **Fach-Barcode scannen** (bindet Paket an Fach) — **namensunabhängig**, direkt nach dem Paket-Scan, gleiche Kamera-Session:
   - System **schlägt vorab ein freies Fach vor** (nächstes freies, sortiert); Personal kann Vorschlag oder ein anderes Fach scannen.
   - *Fach unbekannt:* „Fach nicht registriert" → „Fach jetzt anlegen?" (übernimmt Barcode) oder Abbrechen.
   - *Fremd-Doppelbelegung:* **harte Warnung** „Fach A2 enthält bereits Paket von *Meier*. Trotzdem hinzufügen?" → nur bewusst bestätigen.
   - *Gleicher Empfänger, weiteres Paket ins selbe Fach:* **erlaubt, keine Warnung** (Mehrpaket-Bündel).
4. **Empfänger zuordnen (Typeahead):** Eingabefeld „Empfänger". Vorschläge aus dem **dauerhaften Kunden-Namensregister** (`ParcelCustomer`, §6.3) **plus** aktuell offenen Paketen; Vor-/Nachname-Reihenfolge egal, Tippfehler-/Umlaut-/ß-tolerant (Fuzzy). Stammkunden werden damit **über Besuche hinweg** wiedererkannt (Betreiber-Entscheidung §0). Nur ein **echter Erstkunde** hat keinen Treffer → voller Name wird getippt und dabei ins Register aufgenommen.
   - *Kunde existiert nicht:* Inline „**+ Neu anlegen**" öffnet Mini-Sheet nur mit **Vorname/Nachname** → sofort übernommen **und als `ParcelCustomer` im Register angelegt** (Dublettenprüfung gegen `nameLower`). **Keine** Vermischung mit dem allgemeinen CRM (`ContactProvider`) — eigenes, leichtes Paket-Kundenregister (s. §6.3).
   - *Optional:* Feld **„Absender/Shop"** (`senderName`, z. B. „Amazon") — dient als Disambiguator bei Namensgleichheit (s. §5b3).
5. **Bestätigung:** grünes Feedback (`ScanFeedback.success` + visueller Blitz), **Toast** „Paket für *Schmidt* in Fach **A2** eingelagert". Status = `eingelagert`, `arrivedAt = now`, `siteId`/`siteName` = aufgelöster Hermes-Standort. **Audit-Summary personenfrei:** „Paket eingelagert (Fach A2)" — **nie** mit Empfängernamen (s. §14).
6. **Flüssiger Wiederholmodus:** danach direkt „Nächstes Paket scannen" (Kamera bleibt aktiv, 1000 ms-Dedup verhindert Doppelerfassung).

### (b) Ausgeben
1. **Einstieg:** Hub-Kachel „Paket ausgeben" → `PaketAusgebenScreen`. Gleichwertige Einstiege: **„Paket scannen"**, **„Code vom Kundenhandy scannen"** (neu — Hermes-Benachrichtigung liest `mobile_scanner` als Display-QR/Barcode zuverlässig) und **Suchfeld (Name / Teil-Sendungsnr.)**.
2. **Weg A — Barcode/Handy-Code:** scannen → direkter Treffer via `findParcelByCode` (exakt + Suffix/Präfix, letzte 4–6 Stellen).
3. **Weg B — Name:** Tippen → Fuzzy-Trefferliste über **offene** Pakete.
   - *Namensdublette (Blocker-Fix):* Trefferliste zeigt disambiguierende Zusatzinfo **inkl. Absender/Shop** (`senderName`), Fach, Anzahl Pakete und Sendungsnr.-Suffix — „*Schmidt* · Amazon · Fach A2 · 2 Pakete · …4711". Der Absender ist die natürliche Tresen-Ansage („das von Amazon") und stärkster In-Store-Unterscheider neben dem Kundenhandy-Code (Weg A).
4. **Ergebnis (gebündelt):** Karte zeigt **alle offenen Pakete des Kunden** + **alle Fächer** („*Schmidt* — 3 Pakete: Fach **A2** (2), **B1** (1)"). Einzeln oder gemeinsam auswählbar.
5. **„Ausgegeben" bestätigen:** ein Tap (Einzel oder „Alle ausgeben").
   - Bei **>1 Paket** kurze Bestätigung „3 Pakete ausgeben?" (schützt vor Massen-Fehl-Tap).
   - **Prominenter Hinweisbanner:** „Offizielle Hermes-Ausgabe (Ausweis + Unterschrift am Hermes-Gerät) zusätzlich zwingend."
   - Status → `abgeholt`, `handedOutAt = now`. **`compartmentId` bleibt am Paket** (wird NICHT geleert) — die Fach-Belegung ist **abgeleitet aus offenen Paketen**, ein `abgeholt`-Paket zählt einfach nicht mehr mit. **Präzisierung (korrigiert):** ein Fach wird erst frei, wenn **kein offenes Paket mehr darauf zeigt** — bei Teilausgabe bleibt es belegt.
   - Audit-Summary personenfrei: „Paket ausgegeben (Fach A2)".
   - *Fehler:* schon abgeholt → Hinweis, kein Doppelabschluss.
6. **Undo / Rückgängig (Blocker-Fix):** direkt nach dem Handout kurzlebige **Undo-Snackbar** („Rückgängig") **und** dauerhaft im `PaketDetailSheet` die Aktion „Doch nicht abgeholt". Setzt `status = eingelagert`, `clearHandedOutAt`, das Paket erscheint durch das erhaltene `compartmentId` **automatisch wieder in seinem Fach**. Audit: „Ausgabe rückgängig (Fach A2)".
   - *Konflikt:* wurde das Fach zwischenzeitlich fremd belegt → dieselbe Fremd-Doppelbelegungs-Warnung wie beim Einlagern; alternativ „anderes Fach scannen".
7. **Nicht gefunden / Laufkundschaft (neu):** liefert die Suche nichts → leerer Zustand „Nicht im System — Anlieferung evtl. noch nicht einsortiert". Aktion **„Paket ad hoc erfassen"** (Einlagern-Flow) bzw. **„Ohne Systemtreffer ausgeben (nacherfassen)"**, damit die Bestandszahlen konsistent bleiben.

### (c) Fach-Verwaltung (Fächer mit Barcode anlegen)
1. **Einstieg:** Hub-Kachel „Fächer" → `FachVerwaltungScreen` (Liste + Auslastung).
2. **Fach anlegen:** „+ Fach" → Sheet: **Label** (z. B. „A2", frei) + „**Fach-Barcode scannen**" (bindet physisches Bin-Label) oder manuell.
   - *Barcode bereits vergeben (je Standort):* harte Ablehnung „Barcode gehört zu Fach *B1*" (Eindeutigkeit je `siteId`, clientseitig geprüft wie Artikel-Barcode).
3. **Reverse-Lookup:** in der Liste oder per „Fach scannen" → „Fach A2: 2 Pakete (*Schmidt*)" bzw. „leer". Für Inventur/Aufräumen.
4. **Fach deaktivieren/löschen:** nur wenn leer; belegtes Fach nicht löschbar (Guard). Umbenennen aktiver Fächer aktualisiert den `compartmentLabel`-Cache aller offenen Pakete des Fachs (s. §14-Footgun).

### (d) Konsolidiert: Fehlerfälle & Recovery (neu — Task fragt diese Fälle explizit ab)

| Fall | Verhalten |
|---|---|
| **Fälschlich als abgeholt getippt** | Undo-Snackbar sofort + „Doch nicht abgeholt" im Detail → `status=eingelagert`, `clearHandedOutAt`, Fach re-gebunden über erhaltenes `compartmentId`; Konflikt bei Fremdbelegung → Warnung/neues Fach (§5b6). |
| **Systemtreffer, Fach aber physisch leer** | Detail zeigt gebundenes Fach; „Umlagern (anderes Fach scannen)" korrigiert die Bindung; „Als Rücklauf markieren" wenn verschollen. |
| **Paket physisch da, nicht im System** | Leer-Zustand + „Ad hoc erfassen" / „nacherfassen" (§5b7). |
| **Fach-Mismatch beim Einlagern** | Fremd-Doppelbelegungs-Warnung; bewusste Bestätigung nötig. |
| **Massen-Fehl-Tap „Alle ausgeben"** | Vorab-Bestätigung „N Pakete ausgeben?" + Undo-Snackbar deckt den Sammel-Fall. |

## 6. Datenmodell

**Drei** neue Modelle (`ParcelShipment`, `ShelfCompartment`, `ParcelCustomer`) + ein Config-Doc. Alle Felder nach der **Zwei-Serialisierungs-Regel** (6 Stellen: `toFirestoreMap` camelCase+Timestamp **ohne** `id` · `fromFirestore(id,map)` · `toMap` snake_case+ISO **mit** `id` · `fromMap(map)` · `copyWith` + `clearX` je nullable). Parser tolerant über `core/firestore_num_parser.dart` + `FirestoreDateParser.readDate`/`readLocalDate`. **Vorlage: `lib/models/customer_order.dart`.** Kein Callable → **kein** snake_case-Parsing in `functions/index.js` (der Anonymisierungs-Job liest die Firestore-Docs direkt in camelCase per Admin SDK).

### Empfänger: Namens-Snapshot am Vorgang **+ dauerhaftes Register `ParcelCustomer`** (Zwei-Ebenen, Betreiber-Entscheidung §0)
Statt der ursprünglich empfohlenen reinen Einbettung ein **Zwei-Ebenen-Modell**:
- **Ebene Paket-Vorgang:** `ParcelShipment` trägt einen **Namens-Snapshot** (`recipientFirstName/LastName`) — robust für Anzeige/Bündelung und **unabhängig anonymisierbar** (wird nach Frist geleert, §13).
- **Ebene Kunde:** `ParcelCustomer` (§6.3) ist das **dauerhafte, name-only Register** — speist den Typeahead über Besuche hinweg und **überlebt** die Anonymisierung. Verknüpfung über optionales `parcelCustomerId` am Vorgang.

**Warum NICHT `Contact`/`ContactProvider`:** (1) Paketempfänger sind **keine** Ladenkunden — das allgemeine CRM würde mit Wegwerf-Fremden geflutet, Zweckbindung/Löschung verschwimmen. (2) **Postgeheimnis** (§ 64 PostG, § 206 StGB) verlangt strenge Zweckbindung → getrenntes, minimales Register mit **eigener** Löschkontrolle statt Vermischung. (3) Ein leichtes Eigen-Register bleibt einfacher anonymisierbar/löschbar.
> **Rechtliche Folge (Betreiber-Entscheidung §0):** Das dauerhafte Register ist ein persistentes Personendatenregister → braucht Rechtsgrundlage (berechtigtes Interesse) + **Widerspruchs-/Löschmöglichkeit je Kunde** (Art. 17/21) + Datenschutz-Aushang (§13). Wiedererkennungs-Komfort wurde bewusst über maximale Datensparsamkeit gestellt.

### 6.1 `ParcelShipment` (Paket) — `lib/models/parcel_shipment.dart` **(neu)**
```
String   id
String   orgId                 // Pflicht, orgId-Pin in Rules
String   siteId                // Pflicht (Tabak Börse); Herkunft s. §7 (aus TeamProvider.sites via hermesSiteId)
String?  siteName              // Cache (clearSiteName) — im Mutator frisch gesetzt, nicht via copyWith durchreichen
String   carrier               // v1 fix 'hermes' (String, kein Enum-Zwang → additiv erweiterbar)
String?  trackingCode          // roher Scan-String, KEINE Formatvalidierung (clearTrackingCode)
String   recipientFirstName    // minimaler Feldsatz
String   recipientLastName
String   recipientNameLower    // ABGELEITET: "<last> <first>".toLowerCase(); IMMER neu berechnen (§14)
String?  senderName            // NEU: Absender/Shop (Disambiguator), optional (clearSenderName)
String?  parcelCustomerId      // NEU: FK auf ParcelCustomer.id (clearParcelCustomerId); Snapshot bleibt am Vorgang
ShipmentStatus status
String?  compartmentId         // FK auf ShelfCompartment.id (clearCompartmentId); bleibt bei Ausgabe erhalten
String?  compartmentLabel      // Cache (clearCompartmentLabel); bei Fach-Umbenennung aktiv nachziehen (§14)
DateTime arrivedAt             // Einlagerzeitpunkt (Überfällig-Basis) — Pflicht
DateTime? handedOutAt          // (clearHandedOutAt)
DateTime? returnedAt           // (clearReturnedAt)
DateTime? createdAt            // serverTimestamp bei Neuanlage
```
- **KEIN** personenbezogenes Freitext-/Notizfeld (DSGVO, §13). `sizeHint` (klein/mittel/groß) bewusst **weggelassen** — Fach-Kapazität/„Fach voll" ist v1 nicht modelliert (Einschränkung §14/§15).
- `recipientNameLower` ist Sort-/Suchschlüssel (wie `nameLower` bei Product) → `orderBy('recipientNameLower')`, kein Composite-Index nötig.
- **Aufbewahrung (§0/§13):** in v1 **keine automatische Anonymisierung/Löschung** — Vorgänge bleiben dauerhaft. Manuelles „Vorgang löschen" (`deleteParcel`) und „Kunde löschen" (§6.3) auf Wunsch (Art. 17/21). Der optionale, standardmäßig ausgeschaltete Anonymisierungs-Schalter würde — falls aktiviert — `trackingCode`/`senderName`/`recipientFirstName/LastName`/`recipientNameLower` leeren und `parcelCustomerId` entkoppeln; das Register bliebe unberührt.

**Enum `ShipmentStatus`** (`.value` snake_case, deutsches `.label`, `fromValue` mit Default-Branch, Getter `isOpen`/`isClosed`):
| Dart | .value | .label |
|---|---|---|
| `eingelagert` | `stored` | „Eingelagert" |
| `abgeholt` | `handed_out` | „Abgeholt" |
| `zurueck` | `returned` | „Zurück (Rücklauf)" |

- **„Überfällig" ist KEIN Status**, sondern ein **abgeleiteter Zustand** (`arrivedAt` + konfigurierbare Frist < now && status == eingelagert). Kein DB-Feld, keine nächtliche Statuspflege. `fromValue`-Default = `eingelagert`.

### 6.2 `ShelfCompartment` (Fach) — `lib/models/shelf_compartment.dart` **(neu)**
```
String   id
String   orgId
String   siteId
String?  siteName              // (clearSiteName)
String   label                 // "A2" (frei)
String   labelLower            // orderBy/Suche
String   barcode               // Fach-Bin-Barcode, je siteId eindeutig (clientseitig geprüft)
bool     active                // deaktivierbar statt löschen
DateTime? createdAt
```
- Belegung wird **NICHT** am Fach gespeichert (kein `occupied`-Feld), sondern **abgeleitet** aus `ParcelShipment.compartmentId` der **offenen** Pakete → keine Konsistenz-Duplikation, N Pakete/Fach automatisch, Teilausgabe hält belegt.

### 6.3 `ParcelCustomer` (Kunden-Namensregister, dauerhaft) — `lib/models/parcel_customer.dart` **(neu, Betreiber-Entscheidung §0)**
```
String   id
String   orgId
String   siteId                // Hermes-Standort (Tabak Börse)
String   firstName
String   lastName
String   nameLower             // ABGELEITET "<last> <first>".toLowerCase(); orderBy + Dublettenschlüssel
DateTime? firstSeenAt          // serverTimestamp bei Anlage
DateTime? lastSeenAt           // bei jedem neuen Paket aktualisiert (Aufräum-Heuristik)
```
- **Name-only.** KEINE Adresse/Telefon/E-Mail, KEIN Paket-/Abholverlauf am Kunden (der lebt am `ParcelShipment`) — das minimal mögliche Personendatum für den Zweck „Wiedererkennung".
- **Speist den Typeahead** (§5a-4) via `parcelCustomersMatching(query)` (Fuzzy, `lib/core/fuzzy_name_match.dart`). Erstkunden werden hier angelegt (Dublettenprüfung gegen `nameLower`), bekannte beim erneuten Einlagern nur `lastSeenAt`-aktualisiert.
- **Dauerhaft** (§0). **Eigene Löschkontrolle** „Kunde löschen" (Art. 17/21-Widerspruch, §13) — entkoppelt `parcelCustomerId` an offenen Paketen. Von einem (optionalen, später aktivierbaren) Vorgangs-Anonymisierungs-Lauf wäre das Register nicht betroffen.
- Zwei-Serialisierung wie §6.1 (6 Stellen, `clearX` je nullable); `nameLower` im Mutator immer frisch berechnen (§14).

### 6.4 Optional: append-only `ParcelEvent` — **v1 NICHT nötig**
Rechenschaft läuft über **AuditSink**. Ein separates `parcelEvents`-Ledger (nach `stockMovements`-Muster) ist erst bei feinkörniger, nicht-admin-lesbarer Historie relevant → spätere Ausbaustufe.

### 6.5 Firestore-Pfade & Indexes
- `organizations/{orgId}/parcelShipments/{id}`
- `organizations/{orgId}/shelfCompartments/{id}`
- `organizations/{orgId}/parcelCustomers/{id}`
- **Composite-Indexes: KEINE nötig in v1.** Die drei Collections streamen org-weit mit reinem `orderBy('recipientNameLower')` / `orderBy('labelLower')` / `orderBy('nameLower')` (Single-Field, automatisch). Kein `where(siteId)+orderBy(anderes Feld)`-Query. Der Anonymisierungs-Job iteriert die (kleine) Org-Collection und filtert **in-memory** → **kein** Index. Falls je ein site-gefilterter `where('siteId')+orderBy('arrivedAt')`-Query gebaut wird → `(siteId ASC, arrivedAt DESC)`-Composite-Index nach `stockMovements`-Muster ergänzen + deployen.

### 6.6 Config: `config/paketshopSettings` **(neu — Speicherort der Schwellen)**
Ein Config-Singleton (Doc-ID fix `paketshopSettings`), gedeckt vom generischen `config/{configId}`-Rules-Block (sameOrg-read/admin-write). Lokaler Fallback `local_v2/paketshop_settings`.
```
int?    overdueFristTage           // Default 6 (Kalendertage, Betreiber-Entscheidung §0)
bool?   anonymisierungAktiv        // Default FALSE (§0: keine Auto-Anonymisierung); optionaler Schalter für später
int?    anonymisierungFristTage    // nur wirksam wenn anonymisierungAktiv == true (Vorgangs-Anonymisierung §13)
String? hermesSiteId               // aktiver Hermes-Standort (Tabak Börse) → siteId-Auflösung §7
```
Konservative In-Memory-Defaults, wenn Doc/Feld fehlt (`anonymisierungAktiv` = false). Geladen von `ParcelProvider` (kleiner Einzel-Doc-Read in `updateSession`, mit lokalem Fallback); `overdueFristTage` fließt in `overdueParcels(frist)`. Die Anonymisierungs-Regel wird als purer Helfer implementiert + getestet, ist in v1 aber **deaktiviert** (nur manuelle Löschung aktiv).

## 7. Architektur- / Provider-Integration

### 7.1 Repository-Pattern (DIP) — Vorlage `InventoryRepository`
- `abstract interface class ParcelRepository` (`lib/repositories/parcel_repository.dart`, **neu**): `watchParcels(orgId)`, `saveParcel(ParcelShipment) → Future<String>`, `deleteParcel({orgId,id})`, `watchCompartments(orgId)`, `saveCompartment(ShelfCompartment) → Future<String>`, `deleteCompartment({orgId,id})`, **`watchCustomers(orgId)`, `saveCustomer(ParcelCustomer) → Future<String>`, `deleteCustomer({orgId,id})`** (Register), **`anonymizeShipment(ParcelShipment) → Future<void>`** (nur wenn optionaler Anonymisierungs-Schalter aktiv — in v1 **aus**, §13).
- `class FirestoreParcelRepository implements ParcelRepository` (`lib/repositories/firestore_parcel_repository.dart`, **neu**): org-skopierte Getter `_organizationDoc(orgId).collection('parcelShipments')` / `...('shelfCompartments')` / `...('parcelCustomers')`. Save: `docRef = id==null ? col.doc() : col.doc(id); await docRef.set({...item.copyWith(id: docRef.id).toFirestoreMap(), if new 'createdAt': FieldValue.serverTimestamp()}, SetOptions(merge:true)); return docRef.id;`. `watch* = orderBy(...).snapshots().map(fromFirestore)`.
- In `FirestoreService`: **privates** `late final ParcelRepository _parcelRepository = FirestoreParcelRepository(firestore: _firestore);` **+ öffentlicher Getter** `ParcelRepository get parcelRepository => _parcelRepository;` (Muster `_inventoryRepository`/`inventoryRepository` — **korrigiert**, kein öffentliches Feld). Pfade nie hardcoden.

### 7.2 `ParcelProvider` (ChangeNotifier) — Vorlage `InventoryProvider`, `lib/providers/parcel_provider.dart` **(neu)**
- **Lazy Cloud-Repo:** `_parcel => _injectedParcel ?? _firestoreService.parcelRepository` — **NIE im Konstruktor** (sonst Crash in `APP_DISABLE_AUTH`/Web).
- **Drei Storage-Modi:** `usesLocalStorage`/`usesHybridStorage`/`_usesFirestore`, Helfer `_tryFirestore(label, action)` (hybrid: Fehler→`false`→lokaler Fallback, **kein rethrow**; cloud-only→rethrow).
- **Mutator-Muster:** `if (_usesFirestore && await _tryFirestore('…', () => _parcel.saveParcel(prepared))) { _audit?.call(...); return; }` danach lokaler Zweig `upsert + _persistParcels() + _safeNotify() + _audit?.call(...)`. **AuditSink nur auf Erfolgs-Pfad, in JEDEM Storage-Zweig, deutsche personenfreie Summary, `entityType:'Paket'`/`'Paketfach'`** (s. §14).
- `updateSession(user, {localStorageOnly, hybridStorageEnabled})`: `_lastSessionKey`-Dedup, `_cancelSubscriptions`, dann `_startFirestoreSubscriptions(orgId)` (Streams parcels + compartments, `onError: _setError`) + Config-Load **oder** `_loadLocalData()`. `_safeNotify()` prüft `_disposed`.
- **Abgeleitete Getter (rein clientseitig, kein Index):**
  - `openParcels`, `parcelsForRecipient(query)` (Fuzzy), `findParcelByCode(code)` (exakt + Suffix/Präfix, tolerant wie `productByBarcode`, **ohne** `isPlausibleRetailCode`-Gate).
  - `compartmentByBarcode(code)`, `freeCompartments`, `parcelsInCompartment(id)`.
  - `overdueParcels(fristTage)` (Kalendertage ab `arrivedAt`, Default 6, §0/§15), `compartmentOccupancy`, `parcelsArrivedOn(date)`/`parcelsHandedOutOn(date)` (Tages-Reconciliation).
  - **Register:** `parcelCustomersMatching(query)` (Typeahead, Fuzzy) · `upsertCustomer(first,last)` (Dublettenprüfung `nameLower`, sonst `lastSeenAt`-Update) · `deleteCustomer(id)` (Widerspruch/Löschung §13, entkoppelt `parcelCustomerId`).
  - **Löschung (manuell, §0):** `deleteParcel(id)` + `deleteCustomer(id)` (Art. 17/21). Optionaler purer Helfer `shipmentsDueForAnonymization(fristTage)` + `anonymizeShipment` ist implementiert/testbar, aber in v1 **deaktiviert** (`anonymisierungAktiv==false`, §12.3/§13).
- **Barcode-/Fach-Eindeutigkeit je Standort** im `saveCompartment` clientseitig (Muster `saveProduct`-Barcode-Uniqueness), **nicht** in Rules.
- **Cache-Recompute (Footgun §14):** `recipientNameLower`, `compartmentLabel`, `siteName` werden im Mutator **frisch** berechnet, nie ungeprüft aus `copyWith` durchgereicht.

### 7.3 Provider-Kette (`lib/main.dart`)
`ChangeNotifierProxyProvider3<AuthProvider, StorageModeProvider, AuditProvider, ParcelProvider>` — einfügen **nach `AuditProvider`** (idiomatisch beim/nach dem `InventoryProvider`-Block, Position ~485). `update`: `provider.setAuditSink(audit.log); _dispatchProviderUpdate(provider.updateSession(auth.profile, localStorageOnly: storage.isLocalOnly, hybridStorageEnabled: storage.isHybrid), 'ParcelProvider.updateSession', onError: provider.surfaceSessionError);`.
- **Kein TeamProvider-Dependency** (ParcelProvider bleibt Proxy3). Die **Pflicht-siteId** kommt **nicht** aus dem Provider: Screens lesen `context.read<TeamProvider>().sites`, wählen den Standort mit `id == paketshopSettings.hermesSiteId` (bzw. den einzigen Standort, falls die Org nur einen hat) und reichen **`siteId` + `siteName` in `saveParcel`/`saveCompartment` durch** (Major-Fix). `siteName` ist reiner Anzeige-Cache.

### 7.4 Wiederverwendung Scanner & Kontakte
- **Scanner:** Engine `BarcodeScanner` + `MobileScannerAdapter` + `ScanFeedback` **1:1**. Die im `ScannerScreen` privaten Primitive (`_onCodeDetected` 1000 ms-Dedup, `_withDialogGuard`/`_dialogOpen`, Lifecycle-Start/Stop, Preview mit Torch/Zoom/Dark-Hint, Manuell-/Foto-Fallback) **einmalig extrahieren** nach `lib/widgets/barcode_scan_field.dart` (**neu**) bzw. `showBarcodeScanSheet(context) → Future<String?>` (**keine** Warenwirtschaftslogik). `ScannerScreen` anschließend auf dieses Widget umstellen (Dedupe). **`scanWindow` NIE setzen.** Für Paket/Fach/Kundenhandy-Code durchgängig **`ScannerTarget.extended`** (deckt code128/qr/dataMatrix/itf14 + EAN/UPC ab — **kein neuer `logistics`-Target**, sonst unnötige Enum-Kopplung #3 im erschöpfenden `_formatsFor`-switch). GS1/SSCC nur wo erwartet via `parseGs1` (SSCC über `elements['00']`, kein Getter). Der Einlagern-Flow nutzt eine **fortlaufende Scan-Session Paket→Fach** (Kamera bleibt offen, s. §5a).
- **Namens-Autocomplete:** **nicht** über `ContactProvider`, sondern Fuzzy-Matching über das **`ParcelCustomer`-Register + offene Pakete** — Flutter `Autocomplete`/`RawAutocomplete` mit Normalisierung (lower + Umlaut/ß-Fold + Levenshtein-Toleranz), pure Helfer in `lib/core/fuzzy_name_match.dart` (**neu**, offline testbar).

### 7.5 Permission-Getter (`lib/models/app_user.dart`) — alle aktiven Mitarbeiter (Betreiber-Entscheidung §0)
Neue Getter, gaten UI **und** Provider-Mutatoren **und** in `firestore.rules` gespiegelt:
```dart
bool get canManageParcels => isActive;  // Betreiber-Entscheidung §0: jeder aktive Mitarbeiter am Tresen
bool get canViewParcels    => isActive;
```
> **Bewusste Entscheidung (§0):** Der Betreiber will, dass **alle aktiven Mitarbeiter** annehmen/ausgeben (Tresenbetrieb). Getrennte Getter bleiben erhalten, falls später eine Read-only-Rolle oder Manager-Einschränkung nötig wird. **Auflage:** alle Mitarbeiter organisatorisch aufs Daten-/Postgeheimnis (§ 206 StGB) verpflichten. **Folgen:** (a) das ursprüngliche „need-to-know"-Argument entfällt → §13-Abwägung erweitert; (b) die verlässliche Anonymisierung läuft server-seitig (§12.3), unabhängig davon wer eingeloggt ist.

### 7.6 Routing — Hauptbereich-Screen unter dem „Laden"-Hub, KEIN neuer Tab
Ein neuer `ShellTab` zöge die schwere Kopplung #7 nach sich — für ein Standort-Nischenmodul unangemessen. Warenwirtschaft/Kundenbestellungen liegen bereits als **Section-Routes** unter dem `shop`-Tab (`/laden`). Der Paketshop reiht sich dort ein:
- `AppRoutes.paketshop = '/paketshop'` (**neu**) in `lib/routing/shell_tab.dart`.
- `_sectionRoute(AppRoutes.paketshop, (c,s) => const PaketshopHubScreen(parentLabel: 'Laden'))` in `buildAppRouter` (`lib/routing/app_router.dart`, bei den übrigen `_sectionRoute`-Einträgen ~Zeile 154+).
- `RoutePermissions.isLocationAllowed` (`route_permissions.dart`): `case AppRoutes.paketshop: return p?.canViewParcels ?? false;` (SSoT).
- Aufruf via `context.push(AppRoutes.paketshop)`; Einlagern-/Ausgeben-/Fach-/Detail-Sheets bleiben imperativ `Navigator.push`/`showModalBottomSheet`.
- **Hub-Einbindung:** Kachel „Hermes-Paketshop" im `_ShopHubTab` (`home_screen`, ~Zeile 2875+, **korrigierter Name**) mit Badge „X offen / Y überfällig". Optional zusätzlich Home-Schnellaktion „Paket annehmen".

## 8. Screens / UI (mobil-first, Material 3, `appColors`, Deutsch)

Alle Modals via `showModalBottomSheet(showDragHandle: true, isScrollControlled: true, useSafeArea: true)`. Status-Chips über `Theme.of(context).appColors` (success/warning/info) + `_ChipTone`-Muster, **nie** hardcoden. Jedes `DateFormat` explizit `'de_DE'`.

**Tresen-Ergonomie / Ein-Hand-Bedienung (neu):** Primäraktionen (Scannen, „Ausgegeben") groß und **unten/daumenreichbar**; Suchfeld mit sofortiger Trefferliste. Die zweihändige Namenseingabe ist als bekannter Engpass anerkannt (weitere Gründe für Kundenhandy-Code und spätere OCR).

| Screen/Sheet | Datei | Zweck & Layout (knapp) |
|---|---|---|
| **PaketshopHubScreen** | `lib/screens/paketshop_screen.dart` (**neu**) | Einstieg. Kennzahl-Chips (offen / überfällig / freie Fächer / heute an·aus). Zwei große Primäraktionen **„Paket annehmen"** / **„Paket ausgeben"**. Sektionen: „Überfällig", „Alle offenen Pakete" (`_ParcelTile`), Kacheln „Fächer" und „Tages-Reconciliation". Persistenter Hinweisbanner „Offizieller Hermes-Ablauf bleibt zusätzlich zwingend". |
| **PaketEinlagernScreen** (oder Sheet) | dito | Flow §5a. Sequenz Scan Paket → Scan Fach (Freifach-Vorschlag-Chip) → Name-Typeahead **aus `ParcelCustomer`-Register + offenen Paketen** (+„Neu anlegen" legt Register-Eintrag, optional Absender). Erfolgs-Blitz, „Nächstes Paket". |
| **PaketAusgebenScreen** (oder Sheet) | dito | Flow §5b. SearchBar (Name/Teil-Nr.) + „Scannen" + **„Kundenhandy-Code scannen"**. Gebündelte Kunden-Karte (Dubletten-Zusatzinfo inkl. Absender). „Ausgegeben"/„Alle" (+ Bestätigung >1) + Undo-Snackbar + Hermes-Banner + Leer-Zustand/Nacherfassen. |
| **FachVerwaltungScreen** (oder Sheet) | dito | Flow §5c. `ListView` mit Auslastungs-Chip. „+ Fach" (Label + Barcode-Scan). „Fach scannen" → Reverse-Lookup. |
| **KundenRegisterScreen** (oder Sheet) | dito (**neu**) | §0-Register. Suchbare Liste der `ParcelCustomer` (name-only). Aktion **„Kunde löschen"** (Art. 17/21-Widerspruch, entkoppelt `parcelCustomerId` an offenen Paketen). Hinweis, dass Namen dauerhaft gespeichert werden (Transparenz §13). Erreichbar als Kachel im Hub. |
| **ÜberfälligBoard** (Teil des Hubs) | dito | Farbcodierte Liste (Frist aus Config); **Mehrfachauswahl → „Rücklauf vorbereiten/markieren"** (Bulk, Fächer werden über abgeleitete Belegung automatisch frei; optional Abhak-Liste für den Kurier). |
| **PaketDetailSheet** | dito (privat `_ParcelDetailSheet`) | Empfänger, Absender, Sendungsnr., Fach, Status, `arrivedAt` (`de_DE`), Aktionen „Ausgegeben"/„Doch nicht abgeholt (Undo)"/„Umlagern (anderes Fach scannen)"/„Als Rücklauf markieren". |
| **`_ParcelTile`/`_CompartmentTile`** | dito (file-private) | Wiederverwendbare Zeilen; Chips via `appColors`. |
| **`barcode_scan_field.dart`** | `lib/widgets/` (**neu**) | Extrahiertes Scan-Widget/`showBarcodeScanSheet` (§7.4), geteilt mit `ScannerScreen`. |

**Layout-Prinzip:** ein Screen mit klaren Primäraktionen statt tiefer Navigation; Kamera-Sheets kurzlebig (Lifecycle-Stop). Wide-Layout (≥600) zweispaltig (Liste | Detail), Handy einspaltig.

## 9. „Besser als DHL"-Features (priorisiert, ehrlich eingeordnet)

Der Vorsprung liegt beim **Wiederfinden/Ausgeben**, nicht beim Einlage-Durchsatz (§1/§3).

**P1 (Kern, in v1):**
1. **Fach-Barcode-Bindung + aktive Freifach-Führung:** Vorschlag freies Fach, harte Fremd-Doppelbelegungs-Warnung, Mehrpaket im selben Fach beim gleichen Empfänger.
2. **Mehrpaket-Bündelung je Kunde:** ein Sucheinstieg zeigt alle Pakete + Fächer → gesammelt ausgeben.
3. **Fuzzy-Namenssuche** + **Teil-Sendungsnr.-Suche** + **Kundenhandy-Code-Scan** + **Absender/Shop als Dubletten-Disambiguator**.
4. **Duplikat-/Doppelscan-Schutz** + **Undo/Recovery** (Fehl-Tap rückgängig).

**P2 (Überblick, in v1):**
5. **Überfällig-/Ladenhüter-Board** (`arrivedAt` + konfigurierbare Frist, Kalendertage, Default ~6, farbcodiert, rein beratend) **+ Rücklauf-Sammelaktion**.
6. **Fach-Auslastung** + **Reverse-Lookup** + **Tages-Reconciliation** (heute angenommen/ausgegeben — Abgleich mit dem Hermes-Gerät).

**P3 (inhärent):**
7. **Offline-first** (hybrid-Cache) — Einlagern/Ausgeben auch bei Internet-Ausfall.
8. **Minimaler Klick-Pfad** (Scan→Scan→Name / finden→ein Tap) — bewusst schlanker als DHLs Druck-/Unterschrift-Prozess.

**Spätere Option (NICHT v1):** **OCR/Text-Erkennung des Empfängernamens vom Etikett** als Vorschlag zum Bestätigen — der einzige echte Hebel gegen die Tipp-Last beim Einlagern. Benötigt ein Text-Recognition-Paket (z. B. ML-Kit/`google_mlkit_text_recognition`, **Eignung zu prüfen**; `mobile_scanner` ist barcode-fokussiert).

## 10. Meilensteine (alle **offen**)

Jeder Meilenstein ist der **kleinste offline (`APP_DISABLE_AUTH`) testbare Schritt**; danach `flutter analyze` + `flutter test` grün.

| MS | Inhalt | Definition of Done | Status |
|---|---|---|---|
| **P-0** | Modelle `ParcelShipment` (+`senderName`,`parcelCustomerId`) + `ShelfCompartment` + **`ParcelCustomer`** (je 6 Serialisierungsstellen, `ShipmentStatus`-Enum, `copyWith`/`clearX` inkl. `clearSenderName`/`clearParcelCustomerId`/`clearHandedOutAt`) | Round-Trip-Tests grün (beide Formate, alle **3** Modelle); `recipientNameLower`/`nameLower`-Ableitung; `analyze` sauber | ✅ **erledigt (13.07.)** — `lib/models/parcel_{shipment,customer}.dart` + `shelf_compartment.dart`, `test/parcel_models_test.dart` (16 Tests grün, analyze 0 Issues) |
| **P-1** | `ParcelRepository` + `FirestoreParcelRepository` (Pakete/Fächer/Kunden-CRUD) + privates Feld/Getter in `FirestoreService`; lokale Keys `parcel_shipments`, `shelf_compartments`, `parcel_customers` im `_orgScopedCollectionKeys`-Set + load/save-Paare (`paketshop_settings`-Key erst mit Config in P-2) | Repo-Test gegen `FakeFirebaseFirestore` (save gibt ID, watch streamt, alle 3 Collections); Local-Round-Trip | ✅ **erledigt (13.07.)** — `lib/repositories/{parcel_repository,firestore_parcel_repository}.dart`, `FirestoreService.parcelRepository`, 3 DB-Keys + load/save, `test/firestore_parcel_repository_test.dart` grün. **Abw.:** `anonymizeShipment` weggelassen (§0 v1-aus, kommt ggf. mit P-11) |
| **P-2** | `ParcelProvider` (3 Storage-Modi, `_tryFirestore`, `updateSession` inkl. Config-Load `config/paketshopSettings`, `_safeNotify`, `setAuditSink`, Cache-Recompute) + abgeleitete Getter + **Register-CRUD (`upsertCustomer`/`deleteCustomer`/`parcelCustomersMatching`)** + `shipmentsDueForAnonymization` | Provider-Test local/cloud/hybrid; Hybrid-Offline-Fallback via `_OfflineParcelRepository`; Register-Dublette + `lastSeenAt`; Audit nur auf Erfolg, personenfrei | ✅ **erledigt (13.07.)** — `lib/providers/parcel_provider.dart` + `lib/models/paketshop_settings.dart`; Repo um `fetchSettings`/`saveSettings` (`config/paketshopSettings`) + DB-Key `paketshop_settings` erweitert; abgeleitete Getter (openParcels/findParcelByCode/freeCompartments/compartmentOccupancy/overdueParcels/parcelCustomersMatching/parcelsArrivedOn·HandedOutOn), Register-CRUD (upsert-Dedup + delete entkoppelt), Audit personenfrei; `test/parcel_provider_test.dart` 10 grün (local/cloud/hybrid-offline/audit/config). **Abw.:** `shipmentsDueForAnonymization` weggelassen (§0 v1-aus, ggf. P-11); Namensmatch vorerst normalisierter Teilstring (echte Fuzzy erst P-5) |
| **P-3** | Provider in `main.dart`-Kette (nach Audit) + Permission-Getter (`canViewParcels`/`canManageParcels` = **`isActive`, alle aktiven Mitarbeiter §0**) + Route `/paketshop` + `route_permissions`-Case + Hub-Kachel; **siteId/siteName-Auflösung via `TeamProvider.sites` + `hermesSiteId`** | App startet offline; Route erreichbar/gegatet; Router-Test via `pumpApp`; siteId wird durchgereicht | offen |
| **P-4** | Scan-Primitive extrahieren → `barcode_scan_field.dart`/`showBarcodeScanSheet` (`ScannerTarget.extended`, **kein logistics**, fortlaufende Session); `ScannerScreen` umstellen | Widget-Test mit `_FakeBarcodeScanner.emit()` + `NoopScanFeedback`; code128/qr dekodiert; `scanWindow` nie gesetzt | offen |
| **P-5** | **Einlagern-Flow** (Scan Paket → Scan Fach → Name-Typeahead **aus Register + offenen Paketen**) inkl. Duplikat-Schutz, Fremd-Doppelbelegungs-Warnung, „Neu anlegen" (legt `ParcelCustomer` an), optional Absender | Widget-Test: Paket gebunden, Fremdbelegung warnt, gleicher Kunde nicht; „Neu anlegen" erzeugt Register-Eintrag; Fuzzy-Match-Core-Test | offen |
| **P-6** | **Ausgeben-Flow** (Scan/Kundenhandy/Name → gebündelte Karte → „Ausgegeben"/„Alle" + Bestätigung>1) + Status/`handedOutAt` + abgeleitete Fach-Freigabe + **Undo/Recovery** (`clearHandedOutAt`, Re-Bindung, Konflikt) + Hermes-Banner + Leer-/Nacherfassen-Zustand | Test: Status→`abgeholt`, `handedOutAt` gesetzt, Fach abgeleitet frei; Undo stellt `eingelagert`+Fach wieder her; Teilausgabe hält Fach belegt; Bündelung | offen |
| **P-7** | **Fach-Verwaltung** (anlegen mit Barcode-Scan, je-Standort-Eindeutigkeit, Reverse-Lookup, Löschguard belegter Fächer, Umbenennen zieht `compartmentLabel` nach) | Test: doppelter Barcode abgelehnt; belegtes Fach nicht löschbar; Reverse-Lookup korrekt | offen |
| **P-8** | **Überfällig-Board + Auslastung + Rücklauf-Sammelaktion + Tages-Reconciliation** (Frist aus Config, Kalendertage) + Hub-Kennzahlen | Test: `overdueParcels(fristTage)` an Grenzdaten (feste `de_DE`-Testdaten); Rücklauf-Bulk setzt Status; Reconciliation-Filter | offen |
| **P-9** | **UI-Politur** (mobil/wide, daumenreichbare Aktionen, `appColors`-Chips, leere Zustände, Feedback-Blitz) + **Kunden-Register-Verwaltung** („Kunde löschen"/„Vorgang löschen" = Widerspruch/Art. 17) — **keine Auto-Anonymisierung in v1** (§0) | Test: „Kunde löschen" entkoppelt `parcelCustomerId`; „Vorgang löschen" entfernt Vorgang; Register bleibt bei Vorgangs-Löschung erhalten | offen |
| **P-10** | `firestore.rules`-Blöcke (`parcelShipments`/`shelfCompartments`/**`parcelCustomers`**) + Deploy-Doku; End-to-End-Offline-Durchlauf | Rules greifen (sameOrg + canManageParcels=isActive + orgId-Pin); Deploy-Schritte gelistet; Gesamt-DoD (§16) | offen |
| **P-11** *(optional, NICHT v1)* | Nur falls DSB/Anwalt später eine Frist verlangt: `anonymisierungAktiv`-Schalter an + **Server-Job `parcelAnonymize`** (`onSchedule`, Admin SDK, `europe-west3`, Register unberührt). Der **pure Anonymisierungs-Regel-Helfer wird schon in v1 implementiert + getestet** (nur inaktiv). | Pure-Helfer-Test grün (v1); Job-Deploy erst bei Aktivierung (Blaze) | offen (optional) |

> **Bulk-Writes (korrigiert):** „Alle ausgeben"/„Rücklauf-Sammelaktion" laufen als **direkte** Firestore-Writes → es gilt Firestores **WriteBatch-Grenze 500**, NICHT die 50er-Callable-Konvention (die betrifft nur `upsertShiftBatch` o. ä.). Realistisch ≤ wenige Writes/Kunde; für Atomarität optional `WriteBatch` (≤500), Rücklauf-Sammelaktion defensiv in ≤500er-Chunks.

## 11. Tests

Konventionen: `TestWidgetsFlutterBinding.ensureInitialized()`, `await initializeDateFormatting('de_DE')`; in `setUp`: `SharedPreferences.setMockInitialValues({}); DatabaseService.resetCachedPrefs();`. Nie echtes Firebase (`FakeFirebaseFirestore`). Fakes geben Zahlen als `double`. Offline-/Fehler-Seam = handgeschriebener Fake (kein Mockito).

| Datei | Fälle |
|---|---|
| `test/parcel_models_test.dart` | Round-Trips beider Formate für **alle 3 Modelle** inkl. `senderName`/`parcelCustomerId`; `ShipmentStatus.fromValue` Default-Branch; `copyWith`/`clearX` (Fach entfernen, `handedOutAt`/`senderName`/`parcelCustomerId` leeren); `recipientNameLower`/`nameLower`-Ableitung |
| `test/parcel_provider_test.dart` | `updateSession` local/cloud/hybrid (nach Moduswechsel `await Future<void>.delayed(Duration.zero)`); Config-Load mit Fallback; Einlagern bindet Fach; Ausgeben → Status + abgeleitete Freigabe; **Undo** stellt Zustand wieder her; Duplikat-Erkennung; **Hybrid-Offline-Fallback** via `_OfflineParcelRepository` (`FirebaseException(code:'unavailable')` → lokaler Fallback, kein rethrow); Audit **nur** auf Erfolg **und personenfrei** |
| `test/firestore_parcel_repository_test.dart` | `saveParcel` gibt Doc-ID, `watchParcels` streamt sortiert; `saveCompartment`/`watchCompartments` |
| `test/parcel_derived_getters_test.dart` | `overdueParcels(fristTage)` (Kalendertage) an Grenzdaten; `freeCompartments`/`compartmentOccupancy` (Teilausgabe hält belegt); `findParcelByCode` exakt + Suffix; `parcelsForRecipient`; `parcelsArrivedOn`/`parcelsHandedOutOn` |
| `test/fuzzy_name_match_test.dart` | pure Fuzzy: Umlaut/ß-Fold, Vor-/Nachname-Reihenfolge, Tippfehler-Toleranz, Nicht-Treffer |
| `test/parcel_anonymize_test.dart` | pure Anonymisierungs-Regel (in v1 **inaktiv**, für spätere Aktivierung): abgeholt/zurück > Frist + verwaiste Vorgänge erfasst; offene Pakete **und** `ParcelCustomer`-Register bleiben unberührt |
| `test/parcel_manual_delete_test.dart` | manuelle Löschung: `deleteParcel` entfernt Vorgang; `deleteCustomer` entkoppelt `parcelCustomerId` an offenen Paketen; Register-Eintrag weg, Pakete bleiben |
| `test/parcel_customer_register_test.dart` | Dublettenprüfung `nameLower`; `upsertCustomer` legt an bzw. aktualisiert `lastSeenAt`; `deleteCustomer` entkoppelt `parcelCustomerId`; `parcelCustomersMatching` (Fuzzy) |
| `test/parcel_scan_flow_test.dart` (Widget) | Einlagern/Ausgeben via `_FakeBarcodeScanner.emit()` + `NoopScanFeedback` + `pumpApp`; Fremdbelegungs-Warnung; „Neu anlegen" legt Empfänger inline an; Undo-Snackbar |
| `test/parcel_shelf_management_test.dart` | Fach-Barcode-Eindeutigkeit je `siteId`; Löschguard belegter Fächer; Reverse-Lookup; Umbenennen zieht `compartmentLabel` nach |

## 12. Firestore-Rules, Indexes, Functions & Deploy

### 12.1 Rules (`firestore.rules`, unter `organizations/{orgId}`, Muster `products`/`customerOrders`/`scanEvents`)
```
function canManageParcels() {
  return isActiveUser();   // Betreiber-Entscheidung §0: alle aktiven Mitarbeiter (== app_user.canManageParcels/canViewParcels)
}
match /parcelShipments/{parcelId} {
  allow read:           if sameOrg(orgId) && canManageParcels();
  allow create, update: if sameOrg(orgId) && canManageParcels()
                           && request.resource.data.orgId == orgId; // orgId-Pin gegen Spoofing
  allow delete:         if sameOrg(orgId) && canManageParcels();
}
match /shelfCompartments/{compId} {
  allow read:           if sameOrg(orgId) && canManageParcels();
  allow create, update: if sameOrg(orgId) && canManageParcels()
                           && request.resource.data.orgId == orgId;
  allow delete:         if sameOrg(orgId) && canManageParcels();
}
match /parcelCustomers/{customerId} {           // Kunden-Namensregister (§6.3)
  allow read:           if sameOrg(orgId) && canManageParcels();
  allow create, update: if sameOrg(orgId) && canManageParcels()
                           && request.resource.data.orgId == orgId;
  allow delete:         if sameOrg(orgId) && canManageParcels(); // „Kunde löschen" (Widerspruch §13)
}
```
- **Ehrliche Isolations-Aussage (korrigiert, §0):** Nach der Betreiber-Entscheidung erzwingen die Rules nur noch **aktiver Nutzer + Mandant** (`sameOrg`/orgId-Pin) — **keine** Rollen- und **keine** Standort-Einschränkung. User tragen nur `orgId`, keine feste `siteId`; echte Standort-/Row-Level-Isolation ist in den Rules nicht durchsetzbar. Der Zugriffskreis ist damit **breiter** als ursprünglich empfohlen (alle aktiven Mitarbeiter statt nur Manager) — das ist die bewusste §0-Entscheidung und in §13 in die Abwägung aufgenommen. Standort-Trennung bleibt organisatorisch/UI-seitig.
- Optional strengere Feld-Allowlist (`request.resource.data.keys().hasOnly([...])`) gegen Mass Assignment nach `scanEvents`-Muster.
- **Kopplung #4/#8:** `canManageParcels()` in Rules == `app_user.canManageParcels`/`canViewParcels` == `RoutePermissions`-Case — alle synchron halten.

### 12.2 Indexes (`firestore.indexes.json`)
- **v1: keine neuen Composite-Indexes** (reines `orderBy` auf `recipientNameLower`/`labelLower`/`nameLower`; Anonymisierungs-Job filtert in-memory). Nur falls später site-gefilterte Datums-Query → `(siteId ASC, arrivedAt DESC)` ergänzen + deployen.

### 12.3 Cloud Functions — KEINE in v1
- **Kein Callable, keine Function** für den CRUD-Pfad: wie Warenwirtschaft/Kontakte reiner Firestore-CRUD, direkter Client-Write, Enforcement in `firestore.rules`. Keine Compliance-Re-Validierung, keine Secrets, kein Outbound, **kein Blaze-Job**.
- **Keine automatische Anonymisierung/Löschung (Betreiber-Entscheidung §0):** Vorgänge **und** Register bleiben dauerhaft; gelöscht wird nur manuell auf Wunsch (`deleteParcel`/`deleteCustomer`, Art. 17/21). Der ursprünglich geplante `onSchedule`-Job entfällt damit in v1.
- **Optional/später (NICHT v1):** ein `onSchedule`-Anonymisierungs-Job `parcelAnonymize` (Admin SDK, `europe-west3` = `const REGION`, neue Datei `functions/parcel_anonymize.js`), der bei aktiviertem Schalter (`anonymisierungAktiv==true`) die Vorgangs-Felder `trackingCode`/`senderName`/`recipientFirstName/LastName`/`recipientNameLower` anonymisiert und `parcelCustomerId` entkoppelt (Register unberührt; Marker-Muster wie `account_deletion.js`). Erst nötig, falls die Rechtslage doch eine Frist verlangt (dann Kopplung §14 + Blaze-Deploy).
- Weitere Functions erst bei Kundenbenachrichtigung (fanOutPush) — spätere Ausbaustufe.

### 12.4 Deploy-Schritte
```bash
firebase deploy --only firestore:rules            # neue parcel-Blöcke (parcelShipments/shelfCompartments/parcelCustomers)
# KEIN functions-Deploy in v1 (kein Blaze-Job) — nur falls der optionale Anonymisierungs-Job später aktiviert wird
# firestore:indexes NUR falls später ein Composite-Index ergänzt wird
```
Kein Web-Redeploy-Sonderfall (keine neuen Web-Plugins). Falls Web betroffen: `flutter clean` vor `flutter build web` (Plugin-Registrant-Footgun).

## 13. DSGVO / Recht

> Recherche, **keine Rechtsberatung** — verbindliche Bewertung durch DPO/Fachanwalt (Go-Live-Blocker unten).

- **Minimaler Feldsatz (Art. 5 Abs. 1 lit. c), zwei Ebenen:** *(Vorgang `ParcelShipment`)* `recipientFirstName/LastName`-Snapshot, optional `senderName`, `trackingCode`, `carrier`, `compartmentId`, `status`, `arrivedAt`, `handedOutAt`, `returnedAt`, `parcelCustomerId`. *(Register `ParcelCustomer`)* **nur** `firstName`, `lastName`, `siteId`, Zeitstempel. In **beiden** Ebenen **kein** Adresse/Telefon/E-Mail/Geburtsdatum/Ausweisnr., **kein** personenbezogenes Freitextfeld (Art.-9-Risiko).
- **`senderName`:** additives, optionales Feld zur Disambiguierung bei Namensgleichheit. In aller Regel ein **Shop/gewerblicher Absender** („Amazon", „Zalando") mit geringer Personenbezug-Sensibilität; kann im Einzelfall ein privater Absendername sein (dann Dritt-Personendatum) → deshalb **optional**, minimal, der Vorgangs-Anonymisierung unterworfen und über Art. 6 Abs. 1 lit. f getragen. In die Interessenabwägung aufnehmen.
- **Rechtsgrundlage:** Art. 6 Abs. 1 lit. f (berechtigtes Interesse: effizienter, fehlerarmer Betrieb der übernommenen Paketdienstleistung) — deckt den **Vorgang**. Das **dauerhafte Namensregister** (§0) stützt sich auf dasselbe berechtigte Interesse („Wiedererkennung von Stammkunden"), ist aber **abwägungsintensiver** (Dauerhaftigkeit + breiter Zugriffskreis) → die Abwägung muss Nutzen gegen unbefristete Speicherung stellen und ein **Widerspruchs-/Löschrecht** (Art. 21/17, „Kunde löschen") vorsehen. **Keine Einwilligung** nötig, solange rein intern & ohne Benachrichtigung/Marketing — aber **DPO-Bestätigung insb. fürs Register** (Go-Live-Blocker). Kurze **Interessenabwägung** + **VVT (Art. 30)** anlegen.
- **Postgeheimnis (§ 64 PostG, § 206 StGB):** Empfänger-/Sendungsdaten sind „nähere Umstände des Postverkehrs". Nach §0 ist der Zugriff **auf alle aktiven Mitarbeiter** geöffnet (nicht mehr nur Manager) — zulässig, weil das bedienende Personal die Daten für die Aufgabe braucht, **erfordert aber** die schriftliche **Verpflichtung aller auf das Post-/Datengeheimnis** und keine bereichsübergreifende Auswertung. **Ehrlich (§12.1):** die Rules erzwingen aktiver Nutzer + Mandant, **nicht** Rolle/Standort; die Trennung bleibt organisatorisch/UI-seitig. Der breitere Zugriffskreis ist eine bewusste §0-Entscheidung.
- **Aufbewahrung (Art. 5 Abs. 1 lit. e) — Betreiber-Entscheidung §0 = KEINE automatische Begrenzung:** Sowohl Paket-Vorgänge (inkl. Postgeheimnis-Daten) als auch das Namensregister bleiben **unbefristet** gespeichert. Gelöscht wird **nur manuell auf Wunsch** (`deleteParcel`/`deleteCustomer`, Art. 17/21).
  - **Ehrliches Restrisiko:** Die unbefristete Speicherung — insbesondere der Postgeheimnis-Vorgangsdaten — steht in **Spannung zu Art. 5 Abs. 1 lit. e** (Speicherbegrenzung). Das ist eine bewusste, informierte Betreiber-Entscheidung (§0); der Betreiber bestätigt Vertrags-/AVV-Deckung und hält das Register für zulässig und übernimmt die Verantwortung.
  - **Zwingende Auflagen (unabhängig von der Speicherdauer, Art. 5 Abs. 2 Rechenschaft):** dokumentierte **Interessenabwägung + VVT (Art. 30)**, **Datenschutz-Aushang** (Art. 13/14), funktionierendes **„Kunde löschen" / „Vorgang löschen"** auf Wunsch. Aggregierte KPIs ohne Namensvorhalt.
  - **Optional/später:** der Anonymisierungs-Schalter (`anonymisierungAktiv`, Default **aus**) + Job (§12.3) kann eine Frist nachrüsten, falls DSB/Anwalt das verlangt — die Regel ist als purer Dart-Helfer bereits implementiert/testbar, im JS-Job spiegelbar (Kopplung §14), in v1 aber inaktiv.
- **Typeahead über Namensregister + offene Pakete** (§0): bewusst mit persistenter Wiedererkennung. Privacy-by-Design (Art. 25) bleibt durch **name-only**-Register (keine weiteren Attribute), getrennte Ebenen und die manuelle Löschmöglichkeit gewahrt.
- **Rolle:** eigener Verantwortlicher (Hermes ist eigener Verantwortlicher; keine klassische AV). Firestore `europe-west3` (EU) passt.
- **Transparenz (Art. 13/14):** Drittdatenerhebung → knapper **Datenschutz-Aushang** im Laden + Absatz in der Datenschutzerklärung (nutzt `LegalInfo`/`APP_LEGAL_*`).

**Rechtliche Auflagen vor Go-Live (§0):** Der Betreiber hat bestätigt, dass Vertrag/AVV die Speicherung deckt (1) und das dauerhafte Register zulässig ist (2), und verpflichtet das Personal aufs Datengeheimnis (3). **Weiterhin zu erledigen & zu dokumentieren:** (a) **schriftliche DSB/Anwalt-Bestätigung** zu (1)/(2) — dringend empfohlen, da unbefristete Postgeheimnis-Speicherung + breiter Zugriffskreis das rechtlich exponierteste Element sind; (b) **Interessenabwägung + VVT (Art. 30)** schriftlich; (c) **Datenschutz-Aushang** (Art. 13/14) im Laden + Absatz in der Datenschutzerklärung; (d) **Verpflichtungserklärungen** aller Mitarbeiter aufs Post-/Datengeheimnis; (e) `senderName`-Zulässigkeit in die Abwägung aufnehmen. **Kein Anonymisierungs-Job als Go-Live-Blocker mehr** (bewusst abgewählt) — dafür ist die funktionierende **manuelle Löschung auf Wunsch** Pflicht.

## 14. Kritische Kopplungen & Footguns

1. **Zwei-Serialisierung (größter Footgun):** jedes Feld an **6 Stellen** — `toFirestoreMap` (camelCase, `Timestamp`, **kein** `id`), `fromFirestore(id,map)`, `toMap` (snake_case, ISO, **mit** `id`), `fromMap(map)`, `copyWith` + `clearX` je nullable. Verwechslung verliert **still** Felder. Kein Callable → kein `functions/index.js`-CRUD-Parsing (der Anonymisierungs-Job liest camelCase-Docs).
2. **Rules ↔ app_user ↔ RoutePermissions dreifach synchron:** `canManageParcels()`/`canViewParcels` an allen drei Stellen; `orgId`-Pin in Rules (Direct-Write ohne Callable-Validierung).
3. **Site-Skopierung = nur ein `siteId`-Feld**, KEINE Row-Level-Security. Rules erzwingen Rolle + `orgId`, **nicht** Standort (§12.1/§13). Fach-/Barcode-Eindeutigkeit je Standort wird **clientseitig** geprüft. **siteId-Herkunft:** Screens lesen `TeamProvider.sites` + `hermesSiteId`, reichen `siteId`/`siteName` durch (kein TeamProvider-Dep am Provider).
4. **AuditSink nur auf Erfolgs-Pfad**, in JEDEM Storage-Zweig, NIE auf rethrow/Permission-Deny, NIE doppelt. `setAuditSink` löst **kein** `notifyListeners` aus. Deutsche Summaries — **und STRIKT personenfrei:** nur Fach/Status, **nie** Empfängername (sonst überlebt PII die Paket-Löschung → Schattenregister). Die Namens-Toasts in §5 sind **UI-only**, nicht Audit-Summary.
5. **Cache-Recompute-Footgun (neu):** `recipientNameLower`, `compartmentLabel`, `siteName` sind abgeleitete Caches — im Mutator **immer frisch** setzen, nie ungeprüft aus `copyWith` durchreichen (analog `Product.nameLower`). Fach-**Umbenennung** zieht `compartmentLabel` an allen offenen Paketen des Fachs nach (oder Label stets frisch aus `compartmentByBarcode` anzeigen).
6. **Storage-Modus-catch:** hybrid → lokaler Fallback (**kein** rethrow), cloud-only → rethrow, local → sofort persist+notify+return. `_tryFirestore` kapselt das.
7. **Lazy Cloud-Repo:** `_parcel`-Getter, **nie im Konstruktor**. Provider **nach** Audit in die Kette.
8. **Scanner-`scanWindow` NIE setzen** (mobile_scanner #1009/#633). Volle-Frame-Analyse, Reticle rein visuell. **`ScannerTarget.extended`** für Paket/Fach/Kundenhandy-Code (**kein** `logistics`-Target — `_formatsFor`-switch ist erschöpfend ohne default, jeder neue Wert erzwingt Switch-Pflege). **`isPlausibleRetailCode`-Gate NICHT** auf opake Paket-/Fach-Codes. GS1-SSCC über `elements['00']` (kein Getter).
9. **Barcode-Verwechslung Paket vs. Fach:** Flows sind kontextgebunden (erst Paket-, dann Fach-Scan) → keine Typ-Erkennung nötig; Reverse-Lookup löst gezielt gegen `shelfCompartments` auf. Roh-String speichern, tolerant matchen, **keine** starre Formatvalidierung.
10. **Ausgabe/Undo:** `compartmentId` bei Ausgabe **NICHT** leeren (Belegung ist abgeleitet aus offenen Paketen) → Undo (`clearHandedOutAt`, `status=eingelagert`) stellt die Fach-Zuordnung automatisch wieder her; Konflikt bei zwischenzeitlicher Fremdbelegung behandeln.
11. **`_safeNotify()`** in async/Stream/Timer (`_disposed`-Check). Lokale Listen **growable** halten (`_upsertLocal` ruft `.add()`).
12. **Deutsch-only, Locale `de_DE`, jedes `DateFormat` explizit `'de_DE'`.** Farben über `Theme.appColors`, nie hardcoden.
13. **Anonymisierung ist in v1 AUS (§0):** kein Auto-Purge/-Anonymisierung, kein `onSchedule`-Job. Löschung nur manuell (`deleteParcel`/`deleteCustomer`, Art. 17/21). Der optionale Anonymisierungs-Regel-Helfer (für spätere Aktivierung) existiert dann **zweimal** — purer Dart-Helfer + JS-`onSchedule` — und muss synchron bleiben (wie Compliance-Spiegel); er darf das `ParcelCustomer`-Register **nie** erfassen, sonst bräche die Wiedererkennung.
14. **Bulk-Writes = WriteBatch-Grenze 500** (nicht 50), da direkte Writes (§10).
15. **Neuer where+orderBy-Query ohne passenden Composite-Index → Laufzeitfehler.** v1 vermeidet das; bei späterem site-gefilterten Query Index nachziehen.
16. **Register (`ParcelCustomer`) vs. Vorgangs-Snapshot NICHT verwechseln (§0):** Typeahead liest das dauerhafte Register; die Anonymisierung leert nur den Vorgangs-Snapshot. `nameLower` im Register beim Anlegen frisch berechnen (Dublettenprüfung dagegen). „Kunde löschen" entkoppelt `parcelCustomerId` an offenen Paketen, löscht aber **keine** offenen Pakete.
17. **Alle DREI Modelle unterliegen der vollen Zwei-Serialisierung:** insbesondere das leicht zu vergessende `ParcelCustomer` (nur zwei Namensfelder) — exakt dieselbe 6-Stellen-Regel wie `ParcelShipment`/`ShelfCompartment` (Footgun #1).

## 15. Offene Fragen (mit Empfehlung)

1. **Wer darf annehmen/ausgeben?** → ✅ **ENTSCHIEDEN (§0):** alle aktiven Mitarbeiter (`canManageParcels => isActive`). Auflage: Verpflichtung aufs Post-/Datengeheimnis. (War Empfehlung „manager-skopiert" — vom Betreiber bewusst gelockert.)
2. **Aufbewahrung/Löschung?** → ✅ **ENTSCHIEDEN (§0):** **keine automatische Anonymisierung/Löschung** — Vorgänge **und** Register bleiben dauerhaft; Löschung nur manuell auf Wunsch (Art. 17/21). Betreiber bestätigt Vertrags-/Register-Zulässigkeit; **schriftliche DSB/Anwalt-Bestätigung + VVT/Aushang** bleiben Pflicht (§13). Optionaler Anonymisierungs-Schalter (Default **aus**) für später.
3. **Überfällig-Schwelle & Zeitbasis?** → ✅ **ENTSCHIEDEN (§0):** **6 Kalendertage** (konservativ, rein beratend), pro Standort konfigurierbar; `overdueParcels`/Tests rechnen Kalendertage. Werktage/SH-Feiertage bewusst **out of scope** v1.
4. **Empfänger-Wiedererkennung — Contact, eingebettet oder Register?** → ✅ **ENTSCHIEDEN (§0):** eigenes **name-only `ParcelCustomer`-Register** (nicht `Contact`), dauerhaft, für Typeahead über Besuche. Snapshot am Vorgang bleibt anonymisierbar. Rechtsfolge (persistentes Register) in §13 aufgenommen.
5. **Fach-Kapazität/`sizeHint`?** → *Empfehlung:* v1 **kein** Größenmodell; Freifach-Vorschlag ignoriert Paketgröße, manueller Override (anderes Fach scannen) ist die Rettung. Optionales `sizeHint` (klein/mittel/groß) für größenbewusste Sortierung als spätere Option.
6. **`ParcelEvent`-Ledger jetzt oder später?** → *Empfehlung:* später — AuditSink deckt v1-Rechenschaft (personenfrei).
7. **Empfänger an Audit binden (wer hat abgeholt)?** → *Empfehlung:* **nein** in v1 (kein Identitätsnachweis, DSGVO-günstiger; Audit protokolliert nur Mitarbeiter+Zeit, personenfrei).
8. **Ein Screen mit internen Tabs vs. mehrere Section-Routes?** → *Empfehlung:* ein `PaketshopHubScreen` mit Primäraktionen; nur `/paketshop` als Route, Flows als Sheets.

## 16. Definition of Done (Gesamt)

- [ ] **Drei** Modelle (`ParcelShipment` inkl. `senderName`/`parcelCustomerId`, `ShelfCompartment`, **`ParcelCustomer`**) mit vollständiger Zwei-Serialisierung + Round-Trip-Tests grün.
- [ ] `ParcelRepository`/`FirestoreParcelRepository` (inkl. Register-CRUD + `anonymizeShipment`) + privates Feld/Getter in `FirestoreService`; lokale Keys (`parcel_shipments`, `shelf_compartments`, **`parcel_customers`**, `paketshop_settings`) registriert & round-trip-fest.
- [ ] `ParcelProvider` bedient alle drei Storage-Modi inkl. Hybrid-Offline-Fallback; AuditSink nur auf Erfolgs-Pfad **und personenfrei**; lazy Cloud-Repo; Config-Load.
- [ ] Provider in `main.dart`-Kette nach Audit; `setAuditSink` verdrahtet; **siteId/siteName aus `TeamProvider.sites` + `hermesSiteId` durchgereicht**.
- [ ] Permission-Getter (`canViewParcels`/`canManageParcels` = **`isActive`, alle aktiven Mitarbeiter §0**) in `app_user.dart`, gespiegelt in `firestore.rules` und `RoutePermissions`; Personal aufs Post-/Datengeheimnis verpflichtet (organisatorisch).
- [ ] **Kunden-Namensregister** (`ParcelCustomer`) speist Typeahead über Besuche hinweg; „Neu anlegen" mit Dublettenprüfung; **„Kunde löschen" + „Vorgang löschen"** (Art. 17/21) vorhanden.
- [ ] Route `/paketshop` als Section-Route unter „Laden"-Hub (`_ShopHubTab`-Kachel); Flows als Sheets.
- [ ] Extrahiertes `showBarcodeScanSheet`/`barcode_scan_field.dart` (geteilt, `scanWindow` nie gesetzt, `ScannerTarget.extended`, fortlaufende Paket→Fach-Session).
- [ ] Einlagern-, Ausgeben-, Fach-Verwaltungs-Flows inkl. Freifach-Vorschlag, Fremd-Doppelbelegungs-Warnung, Duplikat-Schutz, Bündelung, Reverse-Lookup, **Kundenhandy-Code**, **Dubletten-Disambiguierung mit Absender**.
- [ ] **Undo/Recovery** (Fehl-Tap rückgängig, Fach-Re-Bindung, Konflikt) + Leer-/Nacherfassen-Zustand.
- [ ] Überfällig-Board + Auslastung + **Rücklauf-Sammelaktion** + **Tages-Reconciliation** (konfigurierbare Kalendertage-Frist).
- [ ] **DSGVO-Auflagen (§0/§13):** funktionierende **manuelle Löschung** („Kunde löschen"/„Vorgang löschen", Art. 17/21) + dokumentierte **Interessenabwägung + VVT** + **Datenschutz-Aushang** + **Verpflichtungserklärungen** aufs Post-/Datengeheimnis. **Keine** Auto-Anonymisierung in v1 (Schalter Default aus); Anonymisierungs-Regel-Helfer implementiert + getestet (inaktiv), für spätere Aktivierung. **Kein Blaze/Functions-Deploy in v1.**
- [ ] **`flutter analyze` 0 Issues** · **`flutter test` grün** · **offline lauffähig** (`flutter run --dart-define=APP_DISABLE_AUTH=true`).
- [ ] Alle Texte Deutsch, Locale `de_DE`, `DateFormat` explizit `'de_DE'`, Farben via `appColors`, daumenreichbare Primäraktionen.
- [ ] Deploy-Schritte gelistet (`firestore:rules` + `functions`; Indexes nur bei Bedarf).
- [ ] Persistenter UI-Hinweis „offizieller Hermes-Ablauf zusätzlich zwingend" vorhanden.
- [ ] Rechtliche Go-Live-Auflagen (§13) erledigt/übergeben: schriftliche DSB/Anwalt-Bestätigung zu Vertrag/AVV + Register-Zulässigkeit, **Interessenabwägung + VVT**, Art.-13/14-Aushang, Verpflichtungserklärungen, `senderName`, **funktionierende manuelle Löschung**.
- [ ] **MEMORY.md-Index-Pointer** ergänzt (s. §17).

## 17. Ablage / Planungskonvention

- Plandokument liegt versioniert unter `plan/hermes-paketshop-sortieren-ausgeben.md`.
- **Pflicht (Planungskonvention):** ein Ein-Zeilen-Pointer im MEMORY.md-Index. Vorschlag:

  > `[Hermes-Paketshop Sortieren/Ausgeben (Plan)](hermes-paketshop-plan.md) — 13.07.: internes Sortier-/Wiederfinde-Modul für Hermes-Shop Tabak Börse (Paket↔Fach-Barcode nach DHL-PLAPP-Vorbild, Fuzzy-Namenssuche, Undo, Rücklauf-Sammelaktion); plan/hermes-paketshop-sortieren-ausgeben.md; 4 Betreiber-Entscheidungen §0 (alle aktiven Mitarbeiter, dauerhaftes name-only ParcelCustomer-Register, KEINE Auto-Anonymisierung/Löschung — nur manuell auf Wunsch, Überfällig 6 Tage); Section-Route /paketshop unter /laden, KEINE Cloud Function/kein Callable/kein Composite-Index in v1; DSGVO-Restrisiko (unbefristete Postgeheimnis-Speicherung) als informierte Betreiber-Entscheidung dokumentiert, VVT/Aushang/manuelle Löschung Pflicht; Status ENTWURF, alle Meilensteine offen.`