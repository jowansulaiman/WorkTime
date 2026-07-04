import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Eingebettete Gehalts-Nebenobjekte des [EmployeeProfile] (AllTec-Parität,
/// Gehalt-Tab): VWL, Zulagen-Liste, Bankverbindungs-Liste. Alle drei werden als
/// verschachtelte Maps im `employeeProfiles`-Dokument gespeichert (kein eigenes
/// Collection/Rule), halten aber die Zwei-Serialisierungs-Regel je Element ein
/// (camelCase+Timestamp für Firestore, snake_case+ISO für lokal), analog
/// `PayrollLine`.

DateTime? _dateOnly(DateTime? d) =>
    d == null ? null : DateTime(d.year, d.month, d.day, 12);
Timestamp? _ts(DateTime? d) {
  final v = _dateOnly(d);
  return v == null ? null : Timestamp.fromDate(v);
}

/// Vermögenswirksame Leistungen (0..1 je Mitarbeiter).
class VwlData {
  const VwlData({
    this.arbeitgeberAnteilCents,
    this.arbeitnehmerAnteilCents,
    this.vertragsnummer,
    this.institut,
    this.vertragBeginn,
    this.vertragEnde,
  });

  final int? arbeitgeberAnteilCents;
  final int? arbeitnehmerAnteilCents;
  final String? vertragsnummer;
  final String? institut;
  final DateTime? vertragBeginn;
  final DateTime? vertragEnde;

  bool get isEmpty =>
      arbeitgeberAnteilCents == null &&
      arbeitnehmerAnteilCents == null &&
      (vertragsnummer == null || vertragsnummer!.trim().isEmpty) &&
      (institut == null || institut!.trim().isEmpty) &&
      vertragBeginn == null &&
      vertragEnde == null;

  factory VwlData.fromFirestore(Map<String, dynamic> map) => VwlData(
        arbeitgeberAnteilCents: parse.toInt(map['arbeitgeberAnteilCents']),
        arbeitnehmerAnteilCents: parse.toInt(map['arbeitnehmerAnteilCents']),
        vertragsnummer: map['vertragsnummer'] as String?,
        institut: map['institut'] as String?,
        vertragBeginn: FirestoreDateParser.readDate(map['vertragBeginn']),
        vertragEnde: FirestoreDateParser.readDate(map['vertragEnde']),
      );

  factory VwlData.fromMap(Map<String, dynamic> map) => VwlData(
        arbeitgeberAnteilCents: parse.toInt(map['arbeitgeber_anteil_cents']),
        arbeitnehmerAnteilCents: parse.toInt(map['arbeitnehmer_anteil_cents']),
        vertragsnummer: map['vertragsnummer'] as String?,
        institut: map['institut'] as String?,
        vertragBeginn: FirestoreDateParser.readLocalDate(map['vertrag_beginn']),
        vertragEnde: FirestoreDateParser.readLocalDate(map['vertrag_ende']),
      );

  Map<String, dynamic> toFirestoreMap() => {
        'arbeitgeberAnteilCents': arbeitgeberAnteilCents,
        'arbeitnehmerAnteilCents': arbeitnehmerAnteilCents,
        'vertragsnummer': vertragsnummer,
        'institut': institut,
        'vertragBeginn': _ts(vertragBeginn),
        'vertragEnde': _ts(vertragEnde),
      };

  Map<String, dynamic> toMap() => {
        'arbeitgeber_anteil_cents': arbeitgeberAnteilCents,
        'arbeitnehmer_anteil_cents': arbeitnehmerAnteilCents,
        'vertragsnummer': vertragsnummer,
        'institut': institut,
        'vertrag_beginn': _dateOnly(vertragBeginn)?.toIso8601String(),
        'vertrag_ende': _dateOnly(vertragEnde)?.toIso8601String(),
      };
}

/// Eine Gehaltszulage (z. B. Weihnachtsgeld). `betragCents` und `prozentsatz`
/// sind alternativ.
class SalaryAllowance {
  const SalaryAllowance({
    required this.id,
    this.bezeichnung = '',
    this.betragCents,
    this.prozentsatz,
    this.gueltigAb,
    this.gueltigBis,
    this.bemerkung,
  });

  final String id;
  final String bezeichnung;
  final int? betragCents;
  final double? prozentsatz;
  final DateTime? gueltigAb;
  final DateTime? gueltigBis;
  final String? bemerkung;

  factory SalaryAllowance.fromFirestore(Map<String, dynamic> map) =>
      SalaryAllowance(
        id: (map['id'] ?? '').toString(),
        bezeichnung: (map['bezeichnung'] ?? '').toString(),
        betragCents: parse.toInt(map['betragCents']),
        prozentsatz: parse.toDouble(map['prozentsatz']),
        gueltigAb: FirestoreDateParser.readDate(map['gueltigAb']),
        gueltigBis: FirestoreDateParser.readDate(map['gueltigBis']),
        bemerkung: map['bemerkung'] as String?,
      );

  factory SalaryAllowance.fromMap(Map<String, dynamic> map) => SalaryAllowance(
        id: (map['id'] ?? '').toString(),
        bezeichnung: (map['bezeichnung'] ?? '').toString(),
        betragCents: parse.toInt(map['betrag_cents']),
        prozentsatz: parse.toDouble(map['prozentsatz']),
        gueltigAb: FirestoreDateParser.readLocalDate(map['gueltig_ab']),
        gueltigBis: FirestoreDateParser.readLocalDate(map['gueltig_bis']),
        bemerkung: map['bemerkung'] as String?,
      );

  Map<String, dynamic> toFirestoreMap() => {
        'id': id,
        'bezeichnung': bezeichnung,
        'betragCents': betragCents,
        'prozentsatz': prozentsatz,
        'gueltigAb': _ts(gueltigAb),
        'gueltigBis': _ts(gueltigBis),
        'bemerkung': bemerkung,
      };

  Map<String, dynamic> toMap() => {
        'id': id,
        'bezeichnung': bezeichnung,
        'betrag_cents': betragCents,
        'prozentsatz': prozentsatz,
        'gueltig_ab': _dateOnly(gueltigAb)?.toIso8601String(),
        'gueltig_bis': _dateOnly(gueltigBis)?.toIso8601String(),
        'bemerkung': bemerkung,
      };

  SalaryAllowance copyWith({
    String? id,
    String? bezeichnung,
    int? betragCents,
    bool clearBetrag = false,
    double? prozentsatz,
    bool clearProzentsatz = false,
    DateTime? gueltigAb,
    DateTime? gueltigBis,
    String? bemerkung,
    bool clearBemerkung = false,
  }) =>
      SalaryAllowance(
        id: id ?? this.id,
        bezeichnung: bezeichnung ?? this.bezeichnung,
        betragCents: clearBetrag ? null : (betragCents ?? this.betragCents),
        prozentsatz:
            clearProzentsatz ? null : (prozentsatz ?? this.prozentsatz),
        gueltigAb: gueltigAb ?? this.gueltigAb,
        gueltigBis: gueltigBis ?? this.gueltigBis,
        bemerkung: clearBemerkung ? null : (bemerkung ?? this.bemerkung),
      );
}

/// Eine Bankverbindung des Mitarbeiters. `isPrimary` markiert das Hauptkonto.
class BankAccount {
  const BankAccount({
    required this.id,
    this.kontoinhaber,
    this.iban,
    this.bic,
    this.bankname,
    this.isPrimary = true,
  });

  final String id;
  final String? kontoinhaber;
  final String? iban;
  final String? bic;
  final String? bankname;
  final bool isPrimary;

  factory BankAccount.fromFirestore(Map<String, dynamic> map) => BankAccount(
        id: (map['id'] ?? '').toString(),
        kontoinhaber: map['kontoinhaber'] as String?,
        iban: map['iban'] as String?,
        bic: map['bic'] as String?,
        bankname: map['bankname'] as String?,
        isPrimary: parse.toBool(map['isPrimary']) ?? true,
      );

  factory BankAccount.fromMap(Map<String, dynamic> map) => BankAccount(
        id: (map['id'] ?? '').toString(),
        kontoinhaber: map['kontoinhaber'] as String?,
        iban: map['iban'] as String?,
        bic: map['bic'] as String?,
        bankname: map['bankname'] as String?,
        isPrimary: parse.toBool(map['is_primary']) ?? true,
      );

  Map<String, dynamic> toFirestoreMap() => {
        'id': id,
        'kontoinhaber': kontoinhaber,
        'iban': iban,
        'bic': bic,
        'bankname': bankname,
        'isPrimary': isPrimary,
      };

  Map<String, dynamic> toMap() => {
        'id': id,
        'kontoinhaber': kontoinhaber,
        'iban': iban,
        'bic': bic,
        'bankname': bankname,
        'is_primary': isPrimary,
      };

  BankAccount copyWith({
    String? id,
    String? kontoinhaber,
    String? iban,
    String? bic,
    String? bankname,
    bool? isPrimary,
  }) =>
      BankAccount(
        id: id ?? this.id,
        kontoinhaber: kontoinhaber ?? this.kontoinhaber,
        iban: iban ?? this.iban,
        bic: bic ?? this.bic,
        bankname: bankname ?? this.bankname,
        isPrimary: isPrimary ?? this.isPrimary,
      );
}
