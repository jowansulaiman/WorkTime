import '../models/employee_qualification.dart';

/// **PERSONAL-7 — Ablauf-Status einer Qualifikation.**
enum QualiExpiryLevel {
  /// Unbefristet oder noch weit vor dem Vorlauf.
  ok,

  /// Läuft innerhalb des konfigurierten Vorlaufs ab.
  laeuftAb,

  /// Gültigkeit ist bereits überschritten.
  abgelaufen,
}

extension QualiExpiryLevelLabel on QualiExpiryLevel {
  String get label {
    switch (this) {
      case QualiExpiryLevel.ok:
        return 'Gültig';
      case QualiExpiryLevel.laeuftAb:
        return 'Läuft ab';
      case QualiExpiryLevel.abgelaufen:
        return 'Abgelaufen';
    }
  }

  bool get isWarning => this != QualiExpiryLevel.ok;
}

/// Eine Ablauf-Warnung zu genau einer Qualifikation.
class QualiExpiryWarning {
  const QualiExpiryWarning({
    required this.qualification,
    required this.level,
    required this.daysUntilExpiry,
  });

  final EmployeeQualification qualification;
  final QualiExpiryLevel level;

  /// Volle Tage bis zum Ablauf (negativ = bereits abgelaufen).
  final int daysUntilExpiry;
}

/// Bestimmt den Ablauf-Status eines Gültigkeitsdatums gegenüber [now] mit
/// Vorlauf [vorlaufTage]. Rein, deterministisch. `gueltigBis == null` = ok
/// (unbefristet). Ein negativer Vorlauf wird auf 0 geklemmt (nur „abgelaufen").
/// Vergleich auf Tagesebene (Uhrzeit gekappt) — kein Off-by-one am Zeitpunkt.
QualiExpiryLevel qualiExpiryLevel(
  DateTime? gueltigBis, {
  required DateTime now,
  int vorlaufTage = 30,
}) {
  if (gueltigBis == null) return QualiExpiryLevel.ok;
  final vorlauf = vorlaufTage < 0 ? 0 : vorlaufTage;
  final today = DateTime(now.year, now.month, now.day);
  final expiry = DateTime(gueltigBis.year, gueltigBis.month, gueltigBis.day);
  final days = expiry.difference(today).inDays;
  if (days < 0) return QualiExpiryLevel.abgelaufen;
  if (days <= vorlauf) return QualiExpiryLevel.laeuftAb;
  return QualiExpiryLevel.ok;
}

/// Volle Tage bis zum Ablauf (negativ = abgelaufen); `null` bei unbefristet.
int? qualiDaysUntilExpiry(DateTime? gueltigBis, {required DateTime now}) {
  if (gueltigBis == null) return null;
  final today = DateTime(now.year, now.month, now.day);
  final expiry = DateTime(gueltigBis.year, gueltigBis.month, gueltigBis.day);
  return expiry.difference(today).inDays;
}

/// **PERSONAL-7 — Warn-Engine.** Liefert je ablaufender/abgelaufener
/// Qualifikation eine [QualiExpiryWarning]. Unbefristete (`gueltigBis == null`)
/// und noch gültige (> Vorlauf) werden übersprungen. Reihenfolge: dringlichste
/// zuerst (kleinster/negativster `daysUntilExpiry`).
List<QualiExpiryWarning> computeQualiExpiryWarnings(
  List<EmployeeQualification> qualifications, {
  required DateTime now,
  int vorlaufTage = 30,
}) {
  final result = <QualiExpiryWarning>[];
  for (final q in qualifications) {
    final level =
        qualiExpiryLevel(q.gueltigBis, now: now, vorlaufTage: vorlaufTage);
    if (!level.isWarning) continue;
    result.add(QualiExpiryWarning(
      qualification: q,
      level: level,
      daysUntilExpiry: qualiDaysUntilExpiry(q.gueltigBis, now: now) ?? 0,
    ));
  }
  result.sort((a, b) => a.daysUntilExpiry.compareTo(b.daysUntilExpiry));
  return result;
}
