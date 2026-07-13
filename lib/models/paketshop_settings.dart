import '../core/firestore_num_parser.dart' as parse;

/// Operative Einstellungen des Hermes-Paketshops (Config-Singleton
/// `config/paketshopSettings`, ein Datensatz je Org). Enthält die
/// konfigurierbaren Schwellen und den aktiven Hermes-Standort.
///
/// Kein `id`/`orgId` (über den Doc-Pfad identifiziert). Konservative Defaults,
/// wenn das Doc/Feld fehlt (Plan §6.6). Die Auto-Anonymisierung ist in v1
/// **ausgeschaltet** (`anonymisierungAktiv == false`, Betreiber-Entscheidung §0).
class PaketshopSettings {
  const PaketshopSettings({
    this.overdueFristTage = 6,
    this.anonymisierungAktiv = false,
    this.anonymisierungFristTage = 14,
    this.hermesSiteId,
  });

  /// Kalendertage im Fach, ab denen ein offenes Paket intern als überfällig
  /// gilt (rein beratend). Default 6 (Betreiber-Entscheidung §0).
  final int overdueFristTage;

  /// Optionaler Schalter für die (in v1 ausgeschaltete) Auto-Anonymisierung.
  final bool anonymisierungAktiv;

  /// Frist der Vorgangs-Anonymisierung, nur wirksam wenn [anonymisierungAktiv].
  final int anonymisierungFristTage;

  /// Aktiver Hermes-Standort (Tabak Börse) → siteId-Auflösung (P-3).
  final String? hermesSiteId;

  factory PaketshopSettings.defaults() => const PaketshopSettings();

  factory PaketshopSettings.fromFirestore(Map<String, dynamic> map) {
    return PaketshopSettings(
      overdueFristTage: parse.toInt(map['overdueFristTage']) ?? 6,
      anonymisierungAktiv: parse.toBool(map['anonymisierungAktiv']) ?? false,
      anonymisierungFristTage:
          parse.toInt(map['anonymisierungFristTage']) ?? 14,
      hermesSiteId: map['hermesSiteId'] as String?,
    );
  }

  factory PaketshopSettings.fromMap(Map<String, dynamic> map) {
    return PaketshopSettings(
      overdueFristTage: parse.toInt(map['overdue_frist_tage']) ?? 6,
      anonymisierungAktiv: parse.toBool(map['anonymisierung_aktiv']) ?? false,
      anonymisierungFristTage:
          parse.toInt(map['anonymisierung_frist_tage']) ?? 14,
      hermesSiteId: map['hermes_site_id'] as String?,
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'overdueFristTage': overdueFristTage,
      'anonymisierungAktiv': anonymisierungAktiv,
      'anonymisierungFristTage': anonymisierungFristTage,
      'hermesSiteId': hermesSiteId,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'overdue_frist_tage': overdueFristTage,
      'anonymisierung_aktiv': anonymisierungAktiv,
      'anonymisierung_frist_tage': anonymisierungFristTage,
      'hermes_site_id': hermesSiteId,
    };
  }

  PaketshopSettings copyWith({
    int? overdueFristTage,
    bool? anonymisierungAktiv,
    int? anonymisierungFristTage,
    String? hermesSiteId,
    bool clearHermesSiteId = false,
  }) {
    return PaketshopSettings(
      overdueFristTage: overdueFristTage ?? this.overdueFristTage,
      anonymisierungAktiv: anonymisierungAktiv ?? this.anonymisierungAktiv,
      anonymisierungFristTage:
          anonymisierungFristTage ?? this.anonymisierungFristTage,
      hermesSiteId: clearHermesSiteId ? null : (hermesSiteId ?? this.hermesSiteId),
    );
  }
}
