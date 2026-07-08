import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/contact_dedup.dart';
import 'package:worktime_app/models/contact.dart';

void main() {
  const existing = [
    Contact(
      id: 'c1',
      orgId: 'o',
      name: 'Stammkunde Hansen',
      email: 'hansen@example.com',
      phone: '0431 123456',
      postalCode: '24105',
    ),
    Contact(
      id: 'c2',
      orgId: 'o',
      name: 'Nord-Tabak GmbH',
      email: 'info@nordtabak.de',
    ),
  ];

  group('ContactDedup', () {
    test('erkennt nahezu identischen Namen als Dublette', () {
      const candidate =
          Contact(orgId: 'o', name: 'Stammkunde Hanssen'); // ein Buchstabe mehr
      final dups = ContactDedup.findDuplicates(candidate, existing);
      expect(dups, isNotEmpty);
      expect(dups.first.contact.id, 'c1');
    });

    test('gleiche E-Mail hebt den Score deutlich', () {
      const candidate = Contact(
        orgId: 'o',
        name: 'H. Hansen',
        email: 'hansen@example.com',
      );
      final dups = ContactDedup.findDuplicates(candidate, existing);
      expect(dups, isNotEmpty);
      expect(dups.first.contact.id, 'c1');
      // Gleiche E-Mail hebt den Score trotz schwächerem Namen über die Schwelle.
      expect(dups.first.score, greaterThanOrEqualTo(0.6));
    });

    test('unähnlicher Kontakt liefert keine Dublette', () {
      const candidate = Contact(orgId: 'o', name: 'Vermieter Müller');
      expect(ContactDedup.findDuplicates(candidate, existing), isEmpty);
    });

    test('eigener Datensatz (gleiche id) wird übersprungen', () {
      const self = Contact(id: 'c1', orgId: 'o', name: 'Stammkunde Hansen');
      expect(ContactDedup.findDuplicates(self, existing), isEmpty);
    });
  });

  group('mergeContacts', () {
    test('Master behält Id + Werte, Victim füllt Lücken + vereinigt Listen', () {
      const master = Contact(
        id: 'm1',
        orgId: 'o',
        name: 'Nord-Tabak GmbH',
        email: 'info@nord.test',
        tags: ['A'],
      );
      const victim = Contact(
        id: 'v1',
        orgId: 'o',
        name: 'Nord Tabak',
        email: 'ignored@nord.test', // Master hat schon eine E-Mail
        phone: '0431 999', // fehlt im Master → übernommen
        tags: ['A', 'B'],
        notes: 'Notiz vom Duplikat',
      );

      final merged = ContactDedup.mergeContacts(master: master, victim: victim);
      expect(merged.id, 'm1'); // Master-Id bleibt
      expect(merged.email, 'info@nord.test'); // Master-Wert bleibt
      expect(merged.phone, '0431 999'); // aus Victim ergänzt
      expect(merged.tags, containsAll(['A', 'B'])); // vereinigt
      expect(merged.tags.length, 2); // dedupliziert
      expect(merged.notes, 'Notiz vom Duplikat'); // Master hatte keine
    });
  });
}
