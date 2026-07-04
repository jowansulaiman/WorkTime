import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;
import 'payroll_extras.dart';

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

/// Art des Erwerbs/Beschäftigungsverhältnisses (AllTec-Parität, Status-Tab).
enum Erwerbsart {
  festanstellungHaupterwerb,
  festanstellungNebenerwerb,
  geringfuegigeBeschaeftigung,
  midijob,
  praktikum,
  werkstudent,
}

extension ErwerbsartX on Erwerbsart {
  String get value => switch (this) {
        Erwerbsart.festanstellungHaupterwerb => 'festanstellung_haupterwerb',
        Erwerbsart.festanstellungNebenerwerb => 'festanstellung_nebenerwerb',
        Erwerbsart.geringfuegigeBeschaeftigung =>
          'geringfuegige_beschaeftigung',
        Erwerbsart.midijob => 'midijob',
        Erwerbsart.praktikum => 'praktikum',
        Erwerbsart.werkstudent => 'werkstudent',
      };

  String get label => switch (this) {
        Erwerbsart.festanstellungHaupterwerb => 'Festanstellung Haupterwerb',
        Erwerbsart.festanstellungNebenerwerb => 'Festanstellung Nebenerwerb',
        Erwerbsart.geringfuegigeBeschaeftigung => 'Geringfügige Beschäftigung',
        Erwerbsart.midijob => 'Midijob',
        Erwerbsart.praktikum => 'Praktikum',
        Erwerbsart.werkstudent => 'Werkstudent',
      };

  static Erwerbsart? fromValue(String? value) => switch (value) {
        'festanstellung_haupterwerb' => Erwerbsart.festanstellungHaupterwerb,
        'festanstellung_nebenerwerb' => Erwerbsart.festanstellungNebenerwerb,
        'geringfuegige_beschaeftigung' =>
          Erwerbsart.geringfuegigeBeschaeftigung,
        'midijob' => Erwerbsart.midijob,
        'praktikum' => Erwerbsart.praktikum,
        'werkstudent' => Erwerbsart.werkstudent,
        _ => null,
      };
}

/// Typ der Kündigungsfrist (AllTec-Parität, Status-Tab).
enum KuendigungsfristTyp {
  wochenAbKuendigung,
  wochenZumMonatsende,
  monateZumMonatsende,
  monateZumQuartalsende,
  monateZumJahresende,
}

extension KuendigungsfristTypX on KuendigungsfristTyp {
  String get value => switch (this) {
        KuendigungsfristTyp.wochenAbKuendigung => 'wochen_ab_kuendigung',
        KuendigungsfristTyp.wochenZumMonatsende => 'wochen_zum_monatsende',
        KuendigungsfristTyp.monateZumMonatsende => 'monate_zum_monatsende',
        KuendigungsfristTyp.monateZumQuartalsende => 'monate_zum_quartalsende',
        KuendigungsfristTyp.monateZumJahresende => 'monate_zum_jahresende',
      };

  String get label => switch (this) {
        KuendigungsfristTyp.wochenAbKuendigung => 'Wochen ab Kündigung',
        KuendigungsfristTyp.wochenZumMonatsende => 'Wochen zum Monatsende',
        KuendigungsfristTyp.monateZumMonatsende => 'Monate zum Monatsende',
        KuendigungsfristTyp.monateZumQuartalsende => 'Monate zum Quartalsende',
        KuendigungsfristTyp.monateZumJahresende => 'Monate zum Jahresende',
      };

  static KuendigungsfristTyp? fromValue(String? value) => switch (value) {
        'wochen_ab_kuendigung' => KuendigungsfristTyp.wochenAbKuendigung,
        'wochen_zum_monatsende' => KuendigungsfristTyp.wochenZumMonatsende,
        'monate_zum_monatsende' => KuendigungsfristTyp.monateZumMonatsende,
        'monate_zum_quartalsende' => KuendigungsfristTyp.monateZumQuartalsende,
        'monate_zum_jahresende' => KuendigungsfristTyp.monateZumJahresende,
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
    this.kuerzel,
    this.geburtsort,
    this.geburtsname,
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
    // Klassifizierung / Organisation (AllTec-Parität)
    this.abteilung,
    this.position,
    this.kostenstelle,
    this.vorgesetzterName,
    this.vertreterName,
    this.produktiveZeitProzent,
    this.fteFaktor,
    // Status & Vereinbarungen (AllTec-Parität)
    this.erwerbsart,
    this.teilnahmeZeiterfassung,
    this.autoBuchung,
    this.langzeitkrankAb,
    this.letzterArbeitstag,
    this.kuendigungsfristWert,
    this.kuendigungsfristTyp,
    this.kuendigungsfristAnmerkung,
    this.kuendigungsDatum,
    this.kuendigungsgrund,
    this.austrittsgrund,
    this.austrittsmodalitaeten,
    // Gehalt (AllTec-Parität): Zusatzfelder + eingebettete Nebenobjekte
    this.entgeltgruppe,
    this.gehaltGueltigAb,
    this.vwl,
    this.zulagen = const [],
    this.bankAccounts = const [],
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
  final String? kuerzel;
  final String? geburtsort;
  final String? geburtsname;

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

  /// **Deprecated (M0):** Der kanonische Jahresurlaub liegt seit M0 in
  /// `SollzeitProfile.urlaubstageJahr`. Dieses Altfeld bleibt nur als
  /// **Fallback** der Vorrangregel §5.1 (`resolveUrlaubstageJahr`) erhalten und
  /// wird per `PersonalProvider.migriereUrlaubstageInSollzeit()` dorthin
  /// übertragen. Nicht mehr als neue Quelle verwenden.
  final int? annualVacationDays;

  final String? emergencyContactName;
  final String? emergencyContactPhone;

  final String? note;

  // Klassifizierung / Organisation (AllTec-Parität).
  final String? abteilung;
  final String? position;
  final String? kostenstelle;
  final String? vorgesetzterName;
  final String? vertreterName;
  final double? produktiveZeitProzent;
  final double? fteFaktor;

  // Status & Vereinbarungen (AllTec-Parität).
  final Erwerbsart? erwerbsart;
  final bool? teilnahmeZeiterfassung;
  final bool? autoBuchung;
  final DateTime? langzeitkrankAb;
  final DateTime? letzterArbeitstag;
  final int? kuendigungsfristWert;
  final KuendigungsfristTyp? kuendigungsfristTyp;
  final String? kuendigungsfristAnmerkung;
  final DateTime? kuendigungsDatum;
  final String? kuendigungsgrund;
  final String? austrittsgrund;
  final String? austrittsmodalitaeten;

  // Gehalt (AllTec-Parität).
  final String? entgeltgruppe;
  final DateTime? gehaltGueltigAb;
  final VwlData? vwl;
  final List<SalaryAllowance> zulagen;
  final List<BankAccount> bankAccounts;

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
        kuerzel,
        geburtsort,
        geburtsname,
        abteilung,
        position,
        kostenstelle,
        vorgesetzterName,
        vertreterName,
        kuendigungsfristAnmerkung,
        kuendigungsgrund,
        austrittsgrund,
        austrittsmodalitaeten,
        entgeltgruppe,
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
      produktiveZeitProzent == null &&
      fteFaktor == null &&
      erwerbsart == null &&
      teilnahmeZeiterfassung == null &&
      autoBuchung == null &&
      langzeitkrankAb == null &&
      letzterArbeitstag == null &&
      kuendigungsfristWert == null &&
      kuendigungsfristTyp == null &&
      kuendigungsDatum == null &&
      gehaltGueltigAb == null &&
      vwl == null &&
      zulagen.isEmpty &&
      bankAccounts.isEmpty &&
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
      kuerzel: map['kuerzel'] as String?,
      geburtsort: map['geburtsort'] as String?,
      geburtsname: map['geburtsname'] as String?,
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
      abteilung: map['abteilung'] as String?,
      position: map['position'] as String?,
      kostenstelle: map['kostenstelle'] as String?,
      vorgesetzterName: map['vorgesetzterName'] as String?,
      vertreterName: map['vertreterName'] as String?,
      produktiveZeitProzent: parse.toDouble(map['produktiveZeitProzent']),
      fteFaktor: parse.toDouble(map['fteFaktor']),
      erwerbsart: ErwerbsartX.fromValue(map['erwerbsart']?.toString()),
      teilnahmeZeiterfassung: parse.toBool(map['teilnahmeZeiterfassung']),
      autoBuchung: parse.toBool(map['autoBuchung']),
      langzeitkrankAb: FirestoreDateParser.readDate(map['langzeitkrankAb']),
      letzterArbeitstag: FirestoreDateParser.readDate(map['letzterArbeitstag']),
      kuendigungsfristWert: parse.toInt(map['kuendigungsfristWert']),
      kuendigungsfristTyp: KuendigungsfristTypX.fromValue(
          map['kuendigungsfristTyp']?.toString()),
      kuendigungsfristAnmerkung: map['kuendigungsfristAnmerkung'] as String?,
      kuendigungsDatum: FirestoreDateParser.readDate(map['kuendigungsDatum']),
      kuendigungsgrund: map['kuendigungsgrund'] as String?,
      austrittsgrund: map['austrittsgrund'] as String?,
      austrittsmodalitaeten: map['austrittsmodalitaeten'] as String?,
      entgeltgruppe: map['entgeltgruppe'] as String?,
      gehaltGueltigAb: FirestoreDateParser.readDate(map['gehaltGueltigAb']),
      vwl: map['vwl'] is Map
          ? VwlData.fromFirestore(Map<String, dynamic>.from(map['vwl'] as Map))
          : null,
      zulagen: (map['zulagen'] as List?)
              ?.whereType<Map>()
              .map((e) =>
                  SalaryAllowance.fromFirestore(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      bankAccounts: (map['bankAccounts'] as List?)
              ?.whereType<Map>()
              .map((e) => BankAccount.fromFirestore(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
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
      kuerzel: map['kuerzel'] as String?,
      geburtsort: map['geburtsort'] as String?,
      geburtsname: map['geburtsname'] as String?,
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
      abteilung: map['abteilung'] as String?,
      position: map['position'] as String?,
      kostenstelle: map['kostenstelle'] as String?,
      vorgesetzterName: map['vorgesetzter_name'] as String?,
      vertreterName: map['vertreter_name'] as String?,
      produktiveZeitProzent: parse.toDouble(map['produktive_zeit_prozent']),
      fteFaktor: parse.toDouble(map['fte_faktor']),
      erwerbsart: ErwerbsartX.fromValue(map['erwerbsart']?.toString()),
      teilnahmeZeiterfassung: parse.toBool(map['teilnahme_zeiterfassung']),
      autoBuchung: parse.toBool(map['auto_buchung']),
      langzeitkrankAb: FirestoreDateParser.readLocalDate(map['langzeitkrank_ab']),
      letzterArbeitstag:
          FirestoreDateParser.readLocalDate(map['letzter_arbeitstag']),
      kuendigungsfristWert: parse.toInt(map['kuendigungsfrist_wert']),
      kuendigungsfristTyp: KuendigungsfristTypX.fromValue(
          map['kuendigungsfrist_typ']?.toString()),
      kuendigungsfristAnmerkung: map['kuendigungsfrist_anmerkung'] as String?,
      kuendigungsDatum:
          FirestoreDateParser.readLocalDate(map['kuendigungs_datum']),
      kuendigungsgrund: map['kuendigungsgrund'] as String?,
      austrittsgrund: map['austrittsgrund'] as String?,
      austrittsmodalitaeten: map['austrittsmodalitaeten'] as String?,
      entgeltgruppe: map['entgeltgruppe'] as String?,
      gehaltGueltigAb:
          FirestoreDateParser.readLocalDate(map['gehalt_gueltig_ab']),
      vwl: map['vwl'] is Map
          ? VwlData.fromMap(Map<String, dynamic>.from(map['vwl'] as Map))
          : null,
      zulagen: (map['zulagen'] as List?)
              ?.whereType<Map>()
              .map((e) => SalaryAllowance.fromMap(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      bankAccounts: (map['bank_accounts'] as List?)
              ?.whereType<Map>()
              .map((e) => BankAccount.fromMap(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
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
      'kuerzel': _clean(kuerzel),
      'geburtsort': _clean(geburtsort),
      'geburtsname': _clean(geburtsname),
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
      'abteilung': _clean(abteilung),
      'position': _clean(position),
      'kostenstelle': _clean(kostenstelle),
      'vorgesetzterName': _clean(vorgesetzterName),
      'vertreterName': _clean(vertreterName),
      'produktiveZeitProzent': produktiveZeitProzent,
      'fteFaktor': fteFaktor,
      'erwerbsart': erwerbsart?.value,
      'teilnahmeZeiterfassung': teilnahmeZeiterfassung,
      'autoBuchung': autoBuchung,
      'langzeitkrankAb': _dateOnly(langzeitkrankAb),
      'letzterArbeitstag': _dateOnly(letzterArbeitstag),
      'kuendigungsfristWert': kuendigungsfristWert,
      'kuendigungsfristTyp': kuendigungsfristTyp?.value,
      'kuendigungsfristAnmerkung': _clean(kuendigungsfristAnmerkung),
      'kuendigungsDatum': _dateOnly(kuendigungsDatum),
      'kuendigungsgrund': _clean(kuendigungsgrund),
      'austrittsgrund': _clean(austrittsgrund),
      'austrittsmodalitaeten': _clean(austrittsmodalitaeten),
      'entgeltgruppe': _clean(entgeltgruppe),
      'gehaltGueltigAb': _dateOnly(gehaltGueltigAb),
      'vwl': vwl?.toFirestoreMap(),
      'zulagen': zulagen.map((e) => e.toFirestoreMap()).toList(),
      'bankAccounts': bankAccounts.map((e) => e.toFirestoreMap()).toList(),
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
      'kuerzel': kuerzel,
      'geburtsort': geburtsort,
      'geburtsname': geburtsname,
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
      'abteilung': abteilung,
      'position': position,
      'kostenstelle': kostenstelle,
      'vorgesetzter_name': vorgesetzterName,
      'vertreter_name': vertreterName,
      'produktive_zeit_prozent': produktiveZeitProzent,
      'fte_faktor': fteFaktor,
      'erwerbsart': erwerbsart?.value,
      'teilnahme_zeiterfassung': teilnahmeZeiterfassung,
      'auto_buchung': autoBuchung,
      'langzeitkrank_ab': langzeitkrankAb?.toIso8601String(),
      'letzter_arbeitstag': letzterArbeitstag?.toIso8601String(),
      'kuendigungsfrist_wert': kuendigungsfristWert,
      'kuendigungsfrist_typ': kuendigungsfristTyp?.value,
      'kuendigungsfrist_anmerkung': kuendigungsfristAnmerkung,
      'kuendigungs_datum': kuendigungsDatum?.toIso8601String(),
      'kuendigungsgrund': kuendigungsgrund,
      'austrittsgrund': austrittsgrund,
      'austrittsmodalitaeten': austrittsmodalitaeten,
      'entgeltgruppe': entgeltgruppe,
      'gehalt_gueltig_ab': gehaltGueltigAb?.toIso8601String(),
      'vwl': vwl?.toMap(),
      'zulagen': zulagen.map((e) => e.toMap()).toList(),
      'bank_accounts': bankAccounts.map((e) => e.toMap()).toList(),
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
    String? kuerzel,
    String? geburtsort,
    String? geburtsname,
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
    String? abteilung,
    String? position,
    String? kostenstelle,
    String? vorgesetzterName,
    String? vertreterName,
    double? produktiveZeitProzent,
    double? fteFaktor,
    Erwerbsart? erwerbsart,
    bool? teilnahmeZeiterfassung,
    bool? autoBuchung,
    DateTime? langzeitkrankAb,
    DateTime? letzterArbeitstag,
    int? kuendigungsfristWert,
    KuendigungsfristTyp? kuendigungsfristTyp,
    String? kuendigungsfristAnmerkung,
    DateTime? kuendigungsDatum,
    String? kuendigungsgrund,
    String? austrittsgrund,
    String? austrittsmodalitaeten,
    // Clear-Flags für die per-Abschnitt-Editoren des Stammdaten-Tabs (AllTec):
    // erlauben das gezielte Leeren nullbarer Datums-/Enum-/Zahl-Felder (Text-
    // felder werden über '' + `_clean` geleert).
    bool clearPersonnelGroup = false,
    bool clearHireDate = false,
    bool clearExitDate = false,
    bool clearProbationEnd = false,
    bool clearLimitedUntil = false,
    bool clearMaritalStatus = false,
    bool clearConfession = false,
    bool clearProduktiveZeitProzent = false,
    bool clearFteFaktor = false,
    bool clearErwerbsart = false,
    bool clearLangzeitkrankAb = false,
    bool clearLetzterArbeitstag = false,
    bool clearKuendigungsfristWert = false,
    bool clearKuendigungsfristTyp = false,
    bool clearKuendigungsDatum = false,
    String? entgeltgruppe,
    DateTime? gehaltGueltigAb,
    bool clearGehaltGueltigAb = false,
    VwlData? vwl,
    bool clearVwl = false,
    List<SalaryAllowance>? zulagen,
    List<BankAccount>? bankAccounts,
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
      kuerzel: kuerzel ?? this.kuerzel,
      geburtsort: geburtsort ?? this.geburtsort,
      geburtsname: geburtsname ?? this.geburtsname,
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
      personnelGroup:
          clearPersonnelGroup ? null : (personnelGroup ?? this.personnelGroup),
      hireDate: clearHireDate ? null : (hireDate ?? this.hireDate),
      exitDate: clearExitDate ? null : (exitDate ?? this.exitDate),
      probationEnd:
          clearProbationEnd ? null : (probationEnd ?? this.probationEnd),
      limitedUntil:
          clearLimitedUntil ? null : (limitedUntil ?? this.limitedUntil),
      maritalStatus:
          clearMaritalStatus ? null : (maritalStatus ?? this.maritalStatus),
      confession: clearConfession ? null : (confession ?? this.confession),
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
      abteilung: abteilung ?? this.abteilung,
      position: position ?? this.position,
      kostenstelle: kostenstelle ?? this.kostenstelle,
      vorgesetzterName: vorgesetzterName ?? this.vorgesetzterName,
      vertreterName: vertreterName ?? this.vertreterName,
      produktiveZeitProzent: clearProduktiveZeitProzent
          ? null
          : (produktiveZeitProzent ?? this.produktiveZeitProzent),
      fteFaktor: clearFteFaktor ? null : (fteFaktor ?? this.fteFaktor),
      erwerbsart: clearErwerbsart ? null : (erwerbsart ?? this.erwerbsart),
      teilnahmeZeiterfassung:
          teilnahmeZeiterfassung ?? this.teilnahmeZeiterfassung,
      autoBuchung: autoBuchung ?? this.autoBuchung,
      langzeitkrankAb:
          clearLangzeitkrankAb ? null : (langzeitkrankAb ?? this.langzeitkrankAb),
      letzterArbeitstag: clearLetzterArbeitstag
          ? null
          : (letzterArbeitstag ?? this.letzterArbeitstag),
      kuendigungsfristWert: clearKuendigungsfristWert
          ? null
          : (kuendigungsfristWert ?? this.kuendigungsfristWert),
      kuendigungsfristTyp: clearKuendigungsfristTyp
          ? null
          : (kuendigungsfristTyp ?? this.kuendigungsfristTyp),
      kuendigungsfristAnmerkung:
          kuendigungsfristAnmerkung ?? this.kuendigungsfristAnmerkung,
      kuendigungsDatum:
          clearKuendigungsDatum ? null : (kuendigungsDatum ?? this.kuendigungsDatum),
      kuendigungsgrund: kuendigungsgrund ?? this.kuendigungsgrund,
      austrittsgrund: austrittsgrund ?? this.austrittsgrund,
      austrittsmodalitaeten:
          austrittsmodalitaeten ?? this.austrittsmodalitaeten,
      entgeltgruppe: entgeltgruppe ?? this.entgeltgruppe,
      gehaltGueltigAb: clearGehaltGueltigAb
          ? null
          : (gehaltGueltigAb ?? this.gehaltGueltigAb),
      vwl: clearVwl ? null : (vwl ?? this.vwl),
      zulagen: zulagen ?? this.zulagen,
      bankAccounts: bankAccounts ?? this.bankAccounts,
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
