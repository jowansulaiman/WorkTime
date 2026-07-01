import 'package:flutter/painting.dart';

/// Tolerantes Parsen eines Hex-Farbstrings zu [Color].
///
/// `Shift.color` ist ein freies `String?` aus Firestore und kann durch Import,
/// Altdaten oder manuellen Firestore-Edit fehlerhaft sein. Das frühere direkte
/// `Color(int.parse(color.replaceFirst('#', '0xFF')))` wirft bei jedem
/// Nicht-`#RRGGBB`-Wert eine [FormatException] und kann so eine ganze
/// Board-/Kartenansicht crashen. Diese Hilfe gibt bei ungültiger Eingabe
/// stattdessen `null` zurück (bzw. [fallback], wenn gesetzt).
///
/// Akzeptiert `#RGB`, `#RRGGBB`, `#AARRGGBB` (mit/ohne führendes `#`, Groß-/
/// Kleinschreibung egal). Fehlt der Alphakanal, wird volldeckend (`FF`) ergänzt.
Color? tryParseHexColor(String? value, {Color? fallback}) {
  if (value == null) return fallback;
  var hex = value.trim();
  if (hex.isEmpty) return fallback;
  if (hex.startsWith('#')) hex = hex.substring(1);

  // Kurzform #RGB -> #RRGGBB
  if (hex.length == 3) {
    hex = hex.split('').map((c) => '$c$c').join();
  }
  if (hex.length == 6) {
    hex = 'FF$hex'; // volldeckend
  }
  if (hex.length != 8) return fallback;

  final parsed = int.tryParse(hex, radix: 16);
  if (parsed == null) return fallback;
  return Color(parsed);
}
