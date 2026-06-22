import '../models/finance_models.dart';

/// Konfiguration des DATEV-EXTF-Exports (vom Steuerberater vorgegeben).
class DatevExportConfig {
  const DatevExportConfig({
    this.consultantNumber = '',
    this.clientNumber = '',
    this.accountLength = 4,
    this.defaultContraAccount = '9000',
    this.designation = '',
  });

  /// Berater-Nummer.
  final String consultantNumber;

  /// Mandanten-Nummer.
  final String clientNumber;

  /// Sachkontenlänge (4–8).
  final int accountLength;

  /// Festes Gegenkonto (Vereinfachung – ohne echte Gegenbuchung je Beleg).
  final String defaultContraAccount;

  /// Freie Bezeichnung des Stapels.
  final String designation;
}

/// Erzeugt einen **DATEV-EXTF-Buchungsstapel** (Format 700) aus dem
/// Kosten-Journal.
///
/// **Bewusste Vereinfachung** (wie das Vorbild): Konto = Kostenart-Nummer,
/// festes Gegenkonto, keine Steuerschlüssel. Das Ergebnis ist ein
/// importierbarer Stapel als **Richtwert** – der Steuerberater prüft vor der
/// Verbuchung. CRLF-Zeilenenden + Semikolon-Trenner (DATEV-Konvention).
class DatevExport {
  const DatevExport._();

  static const String disclaimer =
      'Vereinfachter DATEV-EXTF-Buchungsstapel (Konto = Kostenart-Nr, festes '
      'Gegenkonto, ohne Steuerschlüssel). Vor der Übergabe an den '
      'Steuerberater fachlich prüfen.';

  /// Kanonische DATEV-EXTF-Spalten (Format 700), Index = Spaltenposition − 1.
  static const List<String> fieldNames = [
    'Umsatz (ohne Soll/Haben-Kz)',
    'Soll/Haben-Kennzeichen',
    'WKZ Umsatz',
    'Kurs',
    'Basis-Umsatz',
    'WKZ Basis-Umsatz',
    'Konto',
    'Gegenkonto (ohne BU-Schlüssel)',
    'BU-Schlüssel',
    'Belegdatum',
    'Belegfeld 1',
    'Belegfeld 2',
    'Skonto',
    'Buchungstext',
    'Postensperre',
    'Diverse Adressnummer',
    'Geschäftspartnerbank',
    'Sachverhalt',
    'Zinssperre',
    'Beleglink',
    'Beleginfo - Art 1',
    'Beleginfo - Inhalt 1',
    'Beleginfo - Art 2',
    'Beleginfo - Inhalt 2',
    'Beleginfo - Art 3',
    'Beleginfo - Inhalt 3',
    'Beleginfo - Art 4',
    'Beleginfo - Inhalt 4',
    'Beleginfo - Art 5',
    'Beleginfo - Inhalt 5',
    'Beleginfo - Art 6',
    'Beleginfo - Inhalt 6',
    'Beleginfo - Art 7',
    'Beleginfo - Inhalt 7',
    'Beleginfo - Art 8',
    'Beleginfo - Inhalt 8',
    'KOST1 - Kostenstelle',
    'KOST2 - Kostenstelle',
  ];

  /// Spalten, die ohne Anführungszeichen geschrieben werden (Zahlen +
  /// Soll/Haben-Kennzeichen).
  static const Set<int> _unquotedColumns = {0, 1, 3, 4, 6, 7, 8, 9, 12};

  static String buildBuchungsstapel({
    required List<JournalEntry> entries,
    required Map<String, CostCenter> centersById,
    required Map<String, CostType> typesById,
    required int year,
    required DatevExportConfig config,
    required DateTime generatedAt,
  }) {
    final rows = entries.where((e) => e.date.year == year).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final from = rows.isEmpty ? DateTime(year) : rows.first.date;
    final to = rows.isEmpty ? DateTime(year, 12, 31) : rows.last.date;

    final buf = StringBuffer();

    // ── Kopfzeile (EXTF-Header, Format 700; gemischt quoted/unquoted) ──
    buf.write([
      _q('EXTF'),
      '700',
      '21',
      _q('Buchungsstapel'),
      '9',
      _stamp(generatedAt),
      '', '', '', '',
      config.consultantNumber,
      config.clientNumber,
      _ymd(DateTime(year)),
      '${config.accountLength}',
      _ymd(from),
      _ymd(to),
      _q(config.designation),
      '',
      '1', // Buchungstyp: Finanzbuchführung
      '0',
      '0',
      _q('EUR'),
      '', '', '', '', '', '', '', '',
    ].join(';'));
    buf.write('\r\n');

    // ── Spaltenüberschriften ──
    buf.write(fieldNames.map(_q).join(';'));
    buf.write('\r\n');

    // ── Datenzeilen ──
    for (final e in rows) {
      final center = centersById[e.costCenterId];
      final type = typesById[e.costTypeId];
      final cols = List<String>.filled(fieldNames.length, '');
      cols[0] = _amount(e.amountCents); // Umsatz (Betrag ohne Vorzeichen)
      cols[1] = e.amountCents >= 0 ? 'S' : 'H';
      cols[2] = 'EUR';
      cols[6] = _digits(type?.number ?? '');
      cols[7] = _digits(config.defaultContraAccount);
      cols[9] = _ddmm(e.date);
      cols[10] = _truncate(e.reference ?? '', 36);
      cols[13] = _truncate(e.description, 60);
      // KOST1/KOST2 sind alphanumerische Textfelder (quoted, nicht nur Ziffern).
      cols[36] = _truncate(center?.number ?? '', 36);
      cols[37] = _truncate(center?.costBearerRef ?? '', 36);
      buf.write([
        for (var i = 0; i < cols.length; i++) _formatCell(i, cols[i]),
      ].join(';'));
      buf.write('\r\n');
    }

    return buf.toString();
  }

  static String _formatCell(int index, String value) {
    if (value.isEmpty) return '';
    return _unquotedColumns.contains(index) ? value : _q(value);
  }

  static String _q(String s) => '"${s.replaceAll('"', '""')}"';

  /// Betrag (immer positiv) als deutsches Dezimal mit Komma, ohne Float-Drift.
  static String _amount(int cents) {
    final c = cents.abs();
    final whole = c ~/ 100;
    final frac = c % 100;
    return '$whole,${frac.toString().padLeft(2, '0')}';
  }

  static String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}';

  static String _ddmm(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}${d.month.toString().padLeft(2, '0')}';

  static String _stamp(DateTime d) =>
      '${_ymd(d)}'
      '${d.hour.toString().padLeft(2, '0')}'
      '${d.minute.toString().padLeft(2, '0')}'
      '${d.second.toString().padLeft(2, '0')}'
      '${d.millisecond.toString().padLeft(3, '0')}';

  static String _truncate(String s, int max) =>
      s.length <= max ? s : s.substring(0, max);
}
