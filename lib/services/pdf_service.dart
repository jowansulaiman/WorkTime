// lib/services/pdf_service.dart

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/payroll_calculator.dart';
import '../core/personnel_cost.dart';
import '../models/contact.dart';
import '../models/customer_order.dart';
import '../models/payroll_record.dart';
import '../models/product.dart';
import '../models/shift.dart';
import '../models/work_entry.dart';
import '../models/user_settings.dart';

class PdfService {
  static final _timeFormat = DateFormat('HH:mm');

  static Future<Uint8List> generateMonthlyReport({
    required List<WorkEntry> entries,
    required UserSettings settings,
    required int year,
    required int month,
  }) async {
    final baseFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final boldFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );
    final italicFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Italic.ttf'),
    );

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: baseFont,
        bold: boldFont,
        italic: italicFont,
      ),
    );

    final totalHours = entries.fold<double>(0, (sum, e) => sum + e.workedHours);
    final totalWage = totalHours * settings.hourlyRate;
    final overtimeHours = entries.fold<double>(0, (sum, e) {
      final diff = e.workedHours - settings.dailyHours;
      return sum + (diff > 0 ? diff : 0);
    });
    final workingDayCount = entries
        .map((entry) =>
            '${entry.date.year}-${entry.date.month}-${entry.date.day}')
        .toSet()
        .length;
    final monthTitle = '${_monthName(month)} $year';

    // ── Colors ─────────────────────────────────────────────────────
    const primary = PdfColor.fromInt(0xFF1E3A5F);
    const accent = PdfColor.fromInt(0xFF2E86AB);
    const lightBg = PdfColor.fromInt(0xFFF5F7FA);
    const success = PdfColor.fromInt(0xFF27AE60);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => _buildHeader(
            context, monthTitle, settings, primary, accent, lightBg),
        footer: (context) => _buildFooter(context, primary),
        build: (context) => [
          _buildSummaryCards(
            totalHours: totalHours,
            totalWage: totalWage,
            overtimeHours: overtimeHours,
            workingDayCount: workingDayCount,
            settings: settings,
            accent: accent,
            success: success,
            lightBg: lightBg,
            primary: primary,
          ),
          pw.SizedBox(height: 16),
          _buildEntriesTable(entries, settings, primary, accent, lightBg),
          pw.SizedBox(height: 16),
          if (settings.hourlyRate > 0)
            _buildWageSection(totalHours, settings, primary, accent, lightBg),
        ],
      ),
    );

    return pdf.save();
  }

  static Future<Uint8List> generateShiftPlanReport({
    required List<Shift> shifts,
    required String rangeLabel,
    String? employeeLabel,
    String? teamLabel,
  }) async {
    final baseFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final boldFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );
    final italicFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Italic.ttf'),
    );

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: baseFont,
        bold: boldFont,
        italic: italicFont,
      ),
    );

    final sortedShifts = [...shifts]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final totalHours =
        sortedShifts.fold<double>(0, (sum, shift) => sum + shift.workedHours);
    final employeeCount =
        sortedShifts.map((shift) => shift.userId).toSet().length;
    final teamCount = sortedShifts
        .map((shift) => shift.team?.trim())
        .whereType<String>()
        .where((team) => team.isNotEmpty)
        .toSet()
        .length;

    const primary = PdfColor.fromInt(0xFF1E3A5F);
    const accent = PdfColor.fromInt(0xFF2E86AB);
    const lightBg = PdfColor.fromInt(0xFFF5F7FA);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => _buildShiftPlanHeader(
          rangeLabel: rangeLabel,
          employeeLabel: employeeLabel,
          teamLabel: teamLabel,
          primary: primary,
          accent: accent,
        ),
        footer: (context) => _buildFooter(context, primary),
        build: (context) => [
          _buildShiftPlanSummary(
            shiftCount: sortedShifts.length,
            totalHours: totalHours,
            employeeCount: employeeCount,
            teamCount: teamCount,
            primary: primary,
            accent: accent,
            lightBg: lightBg,
          ),
          pw.SizedBox(height: 16),
          _buildShiftPlanTable(
            shifts: sortedShifts,
            primary: primary,
            lightBg: lightBg,
          ),
        ],
      ),
    );

    return pdf.save();
  }

  /// Erzeugt einen PDF-Bericht ueber Kundenbestellungen (Sonderbestellungen).
  static Future<Uint8List> generateCustomerOrderReport({
    required List<CustomerOrder> orders,
    String? siteLabel,
  }) async {
    final baseFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final boldFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );
    final italicFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Italic.ttf'),
    );

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: baseFont,
        bold: boldFont,
        italic: italicFont,
      ),
    );

    final dateFmt = DateFormat('dd.MM.yyyy', 'de_DE');
    final currencyFmt =
        NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);

    final sorted = [...orders]..sort((a, b) {
        final da = a.pickupDate;
        final db = b.pickupDate;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      });
    final openCount =
        sorted.where((order) => order.status == CustomerOrderStatus.open).length;
    final preparedCount = sorted
        .where((order) => order.status == CustomerOrderStatus.prepared)
        .length;
    final notPreparedCount = sorted
        .where((order) => order.status.isOpen && !order.isPrepared)
        .length;

    const primary = PdfColor.fromInt(0xFF1E3A5F);
    const accent = PdfColor.fromInt(0xFF2E86AB);
    const lightBg = PdfColor.fromInt(0xFFF5F7FA);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => _buildCustomerOrderHeader(
          subtitle: siteLabel ?? 'Alle Laeden',
          primary: primary,
          accent: accent,
        ),
        footer: (context) => _buildFooter(context, primary),
        build: (context) => [
          pw.Row(
            children: [
              pw.Expanded(
                child: _summaryCard(
                  badge: 'GES',
                  label: 'Bestellungen',
                  value: '${sorted.length}',
                  color: primary,
                  lightBg: lightBg,
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _summaryCard(
                  badge: 'OFF',
                  label: 'Offen',
                  value: '$openCount',
                  color: accent,
                  lightBg: lightBg,
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _summaryCard(
                  badge: 'VOR',
                  label: 'Vorbereitet',
                  value: '$preparedCount',
                  color: const PdfColor.fromInt(0xFF2E7D32),
                  lightBg: lightBg,
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _summaryCard(
                  badge: '!',
                  label: 'Nicht vorbereitet',
                  value: '$notPreparedCount',
                  color: const PdfColor.fromInt(0xFFA76E00),
                  lightBg: lightBg,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          _buildCustomerOrderTable(
            orders: sorted,
            dateFmt: dateFmt,
            currencyFmt: currencyFmt,
            primary: primary,
            lightBg: lightBg,
          ),
        ],
      ),
    );

    return pdf.save();
  }

  /// Bestandsliste als PDF: Artikel mit Bestand, Preisen und Warenwert.
  static Future<Uint8List> generateStockListReport({
    required List<Product> products,
    String? siteLabel,
  }) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document(theme: fonts);
    final currencyFmt =
        NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);

    final sorted = [...products]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final totalPurchase =
        sorted.fold<int>(0, (sum, p) => sum + p.stockValuePurchaseCents);
    final totalSelling =
        sorted.fold<int>(0, (sum, p) => sum + p.stockValueSellingCents);
    final margin = totalSelling - totalPurchase;

    const primary = PdfColor.fromInt(0xFF1E3A5F);
    const accent = PdfColor.fromInt(0xFF2E86AB);
    const lightBg = PdfColor.fromInt(0xFFF5F7FA);
    const headerStyle = pw.TextStyle(fontSize: 9, color: PdfColors.white);
    const cellStyle = pw.TextStyle(fontSize: 9, color: PdfColors.grey800);

    String euro(int? cents) =>
        cents == null ? '–' : currencyFmt.format(cents / 100);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => _buildSimpleListHeader(
          title: 'Bestandsliste',
          subtitle: siteLabel ?? 'Alle Laeden',
          primary: primary,
          accent: accent,
        ),
        footer: (context) =>
            _buildFooter(context, primary, label: 'Bestandsliste'),
        build: (context) => [
          pw.Row(
            children: [
              pw.Expanded(
                child: _summaryCard(
                  badge: 'GES',
                  label: 'Artikel',
                  value: '${sorted.length}',
                  color: primary,
                  lightBg: lightBg,
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _summaryCard(
                  badge: 'EK',
                  label: 'Warenwert (EK)',
                  value: currencyFmt.format(totalPurchase / 100),
                  color: accent,
                  lightBg: lightBg,
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _summaryCard(
                  badge: 'SPN',
                  label: 'Erwartete Spanne',
                  value: currencyFmt.format(margin / 100),
                  color: const PdfColor.fromInt(0xFF2E7D32),
                  lightBg: lightBg,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Table(
            columnWidths: {
              0: const pw.FlexColumnWidth(2.0),
              1: const pw.FlexColumnWidth(1.2),
              2: const pw.FixedColumnWidth(54),
              3: const pw.FixedColumnWidth(42),
              4: const pw.FixedColumnWidth(64),
              5: const pw.FixedColumnWidth(64),
              6: const pw.FixedColumnWidth(74),
            },
            border: const pw.TableBorder(
              horizontalInside:
                  pw.BorderSide(color: PdfColors.grey200, width: 0.5),
            ),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: primary),
                children: [
                  'Artikel',
                  'Warengruppe',
                  'Bestand',
                  'Min',
                  'EK',
                  'VK',
                  'Warenwert',
                ]
                    .map((h) => pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 6, vertical: 8),
                          child: pw.Text(h, style: headerStyle),
                        ))
                    .toList(),
              ),
              ...sorted.asMap().entries.map((entry) {
                final i = entry.key;
                final p = entry.value;
                final bg = i.isEven ? PdfColors.white : lightBg;
                return pw.TableRow(
                  decoration: pw.BoxDecoration(color: bg),
                  children: [
                    _cell(p.name, cellStyle),
                    _cell(p.category ?? '–', cellStyle),
                    _cell('${p.currentStock} ${p.unit}', cellStyle),
                    _cell(p.minStock > 0 ? '${p.minStock}' : '–', cellStyle),
                    _cell(euro(p.purchasePriceCents), cellStyle),
                    _cell(euro(p.sellingPriceCents), cellStyle),
                    _cell(
                      p.stockValuePurchaseCents > 0
                          ? currencyFmt.format(p.stockValuePurchaseCents / 100)
                          : '–',
                      cellStyle,
                    ),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  /// Nachbestell-Liste als PDF: Artikel unter Meldebestand mit Vorschlagsmenge.
  static Future<Uint8List> generateReorderListReport({
    required List<Product> products,
    String? siteLabel,
  }) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document(theme: fonts);

    final sorted = [...products]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    const primary = PdfColor.fromInt(0xFF1E3A5F);
    const accent = PdfColor.fromInt(0xFF2E86AB);
    const lightBg = PdfColor.fromInt(0xFFF5F7FA);
    const headerStyle = pw.TextStyle(fontSize: 9, color: PdfColors.white);
    const cellStyle = pw.TextStyle(fontSize: 9, color: PdfColors.grey800);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => _buildSimpleListHeader(
          title: 'Nachbestell-Liste',
          subtitle: siteLabel ?? 'Alle Laeden',
          primary: primary,
          accent: accent,
        ),
        footer: (context) =>
            _buildFooter(context, primary, label: 'Nachbestell-Liste'),
        build: (context) => [
          pw.Row(
            children: [
              pw.Expanded(
                child: _summaryCard(
                  badge: '!',
                  label: 'Nachzubestellen',
                  value: '${sorted.length}',
                  color: const PdfColor.fromInt(0xFFA76E00),
                  lightBg: lightBg,
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(child: pw.SizedBox()),
              pw.SizedBox(width: 10),
              pw.Expanded(child: pw.SizedBox()),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Table(
            columnWidths: {
              0: const pw.FlexColumnWidth(2.0),
              1: const pw.FlexColumnWidth(1.6),
              2: const pw.FixedColumnWidth(58),
              3: const pw.FixedColumnWidth(46),
              4: const pw.FixedColumnWidth(52),
              5: const pw.FixedColumnWidth(70),
            },
            border: const pw.TableBorder(
              horizontalInside:
                  pw.BorderSide(color: PdfColors.grey200, width: 0.5),
            ),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: primary),
                children: [
                  'Artikel',
                  'Lieferant',
                  'Bestand',
                  'Min',
                  'Ziel',
                  'Vorschlag',
                ]
                    .map((h) => pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 6, vertical: 8),
                          child: pw.Text(h, style: headerStyle),
                        ))
                    .toList(),
              ),
              ...sorted.asMap().entries.map((entry) {
                final i = entry.key;
                final p = entry.value;
                final bg = i.isEven ? PdfColors.white : lightBg;
                return pw.TableRow(
                  decoration: pw.BoxDecoration(color: bg),
                  children: [
                    _cell(p.name, cellStyle),
                    _cell(p.supplierName ?? '–', cellStyle),
                    _cell('${p.currentStock} ${p.unit}', cellStyle),
                    _cell('${p.minStock}', cellStyle),
                    _cell(p.targetStock > 0 ? '${p.targetStock}' : '–', cellStyle),
                    _cell('${p.suggestedReorderQuantity} ${p.unit}', cellStyle),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  /// Generischer Listen-Kopf (Titel + Untertitel + Datum) im Markendesign.
  static pw.Widget _buildSimpleListHeader({
    required String title,
    required String subtitle,
    required PdfColor primary,
    required PdfColor accent,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: primary,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      margin: const pw.EdgeInsets.only(bottom: 16),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(subtitle,
                  style: pw.TextStyle(color: accent, fontSize: 13)),
            ],
          ),
          pw.Text(
            'Erstellt: ${DateFormat('dd.MM.yyyy', 'de_DE').format(DateTime.now())}',
            style: const pw.TextStyle(color: PdfColors.white, fontSize: 9),
          ),
        ],
      ),
    );
  }

  /// Kontaktliste als PDF, gruppiert nach Kontaktart.
  static Future<Uint8List> generateContactListReport({
    required List<Contact> contacts,
    String? siteLabel,
    String? filterLabel,
  }) async {
    final baseFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final boldFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );
    final italicFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Italic.ttf'),
    );

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: baseFont,
        bold: boldFont,
        italic: italicFont,
      ),
    );

    const primary = PdfColor.fromInt(0xFF1E3A5F);
    const accent = PdfColor.fromInt(0xFF2E86AB);
    const lightBg = PdfColor.fromInt(0xFFF5F7FA);

    // Stabil gruppieren nach Kontaktart (Reihenfolge der Enum-Definition).
    final grouped = <ContactType, List<Contact>>{};
    for (final type in ContactTypeX.ordered) {
      final inType = contacts.where((contact) => contact.type == type).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (inType.isNotEmpty) {
        grouped[type] = inType;
      }
    }
    final favoriteCount = contacts.where((c) => c.isFavorite).length;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => _buildContactHeader(
          subtitle: filterLabel ?? siteLabel ?? 'Alle Kontakte',
          primary: primary,
          accent: accent,
        ),
        footer: (context) =>
            _buildFooter(context, primary, label: 'Kontaktliste'),
        build: (context) => [
          pw.Row(
            children: [
              pw.Expanded(
                child: _summaryCard(
                  badge: 'GES',
                  label: 'Kontakte',
                  value: '${contacts.length}',
                  color: primary,
                  lightBg: lightBg,
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _summaryCard(
                  badge: 'KAT',
                  label: 'Kategorien',
                  value: '${grouped.length}',
                  color: accent,
                  lightBg: lightBg,
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _summaryCard(
                  badge: '★',
                  label: 'Wichtig',
                  value: '$favoriteCount',
                  color: const PdfColor.fromInt(0xFFA76E00),
                  lightBg: lightBg,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          for (final entry in grouped.entries) ...[
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 6, bottom: 6),
              child: pw.Text(
                '${entry.key.label}  (${entry.value.length})',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: primary,
                ),
              ),
            ),
            _buildContactTable(
              contacts: entry.value,
              primary: primary,
              lightBg: lightBg,
            ),
            pw.SizedBox(height: 12),
          ],
          if (grouped.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 24),
              child: pw.Text(
                'Keine Kontakte für die aktuelle Auswahl.',
                style: const pw.TextStyle(
                  fontSize: 11,
                  color: PdfColors.grey600,
                ),
              ),
            ),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildContactHeader({
    required String subtitle,
    required PdfColor primary,
    required PdfColor accent,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: primary,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      margin: const pw.EdgeInsets.only(bottom: 16),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Kontakte',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                subtitle,
                style: pw.TextStyle(color: accent, fontSize: 13),
              ),
            ],
          ),
          pw.Text(
            'Erstellt: ${DateFormat('dd.MM.yyyy', 'de_DE').format(DateTime.now())}',
            style: const pw.TextStyle(color: PdfColors.white, fontSize: 9),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildContactTable({
    required List<Contact> contacts,
    required PdfColor primary,
    required PdfColor lightBg,
  }) {
    const headerStyle = pw.TextStyle(fontSize: 9, color: PdfColors.white);
    const cellStyle = pw.TextStyle(fontSize: 9, color: PdfColors.grey800);
    final headers = [
      'Name',
      'Ansprechpartner',
      'Telefon',
      'E-Mail',
      'Ort',
      'Standort',
    ];

    return pw.Table(
      columnWidths: {
        0: const pw.FlexColumnWidth(1.6),
        1: const pw.FlexColumnWidth(1.2),
        2: const pw.FixedColumnWidth(78),
        3: const pw.FlexColumnWidth(1.6),
        4: const pw.FlexColumnWidth(1.0),
        5: const pw.FlexColumnWidth(1.0),
      },
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
      ),
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: primary),
          children: headers
              .map((h) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 6, vertical: 8),
                    child: pw.Text(h, style: headerStyle),
                  ))
              .toList(),
        ),
        ...contacts.asMap().entries.map((entry) {
          final i = entry.key;
          final contact = entry.value;
          final bg = i.isEven ? PdfColors.white : lightBg;
          final namePrefix = contact.isFavorite ? '★ ' : '';
          return pw.TableRow(
            decoration: pw.BoxDecoration(color: bg),
            children: [
              _cell('$namePrefix${contact.name}', cellStyle),
              _cell(contact.contactPerson ?? '–', cellStyle),
              _cell(contact.primaryPhone ?? '–', cellStyle),
              _cell(contact.email ?? '–', cellStyle),
              _cell(contact.city ?? '–', cellStyle),
              _cell(contact.siteName ?? 'Allgemein', cellStyle),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildCustomerOrderHeader({
    required String subtitle,
    required PdfColor primary,
    required PdfColor accent,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: primary,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      margin: const pw.EdgeInsets.only(bottom: 16),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Kundenbestellungen',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                subtitle,
                style: pw.TextStyle(color: accent, fontSize: 13),
              ),
            ],
          ),
          pw.Text(
            'Erstellt: ${DateFormat('dd.MM.yyyy', 'de_DE').format(DateTime.now())}',
            style: const pw.TextStyle(color: PdfColors.white, fontSize: 9),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildCustomerOrderTable({
    required List<CustomerOrder> orders,
    required DateFormat dateFmt,
    required NumberFormat currencyFmt,
    required PdfColor primary,
    required PdfColor lightBg,
  }) {
    const headerStyle = pw.TextStyle(fontSize: 9, color: PdfColors.white);
    const cellStyle = pw.TextStyle(fontSize: 9, color: PdfColors.grey800);
    final headers = [
      'Bestellnr.',
      'Kunde',
      'Abholung',
      'Status',
      'Positionen',
      'Summe',
    ];

    return pw.Table(
      columnWidths: {
        0: const pw.FixedColumnWidth(70),
        1: const pw.FlexColumnWidth(1.4),
        2: const pw.FixedColumnWidth(60),
        3: const pw.FixedColumnWidth(70),
        4: const pw.FlexColumnWidth(2.2),
        5: const pw.FixedColumnWidth(55),
      },
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
      ),
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: primary),
          children: headers
              .map((h) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 6, vertical: 8),
                    child: pw.Text(h, style: headerStyle),
                  ))
              .toList(),
        ),
        ...orders.asMap().entries.map((entry) {
          final i = entry.key;
          final order = entry.value;
          final bg = i.isEven ? PdfColors.white : lightBg;
          final statusLabel = order.status.isOpen && !order.isPrepared
              ? '${order.status.label} (offen)'
              : order.status.label;
          final positions = order.items
              .map((item) => '${item.quantity}× ${item.name}')
              .join(', ');
          return pw.TableRow(
            decoration: pw.BoxDecoration(color: bg),
            children: [
              _cell(order.orderNumber ?? '–', cellStyle),
              _cell(order.customerName, cellStyle),
              _cell(
                order.pickupDate == null
                    ? '–'
                    : dateFmt.format(order.pickupDate!),
                cellStyle,
              ),
              _cell(statusLabel, cellStyle),
              _cell(positions.isEmpty ? '–' : positions, cellStyle),
              _cell(
                order.hasPrices ? currencyFmt.format(order.totalCents / 100) : '–',
                cellStyle,
              ),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildHeader(
    pw.Context context,
    String monthTitle,
    UserSettings settings,
    PdfColor primary,
    PdfColor accent,
    PdfColor lightBg,
  ) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: primary,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      margin: const pw.EdgeInsets.only(bottom: 16),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'ARBEITSZEITBERICHT',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                monthTitle,
                style: pw.TextStyle(color: accent, fontSize: 13),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              if (settings.name.isNotEmpty)
                pw.Text(
                  settings.name,
                  style: pw.TextStyle(
                      color: PdfColors.white,
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 12),
                ),
              pw.Text(
                'Erstellt: ${DateFormat('dd.MM.yyyy').format(DateTime.now())}',
                style: const pw.TextStyle(color: PdfColors.white, fontSize: 9),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildShiftPlanHeader({
    required String rangeLabel,
    required String? employeeLabel,
    required String? teamLabel,
    required PdfColor primary,
    required PdfColor accent,
  }) {
    final filterRows = <String>[
      'Zeitraum: $rangeLabel',
      if (employeeLabel != null && employeeLabel.trim().isNotEmpty)
        'Mitarbeiter: $employeeLabel',
      if (teamLabel != null && teamLabel.trim().isNotEmpty) 'Team: $teamLabel',
    ];

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: primary,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      margin: const pw.EdgeInsets.only(bottom: 16),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'SCHICHTPLAN',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              pw.SizedBox(height: 6),
              for (final row in filterRows)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 2),
                  child: pw.Text(
                    row,
                    style: pw.TextStyle(color: accent, fontSize: 10),
                  ),
                ),
            ],
          ),
          pw.Text(
            'Erstellt: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}',
            style: const pw.TextStyle(color: PdfColors.white, fontSize: 9),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSummaryCards({
    required double totalHours,
    required double totalWage,
    required double overtimeHours,
    required int workingDayCount,
    required UserSettings settings,
    required PdfColor accent,
    required PdfColor success,
    required PdfColor lightBg,
    required PdfColor primary,
  }) {
    final currencyFmt = NumberFormat.currency(
        locale: 'de_DE', symbol: settings.currency, decimalDigits: 2);

    final cards = <pw.Widget>[
      pw.Expanded(
        child: _summaryCard(
          badge: 'STD',
          label: 'Gesamtstunden',
          value: '${totalHours.toStringAsFixed(2)} h',
          color: accent,
          lightBg: lightBg,
        ),
      ),
      pw.SizedBox(width: 10),
      pw.Expanded(
        child: _summaryCard(
          badge: 'TAG',
          label: 'Arbeitstage',
          value: '$workingDayCount ${workingDayCount == 1 ? 'Tag' : 'Tage'}',
          color: primary,
          lightBg: lightBg,
        ),
      ),
      pw.SizedBox(width: 10),
      pw.Expanded(
        child: _summaryCard(
          badge: 'OT',
          label: 'Überstunden',
          value: '${overtimeHours.toStringAsFixed(2)} h',
          color: const PdfColor.fromInt(0xFFE67E22),
          lightBg: lightBg,
        ),
      ),
    ];

    if (settings.hourlyRate > 0) {
      cards.addAll([
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: _summaryCard(
            badge: settings.currency,
            label: 'Gesamtlohn',
            value: currencyFmt.format(totalWage),
            color: success,
            lightBg: lightBg,
          ),
        ),
      ]);
    }

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: cards,
    );
  }

  static pw.Widget _buildShiftPlanSummary({
    required int shiftCount,
    required double totalHours,
    required int employeeCount,
    required int teamCount,
    required PdfColor primary,
    required PdfColor accent,
    required PdfColor lightBg,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _summaryCard(
            badge: 'SCH',
            label: 'Schichten',
            value: '$shiftCount',
            color: primary,
            lightBg: lightBg,
          ),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: _summaryCard(
            badge: 'STD',
            label: 'Geplante Stunden',
            value: '${totalHours.toStringAsFixed(2)} h',
            color: accent,
            lightBg: lightBg,
          ),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: _summaryCard(
            badge: 'MA',
            label: 'Mitarbeiter',
            value: '$employeeCount',
            color: const PdfColor.fromInt(0xFF2E7D32),
            lightBg: lightBg,
          ),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: _summaryCard(
            badge: 'TEAM',
            label: 'Teams',
            value: '$teamCount',
            color: const PdfColor.fromInt(0xFF6A1B9A),
            lightBg: lightBg,
          ),
        ),
      ],
    );
  }

  static pw.Widget _summaryCard({
    required String badge,
    required String label,
    required String value,
    required PdfColor color,
    required PdfColor lightBg,
  }) {
    return pw.Container(
      height: 74,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: lightBg,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: color, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Text(
                  label,
                  style: const pw.TextStyle(
                    fontSize: 7,
                    color: PdfColors.grey700,
                  ),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: pw.BoxDecoration(
                  color: color,
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Text(
                  badge,
                  style: pw.TextStyle(
                    fontSize: 6,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
              ),
            ],
          ),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 12, fontWeight: pw.FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  static pw.Widget _buildEntriesTable(
    List<WorkEntry> entries,
    UserSettings settings,
    PdfColor primary,
    PdfColor accent,
    PdfColor lightBg,
  ) {
    const headerStyle = pw.TextStyle(fontSize: 9, color: PdfColors.white);
    const cellStyle = pw.TextStyle(fontSize: 9, color: PdfColors.grey800);
    final boldCell = pw.TextStyle(
        fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey900);

    final headers = [
      'Datum',
      'Wochentag',
      'Beginn',
      'Ende',
      'Pause (min)',
      'Stunden',
      'Notiz'
    ];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Zeiterfassung',
            style: pw.TextStyle(
                fontSize: 14, fontWeight: pw.FontWeight.bold, color: primary)),
        pw.SizedBox(height: 6),
        pw.Table(
          columnWidths: {
            0: const pw.FixedColumnWidth(60),
            1: const pw.FixedColumnWidth(65),
            2: const pw.FixedColumnWidth(45),
            3: const pw.FixedColumnWidth(45),
            4: const pw.FixedColumnWidth(55),
            5: const pw.FixedColumnWidth(55),
            6: const pw.FlexColumnWidth(),
          },
          border: const pw.TableBorder(
            horizontalInside:
                pw.BorderSide(color: PdfColors.grey200, width: 0.5),
          ),
          children: [
            // Header row
            pw.TableRow(
              decoration: pw.BoxDecoration(color: primary),
              children: headers
                  .map((h) => pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 6, vertical: 8),
                        child: pw.Text(h, style: headerStyle),
                      ))
                  .toList(),
            ),
            // Data rows
            ...entries.asMap().entries.map((entry) {
              final i = entry.key;
              final e = entry.value;
              final bg = i.isEven ? PdfColors.white : lightBg;
              return pw.TableRow(
                decoration: pw.BoxDecoration(color: bg),
                children: [
                  _cell(DateFormat('dd.MM.yy').format(e.date), cellStyle),
                  _cell(_weekdayShort(e.date.weekday), cellStyle),
                  _cell(_timeFormat.format(e.startTime), cellStyle),
                  _cell(_timeFormat.format(e.endTime), cellStyle),
                  _cell(e.breakMinutes.toInt().toString(), cellStyle),
                  _cell('${e.workedHours.toStringAsFixed(2)} h', boldCell),
                  _cell(e.note ?? '–', cellStyle),
                ],
              );
            }),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildShiftPlanTable({
    required List<Shift> shifts,
    required PdfColor primary,
    required PdfColor lightBg,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Planansicht',
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: primary,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
          headerDecoration: pw.BoxDecoration(color: primary),
          cellStyle: const pw.TextStyle(fontSize: 8.5),
          rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
          oddRowDecoration: pw.BoxDecoration(color: lightBg),
          cellAlignment: pw.Alignment.centerLeft,
          columnWidths: {
            0: const pw.FixedColumnWidth(58),
            1: const pw.FixedColumnWidth(58),
            2: const pw.FixedColumnWidth(44),
            3: const pw.FixedColumnWidth(44),
            4: const pw.FixedColumnWidth(44),
            5: const pw.FixedColumnWidth(46),
            6: const pw.FixedColumnWidth(78),
            7: const pw.FlexColumnWidth(1.1),
            8: const pw.FixedColumnWidth(76),
            9: const pw.FixedColumnWidth(58),
            10: const pw.FlexColumnWidth(),
          },
          headers: const [
            'Datum',
            'Wochentag',
            'Beginn',
            'Ende',
            'Pause',
            'Stunden',
            'Mitarbeiter',
            'Titel',
            'Team',
            'Status',
            'Notiz',
          ],
          data: shifts
              .map((shift) => [
                    DateFormat('dd.MM.yyyy').format(shift.startTime),
                    _weekdayShort(shift.startTime.weekday),
                    _timeFormat.format(shift.startTime),
                    _timeFormat.format(shift.endTime),
                    shift.breakMinutes.toStringAsFixed(0),
                    shift.workedHours.toStringAsFixed(2),
                    shift.employeeName,
                    shift.title,
                    shift.team ?? '–',
                    shift.status.label,
                    shift.notes ?? '–',
                  ])
              .toList(growable: false),
        ),
      ],
    );
  }

  static pw.Widget _cell(String text, pw.TextStyle style) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: pw.Text(text, style: style),
      );

  static pw.Widget _buildWageSection(
    double totalHours,
    UserSettings settings,
    PdfColor primary,
    PdfColor accent,
    PdfColor lightBg,
  ) {
    final currencyFmt = NumberFormat.currency(
        locale: 'de_DE', symbol: settings.currency, decimalDigits: 2);
    final gross = totalHours * settings.hourlyRate;

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: lightBg,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: primary, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Lohnabrechnung',
              style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: primary)),
          pw.SizedBox(height: 10),
          _wageRow('Gearbeitete Stunden', '${totalHours.toStringAsFixed(2)} h',
              false, primary),
          _wageRow('Stundenlohn', currencyFmt.format(settings.hourlyRate),
              false, primary),
          pw.Divider(color: primary),
          _wageRow('Bruttolohn', currencyFmt.format(gross), true, primary),
        ],
      ),
    );
  }

  static pw.Widget _wageRow(
      String label, String value, bool bold, PdfColor primary) {
    final style = bold
        ? pw.TextStyle(
            fontWeight: pw.FontWeight.bold, fontSize: 12, color: primary)
        : const pw.TextStyle(fontSize: 10, color: PdfColors.grey700);

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: style),
          pw.Text(value, style: style),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(
    pw.Context context,
    PdfColor primary, {
    String label = 'Arbeitszeiterfassung',
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
          border: pw.Border(
              top: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label,
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
          pw.Text('Seite ${context.pageNumber} / ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
        ],
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  static String _weekdayShort(int weekday) {
    const days = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    return days[(weekday - 1).clamp(0, 6)];
  }

  static String _monthName(int month) {
    const months = [
      'Januar',
      'Februar',
      'März',
      'April',
      'Mai',
      'Juni',
      'Juli',
      'August',
      'September',
      'Oktober',
      'November',
      'Dezember'
    ];
    return months[(month - 1).clamp(0, 11)];
  }

  // ── Personal-Bereich: Lohnabrechnung & Personalkosten ───────────────────

  static Future<pw.ThemeData> _loadFonts() async {
    final base = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );
    final italic = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Italic.ttf'),
    );
    return pw.ThemeData.withFont(base: base, bold: bold, italic: italic);
  }

  /// PDF-Lohnabrechnung – **RICHTWERT**, keine offizielle Abrechnung.
  static Future<Uint8List> generatePayrollReport({
    required PayrollRecord record,
    required String employeeName,
  }) async {
    final pdf = pw.Document(theme: await _loadFonts());
    final eur =
        NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);
    String money(int cents) => eur.format(cents / 100);
    final period = '${_monthName(record.periodMonth)} ${record.periodYear}';

    const primary = PdfColor.fromInt(0xFF1E3A5F);
    const accent = PdfColor.fromInt(0xFF2E86AB);
    const lightBg = PdfColor.fromInt(0xFFF5F7FA);
    const success = PdfColor.fromInt(0xFF27AE60);
    const warn = PdfColor.fromInt(0xFFA76E00);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => _buildPayrollHeader(
          employeeName: employeeName,
          period: period,
          kindLabel: record.kind.label,
          taxLabel: record.taxClass.label,
          primary: primary,
          accent: accent,
        ),
        footer: (context) => _buildFooter(context, primary),
        build: (context) => [
          _disclaimerBanner(warn),
          pw.SizedBox(height: 12),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _summaryCard(
                  badge: 'BRT',
                  label: 'Bruttolohn',
                  value: money(record.grossCents),
                  color: primary,
                  lightBg: lightBg,
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _summaryCard(
                  badge: 'NET',
                  label: 'Nettolohn',
                  value: money(record.netCents),
                  color: success,
                  lightBg: lightBg,
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _summaryCard(
                  badge: 'AG',
                  label: 'AG-Gesamtkosten',
                  value: money(record.employerTotalCents),
                  color: accent,
                  lightBg: lightBg,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          _payrollTable(
            record: record,
            money: money,
            primary: primary,
          ),
        ],
      ),
    );
    return pdf.save();
  }

  /// PDF-Bericht der Personalkosten (pro Mitarbeiter oder pro Standort).
  static Future<Uint8List> generatePersonnelCostReport({
    required List<PersonnelCostRow> rows,
    required String rangeLabel,
    required String title,
  }) async {
    final pdf = pw.Document(theme: await _loadFonts());
    final eur =
        NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);
    String money(int cents) => eur.format(cents / 100);
    final totalHours = rows.fold<double>(0, (sum, r) => sum + r.workedHours);
    final totalLabor = rows.fold<int>(0, (sum, r) => sum + r.laborCostCents);
    final totalEmployer =
        rows.fold<int>(0, (sum, r) => sum + r.employerTotalCents);

    const primary = PdfColor.fromInt(0xFF1E3A5F);
    const accent = PdfColor.fromInt(0xFF2E86AB);
    const lightBg = PdfColor.fromInt(0xFFF5F7FA);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => _buildSimpleHeader(
          title: title,
          subtitle: rangeLabel,
          primary: primary,
          accent: accent,
        ),
        footer: (context) => _buildFooter(context, primary),
        build: (context) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _summaryCard(
                  badge: 'STD',
                  label: 'Gesamtstunden',
                  value: '${totalHours.toStringAsFixed(2)} h',
                  color: accent,
                  lightBg: lightBg,
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _summaryCard(
                  badge: 'KOST',
                  label: 'Personalkosten',
                  value: money(totalLabor),
                  color: primary,
                  lightBg: lightBg,
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _summaryCard(
                  badge: 'AG',
                  label: 'AG-Gesamtkosten',
                  value: money(totalEmployer),
                  color: const PdfColor.fromInt(0xFF2E7D32),
                  lightBg: lightBg,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          _costTable(
            rows: rows,
            money: money,
            primary: primary,
            lightBg: lightBg,
          ),
        ],
      ),
    );
    return pdf.save();
  }

  static pw.Widget _disclaimerBanner(PdfColor warn) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFFFF8E1),
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: warn, width: 1),
      ),
      child: pw.Text(
        PayrollResult.disclaimer,
        style: pw.TextStyle(
          fontSize: 9,
          color: warn,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  static pw.Widget _buildPayrollHeader({
    required String employeeName,
    required String period,
    required String kindLabel,
    required String taxLabel,
    required PdfColor primary,
    required PdfColor accent,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: primary,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      margin: const pw.EdgeInsets.only(bottom: 16),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'LOHNABRECHNUNG (RICHTWERT)',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                '$employeeName · $period',
                style: pw.TextStyle(color: accent, fontSize: 12),
              ),
              pw.Text(
                '$kindLabel · $taxLabel',
                style: const pw.TextStyle(color: PdfColors.white, fontSize: 9),
              ),
            ],
          ),
          pw.Text(
            'Erstellt: ${DateFormat('dd.MM.yyyy', 'de_DE').format(DateTime.now())}',
            style: const pw.TextStyle(color: PdfColors.white, fontSize: 9),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSimpleHeader({
    required String title,
    required String subtitle,
    required PdfColor primary,
    required PdfColor accent,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: primary,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      margin: const pw.EdgeInsets.only(bottom: 16),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                subtitle,
                style: pw.TextStyle(color: accent, fontSize: 12),
              ),
            ],
          ),
          pw.Text(
            'Erstellt: ${DateFormat('dd.MM.yyyy', 'de_DE').format(DateTime.now())}',
            style: const pw.TextStyle(color: PdfColors.white, fontSize: 9),
          ),
        ],
      ),
    );
  }

  static pw.Widget _payrollTable({
    required PayrollRecord record,
    required String Function(int) money,
    required PdfColor primary,
  }) {
    pw.TableRow line(String label, String value,
        {bool bold = false, PdfColor? color}) {
      final style = pw.TextStyle(
        fontSize: 10,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: color ?? PdfColors.grey800,
      );
      return pw.TableRow(children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: pw.Text(label, style: style),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: pw.Text(value, style: style, textAlign: pw.TextAlign.right),
        ),
      ]);
    }

    pw.Widget section(String title, List<pw.TableRow> body) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: primary,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Table(
              columnWidths: {
                0: const pw.FlexColumnWidth(2.2),
                1: const pw.FlexColumnWidth(1),
              },
              border: const pw.TableBorder(
                horizontalInside:
                    pw.BorderSide(color: PdfColors.grey200, width: 0.5),
              ),
              children: body,
            ),
          ],
        );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        section('Arbeitnehmer', [
          line('Bruttolohn', money(record.grossCents), bold: true),
          line('Lohnsteuer (Richtwert)', '- ${money(record.incomeTaxCents)}'),
          if (record.soliCents > 0)
            line('Solidaritätszuschlag', '- ${money(record.soliCents)}'),
          if (record.churchTaxCents > 0)
            line('Kirchensteuer', '- ${money(record.churchTaxCents)}'),
          line('Krankenversicherung (AN)',
              '- ${money(record.healthEmployeeCents)}'),
          line('Pflegeversicherung (AN)',
              '- ${money(record.careEmployeeCents)}'),
          line('Rentenversicherung (AN)',
              '- ${money(record.pensionEmployeeCents)}'),
          line('Arbeitslosenvers. (AN)',
              '- ${money(record.unemploymentEmployeeCents)}'),
          line('Nettolohn', money(record.netCents),
              bold: true, color: const PdfColor.fromInt(0xFF27AE60)),
        ]),
        pw.SizedBox(height: 14),
        section('Arbeitgeber', [
          line('Krankenversicherung (AG)', money(record.healthEmployerCents)),
          line('Pflegeversicherung (AG)', money(record.careEmployerCents)),
          line('Rentenversicherung (AG)', money(record.pensionEmployerCents)),
          line('Arbeitslosenvers. (AG)',
              money(record.unemploymentEmployerCents)),
          line('Arbeitgeber-Gesamtkosten', money(record.employerTotalCents),
              bold: true, color: primary),
        ]),
      ],
    );
  }

  static pw.Widget _costTable({
    required List<PersonnelCostRow> rows,
    required String Function(int) money,
    required PdfColor primary,
    required PdfColor lightBg,
  }) {
    const headerStyle = pw.TextStyle(fontSize: 9, color: PdfColors.white);
    const cellStyle = pw.TextStyle(fontSize: 9, color: PdfColors.grey800);
    final headers = [
      'Bezeichnung',
      'Stunden',
      'Personalkosten',
      'AG-Gesamtkosten',
    ];

    return pw.Table(
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FixedColumnWidth(60),
        2: const pw.FixedColumnWidth(90),
        3: const pw.FixedColumnWidth(95),
      },
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
      ),
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: primary),
          children: headers
              .map((h) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 6, vertical: 8),
                    child: pw.Text(h, style: headerStyle),
                  ))
              .toList(),
        ),
        ...rows.asMap().entries.map((entry) {
          final i = entry.key;
          final row = entry.value;
          final bg = i.isEven ? PdfColors.white : lightBg;
          return pw.TableRow(
            decoration: pw.BoxDecoration(color: bg),
            children: [
              _cell(row.label, cellStyle),
              _cell('${row.workedHours.toStringAsFixed(2)} h', cellStyle),
              _cell(money(row.laborCostCents), cellStyle),
              _cell(
                row.employerTotalCents > 0
                    ? money(row.employerTotalCents)
                    : '–',
                cellStyle,
              ),
            ],
          );
        }),
      ],
    );
  }
}
