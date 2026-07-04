import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;
import 'third_party_cash.dart';

/// **Kassen-Modul §3.1 — Zählprotokoll (Kassensturz).** Eine physische
/// Bargeld-Zählung je Standort. Unveränderlich (Rules: update/delete = false,
/// Audit-Charakter wie `stockMovements`) — Korrektur = neue Zählung.
///
/// **Cloud-only wie `PosReceipt`** (der Soll-Wert stammt aus den cloud-only
/// Kassenbelegen; ohne Cloud gibt es nichts zu verankern) — daher bewusst nur
/// die Firestore-Serialisierung (camelCase), keine snake_case/`toMap`-Form.
///
/// Blinde Zählung (Plan E2/§7.3): Mitarbeitende ohne Beleg-Leserecht erfassen
/// nur [countedCents]; [expectedCents]/[differenceCents] bleiben dann `null`
/// (die Rules erzwingen das) und die Differenz berechnet erst der Abschluss.
class CashCount {
  const CashCount({
    this.id,
    required this.orgId,
    required this.siteId,
    this.cashRegisterId,
    required this.businessDay,
    required this.countedAt,
    required this.countedCents,
    this.expectedCents,
    this.differenceCents,
    this.denominations,
    this.note,
    this.source = CashCount.sourceManual,
    this.countedByLabel,
    this.countedByUserId,
    this.kioskSessionId,
    this.thirdParty = const [],
    required this.createdByUid,
    this.createdAt,
  });

  /// Zählung am Tagesabschluss-Screen (admin/teamlead).
  static const String sourceManual = 'manual';

  /// Blinde Zählung über die Kiosk-Kachel am Laden-Tablet.
  static const String sourceKiosk = 'kiosk';

  /// Dem Server vorbehalten (E3, falls OktoPOS je einen Kassenlade-Endpunkt
  /// bereitstellt) — Rules verbieten diesen Wert vom Client.
  static const String sourceOktopos = 'oktopos';

  final String? id;
  final String orgId;
  final String siteId;

  /// Kassen-Nummer wie in `PosReceipt.cashRegisterId` (int, von der Kasse);
  /// v1 informativ — die Zählung gilt je Standort (Plan A5).
  final int? cashRegisterId;

  /// `YYYY-MM-DD` = lokales Gerätedatum von [countedAt] (bewusste Näherung —
  /// gezählt wird physisch im Laden; Plan §3.1).
  final String businessDay;

  final DateTime countedAt;

  /// Gezählter Bargeldbestand in Cent.
  final int countedCents;

  /// Soll-Bestand zum Zählzeitpunkt (Snapshot aus `computeCashState`);
  /// `null` bei blinder Zählung oder wenn nicht verankert.
  final int? expectedCents;

  /// `countedCents − expectedCents` (Snapshot, redundant für die Historie).
  final int? differenceCents;

  /// Optionale Stückelung: Nennwert (z. B. `"50.00"`) → Anzahl.
  final Map<String, int>? denominations;

  final String? note;

  /// [sourceManual] | [sourceKiosk] ([sourceOktopos] nur serverseitig).
  final String source;

  /// Anzeigename der zählenden Person aus der Kiosk-Session (am Tablet ist
  /// [createdByUid] das Geräte-Konto).
  final String? countedByLabel;

  /// **Harte Personen-Zuordnung (ZV-4.1):** echte `users`-uid der zählenden
  /// Person. App-Pfad = angemeldeter Nutzer (== [createdByUid]); Kiosk-Pfad =
  /// `kioskSessions/{sid}.employeeId` (server-gesetzt, nicht vom Client
  /// fälschbar). Anders als [countedByLabel] (nur Anzeige) ist dies der
  /// revisionsfeste Bezug für „welcher Mitarbeiter hat gezählt".
  final String? countedByUserId;

  final String? kioskSessionId;

  /// **Dritte-Hand-/Fremdgeld-Beträge (§8.7).** Getrennt von der eigenen Kasse
  /// erfasste Treuhandgelder (Lotto/Post/KVG …). Leer = kein Fremdgeld. Fließt
  /// NIE in [countedCents]/[expectedCents]/[differenceCents].
  final List<ThirdPartyAmount> thirdParty;

  /// Summe aller Fremdgeld-Beträge in Cent (0 wenn keine erfasst).
  int get thirdPartyTotalCents =>
      thirdParty.fold(0, (acc, e) => acc + e.amountCents);

  final String createdByUid;
  final DateTime? createdAt;

  factory CashCount.fromFirestore(String id, Map<String, dynamic> map) {
    final rawDenominations = map['denominations'];
    Map<String, int>? denominations;
    if (rawDenominations is Map) {
      denominations = <String, int>{};
      rawDenominations.forEach((key, value) {
        final count = parse.toInt(value);
        if (count != null) denominations![key.toString()] = count;
      });
    }
    return CashCount(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      siteId: (map['siteId'] ?? '').toString(),
      cashRegisterId: parse.toInt(map['cashRegisterId']),
      businessDay: (map['businessDay'] ?? '').toString(),
      countedAt:
          FirestoreDateParser.readDate(map['countedAt']) ?? DateTime(1970),
      countedCents: parse.toInt(map['countedCents']) ?? 0,
      expectedCents: parse.toInt(map['expectedCents']),
      differenceCents: parse.toInt(map['differenceCents']),
      denominations: denominations,
      // Tolerant parsen (nie hart casten): die Collection ist fuer alle
      // aktiven Nutzer beschreibbar — ein Fremdtyp darf den Lesepfad der
      // Leitung nicht brechen.
      note: map['note']?.toString(),
      source: (map['source'] ?? CashCount.sourceManual).toString(),
      countedByLabel: map['countedByLabel']?.toString(),
      countedByUserId: map['countedByUserId']?.toString(),
      kioskSessionId: map['kioskSessionId']?.toString(),
      thirdParty: _readThirdParty(map['thirdParty']),
      createdByUid: (map['createdByUid'] ?? '').toString(),
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
    );
  }

  /// Tolerant: fehlend/Fremdtyp → leere Liste (Alt-Zählungen ohne Fremdgeld
  /// bleiben gültig, kein Backfill nötig).
  static List<ThirdPartyAmount> _readThirdParty(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) =>
            ThirdPartyAmount.fromFirestore(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  /// Bewusst OHNE `clearX`-Flags (Abweichung von Kopplung #1): Zählungen sind
  /// create-only/unveränderlich — es gibt keinen fachlichen Grund, ein Feld
  /// nachträglich auf null zu leeren (Korrektur = neue Zählung).
  CashCount copyWith({
    String? id,
    String? orgId,
    String? siteId,
    int? cashRegisterId,
    String? businessDay,
    DateTime? countedAt,
    int? countedCents,
    int? expectedCents,
    int? differenceCents,
    Map<String, int>? denominations,
    String? note,
    String? source,
    String? countedByLabel,
    String? countedByUserId,
    String? kioskSessionId,
    List<ThirdPartyAmount>? thirdParty,
    String? createdByUid,
    DateTime? createdAt,
  }) {
    return CashCount(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      siteId: siteId ?? this.siteId,
      cashRegisterId: cashRegisterId ?? this.cashRegisterId,
      businessDay: businessDay ?? this.businessDay,
      countedAt: countedAt ?? this.countedAt,
      countedCents: countedCents ?? this.countedCents,
      expectedCents: expectedCents ?? this.expectedCents,
      differenceCents: differenceCents ?? this.differenceCents,
      denominations: denominations ?? this.denominations,
      note: note ?? this.note,
      source: source ?? this.source,
      countedByLabel: countedByLabel ?? this.countedByLabel,
      countedByUserId: countedByUserId ?? this.countedByUserId,
      kioskSessionId: kioskSessionId ?? this.kioskSessionId,
      thirdParty: thirdParty ?? this.thirdParty,
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toFirestoreMap() => {
        'orgId': orgId,
        'siteId': siteId,
        'cashRegisterId': cashRegisterId,
        'businessDay': businessDay,
        'countedAt': Timestamp.fromDate(countedAt),
        'countedCents': countedCents,
        'expectedCents': expectedCents,
        'differenceCents': differenceCents,
        'denominations': denominations,
        'note': note,
        'source': source,
        'countedByLabel': countedByLabel,
        'countedByUserId': countedByUserId,
        'kioskSessionId': kioskSessionId,
        'thirdParty': thirdParty.map((e) => e.toFirestoreMap()).toList(),
        'createdByUid': createdByUid,
        'createdAt': createdAt == null
            ? FieldValue.serverTimestamp()
            : Timestamp.fromDate(createdAt!),
      };
}
