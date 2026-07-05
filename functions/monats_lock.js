"use strict";

// Monats-Festschreibung (PA-5) — pure, SDK-freie Helfer fuer den serverseitigen
// Guard in upsertWorkEntry/upsertWorkEntryBatch. Spiegel der Dart-Seite
// (lib/core/monats_festschreibung.dart + ZeitkontoSnapshot.buildId): Regel hier
// aendern -> dort mitziehen (Kopplungs-Disziplin wie beim Compliance-Spiegel).
// Offline unit-testbar via `node --test` (functions/test/monats_lock.test.js).

/// Deterministische Doc-ID des Monats-Snapshots: `{userId}-{jahr}-{mm}`
/// (Monat zero-padded — exakt `ZeitkontoSnapshot.buildId`).
function zeitkontoSnapshotId(userId, jahr, monat) {
  return `${userId}-${jahr}-${String(monat).padStart(2, "0")}`;
}

/// Pure Entscheidung: gilt der Monat laut Snapshot-Daten als festgeschrieben?
/// `null`/fehlendes Doc => nicht festgeschrieben (Snapshot entsteht erst beim
/// Monatsabschluss).
function istFestgeschrieben(snapshotData) {
  return Boolean(snapshotData) && snapshotData.abgeschlossen === true;
}

/// Deutsche Fehlermeldung — Wortlaut deckungsgleich mit
/// `MonatsFestschreibung.meldung` (Dart), damit die UI unabhaengig vom
/// greifenden Layer dasselbe sagt.
function festgeschriebenMeldung(monat, jahr) {
  return `Der Monat ${String(monat).padStart(2, "0")}/${jahr} ist ` +
    "festgeschrieben. Änderungen sind erst nach Zurücknahme des " +
    "Monatsabschlusses möglich.";
}

/// Jahr/Monat eines WorkEntry-Datums fuer den Lock-Check. `WorkEntry.date`
/// kommt als lokaler `YYYY-MM-DD`-String durch die Callable und wird von
/// `parseDate` als UTC-Mitternacht geparst -> UTC-Komponenten sind exakt der
/// fachliche Kalendertag (kein Zeitzonen-Kippen; bewusst getUTC*).
function jahrMonatVon(date) {
  if (!(date instanceof Date) || Number.isNaN(date.getTime())) {
    return null;
  }
  return {jahr: date.getUTCFullYear(), monat: date.getUTCMonth() + 1};
}

module.exports = {
  zeitkontoSnapshotId,
  istFestgeschrieben,
  festgeschriebenMeldung,
  jahrMonatVon,
};
