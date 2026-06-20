// Reine Hilfsfunktionen rund um Barcodes (EAN/UPC). Keine Abhaengigkeiten ->
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
  // EAN-8 = 8, UPC-A = 12, EAN-13 = 13. UPC-E (8) nutzt ein anderes Verfahren,
  // taucht aber nicht auf, weil der Scanner auf ean13/ean8/upcA beschraenkt ist.
  if (n != 8 && n != 12 && n != 13) return false;

  var sum = 0;
  // Datenziffern von rechts gewichten: 3, 1, 3, 1, ... (rechteste Datenziffer = 3).
  for (var i = 0; i < n - 1; i++) {
    final digit = code.codeUnitAt(n - 2 - i) - 0x30;
    sum += digit * (i.isEven ? 3 : 1);
  }
  final check = (10 - (sum % 10)) % 10;
  return check == (code.codeUnitAt(n - 1) - 0x30);
}

/// True, wenn [raw] die Laenge eines bekannten Standard-Barcodes hat
/// (EAN-13/EAN-8/UPC-A). Dient als weiche Vorpruefung; die strenge Pruefung ist
/// [isValidEanChecksum].
bool looksLikeEan(String raw) {
  final code = raw.trim();
  if (!_digitsOnly.hasMatch(code)) return false;
  final n = code.length;
  return n == 8 || n == 12 || n == 13;
}

final RegExp _digitsOnly = RegExp(r'^\d+$');
