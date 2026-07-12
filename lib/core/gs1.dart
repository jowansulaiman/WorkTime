// Pure Auswertung von GS1-Inhalten aus QR-/DataMatrix-/Code-128-Scans.
// Keine Abhaengigkeiten, kein now()/IO -> deterministisch offline testbar.
//
// Unterstuetzte Eingabeformen:
// 1. GS1-Element-String mit FNC1/GS-Trennern, wie ihn Scanner roh liefern
//    (optional mit Symbology-Prefix "]C1"/"]d2"/"]Q3"/"]e0"),
//    z. B. "01040123456789011726123110CHARGE7".
// 2. Menschenlesbare Klammer-Notation "(01)04012345678901(17)261231(10)CHARGE7".
// 3. GS1 Digital Link URLs, z. B.
//    https://id.gs1.org/01/04012345678901/10/CHARGE7?17=261231
// 4. Nackte GTIN (8/12/13/14 Ziffern) — z. B. ein QR, der nur eine EAN traegt.
//
// Ausgewertet werden die fuer den Laden relevanten AIs:
// 01/02 (GTIN), 17/15 (MHD bzw. Mindesthaltbarkeit), 10 (Charge), 30/37 (Menge).
// Alle weiteren erkannten AIs landen unausgewertet in [Gs1ScanData.elements].

/// Ergebnis einer GS1-Auswertung. [elements] enthaelt alle erkannten AIs
/// (Schluessel = AI-Nummer als String), die benannten Getter sind die fachlich
/// interpretierten Felder.
class Gs1ScanData {
  const Gs1ScanData({required this.elements});

  final Map<String, String> elements;

  /// GTIN aus AI 01 (Handelseinheit) bzw. 02 (enthaltene Einheit) — roh wie
  /// codiert (meist 14-stellig). Fuer den Artikel-Lookup mit
  /// `gtinLookupVariants` normalisieren.
  String? get gtin => elements['01'] ?? elements['02'];

  /// MHD: AI 17 (Verfallsdatum) bevorzugt, sonst AI 15 (Mindesthaltbarkeit).
  DateTime? get expiryDate {
    final raw = elements['17'] ?? elements['15'];
    return raw == null ? null : _parseGs1Date(raw);
  }

  /// Chargen-/Losnummer (AI 10).
  String? get lot => elements['10'];

  /// Stueckzahl (AI 30 bzw. 37), falls codiert.
  int? get quantity {
    final raw = elements['30'] ?? elements['37'];
    return raw == null ? null : int.tryParse(raw);
  }

  bool get hasGtin => gtin != null && gtin!.isNotEmpty;
}

/// Parst [raw] als GS1-Inhalt. Liefert `null`, wenn der Inhalt keinem der
/// unterstuetzten GS1-Formate entspricht (dann ist es ein gewoehnlicher
/// QR-Inhalt wie eine URL oder Freitext).
Gs1ScanData? parseGs1(String raw) {
  var input = raw.trim();
  if (input.isEmpty) return null;

  // Symbology-Identifier (ISO/IEC 15424) abstreifen: "]C1" (GS1-128),
  // "]e0" (GS1 DataBar), "]d2" (GS1 DataMatrix), "]Q3" (GS1 QR).
  if (input.length > 3 && input.startsWith(']')) {
    input = input.substring(3);
  }

  if (input.startsWith('http://') || input.startsWith('https://')) {
    return _parseDigitalLink(input);
  }
  if (input.startsWith('(')) {
    return _parseBracketNotation(input);
  }
  if (_digitsOnly.hasMatch(input)) {
    final n = input.length;
    if (n == 8 || n == 12 || n == 13) {
      // Nackte GTIN im QR: als AI 01 interpretieren.
      return Gs1ScanData(elements: {'01': input});
    }
    // Rein numerische Nicht-Standard-Laengen koennten auch proprietaere
    // Hauscodes sein (z.B. "0123456..."), die zufaellig mit einer AI-Nummer
    // beginnen. Nur wenn der GS1-Parse die Eingabe VOLLSTAENDIG und sauber
    // konsumiert, gilt sie als GS1 — sonst bleibt sie ein gewoehnlicher Code
    // (der Aufrufer macht dann den normalen Lookup mit dem Original).
    return _parseElementString(input, requireFullConsumption: true);
  }
  return _parseElementString(input);
}

// --- Element-String (FNC1/GS-Trenner) --------------------------------------

/// AIs mit fester Datenlaenge (AI -> Anzahl Datenzeichen). Alle uebrigen
/// bekannten AIs gelten als variabel (bis GS-Trenner bzw. Ende).
const Map<String, int> _fixedLengthAis = {
  '00': 18, '01': 14, '02': 14,
  '11': 6, '12': 6, '13': 6, '15': 6, '16': 6, '17': 6,
  '20': 2,
};

/// Variable AIs, die wir kennen (2-/3-stellig). 4-stellige Mess-AIs (31xx-36xx)
/// werden per Muster erkannt (fix 6 Datenziffern).
const Set<String> _variableAis = {
  '10', '21', '22', '30', '37',
  '90', '91', '92', '93', '94', '95', '96', '97', '98', '99',
  '240', '241', '242', '250', '251', '253', '254',
};

const String _gs = '\u001D';

Gs1ScanData? _parseElementString(
  String input, {
  bool requireFullConsumption = false,
}) {
  final elements = <String, String>{};
  var fullyConsumed = true;
  var i = 0;
  while (i < input.length) {
    // Fuehrende GS-Trenner (nach variablen Feldern) ueberspringen.
    while (i < input.length && input[i] == _gs) {
      i++;
    }
    if (i >= input.length) break;

    String? ai;
    int? fixedLength;
    // 4-stellige Mess-AIs 31xx–36xx: 4. Stelle = Nachkomma-Indikator, 6 Ziffern.
    if (i + 4 <= input.length &&
        _measureAi.hasMatch(input.substring(i, i + 4))) {
      ai = input.substring(i, i + 4);
      fixedLength = 6;
    } else if (i + 3 <= input.length &&
        _variableAis.contains(input.substring(i, i + 3))) {
      ai = input.substring(i, i + 3);
    } else if (i + 2 <= input.length) {
      final two = input.substring(i, i + 2);
      if (_fixedLengthAis.containsKey(two)) {
        ai = two;
        fixedLength = _fixedLengthAis[two];
      } else if (_variableAis.contains(two)) {
        ai = two;
      }
    }
    if (ai == null) {
      // Unbekannter AI: Rest nicht mehr zuordenbar -> mit dem bisher
      // Erkannten aufhoeren (tolerant gegenueber Teil-Beschaedigung).
      fullyConsumed = false;
      break;
    }
    i += ai.length;

    final String value;
    if (fixedLength != null) {
      if (i + fixedLength > input.length) {
        // Abgeschnittener Fix-Wert: NICHT als (gekuerzten) Wert uebernehmen —
        // das wuerde z.B. aus einem 7-stelligen Hauscode "0123456" ein
        // Phantom-GTIN "23456" machen. Rest verwerfen, Parse beenden.
        fullyConsumed = false;
        break;
      } else {
        value = input.substring(i, i + fixedLength);
        i += fixedLength;
      }
    } else {
      final gsIndex = input.indexOf(_gs, i);
      final end = gsIndex == -1 ? input.length : gsIndex;
      value = input.substring(i, end);
      i = end;
    }
    if (value.isNotEmpty) {
      elements.putIfAbsent(ai, () => value);
    }
  }
  if (requireFullConsumption && !fullyConsumed) return null;
  return elements.isEmpty ? null : Gs1ScanData(elements: elements);
}

// --- Klammer-Notation -------------------------------------------------------

Gs1ScanData? _parseBracketNotation(String input) {
  final elements = <String, String>{};
  for (final match in _bracketElement.allMatches(input)) {
    final ai = match.group(1)!;
    final value = match.group(2)!.trim();
    if (value.isNotEmpty) {
      elements.putIfAbsent(ai, () => value);
    }
  }
  return elements.isEmpty ? null : Gs1ScanData(elements: elements);
}

// --- GS1 Digital Link -------------------------------------------------------

Gs1ScanData? _parseDigitalLink(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  final elements = <String, String>{};

  // Pfad: .../01/{gtin}[/{ai}/{wert}]* — erst ab dem 01-Segment auswerten
  // (davor koennen beliebige Pfad-Teile liegen, z. B. Sprach-Prefixe).
  final gtinIndex = segments.indexOf('01');
  if (gtinIndex == -1 || gtinIndex + 1 >= segments.length) return null;
  final gtin = segments[gtinIndex + 1];
  if (!_digitsOnly.hasMatch(gtin) || gtin.length < 8 || gtin.length > 14) {
    return null;
  }
  elements['01'] = gtin;
  for (var i = gtinIndex + 2; i + 1 < segments.length; i += 2) {
    final ai = segments[i];
    if (!_numericAi.hasMatch(ai)) break;
    elements.putIfAbsent(ai, () => Uri.decodeComponent(segments[i + 1]));
  }
  // Query-Parameter mit numerischem Schluessel sind ebenfalls AIs (z. B. ?17=…).
  uri.queryParameters.forEach((key, value) {
    if (_numericAi.hasMatch(key) && value.isNotEmpty) {
      elements.putIfAbsent(key, () => value);
    }
  });
  return Gs1ScanData(elements: elements);
}

// --- Datums-Hilfe -----------------------------------------------------------

/// GS1-Datum YYMMDD -> DateTime (lokale Mittagszeit, DST-robust wie
/// ProductBatch). `DD == 00` bedeutet laut GS1 „Ende des Monats".
/// Jahrhundert-Regel vereinfacht: 00–89 -> 20xx, 90–99 -> 19xx (MHDs liegen in
/// der nahen Zukunft; deterministisch ohne now()).
DateTime? _parseGs1Date(String raw) {
  final value = raw.trim();
  if (value.length != 6 || !_digitsOnly.hasMatch(value)) return null;
  final yy = int.parse(value.substring(0, 2));
  final month = int.parse(value.substring(2, 4));
  final day = int.parse(value.substring(4, 6));
  if (month < 1 || month > 12 || day > 31) return null;
  final year = yy >= 90 ? 1900 + yy : 2000 + yy;
  if (day == 0) {
    // Letzter Tag des Monats: Tag 0 des Folgemonats.
    return DateTime(year, month + 1, 0, 12);
  }
  final date = DateTime(year, month, day, 12);
  // DateTime normalisiert Ueberlaeufe (31.02. -> 03.03.) — das waere ein
  // stiller Fehlwert, also ablehnen.
  if (date.month != month || date.day != day) return null;
  return date;
}

final RegExp _digitsOnly = RegExp(r'^\d+$');
final RegExp _numericAi = RegExp(r'^\d{2,4}$');
final RegExp _measureAi = RegExp(r'^3[1-6]\d\d$');
final RegExp _bracketElement = RegExp(r'\((\d{2,4})\)([^(]*)');
