import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Status einer Inventur-Zählsession.
///
/// snake_case-`value`, `fromValue` mit Default-Branch (wirft nie). Erlaubte
/// Übergänge (in Rules + Provider erzwungen): `open→completed`, `open→cancelled`.
enum InventoryCountStatus {
  open,
  completed,
  cancelled;

  String get value {
    switch (this) {
      case InventoryCountStatus.open:
        return 'open';
      case InventoryCountStatus.completed:
        return 'completed';
      case InventoryCountStatus.cancelled:
        return 'cancelled';
    }
  }

  String get label {
    switch (this) {
      case InventoryCountStatus.open:
        return 'Läuft';
      case InventoryCountStatus.completed:
        return 'Abgeschlossen';
      case InventoryCountStatus.cancelled:
        return 'Abgebrochen';
    }
  }

  bool get isOpen => this == InventoryCountStatus.open;

  static InventoryCountStatus fromValue(String? value) {
    switch (value) {
      case 'completed':
        return InventoryCountStatus.completed;
      case 'cancelled':
        return InventoryCountStatus.cancelled;
      case 'open':
      default:
        return InventoryCountStatus.open;
    }
  }
}

/// **WW-8 — ein append-only Zähl-Event** einer Session (Doc in der
/// Subcollection `inventoryCountSessions/{sessionId}/lines/{lineId}`).
///
/// Bewusst KEIN Last-Write-Wins: jede fremde Zählung eines Artikels ist ein
/// eigenes Event → die Zählhistorie bleibt erhalten (GoBD-freundlich) und
/// Mehrbenutzer-Konflikte werden sichtbar. Die eigene Korrektur aktualisiert
/// das EIGENE Event (kein Event-Spam beim Tippen).
class InventoryCountEvent {
  const InventoryCountEvent({
    this.id,
    required this.productId,
    required this.productName,
    required this.countedQuantity,
    required this.stockAtCount,
    required this.countedAt,
    required this.countedByUid,
    this.countedByLabel,
    this.bookedAt,
  });

  final String? id;
  final String productId;
  final String productName;

  /// Vom Zähler erfasste Ist-Menge.
  final int countedQuantity;

  /// Bestand des Artikels ZUM Zählzeitpunkt (für die Stale-Prüfung in WW-9:
  /// weicht `currentStock` beim Abschluss davon ab, lagen Bewegungen dazwischen).
  final int stockAtCount;

  final DateTime countedAt;
  final String countedByUid;
  final String? countedByLabel;

  /// Wann dieses (maßgebliche) Event beim Abschluss gebucht wurde (WW-9);
  /// `null` = noch nicht gebucht. Einziges Feld, das der Abschließende an einem
  /// fremd-gezählten Event setzen darf (Rules).
  final DateTime? bookedAt;

  bool get isBooked => bookedAt != null;

  factory InventoryCountEvent.fromFirestore(String id, Map<String, dynamic> map) {
    return InventoryCountEvent(
      id: id,
      productId: (map['productId'] ?? '').toString(),
      productName: (map['productName'] ?? '').toString(),
      countedQuantity: parse.toInt(map['countedQuantity']) ?? 0,
      stockAtCount: parse.toInt(map['stockAtCount']) ?? 0,
      countedAt: FirestoreDateParser.readDate(map['countedAt']) ?? DateTime(1970),
      countedByUid: (map['countedByUid'] ?? '').toString(),
      countedByLabel: map['countedByLabel'] as String?,
      bookedAt: FirestoreDateParser.readDate(map['bookedAt']),
    );
  }

  factory InventoryCountEvent.fromMap(Map<String, dynamic> map) {
    return InventoryCountEvent(
      id: map['id'] as String?,
      productId: (map['product_id'] ?? '').toString(),
      productName: (map['product_name'] ?? '').toString(),
      countedQuantity: parse.toInt(map['counted_quantity']) ?? 0,
      stockAtCount: parse.toInt(map['stock_at_count']) ?? 0,
      countedAt:
          FirestoreDateParser.readLocalDate(map['counted_at']) ?? DateTime(1970),
      countedByUid: (map['counted_by_uid'] ?? '').toString(),
      countedByLabel: map['counted_by_label'] as String?,
      bookedAt: FirestoreDateParser.readLocalDate(map['booked_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'productId': productId,
      'productName': productName,
      'countedQuantity': countedQuantity,
      'stockAtCount': stockAtCount,
      'countedAt': Timestamp.fromDate(countedAt),
      'countedByUid': countedByUid,
      'countedByLabel': countedByLabel,
      'bookedAt': bookedAt == null ? null : Timestamp.fromDate(bookedAt!),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'product_id': productId,
      'product_name': productName,
      'counted_quantity': countedQuantity,
      'stock_at_count': stockAtCount,
      'counted_at': countedAt.toIso8601String(),
      'counted_by_uid': countedByUid,
      'counted_by_label': countedByLabel,
      'booked_at': bookedAt?.toIso8601String(),
    };
  }

  InventoryCountEvent copyWith({
    String? id,
    String? productId,
    String? productName,
    int? countedQuantity,
    int? stockAtCount,
    DateTime? countedAt,
    String? countedByUid,
    String? countedByLabel,
    bool clearCountedByLabel = false,
    DateTime? bookedAt,
    bool clearBookedAt = false,
  }) {
    return InventoryCountEvent(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      countedQuantity: countedQuantity ?? this.countedQuantity,
      stockAtCount: stockAtCount ?? this.stockAtCount,
      countedAt: countedAt ?? this.countedAt,
      countedByUid: countedByUid ?? this.countedByUid,
      countedByLabel:
          clearCountedByLabel ? null : (countedByLabel ?? this.countedByLabel),
      bookedAt: clearBookedAt ? null : (bookedAt ?? this.bookedAt),
    );
  }
}

/// **WW-9 — eine eingefrorene Differenz-Zeile** der abgeschlossenen Inventur.
/// Enthält NUR echte Differenzen (Dokumentgrößen-Grenze); die vollständige
/// Zählliste lebt in den line-Docs.
class InventoryCountDiff {
  const InventoryCountDiff({
    required this.productId,
    required this.productName,
    required this.countedQuantity,
    required this.previousStock,
    this.unitCostCents,
    this.decision,
  });

  final String productId;
  final String productName;
  final int countedQuantity;
  final int previousStock;

  /// EK je Einheit zum Abschlusszeitpunkt (für die Bewertung), falls bekannt.
  final int? unitCostCents;

  /// Wie die Zeile behandelt wurde: `null`/`gezaehlt` = normal, `verrechnet` =
  /// Bewegungen seit Zählung verrechnet (WW-9 Stale-Auflösung).
  final String? decision;

  int get delta => countedQuantity - previousStock;

  /// Bewertete Differenz in Cent (Delta × EK), 0 ohne EK.
  int get valuationDeltaCents => (unitCostCents ?? 0) * delta;

  factory InventoryCountDiff.fromMap(Map<String, dynamic> map) {
    return InventoryCountDiff(
      productId: (map['productId'] ?? map['product_id'] ?? '').toString(),
      productName:
          (map['productName'] ?? map['product_name'] ?? '').toString(),
      countedQuantity:
          parse.toInt(map['countedQuantity'] ?? map['counted_quantity']) ?? 0,
      previousStock:
          parse.toInt(map['previousStock'] ?? map['previous_stock']) ?? 0,
      unitCostCents:
          parse.toInt(map['unitCostCents'] ?? map['unit_cost_cents']),
      decision: (map['decision']) as String?,
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'productId': productId,
      'productName': productName,
      'countedQuantity': countedQuantity,
      'previousStock': previousStock,
      'unitCostCents': unitCostCents,
      'decision': decision,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'product_id': productId,
      'product_name': productName,
      'counted_quantity': countedQuantity,
      'previous_stock': previousStock,
      'unit_cost_cents': unitCostCents,
      'decision': decision,
    };
  }
}

/// **WW-8 — eine persistente Inventur-Zählsession.** Ersetzt die frühere
/// In-Memory-Zählung: anlegen, unterbrechen, fortsetzen, mehrgerätefähig. Die
/// eigentliche Bestandsbuchung bleibt bei `recordStocktake` (WW-9-Abschluss).
///
/// Layout: `organizations/{orgId}/inventoryCountSessions/{sessionId}` +
/// Subcollection `lines/{lineId}` (die [InventoryCountEvent]s). Das Session-Doc
/// trägt Metadaten + Konflikt-Auflösungen + eingefrorene Diff-Summary.
class InventoryCountSession {
  const InventoryCountSession({
    this.id,
    required this.orgId,
    required this.siteId,
    required this.title,
    this.status = InventoryCountStatus.open,
    this.categoryFilter,
    required this.startedAt,
    required this.startedByUid,
    this.startedByLabel,
    this.completedAt,
    this.completedByUid,
    this.totalProducts = 0,
    this.countedProducts = 0,
    this.resolvedCounts = const {},
    this.diffSummary = const [],
  });

  final String? id;
  final String orgId;
  final String siteId;
  final String title;
  final InventoryCountStatus status;

  /// Optionaler Warengruppen-Filter (nur diese Kategorie wird gezählt).
  final String? categoryFilter;

  final DateTime startedAt;
  final String startedByUid;
  final String? startedByLabel;

  final DateTime? completedAt;
  final String? completedByUid;

  /// Sortiments-Umfang (für den Fortschrittsbalken).
  final int totalProducts;

  /// Wie viele Artikel bereits (mind. einmal) gezählt wurden.
  final int countedProducts;

  /// **WW-9 Konflikt-Auflösung:** productId → maßgebliche lineId. Bei einem
  /// Mehrbenutzer-Konflikt (abweichende Mengen) muss die maßgebliche Zählung
  /// hier festgehalten sein, bevor abgeschlossen werden darf.
  final Map<String, String> resolvedCounts;

  /// **WW-9:** eingefrorene Differenzliste zum Abschlusszeitpunkt.
  final List<InventoryCountDiff> diffSummary;

  bool get isOpen => status.isOpen;

  double get progress =>
      totalProducts <= 0 ? 0 : (countedProducts / totalProducts).clamp(0, 1);

  factory InventoryCountSession.fromFirestore(
      String id, Map<String, dynamic> map) {
    return InventoryCountSession(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      siteId: (map['siteId'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      status: InventoryCountStatus.fromValue(map['status'] as String?),
      categoryFilter: map['categoryFilter'] as String?,
      startedAt: FirestoreDateParser.readDate(map['startedAt']) ?? DateTime(1970),
      startedByUid: (map['startedByUid'] ?? '').toString(),
      startedByLabel: map['startedByLabel'] as String?,
      completedAt: FirestoreDateParser.readDate(map['completedAt']),
      completedByUid: map['completedByUid'] as String?,
      totalProducts: parse.toInt(map['totalProducts']) ?? 0,
      countedProducts: parse.toInt(map['countedProducts']) ?? 0,
      resolvedCounts: _resolvedFrom(map['resolvedCounts']),
      diffSummary: _diffsFrom(map['diffSummary']),
    );
  }

  factory InventoryCountSession.fromMap(Map<String, dynamic> map) {
    return InventoryCountSession(
      id: map['id'] as String?,
      orgId: (map['org_id'] ?? '').toString(),
      siteId: (map['site_id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      status: InventoryCountStatus.fromValue(map['status'] as String?),
      categoryFilter: map['category_filter'] as String?,
      startedAt:
          FirestoreDateParser.readLocalDate(map['started_at']) ?? DateTime(1970),
      startedByUid: (map['started_by_uid'] ?? '').toString(),
      startedByLabel: map['started_by_label'] as String?,
      completedAt: FirestoreDateParser.readLocalDate(map['completed_at']),
      completedByUid: map['completed_by_uid'] as String?,
      totalProducts: parse.toInt(map['total_products']) ?? 0,
      countedProducts: parse.toInt(map['counted_products']) ?? 0,
      resolvedCounts: _resolvedFrom(map['resolved_counts']),
      diffSummary: _diffsFrom(map['diff_summary']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'siteId': siteId,
      'title': title,
      'status': status.value,
      'categoryFilter': categoryFilter,
      'startedAt': Timestamp.fromDate(startedAt),
      'startedByUid': startedByUid,
      'startedByLabel': startedByLabel,
      'completedAt': completedAt == null ? null : Timestamp.fromDate(completedAt!),
      'completedByUid': completedByUid,
      'totalProducts': totalProducts,
      'countedProducts': countedProducts,
      'resolvedCounts': resolvedCounts,
      'diffSummary': diffSummary.map((d) => d.toFirestoreMap()).toList(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'site_id': siteId,
      'title': title,
      'status': status.value,
      'category_filter': categoryFilter,
      'started_at': startedAt.toIso8601String(),
      'started_by_uid': startedByUid,
      'started_by_label': startedByLabel,
      'completed_at': completedAt?.toIso8601String(),
      'completed_by_uid': completedByUid,
      'total_products': totalProducts,
      'counted_products': countedProducts,
      'resolved_counts': resolvedCounts,
      'diff_summary': diffSummary.map((d) => d.toMap()).toList(),
    };
  }

  InventoryCountSession copyWith({
    String? id,
    String? orgId,
    String? siteId,
    String? title,
    InventoryCountStatus? status,
    String? categoryFilter,
    bool clearCategoryFilter = false,
    DateTime? startedAt,
    String? startedByUid,
    String? startedByLabel,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    String? completedByUid,
    bool clearCompletedByUid = false,
    int? totalProducts,
    int? countedProducts,
    Map<String, String>? resolvedCounts,
    List<InventoryCountDiff>? diffSummary,
  }) {
    return InventoryCountSession(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      siteId: siteId ?? this.siteId,
      title: title ?? this.title,
      status: status ?? this.status,
      categoryFilter: clearCategoryFilter
          ? null
          : (categoryFilter ?? this.categoryFilter),
      startedAt: startedAt ?? this.startedAt,
      startedByUid: startedByUid ?? this.startedByUid,
      startedByLabel: startedByLabel ?? this.startedByLabel,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      completedByUid:
          clearCompletedByUid ? null : (completedByUid ?? this.completedByUid),
      totalProducts: totalProducts ?? this.totalProducts,
      countedProducts: countedProducts ?? this.countedProducts,
      resolvedCounts: resolvedCounts ?? this.resolvedCounts,
      diffSummary: diffSummary ?? this.diffSummary,
    );
  }

  static Map<String, String> _resolvedFrom(dynamic value) {
    if (value is! Map) return const {};
    final result = <String, String>{};
    value.forEach((key, val) {
      if (key is String && val is String) result[key] = val;
    });
    return result;
  }

  static List<InventoryCountDiff> _diffsFrom(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((m) => InventoryCountDiff.fromMap(m.cast<String, dynamic>()))
        .toList(growable: false);
  }
}
