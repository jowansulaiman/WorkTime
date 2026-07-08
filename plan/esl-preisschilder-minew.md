# ESL-Preisschilder (Minew 2.9″) an WorkTime anbinden — Machbarkeit & Entscheidungsvorlage

> Stand: 2026-07-07 · Status: **ENTSCHEIDUNG: Option B gewählt (Minew Offline-Server auf eigenem Server) — Bedarfsliste §10; wartet auf Minew-Antworten**
> Auslöser: Bestellung von Minew 2.9″ ESL-Tags bei Alibaba. Ziel des Nutzers: Preise aus WorkTime
> heraus auf den physischen Regal-Preisschildern verwalten. Verlauf: „Firmware überschreiben" verworfen →
> Voll-DIY/OEPL erwogen (§9) → **final gewählt (07.07.): Option B = Minew Offline-System auf eigenem
> Server + Gateway kaufen + selbstgebaute WorkTime-Brücke. §10 ist maßgeblich.**

## 0. Kernaussage in drei Sätzen

1. Die Tags (Nordic **nRF52810**, BLE 5.0) sind **kein Direkt-am-Handy-Gerät** — sie brauchen zwingend
   einen **Minew-Gateway** (G1/G1-E) und eine **ESL-Plattform** (Cloud **oder** lokal/„Offline System").
2. **Firmware überschreiben ist der falsche Hebel**: Das Standard-Projekt OpenEPaperLink unterstützt
   die Minew-nRF52810-Tags **nicht**; du müsstest Tag-Firmware, Gateway **und** Funkprotokoll komplett
   selbst reverse-engineeren → Monate-Projekt, hohes Brick-Risiko, kein Mehrwert für 2 Läden.
3. **Der tragfähige Weg**: Minew-Gateway kaufen + Minews **Offline-/On-Prem-Server** auf deinem
   eigenen Server betreiben + WorkTime pusht Preise via **Sync-Brücke** an Minews **offene API** —
   exakt das Muster, das ihr für die OktoPOS-Artikel-Anbindung (`pushOktoposArticles`) schon nutzt.

## 1. Was du konkret hast / brauchst (Hardware-Realität)

| Baustein | Status | Detail |
|---|---|---|
| **Tags** Minew 2.9″ (MTag29) | ✅ bestellt | E-Ink, BLE 5.0, Chip **nRF52810**, Batterie 5+ Jahre, Funk: BLE + proprietäres 2.4-GHz-Protokoll |
| **Gateway** (G1 / G1-E) | ❌ **fehlt** | Pflicht — ohne Gateway kannst du die Tags nicht bespielen. Chip im Gateway: nRF52832. Reichweite Retail ~15–60 m Radius. 1 Gateway reicht für einen kleinen Laden. |
| **ESL-Plattform** | ❌ **fehlt** | Zwei Geschmacksrichtungen: **Cloud Platform** (Abo) **oder** **Offline System** (on-prem/lokal). Für „ich habe meinen eigenen Server" → **Offline System** prüfen. |

**3-Schichten-Architektur (unveränderlich):**

```
Preis-Quelle (WorkTime)  →  Minew ESL-Plattform (Cloud ODER lokal)  →  Gateway G1  →  Tags (BLE/2.4 GHz)
```

Der **ESL-Downlink** (Bild/Preis aufs Display schieben) ist **proprietär** und läuft ausschließlich
über Minews Plattform + Gateway-Firmware. Minews generische IoT-Gateways können zwar an einen eigenen
HTTP-Server senden, aber das ist **nur Uplink** (BLE-Empfang) — nicht der ESL-Downlink. Es gibt also
keinen einfachen „eigener Server treibt die Tags direkt"-Trick.

## 2. Die drei realistischen Optionen

### Option A — Minew Cloud-Plattform + Gateway + API-Brücke
- Tags + G1-Gateway + Minew-**Cloud**-Abo. WorkTime pusht via Minew-Cloud-API.
- **+** Am schnellsten live, Cloud-API von einer WorkTime-**Cloud Function** direkt erreichbar (Blaze).
- **−** Laufendes Abo, Preisdaten liegen bei Minew. Passt schlechter zu „eigener Server".

### Option B — Minew Offline-/On-Prem-System auf deinem Server + Gateway + lokale Brücke  ⟵ **wahrscheinlich beste Passung**
- Tags + G1-Gateway + Minews **Offline System** auf deinem eigenen Server im Laden-LAN.
- WorkTime bleibt Preis-Wahrheit; ein **lokaler Sync-Agent** auf deinem Server liest die Preise und
  pusht sie an die lokale ESL-API.
- **+** Kein Cloud-Abo, Daten bleiben bei dir, passt zu deinem Setup.
- **−** **Cloud→LAN-Bruch**: Eine Firebase Cloud Function kann deinen LAN-Server **nicht** direkt
  erreichen. Der Sync muss auf **deinem Server** laufen (Pull aus WorkTime/Firestore → Push an lokale
  ESL-API) statt in einer Cloud Function. Kleiner zusätzlicher Baustein, aber sauber machbar.
- **‼ Offene Kernfrage**: Ist das „Offline System" wirklich auf **eigener Hardware** installierbar und
  hat es eine **lokale API/CSV-Import**-Schnittstelle? (→ §5, mit Minew klären.)

### Option C — Firmware überschreiben (DIY) — **nicht empfohlen**
- OpenEPaperLink unterstützt ZBS243, nRF52811 (Solum), EFR32xG22 — **nicht** Minews nRF52810.
- Du müsstest Tag-Firmware + eigenen BLE-Gateway/AP + Render-/Funkprotokoll selbst bauen; nRF-OTA ist
  i. d. R. auf signierte Images gesperrt → **Brick-Risiko**.
- **Fazit**: Forschungs-/Bastelprojekt über Monate ohne Business-Nutzen. Höchstens als Hobby.

## 3. Empfehlung

**Option B** (lokal/on-prem, passend zu deinem eigenen Server) — **sofern** Minews Offline-System
selbst-hostbar ist und eine API/Import-Schnittstelle hat. Falls Minew das Offline-System **nicht**
mit offener Schnittstelle liefert → **Option A** (Cloud) als pragmatischer Rückfall.

Beide Optionen lassen **WorkTime die alleinige Preis-Wahrheit** und ändern **nichts** an den Tags/der
Firmware.

## 4. WorkTime-Integrationsskizze (für Option A oder B)

- **Verknüpfungsschlüssel = Barcode/EAN.** WorkTime kennt Artikel bereits per Barcode
  (`productByBarcode`, `priceHistory`); ein ESL-Tag wird an eine Artikel-ID/Barcode gebunden.
- **Muster = wie `pushOktoposArticles`**: Bei Preisänderung Artikel-/Preis-/Template-Daten an die
  ESL-API pushen. Idempotent, Barcode als externer Schlüssel.
- **Wo läuft die Brücke?**
  - Option A (Cloud): **Cloud Function** (Blaze), Secret für den ESL-API-Key im Secret Manager — 1:1
    das OktoPOS-Muster (Outbound-HTTP, `X-API-KEY`, `europe-west3`).
  - Option B (lokal): **kleiner Sync-Agent auf deinem Server** (z. B. Node-Service/Cron), der aus
    WorkTime/Firestore liest und an die lokale ESL-API pusht — weil die Cloud Function das LAN nicht
    erreicht.
- **Schalter**: `APP_ESL_ENABLED` (Default aus), analog zu `APP_OKTOPOS_ENABLED` — Modul erst nach
  Hardware-Setup scharfschalten.
- **Kein Firmware-/kein Client-Sicherheits-Thema**: API-Key nie im Flutter-Client, nur server-/agent-seitig.

## 5. Offene Fragen an Minew (blockieren den finalen Bau-Plan)

Die ESL-API ist **nicht öffentlich dokumentiert** (docs.minew.com listet nur Beacon/Sensor-SDKs, kein
ESL). Diese Punkte müssen vom Minew-Vertrieb/Support kommen, bevor ich einen konkreten Bau-Plan
schreiben kann:

1. **Offline System selbst-hostbar?** Läuft es auf **deinem** Server/PC (Windows/Linux)? Welche
   Systemvoraussetzungen?
2. **API-Schnittstelle**: Gibt es eine **lokale HTTP-API** (Endpunkte, Auth) **oder** nur CSV/Excel-
   Import **oder** nur manuelle UI? Bitte API-Doku/Spec anfordern.
3. **API im Preis inbegriffen** oder kostenpflichtiges Enterprise-Add-on? („API interface application
   testing" wird als Service beworben.)
4. **Artikel-Bindung per Barcode/EAN** möglich? Template-/Preisfeld-Mapping?
5. **Passender Gateway** für deine Tags (G1 vs. G1-E), **Standalone-Preis**, wie viele Tags/Reichweite
   pro Gateway in deiner Ladengröße.
6. **Firmware/Provisioning**: Sind die gekauften Tags schon fürs Offline-/Cloud-System vorbereitet oder
   muss ein Kit/Provisioning-Schritt her?

## 6. Kosten (grobe Richtwerte, vor Versand/Zoll — mit Minew verifizieren)

| Posten | Richtwert |
|---|---|
| Gateway G1-E (Einzelstück) | ~199 USD / Stück (~€185) |
| 2 Läden → 2 Gateways | ~€370 |
| Tags | bereits gekauft |
| Demo-Kit (Alternativ-Referenz: G1-E + Sortiment Tags + 1 J. Cloud) | 599 USD |
| Offline-System-Lizenz | **unbekannt** → Angebot einholen |
| Cloud-Abo (Option A) | **unbekannt** → Angebot einholen |
| Sync-Brücke (Entwicklung) | intern (WorkTime), klein — OktoPOS-Muster wiederverwenden |

## 7. Nächste Schritte (Definition of Done dieser Prüfung)

- [ ] **§5-Fragen an Minew** stellen (Vertrieb/Support) und API-Doku beschaffen.
- [ ] **Gateway** passend zu den Tags bestellen (G1/G1-E, ≥1 pro Laden).
- [ ] Entscheiden **Option A (Cloud)** vs. **Option B (lokal)** anhand der Minew-Antworten.
- [ ] Danach: **Bau-Plan** für die Sync-Brücke schreiben (Datenmodell `EslBinding`, Schalter
      `APP_ESL_ENABLED`, Cloud Function **oder** lokaler Agent, Barcode-Mapping) — analog OktoPOS.
- [ ] Option C (Firmware) bewusst **verworfen** dokumentiert.

## 8. Quellen

- [Nordic: Minew ESL nutzt nRF52832 & nRF52810 SoCs](https://www.nordicsemi.com/Nordic-news/2021/11/minew-esl-uses-nrf52832-and-nrf52810-socs)
- [Nordic: Minew STag58P nutzt nRF52833 (OTA-DFU)](https://www.nordicsemi.com/Nordic-news/2023/09/minews-stag58p-employs-nrf52833-soc)
- [Minewtag — ESL-Produkte & offene APIs (POS/ERP)](https://www.minewtag.com/electronic-shelf-labels.html)
- [Minewtag — Support/Services (server localization, API testing)](https://www.minewtag.com/service.html)
- [Minewtag — ESL Demo Kit V2.0 (599 USD, inkl. G1-E)](https://store.minewtag.com/product/demo-kit2-0/)
- [Minew G1 IoT Bluetooth Gateway](https://www.minew.com/product/g1-iot-bluetooth-gateway/)
- [reelyActive — Minew G1 Konfiguration (HTTP-Forwarding = nur Uplink)](https://reelyactive.github.io/diy/minew-g1-config/)
- [OpenEPaperLink — Projekt & unterstützte Chips (ZBS243/nRF52811/EFR32xG22)](https://github.com/OpenEPaperLink/OpenEPaperLink)
- [OpenEPaperLink — Website](https://openepaperlink.de/)
- [docs.minew.com — SDK/API-Portal (nur Beacon/Sensor, kein ESL)](https://docs.minew.com/)

## 9. NEU (07.07.): Voll-DIY-Entscheidung — nur Hardware kaufen, Rest selbst bauen

Nutzer will **nur ein fertiges E-Paper-Display** kaufen und Funk/Gateway/Server **selbst** bauen
(kein Minew-Server, kein Minew-Gateway, kein Abo).

**Kernbefund:** Die bereits bestellten **Minew-nRF52810-Tags sind für Voll-DIY die schlechteste Wahl** —
ihr ganzer Wert ist die proprietäre Firmware/Protokoll/Gateway, also genau der Teil, der selbst gebaut
werden soll. Selbst-Ansteuern hieße: Tag öffnen, SWD anlöten (falls `APPROTECT` nicht gesperrt →
sonst Sackgasse), EPD-Waveforms + Funk-Stack **von Null** schreiben (keine Community-Firmware für
diesen Chip+Panel), eigenen AP bauen. Research-Projekt, hohes Risiko. → **Minew-Tags nicht fürs DIY nutzen.**

**Stattdessen: passende DIY-Hardware kaufen.** Zwei Kategorien:

### Kategorie 1 — All-in-One ESP32 + E-Paper (eigene Firmware, für wenige Displays/Prototyp)

| Modul | Display | Preis | Software | Notiz |
|---|---|---|---|---|
| Waveshare e-Paper ESP32 Driver Board + 2.9″-Panel | 2.9″ 296×128 | ~16 € + ~15–20 € | Arduino/ESP-IDF | „supermarket price tag" als offizieller Use-Case; modularster Weg |
| LilyGo T5 2.13″/2.9″ | 2.13″/2.9″ | ~18 € | Arduino/ESPHome | ESP32+E-Paper integriert, günstig |
| Adafruit MagTag | 2.9″ Graustufen | ~47 € | Arduino/CircuitPython | Batterie + Deep-Sleep 250 µA, sauberstes Fertig-Board |
| M5Stack Core Ink / M5Paper | 1.54″ / 4.7″ | ~30 € / ~85 € | Arduino/UIFlow | poliert, teurer/größer |

**Haken:** WLAN-ESP32 → Akku Tage–Wochen (nicht Jahre), 16–85 €/Stück → für 100+ Regal-Tags zu teuer/stromhungrig. Gut für 1–2 Stück Prototyp.

### Kategorie 2 — OpenEPaperLink: echte ESL-Tags + selbstgebauter AP  ⟵ **für Laden-Rollout empfohlen**

- **Tags:** günstige Restposten-ESL-Tags ~2–8 €/Stück (Solum/Hanshow, ZBS243/nRF52811, OEPL-unterstützt) via AliExpress; fertige OEPL-Tags über Tindie (Electronics by Nic — aktuell Verkaufspause bis 03/11-2026).
- **AP/„Gateway":** selbstgebaut, ESP32-C6 (Mini-AP v3) oder Tag-als-Radio + ESP32, ~10–20 €, ein AP ~30 Tags.
- **+** Akku Jahre, regalfertige Gehäuse, winziger Preis/Tag → skaliert auf ganzen Laden. Eigener Server, **REST-API**, MQTT, Home-Assistant. Kein Cloud/Vendor.

### Empfehlung DIY

- **Laden-Rollout → Kategorie 2 (OpenEPaperLink + günstige ESL-Tags).**
- **Sofort-Start/Lernen → 1× Kategorie 1** (Waveshare Driver-Board+Panel ~32 € oder LilyGo T5 ~18 €).
- **WorkTime-Brücke bleibt gleich:** `WorkTime → Sync-Agent auf eigenem Server → (ESP32-HTTP bzw. OEPL-REST) → Display`, Schlüssel **Barcode/EAN**, Muster wie `pushOktoposArticles`, Schalter `APP_ESL_ENABLED`.
- Minew-Tags: als Lehrgeld verbuchen oder für späteren Cloud/Gateway-Test aufheben; optional „Opfer-Tag"-SWD/`APPROTECT`-Check, bevor endgültig abgeschrieben.

### Quellen §9
- [OpenEPaperLink (offene Firmware, ESP32-AP, eigener Server, REST)](https://openepaperlink.de/)
- [Waveshare e-Paper ESP32 Driver Board (price tag Use-Case)](https://www.waveshare.com/e-paper-esp32-driver-board.htm)
- [LilyGo T5 2.13″ e-Paper](https://lilygo.cc/en-us/products/t5-2-13inch-e-paper)
- [Adafruit MagTag 2.9″ (2025/SSD1680)](https://www.adafruit.com/product/4800)
- [M5Paper / Core Ink](https://shop.m5stack.com/collections/controllers/e-paper)
- [atc1441 E-Paper_Pricetags (BLE-Tags direkt ansteuern)](https://github.com/atc1441/E-Paper_Pricetags)
- [OEPL Tags/AP (Tindie, aktuell teils Verkaufspause)](https://www.tindie.com/stores/electronics-by-nic/)

## 10. GEWÄHLT (07.07.): Option B — Bedarfsliste (Minew Offline-Server auf eigenem Server)

Entscheidung: WorkTime bleibt Preis-Quelle, ESL-Stack = Minews **Offline-System** auf dem **eigenen
Server** des Nutzers, WorkTime-Brücke wird selbst gebaut. (§9-DIY damit nicht weiterverfolgt, bleibt als
Alternative dokumentiert.)

**Was gebraucht wird:**
- **Hardware:** Tags ✅ vorhanden · **Gateway G1/G1-E ❌ fehlt, mind. 1 pro Laden → 2 Stück** (Strom + LAN/WLAN) · eigener Server ✅.
- **Minew-Software:** „ESL Offline System" (On-Prem-Lizenz) auf dem eigenen Server — bindet Tag↔Artikel, pusht via Gateway.
- **Server:** OS/Anforderungen mit Minew klären; **Standort entscheidend** (LAN-Nähe zum Gateway).
- **WorkTime-Seite (Eigenbau):** **Sync-Agent auf dem eigenen Server** (NICHT Cloud Function — Cloud→LAN-Bruch), liest Preise aus WorkTime → mappt per **Barcode/EAN** → pusht an Offline-API **oder** erzeugt CSV/Excel-Import. Schalter `APP_ESL_ENABLED`, Model `EslBinding` (Tag-ID↔Artikel/Barcode), Muster wie `pushOktoposArticles`.
- **Netzwerk:** Gateway ↔ Offline-Server im Laden-LAN erreichbar.

**Blocker (an Minew, vor Bau-Plan):**
1. **Lokale API** zum automatischen Preis-Einspielen — oder nur CSV/Excel-Import oder nur manuelle UI? (Kritischste Frage.)
2. Läuft auf eigenem Server (welches OS/Anforderungen)? Offline-Lizenz im Preis oder Aufpreis?
3. Passender Gateway für die 2.9″-Tags, Standalone-Preis, Tags/Reichweite pro Gateway, sind die gekauften Tags fürs Offline-System provisioniert?

**⚠️ Multi-Standort-Frage:** „Offline" erwartet Server meist im selben LAN wie der Gateway. Bei 2 Läden entweder
(a) zentraler Server + Remote-Gateway-Support/VPN, oder (b) pro Laden eine Offline-Instanz. Hängt am Server-Standort
(in einem Laden / zentral-VPS / zuhause) — mit Nutzer + Minew klären.

**Kosten grob:** Gateway ~185 €/Stück → ~370 € für 2 Läden · Offline-Lizenz unbekannt (Angebot) · Sync-Agent = interne Entwicklung.

**Nächste Schritte:** (1) Anfrage-Mail an Minew mit den 3 Blockern. (2) Gateway(s) bestellen. (3) Server-Standort/OS
festlegen. (4) Danach Bau-Plan Sync-Agent schreiben.

## 11. Alternative in Prüfung (07.07.): GATEWAY-FREI — BLE/NFC direkt aus WorkTime

Nutzer fragt, ob es **ohne Gateway** geht: Schild per **Bluetooth/NFC** direkt am Regal ändern. **Ja — aber
nicht mit den Minew-Tags** (proprietär, gateway-gebunden; nRF52810 hat kein NFC). Mit passenden Tags geht genau das:

- **Weg 1 — BLE-direkt (Gicisky / Hanshow-ATC):** sehr einfaches BLE-Protokoll, Bespielen direkt per (Android-)
  Handy, **kein Gateway/Server**. Offen belegt: `fpoli/gicisky-tag` (Python), `eigger/hass-gicisky` (HA),
  atc1441 WebBluetooth-Image-Uploader, `atc1441/ATC_TLSR_Paper` (Hanshow). Günstig (wenige €/Tag AliExpress),
  Knopfzelle ~1 J. Reichweite ~BLE (~10 m), ein Tag nach dem anderen.
- **Weg 2 — NFC-powered (Waveshare 2.9″):** batterielos, per NFC-Handy **antippen** → Strom+Daten über NFC,
  Display aktualisiert. ~18 $, Android-App/Format vorhanden.

**WorkTime-Fit (stark):** WorkTime ist Handy-App mit Scanner-Tab. Flow **ohne Gateway/Server**: Produkt-Barcode
scannen → WorkTime kennt Preis → per BLE mit Schild verbinden (oder NFC antippen) → Preis-Bild pushen. Umsetzung
via `flutter_blue_plus` + offenes Gicisky/ATC-Protokoll direkt in den Scanner-Flow. **Android** ist der sichere Pfad.

**Kompromiss vs. Option B:** gateway-frei = **physisch an jedes Schild** (kein Zentral-/Fern-/Bulk-Push), dafür
kein Gateway/Server, viel billiger, simpler. Gut für kleinen Laden mit gelegentlichen Preisänderungen; Gateway
gewinnt bei häufigen Massen-Updates.

**Entscheidung offen:** Option B (Gateway-zentral, Minew) **vs.** gateway-frei (BLE/NFC-direkt, Gicisky/Waveshare,
kein Minew). Bei gateway-frei: Test-Charge Gicisky 2.9″ BLE (empfohlen) oder Waveshare 2.9″ NFC bestellen, dann
BLE/NFC-Push in WorkTime bauen.

### Quellen §11
- [Gicisky BLE-ESL — HA-Community-Thread](https://community.home-assistant.io/t/support-for-gicisky-e-ink-ble-esl-labels/778693)
- [fpoli/gicisky-tag (Python-Steuerung)](https://github.com/fpoli/gicisky-tag)
- [eigger/hass-gicisky (Home Assistant)](https://github.com/eigger/hass-gicisky)
- [atc1441 Gicisky WebBluetooth Image Uploader](https://atc1441.github.io/ATC_GICISKY_Paper_Image_Upload.html)
- [atc1441/ATC_TLSR_Paper (Hanshow BLE-FW)](https://github.com/atc1441/ATC_TLSR_Paper)
- [Waveshare 2.9″ NFC-Powered e-Paper (batterielos)](https://www.waveshare.com/2.9inch-nfc-powered-e-paper.htm)
- [TagTinker (Hackaday 2026)](https://hackaday.com/2026/05/04/tagtinker-lets-you-hack-electronic-shelf-labels/)
