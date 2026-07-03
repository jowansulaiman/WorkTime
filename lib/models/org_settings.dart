import '../core/firestore_num_parser.dart' as parse;

/// Org-weite operative Einstellungen — liegt unter dem **deterministischen**
/// Dokument `organizations/{orgId}/config/orgSettings` (analog `appFlags`,
/// admin-write/sameOrg-read über den generischen `config/{configId}`-Rules-Block).
///
/// Steuert die automatische Schichtverteilung (Generator-Defaults +
/// Cap-Härte). Zwei-Serialisierung wie üblich: [toFirestoreMap]/[fromFirestore]
/// camelCase (Firestore), [toMap]/[fromMap] snake_case (lokal/Payload).
class OrgSettings {
  const OrgSettings({
    this.id,
    required this.orgId,
    this.enforceHourCapHard = true,
    this.defaultShiftMinutes = 480,
    this.defaultBreakMinutes = 30,
    this.defaultRequiredCount = 1,
    this.purchasePricesIncludeVat = false,
  });

  /// Feste, deterministische Doc-ID (genau ein Dokument je Org).
  static const String documentId = 'orgSettings';

  final String? id;
  final String orgId;

  /// `true` (Default) = Stundengrenzen (Woche/Monat) werden im Verteiler **hart**
  /// durchgesetzt: Rest-Slots bleiben offen statt überschritten. `false` =
  /// weich: Überschreitung erlaubt, Vorschau warnt + Score-Penalty.
  final bool enforceHourCapHard;

  /// Ziel-Brutto-Schichtlänge (inkl. Pause) in Minuten, mit der der Generator
  /// lange Öffnungsfenster zerlegt. Default 480 (8 h).
  final int defaultShiftMinutes;

  /// Mindest-Pause in Minuten je generierter Schicht. Default 30.
  final int defaultBreakMinutes;

  /// Fallback-Personalbedarf, wenn ein Standort Öffnungszeiten, aber keine
  /// `staffingDemands` hinterlegt hat. Default 1.
  final int defaultRequiredCount;

  /// **Kassen-Modul E1/§3.4:** `true` = die gepflegten Einkaufspreise
  /// (`Product.purchasePriceCents`) enthalten MwSt (brutto) und werden für
  /// Rohertrag/Wareneinsatz über `Product.taxRatePercent` auf netto
  /// normalisiert (Artikel ohne Steuersatz gelten dann als unbewertet).
  /// Default `false` = EK-Preise sind netto (B2B-üblich). Gilt org-weit.
  final bool purchasePricesIncludeVat;

  /// Org-Standardwerte (ohne hinterlegtes Remote-/Local-Dokument).
  factory OrgSettings.defaults(String orgId) => OrgSettings(orgId: orgId);

  factory OrgSettings.fromFirestore(String id, Map<String, dynamic> map) {
    return OrgSettings(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      enforceHourCapHard: parse.toBool(map['enforceHourCapHard']) ?? true,
      defaultShiftMinutes: parse.toInt(map['defaultShiftMinutes']) ?? 480,
      defaultBreakMinutes: parse.toInt(map['defaultBreakMinutes']) ?? 30,
      defaultRequiredCount: parse.toInt(map['defaultRequiredCount']) ?? 1,
      purchasePricesIncludeVat:
          parse.toBool(map['purchasePricesIncludeVat']) ?? false,
    );
  }

  factory OrgSettings.fromMap(Map<String, dynamic> map) {
    return OrgSettings(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      enforceHourCapHard: parse.toBool(map['enforce_hour_cap_hard']) ?? true,
      defaultShiftMinutes: parse.toInt(map['default_shift_minutes']) ?? 480,
      defaultBreakMinutes: parse.toInt(map['default_break_minutes']) ?? 30,
      defaultRequiredCount: parse.toInt(map['default_required_count']) ?? 1,
      purchasePricesIncludeVat:
          parse.toBool(map['purchase_prices_include_vat']) ?? false,
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'enforceHourCapHard': enforceHourCapHard,
      'defaultShiftMinutes': defaultShiftMinutes,
      'defaultBreakMinutes': defaultBreakMinutes,
      'defaultRequiredCount': defaultRequiredCount,
      'purchasePricesIncludeVat': purchasePricesIncludeVat,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'enforce_hour_cap_hard': enforceHourCapHard,
      'default_shift_minutes': defaultShiftMinutes,
      'default_break_minutes': defaultBreakMinutes,
      'default_required_count': defaultRequiredCount,
      'purchase_prices_include_vat': purchasePricesIncludeVat,
    };
  }

  OrgSettings copyWith({
    String? id,
    String? orgId,
    bool? enforceHourCapHard,
    int? defaultShiftMinutes,
    int? defaultBreakMinutes,
    int? defaultRequiredCount,
    bool? purchasePricesIncludeVat,
  }) {
    return OrgSettings(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      enforceHourCapHard: enforceHourCapHard ?? this.enforceHourCapHard,
      defaultShiftMinutes: defaultShiftMinutes ?? this.defaultShiftMinutes,
      defaultBreakMinutes: defaultBreakMinutes ?? this.defaultBreakMinutes,
      defaultRequiredCount: defaultRequiredCount ?? this.defaultRequiredCount,
      purchasePricesIncludeVat:
          purchasePricesIncludeVat ?? this.purchasePricesIncludeVat,
    );
  }
}
