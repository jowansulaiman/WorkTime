import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/daily_closing.dart';
import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;
import 'cash_count.dart';
import 'pos_receipt.dart';
import 'third_party_cash.dart';

/// **Kassen-Modul §3.2 — festgeschriebener Kassenabschluss.** Persistierter
/// Snapshot des berechneten Tagesabschlusses ([DailyClosing]) PLUS Zählung.
/// Doc-ID **deterministisch** `{businessDay}-{siteId}` unter
/// `organizations/{orgId}/cashClosings` ⇒ genau ein Abschluss je Tag+Standort.
///
/// Der Snapshot macht den Abschluss unabhängig von späteren Re-Syncs der
/// Belege. **Festschreibung mit genau einer Ausnahme:** alle fachlichen Felder
/// sind unveränderlich (Rules: delete = false), nur [bookedToFinance] darf per
/// feldbeschränktem Update `false→true` kippen (admin-only, §9) — das ist
/// zugleich die teamlead-lesbare Gebucht-Anzeige, da `journalEntries`
/// admin-only sind.
///
/// **Cloud-only wie `PosReceipt`** — daher bewusst nur die
/// Firestore-Serialisierung (camelCase), keine snake_case/`toMap`-Form.
class CashClosing {
  const CashClosing({
    this.id,
    required this.orgId,
    required this.siteId,
    required this.businessDay,
    this.salesCount = 0,
    this.refundCount = 0,
    this.revenueGrossCents = 0,
    this.taxes = const [],
    this.paymentsByMethod = const {},
    this.cashMovementCents = 0,
    this.cashExpectedCents,
    this.cashCountedCents,
    this.cashCountId,
    this.cashDifferenceCents,
    this.thirdParty = const [],
    this.bookedToFinance = false,
    required this.closedByUid,
    this.closedAt,
    this.note,
  });

  /// Deterministische Doc-ID: genau ein Abschluss je Tag+Standort.
  static String docId(String businessDay, String siteId) =>
      '$businessDay-$siteId';

  final String? id;
  final String orgId;
  final String siteId;
  final String businessDay;

  final int salesCount;
  final int refundCount;
  final int revenueGrossCents;

  /// USt-Aufschlüsselung je Satz (Snapshot), gleiche Form wie am Beleg.
  final List<ReceiptTax> taxes;

  final Map<String, int> paymentsByMethod;
  final int cashMovementCents;

  /// Soll-Bargeld zum Abschluss-Zeitpunkt (aus `computeCashState`); `null`
  /// wenn nicht verankert.
  final int? cashExpectedCents;

  /// Übernommene Zählung ([CashCount]); `null` = ohne Zählung abgeschlossen.
  final int? cashCountedCents;
  final String? cashCountId;

  /// `gezählt − Soll`; `null`, wenn eine Seite fehlt.
  final int? cashDifferenceCents;

  /// **Dritte-Hand-/Fremdgeld-Beträge (§8.7).** Snapshot der beim Zählen
  /// erfassten Treuhandgelder. **Additiv & getrennt:** beeinflusst
  /// [cashDifferenceCents] und alle Umsatz-/Rohertrags-Aggregate NICHT.
  final List<ThirdPartyAmount> thirdParty;

  /// Summe aller Fremdgeld-Beträge in Cent.
  int get thirdPartyTotalCents =>
      thirdParty.fold(0, (acc, e) => acc + e.amountCents);

  /// Gesamtes physisches Geld in der Lade = eigenes Kassen-Ist + Fremdgeld
  /// (reiner Anzeigewert, wird nirgends gebucht).
  int get grandTotalCashCents => (cashCountedCents ?? 0) + thirdPartyTotalCents;

  /// Einziges nachträglich änderbares Feld (`false→true`, admin-only):
  /// Journal-Buchung über den bestehenden `postDailyClosing`-Fluss erfolgt.
  final bool bookedToFinance;

  final String closedByUid;
  final DateTime? closedAt;
  final String? note;

  /// §4.3 — baut den festzuschreibenden Snapshot aus dem berechneten
  /// [DailyClosing] + optionaler Zählung. [cashExpectedCents] ist das
  /// Soll-Bargeld zum Abschluss-Zeitpunkt (`CashState.sollCents`).
  factory CashClosing.fromDailyClosing({
    required DailyClosing closing,
    required String orgId,
    required String closedByUid,
    int? cashExpectedCents,
    CashCount? zaehlung,
    List<ThirdPartyAmount> thirdParty = const [],
    String? note,
  }) {
    final counted = zaehlung?.countedCents;
    return CashClosing(
      orgId: orgId,
      siteId: closing.siteId,
      businessDay: closing.businessDay,
      salesCount: closing.salesCount,
      refundCount: closing.refundCount,
      revenueGrossCents: closing.revenueGrossCents,
      taxes: [
        for (final bucket in closing.taxBuckets)
          ReceiptTax(
            ratePercent: bucket.ratePercent,
            netCents: bucket.netCents,
            taxCents: bucket.taxCents,
            grossCents: bucket.grossCents,
          ),
      ],
      paymentsByMethod: closing.paymentsByMethod,
      cashMovementCents: closing.cashMovementCents,
      cashExpectedCents: cashExpectedCents,
      cashCountedCents: counted,
      cashCountId: zaehlung?.id,
      cashDifferenceCents: (counted != null && cashExpectedCents != null)
          ? counted - cashExpectedCents
          : null,
      // Fremdgeld getrennt übernehmen — beeinflusst die Kassendifferenz NICHT.
      thirdParty:
          thirdParty.isNotEmpty ? thirdParty : (zaehlung?.thirdParty ?? const []),
      closedByUid: closedByUid,
      note: note,
    );
  }

  /// Bewusst OHNE `clearX`-Flags (Abweichung von Kopplung #1): Abschlüsse sind
  /// festgeschrieben — nach dem Create ändert sich nur noch `bookedToFinance`
  /// (per feldbeschränktem Update), nie ein Feld zurück auf null.
  CashClosing copyWith({
    String? id,
    String? orgId,
    String? siteId,
    String? businessDay,
    int? salesCount,
    int? refundCount,
    int? revenueGrossCents,
    List<ReceiptTax>? taxes,
    Map<String, int>? paymentsByMethod,
    int? cashMovementCents,
    int? cashExpectedCents,
    int? cashCountedCents,
    String? cashCountId,
    int? cashDifferenceCents,
    List<ThirdPartyAmount>? thirdParty,
    bool? bookedToFinance,
    String? closedByUid,
    DateTime? closedAt,
    String? note,
  }) {
    return CashClosing(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      siteId: siteId ?? this.siteId,
      businessDay: businessDay ?? this.businessDay,
      salesCount: salesCount ?? this.salesCount,
      refundCount: refundCount ?? this.refundCount,
      revenueGrossCents: revenueGrossCents ?? this.revenueGrossCents,
      taxes: taxes ?? this.taxes,
      paymentsByMethod: paymentsByMethod ?? this.paymentsByMethod,
      cashMovementCents: cashMovementCents ?? this.cashMovementCents,
      cashExpectedCents: cashExpectedCents ?? this.cashExpectedCents,
      cashCountedCents: cashCountedCents ?? this.cashCountedCents,
      cashCountId: cashCountId ?? this.cashCountId,
      cashDifferenceCents: cashDifferenceCents ?? this.cashDifferenceCents,
      thirdParty: thirdParty ?? this.thirdParty,
      bookedToFinance: bookedToFinance ?? this.bookedToFinance,
      closedByUid: closedByUid ?? this.closedByUid,
      closedAt: closedAt ?? this.closedAt,
      note: note ?? this.note,
    );
  }

  factory CashClosing.fromFirestore(String id, Map<String, dynamic> map) {
    final rawPayments = map['paymentsByMethod'];
    final payments = <String, int>{};
    if (rawPayments is Map) {
      rawPayments.forEach((key, value) {
        final cents = parse.toInt(value);
        if (cents != null) payments[key.toString()] = cents;
      });
    }
    return CashClosing(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      siteId: (map['siteId'] ?? '').toString(),
      businessDay: (map['businessDay'] ?? '').toString(),
      salesCount: parse.toInt(map['salesCount']) ?? 0,
      refundCount: parse.toInt(map['refundCount']) ?? 0,
      revenueGrossCents: parse.toInt(map['revenueGrossCents']) ?? 0,
      taxes: _readTaxes(map['taxes']),
      paymentsByMethod: payments,
      cashMovementCents: parse.toInt(map['cashMovementCents']) ?? 0,
      cashExpectedCents: parse.toInt(map['cashExpectedCents']),
      cashCountedCents: parse.toInt(map['cashCountedCents']),
      cashCountId: map['cashCountId']?.toString(),
      cashDifferenceCents: parse.toInt(map['cashDifferenceCents']),
      thirdParty: _readThirdParty(map['thirdParty']),
      bookedToFinance: parse.toBool(map['bookedToFinance']) ?? false,
      closedByUid: (map['closedByUid'] ?? '').toString(),
      closedAt: FirestoreDateParser.readDate(map['closedAt']),
      note: map['note']?.toString(),
    );
  }

  Map<String, dynamic> toFirestoreMap() => {
        'orgId': orgId,
        'siteId': siteId,
        'businessDay': businessDay,
        'salesCount': salesCount,
        'refundCount': refundCount,
        'revenueGrossCents': revenueGrossCents,
        'taxes': taxes.map((t) => t.toFirestoreMap()).toList(),
        'paymentsByMethod': paymentsByMethod,
        'cashMovementCents': cashMovementCents,
        'cashExpectedCents': cashExpectedCents,
        'cashCountedCents': cashCountedCents,
        'cashCountId': cashCountId,
        'cashDifferenceCents': cashDifferenceCents,
        'thirdParty': thirdParty.map((e) => e.toFirestoreMap()).toList(),
        'bookedToFinance': bookedToFinance,
        'closedByUid': closedByUid,
        'closedAt': closedAt == null
            ? FieldValue.serverTimestamp()
            : Timestamp.fromDate(closedAt!),
        'note': note,
      };

  static List<ReceiptTax> _readTaxes(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => ReceiptTax.fromFirestore(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  /// Tolerant: fehlend/Fremdtyp → leere Liste (Alt-Abschlüsse ohne Fremdgeld
  /// bleiben gültig, kein Backfill nötig).
  static List<ThirdPartyAmount> _readThirdParty(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) =>
            ThirdPartyAmount.fromFirestore(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }
}
