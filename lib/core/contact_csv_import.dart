import '../models/contact.dart';
import '../models/contact_details.dart';

/// Ergebnis eines CSV-Imports: erfolgreich geparste Kontakte + Fehler je Zeile.
class ContactCsvImportResult {
  const ContactCsvImportResult({required this.contacts, required this.errors});

  final List<Contact> contacts;
  final List<String> errors;

  bool get hasContacts => contacts.isNotEmpty;
}

/// Reiner, dependency-freier CSV-Import für Kontakte (Gegenstück zum Export).
///
/// Adaptiert aus AllTecs `ContactCsvService.import`: deutsches Excel-Format
/// (`;`-Trenner, UTF-8-BOM tolerant, Felder optional in `"`), Spalten werden
/// über die **Kopfzeile per Name** zugeordnet (Reihenfolge egal), Fehler werden
/// pro Zeile gesammelt statt den ganzen Import abzubrechen.
class ContactCsvImport {
  const ContactCsvImport._();

  static ContactCsvImportResult parse(String csv, {required String orgId}) {
    final contacts = <Contact>[];
    final errors = <String>[];

    var text = csv;
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      text = text.substring(1); // BOM entfernen
    }
    // Quote-bewusst in Records zerlegen (Zeilenumbrüche INNERHALB von "…" sind
    // Teil des Feldes, nicht Datensatz-Trenner). Leere Records werden verworfen.
    final records = _parseRecords(text)
        .where((cells) => cells.any((c) => c.trim().isNotEmpty))
        .toList();
    if (records.isEmpty) {
      return const ContactCsvImportResult(
        contacts: [],
        errors: ['Die Datei ist leer.'],
      );
    }

    final header =
        records.first.map((h) => h.trim().toLowerCase()).toList();
    int col(List<String> names) {
      for (final name in names) {
        final index = header.indexOf(name);
        if (index >= 0) return index;
      }
      return -1;
    }

    final iName = col(['name', 'kontakt', 'firma', 'kunde']);
    if (iName < 0) {
      return const ContactCsvImportResult(
        contacts: [],
        errors: ['Spalte „Name" fehlt in der Kopfzeile.'],
      );
    }
    final iType = col(['kategorie', 'art', 'typ']);
    final iPerson = col(['ansprechpartner', 'kontaktperson']);
    final iEmail = col(['e-mail', 'email', 'mail']);
    final iPhone = col(['telefon', 'tel', 'festnetz']);
    final iMobile = col(['mobil', 'handy']);
    final iWebsite = col(['website', 'web', 'homepage']);
    final iStreet = col(['straße', 'strasse', 'street', 'adresse']);
    final iZip = col(['plz', 'postleitzahl']);
    final iCity = col(['ort', 'stadt', 'city']);
    final iTax = col(['ust-id', 'ustid', 'steuernummer', 'steuernr']);
    final iCustNo = col(['kundennummer', 'kundennr']);
    final iNotes = col(['notiz', 'notizen', 'bemerkung']);
    final iTags = col(['tags', 'schlagworte', 'schlagwörter']);
    // Person/Firma-Split + Nummern (M11).
    final iKind = col(['art']);
    final iFirst = col(['vorname']);
    final iLast = col(['nachname']);
    final iCompany = col(['firmenname']);
    final iDebitor = col(['debitor-nr.', 'debitoren-nr.', 'debitor', 'debitorennr']);
    final iCreditor =
        col(['kreditor-nr.', 'kreditoren-nr.', 'kreditor', 'kreditorennr']);

    for (var r = 1; r < records.length; r++) {
      final cells = records[r];
      String? at(int index) =>
          (index >= 0 && index < cells.length) ? cells[index].trim() : null;

      final name = at(iName);
      if (name == null || name.isEmpty) {
        errors.add('Zeile ${r + 1}: kein Name – übersprungen.');
        continue;
      }
      final tags = (at(iTags) ?? '')
          .split(RegExp(r'[;,]'))
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList(growable: false);

      contacts.add(
        Contact(
          orgId: orgId,
          name: name,
          type: _type(at(iType)),
          kind: _kind(at(iKind)),
          firstName: _nullIfEmpty(at(iFirst)),
          lastName: _nullIfEmpty(at(iLast)),
          companyName: _nullIfEmpty(at(iCompany)),
          debitorNumber: _nullIfEmpty(at(iDebitor)),
          creditorNumber: _nullIfEmpty(at(iCreditor)),
          contactPerson: _nullIfEmpty(at(iPerson)),
          email: _nullIfEmpty(at(iEmail)),
          phone: _nullIfEmpty(at(iPhone)),
          mobile: _nullIfEmpty(at(iMobile)),
          website: _nullIfEmpty(at(iWebsite)),
          street: _nullIfEmpty(at(iStreet)),
          postalCode: _nullIfEmpty(at(iZip)),
          city: _nullIfEmpty(at(iCity)),
          taxId: _nullIfEmpty(at(iTax)),
          customerNumber: _nullIfEmpty(at(iCustNo)),
          notes: _nullIfEmpty(at(iNotes)),
          tags: tags,
        ),
      );
    }

    return ContactCsvImportResult(contacts: contacts, errors: errors);
  }

  /// Ordnet einen „Art"-Text (Person/Firma) einem [ContactKind] zu. Default
  /// [ContactKind.company] (analog Editor / Modell).
  static ContactKind _kind(String? raw) {
    final lower = raw?.trim().toLowerCase() ?? '';
    if (lower == 'person' || lower == ContactKind.person.value) {
      return ContactKind.person;
    }
    return ContactKind.company;
  }

  /// Ordnet einen Kategorie-Text einer [ContactType] zu (über Wert oder Label,
  /// Default [ContactType.customer]).
  static ContactType _type(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return ContactType.customer;
    final lower = value.toLowerCase();
    for (final type in ContactType.values) {
      if (type.value == lower ||
          type.label.toLowerCase() == lower ||
          type.shortLabel.toLowerCase() == lower) {
        return type;
      }
    }
    return ContactType.customer;
  }

  /// Zerlegt den gesamten CSV-Text in Datensätze (Felder am `;`-Trenner),
  /// quote-bewusst: `"`-quotierte Felder dürfen `;`, `""`-Escapes **und
  /// Zeilenumbrüche** enthalten. Datensatz-Grenze ist ein Zeilenumbruch
  /// außerhalb von Quotes (CRLF wird zusammengefasst).
  static List<List<String>> _parseRecords(String text) {
    final records = <List<String>>[];
    var fields = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;

    void endField() {
      fields.add(buffer.toString());
      buffer.clear();
    }

    void endRecord() {
      endField();
      records.add(fields);
      fields = <String>[];
    }

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == '"') {
        if (inQuotes && i + 1 < text.length && text[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ';' && !inQuotes) {
        endField();
      } else if ((char == '\n' || char == '\r') && !inQuotes) {
        if (char == '\r' && i + 1 < text.length && text[i + 1] == '\n') {
          i++; // CRLF -> ein Datensatz-Ende
        }
        endRecord();
      } else {
        buffer.write(char);
      }
    }
    // Letzten Datensatz übernehmen, falls der Text ohne Zeilenumbruch endet.
    if (buffer.isNotEmpty || fields.isNotEmpty) {
      endRecord();
    }
    return records;
  }

  static String? _nullIfEmpty(String? value) {
    if (value == null || value.isEmpty) return null;
    return value;
  }
}
