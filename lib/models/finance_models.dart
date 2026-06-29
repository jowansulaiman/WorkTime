import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Art einer Kostenart (für Auswertungen/Filter).
enum CostTypeGroup { overhead, direct, activity }

extension CostTypeGroupX on CostTypeGroup {
  String get value => switch (this) {
        CostTypeGroup.overhead => 'overhead',
        CostTypeGroup.direct => 'direct',
        CostTypeGroup.activity => 'activity',
      };

  String get label => switch (this) {
        CostTypeGroup.overhead => 'Gemeinkosten',
        CostTypeGroup.direct => 'Direktkosten',
        CostTypeGroup.activity => 'Aktivitätskosten',
      };

  /// Default-Branch wirft nie (Enum-Kopplungsregel).
  static CostTypeGroup fromValue(String? value) => switch (value) {
        'direct' => CostTypeGroup.direct,
        'activity' => CostTypeGroup.activity,
        _ => CostTypeGroup.overhead,
      };
}

String? _clean(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

/// Kostenstelle (WO fallen Kosten an, z. B. ein Laden/Standort).
///
/// Org-skopiert unter `organizations/{orgId}/costCenters` (Auto-ID), admin-only.
/// [number] ist das fachliche Kennzeichen (im DATEV-Export = KOST1).
class CostCenter {
  const CostCenter({
    this.id,
    required this.orgId,
    required this.number,
    required this.name,
    this.description,
    this.costBearerRef,
    this.siteId,
    this.annualBudgetCents = 0,
    this.isBillable = false,
    this.isActive = true,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;
  final String number;
  final String name;
  final String? description;

  /// Kostenträger-Referenz (DATEV-Export: KOST2).
  final String? costBearerRef;

  /// Optionale Zuordnung zu einem Standort (`SiteDefinition.id`). `null` =
  /// standortübergreifend / nicht zugeordnet. **Nicht-unique** und nur eine
  /// Vorbelegungshilfe für die automatische Kostenstellen-Auflösung (H-C1,
  /// Enabler für Personalkosten-/Wareneinsatz-Buchung). Kanonisch für den
  /// DATEV-Export bleibt [number] (KOST1) — `siteId` ersetzt sie nie.
  final String? siteId;

  /// Fallback-Jahresbudget, wenn kein explizites [Budget]-Dokument existiert.
  final int annualBudgetCents;
  final bool isBillable;
  final bool isActive;
  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory CostCenter.fromFirestore(String id, Map<String, dynamic> map) {
    return CostCenter(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      number: (map['number'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      description: map['description'] as String?,
      costBearerRef: map['costBearerRef'] as String?,
      siteId: map['siteId'] as String?,
      annualBudgetCents: parse.toInt(map['annualBudgetCents']) ?? 0,
      isBillable: parse.toBool(map['isBillable']) ?? false,
      isActive: parse.toBool(map['isActive']) ?? true,
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory CostCenter.fromMap(Map<String, dynamic> map) {
    return CostCenter(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      number: (map['number'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      description: map['description'] as String?,
      costBearerRef: map['cost_bearer_ref'] as String?,
      siteId: map['site_id'] as String?,
      annualBudgetCents: parse.toInt(map['annual_budget_cents']) ?? 0,
      isBillable: parse.toBool(map['is_billable']) ?? false,
      isActive: parse.toBool(map['is_active']) ?? true,
      createdByUid: map['created_by_uid'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'number': number.trim(),
      'name': name.trim(),
      'description': _clean(description),
      'costBearerRef': _clean(costBearerRef),
      'siteId': _clean(siteId),
      'annualBudgetCents': annualBudgetCents,
      'isBillable': isBillable,
      'isActive': isActive,
      'createdByUid': createdByUid,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'number': number,
      'name': name,
      'description': description,
      'cost_bearer_ref': costBearerRef,
      'site_id': siteId,
      'annual_budget_cents': annualBudgetCents,
      'is_billable': isBillable,
      'is_active': isActive,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  CostCenter copyWith({
    String? id,
    String? orgId,
    String? number,
    String? name,
    String? description,
    bool clearDescription = false,
    String? costBearerRef,
    bool clearCostBearerRef = false,
    String? siteId,
    bool clearSiteId = false,
    int? annualBudgetCents,
    bool? isBillable,
    bool? isActive,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CostCenter(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      number: number ?? this.number,
      name: name ?? this.name,
      description:
          clearDescription ? null : (description ?? this.description),
      costBearerRef:
          clearCostBearerRef ? null : (costBearerRef ?? this.costBearerRef),
      siteId: clearSiteId ? null : (siteId ?? this.siteId),
      annualBudgetCents: annualBudgetCents ?? this.annualBudgetCents,
      isBillable: isBillable ?? this.isBillable,
      isActive: isActive ?? this.isActive,
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Kostenart (WELCHE Art Kosten, z. B. Miete/Wareneinsatz).
///
/// Org-skopiert unter `organizations/{orgId}/costTypes` (Auto-ID), admin-only.
/// [number] = Sachkonto-Nr (im DATEV-Export das Konto).
class CostType {
  const CostType({
    this.id,
    required this.orgId,
    required this.number,
    required this.name,
    this.group = CostTypeGroup.overhead,
    this.isActive = true,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;
  final String number;
  final String name;
  final CostTypeGroup group;
  final bool isActive;
  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory CostType.fromFirestore(String id, Map<String, dynamic> map) {
    return CostType(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      number: (map['number'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      group: CostTypeGroupX.fromValue(map['group']?.toString()),
      isActive: parse.toBool(map['isActive']) ?? true,
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory CostType.fromMap(Map<String, dynamic> map) {
    return CostType(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      number: (map['number'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      group: CostTypeGroupX.fromValue(map['group']?.toString()),
      isActive: parse.toBool(map['is_active']) ?? true,
      createdByUid: map['created_by_uid'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'number': number.trim(),
      'name': name.trim(),
      'group': group.value,
      'isActive': isActive,
      'createdByUid': createdByUid,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'number': number,
      'name': name,
      'group': group.value,
      'is_active': isActive,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  CostType copyWith({
    String? id,
    String? orgId,
    String? number,
    String? name,
    CostTypeGroup? group,
    bool? isActive,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CostType(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      number: number ?? this.number,
      name: name ?? this.name,
      group: group ?? this.group,
      isActive: isActive ?? this.isActive,
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Buchung im Kosten-Journal (Kosten-Allokationsmodell, KEINE doppelte
/// Buchführung). Ordnet einen Betrag genau EINER Kostenstelle + Kostenart zu.
///
/// **Vorzeichen-Konvention:** [amountCents] > 0 = Kosten/Ausgabe,
/// [amountCents] < 0 = Gutschrift/Erstattung. Org-skopiert unter
/// `organizations/{orgId}/journalEntries` (Auto-ID), admin-only.
class JournalEntry {
  const JournalEntry({
    this.id,
    required this.orgId,
    required this.date,
    required this.costCenterId,
    required this.costTypeId,
    required this.description,
    this.amountCents = 0,
    this.reference,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;
  final DateTime date;
  final String costCenterId;
  final String costTypeId;
  final String description;

  /// Betrag in Cent. Positiv = Kosten, negativ = Gutschrift.
  final int amountCents;

  /// Externe Belegnummer/-referenz (optional).
  final String? reference;
  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isExpense => amountCents > 0;
  bool get isCredit => amountCents < 0;

  factory JournalEntry.fromFirestore(String id, Map<String, dynamic> map) {
    return JournalEntry(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      date: FirestoreDateParser.readDate(map['date']) ?? DateTime(1970),
      costCenterId: (map['costCenterId'] ?? '').toString(),
      costTypeId: (map['costTypeId'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      amountCents: parse.toInt(map['amountCents']) ?? 0,
      reference: map['reference'] as String?,
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory JournalEntry.fromMap(Map<String, dynamic> map) {
    return JournalEntry(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      date: FirestoreDateParser.readLocalDate(map['date']) ?? DateTime(1970),
      costCenterId: (map['cost_center_id'] ?? '').toString(),
      costTypeId: (map['cost_type_id'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      amountCents: parse.toInt(map['amount_cents']) ?? 0,
      reference: map['reference'] as String?,
      createdByUid: map['created_by_uid'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day, 12)),
      'costCenterId': costCenterId,
      'costTypeId': costTypeId,
      'description': description.trim(),
      'amountCents': amountCents,
      'reference': _clean(reference),
      'createdByUid': createdByUid,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'date': date.toIso8601String(),
      'cost_center_id': costCenterId,
      'cost_type_id': costTypeId,
      'description': description,
      'amount_cents': amountCents,
      'reference': reference,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  JournalEntry copyWith({
    String? id,
    String? orgId,
    DateTime? date,
    String? costCenterId,
    String? costTypeId,
    String? description,
    int? amountCents,
    String? reference,
    bool clearReference = false,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return JournalEntry(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      date: date ?? this.date,
      costCenterId: costCenterId ?? this.costCenterId,
      costTypeId: costTypeId ?? this.costTypeId,
      description: description ?? this.description,
      amountCents: amountCents ?? this.amountCents,
      reference: clearReference ? null : (reference ?? this.reference),
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Plan-Budget pro (Kostenstelle [+ optional Kostenart] + Jahr). Das Ist wird
/// NICHT gespeichert, sondern im Provider aus den Buchungen abgeleitet.
///
/// Org-skopiert unter `organizations/{orgId}/budgets` mit **deterministischer
/// Doc-ID** (`<costCenterId>-<costTypeId|all>-<year>`), admin-only.
class Budget {
  const Budget({
    this.id,
    required this.orgId,
    required this.costCenterId,
    this.costTypeId,
    required this.year,
    this.plannedAmountCents = 0,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;
  final String costCenterId;

  /// Optional: Kostenart. null = Gesamtbudget der Kostenstelle.
  final String? costTypeId;
  final int year;
  final int plannedAmountCents;
  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Deterministische Doc-ID (ein Budget je Kostenstelle+Kostenart+Jahr).
  String get documentId => '$costCenterId-${costTypeId ?? 'all'}-$year';

  /// Gesamtbudget der Kostenstelle (keine Kostenart-Bindung)?
  bool get isTotalBudget => costTypeId == null;

  factory Budget.fromFirestore(String id, Map<String, dynamic> map) {
    return Budget(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      costCenterId: (map['costCenterId'] ?? '').toString(),
      costTypeId: map['costTypeId'] as String?,
      year: parse.toInt(map['year']) ?? 0,
      plannedAmountCents: parse.toInt(map['plannedAmountCents']) ?? 0,
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory Budget.fromMap(Map<String, dynamic> map) {
    return Budget(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      costCenterId: (map['cost_center_id'] ?? '').toString(),
      costTypeId: map['cost_type_id'] as String?,
      year: parse.toInt(map['year']) ?? 0,
      plannedAmountCents: parse.toInt(map['planned_amount_cents']) ?? 0,
      createdByUid: map['created_by_uid'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'costCenterId': costCenterId,
      'costTypeId': costTypeId,
      'year': year,
      'plannedAmountCents': plannedAmountCents,
      'createdByUid': createdByUid,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'cost_center_id': costCenterId,
      'cost_type_id': costTypeId,
      'year': year,
      'planned_amount_cents': plannedAmountCents,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  Budget copyWith({
    String? id,
    String? orgId,
    String? costCenterId,
    String? costTypeId,
    bool clearCostTypeId = false,
    int? year,
    int? plannedAmountCents,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Budget(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      costCenterId: costCenterId ?? this.costCenterId,
      costTypeId: clearCostTypeId ? null : (costTypeId ?? this.costTypeId),
      year: year ?? this.year,
      plannedAmountCents: plannedAmountCents ?? this.plannedAmountCents,
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
