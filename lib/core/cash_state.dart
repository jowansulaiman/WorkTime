import '../models/cash_count.dart';
import '../models/pos_receipt.dart';

/// **Kassen-Modul §4.2 — rechnerischer Kassenzustand (Soll-Bargeld).**
///
/// ```
/// Anker = letzte Zählung (countedCents, countedAt)
/// Soll  = Anker
///       + Σ Bar-Zahlungen aus isRevenue-Belegen seit Anker (Refunds negativ, A8)
///       + Σ cash-Belege seit Anker (Ein-/Auszahlungen)
/// ```
///
/// **Pure / offline-testbar.** training-Belege sind in ALLEN Summanden
/// ausgeschlossen (gleiches Verhalten wie `computeDailyClosings`). Ohne
/// Zählung im geladenen Fenster gibt es bewusst KEIN gerechnetes Soll
/// ([CashState.verankert] = false, UI zeigt „Bitte Kasse zählen") — kein
/// read-teurer „ab Datenbeginn"-Fantasiewert (Plan §4.2).
///
/// **Daten-Vorbehalt (A2/A8):** Welche Zahlart-Tokens die Kasse wirklich
/// liefert und ob Beträge vorzeichenbehaftet ankommen, ist erst nach der
/// Swagger-/Echt-Validierung sicher — Ergebnis ist ein Richtwert.

/// Tolerantes Token-Set für Bargeld-Zahlarten (kleingeschrieben verglichen).
const Set<String> barPaymentTokens = {'bar', 'cash', 'bargeld'};

/// Ergebnis von [computeCashState].
class CashState {
  const CashState({
    required this.sollCents,
    required this.verankert,
    required this.letzteZaehlung,
    required this.tagesBareinnahmenCents,
    required this.tagesCashBewegungCents,
  });

  /// Rechnerischer Bargeld-Sollbestand in Cent; `null` wenn nicht verankert.
  final int? sollCents;

  /// `true`, sobald eine Zählung als Anker vorliegt.
  final bool verankert;

  final CashCount? letzteZaehlung;

  /// Bar-Einnahmen des betrachteten Geschäftstags (unabhängig vom Anker).
  final int tagesBareinnahmenCents;

  /// Ein-/Auszahlungen (`type='cash'`) des betrachteten Geschäftstags.
  final int tagesCashBewegungCents;
}

/// Berechnet den Kassenzustand eines Standorts aus Belegen + Zählungen des
/// geladenen Fensters (Aufrufer fenstert, z. B. 62 Tage — §6).
///
/// [businessDay] = betrachteter Geschäftstag für die Tages-Werte
/// (`YYYY-MM-DD`); ohne Angabe der jüngste Tag der übergebenen Belege.
CashState computeCashState({
  required List<PosReceipt> receipts,
  required List<CashCount> counts,
  required String siteId,
  String? businessDay,
}) {
  final siteReceipts = receipts
      .where((r) => r.siteId == siteId && !r.training)
      .toList(growable: false);

  CashCount? anchor;
  for (final count in counts) {
    if (count.siteId != siteId) continue;
    if (anchor == null || count.countedAt.isAfter(anchor.countedAt)) {
      anchor = count;
    }
  }

  String? day = businessDay;
  if (day == null) {
    for (final r in siteReceipts) {
      final d = _receiptDay(r);
      if (d == null) continue;
      if (day == null || d.compareTo(day) > 0) day = d;
    }
  }

  var tagesBar = 0;
  var tagesCash = 0;
  var seitAnkerBar = 0;
  var seitAnkerCash = 0;

  for (final r in siteReceipts) {
    final receiptDay = _receiptDay(r);
    final type = (r.type ?? '').toLowerCase();
    final isCash = type == 'cash';
    final bar = r.isRevenue ? _barAmountCents(r) : 0;

    if (day != null && receiptDay == day) {
      if (isCash) {
        tagesCash += r.grossCents ?? 0;
      } else {
        tagesBar += bar;
      }
    }

    if (anchor != null && _isAfterAnchor(r, receiptDay, anchor)) {
      if (isCash) {
        seitAnkerCash += r.grossCents ?? 0;
      } else {
        seitAnkerBar += bar;
      }
    }
  }

  return CashState(
    sollCents: anchor == null
        ? null
        : anchor.countedCents + seitAnkerBar + seitAnkerCash,
    verankert: anchor != null,
    letzteZaehlung: anchor,
    tagesBareinnahmenCents: tagesBar,
    tagesCashBewegungCents: tagesCash,
  );
}

int _barAmountCents(PosReceipt receipt) {
  var sum = 0;
  for (final payment in receipt.payments) {
    final method = payment.method?.trim().toLowerCase();
    if (method == null || !barPaymentTokens.contains(method)) continue;
    sum += payment.amountCents ?? 0;
  }
  return sum;
}

/// „Seit Anker": bevorzugt der exakte Zeitstempel; Belege ohne
/// `transactionDate` zählen nur, wenn ihr Geschäftstag NACH dem Zähl-Tag liegt
/// (gleicher Tag ist ohne Uhrzeit nicht zuordenbar → bewusst ausgelassen).
bool _isAfterAnchor(PosReceipt receipt, String? receiptDay, CashCount anchor) {
  final tx = receipt.transactionDate;
  if (tx != null) return tx.isAfter(anchor.countedAt);
  if (receiptDay == null) return false;
  return receiptDay.compareTo(anchor.businessDay) > 0;
}

String? _receiptDay(PosReceipt receipt) {
  final raw = receipt.businessDay;
  if (raw != null && raw.trim().isNotEmpty) return raw.trim();
  final tx = receipt.transactionDate;
  if (tx == null) return null;
  return '${tx.year}-${tx.month.toString().padLeft(2, '0')}-'
      '${tx.day.toString().padLeft(2, '0')}';
}
