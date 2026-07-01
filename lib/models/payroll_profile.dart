import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;
import 'payroll_record.dart';

/// Lohn-Stammdaten eines Mitarbeiters (admin-only).
///
/// Dienen der **Vorbefüllung** der monatlichen Lohnabrechnung
/// ([PayrollRecord]), damit Steuerklasse, Beschäftigungsart, Bundesland und
/// Kirchensteuer nicht jeden Monat neu erfasst werden. Org-skopiert unter
/// `organizations/{orgId}/payrollProfiles/{userId}` mit **deterministischer
/// Doc-ID = userId** (ein Profil je Mitarbeiter, erneutes Speichern
/// überschreibt). Hält die Zwei-Serialisierungs-Regel ein.
class PayrollProfile {
  const PayrollProfile({
    this.id,
    required this.orgId,
    required this.userId,
    this.taxClass = TaxClass.i,
    this.kind = PayrollEmploymentKind.standard,
    this.churchTax = false,
    this.federalState,
    this.monthlyGrossCents,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;
  final String userId;
  final TaxClass taxClass;
  final PayrollEmploymentKind kind;
  final bool churchTax;

  /// Bundesland (für den Kirchensteuersatz 8 % BY/BW vs. 9 % sonst).
  final String? federalState;

  /// Zuletzt bekanntes Monatsbrutto (Cent) – **nur UI-Prefill-Fallback** (L3).
  /// SSoT für das Festgehalt ist `EmploymentContract.monthlyGrossCents`; dieser
  /// Wert greift nur, wenn kein aktiver Vertrag existiert. Kein zweiter
  /// Pflege-Ort.
  final int? monthlyGrossCents;

  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Deterministische Doc-ID (ein Profil je Mitarbeiter).
  String get documentId => userId;

  factory PayrollProfile.fromFirestore(String id, Map<String, dynamic> map) {
    return PayrollProfile(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      taxClass: TaxClassX.fromValue(map['taxClass']?.toString()),
      kind: PayrollEmploymentKindX.fromValue(map['kind']?.toString()),
      churchTax: parse.toBool(map['churchTax']) ?? false,
      federalState: map['federalState'] as String?,
      monthlyGrossCents: parse.toInt(map['monthlyGrossCents']),
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory PayrollProfile.fromMap(Map<String, dynamic> map) {
    return PayrollProfile(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      taxClass: TaxClassX.fromValue(map['tax_class']?.toString()),
      kind: PayrollEmploymentKindX.fromValue(map['kind']?.toString()),
      churchTax: parse.toBool(map['church_tax']) ?? false,
      federalState: map['federal_state'] as String?,
      monthlyGrossCents: parse.toInt(map['monthly_gross_cents']),
      createdByUid: map['created_by_uid'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'userId': userId,
      'taxClass': taxClass.value,
      'kind': kind.value,
      'churchTax': churchTax,
      'federalState': _trimmedOrNull(federalState),
      'monthlyGrossCents': monthlyGrossCents,
      'createdByUid': createdByUid,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'user_id': userId,
      'tax_class': taxClass.value,
      'kind': kind.value,
      'church_tax': churchTax,
      'federal_state': federalState,
      'monthly_gross_cents': monthlyGrossCents,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  PayrollProfile copyWith({
    String? id,
    String? orgId,
    String? userId,
    TaxClass? taxClass,
    PayrollEmploymentKind? kind,
    bool? churchTax,
    String? federalState,
    int? monthlyGrossCents,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearFederalState = false,
    bool clearMonthlyGross = false,
  }) {
    return PayrollProfile(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      userId: userId ?? this.userId,
      taxClass: taxClass ?? this.taxClass,
      kind: kind ?? this.kind,
      churchTax: churchTax ?? this.churchTax,
      federalState:
          clearFederalState ? null : (federalState ?? this.federalState),
      monthlyGrossCents: clearMonthlyGross
          ? null
          : (monthlyGrossCents ?? this.monthlyGrossCents),
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// True, wenn die lohnrelevanten Stammfelder identisch sind – um redundante
  /// Schreibvorgänge (Spark-Free-Tier) zu vermeiden.
  bool sameMasterData(PayrollProfile other) =>
      taxClass == other.taxClass &&
      kind == other.kind &&
      churchTax == other.churchTax &&
      federalState == other.federalState &&
      monthlyGrossCents == other.monthlyGrossCents;

  static String? _trimmedOrNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}
