import '../models/product_batch.dart';

/// Dringlichkeit einer MHD-/Ablauf-Warnung.
enum ExpirySeverity {
  /// MHD liegt in der Vergangenheit (Tage < 0) — am dringendsten.
  expired,

  /// Laeuft heute oder morgen ab (Tage <= 1).
  critical,

  /// Laeuft in den naechsten Tagen ab (innerhalb `leadDays`).
  soon;

  String get label {
    switch (this) {
      case ExpirySeverity.expired:
        return 'Abgelaufen';
      case ExpirySeverity.critical:
        return 'Läuft heute/morgen ab';
      case ExpirySeverity.soon:
        return 'Läuft bald ab';
    }
  }
}

/// Eine Ablauf-Warnung fuer genau eine Charge.
class ExpiryWarning {
  const ExpiryWarning({
    required this.batch,
    required this.daysUntilExpiry,
  });

  final ProductBatch batch;

  /// Ganze Kalendertage bis zum MHD; negativ = bereits abgelaufen.
  final int daysUntilExpiry;

  ExpirySeverity get severity {
    if (daysUntilExpiry < 0) return ExpirySeverity.expired;
    if (daysUntilExpiry <= 1) return ExpirySeverity.critical;
    return ExpirySeverity.soon;
  }
}

/// **MHD-/Ablauf-Warnungen** — reine, deterministische Ableitung analog
/// `computeFridgeShortfalls`: kein State, kein IO, **kein `DateTime.now()`** —
/// [now] wird injiziert. Meldet aktive Chargen, deren MHD in <= [leadDays]
/// Kalendertagen liegt (abgelaufene eingeschlossen), aufsteigend nach
/// Restlaufzeit (dringendste zuerst), optional auf einen Standort ([siteId])
/// beschraenkt.
List<ExpiryWarning> computeExpiryWarnings(
  Iterable<ProductBatch> batches,
  DateTime now, {
  int leadDays = 3,
  String? siteId,
}) {
  final nowDay = _dayNumber(now);
  final result = <ExpiryWarning>[];
  for (final batch in batches) {
    if (batch.status != BatchStatus.active) continue;
    if (siteId != null && siteId.isNotEmpty && batch.siteId != siteId) {
      continue;
    }
    final days = _dayNumber(batch.expiryDate) - nowDay;
    if (days > leadDays) continue;
    result.add(ExpiryWarning(batch: batch, daysUntilExpiry: days));
  }
  result.sort((a, b) => a.daysUntilExpiry.compareTo(b.daysUntilExpiry));
  return result;
}

/// Kalendertag als ganzzahliger Tageszaehler (Tage seit Epoche), **DST-robust**
/// ueber UTC — nur das Datum zaehlt, nie die Uhrzeit. Vermeidet Off-by-one, das
/// bei einem reinen Millisekunden-Delta ueber Sommerzeit-Grenzen entstuende.
int _dayNumber(DateTime date) {
  return DateTime.utc(date.year, date.month, date.day)
          .millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
}
