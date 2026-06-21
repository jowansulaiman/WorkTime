import '../models/contact.dart';

/// Ein möglicher Dubletten-Kandidat mit Ähnlichkeits-Score (0..1).
class DuplicateCandidate {
  const DuplicateCandidate({required this.contact, required this.score});

  final Contact contact;
  final double score;

  bool get isHighConfidence => score >= 0.8;
}

/// Reine, dependency-freie Dubletten-Erkennung für Kontakte.
///
/// Adaptiert aus AllTecs `ContactMergeService` auf WorkTimes **flaches**
/// [Contact]-Modell: gewichtete Ähnlichkeit aus Name (Bigramm-Jaccard),
/// E-Mail, Telefon und PLZ. Läuft in-memory über die bereits geladene
/// Kontaktliste – keine zusätzlichen Firestore-Reads.
class ContactDedup {
  const ContactDedup._();

  /// Mögliche Dubletten zu [target] aus [all], Score >= [threshold],
  /// absteigend sortiert. Der Kontakt selbst (gleiche id) wird übersprungen.
  static List<DuplicateCandidate> findDuplicates(
    Contact target,
    List<Contact> all, {
    double threshold = 0.6,
  }) {
    final candidates = <DuplicateCandidate>[];
    for (final other in all) {
      if (other.id != null && other.id == target.id) continue;
      final score = similarity(target, other);
      if (score >= threshold) {
        candidates.add(DuplicateCandidate(contact: other, score: score));
      }
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates;
  }

  /// Gewichtete Ähnlichkeit zweier Kontakte (0..1). Fehlende Felder werden aus
  /// der Gewichtung herausgerechnet (Normalisierung), damit ein Treffer nicht
  /// allein durch viele leere Felder verwässert.
  static double similarity(Contact a, Contact b) {
    var score = 0.0;
    var weights = 0.0;

    // Name (45 %) – Bigramm-Jaccard.
    final nameScore =
        _stringSim(a.name.trim().toLowerCase(), b.name.trim().toLowerCase());
    score += nameScore * 0.45;
    weights += 0.45;

    // E-Mail (30 %) – exakt.
    final aEmail = a.email?.trim().toLowerCase();
    final bEmail = b.email?.trim().toLowerCase();
    if (aEmail != null && aEmail.isNotEmpty && bEmail != null && bEmail.isNotEmpty) {
      score += (aEmail == bEmail ? 1.0 : 0.0) * 0.30;
      weights += 0.30;
    }

    // Telefon (15 %) – normalisiert (ohne Trennzeichen).
    final aPhone = _normalizePhone(a);
    final bPhone = _normalizePhone(b);
    if (aPhone != null && bPhone != null) {
      score += (aPhone == bPhone ? 1.0 : 0.0) * 0.15;
      weights += 0.15;
    }

    // PLZ (10 %).
    final aZip = a.postalCode?.trim();
    final bZip = b.postalCode?.trim();
    if (aZip != null && aZip.isNotEmpty && aZip == bZip) {
      score += 0.10;
      weights += 0.10;
    }

    return weights > 0 ? score / weights : 0;
  }

  /// Bigramm-Jaccard zweier Strings (0..1).
  static double _stringSim(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;
    final aBigrams = _bigrams(a);
    final bBigrams = _bigrams(b);
    final intersection = aBigrams.intersection(bBigrams).length;
    final union = aBigrams.union(bBigrams).length;
    return union == 0 ? 0 : intersection / union;
  }

  static Set<String> _bigrams(String s) {
    if (s.length < 2) return {s};
    return {for (var i = 0; i < s.length - 1; i++) s.substring(i, i + 2)};
  }

  /// Bevorzugte Telefonnummer (Festnetz, sonst Mobil), ohne Trennzeichen.
  static String? _normalizePhone(Contact c) {
    final raw = c.primaryPhone;
    if (raw == null || raw.trim().isEmpty) return null;
    return raw.replaceAll(RegExp(r'[\s\-/()]+'), '');
  }
}
