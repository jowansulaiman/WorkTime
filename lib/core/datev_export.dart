import '../models/finance_models.dart';

/// Konfiguration des DATEV-EXTF-Exports (vom Steuerberater vorgegeben).
///
/// **DATEV-1:** org-weites Firestore-Singleton
/// `organizations/{orgId}/financeConfig/datev` (admin-only laut Rules —
/// bewusst EIGENE Collection statt des generischen `config/{configId}`-Blocks,
/// dessen sameOrg-Read würde Berater-/Mandantennummer allen Org-Mitgliedern
/// zeigen). Der lokale SharedPreferences-Spiegel (`datev_config`) bleibt
/// Fallback bzw. Speicher im local-Modus. Dual serialisiert (Kopplung #1):
/// [toFirestoreMap]/[fromFirestore] camelCase, [toMap]/[fromMap] snake_case.
class DatevExportConfig {
  const DatevExportConfig({
    this.schemaVersion = 1,
    this.consultantNumber = '',
    this.clientNumber = '',
    this.accountLength = 4,
    this.defaultContraAccount = '9000',
    this.designation = '',
    this.revenueAccountByRate = const {},
  });

  /// Feste Doc-ID des Firestore-Singletons
  /// `organizations/{orgId}/financeConfig/datev`.
  static const String firestoreDocId = 'datev';

  /// Schema-Version der persistierten Config (Leitplanke: persistierte
  /// DATEV-Strukturen tragen `schemaVersion`, int ab 1; Leser parsen tolerant
  /// mit Default 1) — hält spätere Format-Änderungen migrierbar.
  final int schemaVersion;

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

  /// **P2.0** — USt-Satz (ganze Prozent) → CostType-/Erlöskonto-ID für die
  /// Tagesabschluss-Buchung (`postDailyClosing`). Explizite Zuordnung statt
  /// Namens-Heuristik; persistiert, damit der Admin sie nur einmal setzt.
  final Map<int, String> revenueAccountByRate;

  /// **DATEV-1:** Ob überhaupt fachliche Werte gepflegt sind (≠ reiner Default).
  /// Steuert die Lokal→Cloud-Migration: ein unkonfiguriertes Gerät legt KEIN
  /// leeres Cloud-Singleton an und überschreibt beim Adoptieren keinen bereits
  /// konfigurierten lokalen Stand (verhindert stillen Verlust der Berater-/
  /// Mandantennummer bei Mehr-Geräte-Login).
  bool get isConfigured =>
      consultantNumber.trim().isNotEmpty ||
      clientNumber.trim().isNotEmpty ||
      revenueAccountByRate.isNotEmpty;

  Map<String, dynamic> toMap() => {
        'schema_version': schemaVersion,
        'consultant_number': consultantNumber,
        'client_number': clientNumber,
        'account_length': accountLength,
        'default_contra_account': defaultContraAccount,
        'designation': designation,
        // JSON-Keys sind Strings -> Satz als String serialisieren.
        'revenue_account_by_rate':
            revenueAccountByRate.map((k, v) => MapEntry('$k', v)),
      };

  factory DatevExportConfig.fromMap(Map<String, dynamic> map) {
    return DatevExportConfig(
      schemaVersion: _toIntOr(map['schema_version'], 1),
      consultantNumber: (map['consultant_number'] ?? '').toString(),
      clientNumber: (map['client_number'] ?? '').toString(),
      accountLength: _toIntOr(map['account_length'], 4).clamp(4, 8),
      defaultContraAccount:
          (map['default_contra_account'] ?? '9000').toString(),
      designation: (map['designation'] ?? '').toString(),
      revenueAccountByRate: _parseRateMap(map['revenue_account_by_rate']),
    );
  }

  /// camelCase-Spiegel für das Firestore-Singleton (DATEV-1). Das `orgId`-Feld
  /// (Rules-Pin) und `updatedAt` schreibt der `FirestoreService` — die Config
  /// selbst bleibt org-frei.
  Map<String, dynamic> toFirestoreMap() => {
        'schemaVersion': schemaVersion,
        'consultantNumber': consultantNumber,
        'clientNumber': clientNumber,
        'accountLength': accountLength,
        'defaultContraAccount': defaultContraAccount,
        'designation': designation,
        // Firestore-Map-Keys sind Strings -> Satz als String serialisieren.
        'revenueAccountByRate':
            revenueAccountByRate.map((k, v) => MapEntry('$k', v)),
      };

  /// Doc-ID kommt konventionsgemäß separat (wird hier nicht gespeichert —
  /// das Singleton heißt immer [firestoreDocId]).
  factory DatevExportConfig.fromFirestore(
    String id,
    Map<String, dynamic> map,
  ) {
    return DatevExportConfig(
      schemaVersion: _toIntOr(map['schemaVersion'], 1),
      consultantNumber: (map['consultantNumber'] ?? '').toString(),
      clientNumber: (map['clientNumber'] ?? '').toString(),
      accountLength: _toIntOr(map['accountLength'], 4).clamp(4, 8),
      defaultContraAccount: (map['defaultContraAccount'] ?? '9000').toString(),
      designation: (map['designation'] ?? '').toString(),
      revenueAccountByRate: _parseRateMap(map['revenueAccountByRate']),
    );
  }

  static int _toIntOr(Object? raw, int fallback) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse('${raw ?? ''}') ?? fallback;
  }

  static Map<int, String> _parseRateMap(Object? rawRates) {
    final rateMap = <int, String>{};
    if (rawRates is Map) {
      rawRates.forEach((k, v) {
        final rate = int.tryParse('$k');
        if (rate != null && v != null && '$v'.isNotEmpty) {
          rateMap[rate] = '$v';
        }
      });
    }
    return rateMap;
  }

  DatevExportConfig copyWith({
    int? schemaVersion,
    String? consultantNumber,
    String? clientNumber,
    int? accountLength,
    String? defaultContraAccount,
    String? designation,
    Map<int, String>? revenueAccountByRate,
  }) {
    return DatevExportConfig(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      consultantNumber: consultantNumber ?? this.consultantNumber,
      clientNumber: clientNumber ?? this.clientNumber,
      accountLength: accountLength ?? this.accountLength,
      defaultContraAccount: defaultContraAccount ?? this.defaultContraAccount,
      designation: designation ?? this.designation,
      revenueAccountByRate: revenueAccountByRate ?? this.revenueAccountByRate,
    );
  }
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
    // DATEV-3 Deterministik-Fix: TOTALE Ordnung nach (date, id). Dart-`sort`
    // ist instabil — bei gleichem Datum hinge die Reihenfolge sonst an der
    // Eingangsreihenfolge und der SHA-256 der Datei wäre nicht reproduzierbar
    // (falsche „Journal verändert"-Warnungen im Rebuild-Vergleich).
    final rows = entries.where((e) => e.date.year == year).toList()
      ..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        if (byDate != 0) return byDate;
        return (a.id ?? '').compareTo(b.id ?? '');
      });

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
