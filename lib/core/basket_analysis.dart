import '../models/pos_receipt.dart';

/// **P4.2 — Cross-Sell / Warenkorb-Analyse.** Aggregiert aus den Belegzeilen
/// (`lines[]`), welche Artikel **häufig zusammen** über denselben Beleg gehen
/// („Feuerzeug + Tabak") — Grundlage für Platzierung/Cross-Sell. Es werden nur
/// **Aggregate** gebildet (keine Roh-Belege gehortet).
///
/// **Pure / offline-testbar.** Nur Umsatzbelege (`isRevenue`, kein training);
/// je Beleg zählt jeder Artikel einmal (distinct), Paare ungeordnet.
class ProductPair {
  const ProductPair({
    required this.productIdA,
    required this.productIdB,
    required this.nameA,
    required this.nameB,
    required this.together,
    required this.countA,
    required this.countB,
    required this.totalReceipts,
  });

  final String productIdA;
  final String productIdB;
  final String? nameA;
  final String? nameB;

  /// Belege, die BEIDE Artikel enthalten.
  final int together;

  /// Belege mit Artikel A bzw. B.
  final int countA;
  final int countB;
  final int totalReceipts;

  /// Konfidenz P(B|A) — Anteil der A-Käufe, die auch B enthalten.
  double get confidenceAtoB => countA == 0 ? 0 : together / countA;

  /// Lift > 1 = positive Assoziation (häufiger zusammen als per Zufall).
  double get lift {
    if (countA == 0 || countB == 0 || totalReceipts == 0) return 0;
    return together * totalReceipts / (countA * countB);
  }
}

class BasketAnalysis {
  const BasketAnalysis({required this.pairs, required this.receiptsConsidered});

  /// Top-Paare, absteigend nach gemeinsamer Häufigkeit.
  final List<ProductPair> pairs;
  final int receiptsConsidered;
}

/// Berechnet die [BasketAnalysis] aus Belegen.
///
/// - [minTogether]: Mindesthäufigkeit eines Paares (gegen Rauschen).
/// - [topN]: maximale Anzahl zurückgegebener Paare.
BasketAnalysis computeBasketAnalysis({
  required List<PosReceipt> receipts,
  int minTogether = 2,
  int topN = 25,
}) {
  final single = <String, int>{};
  final names = <String, String?>{};
  final pairCounts = <String, int>{};
  var considered = 0;

  for (final r in receipts) {
    if (!r.isRevenue || r.training) continue;
    final ids = <String>{};
    for (final line in r.lines) {
      final pid = line.productId;
      if (pid == null) continue;
      ids.add(pid);
      names.putIfAbsent(pid, () => line.name);
    }
    if (ids.isEmpty) continue;
    considered += 1;
    for (final id in ids) {
      single.update(id, (v) => v + 1, ifAbsent: () => 1);
    }
    final sorted = ids.toList()..sort();
    for (var i = 0; i < sorted.length; i++) {
      for (var j = i + 1; j < sorted.length; j++) {
        final key = '${sorted[i]}|${sorted[j]}';
        pairCounts.update(key, (v) => v + 1, ifAbsent: () => 1);
      }
    }
  }

  final pairs = <ProductPair>[];
  for (final entry in pairCounts.entries) {
    if (entry.value < minTogether) continue;
    final parts = entry.key.split('|');
    final a = parts[0];
    final b = parts[1];
    pairs.add(ProductPair(
      productIdA: a,
      productIdB: b,
      nameA: names[a],
      nameB: names[b],
      together: entry.value,
      countA: single[a] ?? 0,
      countB: single[b] ?? 0,
      totalReceipts: considered,
    ));
  }
  pairs.sort((x, y) {
    final c = y.together.compareTo(x.together);
    if (c != 0) return c;
    final l = y.lift.compareTo(x.lift);
    if (l != 0) return l;
    return ('${x.productIdA}|${x.productIdB}')
        .compareTo('${y.productIdA}|${y.productIdB}');
  });

  return BasketAnalysis(
    pairs: pairs.take(topN).toList(growable: false),
    receiptsConsidered: considered,
  );
}
