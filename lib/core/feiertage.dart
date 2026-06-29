/// Gesetzliche Feiertage in Deutschland je **Bundesland** – rein, testbar,
/// dependency-frei (Plan §5.1, Audit-Korrektur H6).
///
/// Bewegliche Feste werden per **Oster-Computus** (Gauß/Meeus, gregorianisch)
/// berechnet, nicht aus statischen Jahres-Tabellen. Das Bundesland ist ein
/// **expliziter Parameter** (kommt aus `SiteDefinition.federalState` via
/// Primärstandort; Org-Default „Schleswig-Holstein" für die beiden Kieler
/// Filialen). SH-Spezifikum: Reformationstag (31.10.) ist dort seit 2018
/// gesetzlicher Feiertag.
library;

/// Normiert eine Bundesland-Bezeichnung (Name oder Kürzel) auf das 2-Buchstaben-
/// Kürzel. Unbekannt/leer → `'SH'` (Org-Default, beide Läden in Kiel).
String normalizeBundesland(String? input) {
  final raw = (input ?? '').trim().toLowerCase();
  if (raw.isEmpty) return 'SH';
  // Bereits ein Kürzel?
  const codes = {
    'bw', 'by', 'be', 'bb', 'hb', 'hh', 'he', 'mv',
    'ni', 'nw', 'rp', 'sl', 'sn', 'st', 'sh', 'th',
  };
  if (codes.contains(raw)) return raw.toUpperCase();
  // Namens-Präfixe (tolerant).
  if (raw.startsWith('baden')) return 'BW';
  if (raw.startsWith('bay')) return 'BY';
  if (raw.startsWith('berlin')) return 'BE';
  if (raw.startsWith('brand')) return 'BB';
  if (raw.startsWith('bremen')) return 'HB';
  if (raw.startsWith('hamburg')) return 'HH';
  if (raw.startsWith('hess')) return 'HE';
  if (raw.startsWith('meck')) return 'MV';
  if (raw.startsWith('nieders')) return 'NI';
  if (raw.startsWith('nordrhein') || raw.startsWith('nrw')) return 'NW';
  if (raw.startsWith('rhein')) return 'RP';
  if (raw.startsWith('saarl')) return 'SL';
  if (raw.startsWith('sachsen-anh') || raw.startsWith('sachsen anh')) {
    return 'ST';
  }
  if (raw.startsWith('sachsen')) return 'SN';
  if (raw.startsWith('schleswig')) return 'SH';
  if (raw.startsWith('thür') || raw.startsWith('thur')) return 'TH';
  return 'SH';
}

/// Ostersonntag (gregorianisch) für [year] – Meeus/Jones/Butcher-Algorithmus.
DateTime ostersonntag(int year) {
  final a = year % 19;
  final b = year ~/ 100;
  final c = year % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final monat = (h + l - 7 * m + 114) ~/ 31;
  final tag = ((h + l - 7 * m + 114) % 31) + 1;
  return DateTime(year, monat, tag, 12);
}

DateTime _d(int y, int m, int day) => DateTime(y, m, day, 12);
DateTime _plus(DateTime base, int days) =>
    DateTime(base.year, base.month, base.day + days, 12);

/// Buß- und Bettag (nur SN): Mittwoch vor dem 23.11.
DateTime _bussUndBettag(int year) {
  var d = _d(year, 11, 22);
  // Auf den vorangehenden Mittwoch (weekday 3) zurückgehen.
  while (d.weekday != DateTime.wednesday) {
    d = _plus(d, -1);
  }
  return d;
}

/// Alle gesetzlichen Feiertage in [year] für [bundesland] (Kürzel oder Name),
/// jeweils auf lokale Mittagszeit normiert.
Set<DateTime> feiertageImJahr(int year, {required String bundesland}) {
  final bl = normalizeBundesland(bundesland);
  final ostern = ostersonntag(year);
  final tage = <DateTime>{
    // Bundesweit.
    _d(year, 1, 1), // Neujahr
    _plus(ostern, -2), // Karfreitag
    _plus(ostern, 1), // Ostermontag
    _d(year, 5, 1), // Tag der Arbeit
    _plus(ostern, 39), // Christi Himmelfahrt
    _plus(ostern, 50), // Pfingstmontag
    _d(year, 10, 3), // Tag der Deutschen Einheit
    _d(year, 12, 25), // 1. Weihnachtstag
    _d(year, 12, 26), // 2. Weihnachtstag
  };

  // Heilige Drei Könige (6.1.): BW, BY, ST.
  if (bl == 'BW' || bl == 'BY' || bl == 'ST') tage.add(_d(year, 1, 6));
  // Internationaler Frauentag (8.3.): BE (seit 2019), MV (seit 2023).
  if ((bl == 'BE' && year >= 2019) || (bl == 'MV' && year >= 2023)) {
    tage.add(_d(year, 3, 8));
  }
  // Fronleichnam (Ostern+60): BW, BY, HE, NW, RP, SL.
  if (const {'BW', 'BY', 'HE', 'NW', 'RP', 'SL'}.contains(bl)) {
    tage.add(_plus(ostern, 60));
  }
  // Mariä Himmelfahrt (15.8.): SL.
  if (bl == 'SL') tage.add(_d(year, 8, 15));
  // Weltkindertag (20.9.): TH (seit 2019).
  if (bl == 'TH' && year >= 2019) tage.add(_d(year, 9, 20));
  // Reformationstag (31.10.): BB, MV, SN, ST, TH immer; HB, HH, NI, SH seit 2018.
  if (const {'BB', 'MV', 'SN', 'ST', 'TH'}.contains(bl) ||
      (const {'HB', 'HH', 'NI', 'SH'}.contains(bl) && year >= 2018)) {
    tage.add(_d(year, 10, 31));
  }
  // Allerheiligen (1.11.): BW, BY, NW, RP, SL.
  if (const {'BW', 'BY', 'NW', 'RP', 'SL'}.contains(bl)) {
    tage.add(_d(year, 11, 1));
  }
  // Buß- und Bettag: nur SN.
  if (bl == 'SN') tage.add(_bussUndBettag(year));

  return tage;
}

/// Ob [date] in [bundesland] ein gesetzlicher Feiertag ist.
bool istFeiertag(DateTime date, {required String bundesland}) {
  final norm = DateTime(date.year, date.month, date.day, 12);
  return feiertageImJahr(date.year, bundesland: bundesland).contains(norm);
}
