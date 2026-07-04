# Routing (go_router)

Das Routing läuft über **go_router** (`lib/routing/app_router.dart`), eingebunden als `MaterialApp.router` in `WorkTimeApp`. Die URLs sind deutsch und in der Domain sichtbar.

## Aufbau

- Der Router wird **einmalig** im `Consumer2`-Builder von `WorkTimeApp` memoisiert (`_router ??= buildAppRouter(auth, featureFlags, theme)`).
- `refreshListenable: Listenable.merge([auth, featureFlags, theme])` – jeder Auth-Übergang, Force-Update- oder V1/V2-Flag-Wechsel triggert `_gateRedirect`.
- Der **Analytics-Observer** hängt am `GoRouter(observers:)`, NICHT an `MaterialApp` (dort ignoriert).

## Die Shell

Die App-Shell ist eine `StatefulShellRoute.indexedStack` mit **7 statischen Branches** (lazy, State-erhaltender `IndexedStack`), einer je `ShellTab` (`lib/routing/shell_tab.dart`). Der **Branch-Index ist kanonisch** = `ShellTab.values.indexOf(tab)`; nie die Position der sichtbaren Nav-Items verwenden – immer über die Enum mappen (`shellBranchIndex(tab)`).

Hauptbereiche (`/warenwirtschaft`, `/team`, …) sind **Top-Level-Routen**, via `context.push(AppRoutes.x)` über die Shell gepusht (Back → Hub). Detail-/Editor-Screens bleiben imperativ `Navigator.push(MaterialPageRoute(...))`.

## Gate-Redirect statt AuthGate

`_gateRedirect` reproduziert die frühere `_AuthGate`-Entscheidung als Redirect. Reihenfolge der Blocker:

- `!firebaseConfigured` → `/einrichtung`
- `!initialized` / `isResolvingProfile` → `/start`
- `!isAuthenticated` → `/anmelden`
- `profile && !isActive` → `/gesperrt`
- `requiresUpdate` → `/aktualisierung`
- Kiosk-Build → `/arbeitsmodus`
- danach Pending-Quick-Action / Push-Route
- sonst: **Permission-Gating** via `RoutePermissions.isLocationAllowed(loc, profile)` (Deep-Link ohne Recht → `/`)

> [!IMPORTANT]
> Berechtigungen sind **Single Source of Truth** in `RoutePermissions` (`lib/routing/route_permissions.dart`) – geteilt zwischen Redirect und Home-Screen. Die serverseitige Spiegelung in `firestore.rules` bleibt getrennt, muss aber dieselben Regeln tragen.

## Eine Route/einen Tab hinzufügen

- **Neuer Hauptbereich-Screen mit URL**: `AppRoutes`-Konstante + `_sectionRoute(...)` in `buildAppRouter` + `case` in `RoutePermissions.isLocationAllowed`, Aufruf via `context.push(AppRoutes.x)`.
- **Neuer Tab**: `ShellTab`-Enum erweitern (Reihenfolge = Branch-Index!) + `StatefulShellBranch` + `_destinationMeta`/`_isTabVisible`/`buildHomeTab` im Home-Screen.

> [!NOTE]
> Der Wissens-Bereich (`/wissen`) ist ein solcher Hauptbereich: Konstante `AppRoutes.knowledge`, `_sectionRoute`, `case AppRoutes.knowledge: return p != null` und Einstiegskacheln in Home/Nav-Menü.

## Weiter

- [Bootstrap & main.dart](article:dev-bootstrap-main)
- [Sicherheit & Mandantentrennung](article:dev-sicherheit-multi-tenancy)
