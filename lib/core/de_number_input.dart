/// Verlustfreie Umrechnung zwischen gespeicherten Werten und deutschen
/// Eingabe-Strings (Dezimalkomma) für Editor-Felder.
///
/// Bewusst dependency-frei und rein testbar – damit die für Lohn-/SV-Sätze
/// load-bearing Prozent-Umrechnung gegen Float-Rauschen und de_DE-Komma
/// abgesichert ist.
library;

/// Wandelt einen als Bruchteil gespeicherten Satz (`0.146`) in eine
/// Prozent-Eingabe mit deutschem Komma (`"14,6"`) – ohne Float-Rauschen
/// (Rundung auf 4 Nachkommastellen der Prozentzahl).
String rateToPercentInput(double fraction) {
  final percent = (fraction * 100 * 10000).round() / 10000;
  var text = percent.toString();
  if (text.endsWith('.0')) text = text.substring(0, text.length - 2);
  return text.replaceAll('.', ',');
}

/// Parst eine Prozent-Eingabe (`"1,1"`/`"1,1 %"`) zurück in einen Bruchteil
/// (`0.011`); null bei leer/ungültig.
double? percentInputToRate(String raw) {
  final cleaned = raw.trim().replaceAll('%', '').replaceAll(',', '.').trim();
  if (cleaned.isEmpty) return null;
  final value = double.tryParse(cleaned);
  return value == null ? null : value / 100.0;
}

/// Formatiert Cent als €-Eingabe mit zwei Nachkommastellen und Komma
/// (`139000` → `"1390,00"`).
String centsToInput(int cents) =>
    (cents / 100).toStringAsFixed(2).replaceAll('.', ',');
