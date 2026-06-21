import '../models/shift.dart';

/// Reiner, dependency-freier iCalendar-Builder (RFC 5545) für Schichtpläne.
///
/// Adaptiert aus AllTecs `ical_schedule_export`. Erzeugt eine `.ics`-Datei, die
/// Mitarbeiter in ihrem Handy-Kalender abonnieren/importieren können. Zeiten
/// werden als „floating" lokale Zeit (ohne `Z`) geschrieben, damit sie in der
/// lokalen Zeitzone des Geräts erscheinen.
class IcalExport {
  const IcalExport._();

  static String buildShifts(
    List<Shift> shifts, {
    String prodId = '-//WorkTime//Schichtplan//DE',
  }) {
    final buffer = StringBuffer();
    // RFC 5545 schreibt CRLF als Zeilentrenner vor.
    void line(String value) => buffer.write('$value\r\n');
    line('BEGIN:VCALENDAR');
    line('VERSION:2.0');
    line('PRODID:$prodId');
    line('CALSCALE:GREGORIAN');
    for (final shift in shifts) {
      line('BEGIN:VEVENT');
      line('UID:${_uid(shift)}');
      line('DTSTAMP:${_fmt(shift.startTime)}');
      line('DTSTART:${_fmt(shift.startTime)}');
      line('DTEND:${_fmt(shift.endTime)}');
      line('SUMMARY:${_escape(_summary(shift))}');
      final location =
          shift.effectiveSiteLabel ?? shift.siteName ?? shift.location;
      if (location != null && location.trim().isNotEmpty) {
        line('LOCATION:${_escape(location)}');
      }
      final notes = shift.notes;
      if (notes != null && notes.trim().isNotEmpty) {
        line('DESCRIPTION:${_escape(notes)}');
      }
      line('END:VEVENT');
    }
    line('END:VCALENDAR');
    return buffer.toString();
  }

  static String _summary(Shift shift) {
    final employee = shift.employeeName.trim();
    final title = shift.title.trim();
    if (employee.isNotEmpty && title.isNotEmpty) return '$title – $employee';
    return title.isNotEmpty ? title : employee;
  }

  static String _uid(Shift shift) {
    final base = shift.id ??
        '${shift.startTime.millisecondsSinceEpoch}-${shift.employeeName}';
    return '$base@worktime';
  }

  static String _fmt(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}${two(dt.month)}${two(dt.day)}'
        'T${two(dt.hour)}${two(dt.minute)}${two(dt.second)}';
  }

  static String _escape(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('\r\n', '\\n')
      .replaceAll('\r', '\\n')
      .replaceAll('\n', '\\n')
      .replaceAll(',', '\\,')
      .replaceAll(';', '\\;');
}
