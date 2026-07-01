import '../models/product.dart';
import '../models/site_definition.dart';

/// **Kühlschrank-Nachfüll-Automatik — was fehlt im Verkaufs-Kühlschrank?**
///
/// Reine, deterministische Ableitung (wie `reorder_suggestion`/`sales_velocity`):
/// kein State, kein IO, kein `DateTime.now()`. Vergleicht je Kühlschrank-Artikel
/// den (geklemmten) Ist-Stand [Product.fridgeStockClamped] gegen das Soll
/// [Product.fridgeTargetStock] und meldet eine Lücke **nur**, wenn im Lager noch
/// Ware zum Nachfüllen liegt (`warehouseStock > 0`) — exakt die Anforderung
/// „noch im Lager vorhanden, bitte Kühlschrank nachfüllen".
enum FridgeShortfallSeverity {
  /// Kühlschrank ist leer (Ist <= 0) — am dringendsten.
  empty,

  /// Unter Soll, Lager reicht zum vollständigen Auffüllen.
  refill,

  /// Unter Soll, aber das Lager reicht nicht fürs volle Soll (Nachbestellen).
  warehouseLow,
}

/// Eine Kühlschrank-Lücke für genau einen Artikel.
class FridgeShortfall {
  const FridgeShortfall({
    required this.product,
    required this.deficit,
    required this.warehouseAvailable,
  });

  final Product product;

  /// Fehlmenge bis zum Kühlschrank-Soll (> 0).
  final int deficit;

  /// Im Lager verfügbare Menge (`currentStock − fridgeStock`), > 0.
  final int warehouseAvailable;

  /// Kann die Lücke vollständig aus dem Lager gedeckt werden?
  bool get coveredByWarehouse => warehouseAvailable >= deficit;

  FridgeShortfallSeverity get severity {
    if (product.fridgeStockClamped <= 0) return FridgeShortfallSeverity.empty;
    if (!coveredByWarehouse) return FridgeShortfallSeverity.warehouseLow;
    return FridgeShortfallSeverity.refill;
  }
}

/// Liefert die Kühlschrank-Lücken (absteigend nach Defizit), optional je Standort.
/// Nur aktive Artikel mit `inFridge == true` und [Product.fridgeNeedsRefill].
List<FridgeShortfall> computeFridgeShortfalls(
  Iterable<Product> products, {
  String? siteId,
}) {
  final result = <FridgeShortfall>[];
  for (final p in products) {
    if (!p.isActive) continue;
    if (siteId != null && p.siteId != siteId) continue;
    if (!p.fridgeNeedsRefill) continue;
    result.add(
      FridgeShortfall(
        product: p,
        deficit: p.fridgeDeficit,
        warehouseAvailable: p.warehouseStock,
      ),
    );
  }
  result.sort((a, b) => b.deficit.compareTo(a.deficit));
  return result;
}

/// Vorschlag für das Kühlschrank-Soll (`fridgeTargetStock`) aus der
/// Verkaufsgeschwindigkeit: Tagesabsatz × gewünschte Kühlschrank-Eindeckung
/// ([coverageDays], Default 2 Tage), aufgerundet, mindestens 1 für Artikel mit
/// Absatz. Ladenhüter (kein Absatz) → 0. Reiner Vorschlag, speichert nichts.
int suggestFridgeTarget(double dailyVelocity, {int coverageDays = 2}) {
  if (dailyVelocity <= 0) return 0;
  final target = (dailyVelocity * coverageDays).ceil();
  return target < 1 ? 1 : target;
}

/// `true`, wenn [now] im Ladenschluss-Vorlauf-Fenster eines Standorts liegt
/// (`[closeMin − leadMinutes, closeMin)`), abgeleitet aus den Öffnungszeiten
/// ([SiteDefinition.weekdayHours]) des heutigen Wochentags. Pure — `now` wird
/// injiziert (kein Wall-Clock-Footgun). Standorte **ohne** hinterlegte
/// Öffnungszeiten für heute → `false` (kein Tagesende-Trigger).
bool isNearClosing(SiteDefinition site, DateTime now, {int leadMinutes = 90}) {
  var closeMin = -1;
  for (final wh in site.weekdayHours) {
    if (wh.weekday != now.weekday) continue;
    for (final window in wh.windows) {
      if (window.endMinute > closeMin) closeMin = window.endMinute;
    }
  }
  if (closeMin < 0) return false;
  final nowMin = now.hour * 60 + now.minute;
  return nowMin >= closeMin - leadMinutes && nowMin < closeMin;
}
