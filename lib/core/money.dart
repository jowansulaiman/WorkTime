import 'package:intl/intl.dart';

/// Kleines, reines Wertobjekt für Geldbeträge in **ganzen Cent**.
///
/// Zentralisiert das de_DE-Formatieren/Parsen, das sonst über die neuen
/// HR-/Inventar-/Bestell-Screens verstreut kopiert ist. Modelle speichern
/// weiterhin rohe `int`-Cent (Money ist nur ein Rechen-/Format-Wrapper – die
/// Zwei-Serialisierungs-Regel bleibt unberührt). Vermeidet Float-Drift, weil
/// intern nie in Euro-`double` gerechnet wird.
class Money implements Comparable<Money> {
  const Money(this.cents);

  /// Aus einem Euro-Betrag (z.B. 12.34) → 1234 Cent (kaufmännisch gerundet).
  factory Money.fromEuros(num euros) => Money((euros * 100).round());

  /// Betrag in ganzen Cent.
  final int cents;

  static final NumberFormat _euroFormat =
      NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);

  static const Money zero = Money(0);

  /// Formatiert als „12,34 €" (de_DE).
  String format() => _euroFormat.format(cents / 100);

  @override
  String toString() => format();

  double get euros => cents / 100;

  bool get isZero => cents == 0;
  bool get isPositive => cents > 0;
  bool get isNegative => cents < 0;

  Money operator +(Money other) => Money(cents + other.cents);
  Money operator -(Money other) => Money(cents - other.cents);
  Money operator *(int factor) => Money(cents * factor);
  Money operator -() => Money(-cents);

  @override
  int compareTo(Money other) => cents.compareTo(other.cents);

  @override
  bool operator ==(Object other) => other is Money && other.cents == cents;

  @override
  int get hashCode => cents.hashCode;

  /// Parst eine deutsche Eingabe (`"1.234,56"`, `"12,34 €"`, `"12.34"`) in Cent.
  /// Gibt `null` bei leerer oder ungültiger Eingabe zurück.
  static int? parseCents(String input) {
    final trimmed = input.trim().replaceAll('€', '').trim();
    if (trimmed.isEmpty) return null;
    // Deutsches Format (wie der bestehende Inline-Parser): Punkt =
    // Tausendertrenner (entfernen), Komma = Dezimaltrenner. So ist „1.234"
    // = 1234 € und „12,34" = 12,34 € — beide konsistent zur restlichen App.
    final normalized = trimmed.replaceAll('.', '').replaceAll(',', '.');
    final euros = double.tryParse(normalized);
    if (euros == null) return null;
    return (euros * 100).round();
  }

  /// Wie [parseCents], liefert aber direkt ein [Money] (oder `null`).
  static Money? tryParse(String input) {
    final c = parseCents(input);
    return c == null ? null : Money(c);
  }

  /// Formatiert einen nullbaren Centbetrag; `null` → [placeholder].
  static String formatCents(int? cents, {String placeholder = '–'}) {
    if (cents == null) return placeholder;
    return _euroFormat.format(cents / 100);
  }
}
