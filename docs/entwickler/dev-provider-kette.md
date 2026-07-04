# Provider-Kette & State-Management

Der State liegt in `ChangeNotifier`-Providern (`package:provider`). Die **Reihenfolge der Provider in `lib/main.dart` ist tragend** – neue abhängige Provider gehören DANACH eingefügt.

## Die Kette

```
AuthProvider(.value, vor runApp init'd) → ThemeProvider → StorageModeProvider
  → FeatureFlagProvider (Proxy2<Auth,Storage>)   // erster Proxy, vom go_router-Redirect gelesen
  → AuditProvider (Proxy2<Auth,Storage>)         // Änderungsprotokoll (best-effort), FRÜH
  → TeamProvider (Proxy3<Auth,Storage,Audit>)    // einziger Produzent von Stammdaten
  → ScheduleProvider (Proxy4<Auth,Team,Storage,Audit>)
  → InventoryProvider (Proxy3<Auth,Storage,Audit>)
  → ContactProvider (Proxy3<Auth,Storage,Audit>)
  → PersonalProvider (Proxy4<Auth,Team,Storage,Audit>)
  → WorkProvider (Proxy5<Auth,Team,Storage,Schedule,Audit>)
```

## Proxy-Regeln

- Jeder Proxy ruft `provider.updateSession(auth.profile, localStorageOnly: storage.isLocalOnly, hybridStorageEnabled: storage.isHybrid)`.
- `updateSession` ist **async**, der Proxy-Callback aber sync → Ausführung via `_dispatchProviderUpdate` **fire-and-forget**. Fehler werden nur per `debugPrint` geloggt.

> [!WARNING]
> Nie annehmen, dass `updateSession` beim Rebuild bereits fertig ist. Es läuft fire-and-forget.

## Referenzdaten & Provider→Provider

- `TeamProvider` schiebt seine Listen **synchron** via `updateReferenceData(...)` in Schedule/Work (die lesen Stammdaten nie selbst). Diese Setter rufen **kein** `notifyListeners` (sonst Rebuild-Loops).
- `WorkProvider` bekommt zusätzlich die lebende `ScheduleProvider`-Instanz via `updateScheduleProvider` – der einzige direkte Provider→Provider-Call (markiert Schicht als completed bei Entry-Save).

## Lazy Cloud-Repository

> [!IMPORTANT]
> Inventory/Contact/Audit/Personal lösen ihr Cloud-Repository **lazy** auf (nie im Konstruktor) – sonst Crash im `APP_DISABLE_AUTH`/Web-Modus. Neue abhängige Provider genauso.

## AuditSink

`AuditProvider` ist absichtlich FRÜH registriert, damit jeder Daten-Provider via `provider.setAuditSink(audit.log)` die best-effort-Senke `AuditSink` (`lib/providers/audit_sink.dart`, fire-and-forget, wirft nie) bezieht. Details: [Änderungsprotokoll (Audit)](article:dev-audit-trail).

## Sicheres Benachrichtigen

> [!TIP]
> In async-/Stream-/Timer-Callbacks immer `_safeNotify()` verwenden (prüft `_disposed`), nie bare `notifyListeners`.

## Weiter

- [Speichermodi & lokale Persistenz](article:dev-storage-modi)
- [Routing (go_router)](article:dev-routing)
- [Kritische Kopplungen](article:dev-kritische-kopplungen)
