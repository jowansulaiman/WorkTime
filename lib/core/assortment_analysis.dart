import '../models/pos_receipt.dart';
import '../models/product.dart';

/// **P2.1 — Rohertrag & ABC nach DECKUNGSBEITRAG** (nicht nach Umsatz). Der
/// Tabak-Kern: Zigaretten machen Riesenumsatz bei winziger Spanne — der Gewinn
/// kommt aus margenstarken Impulsartikeln. Diese Auswertung rankt das Sortiment
/// nach **Rohertrag** (Σ Menge × (realisierter Verkaufspreis − Einkaufspreis)),
/// damit margenstarke Artikel den Regalplatz verdienen.
///
/// **Pure / offline-testbar.** Eingaben:
/// - [PosReceipt]e (P0-Verkaufsfakten) — es zählen nur Umsatzbelege
///   (`isRevenue`, kein `training`/`cash`).
/// - Realisierter Stückpreis = `unitPriceCents − discountCents` (aus der Kasse).
/// - Einkaufspreis aus dem aktuellen [Product] (Belege tragen kein EK).
///
/// **Daten-Vorbehalt:** Die Geld-/Mengenfelder der Kassenbelege sind noch nicht
/// gegen die OktoPOS-Swagger verifiziert (P0). Die Rechnung ist korrekt für die
/// definierte Datenform; Vorzeichen von Erstattungs-Mengen vor produktiver
/// Nutzung prüfen. Fehlt ein EK, gilt der Artikel als **„unbewertet"** (nicht 0).
class AssortmentItem {
  const AssortmentItem({
    required this.productId,
    required this.name,
    required this.category,
    required this.quantitySold,
    required this.revenueCents,
    required this.contributionCents,
    required this.isValuated,
    required this.abcClass,
  });

  final String productId;
  final String? name;
  final String? category;
  final int quantitySold;

  /// Bekannter Umsatz (Σ Menge × realisierter Stückpreis) in Cent.
  final int revenueCents;

  /// Rohertrag/Deckungsbeitrag in Cent; `null`, wenn unbewertet (EK oder
  /// Verkaufspreis einer Zeile fehlt) — **nicht** als 0 interpretieren.
  final int? contributionCents;

  final bool isValuated;

  /// `'A'` | `'B'` | `'C'` (nach kumuliertem Deckungsbeitrag); `'-'` für
  /// unbewertete Artikel (nehmen an der ABC-Klassifizierung nicht teil).
  final String abcClass;
}

/// Gesamtergebnis der Sortimentsanalyse für einen Zeitraum/Standort.
class AssortmentAnalysis {
  const AssortmentAnalysis({
    required this.items,
    required this.totalRevenueCents,
    required this.totalContributionCents,
    required this.contributionByCategory,
    required this.unvaluatedCount,
  });

  /// Artikel, absteigend nach Deckungsbeitrag (bewertete zuerst), unbewertete
  /// danach absteigend nach Umsatz.
  final List<AssortmentItem> items;
  final int totalRevenueCents;

  /// Gesamt-Rohertrag (nur bewertete Artikel) in Cent.
  final int totalContributionCents;

  /// Deckungsbeitrag je Warengruppe (nur bewertete) in Cent.
  final Map<String, int> contributionByCategory;

  /// Anzahl Artikel ohne belastbaren Rohertrag (unbewertet).
  final int unvaluatedCount;
}

class _Acc {
  _Acc({this.name, this.category});
  String? name;
  String? category;
  int qty = 0;
  int qtyPriced = 0;
  int revenue = 0;
}

/// Berechnet die [AssortmentAnalysis] aus Belegen + Artikeln (für die EK-Preise).
///
/// ABC: bewertete Artikel absteigend nach Deckungsbeitrag, kumulierter Anteil am
/// Gesamt-Deckungsbeitrag → A bis [aThresholdPercent] %, B bis
/// [bThresholdPercent] %, sonst C.
AssortmentAnalysis computeAssortmentAnalysis({
  required List<PosReceipt> receipts,
  required List<Product> products,
  double aThresholdPercent = 80,
  double bThresholdPercent = 95,
}) {
  final ekById = <String, int?>{
    for (final p in products)
      if (p.id != null) p.id!: p.purchasePriceCents,
  };

  final acc = <String, _Acc>{};
  for (final r in receipts) {
    if (!r.isRevenue || r.training) continue;
    for (final line in r.lines) {
      final pid = line.productId;
      if (pid == null) continue;
      final qty = line.quantity;
      if (qty == 0) continue;
      final a = acc.putIfAbsent(
        pid,
        () => _Acc(name: line.name, category: line.category),
      );
      a.qty += qty;
      final unit = line.realizedUnitPriceCents;
      // Negativer realisierter Preis (Rabatt > VK, fehlerhafte Kassendaten) gilt
      // als unbekannter Preis -> Artikel „unbewertet", statt den Rohertrag zu
      // verfälschen.
      if (unit != null && unit >= 0) {
        a.qtyPriced += qty;
        a.revenue += qty * unit;
      }
    }
  }

  // Erst alle Items bilden (ohne ABC), dann bewertete für ABC sortieren.
  final draft = <String, _AssortmentDraft>{};
  for (final entry in acc.entries) {
    final pid = entry.key;
    final a = entry.value;
    final ek = ekById[pid];
    final fullyPriced = a.qtyPriced == a.qty;
    final isValuated = ek != null && fullyPriced;
    final contribution = isValuated ? a.revenue - ek * a.qty : null;
    draft[pid] = _AssortmentDraft(
      productId: pid,
      acc: a,
      contributionCents: contribution,
      isValuated: isValuated,
    );
  }

  // ABC über die bewerteten Artikel (Deckungsbeitrag desc).
  final valuatedDrafts = draft.values.where((d) => d.isValuated).toList()
    ..sort((x, y) {
      final c = y.contributionCents!.compareTo(x.contributionCents!);
      return c != 0 ? c : x.productId.compareTo(y.productId);
    });
  final totalContribution =
      valuatedDrafts.fold<int>(0, (s, d) => s + d.contributionCents!);
  // Klassifizierung über den KUMULIERTEN Anteil der HÖHER gerankten Artikel
  // („Artikel bis X %"): der erste/alleinige Deckungsbeitragsträger ist immer A,
  // erst wer jenseits der Schwelle beginnt, fällt nach B/C. Bei Gesamt-DB <= 0
  // (alles Nullmarge/Verlust) gibt es keine A-Träger -> alles C.
  final abcByProduct = <String, String>{};
  var running = 0;
  for (final d in valuatedDrafts) {
    if (totalContribution <= 0) {
      abcByProduct[d.productId] = 'C';
      continue;
    }
    final beforePct = running / totalContribution * 100;
    abcByProduct[d.productId] = beforePct < aThresholdPercent
        ? 'A'
        : (beforePct < bThresholdPercent ? 'B' : 'C');
    running += d.contributionCents!;
  }

  final contributionByCategory = <String, int>{};
  for (final d in valuatedDrafts) {
    final cat = (d.acc.category == null || d.acc.category!.trim().isEmpty)
        ? 'Ohne Warengruppe'
        : d.acc.category!;
    contributionByCategory[cat] =
        (contributionByCategory[cat] ?? 0) + d.contributionCents!;
  }

  final items = draft.values.map((d) {
    return AssortmentItem(
      productId: d.productId,
      name: d.acc.name,
      category: d.acc.category,
      quantitySold: d.acc.qty,
      revenueCents: d.acc.revenue,
      contributionCents: d.contributionCents,
      isValuated: d.isValuated,
      abcClass: d.isValuated ? abcByProduct[d.productId]! : '-',
    );
  }).toList()
    ..sort((x, y) {
      // Bewertete (nach DB desc) vor unbewerteten (nach Umsatz desc).
      if (x.isValuated != y.isValuated) return x.isValuated ? -1 : 1;
      if (x.isValuated) {
        final c = y.contributionCents!.compareTo(x.contributionCents!);
        return c != 0 ? c : x.productId.compareTo(y.productId);
      }
      final c = y.revenueCents.compareTo(x.revenueCents);
      return c != 0 ? c : x.productId.compareTo(y.productId);
    });

  return AssortmentAnalysis(
    items: items,
    totalRevenueCents: items.fold(0, (s, i) => s + i.revenueCents),
    totalContributionCents: totalContribution,
    contributionByCategory: contributionByCategory,
    unvaluatedCount: items.where((i) => !i.isValuated).length,
  );
}

class _AssortmentDraft {
  _AssortmentDraft({
    required this.productId,
    required this.acc,
    required this.contributionCents,
    required this.isValuated,
  });
  final String productId;
  final _Acc acc;
  final int? contributionCents;
  final bool isValuated;
}
