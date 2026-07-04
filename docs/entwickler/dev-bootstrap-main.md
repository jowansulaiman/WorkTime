# Bootstrap & main.dart

Der App-Start ist in `lib/main.dart` orchestriert. Die Reihenfolge ist **tragend** – einige Schritte müssen zwingend vor anderen laufen.

## Startsequenz

`main()` führt der Reihe nach aus:

1. `AppConfig.validateEnvironment()` – wirft im Release-Build einen `StateError`, wenn eine unzulässige Konfiguration vorliegt (z. B. `APP_DISABLE_AUTH=true`).
2. `usePathUrlStrategy()` – saubere Web-URLs ohne `#`.
3. Globale **Error-Handler** installieren.
4. `Firebase.initializeApp` – mit Options, wenn konfiguriert; sonst nativ nur auf Android. Ein `duplicate-app`-Fehler wird geschluckt.
5. **Firestore-Offline-Persistence setzen – VOR dem ersten Read!**
6. `authProvider.init()`.

> [!WARNING]
> Die Offline-Persistence muss **vor dem ersten Firestore-Read** gesetzt werden, sonst greift sie nicht. Verschieben Sie keinen Read vor diesen Schritt.

## Öffentliche Web-Routen zuerst

Bestimmte öffentliche Routen liegen bewusst **vor** der Provider-Kette und **vor** go_router – als eigene, isolierte `MaterialApp` ohne `authProvider.init()`:

- `/wunsch` (`PublicWishApp`) und `/feedback` (`PublicFeedbackApp`) – brauchen Firebase (anonymer Schreibpfad).
- `/impressum` + `/datenschutz` (`PublicLegalApp`) – reine Statik ohne Firebase.

`_AppBootstrap` liest `Uri.base` einmalig und wählt zwischen öffentlicher App und `WorkTimeApp` (nur Letztere bekommt go_router). Eine neue öffentliche Route braucht: `isPublic*Route()`, einen Zweig in `_AppBootstrapState.build` und einen Eintrag im `_publicMode`-Getter – und der Pfad darf **nicht** mit einem go_router-Pfad kollidieren.

> [!NOTE]
> Diese Trennung ist eine bewusste Sicherheits-/Kostengrenze: Der öffentliche Schreibpfad läuft nie durch die volle App und lädt keine Nutzerdaten.

## Firebase konfiguriert – oder nicht

`DefaultFirebaseOptions` in `lib/firebase_options.dart` gilt als **konfiguriert**, wenn echte Werte gesetzt sind. Platzhalter (`REPLACE_ME`/`YOUR_VALUE_HERE`/leer) gelten als „unset" → Firebase bleibt still deaktiviert (Demo-/Offline-Modus). Der `bootstrap_frame.dart` liefert den Lade-/Fehlerrahmen während des Starts.

## Weiter

- [Provider-Kette & State-Management](article:dev-provider-kette)
- [Routing (go_router)](article:dev-routing)
- [Konfiguration, dart-defines & Feature-Flags](article:dev-konfiguration-flags)
