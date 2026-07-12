// Pure Auswertung der Scan-Telemetrie ([ScanEvent]) fuer die Scan-Statistik.
// Kein now()/IO — [now] wird injiziert, deterministisch offline testbar
// (Muster: computeExpiryWarnings in expiry_warning.dart).

import '../models/scan_event.dart';

/// Ein Code, der wiederholt NICHT zum Treffer fuehrte — Kandidat fuer
/// „Barcode fehlt am Artikel", beschaedigtes Etikett oder Fremdsortiment.
class FailingCode {
  const FailingCode({
    required this.code,
    required this.attempts,
    required this.notFound,
    required this.invalidChecksum,
    this.lastTriedAt,
  });

  final String code;

  /// Fehlversuche gesamt (notFound + invalidChecksum).
  final int attempts;
  final int notFound;
  final int invalidChecksum;
  final DateTime? lastTriedAt;
}

/// Kennzahlen ueber die Scans eines Zeitfensters.
class ScanStats {
  const ScanStats({
    required this.total,
    required this.matched,
    required this.multiMatch,
    required this.notFound,
    required this.invalidChecksum,
    required this.manualEntries,
    required this.photoScans,
    required this.averageTimeToHitMs,
    required this.medianTimeToHitMs,
    required this.failingCodes,
    required this.byPlatform,
    required this.bySource,
    required this.byMode,
  });

  const ScanStats.empty()
      : this(
          total: 0,
          matched: 0,
          multiMatch: 0,
          notFound: 0,
          invalidChecksum: 0,
          manualEntries: 0,
          photoScans: 0,
          averageTimeToHitMs: null,
          medianTimeToHitMs: null,
          failingCodes: const [],
          byPlatform: const {},
          bySource: const {},
          byMode: const {},
        );

  final int total;
  final int matched;
  final int multiMatch;
  final int notFound;
  final int invalidChecksum;

  /// Manuell eingetippte Codes — ein hoher Anteil heisst: die Kamera versagt
  /// im Alltag (das eigentliche Alarmsignal dieser Statistik).
  final int manualEntries;

  /// Ueber die Standbild-Analyse („Foto scannen") erkannte Codes.
  final int photoScans;

  final int? averageTimeToHitMs;
  final int? medianTimeToHitMs;

  /// Codes mit den meisten Fehlversuchen, absteigend.
  final List<FailingCode> failingCodes;

  final Map<String, int> byPlatform;
  final Map<String, int> bySource;
  final Map<String, int> byMode;

  /// Anteil der Scans, die einen Artikel fanden (Treffer + Mehrfachtreffer).
  double get hitRate => total == 0 ? 0 : (matched + multiMatch) / total;

  /// Anteil manueller Eingaben an allen Versuchen.
  double get manualShare => total == 0 ? 0 : manualEntries / total;

  bool get isEmpty => total == 0;
}

/// Wertet [events] fuer die letzten [windowDays] Tage vor [now] aus.
///
/// [siteId] filtert optional auf einen Laden; Events ohne Zeitstempel werden
/// mitgezaehlt (lokale Events tragen immer einen, Cloud-Events praktisch auch).
ScanStats computeScanStats(
  List<ScanEvent> events, {
  required DateTime now,
  int windowDays = 30,
  String? siteId,
  int maxFailingCodes = 10,
}) {
  final cutoff = now.subtract(Duration(days: windowDays));
  final relevant = events.where((event) {
    if (siteId != null && siteId.isNotEmpty && event.siteId != siteId) {
      return false;
    }
    final at = event.createdAt;
    return at == null || !at.isBefore(cutoff);
  }).toList();

  if (relevant.isEmpty) return const ScanStats.empty();

  var matched = 0;
  var multiMatch = 0;
  var notFound = 0;
  var invalidChecksum = 0;
  var manualEntries = 0;
  var photoScans = 0;
  final hitTimes = <int>[];
  final byPlatform = <String, int>{};
  final bySource = <String, int>{};
  final byMode = <String, int>{};
  final failing = <String, ({int notFound, int invalid, DateTime? lastAt})>{};

  for (final event in relevant) {
    switch (event.outcome) {
      case ScanOutcome.matched:
        matched++;
      case ScanOutcome.multiMatch:
        multiMatch++;
      case ScanOutcome.notFound:
        notFound++;
      case ScanOutcome.invalidChecksum:
        invalidChecksum++;
    }
    if (event.source == 'manual') manualEntries++;
    if (event.source == 'photo') photoScans++;

    final platform = event.platform ?? 'unbekannt';
    byPlatform[platform] = (byPlatform[platform] ?? 0) + 1;
    final source = event.source ?? 'unbekannt';
    bySource[source] = (bySource[source] ?? 0) + 1;
    final mode = event.mode ?? 'unbekannt';
    byMode[mode] = (byMode[mode] ?? 0) + 1;

    final timeToHit = event.timeToHitMs;
    if (event.outcome == ScanOutcome.matched && timeToHit != null) {
      hitTimes.add(timeToHit);
    }

    if (event.outcome == ScanOutcome.notFound ||
        event.outcome == ScanOutcome.invalidChecksum) {
      final prev = failing[event.code];
      final at = event.createdAt;
      final prevAt = prev?.lastAt;
      final lastAt = prevAt == null
          ? at
          : (at == null || at.isBefore(prevAt) ? prevAt : at);
      failing[event.code] = (
        notFound: (prev?.notFound ?? 0) +
            (event.outcome == ScanOutcome.notFound ? 1 : 0),
        invalid: (prev?.invalid ?? 0) +
            (event.outcome == ScanOutcome.invalidChecksum ? 1 : 0),
        lastAt: lastAt,
      );
    }
  }

  hitTimes.sort();
  final average = hitTimes.isEmpty
      ? null
      : (hitTimes.reduce((a, b) => a + b) / hitTimes.length).round();
  final median = hitTimes.isEmpty ? null : hitTimes[hitTimes.length ~/ 2];

  final failingCodes = failing.entries
      .map(
        (entry) => FailingCode(
          code: entry.key,
          attempts: entry.value.notFound + entry.value.invalid,
          notFound: entry.value.notFound,
          invalidChecksum: entry.value.invalid,
          lastTriedAt: entry.value.lastAt,
        ),
      )
      .toList()
    ..sort((a, b) {
      final byAttempts = b.attempts.compareTo(a.attempts);
      if (byAttempts != 0) return byAttempts;
      return a.code.compareTo(b.code); // stabil bei Gleichstand
    });

  return ScanStats(
    total: relevant.length,
    matched: matched,
    multiMatch: multiMatch,
    notFound: notFound,
    invalidChecksum: invalidChecksum,
    manualEntries: manualEntries,
    photoScans: photoScans,
    averageTimeToHitMs: average,
    medianTimeToHitMs: median,
    failingCodes: failingCodes.take(maxFailingCodes).toList(growable: false),
    byPlatform: byPlatform,
    bySource: bySource,
    byMode: byMode,
  );
}
