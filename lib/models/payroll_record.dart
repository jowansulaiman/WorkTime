import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Steuerklasse (Lohnsteuerklasse) I–VI.
enum TaxClass { i, ii, iii, iv, v, vi }

/// Beschäftigungsart für die SV-Berechnung.
enum PayrollEmploymentKind { standard, minijob, midijob }

extension TaxClassX on TaxClass {
  String get value => switch (this) {
        TaxClass.i => '1',
        TaxClass.ii => '2',
        TaxClass.iii => '3',
        TaxClass.iv => '4',
        TaxClass.v => '5',
        TaxClass.vi => '6',
      };

  String get label => switch (this) {
        TaxClass.i => 'Steuerklasse I',
        TaxClass.ii => 'Steuerklasse II',
        TaxClass.iii => 'Steuerklasse III',
        TaxClass.iv => 'Steuerklasse IV',
        TaxClass.v => 'Steuerklasse V',
        TaxClass.vi => 'Steuerklasse VI',
      };

  /// Kurzform für kompakte Chips (z.B. „St.-Kl. III").
  String get shortLabel => switch (this) {
        TaxClass.i => 'I',
        TaxClass.ii => 'II',
        TaxClass.iii => 'III',
        TaxClass.iv => 'IV',
        TaxClass.v => 'V',
        TaxClass.vi => 'VI',
      };

  static TaxClass fromValue(String? value) => switch (value) {
        '2' => TaxClass.ii,
        '3' => TaxClass.iii,
        '4' => TaxClass.iv,
        '5' => TaxClass.v,
        '6' => TaxClass.vi,
        _ => TaxClass.i,
      };
}

extension PayrollEmploymentKindX on PayrollEmploymentKind {
  String get value => switch (this) {
        PayrollEmploymentKind.standard => 'standard',
        PayrollEmploymentKind.minijob => 'minijob',
        PayrollEmploymentKind.midijob => 'midijob',
      };

  String get label => switch (this) {
        PayrollEmploymentKind.standard => 'Sozialversicherungspflichtig',
        PayrollEmploymentKind.minijob => 'Minijob',
        PayrollEmploymentKind.midijob => 'Midijob (Übergangsbereich)',
      };

  static PayrollEmploymentKind fromValue(String? value) => switch (value) {
        'minijob' => PayrollEmploymentKind.minijob,
        'midijob' => PayrollEmploymentKind.midijob,
        _ => PayrollEmploymentKind.standard,
      };
}

/// Monatlicher Lohn-Snapshot pro Mitarbeiter (Personal-Bereich, nur Admin).
///
/// Org-skopiert unter `organizations/{orgId}/payrollRecords`. Alle Beträge sind
/// ganzzahlige Cent. Die berechneten Felder (Lohnsteuer, SV, Netto, AG-Kosten)
/// sind ein **unverbindlicher Richtwert** – siehe `PayrollCalculator`.
///
/// Doc-ID ist deterministisch (`<userId>-<jahr>-<mm>`), damit eine erneute
/// Abrechnung desselben Monats den Eintrag überschreibt statt zu duplizieren.
class PayrollRecord {
  const PayrollRecord({
    this.id,
    required this.orgId,
    required this.userId,
    required this.periodYear,
    required this.periodMonth,
    this.grossCents = 0,
    this.taxClass = TaxClass.i,
    this.churchTax = false,
    this.federalState,
    this.kind = PayrollEmploymentKind.standard,
    this.incomeTaxCents = 0,
    this.soliCents = 0,
    this.churchTaxCents = 0,
    this.healthEmployeeCents = 0,
    this.careEmployeeCents = 0,
    this.pensionEmployeeCents = 0,
    this.unemploymentEmployeeCents = 0,
    this.healthEmployerCents = 0,
    this.careEmployerCents = 0,
    this.pensionEmployerCents = 0,
    this.unemploymentEmployerCents = 0,
    this.netCents = 0,
    this.employerTotalCents = 0,
    this.note,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;
  final String userId;
  final int periodYear;
  final int periodMonth;
  final int grossCents;
  final TaxClass taxClass;
  final bool churchTax;
  final String? federalState;
  final PayrollEmploymentKind kind;

  // --- Berechnete Positionen (Richtwert) ------------------------------------
  final int incomeTaxCents;
  final int soliCents;
  final int churchTaxCents;
  final int healthEmployeeCents;
  final int careEmployeeCents;
  final int pensionEmployeeCents;
  final int unemploymentEmployeeCents;
  final int healthEmployerCents;
  final int careEmployerCents;
  final int pensionEmployerCents;
  final int unemploymentEmployerCents;
  final int netCents;
  final int employerTotalCents;

  final String? note;
  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Deterministische Dokument-ID für stabilen Upsert pro Monat.
  String get documentId =>
      '$userId-$periodYear-${periodMonth.toString().padLeft(2, '0')}';

  int get employeeSocialTotalCents =>
      healthEmployeeCents +
      careEmployeeCents +
      pensionEmployeeCents +
      unemploymentEmployeeCents;

  int get employerSocialTotalCents =>
      healthEmployerCents +
      careEmployerCents +
      pensionEmployerCents +
      unemploymentEmployerCents;

  int get totalDeductionsCents =>
      incomeTaxCents +
      soliCents +
      churchTaxCents +
      employeeSocialTotalCents;

  factory PayrollRecord.fromFirestore(String id, Map<String, dynamic> map) {
    return PayrollRecord(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      periodYear: parse.toInt(map['periodYear']) ?? 0,
      periodMonth: parse.toInt(map['periodMonth']) ?? 1,
      grossCents: parse.toInt(map['grossCents']) ?? 0,
      taxClass: TaxClassX.fromValue(map['taxClass']?.toString()),
      churchTax: parse.toBool(map['churchTax']) ?? false,
      federalState: map['federalState'] as String?,
      kind: PayrollEmploymentKindX.fromValue(map['kind']?.toString()),
      incomeTaxCents: parse.toInt(map['incomeTaxCents']) ?? 0,
      soliCents: parse.toInt(map['soliCents']) ?? 0,
      churchTaxCents: parse.toInt(map['churchTaxCents']) ?? 0,
      healthEmployeeCents: parse.toInt(map['healthEmployeeCents']) ?? 0,
      careEmployeeCents: parse.toInt(map['careEmployeeCents']) ?? 0,
      pensionEmployeeCents: parse.toInt(map['pensionEmployeeCents']) ?? 0,
      unemploymentEmployeeCents:
          parse.toInt(map['unemploymentEmployeeCents']) ?? 0,
      healthEmployerCents: parse.toInt(map['healthEmployerCents']) ?? 0,
      careEmployerCents: parse.toInt(map['careEmployerCents']) ?? 0,
      pensionEmployerCents: parse.toInt(map['pensionEmployerCents']) ?? 0,
      unemploymentEmployerCents:
          parse.toInt(map['unemploymentEmployerCents']) ?? 0,
      netCents: parse.toInt(map['netCents']) ?? 0,
      employerTotalCents: parse.toInt(map['employerTotalCents']) ?? 0,
      note: map['note'] as String?,
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory PayrollRecord.fromMap(Map<String, dynamic> map) {
    return PayrollRecord(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      periodYear: parse.toInt(map['period_year']) ?? 0,
      periodMonth: parse.toInt(map['period_month']) ?? 1,
      grossCents: parse.toInt(map['gross_cents']) ?? 0,
      taxClass: TaxClassX.fromValue(map['tax_class']?.toString()),
      churchTax: parse.toBool(map['church_tax']) ?? false,
      federalState: map['federal_state'] as String?,
      kind: PayrollEmploymentKindX.fromValue(map['kind']?.toString()),
      incomeTaxCents: parse.toInt(map['income_tax_cents']) ?? 0,
      soliCents: parse.toInt(map['soli_cents']) ?? 0,
      churchTaxCents: parse.toInt(map['church_tax_cents']) ?? 0,
      healthEmployeeCents: parse.toInt(map['health_employee_cents']) ?? 0,
      careEmployeeCents: parse.toInt(map['care_employee_cents']) ?? 0,
      pensionEmployeeCents: parse.toInt(map['pension_employee_cents']) ?? 0,
      unemploymentEmployeeCents:
          parse.toInt(map['unemployment_employee_cents']) ?? 0,
      healthEmployerCents: parse.toInt(map['health_employer_cents']) ?? 0,
      careEmployerCents: parse.toInt(map['care_employer_cents']) ?? 0,
      pensionEmployerCents: parse.toInt(map['pension_employer_cents']) ?? 0,
      unemploymentEmployerCents:
          parse.toInt(map['unemployment_employer_cents']) ?? 0,
      netCents: parse.toInt(map['net_cents']) ?? 0,
      employerTotalCents: parse.toInt(map['employer_total_cents']) ?? 0,
      note: map['note'] as String?,
      createdByUid: map['created_by_uid'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'userId': userId,
      'periodYear': periodYear,
      'periodMonth': periodMonth,
      'grossCents': grossCents,
      'taxClass': taxClass.value,
      'churchTax': churchTax,
      'federalState': federalState,
      'kind': kind.value,
      'incomeTaxCents': incomeTaxCents,
      'soliCents': soliCents,
      'churchTaxCents': churchTaxCents,
      'healthEmployeeCents': healthEmployeeCents,
      'careEmployeeCents': careEmployeeCents,
      'pensionEmployeeCents': pensionEmployeeCents,
      'unemploymentEmployeeCents': unemploymentEmployeeCents,
      'healthEmployerCents': healthEmployerCents,
      'careEmployerCents': careEmployerCents,
      'pensionEmployerCents': pensionEmployerCents,
      'unemploymentEmployerCents': unemploymentEmployerCents,
      'netCents': netCents,
      'employerTotalCents': employerTotalCents,
      'note': note,
      'createdByUid': createdByUid,
      if (id == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'user_id': userId,
      'period_year': periodYear,
      'period_month': periodMonth,
      'gross_cents': grossCents,
      'tax_class': taxClass.value,
      'church_tax': churchTax,
      'federal_state': federalState,
      'kind': kind.value,
      'income_tax_cents': incomeTaxCents,
      'soli_cents': soliCents,
      'church_tax_cents': churchTaxCents,
      'health_employee_cents': healthEmployeeCents,
      'care_employee_cents': careEmployeeCents,
      'pension_employee_cents': pensionEmployeeCents,
      'unemployment_employee_cents': unemploymentEmployeeCents,
      'health_employer_cents': healthEmployerCents,
      'care_employer_cents': careEmployerCents,
      'pension_employer_cents': pensionEmployerCents,
      'unemployment_employer_cents': unemploymentEmployerCents,
      'net_cents': netCents,
      'employer_total_cents': employerTotalCents,
      'note': note,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  PayrollRecord copyWith({
    String? id,
    String? orgId,
    String? userId,
    int? periodYear,
    int? periodMonth,
    int? grossCents,
    TaxClass? taxClass,
    bool? churchTax,
    String? federalState,
    bool clearFederalState = false,
    PayrollEmploymentKind? kind,
    int? incomeTaxCents,
    int? soliCents,
    int? churchTaxCents,
    int? healthEmployeeCents,
    int? careEmployeeCents,
    int? pensionEmployeeCents,
    int? unemploymentEmployeeCents,
    int? healthEmployerCents,
    int? careEmployerCents,
    int? pensionEmployerCents,
    int? unemploymentEmployerCents,
    int? netCents,
    int? employerTotalCents,
    String? note,
    bool clearNote = false,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PayrollRecord(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      userId: userId ?? this.userId,
      periodYear: periodYear ?? this.periodYear,
      periodMonth: periodMonth ?? this.periodMonth,
      grossCents: grossCents ?? this.grossCents,
      taxClass: taxClass ?? this.taxClass,
      churchTax: churchTax ?? this.churchTax,
      federalState:
          clearFederalState ? null : (federalState ?? this.federalState),
      kind: kind ?? this.kind,
      incomeTaxCents: incomeTaxCents ?? this.incomeTaxCents,
      soliCents: soliCents ?? this.soliCents,
      churchTaxCents: churchTaxCents ?? this.churchTaxCents,
      healthEmployeeCents: healthEmployeeCents ?? this.healthEmployeeCents,
      careEmployeeCents: careEmployeeCents ?? this.careEmployeeCents,
      pensionEmployeeCents: pensionEmployeeCents ?? this.pensionEmployeeCents,
      unemploymentEmployeeCents:
          unemploymentEmployeeCents ?? this.unemploymentEmployeeCents,
      healthEmployerCents: healthEmployerCents ?? this.healthEmployerCents,
      careEmployerCents: careEmployerCents ?? this.careEmployerCents,
      pensionEmployerCents: pensionEmployerCents ?? this.pensionEmployerCents,
      unemploymentEmployerCents:
          unemploymentEmployerCents ?? this.unemploymentEmployerCents,
      netCents: netCents ?? this.netCents,
      employerTotalCents: employerTotalCents ?? this.employerTotalCents,
      note: clearNote ? null : (note ?? this.note),
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
