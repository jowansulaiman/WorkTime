import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;
import 'payroll_settings.dart';

/// Org-/jahr-spezifische Lohn-Konfiguration (`payrollConfig/{jahr}`).
///
/// Bündelt die [PayrollSettings] (SV-/Steuer-Richtwerte **inkl.** der
/// Arbeitgeber-Umlagen U1/U2/InsO/UV) als **org-individuelle, editierbare**
/// Überschreibung. Liegt **kein** Dokument für ein Jahr vor, fällt die
/// Berechnung auf [PayrollSettings.defaults2025]/[PayrollSettings.defaults2026]
/// zurück (siehe [defaultsFor]/[defaultSettingsForYear]).
///
/// **Serialisierung:** Die eingebetteten [settings] werden als **verschachtelte
/// Map** unter dem Schlüssel `settings` geführt. [PayrollSettings] enthält keine
/// Datumsfelder, daher ist seine `toMap()`-Darstellung format-neutral und in
/// **beiden** Serialisierungen (Firestore camelCase / lokal snake_case)
/// identisch einsetzbar. Nur die Meta-Datumsfelder dieser Klasse werden je
/// Format unterschiedlich (Timestamp vs. ISO) behandelt.
///
/// **ACL:** admin-only (Vergütungs-/Beitragssätze). Collection org-skopiert.
class OrgPayrollSettings {
  const OrgPayrollSettings({
    this.id,
    required this.orgId,
    required this.jahr,
    required this.settings,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  /// Doc-ID = Bezugsjahr als String (deterministisch, ein Dokument je Jahr).
  final String? id;
  final String orgId;
  final int jahr;
  final PayrollSettings settings;

  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Deterministische Doc-ID (Bezugsjahr), damit es je Org/Jahr genau einen
  /// Datensatz gibt (Upsert).
  String get documentId => jahr.toString();

  /// Liefert die für [jahr] passenden gesetzlichen Richtwert-Defaults
  /// (≤ 2025 → 2025er-Sätze, sonst 2026er-Sätze). Das Bezugsjahr wird auf das
  /// gewünschte [jahr] gesetzt.
  static PayrollSettings defaultSettingsForYear(int jahr) {
    final base = jahr <= 2025
        ? PayrollSettings.defaults2025()
        : PayrollSettings.defaults2026();
    return base.year == jahr ? base : base.copyWith(year: jahr);
  }

  /// Fallback-Konfiguration für ein Jahr ohne hinterlegtes Dokument.
  factory OrgPayrollSettings.defaultsFor({
    required String orgId,
    required int jahr,
  }) {
    return OrgPayrollSettings(
      id: jahr.toString(),
      orgId: orgId,
      jahr: jahr,
      settings: defaultSettingsForYear(jahr),
    );
  }

  factory OrgPayrollSettings.fromFirestore(String id, Map<String, dynamic> map) {
    // jahr bevorzugt aus dem Feld, sonst aus der Doc-ID (= Jahr-String).
    final jahr = parse.toInt(map['jahr']) ?? int.tryParse(id) ?? DateTime.now().year;
    return OrgPayrollSettings(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      jahr: jahr,
      settings: _settingsFrom(map['settings'], jahr),
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory OrgPayrollSettings.fromMap(Map<String, dynamic> map) {
    final jahr = parse.toInt(map['jahr']) ??
        int.tryParse(map['id']?.toString() ?? '') ??
        DateTime.now().year;
    return OrgPayrollSettings(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      jahr: jahr,
      settings: _settingsFrom(map['settings'], jahr),
      createdByUid: map['created_by_uid'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  /// Liest die eingebettete [PayrollSettings] tolerant; fehlt sie, greifen die
  /// Jahres-Defaults (kein Crash bei Alt-/Teil-Dokumenten).
  static PayrollSettings _settingsFrom(dynamic raw, int jahr) {
    final map = parse.toMap(raw);
    if (map.isEmpty) return defaultSettingsForYear(jahr);
    return PayrollSettings.fromMap(map);
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'jahr': jahr,
      'settings': settings.toMap(),
      'createdByUid': createdByUid,
      // Doc-ID ist deterministisch (Jahr) → beim Speichern bereits gesetzt; daher
      // den Erstellungs-Zeitstempel am tatsächlich noch fehlenden createdAt
      // festmachen (nicht an id==null). Mit merge:true wird er nur beim ersten
      // Anlegen geschrieben und danach (createdAt aus fromFirestore vorhanden,
      // vom Editor durchgereicht) nicht mehr überschrieben.
      if (createdAt == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'jahr': jahr,
      'settings': settings.toMap(),
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  OrgPayrollSettings copyWith({
    String? id,
    String? orgId,
    int? jahr,
    PayrollSettings? settings,
    String? createdByUid,
    bool clearCreatedByUid = false,
    DateTime? createdAt,
    bool clearCreatedAt = false,
    DateTime? updatedAt,
    bool clearUpdatedAt = false,
  }) {
    return OrgPayrollSettings(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      jahr: jahr ?? this.jahr,
      settings: settings ?? this.settings,
      createdByUid:
          clearCreatedByUid ? null : (createdByUid ?? this.createdByUid),
      createdAt: clearCreatedAt ? null : (createdAt ?? this.createdAt),
      updatedAt: clearUpdatedAt ? null : (updatedAt ?? this.updatedAt),
    );
  }
}
