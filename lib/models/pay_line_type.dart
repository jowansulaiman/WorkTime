import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Art einer Lohnart/-zeile (Plan §5.7/§5.8, Meilenstein M-L). Bestimmt das
/// Vorzeichen (Bezug vs. Abzug) und die steuerliche Behandlung.
enum PayLineKind {
  /// Laufender Grundlohn (aus der Brutto-Herleitung, M-B0).
  grundlohn,

  /// Zusätzlicher Bezug (z. B. Leistungszulage).
  zulage,

  /// Abzug (negativer Betrag).
  abzug,

  /// Festes Monatsfixum.
  fixum,

  /// Vermögenswirksame Leistungen (AG-Zuschuss + AN-Eigenanteil, §5.7).
  vwl,

  /// Steuerfreier §3b-Zuschlag (Nacht/Sonn/Feiertag) — trägt eine partielle
  /// steuerfrei/SV-frei-Aufteilung (siehe `Sfn3bAnteil`/`PayrollLine`).
  zuschlag3b,

  /// Einmalzahlung / sonstiger Bezug (§39b Abs. 3, z. B. Urlaubs-/Weihnachtsgeld).
  einmalzahlung,
}

extension PayLineKindX on PayLineKind {
  String get value => switch (this) {
        PayLineKind.grundlohn => 'grundlohn',
        PayLineKind.zulage => 'zulage',
        PayLineKind.abzug => 'abzug',
        PayLineKind.fixum => 'fixum',
        PayLineKind.vwl => 'vwl',
        PayLineKind.zuschlag3b => 'zuschlag3b',
        PayLineKind.einmalzahlung => 'einmalzahlung',
      };

  String get label => switch (this) {
        PayLineKind.grundlohn => 'Grundlohn',
        PayLineKind.zulage => 'Zulage',
        PayLineKind.abzug => 'Abzug',
        PayLineKind.fixum => 'Fixum',
        PayLineKind.vwl => 'VwL',
        PayLineKind.zuschlag3b => '§3b-Zuschlag',
        PayLineKind.einmalzahlung => 'Einmalzahlung',
      };

  /// Ob diese Art üblicherweise einen Abzug (negativen Betrag) darstellt.
  bool get isAbzug => this == PayLineKind.abzug;

  static PayLineKind fromValue(String? value) => switch (value) {
        'grundlohn' => PayLineKind.grundlohn,
        'abzug' => PayLineKind.abzug,
        'fixum' => PayLineKind.fixum,
        'vwl' => PayLineKind.vwl,
        'zuschlag3b' => PayLineKind.zuschlag3b,
        'einmalzahlung' => PayLineKind.einmalzahlung,
        _ => PayLineKind.zulage,
      };
}

/// Werttyp einer Lohnart: fester €-Betrag oder prozentual (Plan §5.7 `WertTyp`).
enum PayWertTyp { nominal, prozent }

extension PayWertTypX on PayWertTyp {
  String get value => switch (this) {
        PayWertTyp.nominal => 'nominal',
        PayWertTyp.prozent => 'prozent',
      };

  String get label => switch (this) {
        PayWertTyp.nominal => 'Festbetrag (€)',
        PayWertTyp.prozent => 'Prozentual (%)',
      };

  static PayWertTyp fromValue(String? value) =>
      value == 'prozent' ? PayWertTyp.prozent : PayWertTyp.nominal;
}

/// Abrechnungsintervall einer Lohnart (Plan §5.7 `PayInterval`).
enum PayInterval { einmalig, monatlich, quartal, jaehrlich }

extension PayIntervalX on PayInterval {
  String get value => switch (this) {
        PayInterval.einmalig => 'einmalig',
        PayInterval.monatlich => 'monatlich',
        PayInterval.quartal => 'quartal',
        PayInterval.jaehrlich => 'jaehrlich',
      };

  String get label => switch (this) {
        PayInterval.einmalig => 'Einmalig',
        PayInterval.monatlich => 'Monatlich',
        PayInterval.quartal => 'Quartalsweise',
        PayInterval.jaehrlich => 'Jährlich',
      };

  static PayInterval fromValue(String? value) => switch (value) {
        'einmalig' => PayInterval.einmalig,
        'quartal' => PayInterval.quartal,
        'jaehrlich' => PayInterval.jaehrlich,
        _ => PayInterval.monatlich,
      };
}

/// Org-weiter Lohnart-Katalog (Plan §5.7, Meilenstein M-L). Eine Vorlage, aus
/// der beim Lohnlauf konkrete [PayrollLine]s instanziiert werden.
///
/// Org-skopiert unter `organizations/{orgId}/payLineTypes`, admin-only. Dual
/// serialisiert (camelCase/Firestore · snake_case/lokal), wie alle Modelle.
class PayLineType {
  const PayLineType({
    this.id,
    required this.orgId,
    required this.name,
    this.datevLohnartNr,
    this.kind = PayLineKind.zulage,
    this.wertTyp = PayWertTyp.nominal,
    this.intervall = PayInterval.monatlich,
    this.steuerfrei = false,
    this.svFrei = false,
    this.deaktiviert = false,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;
  final String name;

  /// DATEV-Lohnartnummer (frei, mandanten-/LuG-vs-LODAS-spezifisch). **Weiche**
  /// Validierung über [isValidDatevLohnartNr] — kein fester Nummernbereich.
  final String? datevLohnartNr;

  final PayLineKind kind;
  final PayWertTyp wertTyp;
  final PayInterval intervall;

  /// §3b-/VwL-Steuer-Handling: ist der Bezug steuerfrei?
  final bool steuerfrei;
  final bool svFrei;

  /// Deaktivierte Lohnarten bleiben für Alt-Abrechnungen lesbar, sind aber für
  /// neue Zeilen nicht mehr wählbar.
  final bool deaktiviert;

  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Weiche Validierung der DATEV-Lohnartnummer: leer/null ist erlaubt, sonst
  /// **max. 4-stellig numerisch** — bewusst KEIN fester Bereich (1–5999/8000–9999
  /// wäre LODAS-/LuG-/mandantenspezifisch und würde gültige Nummern ablehnen).
  static bool isValidDatevLohnartNr(String? value) {
    final v = value?.trim();
    if (v == null || v.isEmpty) {
      return true;
    }
    return RegExp(r'^\d{1,4}$').hasMatch(v);
  }

  factory PayLineType.fromFirestore(String id, Map<String, dynamic> map) {
    return PayLineType(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      datevLohnartNr: map['datevLohnartNr'] as String?,
      kind: PayLineKindX.fromValue(map['kind']?.toString()),
      wertTyp: PayWertTypX.fromValue(map['wertTyp']?.toString()),
      intervall: PayIntervalX.fromValue(map['intervall']?.toString()),
      steuerfrei: parse.toBool(map['steuerfrei']) ?? false,
      svFrei: parse.toBool(map['svFrei']) ?? false,
      deaktiviert: parse.toBool(map['deaktiviert']) ?? false,
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory PayLineType.fromMap(Map<String, dynamic> map) {
    return PayLineType(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      datevLohnartNr: map['datev_lohnart_nr'] as String?,
      kind: PayLineKindX.fromValue(map['kind']?.toString()),
      wertTyp: PayWertTypX.fromValue(map['wert_typ']?.toString()),
      intervall: PayIntervalX.fromValue(map['intervall']?.toString()),
      steuerfrei: parse.toBool(map['steuerfrei']) ?? false,
      svFrei: parse.toBool(map['sv_frei']) ?? false,
      deaktiviert: parse.toBool(map['deaktiviert']) ?? false,
      createdByUid: map['created_by_uid'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'name': name.trim(),
      'datevLohnartNr': _trimmedOrNull(datevLohnartNr),
      'kind': kind.value,
      'wertTyp': wertTyp.value,
      'intervall': intervall.value,
      'steuerfrei': steuerfrei,
      'svFrei': svFrei,
      'deaktiviert': deaktiviert,
      'createdByUid': createdByUid,
      if (id == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'name': name,
      'datev_lohnart_nr': datevLohnartNr,
      'kind': kind.value,
      'wert_typ': wertTyp.value,
      'intervall': intervall.value,
      'steuerfrei': steuerfrei,
      'sv_frei': svFrei,
      'deaktiviert': deaktiviert,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  PayLineType copyWith({
    String? id,
    String? orgId,
    String? name,
    String? datevLohnartNr,
    bool clearDatevLohnartNr = false,
    PayLineKind? kind,
    PayWertTyp? wertTyp,
    PayInterval? intervall,
    bool? steuerfrei,
    bool? svFrei,
    bool? deaktiviert,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PayLineType(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      name: name ?? this.name,
      datevLohnartNr: clearDatevLohnartNr
          ? null
          : (datevLohnartNr ?? this.datevLohnartNr),
      kind: kind ?? this.kind,
      wertTyp: wertTyp ?? this.wertTyp,
      intervall: intervall ?? this.intervall,
      steuerfrei: steuerfrei ?? this.steuerfrei,
      svFrei: svFrei ?? this.svFrei,
      deaktiviert: deaktiviert ?? this.deaktiviert,
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static String? _trimmedOrNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
