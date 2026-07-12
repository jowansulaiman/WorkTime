import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Ausgang eines Scan-Versuchs.
///
/// Serialisiert als snake_case-`value` (nicht der Dart-Name); `fromValue` hat
/// einen Default-Branch und wirft nie.
enum ScanOutcome {
  /// Genau ein aktiver Artikel gefunden.
  matched,

  /// Mehrere Artikel mit diesem Barcode (Auswahl noetig).
  multiMatch,

  /// Kein Artikel gefunden.
  notFound,

  /// Code an der Pruefziffer gescheitert (Fehl-/Teilscan oder beschaedigt).
  invalidChecksum;

  String get value {
    switch (this) {
      case ScanOutcome.matched:
        return 'matched';
      case ScanOutcome.multiMatch:
        return 'multi_match';
      case ScanOutcome.notFound:
        return 'not_found';
      case ScanOutcome.invalidChecksum:
        return 'invalid_checksum';
    }
  }

  String get label {
    switch (this) {
      case ScanOutcome.matched:
        return 'Treffer';
      case ScanOutcome.multiMatch:
        return 'Mehrfachtreffer';
      case ScanOutcome.notFound:
        return 'Nicht gefunden';
      case ScanOutcome.invalidChecksum:
        return 'Ungültige Prüfziffer';
    }
  }

  static ScanOutcome fromValue(String? value) {
    switch (value) {
      case 'matched':
        return ScanOutcome.matched;
      case 'multi_match':
        return ScanOutcome.multiMatch;
      case 'invalid_checksum':
        return ScanOutcome.invalidChecksum;
      case 'not_found':
      default:
        return ScanOutcome.notFound;
    }
  }
}

/// Ein einzelner Scan-Versuch fuer die Scan-Statistik/Fehleranalyse:
/// Welcher Code, mit welchem Ausgang, wie schnell, auf welchem Geraet.
///
/// Bewusst schlank und append-only (wie `StockMovement`) — die Auswertung
/// macht die pure Engine `lib/core/scan_stats.dart`. Geloggt wird
/// fire-and-forget (Scannen darf durch die Statistik NIE langsamer werden
/// oder fehlschlagen).
class ScanEvent {
  const ScanEvent({
    this.id,
    required this.orgId,
    this.siteId,
    required this.code,
    required this.outcome,
    this.mode,
    this.source,
    this.timeToHitMs,
    this.productId,
    this.platform,
    this.createdByUid,
    this.createdAt,
  });

  final String? id;
  final String orgId;
  final String? siteId;

  /// Der gescannte/eingegebene Code (roh, getrimmt).
  final String code;

  final ScanOutcome outcome;

  /// Scanner-Modus zum Zeitpunkt des Scans: `order`/`book`/`stocktake`.
  final String? mode;

  /// Herkunft des Codes: `camera` (Live-Scan), `manual` (Tastatur),
  /// `photo` (Standbild-Analyse). Viel `manual` = die Kamera versagt im Alltag.
  final String? source;

  /// Millisekunden vom Scanner-Start bzw. letzten Ergebnis bis zu diesem
  /// Treffer — „wie lange musste der Nutzer zielen".
  final int? timeToHitMs;

  /// Getroffener Artikel (nur bei [ScanOutcome.matched]).
  final String? productId;

  /// Plattform des Geraets (`android`/`ios`/`web`/`macos`/...), um
  /// Geraeteklassen mit Problemen zu erkennen.
  final String? platform;

  final String? createdByUid;
  final DateTime? createdAt;

  // Tolerante Parser (?.toString() statt Casts): ein einzelnes Doc mit
  // falschen Typen darf die org-weite Statistik nicht dauerhaft brechen —
  // scanEvents sind append-only und clientseitig nicht loesch-/korrigierbar.
  factory ScanEvent.fromFirestore(String id, Map<String, dynamic> map) {
    return ScanEvent(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      siteId: map['siteId']?.toString(),
      code: (map['code'] ?? '').toString(),
      outcome: ScanOutcome.fromValue(map['outcome']?.toString()),
      mode: map['mode']?.toString(),
      source: map['source']?.toString(),
      timeToHitMs: parse.toInt(map['timeToHitMs']),
      productId: map['productId']?.toString(),
      platform: map['platform']?.toString(),
      createdByUid: map['createdByUid']?.toString(),
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
    );
  }

  factory ScanEvent.fromMap(Map<String, dynamic> map) {
    return ScanEvent(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      siteId: map['site_id']?.toString(),
      code: (map['code'] ?? '').toString(),
      outcome: ScanOutcome.fromValue(map['outcome']?.toString()),
      mode: map['mode']?.toString(),
      source: map['source']?.toString(),
      timeToHitMs: parse.toInt(map['time_to_hit_ms']),
      productId: map['product_id']?.toString(),
      platform: map['platform']?.toString(),
      createdByUid: map['created_by_uid']?.toString(),
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'siteId': siteId,
      'code': code,
      'outcome': outcome.value,
      'mode': mode,
      'source': source,
      'timeToHitMs': timeToHitMs,
      'productId': productId,
      'platform': platform,
      'createdByUid': createdByUid,
      'createdAt': createdAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(createdAt!),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'site_id': siteId,
      'code': code,
      'outcome': outcome.value,
      'mode': mode,
      'source': source,
      'time_to_hit_ms': timeToHitMs,
      'product_id': productId,
      'platform': platform,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  ScanEvent copyWith({
    String? id,
    String? orgId,
    String? siteId,
    String? code,
    ScanOutcome? outcome,
    String? mode,
    String? source,
    int? timeToHitMs,
    String? productId,
    String? platform,
    String? createdByUid,
    DateTime? createdAt,
  }) {
    return ScanEvent(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      siteId: siteId ?? this.siteId,
      code: code ?? this.code,
      outcome: outcome ?? this.outcome,
      mode: mode ?? this.mode,
      source: source ?? this.source,
      timeToHitMs: timeToHitMs ?? this.timeToHitMs,
      productId: productId ?? this.productId,
      platform: platform ?? this.platform,
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
