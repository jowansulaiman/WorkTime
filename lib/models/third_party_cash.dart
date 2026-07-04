import '../core/firestore_num_parser.dart' as parse;

/// **Dritte-Hand-/Fremdgeld-Modul §8.5 — Kategorie-Definition.**
/// Eine pro Filiale angebotene Fremdgeld-Art (Lotto, Deutsche Post, KVG …).
/// Reines Wert-Objekt, kein eigenes Doc — lebt genestet in
/// `SiteDefinition.thirdPartyCashTypes` (v1 Minimal-Variante: Katalog UND
/// Filial-Aktivierung zusammen an der Filiale). Dual-serialisiert, weil
/// `SiteDefinition` beide Formate hat.
///
/// **Freitext mit stabiler [id] (kein Dart-Enum):** der Admin pflegt Arten zur
/// Laufzeit; [id] ist der revisionsfeste Verknüpfungsschlüssel ([name] darf
/// sich ändern, [id] nie). Erfasste Beträge referenzieren [id] als `typeId`.
class ThirdPartyCashType {
  const ThirdPartyCashType({
    required this.id,
    required this.name,
    this.enabled = true,
    this.required = false,
    this.hint,
    this.sortOrder = 0,
  });

  /// Stabile ID (slug/uuid) — NIE ändern (verwaist sonst erfasste Beträge).
  final String id;

  /// Anzeigename, z. B. `Lotto`, `Deutsche Post`, `KVG-Tickets`.
  final String name;

  /// Ob die Art an dieser Filiale aktiv angeboten wird.
  final bool enabled;

  /// Pflicht-Betrag (0 zulässig, aber die Eingabe/Quittierung wird erzwungen).
  final bool required;

  /// Optionaler Hinweis im Zähl-Sheet, z. B. „Lottokasse separat zählen".
  final String? hint;

  /// Anzeigereihenfolge.
  final int sortOrder;

  factory ThirdPartyCashType.fromFirestore(Map<String, dynamic> map) {
    return ThirdPartyCashType(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      enabled: parse.toBool(map['enabled']) ?? true,
      required: parse.toBool(map['required']) ?? false,
      hint: map['hint']?.toString(),
      sortOrder: parse.toInt(map['sortOrder']) ?? 0,
    );
  }

  factory ThirdPartyCashType.fromMap(Map<String, dynamic> map) {
    return ThirdPartyCashType(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      enabled: parse.toBool(map['enabled']) ?? true,
      required: parse.toBool(map['required']) ?? false,
      hint: map['hint']?.toString(),
      sortOrder: parse.toInt(map['sort_order']) ?? 0,
    );
  }

  Map<String, dynamic> toFirestoreMap() => {
        'id': id,
        'name': name,
        'enabled': enabled,
        'required': required,
        'hint': hint,
        'sortOrder': sortOrder,
      };

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'enabled': enabled,
        'required': required,
        'hint': hint,
        'sort_order': sortOrder,
      };

  ThirdPartyCashType copyWith({
    String? id,
    String? name,
    bool? enabled,
    bool? required,
    String? hint,
    int? sortOrder,
    bool clearHint = false,
  }) {
    return ThirdPartyCashType(
      id: id ?? this.id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      required: required ?? this.required,
      hint: clearHint ? null : (hint ?? this.hint),
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

/// **Dritte-Hand-/Fremdgeld-Modul §8.6 — erfasster Einzelbetrag.**
/// Ein beim Kassenzählen erfasster Fremdgeld-Betrag je Art. Lebt als Sub-Liste
/// (`thirdParty`) an `CashCount` (Erfassung) und `CashClosing` (Snapshot).
///
/// **Getrennt von der eigenen Kasse:** fließt NIE in `countedCents`/
/// `cashExpectedCents`/`cashDifferenceCents`/`revenueGrossCents`.
class ThirdPartyAmount {
  const ThirdPartyAmount({
    required this.typeId,
    required this.typeName,
    this.amountCents = 0,
    this.expectedCents,
    this.note,
  });

  /// FK auf [ThirdPartyCashType.id] (revisionsfest).
  final String typeId;

  /// Snapshot des Namens zum Erfassungszeitpunkt (überlebt Umbenennung/
  /// Löschung der Kategorie — wie `ReceiptTax`/`siteName`-Snapshots).
  final String typeName;

  /// Erfasster Ist-Betrag in Cent (>= 0).
  final int amountCents;

  /// Optionales Fremdgeld-Soll (nur Tagesabschluss); `null` = reine
  /// Ist-Erfassung (Standard, u. a. am Kiosk blind erzwungen).
  final int? expectedCents;

  final String? note;

  factory ThirdPartyAmount.fromFirestore(Map<String, dynamic> map) {
    return ThirdPartyAmount(
      typeId: (map['typeId'] ?? '').toString(),
      typeName: (map['typeName'] ?? '').toString(),
      amountCents: parse.toInt(map['amountCents']) ?? 0,
      expectedCents: parse.toInt(map['expectedCents']),
      note: map['note']?.toString(),
    );
  }

  factory ThirdPartyAmount.fromMap(Map<String, dynamic> map) {
    return ThirdPartyAmount(
      typeId: (map['type_id'] ?? '').toString(),
      typeName: (map['type_name'] ?? '').toString(),
      amountCents: parse.toInt(map['amount_cents']) ?? 0,
      expectedCents: parse.toInt(map['expected_cents']),
      note: map['note']?.toString(),
    );
  }

  Map<String, dynamic> toFirestoreMap() => {
        'typeId': typeId,
        'typeName': typeName,
        'amountCents': amountCents,
        'expectedCents': expectedCents,
        'note': note,
      };

  Map<String, dynamic> toMap() => {
        'type_id': typeId,
        'type_name': typeName,
        'amount_cents': amountCents,
        'expected_cents': expectedCents,
        'note': note,
      };

  ThirdPartyAmount copyWith({
    String? typeId,
    String? typeName,
    int? amountCents,
    int? expectedCents,
    String? note,
    bool clearExpectedCents = false,
    bool clearNote = false,
  }) {
    return ThirdPartyAmount(
      typeId: typeId ?? this.typeId,
      typeName: typeName ?? this.typeName,
      amountCents: amountCents ?? this.amountCents,
      expectedCents:
          clearExpectedCents ? null : (expectedCents ?? this.expectedCents),
      note: clearNote ? null : (note ?? this.note),
    );
  }
}
