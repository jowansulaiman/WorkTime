# Digitale Werbe-Displays (Digital Signage)

**Stand:** 08.07.2026 · code-fertig + getestet (flutter analyze clean, 1701 Tests grün), **offen: Deploy** (firestore:rules + firestore:indexes[keine neuen] + storage + hosting) + Feature-Flag-Aktivierung + Commit.

## Ziel

Werbung/Bilder auf den Laden-Fernsehern zentral verwalten und anzeigen. **Nur Admin.**
Zwei Läden in Kiel (Strichmännchen, Tabak Börse), je ein/mehrere Displays möglich, pro Display eigene Playlist.

## Entscheidungen (mit dem Nutzer abgestimmt)

1. **Anzeige-Weg:** öffentliche Web-URL — jeder TV / Fire-TV-Stick / Android-Box öffnet im Browser
   `…/anzeige/<token>` und spielt Vollbild in Schleife ab. Kein Login am Gerät. **Kein Blaze nötig**
   (nur Firestore-Reads + Storage-GET + Hosting).
2. **Medien:** nur Bilder (JPG/PNG/WebP/GIF). Video ist additiv später nachrüstbar (video_player + Projektions-Slide-Typ).
3. **Zielsteuerung:** pro Display steuerbar (Name + optionaler Standort + eigene Playlist + Anzeigedauer).

## Architektur

**Admin-Hälfte** (interne App, admin-only Section-Route `/werbung`, Kachel „Displays & Werbung" im Laden-Hub):
- Werbebilder hochladen (`DocumentStorage`-Seam wie Personalakte/Kontakt-Avatar; Bytes via `file_picker withData:true`, Web+Mobile).
- Displays anlegen, Standort zuweisen, Playlist ordnen (Drag&Drop), Anzeigedauer + Einpassung (füllen/ganz zeigen), aktiv/pausiert.
- Fernseh-Link kopieren.

**Player-Hälfte** (öffentliche Web-Route `/anzeige/<token>`, isoliert wie `/wunsch` — kein go_router, keine Provider-Kette):
- Liest login-frei `publicDisplays/{token}` als Live-Stream, spielt Bilder in Vollbild-Schleife (per-Slide-Standzeit).
- Bilder via tokenisierte `getDownloadURL` direkt ins `Image.network` (umgeht Storage-Rules, kein CORS).
- `WakelockPlus` hält den Bildschirm wach. Ändert der Admin die Playlist → TV aktualisiert sich selbst.

## Datenmodell

Org-skopiert (`organizations/{orgId}/…`, admin-write):
- **`adMedia/{id}`** — Werbebild-Bibliothek: `title`, `storagePath`, `downloadUrl`, `contentType`, `fileSize`. (`lib/models/ad_media.dart`)
- **`signageDisplays/{id}`** — Display: `name`, `siteId?`, `pairingToken`, `slideSeconds`, `fit`, `transition`, `mediaIds[]`, `isActive`. (`lib/models/signage_display.dart`)
  - `transition` (Enum `SignageTransition`): Übergangs-Animation je Display — `fade`/`slide`/`zoom`/`kenBurns` (`ken_burns`)/`none`. Admin wählt im Editor (Dropdown); Player wendet an (AnimatedSwitcher-transitionBuilder; Ken-Burns = Fade + langsamer Transform.scale über die Standzeit via TweenAnimationBuilder). Kopplung #1 (6 Stellen) + #3 (Enum value/fromValue/label).

Top-Level (öffentlich lesbar, per-Token):
- **`publicDisplays/{token}`** — denormalisierte Projektion (aufgelöste Bild-URLs + Standzeit): `{orgId, name, slideSeconds, fit, isActive, slides:[{url,seconds,title}]}`. Wird vom Admin-Client mitgeschrieben; der Player liest nur.

Storage: `organizations/{orgId}/signage/{id}.{ext}` (admin-write, image/*, <10 MB).

## Sicherheit (firestore.rules + storage.rules)

- `adMedia`/`signageDisplays`: `read: sameOrg`, `create/update: isAdmin && sameOrg && body.orgId==orgId`, `delete: isAdmin && sameOrg` (Muster workTasks).
- `publicDisplays/{token}`: **`allow get: if true; allow list: if false;`** (Token = Bearer-Secret, keine Aufzählung), `create/update/delete: isAdmin && orgId==currentOrgId`.
- Storage `signage/`: admin-write; **kein** öffentlicher Read nötig (Player nutzt Download-URL-Token).
- Client-Gate: `RoutePermissions.isLocationAllowed(/werbung) → isAdmin` + in-Screen Defense-in-depth + Kachel `if (isAdmin && signageEnabled)`.
- Rollout-Schalter `AppConfig.signageEnabled` (`APP_SIGNAGE_ENABLED`, Default aus) blendet Admin-Bereich aus, bis Rules/Player deployt sind.

## Kopplungen beachtet

- Zwei-Serialisierung an beiden neuen Modellen (camelCase toFirestoreMap + `titleLower`/`nameLower`-Sortierschlüssel; snake_case toMap; clearSiteId-Flag).
- Provider-Kette: `SignageProvider` nach ContactProvider (Proxy3 Auth/Storage/Audit), lazy Cloud-Repo, `setDocumentStorage` wie PersonalProvider, AuditSink nur auf Erfolgspfad („Werbebild"/„Werbe-Display").
- FirestoreService-Getter + DatabaseService-Keys (`ad_media`, `signage_displays`) + `_orgScopedCollectionKeys` + load/save-Wrapper.
- Section-Route: AppRoutes.signage + `_sectionRoute` + `_denseSectionPaths` + isLocationAllowed-Case.
- **Kein neuer Composite-Index** (Streams sortieren per Single-`orderBy` auf `titleLower`/`nameLower`).
- Neue öffentliche Route: `isPublicDisplayRoute()` + Zweig in `_AppBootstrapState.build` + `_publicMode`.

## Neue/geänderte Dateien

Neu: `lib/models/ad_media.dart`, `lib/models/signage_display.dart`, `lib/repositories/signage_repository.dart`,
`lib/repositories/firestore_signage_repository.dart`, `lib/providers/signage_provider.dart`,
`lib/screens/signage/signage_screen.dart`, `lib/screens/public/public_display_app.dart`,
`lib/screens/public/public_display_screen.dart`, `test/signage_model_test.dart`, `test/signage_provider_test.dart`.

Geändert: `lib/core/app_config.dart` (2 Flags), `lib/services/firestore_service.dart`, `lib/services/database_service.dart`,
`lib/main.dart` (Provider + öffentliche Route), `lib/routing/shell_tab.dart`, `lib/routing/app_router.dart`,
`lib/routing/route_permissions.dart`, `lib/screens/home_screen.dart` (Hub-Kachel), `firestore.rules`, `storage.rules`,
`test/route_permissions_test.dart`.

## Deploy / Inbetriebnahme (offen)

1. `firebase deploy --only firestore:rules` (adMedia/signageDisplays/publicDisplays).
2. `firebase deploy --only storage` (signage-Upload-Pfad) — manueller Schritt.
3. Web bauen + deployen (siehe [[web-deploy-prozedur]]: `flutter clean` PFLICHT wegen neuem Web-Plugin `wakelock_plus`/`file_picker`), mit dart-defines:
   - `APP_SIGNAGE_ENABLED=true`
   - `APP_SIGNAGE_PLAYER_BASE_URL=https://<hosting-domain>` (für kopierbaren Link auf Mobil; im Web sonst eigener Origin)
4. Fernseher: Browser öffnen → `https://<domain>/anzeige/<token>` (Link aus der Verwaltung kopieren), Vollbild (F11 / Kiosk-App).
5. Optional: App Check aktivieren (`APP_APPCHECK_RECAPTCHA_KEY`) — schützt den neuen öffentlichen Lesepfad vor Scraping.

## Auto-Start am Fernseher (nach Aus/Ein)

Eine Webseite kann sich beim Einschalten nicht selbst öffnen — Auto-Start ist Sache des Geräts. Die App-Seite ist aber maximal kooperativ:
- **Token-Merker (localStorage):** Der Player speichert seinen Code (`SignageTokenStore`, auf Web = localStorage). Öffnet das Gerät beim Booten die feste Adresse **`…/anzeige`** (ohne Code), nimmt der Player den gemerkten Code und startet die Werbung **automatisch** — ohne erneute Eingabe.
- **Pairing-Seite:** Ist noch nichts gemerkt, zeigt `/anzeige` eine einmalige Code-Eingabe (`_PairingView`). Nach dem Koppeln läuft es künftig von selbst.
- Volle URL `…/anzeige/<code>` funktioniert weiterhin direkt (und merkt den Code zusätzlich).

**Empfohlenes Geräte-Setup (löst Power-On vollständig):** günstiger Fire-TV-Stick / Android-TV-Box + **Fully Kiosk Browser** (Android-App, Signage-Standard): Start-URL = `…/anzeige`, „Start on Boot" + „Keep Screen On" + „Restart on Crash" an. Alternativen: Raspberry Pi `chromium --kiosk --app=…/anzeige` im Autostart. Reine Smart-TV-Browser (Samsung/LG) haben oft keinen Auto-Start-zu-URL → dann Stick/Box davorstecken.

## Offene Punkte / spätere Ausbaustufen

- Video-Slides (video_player + Slide-Typ in der Projektion).
- Zeit-/Tag-Steuerung (Kampagne von–bis, Uhrzeit-Fenster).
- Heartbeat „Display online" (Gerät schreibt `lastSeenAt` — würde einen server-only-Write-Pfad brauchen).
- QR-Code des Player-Links direkt in der Verwaltung (Paket `qr` ist vorhanden).
