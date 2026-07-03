import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../core/datev_export.dart';
import '../core/finance_analytics.dart';
import '../core/ical_export.dart';
import '../core/kasse_report.dart';
import '../core/order_frequency.dart' show isoWeekNumber;
import '../core/personnel_cost.dart';
import '../core/shift_plan_grid.dart';
import '../models/audit_log_entry.dart';
import '../models/contact.dart';
import '../models/finance_models.dart';
import '../models/customer_order.dart';
import '../models/payroll_record.dart';
import '../models/product.dart';
import '../models/shift.dart';
import '../models/user_settings.dart';
import '../models/work_entry.dart';
import 'download_service.dart';
import 'pdf_service.dart';

class ExportService {
  ExportService._();

  static Future<void> exportMonthlyReport({
    required List<WorkEntry> entries,
    required UserSettings settings,
    required int year,
    required int month,
  }) async {
    final bytes = await PdfService.generateMonthlyReport(
      entries: entries,
      settings: settings,
      year: year,
      month: month,
    );

    final stamp = DateFormat('yyyy-MM', 'de_DE').format(DateTime(year, month));
    final fileName = 'arbeitszeitbericht-$stamp.pdf';
    await downloadPdfBytes(bytes: bytes, fileName: fileName);
  }

  static Future<void> exportShiftPlanPdf({
    required List<Shift> shifts,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required String rangeLabel,
    String? employeeLabel,
    String? teamLabel,
  }) async {
    final bytes = await PdfService.generateShiftPlanReport(
      shifts: shifts,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      rangeLabel: rangeLabel,
      employeeLabel: employeeLabel,
      teamLabel: teamLabel,
    );
    await downloadFileBytes(
      bytes: bytes,
      fileName: _shiftPlanFileName(
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        extension: 'pdf',
      ),
      mimeType: 'application/pdf',
    );
  }

  static Future<void> exportShiftPlanCsv({
    required List<Shift> shifts,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required String rangeLabel,
    String? employeeLabel,
    String? teamLabel,
  }) async {
    final csv = buildShiftPlanCsv(
      shifts: shifts,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      rangeLabel: rangeLabel,
      employeeLabel: employeeLabel,
      teamLabel: teamLabel,
    );
    await downloadFileBytes(
      bytes: Uint8List.fromList(utf8.encode(csv)),
      fileName: _shiftPlanFileName(
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        extension: 'csv',
      ),
      mimeType: 'text/csv;charset=utf-8',
    );
  }

  static Future<void> exportShiftPlanIcal({
    required List<Shift> shifts,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    final ical = IcalExport.buildShifts(shifts);
    await downloadFileBytes(
      bytes: Uint8List.fromList(utf8.encode(ical)),
      fileName: _shiftPlanFileName(
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        extension: 'ics',
      ),
      mimeType: 'text/calendar;charset=utf-8',
    );
  }

  /// Schichtplan als CSV, **nach Standort getrennt** (Matrix: Zeilen =
  /// Mitarbeiter, Spalten = Kalendertage) \u2014 Format des echten Plans. UTF-8-BOM
  /// + `;`-Delimiter (deutsches Excel).
  static String buildShiftPlanCsv({
    required List<Shift> shifts,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required String rangeLabel,
    String? employeeLabel,
    String? teamLabel,
  }) {
    final buffer = StringBuffer('\uFEFF');
    buffer.writeln('Schichtplan Export');
    buffer.writeln('Zeitraum;${_escapeCsv(rangeLabel)}');
    if (employeeLabel != null && employeeLabel.trim().isNotEmpty) {
      buffer.writeln('Mitarbeiter;${_escapeCsv(employeeLabel)}');
    }
    if (teamLabel != null && teamLabel.trim().isNotEmpty) {
      buffer.writeln('Team;${_escapeCsv(teamLabel)}');
    }

    final grid = ShiftPlanGrid.build(
      shifts: shifts,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
    );

    if (grid.sites.isEmpty) {
      buffer.writeln();
      buffer.writeln('Keine Schichten im Zeitraum.');
      return buffer.toString();
    }

    final dateFmt = DateFormat('dd.MM.', 'de_DE');
    final dayHeaders = [
      for (final day in grid.days)
        '${_weekdayShort(day.weekday)} ${dateFmt.format(day)}',
    ];

    for (final site in grid.sites) {
      buffer.writeln();
      buffer.writeln(_escapeCsv(site.siteName));
      buffer.writeln(
        ['Mitarbeiter', ...dayHeaders, 'Summe (h)'].map(_escapeCsv).join(';'),
      );
      for (final row in site.rows) {
        buffer.writeln([
          row.label,
          ...row.cells,
          row.totalHours.toStringAsFixed(2),
        ].map(_escapeCsv).join(';'));
      }
    }

    return buffer.toString();
  }

  // --- Kundenbestellungen --------------------------------------------------

  static Future<void> exportCustomerOrdersPdf({
    required List<CustomerOrder> orders,
    String? siteLabel,
  }) async {
    final bytes = await PdfService.generateCustomerOrderReport(
      orders: orders,
      siteLabel: siteLabel,
    );
    await downloadFileBytes(
      bytes: bytes,
      fileName: _customerOrderFileName('pdf'),
      mimeType: 'application/pdf',
    );
  }

  static Future<void> exportCustomerOrdersCsv({
    required List<CustomerOrder> orders,
    String? siteLabel,
  }) async {
    final csv = buildCustomerOrderCsv(orders: orders, siteLabel: siteLabel);
    await downloadFileBytes(
      bytes: Uint8List.fromList(utf8.encode(csv)),
      fileName: _customerOrderFileName('csv'),
      mimeType: 'text/csv;charset=utf-8',
    );
  }

  static String buildCustomerOrderCsv({
    required List<CustomerOrder> orders,
    String? siteLabel,
  }) {
    final dateFmt = DateFormat('dd.MM.yyyy', 'de_DE');
    final currencyFmt =
        NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);
    final buffer = StringBuffer('﻿');

    buffer.writeln('Kundenbestellungen Export');
    if (siteLabel != null && siteLabel.trim().isNotEmpty) {
      buffer.writeln('Laden;${_escapeCsv(siteLabel)}');
    }
    buffer.writeln();
    buffer.writeln(
      'Bestellnr.;Kunde;Kontakt;Laden;Abholtermin;Rhythmus;Status;Vorbereitet;Positionen;Summe;Notiz',
    );

    for (final order in orders) {
      final positions = order.items
          .map((item) => '${item.quantity}x ${item.name}')
          .join(' | ');
      buffer.writeln([
        order.orderNumber ?? '',
        order.customerName,
        order.customerContact ?? '',
        order.siteName ?? '',
        order.pickupDate == null ? '' : dateFmt.format(order.pickupDate!),
        order.recurrence.label,
        order.status.label,
        order.isPrepared ? 'Ja' : 'Nein',
        positions,
        order.hasPrices ? currencyFmt.format(order.totalCents / 100) : '',
        order.notes ?? '',
      ].map(_escapeCsv).join(';'));
    }

    return buffer.toString();
  }

  static String _customerOrderFileName(String extension) {
    final stamp = DateFormat('yyyy-MM-dd', 'de_DE').format(DateTime.now());
    return 'kundenbestellungen-$stamp.$extension';
  }

  // --- Warenwirtschaft: Bestand & Nachbestellung ---------------------------

  static Future<void> exportStockListPdf({
    required List<Product> products,
    String? siteLabel,
  }) async {
    final bytes = await PdfService.generateStockListReport(
      products: products,
      siteLabel: siteLabel,
    );
    await downloadFileBytes(
      bytes: bytes,
      fileName: _inventoryFileName('bestandsliste', 'pdf'),
      mimeType: 'application/pdf',
    );
  }

  static Future<void> exportStockListCsv({
    required List<Product> products,
    String? siteLabel,
  }) async {
    final csv = buildStockListCsv(products: products, siteLabel: siteLabel);
    await downloadFileBytes(
      bytes: Uint8List.fromList(utf8.encode(csv)),
      fileName: _inventoryFileName('bestandsliste', 'csv'),
      mimeType: 'text/csv;charset=utf-8',
    );
  }

  static Future<void> exportReorderListPdf({
    required List<Product> products,
    String? siteLabel,
  }) async {
    final bytes = await PdfService.generateReorderListReport(
      products: products,
      siteLabel: siteLabel,
    );
    await downloadFileBytes(
      bytes: bytes,
      fileName: _inventoryFileName('nachbestellliste', 'pdf'),
      mimeType: 'application/pdf',
    );
  }

  static Future<void> exportReorderListCsv({
    required List<Product> products,
    String? siteLabel,
  }) async {
    final csv = buildReorderListCsv(products: products, siteLabel: siteLabel);
    await downloadFileBytes(
      bytes: Uint8List.fromList(utf8.encode(csv)),
      fileName: _inventoryFileName('nachbestellliste', 'csv'),
      mimeType: 'text/csv;charset=utf-8',
    );
  }

  // --- Kassenbericht (Kassen-Modul M4) -------------------------------------

  static Future<void> exportKassenberichtCsv({
    required List<KassenPeriode> perioden,
    required ReportGranularity granularity,
    String? siteLabel,
  }) async {
    final csv = buildKassenberichtCsv(
      perioden: perioden,
      granularity: granularity,
      siteLabel: siteLabel,
    );
    await downloadFileBytes(
      bytes: Uint8List.fromList(utf8.encode(csv)),
      fileName: _inventoryFileName('kassenbericht', 'csv'),
      mimeType: 'text/csv;charset=utf-8',
    );
  }

  /// Kassenbericht als CSV (UTF-8-BOM + `;`-Delimiter, deutsches Excel).
  /// Beträge in Euro mit Dezimalkomma; leere Buckets bleiben leer statt „0".
  static String buildKassenberichtCsv({
    required List<KassenPeriode> perioden,
    required ReportGranularity granularity,
    String? siteLabel,
  }) {
    String euro(int? cents) =>
        cents == null ? '' : (cents / 100).toStringAsFixed(2).replaceAll('.', ',');
    String pct(double? value) =>
        value == null ? '' : value.toStringAsFixed(1).replaceAll('.', ',');

    final monthFmt = DateFormat('MMM yyyy', 'de_DE');
    String periodLabel(KassenPeriode p) => switch (granularity) {
          ReportGranularity.week => 'KW${isoWeekNumber(p.start)} ${p.start.year}',
          ReportGranularity.month => monthFmt.format(p.start),
          ReportGranularity.year => '${p.start.year}',
        };

    final buffer = StringBuffer('﻿');
    buffer.writeln('Kassenbericht Export');
    buffer.writeln('Granularität;${_escapeCsv(granularity.label)}');
    if (siteLabel != null && siteLabel.trim().isNotEmpty) {
      buffer.writeln('Laden;${_escapeCsv(siteLabel)}');
    }
    buffer.writeln('Hinweis;Richtwert — Kassendaten Swagger-unverifiziert');
    buffer.writeln();
    buffer.writeln([
      'Zeitraum',
      'Umsatz brutto',
      'Umsatz netto',
      'Käufe netto',
      'Käufe brutto',
      'Wareneinsatz',
      'Rohertrag netto',
      'Rohertrag brutto',
      'Δ Vorperiode %',
      'Δ Vorjahr %',
      'Belege',
      'Erstattungen',
      'EK-Abdeckung %',
    ].map(_escapeCsv).join(';'));
    for (final p in perioden) {
      buffer.writeln([
        periodLabel(p),
        p.hatDaten ? euro(p.umsatzBruttoCents) : '',
        p.hatDaten ? euro(p.umsatzNettoCents) : '',
        euro(p.kaeufeNettoCents),
        euro(p.kaeufeBruttoCents),
        euro(p.wareneinsatzCents),
        euro(p.rohertragNettoCents),
        euro(p.rohertragBruttoCents),
        pct(p.deltaVorperiodePct),
        pct(p.deltaVorjahrPct),
        p.hatDaten ? '${p.belege}' : '',
        p.hatDaten ? '${p.erstattungen}' : '',
        pct(p.wareneinsatzAbdeckungPct),
      ].map(_escapeCsv).join(';'));
    }
    return buffer.toString();
  }

  static String buildStockListCsv({
    required List<Product> products,
    String? siteLabel,
  }) {
    final currencyFmt =
        NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);
    final buffer = StringBuffer('﻿');
    buffer.writeln('Bestandsliste Export');
    if (siteLabel != null && siteLabel.trim().isNotEmpty) {
      buffer.writeln('Laden;${_escapeCsv(siteLabel)}');
    }
    buffer.writeln();
    buffer.writeln(
      'Artikel;Warengruppe;Standort;Bestand;Einheit;Mindestbestand;Zielbestand;EK;VK;Warenwert',
    );
    final sorted = [...products]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    for (final p in sorted) {
      buffer.writeln([
        p.name,
        p.category ?? '',
        p.siteName ?? '',
        '${p.currentStock}',
        p.unit,
        p.minStock > 0 ? '${p.minStock}' : '',
        p.targetStock > 0 ? '${p.targetStock}' : '',
        p.purchasePriceCents == null
            ? ''
            : currencyFmt.format(p.purchasePriceCents! / 100),
        p.sellingPriceCents == null
            ? ''
            : currencyFmt.format(p.sellingPriceCents! / 100),
        p.stockValuePurchaseCents > 0
            ? currencyFmt.format(p.stockValuePurchaseCents / 100)
            : '',
      ].map(_escapeCsv).join(';'));
    }
    return buffer.toString();
  }

  static String buildReorderListCsv({
    required List<Product> products,
    String? siteLabel,
  }) {
    final buffer = StringBuffer('﻿');
    buffer.writeln('Nachbestell-Liste Export');
    if (siteLabel != null && siteLabel.trim().isNotEmpty) {
      buffer.writeln('Laden;${_escapeCsv(siteLabel)}');
    }
    buffer.writeln();
    buffer.writeln(
      'Artikel;Lieferant;Standort;Bestand;Einheit;Mindestbestand;Zielbestand;Vorschlag',
    );
    final sorted = [...products]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    for (final p in sorted) {
      buffer.writeln([
        p.name,
        p.supplierName ?? '',
        p.siteName ?? '',
        '${p.currentStock}',
        p.unit,
        '${p.minStock}',
        p.targetStock > 0 ? '${p.targetStock}' : '',
        '${p.suggestedReorderQuantity}',
      ].map(_escapeCsv).join(';'));
    }
    return buffer.toString();
  }

  static String _inventoryFileName(String base, String extension) {
    final stamp = DateFormat('yyyy-MM-dd', 'de_DE').format(DateTime.now());
    return '$base-$stamp.$extension';
  }

  // --- Kontakte ------------------------------------------------------------

  static Future<void> exportContactsPdf({
    required List<Contact> contacts,
    String? siteLabel,
    String? filterLabel,
  }) async {
    final bytes = await PdfService.generateContactListReport(
      contacts: contacts,
      siteLabel: siteLabel,
      filterLabel: filterLabel,
    );
    await downloadFileBytes(
      bytes: bytes,
      fileName: _contactsFileName('pdf'),
      mimeType: 'application/pdf',
    );
  }

  static Future<void> exportContactsCsv({
    required List<Contact> contacts,
    String? filterLabel,
  }) async {
    final csv = buildContactsCsv(contacts: contacts, filterLabel: filterLabel);
    await downloadFileBytes(
      bytes: Uint8List.fromList(utf8.encode(csv)),
      fileName: _contactsFileName('csv'),
      mimeType: 'text/csv;charset=utf-8',
    );
  }

  static String buildContactsCsv({
    required List<Contact> contacts,
    String? filterLabel,
  }) {
    final buffer = StringBuffer('﻿');
    final sorted = [...contacts]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    buffer.writeln('Kontakte Export');
    if (filterLabel != null && filterLabel.trim().isNotEmpty) {
      buffer.writeln('Auswahl;${_escapeCsv(filterLabel)}');
    }
    buffer.writeln();
    buffer.writeln(
      'Name;Kategorie;Ansprechpartner;Telefon;Mobil;E-Mail;Website;Straße;PLZ;Ort;USt-IdNr.;Kunden-/Lief.-Nr.;Standort;Schlagworte;Wichtig;Aktiv;Notiz',
    );

    for (final contact in sorted) {
      buffer.writeln([
        contact.name,
        contact.type.label,
        contact.contactPerson ?? '',
        contact.phone ?? '',
        contact.mobile ?? '',
        contact.email ?? '',
        contact.website ?? '',
        contact.street ?? '',
        contact.postalCode ?? '',
        contact.city ?? '',
        contact.taxId ?? '',
        contact.customerNumber ?? '',
        contact.siteName ?? 'Allgemein',
        contact.tags.join(', '),
        contact.isFavorite ? 'Ja' : 'Nein',
        contact.isActive ? 'Ja' : 'Nein',
        contact.notes ?? '',
      ].map(_escapeCsv).join(';'));
    }

    return buffer.toString();
  }

  static String _contactsFileName(String extension) {
    final stamp = DateFormat('yyyy-MM-dd', 'de_DE').format(DateTime.now());
    return 'kontakte-$stamp.$extension';
  }

  // --- Personal-Bereich: Lohnabrechnung & Personalkosten -------------------

  static Future<void> exportPayrollPdf({
    required PayrollRecord record,
    required String employeeName,
  }) async {
    final bytes = await PdfService.generatePayrollReport(
      record: record,
      employeeName: employeeName,
    );
    final stamp =
        '${record.periodYear}-${record.periodMonth.toString().padLeft(2, '0')}';
    await downloadPdfBytes(
      bytes: bytes,
      fileName: 'lohnabrechnung-$stamp.pdf',
    );
  }

  static Future<void> exportPersonnelCostPdf({
    required List<PersonnelCostRow> rows,
    required String rangeLabel,
    required String title,
  }) async {
    final bytes = await PdfService.generatePersonnelCostReport(
      rows: rows,
      rangeLabel: rangeLabel,
      title: title,
    );
    await downloadFileBytes(
      bytes: bytes,
      fileName: _personnelCostFileName('pdf'),
      mimeType: 'application/pdf',
    );
  }

  /// Monats-Lohnjournal aller Mitarbeiter als CSV (UTF-8-BOM + `;`, deutsches
  /// Excel) — pur/testbar (PA-6.3). Ein Datensatz je [PayrollRecord];
  /// [employeeName] löst die Anzeige je userId auf. Für Monatsabschluss/Weiter-
  /// gabe ans Lohnbüro. Enthält den Richtwert-Vorbehalt in der Kopfzeile.
  static String buildLohnjournalCsv({
    required List<PayrollRecord> records,
    required String Function(String userId) employeeName,
    required String monthLabel,
  }) {
    final fmt = NumberFormat.currency(
        locale: 'de_DE', symbol: '€', decimalDigits: 2);
    String money(int cents) => fmt.format(cents / 100);
    final buffer = StringBuffer('﻿');
    buffer.writeln('Lohnjournal (unverbindlicher Richtwert)');
    buffer.writeln('Zeitraum;${_escapeCsv(monthLabel)}');
    buffer.writeln();
    buffer.writeln([
      'Mitarbeiter', 'Steuerklasse', 'Beschäftigung', 'Status', 'Brutto',
      'Lohnsteuer', 'Soli', 'Kirchensteuer', 'KV (AN)', 'PV (AN)', 'RV (AN)',
      'ALV (AN)', 'Netto', 'AG-Gesamt', 'U1', 'U2', 'InsO', 'UV',
    ].map(_escapeCsv).join(';'));
    final sorted = [...records]
      ..sort((a, b) =>
          employeeName(a.userId).compareTo(employeeName(b.userId)));
    for (final r in sorted) {
      buffer.writeln([
        employeeName(r.userId), r.taxClass.label, r.kind.label, r.status.label,
        money(r.grossCents), money(r.incomeTaxCents), money(r.soliCents),
        money(r.churchTaxCents), money(r.healthEmployeeCents),
        money(r.careEmployeeCents), money(r.pensionEmployeeCents),
        money(r.unemploymentEmployeeCents), money(r.netCents),
        money(r.employerTotalCents), money(r.employerU1Cents),
        money(r.employerU2Cents), money(r.employerInsolvencyCents),
        money(r.employerAccidentCents),
      ].map(_escapeCsv).join(';'));
    }
    return buffer.toString();
  }

  static Future<void> exportLohnjournalCsv({
    required List<PayrollRecord> records,
    required String Function(String userId) employeeName,
    required String monthLabel,
    required String fileStamp,
  }) async {
    final csv = buildLohnjournalCsv(
      records: records,
      employeeName: employeeName,
      monthLabel: monthLabel,
    );
    await downloadFileBytes(
      bytes: Uint8List.fromList(utf8.encode(csv)),
      fileName: 'lohnjournal-$fileStamp.csv',
      mimeType: 'text/csv;charset=utf-8',
    );
  }

  static Future<void> exportPersonnelCostCsv({
    required List<PersonnelCostRow> rows,
    required String rangeLabel,
    required String title,
  }) async {
    final csv =
        buildPersonnelCostCsv(rows: rows, rangeLabel: rangeLabel, title: title);
    await downloadFileBytes(
      bytes: Uint8List.fromList(utf8.encode(csv)),
      fileName: _personnelCostFileName('csv'),
      mimeType: 'text/csv;charset=utf-8',
    );
  }

  static String buildPersonnelCostCsv({
    required List<PersonnelCostRow> rows,
    required String rangeLabel,
    required String title,
  }) {
    final currencyFmt =
        NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);
    final buffer = StringBuffer('﻿');

    buffer.writeln('Personalkosten Export');
    buffer.writeln('Auswertung;${_escapeCsv(title)}');
    buffer.writeln('Zeitraum;${_escapeCsv(rangeLabel)}');
    buffer.writeln();
    buffer.writeln('Bezeichnung;Stunden;Personalkosten;AG-Gesamtkosten');

    for (final row in rows) {
      buffer.writeln([
        row.label,
        row.workedHours.toStringAsFixed(2),
        currencyFmt.format(row.laborCostCents / 100),
        row.employerTotalCents > 0
            ? currencyFmt.format(row.employerTotalCents / 100)
            : '',
      ].map(_escapeCsv).join(';'));
    }

    return buffer.toString();
  }

  static String _personnelCostFileName(String extension) {
    final stamp = DateFormat('yyyy-MM-dd', 'de_DE').format(DateTime.now());
    return 'personalkosten-$stamp.$extension';
  }

  static String _shiftPlanFileName({
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required String extension,
  }) {
    final startStamp = DateFormat('yyyy-MM-dd', 'de_DE').format(rangeStart);
    final inclusiveEnd = rangeEnd.subtract(const Duration(days: 1));
    final endStamp = DateFormat('yyyy-MM-dd', 'de_DE').format(
      inclusiveEnd.isBefore(rangeStart) ? rangeStart : inclusiveEnd,
    );
    final suffix =
        startStamp == endStamp ? startStamp : '$startStamp-bis-$endStamp';
    return 'schichtplan-$suffix.$extension';
  }

  static String _escapeCsv(String value) {
    var normalized = value;
    // CSV-/Formel-Injection: Excel/LibreOffice fuehren Zellen, die mit
    // = + - @ Tab oder CR beginnen, als Formel aus (z.B. =HYPERLINK(...),
    // =cmd|...). Mit vorangestelltem Apostroph als Text neutralisieren —
    // wichtig, da Kontakte/Notizen aus fremder CSV importiert werden koennen
    // und unveraendert re-exportiert werden (probleme #7).
    if (normalized.isNotEmpty &&
        const ['=', '+', '-', '@', '\t', '\r'].contains(normalized[0])) {
      normalized = "'$normalized";
    }
    normalized = normalized.replaceAll('"', '""');
    if (normalized.contains(';') ||
        normalized.contains('"') ||
        normalized.contains('\n') ||
        // Nacktes CR (ohne LF) wuerde sonst die Datensatzstruktur zerstoeren
        // (probleme #38).
        normalized.contains('\r')) {
      return '"$normalized"';
    }
    return normalized;
  }

  static String _weekdayShort(int weekday) {
    const weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    return weekdays[(weekday - 1).clamp(0, 6)];
  }

  // --- Änderungsprotokoll (Audit) -----------------------------------------

  static String buildAuditLogCsv({required List<AuditLogEntry> entries}) {
    final dateFmt = DateFormat('dd.MM.yyyy HH:mm', 'de_DE');
    final buffer = StringBuffer('﻿');
    buffer.writeln('Änderungsprotokoll Export');
    buffer.writeln('Erstellt;${_escapeCsv(dateFmt.format(DateTime.now()))}');
    buffer.writeln();
    buffer.writeln(
      'Zeitpunkt;Aktion;Objekttyp;Objekt-ID;Zusammenfassung;Benutzer',
    );
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    final rows = [...entries]
      ..sort((a, b) =>
          (b.createdAt ?? epoch).compareTo(a.createdAt ?? epoch));
    for (final e in rows) {
      buffer.writeln([
        e.createdAt == null ? '' : dateFmt.format(e.createdAt!),
        e.action.label,
        e.entityType,
        e.entityId ?? '',
        e.summary,
        e.actorName ?? e.actorUid ?? '',
      ].map(_escapeCsv).join(';'));
    }
    return buffer.toString();
  }

  static Future<void> exportAuditLogCsv({
    required List<AuditLogEntry> entries,
  }) async {
    final csv = buildAuditLogCsv(entries: entries);
    await downloadFileBytes(
      bytes: Uint8List.fromList(utf8.encode(csv)),
      fileName: _auditLogFileName('csv'),
      mimeType: 'text/csv;charset=utf-8',
    );
  }

  static String _auditLogFileName(String extension) {
    final stamp = DateFormat('yyyy-MM-dd', 'de_DE').format(DateTime.now());
    return 'aenderungsprotokoll-$stamp.$extension';
  }

  // --- Finanzen: Journal-CSV + DATEV-EXTF-Buchungsstapel -------------------

  static String _euroPlain(int cents) =>
      (cents / 100).toStringAsFixed(2).replaceAll('.', ',');

  static String buildFinanceJournalCsv({
    required List<JournalEntry> entries,
    required Map<String, CostCenter> centersById,
    required Map<String, CostType> typesById,
    required int year,
  }) {
    final buffer = StringBuffer('\uFEFF');
    buffer.writeln('Buchungsjournal $year');
    buffer.writeln();
    buffer.writeln(
        'Datum;Bezeichnung;Kostenstelle;Kostenart;Betrag (€);Art;Beleg');
    final rows = entries.where((e) => e.date.year == year).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    for (final e in rows) {
      buffer.writeln([
        DateFormat('dd.MM.yyyy', 'de_DE').format(e.date),
        e.description,
        centersById[e.costCenterId]?.name ?? '',
        typesById[e.costTypeId]?.name ?? '',
        _euroPlain(e.amountCents),
        e.amountCents >= 0 ? 'Kosten' : 'Gutschrift',
        e.reference ?? '',
      ].map(_escapeCsv).join(';'));
    }
    return buffer.toString();
  }

  static Future<void> exportFinanceJournalCsv({
    required List<JournalEntry> entries,
    required Map<String, CostCenter> centersById,
    required Map<String, CostType> typesById,
    required int year,
  }) async {
    final csv = buildFinanceJournalCsv(
      entries: entries,
      centersById: centersById,
      typesById: typesById,
      year: year,
    );
    await downloadFileBytes(
      bytes: Uint8List.fromList(utf8.encode(csv)),
      fileName: 'Buchungsjournal_$year.csv',
      mimeType: 'text/csv;charset=utf-8',
    );
  }

  static Future<void> exportFinanceReportPdf({
    required int year,
    required String orgName,
    required List<CostCenterReport> reports,
    required List<MonthBucket> months,
    required int totalPlanned,
    required int totalActual,
    required int totalExpenses,
    required int totalCredits,
  }) async {
    final bytes = await PdfService.generateFinanceReport(
      year: year,
      orgName: orgName,
      reports: reports,
      months: months,
      totalPlanned: totalPlanned,
      totalActual: totalActual,
      totalExpenses: totalExpenses,
      totalCredits: totalCredits,
    );
    await downloadPdfBytes(bytes: bytes, fileName: 'Finanzbericht_$year.pdf');
  }

  /// DATEV-EXTF-Buchungsstapel (Format 700) als Datei. Encoding UTF-8 (von
  /// aktuellen DATEV-Importen akzeptiert) – siehe [DatevExport.disclaimer].
  static Future<void> exportDatevBuchungsstapel({
    required List<JournalEntry> entries,
    required Map<String, CostCenter> centersById,
    required Map<String, CostType> typesById,
    required int year,
    DatevExportConfig config = const DatevExportConfig(),
  }) async {
    final content = DatevExport.buildBuchungsstapel(
      entries: entries,
      centersById: centersById,
      typesById: typesById,
      year: year,
      config: config,
      generatedAt: DateTime.now(),
    );
    await downloadFileBytes(
      bytes: Uint8List.fromList(utf8.encode(content)),
      fileName: 'EXTF_Buchungsstapel_$year.csv',
      mimeType: 'text/csv;charset=utf-8',
    );
  }
}
