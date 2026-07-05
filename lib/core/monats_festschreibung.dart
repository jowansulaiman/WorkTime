import '../models/zeitkonto_snapshot.dart';

/// Signatur zum Nachladen des Monats-Snapshots eines Mitarbeiters
/// (`zeitkontoSnapshots/{userId}-{jahr}-{mm}`). Liefert `null`, wenn (noch)
/// kein Snapshot existiert — ein Monat ohne Snapshot ist NIE festgeschrieben
/// (der Snapshot entsteht erst beim Monatsabschluss).
typedef ZeitkontoSnapshotLoader = Future<ZeitkontoSnapshot?> Function(
  String userId,
  int jahr,
  int monat,
);

/// **Monats-Festschreibung** (PA-5): zentrale, pure Entscheidungslogik des
/// Client-Guards gegen Änderungen an Zeiteinträgen/Stempelungen eines bereits
/// abgeschlossenen (festgeschriebenen) Monats.
///
/// Drei Enforcement-Schichten (Plan personal-bereich-ausbau §PA-5.1):
/// 1. **Client** (diese Klasse, freundliche deutsche Meldung VOR dem Write),
/// 2. **Callable** (`upsertWorkEntry`/`upsertWorkEntryBatch` →
///    `failed-precondition`, Spiegel in `functions/monats_lock.js`),
/// 3. **Rules** (`workEntries` mit `exists()`-sicherem Snapshot-`get()`;
///    `clockEntries` bewusst NUR Client+Callable — `kommen` ist ein echter
///    Zeitpunkt und kippt in UTC an der Monatsgrenze in den Nachbarmonat,
///    `WorkEntry.date` dagegen ist auf 12:00 LOKAL normalisiert und damit
///    UTC-monatsstabil).
///
/// Regel in einer Schicht ändern → in den anderen mitziehen (Kopplung wie
/// Compliance-Spiegel #2).
abstract final class MonatsFestschreibung {
  MonatsFestschreibung._();

  /// Deutsche Fehlermeldung — identischer Wortlaut in Client und Callable,
  /// damit die UI unabhängig vom greifenden Layer dasselbe sagt.
  static String meldung(int monat, int jahr) =>
      'Der Monat ${monat.toString().padLeft(2, '0')}/$jahr ist festgeschrieben. '
      'Änderungen sind erst nach Zurücknahme des Monatsabschlusses möglich.';

  /// Pure Entscheidung: gilt der Monat als festgeschrieben?
  static bool istFestgeschrieben(ZeitkontoSnapshot? snapshot) =>
      snapshot?.abgeschlossen == true;

  /// Wirft [StateError] mit [meldung], wenn der Monat von [datum] für [userId]
  /// festgeschrieben ist.
  ///
  /// **Fail-open bei Ladefehlern** (bewusst): Kann der Snapshot nicht geladen
  /// werden (z. B. hybrid offline), blockiert der Client NICHT — sonst wäre die
  /// gesamte Offline-Zeiterfassung tot. Callable + Rules bleiben die harten
  /// Schichten; der Client-Guard liefert die frühe, verständliche Meldung.
  static Future<void> assertNichtFestgeschrieben({
    required ZeitkontoSnapshotLoader ladeSnapshot,
    required String userId,
    required DateTime datum,
  }) async {
    ZeitkontoSnapshot? snapshot;
    try {
      snapshot = await ladeSnapshot(userId, datum.year, datum.month);
    } catch (_) {
      return; // fail-open — harte Schichten sind Callable + Rules.
    }
    if (istFestgeschrieben(snapshot)) {
      throw StateError(meldung(datum.month, datum.year));
    }
  }
}
