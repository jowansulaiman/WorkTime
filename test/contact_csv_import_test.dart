import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/contact_csv_import.dart';
import 'package:worktime_app/models/contact.dart';

void main() {
  group('ContactCsvImport', () {
    test('parst Kopfzeile spaltenunabhängig + Kategorie + Quotes', () {
      const csv = '\u{FEFF}Kategorie;Name;E-Mail;Telefon;PLZ;Ort\n'
          'Lieferant;"Nord-Tabak, GmbH";info@nord.de;0431 1;24105;Kiel\n'
          'Kunde;Hansen;;;;\n';
      final result = ContactCsvImport.parse(csv, orgId: 'org-1');

      expect(result.contacts, hasLength(2));
      final first = result.contacts.first;
      expect(first.name, 'Nord-Tabak, GmbH'); // Komma im quotierten Feld bleibt
      expect(first.type, ContactType.supplier);
      expect(first.email, 'info@nord.de');
      expect(first.postalCode, '24105');
      expect(first.city, 'Kiel');
      expect(result.contacts[1].type, ContactType.customer);
      expect(result.errors, isEmpty);
    });

    test('sammelt Fehler pro Zeile ohne Namen', () {
      const csv = 'Name;E-Mail\n;leer@x.de\nEcht;echt@x.de\n';
      final result = ContactCsvImport.parse(csv, orgId: 'o');
      expect(result.contacts, hasLength(1));
      expect(result.contacts.single.name, 'Echt');
      expect(result.errors, hasLength(1));
      expect(result.errors.first, contains('Zeile 2'));
    });

    test('quotiertes Feld mit Zeilenumbruch bleibt EIN Datensatz', () {
      const csv = 'Name;Notiz\n'
          '"Hansen";"Zeile 1\nZeile 2"\n'
          'Müller;ok\n';
      final result = ContactCsvImport.parse(csv, orgId: 'o');
      expect(result.contacts, hasLength(2));
      expect(result.contacts.first.name, 'Hansen');
      expect(result.contacts.first.notes, 'Zeile 1\nZeile 2');
      expect(result.contacts[1].name, 'Müller');
      expect(result.errors, isEmpty);
    });

    test('fehlende Name-Spalte -> klarer Fehler, kein Import', () {
      const csv = 'Vorname;Ort\nMax;Kiel\n';
      final result = ContactCsvImport.parse(csv, orgId: 'o');
      expect(result.contacts, isEmpty);
      expect(result.errors.single, contains('Name'));
    });
  });
}
