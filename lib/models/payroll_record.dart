import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;
import '../core/sfn_zuschlag.dart';
import 'pay_line_type.dart';

/// Eine konkrete Lohnzeile einer Abrechnung (Plan §5.7/§5.8, M-L). Eingebettet
/// in [PayrollRecord.lines] — zusätzliche Bezüge/Abzüge **neben** den
/// bestehenden Einzelfeldern (Grundlohn, Zulagen, §3b-Zuschläge, VwL,
/// Einmalzahlungen). [amountCents] ist signiert (Abzüge negativ).
///
/// Steuer-/SV-Behandlung: für die meisten Arten genügen die Flags
/// [steuerfrei]/[svFrei] (Zeile ganz frei oder ganz pflichtig). Für
/// [PayLineKind.zuschlag3b] ist die Aufteilung **partiell** (über/unter der
/// 50 €/25 €-Grundlohngrenze) → dann tragen [steuerfreiAnteilCents]/
/// [svFreiAnteilCents] die exakten Beträge und haben Vorrang vor den Flags
/// (siehe [effektivSteuerfreiCents]/[effektivSvFreiCents]).
class PayrollLine {
  const PayrollLine({
    this.lineTypeId,
    required this.name,
    this.datevLohnartNr,
    this.amountCents = 0,
    this.kind = PayLineKind.zulage,
    this.steuerfrei = false,
    this.svFrei = false,
    this.steuerfreiAnteilCents,
    this.svFreiAnteilCents,
    this.note,
  });

  /// Verweis auf die [PayLineType]-Vorlage (`null` = freie Ad-hoc-Zeile).
  final String? lineTypeId;
  final String name;
  final String? datevLohnartNr;

  /// Signierter Betrag in Cent (Bezug positiv, Abzug negativ).
  final int amountCents;
  final PayLineKind kind;

  /// Ganz-steuerfrei-Flag (Fallback, wenn [steuerfreiAnteilCents] null ist).
  final bool steuerfrei;

  /// Ganz-SV-frei-Flag (Fallback, wenn [svFreiAnteilCents] null ist).
  final bool svFrei;

  /// Partieller steuerfreier Betrag (z. B. §3b über 50 € Grundlohn). `null` ⇒
  /// das [steuerfrei]-Flag entscheidet.
  final int? steuerfreiAnteilCents;

  /// Partieller SV-freier Betrag (z. B. §3b über 25 € Grundlohn). `null` ⇒ das
  /// [svFrei]-Flag entscheidet.
  final int? svFreiAnteilCents;

  final String? note;

  /// Erzeugt eine §3b-Zuschlagszeile aus der reinen Aufteilung [Sfn3bAnteil]
  /// (siehe `lib/core/sfn_zuschlag.dart`). Bindet den §3b-Rechenkern an die
  /// Lohnzeile, ohne dass dieser den Lohnart-/Persistenz-Layer kennt.
  factory PayrollLine.zuschlag3b({
    required Sfn3bAnteil anteil,
    required String name,
    String? lineTypeId,
    String? datevLohnartNr,
    String? note,
  }) {
    return PayrollLine(
      lineTypeId: lineTypeId,
      name: name,
      datevLohnartNr: datevLohnartNr,
      amountCents: anteil.gesamtCents,
      kind: PayLineKind.zuschlag3b,
      steuerfrei: anteil.steuerpflichtigCents == 0,
      svFrei: anteil.svPflichtigCents == 0,
      steuerfreiAnteilCents: anteil.steuerfreiCents,
      svFreiAnteilCents: anteil.svFreiCents,
      note: note,
    );
  }

  // Hinweis: Diese Getter geben den partiellen Anteil unverändert zurück (kein
  // Clamp gegen [amountCents]). Heute unkritisch, da der einzige Produzent die
  // [PayrollLine.zuschlag3b]-Factory ist, die die `Sfn3bAnteil`-Invariante
  // (0 ≤ svFrei ≤ steuerfrei ≤ gesamt) garantiert. Sobald ein Lohnart-Editor
  // (M-L-b) frei Anteile setzt, gehört eine Grenzwert-Validierung an dessen
  // Eingabe-Boundary (sonst könnte `steuerpflichtigCents` negativ werden).
  /// Effektiv steuerfreier Betrag: partieller Anteil falls gesetzt, sonst das
  /// Flag (ganze Zeile frei oder nichts).
  int get effektivSteuerfreiCents =>
      steuerfreiAnteilCents ?? (steuerfrei ? amountCents : 0);

  /// Effektiv SV-freier Betrag (analog).
  int get effektivSvFreiCents =>
      svFreiAnteilCents ?? (svFrei ? amountCents : 0);

  /// Steuerpflichtiger Rest der Zeile.
  int get steuerpflichtigCents => amountCents - effektivSteuerfreiCents;

  /// SV-pflichtiger Rest der Zeile.
  int get svPflichtigCents => amountCents - effektivSvFreiCents;

  factory PayrollLine.fromFirestore(Map<String, dynamic> map) {
    return PayrollLine(
      lineTypeId: map['lineTypeId'] as String?,
      name: (map['name'] ?? '').toString(),
      datevLohnartNr: map['datevLohnartNr'] as String?,
      amountCents: parse.toInt(map['amountCents']) ?? 0,
      kind: PayLineKindX.fromValue(map['kind']?.toString()),
      steuerfrei: parse.toBool(map['steuerfrei']) ?? false,
      svFrei: parse.toBool(map['svFrei']) ?? false,
      steuerfreiAnteilCents: parse.toInt(map['steuerfreiAnteilCents']),
      svFreiAnteilCents: parse.toInt(map['svFreiAnteilCents']),
      note: map['note'] as String?,
    );
  }

  factory PayrollLine.fromMap(Map<String, dynamic> map) {
    return PayrollLine(
      lineTypeId: map['line_type_id'] as String?,
      name: (map['name'] ?? '').toString(),
      datevLohnartNr: map['datev_lohnart_nr'] as String?,
      amountCents: parse.toInt(map['amount_cents']) ?? 0,
      kind: PayLineKindX.fromValue(map['kind']?.toString()),
      steuerfrei: parse.toBool(map['steuerfrei']) ?? false,
      svFrei: parse.toBool(map['sv_frei']) ?? false,
      steuerfreiAnteilCents: parse.toInt(map['steuerfrei_anteil_cents']),
      svFreiAnteilCents: parse.toInt(map['sv_frei_anteil_cents']),
      note: map['note'] as String?,
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'lineTypeId': lineTypeId,
      'name': name.trim(),
      'datevLohnartNr': datevLohnartNr,
      'amountCents': amountCents,
      'kind': kind.value,
      'steuerfrei': steuerfrei,
      'svFrei': svFrei,
      'steuerfreiAnteilCents': steuerfreiAnteilCents,
      'svFreiAnteilCents': svFreiAnteilCents,
      'note': note,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'line_type_id': lineTypeId,
      'name': name,
      'datev_lohnart_nr': datevLohnartNr,
      'amount_cents': amountCents,
      'kind': kind.value,
      'steuerfrei': steuerfrei,
      'sv_frei': svFrei,
      'steuerfrei_anteil_cents': steuerfreiAnteilCents,
      'sv_frei_anteil_cents': svFreiAnteilCents,
      'note': note,
    };
  }

  PayrollLine copyWith({
    String? lineTypeId,
    bool clearLineTypeId = false,
    String? name,
    String? datevLohnartNr,
    bool clearDatevLohnartNr = false,
    int? amountCents,
    PayLineKind? kind,
    bool? steuerfrei,
    bool? svFrei,
    int? steuerfreiAnteilCents,
    bool clearSteuerfreiAnteil = false,
    int? svFreiAnteilCents,
    bool clearSvFreiAnteil = false,
    String? note,
    bool clearNote = false,
  }) {
    return PayrollLine(
      lineTypeId: clearLineTypeId ? null : (lineTypeId ?? this.lineTypeId),
      name: name ?? this.name,
      datevLohnartNr: clearDatevLohnartNr
          ? null
          : (datevLohnartNr ?? this.datevLohnartNr),
      amountCents: amountCents ?? this.amountCents,
      kind: kind ?? this.kind,
      steuerfrei: steuerfrei ?? this.steuerfrei,
      svFrei: svFrei ?? this.svFrei,
      steuerfreiAnteilCents: clearSteuerfreiAnteil
          ? null
          : (steuerfreiAnteilCents ?? this.steuerfreiAnteilCents),
      svFreiAnteilCents: clearSvFreiAnteil
          ? null
          : (svFreiAnteilCents ?? this.svFreiAnteilCents),
      note: clearNote ? null : (note ?? this.note),
    );
  }
}

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

/// Status einer Lohnabrechnung im Freigabe-Workflow.
enum PayrollStatus { entwurf, freigegeben, bezahlt, storniert }

extension PayrollStatusX on PayrollStatus {
  String get value => switch (this) {
        PayrollStatus.entwurf => 'entwurf',
        PayrollStatus.freigegeben => 'freigegeben',
        PayrollStatus.bezahlt => 'bezahlt',
        PayrollStatus.storniert => 'storniert',
      };

  String get label => switch (this) {
        PayrollStatus.entwurf => 'Entwurf',
        PayrollStatus.freigegeben => 'Freigegeben',
        PayrollStatus.bezahlt => 'Bezahlt',
        PayrollStatus.storniert => 'Storniert',
      };

  /// Gilt die Abrechnung als final (freigegeben oder bezahlt)?
  bool get isFinalized =>
      this == PayrollStatus.freigegeben || this == PayrollStatus.bezahlt;

  static PayrollStatus fromValue(String? value) => switch (value) {
        'freigegeben' => PayrollStatus.freigegeben,
        'bezahlt' => PayrollStatus.bezahlt,
        'storniert' => PayrollStatus.storniert,
        _ => PayrollStatus.entwurf,
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
    this.status = PayrollStatus.entwurf,
    this.finalizedByUid,
    this.finalizedAt,
    this.journalEntryId,
    this.lines = const [],
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

  /// Freigabe-Status (Default: Entwurf).
  final PayrollStatus status;

  /// Wer hat die Abrechnung freigegeben/bezahlt markiert (uid).
  final String? finalizedByUid;

  /// Zeitpunkt der Freigabe/Statusänderung.
  final DateTime? finalizedAt;

  /// Verknüpfte Finanz-Buchung (`JournalEntry.id`), sobald die Personalkosten
  /// bei der Freigabe automatisch in die Buchhaltung gebucht wurden (H-A1).
  /// `null` = noch nicht gebucht. Dient zugleich als Idempotenz-Marker gegen
  /// Doppelbuchung im hybrid-Fallback (zusätzlich zur deterministischen
  /// Journal-Doc-ID `pay-<documentId>`).
  final String? journalEntryId;

  /// Itemisierte Zusatz-Lohnzeilen (Plan §5.7/§5.8, M-L): Grundlohn-Line,
  /// §3b-Zuschläge, VwL, Einmalzahlungen … **zusätzlich** zu den bestehenden
  /// Einzelfeldern (die bleiben für Brutto/Netto maßgeblich). Eingebettet.
  final List<PayrollLine> lines;

  final String? note;
  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Summe aller Lohnzeilen (signiert) in Cent.
  int get linesTotalCents =>
      lines.fold(0, (acc, line) => acc + line.amountCents);

  /// Steuerpflichtiger Anteil aller Lohnzeilen (z. B. §3b-Rest über 50 €).
  int get steuerpflichtigeLinesCents =>
      lines.fold(0, (acc, line) => acc + line.steuerpflichtigCents);

  /// SV-pflichtiger Anteil aller Lohnzeilen (z. B. §3b-Rest über 25 €).
  int get svPflichtigeLinesCents =>
      lines.fold(0, (acc, line) => acc + line.svPflichtigCents);

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
      status: PayrollStatusX.fromValue(map['status']?.toString()),
      finalizedByUid: map['finalizedByUid'] as String?,
      finalizedAt: FirestoreDateParser.readDate(map['finalizedAt']),
      journalEntryId: map['journalEntryId'] as String?,
      lines: _parseLines(map['lines'], local: false),
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
      status: PayrollStatusX.fromValue(map['status']?.toString()),
      finalizedByUid: map['finalized_by_uid'] as String?,
      finalizedAt: FirestoreDateParser.readLocalDate(map['finalized_at']),
      journalEntryId: map['journal_entry_id'] as String?,
      lines: _parseLines(map['lines'], local: true),
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
      'status': status.value,
      'finalizedByUid': finalizedByUid,
      'finalizedAt':
          finalizedAt == null ? null : Timestamp.fromDate(finalizedAt!),
      'journalEntryId': journalEntryId,
      'lines': lines.map((line) => line.toFirestoreMap()).toList(),
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
      'status': status.value,
      'finalized_by_uid': finalizedByUid,
      'finalized_at': finalizedAt?.toIso8601String(),
      'journal_entry_id': journalEntryId,
      'lines': lines.map((line) => line.toMap()).toList(),
      'note': note,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  /// Parst die eingebettete Lohnzeilen-Liste tolerant (camelCase via
  /// [PayrollLine.fromFirestore] bzw. snake_case via [PayrollLine.fromMap]).
  static List<PayrollLine> _parseLines(dynamic raw, {required bool local}) {
    if (raw is! List) {
      return const [];
    }
    return raw
        .whereType<Map>()
        .map((e) {
          final map = Map<String, dynamic>.from(e);
          return local
              ? PayrollLine.fromMap(map)
              : PayrollLine.fromFirestore(map);
        })
        .toList(growable: false);
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
    PayrollStatus? status,
    String? finalizedByUid,
    bool clearFinalizedBy = false,
    DateTime? finalizedAt,
    bool clearFinalizedAt = false,
    String? journalEntryId,
    bool clearJournalEntryId = false,
    List<PayrollLine>? lines,
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
      status: status ?? this.status,
      finalizedByUid:
          clearFinalizedBy ? null : (finalizedByUid ?? this.finalizedByUid),
      finalizedAt:
          clearFinalizedAt ? null : (finalizedAt ?? this.finalizedAt),
      journalEntryId: clearJournalEntryId
          ? null
          : (journalEntryId ?? this.journalEntryId),
      lines: lines ?? this.lines,
      note: clearNote ? null : (note ?? this.note),
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
