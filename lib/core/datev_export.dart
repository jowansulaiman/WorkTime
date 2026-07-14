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
    this.paymentAccountByMethod = const {},
    this.taxKeyByRate = const {},
    this.contraAccountBySiteId = const {},
    this.skrProfile = '',
    this.cashDifferenceCostTypeId,
    this.personnelCostTypeId,
    this.wareneinsatzCostTypeId,
  });

  /// Feste Doc-ID des Firestore-Singletons
  /// `organizations/{orgId}/financeConfig/datev`.
  static const String firestoreDocId = 'datev';

  /// **DATEV-5:** Vorschlags-BU-Schlüssel je USt-Satz — reine **Vorbelegung**
  /// der Admin-UI, NICHT der Default-Wert von [taxKeyByRate] (der bleibt leer).
  /// Die Zuordnung ist steuerlich anzunehmen (SKR03/04: 19 % → '3', 7 % → '2')
  /// und **vom Steuerberater zu bestätigen**.
  static const Map<int, String> taxKeySuggestions = {19: '3', 7: '2'};

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

  /// **DATEV-5** — Zahlart-Token (bar/Karte/…) → CostType-/Konto-ID für die
  /// Zahlart-Transitzeilen (`buildPaymentTransitEntries`). Leer = kein
  /// Transit-Mapping (Feature aus). Map-Keys sind bereits Strings.
  final Map<String, String> paymentAccountByMethod;

  /// **DATEV-5** — USt-Satz (ganze Prozent) → DATEV-BU-Schlüssel (Steuerschlüssel)
  /// für die BU-Spalte des EXTF-Exports. Leer = keine BU-Schlüssel (Spalte
  /// bleibt leer, abwärtskompatibel). Vorschläge in [taxKeySuggestions].
  final Map<int, String> taxKeyByRate;

  /// **DATEV-5** — Standort (`SiteDefinition.id`) → Gegenkonto für die
  /// Gegenkonto-Spalte des EXTF-Exports. Ohne Treffer greift
  /// [defaultContraAccount]. Map-Keys sind bereits Strings.
  final Map<String, String> contraAccountBySiteId;

  /// **DATEV-5** — SKR-Profil (z. B. „SKR03"/„SKR04") als reines Metadatum
  /// (Doku/Prüfung, fließt nicht in den Export).
  final String skrProfile;

  /// **DATEV-5** — explizite Kostenart-ID für Kassendifferenz-Buchungen
  /// (Primärquelle statt Namens-Heuristik). `null` = Heuristik-Fallback.
  final String? cashDifferenceCostTypeId;

  /// **DATEV-5** — explizite Kostenart-ID für Personalkosten-Buchungen.
  final String? personnelCostTypeId;

  /// **DATEV-5** — explizite Kostenart-ID für Wareneinsatz-Buchungen.
  final String? wareneinsatzCostTypeId;

  /// **DATEV-1:** Ob überhaupt fachliche Werte gepflegt sind (≠ reiner Default).
  /// Steuert die Lokal→Cloud-Migration: ein unkonfiguriertes Gerät legt KEIN
  /// leeres Cloud-Singleton an und überschreibt beim Adoptieren keinen bereits
  /// konfigurierten lokalen Stand (verhindert stillen Verlust der Berater-/
  /// Mandantennummer bei Mehr-Geräte-Login).
  bool get isConfigured =>
      consultantNumber.trim().isNotEmpty ||
      clientNumber.trim().isNotEmpty ||
      revenueAccountByRate.isNotEmpty ||
      paymentAccountByMethod.isNotEmpty ||
      taxKeyByRate.isNotEmpty ||
      contraAccountBySiteId.isNotEmpty ||
      skrProfile.trim().isNotEmpty ||
      (cashDifferenceCostTypeId ?? '').isNotEmpty ||
      (personnelCostTypeId ?? '').isNotEmpty ||
      (wareneinsatzCostTypeId ?? '').isNotEmpty;

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
        'payment_account_by_method': Map<String, String>.from(paymentAccountByMethod),
        'tax_key_by_rate': taxKeyByRate.map((k, v) => MapEntry('$k', v)),
        'contra_account_by_site_id':
            Map<String, String>.from(contraAccountBySiteId),
        'skr_profile': skrProfile,
        'cash_difference_cost_type_id': cashDifferenceCostTypeId,
        'personnel_cost_type_id': personnelCostTypeId,
        'wareneinsatz_cost_type_id': wareneinsatzCostTypeId,
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
      paymentAccountByMethod: _parseStringMap(map['payment_account_by_method']),
      taxKeyByRate: _parseRateMap(map['tax_key_by_rate']),
      contraAccountBySiteId: _parseStringMap(map['contra_account_by_site_id']),
      skrProfile: (map['skr_profile'] ?? '').toString(),
      cashDifferenceCostTypeId: _cleanId(map['cash_difference_cost_type_id']),
      personnelCostTypeId: _cleanId(map['personnel_cost_type_id']),
      wareneinsatzCostTypeId: _cleanId(map['wareneinsatz_cost_type_id']),
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
        'paymentAccountByMethod': Map<String, String>.from(paymentAccountByMethod),
        'taxKeyByRate': taxKeyByRate.map((k, v) => MapEntry('$k', v)),
        'contraAccountBySiteId':
            Map<String, String>.from(contraAccountBySiteId),
        'skrProfile': skrProfile,
        'cashDifferenceCostTypeId': cashDifferenceCostTypeId,
        'personnelCostTypeId': personnelCostTypeId,
        'wareneinsatzCostTypeId': wareneinsatzCostTypeId,
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
      paymentAccountByMethod: _parseStringMap(map['paymentAccountByMethod']),
      taxKeyByRate: _parseRateMap(map['taxKeyByRate']),
      contraAccountBySiteId: _parseStringMap(map['contraAccountBySiteId']),
      skrProfile: (map['skrProfile'] ?? '').toString(),
      cashDifferenceCostTypeId: _cleanId(map['cashDifferenceCostTypeId']),
      personnelCostTypeId: _cleanId(map['personnelCostTypeId']),
      wareneinsatzCostTypeId: _cleanId(map['wareneinsatzCostTypeId']),
    );
  }

  static int _toIntOr(Object? raw, int fallback) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse('${raw ?? ''}') ?? fallback;
  }

  /// `null`/leer -> null (nullable ID-Felder tolerant lesen).
  static String? _cleanId(Object? raw) {
    final s = (raw ?? '').toString().trim();
    return s.isEmpty ? null : s;
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

  /// String→String-Map tolerant lesen (leere Werte werden verworfen).
  static Map<String, String> _parseStringMap(Object? raw) {
    final out = <String, String>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        final key = '$k';
        if (key.isNotEmpty && v != null && '$v'.isNotEmpty) {
          out[key] = '$v';
        }
      });
    }
    return out;
  }

  DatevExportConfig copyWith({
    int? schemaVersion,
    String? consultantNumber,
    String? clientNumber,
    int? accountLength,
    String? defaultContraAccount,
    String? designation,
    Map<int, String>? revenueAccountByRate,
    Map<String, String>? paymentAccountByMethod,
    Map<int, String>? taxKeyByRate,
    Map<String, String>? contraAccountBySiteId,
    String? skrProfile,
    String? cashDifferenceCostTypeId,
    bool clearCashDifferenceCostTypeId = false,
    String? personnelCostTypeId,
    bool clearPersonnelCostTypeId = false,
    String? wareneinsatzCostTypeId,
    bool clearWareneinsatzCostTypeId = false,
  }) {
    return DatevExportConfig(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      consultantNumber: consultantNumber ?? this.consultantNumber,
      clientNumber: clientNumber ?? this.clientNumber,
      accountLength: accountLength ?? this.accountLength,
      defaultContraAccount: defaultContraAccount ?? this.defaultContraAccount,
      designation: designation ?? this.designation,
      revenueAccountByRate: revenueAccountByRate ?? this.revenueAccountByRate,
      paymentAccountByMethod:
          paymentAccountByMethod ?? this.paymentAccountByMethod,
      taxKeyByRate: taxKeyByRate ?? this.taxKeyByRate,
      contraAccountBySiteId:
          contraAccountBySiteId ?? this.contraAccountBySiteId,
      skrProfile: skrProfile ?? this.skrProfile,
      cashDifferenceCostTypeId: clearCashDifferenceCostTypeId
          ? null
          : (cashDifferenceCostTypeId ?? this.cashDifferenceCostTypeId),
      personnelCostTypeId: clearPersonnelCostTypeId
          ? null
          : (personnelCostTypeId ?? this.personnelCostTypeId),
      wareneinsatzCostTypeId: clearWareneinsatzCostTypeId
          ? null
          : (wareneinsatzCostTypeId ?? this.wareneinsatzCostTypeId),
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
      // DATEV-5: Gegenkonto standortabhängig (CostCenter→Site→Mapping), sonst
      // festes Default-Gegenkonto (abwärtskompatibel).
      cols[7] = _digits(_contraAccountFor(center?.siteId, config));
      // DATEV-5: BU-Schlüssel je USt-Satz (leer, wenn kein Satz/kein Mapping).
      cols[8] = _taxKeyFor(e.taxRatePercent, config);
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

  /// DATEV-5: Gegenkonto einer Zeile — standortspezifisch (via
  /// `contraAccountBySiteId`), sonst das feste [DatevExportConfig.defaultContraAccount].
  static String _contraAccountFor(String? siteId, DatevExportConfig config) {
    if (siteId != null) {
      final mapped = config.contraAccountBySiteId[siteId];
      if (mapped != null && mapped.trim().isNotEmpty) return mapped;
    }
    return config.defaultContraAccount;
  }

  /// DATEV-5: BU-Schlüssel (Steuerschlüssel) einer Zeile aus `taxKeyByRate`;
  /// ohne Satz oder ohne Mapping bleibt die BU-Spalte leer (abwärtskompatibel).
  static String _taxKeyFor(int? taxRatePercent, DatevExportConfig config) {
    if (taxRatePercent == null) return '';
    final key = config.taxKeyByRate[taxRatePercent];
    return (key ?? '').trim();
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
