# Shell / Navigation / Bootstrap

> Teil des WorkTime-Code-Reviews. Zurück zur [Übersicht](README.md).

### 56. Force-Update-Gate hängt von fire-and-forget updateSession ab — auf veralteten Release-Builds bleibt der Block bis zum nächsten Rebuild aus

- **Schweregrad:** Niedrig  ·  **Kategorie:** race-lifecycle  ·  **Konfidenz:** medium  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/main.dart`, `lib/providers/feature_flag_provider.dart`

**Problem.** Im _AuthGate (main.dart:655-662) entscheidet featureFlags.requiresUpdate, ob ein zu altes Binary den ForceUpdateScreen sieht. requiresUpdate (feature_flag_provider.dart:38-39) wird erst wahr, nachdem updateSession() den Remote-Config-Read abgeschlossen hat. updateSession wird über _dispatchProviderUpdate (main.dart:475-488) bewusst fire-and-forget gestartet; der ProxyProvider-update-Callback kehrt synchron zurück. Da der FeatureFlagProvider beim erfolgreichen Laden _safeNotify aufruft (feature_flag_provider.dart:98), führt das zu einem zweiten Rebuild des _AuthGate, der dann blockiert. Es gibt jedoch ein Zeitfenster zwischen 'authentifiziert' und 'Config geladen', in dem ein veraltetes Binary die HomeScreen voll nutzbar sieht. Das ist als fail-open dokumentiert/gewollt, aber das Gate ist damit kein harter Block, sondern ein verzögerter Hinweis.

**Auswirkung.** Ein per Server zwingend zu aktualisierendes (z.B. wegen API-Bruch) Binary kann nach dem Login kurzzeitig (bis der async Config-Read durchläuft, bei schlechter Verbindung auch länger) voll arbeiten und Writes absetzen, bevor der Block greift. Niedrige Severity, da Schutz fail-open by design ist und Compliance serverseitig in den Callables nochmals geprüft wird.

**Beleg.** main.dart:655-662 (Gate liest featureFlags.requiresUpdate erst nach isAuthenticated) · main.dart:475-488 _dispatchProviderUpdate(unawaited(...)) · feature_flag_provider.dart:38-39, 73-83, 98

**Empfehlung.** Falls das Gate harte Wirkung haben soll: während noch keine Remote-Config aufgelöst ist und der Nutzer authentifiziert ist, einen kurzen Lade-/Prüfzustand anzeigen statt direkt HomeScreen, oder requiresUpdate erst nach erstem abgeschlossenem fetch als 'aussagekräftig' markieren. Andernfalls die fail-open-Lücke explizit als akzeptiert dokumentieren.

### 57. Keyboard-Shortcuts Strg+1..9 sind in der mobilen Bottom-Nav-Layout aktiv und mappen auf railDestinations (ohne Profil-Tab) statt auf die sichtbaren Bottom-Nav-Ziele

- **Schweregrad:** Niedrig  ·  **Kategorie:** ux  ·  **Konfidenz:** medium  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/screens/home_screen.dart`

**Problem.** Die Shortcut-Bindings werden im build() unabhängig vom Layout aus railDestinations gebaut (home_screen.dart:112-118), wobei railDestinations das Profil-Ziel herausfiltert (home_screen.dart:103-105). CallbackShortcuts umschließt den gesamten Subtree (home_screen.dart:120), auch wenn useRail==false (Bottom-Nav auf schmalen Geräten/Fenstern). Damit gilt in der Bottom-Nav-Ansicht: Strg+N springt auf die N-te RAIL-Destination, die NICHT mit der Reihenfolge/Menge der sichtbaren Bottom-Nav-Ziele (inkl. Profil) übereinstimmt. Profil ist per Shortcut nie erreichbar; in V1-Bottom-Nav ist die Indizierung gegenüber der sichtbaren Leiste leicht verschoben (Profil ist als letztes Bottom-Nav-Ziel vorhanden, fehlt aber in railDestinations).

**Auswirkung.** Auf Geräten/Fenstern mit physischer Tastatur und Bottom-Nav (z.B. schmales Desktop-/Web-Fenster < 600px Breite mit Tastatur) lösen Strg+1..9 Sprünge aus, die nicht der sichtbaren Navigationsleiste entsprechen. Reiner UX-Inkonsistenz-Effekt, kein Crash, keine Datenwirkung.

**Beleg.** home_screen.dart:103-105 (railDestinations filtert profile) · home_screen.dart:112-118 (Bindings aus railDestinations) · home_screen.dart:120-121 (CallbackShortcuts umschließt alles, vor LayoutBuilder) · home_screen.dart:267-283 (Bottom-Nav nutzt vollständige destinations)

**Empfehlung.** Die Shortcut-Bindings an das tatsächliche Navigationsmodell des aktuellen Layouts koppeln: im Bottom-Nav-Fall die vollständige destinations-Liste verwenden (und _handleDestinationTap mit destinations aufrufen), im Rail-Fall railDestinations. Die LayoutBuilder-Info (useRail) ist verfügbar und sollte in die Binding-Berechnung einfließen.

### 58. PopScope: Wenn _navHistory keine gültige Rück-Destination mehr enthält, wird der erste Zurück-Druck verschluckt — App schließt erst beim zweiten Druck

- **Schweregrad:** Niedrig  ·  **Kategorie:** ux  ·  **Konfidenz:** low  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/screens/home_screen.dart`

**Problem.** PopScope.canPop ist _navHistory.isEmpty (home_screen.dart:124). Ist Historie vorhanden, ist canPop=false und onPopInvokedWithResult ruft _navigateBackInShell (home_screen.dart:125-130). _navigateBackInShell (home_screen.dart:348-373) entfernt in der while-Schleife sukzessive Historieneinträge; sind alle Einträge ungültig (index==-1, z.B. weil sich die Destination-Liste durch Profil-/Permission-Änderung verkleinert hat) oder gleich der aktuellen ID, leert es die Historie komplett und gibt false zurück, ohne zu navigieren. Da der System-Pop bereits konsumiert wurde (didPop=false), passiert beim ersten Zurück nichts Sichtbares; erst der nächste Zurück (jetzt canPop=true) schließt die App.

**Auswirkung.** Seltener Sonderfall (Historie enthält nur Ziele, die nach Permission-Reduktion verschwunden sind). Folge: ein 'toter' Zurück-Druck, danach normales Verhalten. Kein Crash, kein Datenverlust.

**Beleg.** home_screen.dart:124-130 (PopScope) · home_screen.dart:348-373 (_navigateBackInShell leert Historie, return false)

**Empfehlung.** In _navigateBackInShell bei false-Rückgabe (keine gültige Ziel-Destination) explizit das System-Pop nachholen (z.B. Navigator.maybePop / SystemNavigator) oder vorab ungültige Historieneinträge beim Neuaufbau der Destinations bereinigen, sodass canPop konsistent zur tatsächlichen Navigierbarkeit ist.

### 59. CLAUDE.md/Doku nennt Rail-Breakpoint 1120, Code verwendet 600 (mediumWindow) — irreführende Invarianten-Doku für künftige Änderungen

- **Schweregrad:** Niedrig  ·  **Kategorie:** maintainability  ·  **Konfidenz:** high  ·  **Status:** Einzelpass (unverifiziert)
- **Fundstellen:** `lib/screens/home_screen.dart`, `lib/widgets/responsive_layout.dart`

**Problem.** CLAUDE.md (UI-Konventionen) beschreibt 'Rail-vs-BottomNav-Breakpoint ist hartes >= 1120 in home_screen'. Tatsächlich entscheidet home_screen.dart:137-139 über MobileBreakpoints.useNavigationRail(constraints.maxWidth), und useNavigationRail prüft width >= mediumWindow == 600 (responsive_layout.dart:18,25). Der Wert 1120 kommt im gesamten lib/ nicht vor (Grep ohne Treffer). Die Doku-Aussage ist veraltet/falsch.

**Auswirkung.** Keine Laufzeitwirkung. Risiko liegt in der Zukunft: Wer sich beim Anpassen des Layouts auf die in CLAUDE.md (laut Auftrag verbindliche Autorität) genannten 1120 verlässt, trifft falsche Annahmen über das Umschaltverhalten (z.B. iPad-Portrait/Split-View ab 600px nutzt bereits die Rail).

**Beleg.** home_screen.dart:137-139 useNavigationRail(constraints.maxWidth) && maxHeight>=mediumWindow · responsive_layout.dart:18 mediumWindow=600, :25 useNavigationRail => width>=mediumWindow · grep '1120' in lib/ ohne Treffer

**Empfehlung.** CLAUDE.md auf den tatsächlichen Wert (mediumWindow=600 für Rail, expandedWindow=840 für volle Rail-Labels) korrigieren, oder — falls 1120 die gewünschte Schwelle war — den Code anpassen. Die beiden Quellen (Doku und MobileBreakpoints) in Einklang bringen.
