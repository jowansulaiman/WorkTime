import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/contact.dart';
import 'package:worktime_app/services/export_service.dart';

void main() {
  group('ExportService.buildContactsCsv', () {
    test('beginnt mit UTF-8-BOM und enthält die Kopfzeile', () {
      final csv = ExportService.buildContactsCsv(
        contacts: const [
          Contact(
            orgId: 'o',
            name: 'Nord GmbH',
            type: ContactType.supplier,
            city: 'Kiel',
          ),
        ],
      );

      expect(csv.startsWith('﻿'), isTrue);
      expect(csv, contains('Name;Kategorie;'));
      expect(csv, contains('Nord GmbH;Lieferant;'));
    });

    test('maskiert Felder mit Semikolon korrekt (RFC 4180)', () {
      final csv = ExportService.buildContactsCsv(
        contacts: const [
          Contact(orgId: 'o', name: 'A; B', notes: 'x;y'),
        ],
      );

      expect(csv, contains('"A; B"'));
      expect(csv, contains('"x;y"'));
    });

    test('schreibt Standort und Favoriten-Status', () {
      final csv = ExportService.buildContactsCsv(
        contacts: const [
          Contact(
            orgId: 'o',
            name: 'Allgemeiner Kontakt',
            isFavorite: true,
          ),
          Contact(
            orgId: 'o',
            name: 'Laden-Kontakt',
            siteName: 'Tabak Börse',
          ),
        ],
      );

      expect(csv, contains('Allgemein'));
      expect(csv, contains('Tabak Börse'));
      // Favorit -> 'Ja' steht in der Zeile.
      final favLine =
          csv.split('\n').firstWhere((l) => l.startsWith('Allgemeiner'));
      expect(favLine.contains(';Ja;'), isTrue);
    });

    test('filterLabel erscheint im Export-Kopf', () {
      final csv = ExportService.buildContactsCsv(
        contacts: const [],
        filterLabel: 'Nur Kunden',
      );
      expect(csv, contains('Auswahl;Nur Kunden'));
    });
  });
}
