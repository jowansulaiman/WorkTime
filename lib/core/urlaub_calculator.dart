import '../models/absence_request.dart';
import '../models/sollzeit_profile.dart';
import '../models/urlaubsanpassung.dart';
import '../models/urlaubskonto_jahr.dart';
import 'abwesenheit_matrix.dart';
import 'feiertage.dart';

/// Quelle, aus der der kanonische Jahresurlaubsanspruch aufgelöst wurde
/// (Vorrangregel §5.1 des IDA-HR-Plans).
enum UrlaubstageQuelle {
  /// `SollzeitProfile.urlaubstageJahr` – kanonische Quelle (höchster Vorrang).
  sollzeitProfile,

  /// Altfeld `EmployeeProfile.annualVacationDays` (deprecated, M0-Fallback).
  mitarbeiterprofil,

  /// Altfeld `EmploymentContract.vacationDays` (deprecated, M0-Fallback).
  vertrag,

  /// Gesetzlicher Mindesturlaub – kein Wert hinterlegt.
  gesetzlicherMindesturlaub,
}

/// Ergebnis der Vorrang-Auflösung des Jahresurlaubs (Basis-Tage,
/// **5-Tage-Woche / vollzeitäquivalent** – Teilzeit-Umrechnung erst in M-U).
class UrlaubstageErgebnis {
  const UrlaubstageErgebnis({required this.tage, required this.quelle});

  final double tage;
  final UrlaubstageQuelle quelle;

  /// True, wenn der Wert noch aus einem deprecaten Altfeld stammt (Migration
  /// nach `SollzeitProfile.urlaubstageJahr` offen).
  bool get ausAltfeld =>
      quelle == UrlaubstageQuelle.mitarbeiterprofil ||
      quelle == UrlaubstageQuelle.vertrag;
}

/// Gesetzlicher Mindesturlaub bei 5-Tage-Woche (§3 BUrlG: 24 Werktage auf
/// 6-Tage-Basis = 20 Tage auf 5-Tage-Basis).
const double gesetzlicherMindesturlaub5Tage = 20;

/// Löst den **kanonischen Jahresurlaubsanspruch** (Basis-Tage) nach der
/// Vorrangregel §5.1 auf:
/// aktives [sollzeit] (dessen `urlaubstageJahr` – auch wenn = Default, denn die
/// **Existenz** des Profils ist das Signal) → sonst [annualVacationDays]
/// (Altfeld `EmployeeProfile`) → sonst [vertragVacationDays] (Altfeld
/// `EmploymentContract`) → sonst gesetzlicher Mindesturlaub.
///
/// **Audit-Korrektur B1:** verwendet die Altwerte **verbatim**, ohne
/// Teilzeit-Skalierung – sie sind bereits 5-Tage-basiert. Die Teilzeit-/
/// Anteils-Umrechnung passiert erst im UrlaubsReport (M-U).
UrlaubstageErgebnis resolveUrlaubstageJahr({
  SollzeitProfile? sollzeit,
  int? annualVacationDays,
  int? vertragVacationDays,
}) {
  if (sollzeit != null) {
    return UrlaubstageErgebnis(
      tage: sollzeit.urlaubstageJahr,
      quelle: UrlaubstageQuelle.sollzeitProfile,
    );
  }
  if (annualVacationDays != null) {
    return UrlaubstageErgebnis(
      tage: annualVacationDays.toDouble(),
      quelle: UrlaubstageQuelle.mitarbeiterprofil,
    );
  }
  if (vertragVacationDays != null) {
    return UrlaubstageErgebnis(
      tage: vertragVacationDays.toDouble(),
      quelle: UrlaubstageQuelle.vertrag,
    );
  }
  return const UrlaubstageErgebnis(
    tage: gesetzlicherMindesturlaub5Tage,
    quelle: UrlaubstageQuelle.gesetzlicherMindesturlaub,
  );
}

// ─────────────────────────── Urlaubskonto (M-U) ───────────────────────────

/// Urlaubskonto-Aufstellung eines Mitarbeiters für ein Kalenderjahr (Plan §5.2;
/// nicht persistiert – reines Wert-Objekt). Alle Werte in **Tagen** (double).
class UrlaubsReport {
  const UrlaubsReport({
    required this.jahr,
    required this.anspruchJahr,
    required this.vortragVorjahr,
    required this.vortragVerfallen,
    required this.genommen,
    required this.geplant,
  });

  final int jahr;

  /// Jahresanspruch (werktagsgenau + Teilzeit + §5(2)-Rundung, anteilig).
  final double anspruchJahr;
  final double vortragVorjahr;

  /// Verfallener Vortrag (nur bei dokumentierter Hinweisobliegenheit, §7(3)).
  final double vortragVerfallen;
  final double genommen;
  final double geplant;

  /// Gesamtanspruch = Anspruch + (Vortrag − Verfallen).
  double get anspruchGesamt => anspruchJahr + vortragVorjahr - vortragVerfallen;

  /// Resturlaub = Gesamt − genommen − geplant.
  double get resturlaub => anspruchGesamt - genommen - geplant;

  /// Resturlaub ohne die geplanten (noch offenen) Anträge.
  double get resturlaubOhneGeplant => anspruchGesamt - genommen;
}

double _round1(double v) => (v * 10).round() / 10;

/// §5(2) BUrlG: Bruchteile ≥ 0,5 Tage werden aufgerundet, sonst abgerundet.
double _rundeGesetzlich(double tage) {
  final ganz = tage.floor();
  return (tage - ganz) >= 0.5 ? ganz + 1.0 : ganz.toDouble();
}

/// Beschäftigte (volle) Monate im [jahr], gekappt auf Ein-/Austritt (Zwölftelung).
int beschaeftigteMonate(int jahr, {DateTime? hireDate, DateTime? exitDate}) {
  if (hireDate != null && hireDate.year > jahr) return 0;
  if (exitDate != null && exitDate.year < jahr) return 0;
  var von = 1, bis = 12;
  if (hireDate != null && hireDate.year == jahr) von = hireDate.month;
  if (exitDate != null && exitDate.year == jahr) bis = exitDate.month;
  final m = bis - von + 1;
  return m < 0 ? 0 : (m > 12 ? 12 : m);
}

/// Zählt **Werktage** (Soll > 0 laut [sollzeit], sonst Mo–Fr; ohne Feiertag) im
/// inklusiven Bereich [von]..[bis] innerhalb von [jahr]; [halbtags] zählt 0,5.
double werktageImBereich(
  DateTime von,
  DateTime bis, {
  required int jahr,
  required Set<DateTime> feiertage,
  SollzeitProfile? sollzeit,
  bool halbtags = false,
}) {
  var tage = 0.0;
  var d = DateTime(von.year, von.month, von.day, 12);
  final end = DateTime(bis.year, bis.month, bis.day, 12);
  while (!d.isAfter(end)) {
    if (d.year == jahr) {
      final istArbeitstag = sollzeit != null
          ? sollzeit.sollMinutesForWeekday(d.weekday) > 0
          : (d.weekday >= DateTime.monday && d.weekday <= DateTime.friday);
      final feiertag = feiertage.contains(DateTime(d.year, d.month, d.day, 12));
      if (istArbeitstag && !feiertag) {
        tage += halbtags ? 0.5 : 1.0;
      }
    }
    d = DateTime(d.year, d.month, d.day + 1, 12);
  }
  return tage;
}

/// Urlaubswirksame **Werktage** einer Abwesenheit im [jahr]: Tage mit Soll > 0
/// (laut [sollzeit], sonst Mo–Fr) und ohne Feiertag; halbtägig = 0,5.
double genommeneUrlaubstage(
  AbsenceRequest absence, {
  required int jahr,
  SollzeitProfile? sollzeit,
  String bundesland = 'SH',
}) {
  if (!regelFor(absence.type).urlaubswirksam) return 0;
  return werktageImBereich(
    absence.startDate,
    absence.endDate,
    jahr: jahr,
    feiertage: feiertageImJahr(jahr, bundesland: bundesland),
    sollzeit: sollzeit,
    halbtags: absence.halfDay,
  );
}

/// Eine Überlappung von Krankheit und genehmigtem Urlaub (§9 BUrlG).
class KrankheitImUrlaub {
  const KrankheitImUrlaub({
    required this.urlaub,
    required this.krankheit,
    required this.tage,
  });

  /// Der genehmigte Urlaubsantrag, in dessen Zeitraum die Krankheit fällt.
  final AbsenceRequest urlaub;

  /// Der überlappende Krank-Antrag (`sickness`).
  final AbsenceRequest krankheit;

  /// Überlappende **Werktage** (gutzuschreibender Urlaub), ≥ 0.
  final double tage;
}

/// §9 BUrlG: Erkrankt ein Mitarbeiter während eines **genehmigten** Urlaubs und
/// weist die Arbeitsunfähigkeit nach, werden die überlappenden Urlaubstage nicht
/// auf den Jahresurlaub angerechnet (Gutschrift). Liefert die Überlappungen im
/// [jahr] – als **Hinweis** für die Verwaltung (die Gutschrift selbst bucht der
/// Admin als [Urlaubsanpassung], damit sie nachvollziehbar im Ledger steht).
///
/// Berücksichtigt nur ärztlich relevante Krankheit (`AbsenceType.sickness`),
/// nicht abgelehnte Anträge, und zählt nur die **werktagsgenaue** Schnittmenge.
List<KrankheitImUrlaub> findeKrankheitImUrlaub(
  List<AbsenceRequest> absences, {
  required int jahr,
  SollzeitProfile? sollzeit,
  String bundesland = 'SH',
}) {
  final feiertage = feiertageImJahr(jahr, bundesland: bundesland);
  final urlaube = absences.where((a) =>
      a.type == AbsenceType.vacation && a.status == AbsenceStatus.approved);
  final krankheiten = absences.where((a) =>
      a.type == AbsenceType.sickness && a.status != AbsenceStatus.rejected);
  final result = <KrankheitImUrlaub>[];
  for (final u in urlaube) {
    for (final k in krankheiten) {
      // Schnittmenge der beiden Zeiträume (inklusive Tage).
      final von = u.startDate.isAfter(k.startDate) ? u.startDate : k.startDate;
      final bis = u.endDate.isBefore(k.endDate) ? u.endDate : k.endDate;
      if (von.isAfter(bis)) continue;
      final tage = werktageImBereich(
        von,
        bis,
        jahr: jahr,
        feiertage: feiertage,
        sollzeit: sollzeit,
        // Halbtags-Urlaub kann nur halbe Tage gutgeschrieben bekommen.
        halbtags: u.halfDay,
      );
      if (tage > 0) {
        result.add(KrankheitImUrlaub(urlaub: u, krankheit: k, tage: tage));
      }
    }
  }
  return result;
}

/// Berechnet die Urlaubskonto-Aufstellung (Plan §5.1/§5.2).
///
/// [vacationAbsences] = die **urlaubswirksamen** Anträge des Mitarbeiters
/// (genehmigt → genommen, offen → geplant; abgelehnte vorher rausfiltern).
UrlaubsReport berechneUrlaubsReport({
  required int jahr,
  SollzeitProfile? sollzeit,
  int? annualVacationDays,
  int? vertragVacationDays,
  DateTime? hireDate,
  DateTime? exitDate,
  UrlaubskontoJahr? konto,
  List<Urlaubsanpassung> anpassungen = const [],
  List<AbsenceRequest> vacationAbsences = const [],
  String bundesland = 'SH',
  DateTime? stichtag,
}) {
  final basis = resolveUrlaubstageJahr(
    sollzeit: sollzeit,
    annualVacationDays: annualVacationDays,
    vertragVacationDays: vertragVacationDays,
  ).tage;
  final zusatz = sollzeit?.zusatzurlaubstage ?? 0;

  // Teilzeitfaktor: eigene Arbeitstage/Woche ÷ Basis (5-Tage), B1: keine
  // Doppelskalierung – Basiswerte sind bereits 5-Tage-äquivalent.
  final eigeneArbeitstage = sollzeit?.effektiveArbeitstage ?? 5;
  final basisWerktage = sollzeit?.urlaubsbasisWerktage ?? 5;
  final teilzeit =
      basisWerktage <= 0 ? 1.0 : eigeneArbeitstage / basisWerktage;

  // Anteilige Zwölftelung bei Ein-/Austritt.
  final monate =
      beschaeftigteMonate(jahr, hireDate: hireDate, exitDate: exitDate);
  final anteil = monate / 12.0;

  // §5(2): gesetzlichen Mindesturlaub aufrunden, vertraglichen Mehrurlaub exakt.
  final gesetzlichVoll =
      (basis < gesetzlicherMindesturlaub5Tage ? basis : gesetzlicherMindesturlaub5Tage);
  final vertraglichVoll = (basis - gesetzlichVoll) + zusatz;
  final gesetzlich = _rundeGesetzlich(gesetzlichVoll * teilzeit * anteil);
  final vertraglich = vertraglichVoll * teilzeit * anteil;
  final anspruchJahr = _round1(gesetzlich + vertraglich);

  final vortrag = konto?.vortragVorjahrTage ?? 0;

  // genommen (genehmigt) / geplant (offen).
  var genommen = 0.0, geplant = 0.0;
  var genommenVorVerfall = 0.0;
  final verfallAm = konto?.vortragVerfaelltAm;
  for (final a in vacationAbsences) {
    final tage = genommeneUrlaubstage(a,
        jahr: jahr, sollzeit: sollzeit, bundesland: bundesland);
    if (a.status == AbsenceStatus.approved) {
      genommen += tage;
      if (verfallAm != null && !a.endDate.isAfter(verfallAm)) {
        genommenVorVerfall += tage;
      }
    } else if (a.status == AbsenceStatus.pending) {
      geplant += tage;
    }
  }

  // 31.3.-Verfall NUR mit dokumentierter Hinweisobliegenheit (§7(3) BUrlG).
  var vortragVerfallen = 0.0;
  final now = stichtag ?? DateTime.now();
  if (konto != null &&
      konto.hinweisErteiltAm != null &&
      verfallAm != null &&
      now.isAfter(verfallAm)) {
    // Vortrag wird zuerst verbraucht; der bis zum Verfall ungenutzte Rest verfällt.
    final restVortrag = vortrag - genommenVorVerfall;
    vortragVerfallen = restVortrag < 0 ? 0 : restVortrag;
  }

  // Manuelle Anpassungen fließen in den Anspruch ein.
  final anpassungSumme = anpassungen
      .where((x) => x.jahr == jahr)
      .fold<double>(0, (s, x) => s + x.tage);

  return UrlaubsReport(
    jahr: jahr,
    anspruchJahr: _round1(anspruchJahr + anpassungSumme),
    vortragVorjahr: _round1(vortrag),
    vortragVerfallen: _round1(vortragVerfallen),
    genommen: _round1(genommen),
    geplant: _round1(geplant),
  );
}
