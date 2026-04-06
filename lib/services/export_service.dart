import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';

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

    final stamp = DateFormat('yyyy-MM').format(DateTime(year, month));
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

  static String buildShiftPlanCsv({
    required List<Shift> shifts,
    required String rangeLabel,
    String? employeeLabel,
    String? teamLabel,
  }) {
    final buffer = StringBuffer('\uFEFF');
    final sortedShifts = [...shifts]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    buffer.writeln('Schichtplan Export');
    buffer.writeln('Zeitraum;${_escapeCsv(rangeLabel)}');
    if (employeeLabel != null && employeeLabel.trim().isNotEmpty) {
      buffer.writeln('Mitarbeiter;${_escapeCsv(employeeLabel)}');
    }
    if (teamLabel != null && teamLabel.trim().isNotEmpty) {
      buffer.writeln('Team;${_escapeCsv(teamLabel)}');
    }
    buffer.writeln();
    buffer.writeln(
      'Datum;Wochentag;Beginn;Ende;Pause (min);Stunden;Mitarbeiter;Titel;Team;Status;Notiz',
    );

    for (final shift in sortedShifts) {
      buffer.writeln([
        DateFormat('dd.MM.yyyy').format(shift.startTime),
        _weekdayShort(shift.startTime.weekday),
        DateFormat('HH:mm').format(shift.startTime),
        DateFormat('HH:mm').format(shift.endTime),
        shift.breakMinutes.toStringAsFixed(0),
        shift.workedHours.toStringAsFixed(2),
        shift.employeeName,
        shift.title,
        shift.team ?? '',
        shift.status.label,
        shift.notes ?? '',
      ].map(_escapeCsv).join(';'));
    }

    return buffer.toString();
  }

  static String _shiftPlanFileName({
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required String extension,
  }) {
    final startStamp = DateFormat('yyyy-MM-dd').format(rangeStart);
    final inclusiveEnd = rangeEnd.subtract(const Duration(days: 1));
    final endStamp = DateFormat('yyyy-MM-dd').format(
      inclusiveEnd.isBefore(rangeStart) ? rangeStart : inclusiveEnd,
    );
    final suffix =
        startStamp == endStamp ? startStamp : '$startStamp-bis-$endStamp';
    return 'schichtplan-$suffix.$extension';
  }

  static String _escapeCsv(String value) {
    final normalized = value.replaceAll('"', '""');
    if (normalized.contains(';') ||
        normalized.contains('"') ||
        normalized.contains('\n')) {
      return '"$normalized"';
    }
    return normalized;
  }

  static String _weekdayShort(int weekday) {
    const weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    return weekdays[(weekday - 1).clamp(0, 6)];
  }
}
