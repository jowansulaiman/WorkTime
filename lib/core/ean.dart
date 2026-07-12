// Reine Hilfsfunktionen rund um Barcodes (EAN/UPC/GTIN). Keine Abhaengigkeiten ->
// leicht testbar und ueberall einsetzbar.

/// Prueft die Pruefziffer eines EAN-13, EAN-8 oder UPC-A Codes.
///
/// Fehl-/Teilscans liefern oft Codes mit falscher Pruefziffer; damit lassen sie
/// sich vor dem Datenbank-Lookup abfangen. Andere Laengen (z. B. proprietaere
/// Hauscodes) werden bewusst NICHT als ungueltig gewertet — siehe [looksLikeEan].
bool isValidEanChecksum(String raw) {
  final code = raw.trim();
  if (!_digitsOnly.hasMatch(code)) return false;
  final n = code.length;
  // EAN-8 = 8, UPC-A = 12, EAN-13 = 13, GTIN-14 = 14. UPC-E (ebenfalls 8) nutzt
  // ein anderes Verfahren — siehe [upcEToUpcA]/[isPlausibleRetailCode].
  if (n != 8 && n != 12 && n != 13 && n != 14) return false;
  return _checkDigit(code.substring(0, n - 1)) ==
      code.codeUnitAt(n - 1) - 0x30;
}

/// True, wenn [raw] die Laenge eines bekannten Standard-Barcodes hat
/// (EAN-8/UPC-E, UPC-A, EAN-13, GTIN-14/ITF-14). Dient als weiche Vorpruefung;
/// die strenge Pruefung ist [isPlausibleRetailCode].
bool looksLikeEan(String raw) {
  final code = raw.trim();
  if (!_digitsOnly.hasMatch(code)) return false;
  final n = code.length;
  return n == 8 || n == 12 || n == 13 || n == 14;
}

/// Strenges Annahme-Gate fuer gescannte Codes: Standard-Laengen muessen eine
/// gueltige Pruefziffer tragen — als EAN/UPC-A/GTIN-14 ODER als UPC-E (dessen
/// Pruefziffer nur ueber die UPC-A-Expansion pruefbar ist). Nicht-Standard-
/// Laengen (Hauscodes) passieren unveraendert.
bool isPlausibleRetailCode(String raw) {
  final code = raw.trim();
  if (!looksLikeEan(code)) return true; // Hauscode o.ae. -> durchlassen
  if (isValidEanChecksum(code)) return true;
  return code.length == 8 && upcEToUpcA(code) != null;
}

/// Expandiert einen 8-stelligen UPC-E-Code (Nummernsystem 0/1) zum
/// 12-stelligen UPC-A. Liefert `null`, wenn [raw] kein gueltiger UPC-E ist
/// (falsche Laenge/Zeichen, Nummernsystem >1 oder Pruefziffer der Expansion
/// stimmt nicht).
///
/// Hintergrund: gerade KLEINE Import-Artikel tragen UPC-E; gespeichert sind
/// Artikel aber als UPC-A/EAN-13. Ohne Expansion findet der Lookup nichts.
String? upcEToUpcA(String raw) {
  final code = raw.trim();
  if (code.length != 8 || !_digitsOnly.hasMatch(code)) return null;
  final system = code.codeUnitAt(0) - 0x30;
  if (system > 1) return null; // UPC-E existiert nur im Nummernsystem 0/1.
  final d = code.substring(1, 7); // 6 Datenziffern
  final check = code[7];
  final last = d.codeUnitAt(5) - 0x30;
  final String body; // 10 Ziffern zwischen Nummernsystem und Pruefziffer
  if (last <= 2) {
    body = '${d[0]}${d[1]}${d[5]}0000${d[2]}${d[3]}${d[4]}';
  } else if (last == 3) {
    body = '${d[0]}${d[1]}${d[2]}00000${d[3]}${d[4]}';
  } else if (last == 4) {
    body = '${d[0]}${d[1]}${d[2]}${d[3]}00000${d[4]}';
  } else {
    body = '${d[0]}${d[1]}${d[2]}${d[3]}${d[4]}0000${d[5]}';
  }
  final upcA = '$system$body$check';
  return isValidEanChecksum(upcA) ? upcA : null;
}

/// Liefert die in einer GTIN-14 (ITF-14-Umkarton, GS1 AI 01/02) enthaltene
/// GTIN-13: Ziffern 2–13 + neu berechnete Pruefziffer. `null` bei ungueltiger
/// Eingabe (Laenge/Zeichen/Pruefziffer). Die fuehrende Verpackungs-Kennziffer
/// aendert die Pruefziffer — einfaches Abschneiden waere falsch.
String? gtin14ToGtin13(String raw) {
  final code = raw.trim();
  if (code.length != 14 || !_digitsOnly.hasMatch(code)) return null;
  if (!isValidEanChecksum(code)) return null;
  final payload = code.substring(1, 13);
  return '$payload${_checkDigit(payload)}';
}

/// Kandidaten-Codes fuer den Barcode-Lookup: der Code selbst plus tolerante
/// Normalisierungs-Varianten.
///
/// - UPC-A(12) <-> EAN-13(0+12): `mobile_scanner` liefert auf iOS UPC-A teils
///   als 13-stellige EAN-13 mit fuehrender Null (GitHub #1653).
/// - UPC-E(8): wird zum UPC-A expandiert (+ dessen EAN-13-Variante), damit ein
///   als UPC-A/EAN-13 gespeicherter Artikel gefunden wird.
/// - GTIN-14 (ITF-14/GS1): enthaltene GTIN-13 (+ deren Varianten), damit der
///   Umkarton-Scan den als EAN-13 gespeicherten Artikel trifft.
///
/// Diese Funktion macht NUR die Suche tolerant — gespeicherte Werte bleiben
/// unveraendert. Nicht-numerische oder andere Laengen (Hauscodes) werden
/// unveraendert als einziger Kandidat zurueckgegeben.
Set<String> gtinLookupVariants(String raw) {
  final code = raw.trim();
  final variants = <String>{code};
  if (code.isEmpty || !_digitsOnly.hasMatch(code)) return variants;
  if (code.length == 13 && code.startsWith('0')) {
    variants.add(code.substring(1)); // EAN-13 mit fuehrender Null -> UPC-A (12)
  } else if (code.length == 12) {
    variants.add('0$code'); // UPC-A (12) -> EAN-13 mit fuehrender Null
  } else if (code.length == 8) {
    final upcA = upcEToUpcA(code);
    if (upcA != null) {
      variants
        ..add(upcA)
        ..add('0$upcA');
    }
  } else if (code.length == 14) {
    final gtin13 = gtin14ToGtin13(code);
    if (gtin13 != null) {
      variants.addAll(gtinLookupVariants(gtin13));
    }
  }
  return variants;
}

/// Kanonische Vergleichsform eines Barcodes: wo moeglich die EAN-13-Schreibweise
/// (UPC-A -> 0+12, UPC-E -> expandiert, GTIN-14 -> enthaltene GTIN-13), sonst
/// der getrimmte Code selbst. Zwei Schreibweisen desselben Codes (z.B. UPC-A
/// mit/ohne fuehrende Null) landen so auf demselben Schluessel — Basis der
/// Duplikat-Erkennung. EAN-8 bleibt EAN-8 (eigenstaendiger Nummernkreis, KEINE
/// Kurzform von EAN-13).
String canonicalGtin(String raw) {
  final code = raw.trim();
  if (code.isEmpty || !_digitsOnly.hasMatch(code)) return code;
  switch (code.length) {
    case 12:
      return '0$code';
    case 8:
      final upcA = upcEToUpcA(code);
      // Gueltige EAN-8 bevorzugt als EAN-8 lassen; nur ein reiner UPC-E
      // (EAN-8-Pruefziffer passt nicht) wird expandiert.
      if (!isValidEanChecksum(code) && upcA != null) return '0$upcA';
      return code;
    case 14:
      return gtin14ToGtin13(code) ?? code;
    default:
      return code;
  }
}

/// Pruefziffer (Modulo-10, Gewichte 3/1 von rechts) ueber die Datenziffern
/// [digits] (OHNE Pruefziffer). Gemeinsame Basis fuer EAN-8/UPC-A/EAN-13/GTIN-14.
int _checkDigit(String digits) {
  var sum = 0;
  final n = digits.length;
  for (var i = 0; i < n; i++) {
    final digit = digits.codeUnitAt(n - 1 - i) - 0x30;
    sum += digit * (i.isEven ? 3 : 1);
  }
  return (10 - (sum % 10)) % 10;
}

final RegExp _digitsOnly = RegExp(r'^\d+$');
