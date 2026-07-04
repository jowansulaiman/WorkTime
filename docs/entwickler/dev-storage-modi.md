# Speichermodi & lokale Persistenz

WorkTime kennt **drei Speichermodi** (`StorageModeProvider`, enum `DataStorageLocation{hybrid(Default), cloud, local}`). Jeder Datenmutator muss alle drei bedienen.

## Die drei Modi

- **local**: nur SharedPreferences.
- **cloud**: nur Firestore-Streams.
- **hybrid (Default)**: Cloud-Reads, lokal gecacht.

Im **hybrid**-Modus wird *userContent* (Schichten, Zeiteinträge, Templates, Abwesenheiten) zusätzlich in SharedPreferences gespiegelt – das spart bezahlte Firestore-Writes (Spark-Free-Tier). *Stammdaten* (sites/teams/quals/contracts/ruleSets/travelTimeRules) werden **nicht** gespiegelt und verlassen sich auf Firestores eigenen Offline-Cache.

## Das Mutator-Muster

```dart
if (usesLocalStorage) {
  // lokal mutieren + persist + notify
  return;
}
try {
  // Firestore-Write versuchen
} catch (e) {
  if (hybrid) {
    // lokal fallbacken (NICHT rethrow)
  } else {
    rethrow; // cloud-only
  }
}
```

> [!WARNING]
> Im catch gilt: bei **hybrid** lokal fallbacken (nicht rethrow), bei **cloud-only** rethrow. Und: `_audit?.call(...)` nur auf dem Erfolgs-Pfad – in JEDEM Storage-Zweig (local-return UND hybrid-catch-Fallback), NIE auf rethrow.

## DatabaseService = SharedPreferences, kein SQLite

> [!IMPORTANT]
> Die lokale Persistenz ist **SharedPreferences** (`shared_preferences`), **kein SQLite**. JSON-Collections unter Key-Namespace `local_v2/...`. Keine DB, kein Schema, keine SQL-Migrationen. `DatabaseService` ist komplett statisch.

Eine **neue lokal-persistierte Collection** braucht:

1. Key in `DatabaseService` registrieren.
2. Über `_orgScopedCollectionKeys` org- vs. user-skopiert entscheiden (nur `work_templates` + Settings sind user-skopiert).
3. Über `_load/_saveCollection` laufen lassen.
4. `toMap`/`fromMap` muss **round-trippen** (snake_case, ISO-Strings – siehe [Zwei-Serialisierungs-Regel](article:dev-zwei-serialisierung)).

## Test-Hinweis

In `setUp`: `SharedPreferences.setMockInitialValues({}); DatabaseService.resetCachedPrefs();` – der Prefs-Cache ist statisch.

## Weiter

- [Die Zwei-Serialisierungs-Regel](article:dev-zwei-serialisierung)
- [Firestore-Datenmodell](article:dev-datenmodell-firestore)
