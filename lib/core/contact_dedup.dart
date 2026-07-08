import '../models/contact.dart';
import '../models/contact_details.dart';

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

  /// Führt zwei Kontakte zusammen (Portierung AllTecs `ContactMergeService`):
  /// [master] behält Id und seine gesetzten Werte; [victim] liefert nur die im
  /// Master fehlenden Felder. Eingebettete Listen werden dedupliziert vereinigt,
  /// Notizen konkateniert. `kind`/`type`/`status`/Flags bleiben vom Master.
  static Contact mergeContacts({
    required Contact master,
    required Contact victim,
  }) {
    String? pick(String? a, String? b) {
      final at = a?.trim();
      if (at != null && at.isNotEmpty) return a;
      return b;
    }

    return master.copyWith(
      alias: pick(master.alias, victim.alias),
      firstName: pick(master.firstName, victim.firstName),
      lastName: pick(master.lastName, victim.lastName),
      title: pick(master.title, victim.title),
      position: pick(master.position, victim.position),
      department: pick(master.department, victim.department),
      companyName: pick(master.companyName, victim.companyName),
      legalName: pick(master.legalName, victim.legalName),
      registrationNumber:
          pick(master.registrationNumber, victim.registrationNumber),
      contactPerson: pick(master.contactPerson, victim.contactPerson),
      email: pick(master.email, victim.email),
      phone: pick(master.phone, victim.phone),
      mobile: pick(master.mobile, victim.mobile),
      website: pick(master.website, victim.website),
      street: pick(master.street, victim.street),
      postalCode: pick(master.postalCode, victim.postalCode),
      city: pick(master.city, victim.city),
      taxId: pick(master.taxId, victim.taxId),
      customerNumber: pick(master.customerNumber, victim.customerNumber),
      debitorNumber: pick(master.debitorNumber, victim.debitorNumber),
      creditorNumber: pick(master.creditorNumber, victim.creditorNumber),
      avatarUrl: pick(master.avatarUrl, victim.avatarUrl),
      parentContactId: pick(master.parentContactId, victim.parentContactId),
      siteId: master.siteId ?? victim.siteId,
      siteName: master.siteName ?? victim.siteName,
      birthday: master.birthday ?? victim.birthday,
      companyAnniversary:
          master.companyAnniversary ?? victim.companyAnniversary,
      customerSince: master.customerSince ?? victim.customerSince,
      notes: _mergeNotes(master.notes, victim.notes),
      isFavorite: master.isFavorite || victim.isFavorite,
      // Listen dedupliziert vereinigen.
      tags: _unionBy<String>(master.tags, victim.tags, (t) => t.toLowerCase()),
      channels: _unionBy<CommunicationChannel>(
          master.channels, victim.channels, (c) => '${c.type.value}:${c.value}'),
      addresses: _unionBy<ContactAddress>(master.addresses, victim.addresses,
          (a) => '${a.street}|${a.zip}|${a.city}'),
      bankAccounts: _unionBy<BankAccount>(
          master.bankAccounts, victim.bankAccounts, (b) => b.iban),
      contactPersons: _unionBy<ContactPerson>(master.contactPersons,
          victim.contactPersons, (p) => p.personContactId),
      consents: _unionBy<ContactConsent>(
          master.consents, victim.consents, (c) => c.id),
      activities: [...master.activities, ...victim.activities]
          .take(50)
          .toList(growable: false),
    );
  }

  static List<T> _unionBy<T>(
      List<T> a, List<T> b, String Function(T) keyOf) {
    final seen = <String>{};
    final result = <T>[];
    for (final item in [...a, ...b]) {
      if (seen.add(keyOf(item))) result.add(item);
    }
    return result;
  }

  static String? _mergeNotes(String? a, String? b) {
    final at = a?.trim() ?? '';
    final bt = b?.trim() ?? '';
    if (at.isEmpty) return bt.isEmpty ? null : bt;
    if (bt.isEmpty || at == bt) return at;
    return '$at\n--- Zusammengeführt ---\n$bt';
  }
}
