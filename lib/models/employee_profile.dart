import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Familienstand (lohn-/steuerrelevant).
enum MaritalStatus {
  ledig,
  verheiratet,
  geschieden,
  verwitwet,
  getrenntLebend,
  eingetrageneLebenspartnerschaft,
}

extension MaritalStatusX on MaritalStatus {
  String get value => switch (this) {
        MaritalStatus.ledig => 'ledig',
        MaritalStatus.verheiratet => 'verheiratet',
        MaritalStatus.geschieden => 'geschieden',
        MaritalStatus.verwitwet => 'verwitwet',
        MaritalStatus.getrenntLebend => 'getrennt_lebend',
        MaritalStatus.eingetrageneLebenspartnerschaft =>
          'eingetragene_lebenspartnerschaft',
      };

  String get label => switch (this) {
        MaritalStatus.ledig => 'ledig',
        MaritalStatus.verheiratet => 'verheiratet',
        MaritalStatus.geschieden => 'geschieden',
        MaritalStatus.verwitwet => 'verwitwet',
        MaritalStatus.getrenntLebend => 'getrennt lebend',
        MaritalStatus.eingetrageneLebenspartnerschaft =>
          'eingetragene Lebenspartnerschaft',
      };

  static MaritalStatus? fromValue(String? value) => switch (value) {
        'ledig' => MaritalStatus.ledig,
        'verheiratet' => MaritalStatus.verheiratet,
        'geschieden' => MaritalStatus.geschieden,
        'verwitwet' => MaritalStatus.verwitwet,
        'getrennt_lebend' => MaritalStatus.getrenntLebend,
        'eingetragene_lebenspartnerschaft' =>
          MaritalStatus.eingetrageneLebenspartnerschaft,
        _ => null,
      };
}

/// Konfession (für die Kirchensteuerpflicht).
enum Confession { keine, evangelisch, katholisch, sonstige }

extension ConfessionX on Confession {
  String get value => switch (this) {
        Confession.keine => 'keine',
        Confession.evangelisch => 'evangelisch',
        Confession.katholisch => 'katholisch',
        Confession.sonstige => 'sonstige',
      };

  String get label => switch (this) {
        Confession.keine => 'keine',
        Confession.evangelisch => 'evangelisch',
        Confession.katholisch => 'römisch-katholisch',
        Confession.sonstige => 'sonstige',
      };

  /// Konfessionen, die zur Kirchensteuer herangezogen werden.
  bool get isChurchTaxable =>
      this == Confession.evangelisch || this == Confession.katholisch;

  static Confession? fromValue(String? value) => switch (value) {
        'keine' => Confession.keine,
        'evangelisch' => Confession.evangelisch,
        'katholisch' => Confession.katholisch,
        'sonstige' => Confession.sonstige,
        _ => null,
      };
}

/// Personengruppe (SV-Meldewesen, vereinfacht).
enum PersonnelGroup {
  angestellter,
  arbeiter,
  leitenderAngestellter,
  auszubildender,
  praktikant,
  werkstudent,
  geringfuegigBeschaeftigter,
}

extension PersonnelGroupX on PersonnelGroup {
  String get value => switch (this) {
        PersonnelGroup.angestellter => 'angestellter',
        PersonnelGroup.arbeiter => 'arbeiter',
        PersonnelGroup.leitenderAngestellter => 'leitender_angestellter',
        PersonnelGroup.auszubildender => 'auszubildender',
        PersonnelGroup.praktikant => 'praktikant',
        PersonnelGroup.werkstudent => 'werkstudent',
        PersonnelGroup.geringfuegigBeschaeftigter =>
          'geringfuegig_beschaeftigter',
      };

  String get label => switch (this) {
        PersonnelGroup.angestellter => 'Angestellte:r',
        PersonnelGroup.arbeiter => 'Arbeiter:in',
        PersonnelGroup.leitenderAngestellter => 'Leitende:r Angestellte:r',
        PersonnelGroup.auszubildender => 'Auszubildende:r',
        PersonnelGroup.praktikant => 'Praktikant:in',
        PersonnelGroup.werkstudent => 'Werkstudent:in',
        PersonnelGroup.geringfuegigBeschaeftigter => 'Geringfügig beschäftigt',
      };

  static PersonnelGroup? fromValue(String? value) => switch (value) {
        'angestellter' => PersonnelGroup.angestellter,
        'arbeiter' => PersonnelGroup.arbeiter,
        'leitender_angestellter' => PersonnelGroup.leitenderAngestellter,
        'auszubildender' => PersonnelGroup.auszubildender,
        'praktikant' => PersonnelGroup.praktikant,
        'werkstudent' => PersonnelGroup.werkstudent,
        'geringfuegig_beschaeftigter' =>
          PersonnelGroup.geringfuegigBeschaeftigter,
        _ => null,
      };
}

/// Status des Beschäftigungsverhältnisses.
enum EmployeeStatus { aktiv, probezeit, gekuendigt, ausgeschieden, ruhend }

extension EmployeeStatusX on EmployeeStatus {
  String get value => switch (this) {
        EmployeeStatus.aktiv => 'aktiv',
        EmployeeStatus.probezeit => 'probezeit',
        EmployeeStatus.gekuendigt => 'gekuendigt',
        EmployeeStatus.ausgeschieden => 'ausgeschieden',
        EmployeeStatus.ruhend => 'ruhend',
      };

  String get label => switch (this) {
        EmployeeStatus.aktiv => 'Aktiv',
        EmployeeStatus.probezeit => 'Probezeit',
        EmployeeStatus.gekuendigt => 'Gekündigt',
        EmployeeStatus.ausgeschieden => 'Ausgeschieden',
        EmployeeStatus.ruhend => 'Ruhend',
      };

  /// Zählt das Beschäftigungsverhältnis als laufend (für aktive Sichten)?
  bool get isCurrent =>
      this == EmployeeStatus.aktiv || this == EmployeeStatus.probezeit;

  /// Default-Branch wirft nie (Enum-Kopplungsregel).
  static EmployeeStatus fromValue(String? value) => switch (value) {
        'aktiv' => EmployeeStatus.aktiv,
        'probezeit' => EmployeeStatus.probezeit,
        'gekuendigt' => EmployeeStatus.gekuendigt,
        'ausgeschieden' => EmployeeStatus.ausgeschieden,
        'ruhend' => EmployeeStatus.ruhend,
        _ => EmployeeStatus.aktiv,
      };
}

/// Art der Krankenversicherung.
enum HealthInsuranceType { gesetzlich, privat, freiwillig }

extension HealthInsuranceTypeX on HealthInsuranceType {
  String get value => switch (this) {
        HealthInsuranceType.gesetzlich => 'gesetzlich',
        HealthInsuranceType.privat => 'privat',
        HealthInsuranceType.freiwillig => 'freiwillig',
      };

  String get label => switch (this) {
        HealthInsuranceType.gesetzlich => 'gesetzlich pflichtversichert',
        HealthInsuranceType.privat => 'privat versichert',
        HealthInsuranceType.freiwillig => 'freiwillig gesetzlich',
      };

  static HealthInsuranceType? fromValue(String? value) => switch (value) {
        'gesetzlich' => HealthInsuranceType.gesetzlich,
        'privat' => HealthInsuranceType.privat,
        'freiwillig' => HealthInsuranceType.freiwillig,
        _ => null,
      };
}

/// Personal-Stammakte eines Mitarbeiters (admin-only).
///
/// Ergänzt die schlanken Login-/Vertragsdaten ([AppUserProfile],
/// [EmploymentContract]) und die Lohn-Vorbefüllung ([PayrollProfile]) um die
/// klassischen HR-Stammdaten: Anschrift, persönliche Daten, Eintritts-/
/// Austrittsdaten, Sozialversicherungs-/Bankdaten, Urlaubsanspruch und Notizen.
///
/// Org-skopiert unter `organizations/{orgId}/employeeProfiles/{userId}` mit
/// **deterministischer Doc-ID = userId** (genau eine Akte je Mitarbeiter,
/// erneutes Speichern überschreibt). Hält die Zwei-Serialisierungs-Regel ein
/// (camelCase+Timestamp für Firestore, snake_case+ISO für SharedPreferences).
///
/// **Datenschutz:** sensible besondere Kategorien (Grad der Behinderung,
/// Aufenthaltsstatus) werden bewusst NICHT erfasst; einzig lohnrelevante
/// Sonderkategorie ist die [confession] (für die Kirchensteuer).
///
/// `copyWith` ersetzt Felder nach dem `value ?? this.value`-Muster; ein Feld
/// wird durch erneutes vollständiges Speichern der Akte (Editor baut sie frisch
/// auf) geleert, nicht über einzelne `clearX`-Flags.
class EmployeeProfile {
  const EmployeeProfile({
    this.id,
    required this.orgId,
    required this.userId,
    // Persönlich
    this.salutation,
    this.titleAcademic,
    this.birthDate,
    this.nationality,
    // Anschrift
    this.street,
    this.houseNumber,
    this.postalCode,
    this.city,
    this.addressExtra,
    // Private Kontaktdaten
    this.privatePhone,
    this.privateMobile,
    this.privateEmail,
    // Beschäftigung
    this.personnelNumber,
    this.status = EmployeeStatus.aktiv,
    this.personnelGroup,
    this.hireDate,
    this.exitDate,
    this.probationEnd,
    this.limitedUntil,
    // Lohnrelevante Stammdaten
    this.maritalStatus,
    this.confession,
    this.childrenCount = 0,
    // Sozialversicherung / Steuer
    this.taxId,
    this.socialSecurityNumber,
    this.healthInsurance,
    this.healthInsuranceType,
    this.healthInsuranceSurchargePercent,
    // Bank
    this.iban,
    this.bic,
    this.accountHolder,
    // Urlaub
    this.annualVacationDays,
    // Notfallkontakt
    this.emergencyContactName,
    this.emergencyContactPhone,
    // Notizen
    this.note,
    // Meta
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;
  final String userId;

  final String? salutation;
  final String? titleAcademic;
  final DateTime? birthDate;
  final String? nationality;

  final String? street;
  final String? houseNumber;
  final String? postalCode;
  final String? city;
  final String? addressExtra;

  final String? privatePhone;
  final String? privateMobile;
  final String? privateEmail;

  final String? personnelNumber;
  final EmployeeStatus status;
  final PersonnelGroup? personnelGroup;
  final DateTime? hireDate;
  final DateTime? exitDate;
  final DateTime? probationEnd;
  final DateTime? limitedUntil;

  final MaritalStatus? maritalStatus;
  final Confession? confession;
  final int childrenCount;

  final String? taxId;
  final String? socialSecurityNumber;
  final String? healthInsurance;
  final HealthInsuranceType? healthInsuranceType;

  /// Kassenindividueller KV-Zusatzbeitrag in Prozent (z. B. 1.7). Fließt in
  /// die Lohnberechnung ein (sonst pauschaler Default der [PayrollSettings]).
  final double? healthInsuranceSurchargePercent;

  final String? iban;
  final String? bic;
  final String? accountHolder;

  final int? annualVacationDays;

  final String? emergencyContactName;
  final String? emergencyContactPhone;

  final String? note;

  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Deterministische Doc-ID (genau eine Akte je Mitarbeiter).
  String get documentId => userId;

  /// Vollständige Anschrift als einzeilige Zusammenfassung (oder null).
  String? get formattedAddress {
    final line1 = [street, houseNumber]
        .where((p) => p != null && p.trim().isNotEmpty)
        .join(' ')
        .trim();
    final line2 = [postalCode, city]
        .where((p) => p != null && p.trim().isNotEmpty)
        .join(' ')
        .trim();
    final parts = [line1, line2].where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return null;
    return parts.join(', ');
  }

  /// True, wenn keine inhaltlichen Felder gepflegt sind (nur Identität +
  /// Default-Status) – steuert die „Stammdaten erfassen"-Leeransicht.
  bool get isEmpty =>
      _allTrimmedEmpty([
        salutation,
        titleAcademic,
        nationality,
        street,
        houseNumber,
        postalCode,
        city,
        addressExtra,
        privatePhone,
        privateMobile,
        privateEmail,
        personnelNumber,
        taxId,
        socialSecurityNumber,
        healthInsurance,
        iban,
        bic,
        accountHolder,
        emergencyContactName,
        emergencyContactPhone,
        note,
      ]) &&
      birthDate == null &&
      hireDate == null &&
      exitDate == null &&
      probationEnd == null &&
      limitedUntil == null &&
      personnelGroup == null &&
      maritalStatus == null &&
      confession == null &&
      healthInsuranceType == null &&
      healthInsuranceSurchargePercent == null &&
      annualVacationDays == null &&
      childrenCount == 0 &&
      status == EmployeeStatus.aktiv;

  factory EmployeeProfile.fromFirestore(String id, Map<String, dynamic> map) {
    return EmployeeProfile(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      salutation: map['salutation'] as String?,
      titleAcademic: map['titleAcademic'] as String?,
      birthDate: FirestoreDateParser.readDate(map['birthDate']),
      nationality: map['nationality'] as String?,
      street: map['street'] as String?,
      houseNumber: map['houseNumber'] as String?,
      postalCode: map['postalCode'] as String?,
      city: map['city'] as String?,
      addressExtra: map['addressExtra'] as String?,
      privatePhone: map['privatePhone'] as String?,
      privateMobile: map['privateMobile'] as String?,
      privateEmail: map['privateEmail'] as String?,
      personnelNumber: map['personnelNumber'] as String?,
      status: EmployeeStatusX.fromValue(map['status']?.toString()),
      personnelGroup:
          PersonnelGroupX.fromValue(map['personnelGroup']?.toString()),
      hireDate: FirestoreDateParser.readDate(map['hireDate']),
      exitDate: FirestoreDateParser.readDate(map['exitDate']),
      probationEnd: FirestoreDateParser.readDate(map['probationEnd']),
      limitedUntil: FirestoreDateParser.readDate(map['limitedUntil']),
      maritalStatus:
          MaritalStatusX.fromValue(map['maritalStatus']?.toString()),
      confession: ConfessionX.fromValue(map['confession']?.toString()),
      childrenCount: parse.toInt(map['childrenCount']) ?? 0,
      taxId: map['taxId'] as String?,
      socialSecurityNumber: map['socialSecurityNumber'] as String?,
      healthInsurance: map['healthInsurance'] as String?,
      healthInsuranceType: HealthInsuranceTypeX.fromValue(
          map['healthInsuranceType']?.toString()),
      healthInsuranceSurchargePercent:
          parse.toDouble(map['healthInsuranceSurchargePercent']),
      iban: map['iban'] as String?,
      bic: map['bic'] as String?,
      accountHolder: map['accountHolder'] as String?,
      annualVacationDays: parse.toInt(map['annualVacationDays']),
      emergencyContactName: map['emergencyContactName'] as String?,
      emergencyContactPhone: map['emergencyContactPhone'] as String?,
      note: map['note'] as String?,
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory EmployeeProfile.fromMap(Map<String, dynamic> map) {
    return EmployeeProfile(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      salutation: map['salutation'] as String?,
      titleAcademic: map['title_academic'] as String?,
      birthDate: FirestoreDateParser.readLocalDate(map['birth_date']),
      nationality: map['nationality'] as String?,
      street: map['street'] as String?,
      houseNumber: map['house_number'] as String?,
      postalCode: map['postal_code'] as String?,
      city: map['city'] as String?,
      addressExtra: map['address_extra'] as String?,
      privatePhone: map['private_phone'] as String?,
      privateMobile: map['private_mobile'] as String?,
      privateEmail: map['private_email'] as String?,
      personnelNumber: map['personnel_number'] as String?,
      status: EmployeeStatusX.fromValue(map['status']?.toString()),
      personnelGroup:
          PersonnelGroupX.fromValue(map['personnel_group']?.toString()),
      hireDate: FirestoreDateParser.readLocalDate(map['hire_date']),
      exitDate: FirestoreDateParser.readLocalDate(map['exit_date']),
      probationEnd: FirestoreDateParser.readLocalDate(map['probation_end']),
      limitedUntil: FirestoreDateParser.readLocalDate(map['limited_until']),
      maritalStatus:
          MaritalStatusX.fromValue(map['marital_status']?.toString()),
      confession: ConfessionX.fromValue(map['confession']?.toString()),
      childrenCount: parse.toInt(map['children_count']) ?? 0,
      taxId: map['tax_id'] as String?,
      socialSecurityNumber: map['social_security_number'] as String?,
      healthInsurance: map['health_insurance'] as String?,
      healthInsuranceType: HealthInsuranceTypeX.fromValue(
          map['health_insurance_type']?.toString()),
      healthInsuranceSurchargePercent:
          parse.toDouble(map['health_insurance_surcharge_percent']),
      iban: map['iban'] as String?,
      bic: map['bic'] as String?,
      accountHolder: map['account_holder'] as String?,
      annualVacationDays: parse.toInt(map['annual_vacation_days']),
      emergencyContactName: map['emergency_contact_name'] as String?,
      emergencyContactPhone: map['emergency_contact_phone'] as String?,
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
      'salutation': _clean(salutation),
      'titleAcademic': _clean(titleAcademic),
      'birthDate': _dateOnly(birthDate),
      'nationality': _clean(nationality),
      'street': _clean(street),
      'houseNumber': _clean(houseNumber),
      'postalCode': _clean(postalCode),
      'city': _clean(city),
      'addressExtra': _clean(addressExtra),
      'privatePhone': _clean(privatePhone),
      'privateMobile': _clean(privateMobile),
      'privateEmail': _clean(privateEmail),
      'personnelNumber': _clean(personnelNumber),
      'status': status.value,
      'personnelGroup': personnelGroup?.value,
      'hireDate': _dateOnly(hireDate),
      'exitDate': _dateOnly(exitDate),
      'probationEnd': _dateOnly(probationEnd),
      'limitedUntil': _dateOnly(limitedUntil),
      'maritalStatus': maritalStatus?.value,
      'confession': confession?.value,
      'childrenCount': childrenCount,
      'taxId': _clean(taxId),
      'socialSecurityNumber': _clean(socialSecurityNumber),
      'healthInsurance': _clean(healthInsurance),
      'healthInsuranceType': healthInsuranceType?.value,
      'healthInsuranceSurchargePercent': healthInsuranceSurchargePercent,
      'iban': _clean(iban),
      'bic': _clean(bic),
      'accountHolder': _clean(accountHolder),
      'annualVacationDays': annualVacationDays,
      'emergencyContactName': _clean(emergencyContactName),
      'emergencyContactPhone': _clean(emergencyContactPhone),
      'note': _clean(note),
      'createdByUid': createdByUid,
      // createdAt nur beim Erst-Write setzen: Doc-ID ist deterministisch (id wird
      // vor dem Speichern stets gesetzt), daher knüpfen wir an createdAt == null
      // an. Bei Folge-Speicherungen wird der Key weggelassen, sodass merge:true
      // den vorhandenen Anlage-Zeitstempel erhält (Muster wie WorkTask).
      if (createdAt == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'user_id': userId,
      'salutation': salutation,
      'title_academic': titleAcademic,
      'birth_date': birthDate?.toIso8601String(),
      'nationality': nationality,
      'street': street,
      'house_number': houseNumber,
      'postal_code': postalCode,
      'city': city,
      'address_extra': addressExtra,
      'private_phone': privatePhone,
      'private_mobile': privateMobile,
      'private_email': privateEmail,
      'personnel_number': personnelNumber,
      'status': status.value,
      'personnel_group': personnelGroup?.value,
      'hire_date': hireDate?.toIso8601String(),
      'exit_date': exitDate?.toIso8601String(),
      'probation_end': probationEnd?.toIso8601String(),
      'limited_until': limitedUntil?.toIso8601String(),
      'marital_status': maritalStatus?.value,
      'confession': confession?.value,
      'children_count': childrenCount,
      'tax_id': taxId,
      'social_security_number': socialSecurityNumber,
      'health_insurance': healthInsurance,
      'health_insurance_type': healthInsuranceType?.value,
      'health_insurance_surcharge_percent': healthInsuranceSurchargePercent,
      'iban': iban,
      'bic': bic,
      'account_holder': accountHolder,
      'annual_vacation_days': annualVacationDays,
      'emergency_contact_name': emergencyContactName,
      'emergency_contact_phone': emergencyContactPhone,
      'note': note,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  EmployeeProfile copyWith({
    String? id,
    String? orgId,
    String? userId,
    String? salutation,
    String? titleAcademic,
    DateTime? birthDate,
    String? nationality,
    String? street,
    String? houseNumber,
    String? postalCode,
    String? city,
    String? addressExtra,
    String? privatePhone,
    String? privateMobile,
    String? privateEmail,
    String? personnelNumber,
    EmployeeStatus? status,
    PersonnelGroup? personnelGroup,
    DateTime? hireDate,
    DateTime? exitDate,
    DateTime? probationEnd,
    DateTime? limitedUntil,
    MaritalStatus? maritalStatus,
    Confession? confession,
    int? childrenCount,
    String? taxId,
    String? socialSecurityNumber,
    String? healthInsurance,
    HealthInsuranceType? healthInsuranceType,
    double? healthInsuranceSurchargePercent,
    String? iban,
    String? bic,
    String? accountHolder,
    int? annualVacationDays,
    String? emergencyContactName,
    String? emergencyContactPhone,
    String? note,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EmployeeProfile(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      userId: userId ?? this.userId,
      salutation: salutation ?? this.salutation,
      titleAcademic: titleAcademic ?? this.titleAcademic,
      birthDate: birthDate ?? this.birthDate,
      nationality: nationality ?? this.nationality,
      street: street ?? this.street,
      houseNumber: houseNumber ?? this.houseNumber,
      postalCode: postalCode ?? this.postalCode,
      city: city ?? this.city,
      addressExtra: addressExtra ?? this.addressExtra,
      privatePhone: privatePhone ?? this.privatePhone,
      privateMobile: privateMobile ?? this.privateMobile,
      privateEmail: privateEmail ?? this.privateEmail,
      personnelNumber: personnelNumber ?? this.personnelNumber,
      status: status ?? this.status,
      personnelGroup: personnelGroup ?? this.personnelGroup,
      hireDate: hireDate ?? this.hireDate,
      exitDate: exitDate ?? this.exitDate,
      probationEnd: probationEnd ?? this.probationEnd,
      limitedUntil: limitedUntil ?? this.limitedUntil,
      maritalStatus: maritalStatus ?? this.maritalStatus,
      confession: confession ?? this.confession,
      childrenCount: childrenCount ?? this.childrenCount,
      taxId: taxId ?? this.taxId,
      socialSecurityNumber: socialSecurityNumber ?? this.socialSecurityNumber,
      healthInsurance: healthInsurance ?? this.healthInsurance,
      healthInsuranceType: healthInsuranceType ?? this.healthInsuranceType,
      healthInsuranceSurchargePercent:
          healthInsuranceSurchargePercent ?? this.healthInsuranceSurchargePercent,
      iban: iban ?? this.iban,
      bic: bic ?? this.bic,
      accountHolder: accountHolder ?? this.accountHolder,
      annualVacationDays: annualVacationDays ?? this.annualVacationDays,
      emergencyContactName: emergencyContactName ?? this.emergencyContactName,
      emergencyContactPhone:
          emergencyContactPhone ?? this.emergencyContactPhone,
      note: note ?? this.note,
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static bool _allTrimmedEmpty(List<String?> values) =>
      values.every((v) => v == null || v.trim().isEmpty);

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  /// Normalisiert ein Datum auf reine Tagesgenauigkeit (12:00 lokal) und gibt
  /// einen Firestore-`Timestamp` zurück (oder null).
  static Timestamp? _dateOnly(DateTime? date) {
    if (date == null) return null;
    return Timestamp.fromDate(DateTime(date.year, date.month, date.day, 12));
  }
}
