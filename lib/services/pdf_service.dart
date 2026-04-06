// lib/services/pdf_service.dart

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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

  static pw.Widget _buildFooter(pw.Context context, PdfColor primary) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
          border: pw.Border(
              top: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Arbeitszeiterfassung',
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
}
