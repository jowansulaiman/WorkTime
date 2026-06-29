import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Arbeitszeitmodell (Sollzeit) eines Mitarbeiters – **gültig-ab-versioniert**,
/// d. h. je Mitarbeiter können mehrere Datensätze mit unterschiedlichem
/// [gueltigAb] existieren (Vertrags-/Modelländerungen, wie in IDA `hr_sollzeiten`).
///
/// Trägt zugleich die **zentrale Urlaubsquelle** ([urlaubstageJahr], 5-Tage-Woche-
/// Basis = vollzeitäquivalent) für die BUrlG-Berechnung (siehe Plan §5.1). Die
/// Altfelder `EmployeeProfile.annualVacationDays` / `EmploymentContract.vacationDays`
/// werden in M0 hierher migriert.
///
/// **Vollausbau (E3):** Kern-/Rahmenzeit, Karenz, Rundung, Kappung, Gleitzeit,
/// fakultative Überstunden und [urlaubAlsStunden] sind enthalten. Kern-/Rahmenzeit
/// gelten **global** (nicht je Wochentag) – bewusste, retail-taugliche Vereinfachung;
/// nur das Tagessoll variiert je Wochentag.
class SollzeitProfile {
  const SollzeitProfile({
    this.id,
    required this.orgId,
    required this.userId,
    required this.gueltigAb,
    this.montagMinutes = 0,
    this.dienstagMinutes = 0,
    this.mittwochMinutes = 0,
    this.donnerstagMinutes = 0,
    this.freitagMinutes = 0,
    this.samstagMinutes = 0,
    this.sonntagMinutes = 0,
    this.isMonatsarbeitszeit = false,
    this.monatsarbeitszeitMinutes,
    this.arbeitstageProWoche = 5,
    this.urlaubstageJahr = 20,
    this.urlaubsbasisWerktage = 5,
    this.zusatzurlaubstage = 0,
    this.urlaubAlsStunden = false,
    this.pauseAb6hMinutes = 30,
    this.pauseAb9hMinutes = 45,
    this.rahmenVonMinutes,
    this.rahmenBisMinutes,
    this.kernzeitVonMinutes,
    this.kernzeitBisMinutes,
    this.pauseKarenzMinutes = 0,
    this.kernzeitKarenzMinutes = 0,
    this.azRunden = false,
    this.azRundenAufMinutes = 0,
    this.azRundenStart = false,
    this.azRundenEnde = false,
    this.azMaximumMinutes,
    this.gleitzeit = false,
    this.fakultativeUeberstunden = false,
    this.fakultativeUeberstundenTyp,
    this.fakultativeUeberstundenZeitraum,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;
  final String userId;

  /// Ab wann dieses Modell gilt (versioniert). **In Firestore** auf lokale
  /// Mittagszeit normalisiert (lokale snake_case-Serialisierung bleibt unverändert).
  final DateTime gueltigAb;

  /// Tagessoll je Wochentag in Minuten (0 = freier Tag, z. B. Feiertag-unabhängig).
  final int montagMinutes;
  final int dienstagMinutes;
  final int mittwochMinutes;
  final int donnerstagMinutes;
  final int freitagMinutes;
  final int samstagMinutes;
  final int sonntagMinutes;

  /// Wenn true, gilt [monatsarbeitszeitMinutes] (gleichmäßig auf Arbeitstage des
  /// Monats verteilt) statt der Tagessollwerte.
  final bool isMonatsarbeitszeit;
  final int? monatsarbeitszeitMinutes;

  /// Arbeitstage je Woche – Basis der BUrlG-Teilzeit-Umrechnung
  /// (`urlaubstageJahr × arbeitstageProWoche / urlaubsbasisWerktage`). Default 5.
  final int arbeitstageProWoche;

  /// **Zentrale Urlaubsquelle:** Jahresurlaub bei [urlaubsbasisWerktage]-Tage-Woche
  /// (vollzeitäquivalent). Default 20 (gesetzl. Mindesturlaub 5-Tage-Woche).
  final double urlaubstageJahr;

  /// Werktagsbasis des [urlaubstageJahr] (Default 5; 6 = klassische BUrlG-Basis).
  final int urlaubsbasisWerktage;

  /// Vertraglicher Zusatzurlaub (über den gesetzlichen Mindesturlaub hinaus).
  final double zusatzurlaubstage;

  /// IDA `urlaub_als_stunden`: Urlaub wird in Stunden statt Tagen geführt.
  final bool urlaubAlsStunden;

  /// Pflichtpausen-Vorgaben (ArbZG-Spiegel; Default 30 @ 6 h, 45 @ 9 h).
  final int pauseAb6hMinutes;
  final int pauseAb9hMinutes;

  /// Rahmen-/Kernarbeitszeit (Minuten ab Mitternacht, global). null = nicht gesetzt.
  final int? rahmenVonMinutes;
  final int? rahmenBisMinutes;
  final int? kernzeitVonMinutes;
  final int? kernzeitBisMinutes;

  /// Karenz (Toleranz) auf Pause bzw. Kernzeit in Minuten.
  final int pauseKarenzMinutes;
  final int kernzeitKarenzMinutes;

  /// Rundung der erfassten Zeit.
  final bool azRunden;
  final int azRundenAufMinutes; // Rundungs-Schrittweite (z. B. 15)
  final bool azRundenStart; // Beginn runden
  final bool azRundenEnde; // Ende runden

  /// Tages-Kappung der angerechneten Zeit (IDA `az_maximum`). null = keine.
  final int? azMaximumMinutes;

  /// Gleitzeitmodell (Plus-/Minus-Stunden ins Stundenkonto).
  final bool gleitzeit;

  /// Fakultative (freiwillige, nicht angerechnete) Überstunden.
  final bool fakultativeUeberstunden;
  final String? fakultativeUeberstundenTyp;
  final String? fakultativeUeberstundenZeitraum;

  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Tagessoll (Minuten) für einen Wochentag (`DateTime.monday`..`sunday`, 1..7).
  int sollMinutesForWeekday(int weekday) => switch (weekday) {
        DateTime.monday => montagMinutes,
        DateTime.tuesday => dienstagMinutes,
        DateTime.wednesday => mittwochMinutes,
        DateTime.thursday => donnerstagMinutes,
        DateTime.friday => freitagMinutes,
        DateTime.saturday => samstagMinutes,
        DateTime.sunday => sonntagMinutes,
        _ => 0,
      };

  /// Wochensoll (Summe der Tagessollwerte) in Minuten.
  int get wochensollMinutes =>
      montagMinutes +
      dienstagMinutes +
      mittwochMinutes +
      donnerstagMinutes +
      freitagMinutes +
      samstagMinutes +
      sonntagMinutes;

  /// Anzahl Wochentage mit Soll > 0 (für Teilzeit-Erkennung; fällt auf
  /// [arbeitstageProWoche] zurück, wenn keine Tagessollwerte gesetzt sind).
  int get effektiveArbeitstage {
    var count = 0;
    for (var wd = DateTime.monday; wd <= DateTime.sunday; wd++) {
      if (sollMinutesForWeekday(wd) > 0) count++;
    }
    return count > 0 ? count : arbeitstageProWoche;
  }

  /// Gilt dieses Modell am [date] (d. h. [gueltigAb] <= date)?
  bool isEffectiveOn(DateTime date) {
    final from = DateTime(gueltigAb.year, gueltigAb.month, gueltigAb.day);
    return !date.isBefore(from);
  }

  static DateTime _normalize(DateTime date) =>
      DateTime(date.year, date.month, date.day, 12);

  factory SollzeitProfile.fromFirestore(String id, Map<String, dynamic> map) {
    return SollzeitProfile(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      gueltigAb:
          FirestoreDateParser.readDate(map['gueltigAb']) ?? DateTime.now(),
      montagMinutes: parse.toInt(map['montagMinutes']) ?? 0,
      dienstagMinutes: parse.toInt(map['dienstagMinutes']) ?? 0,
      mittwochMinutes: parse.toInt(map['mittwochMinutes']) ?? 0,
      donnerstagMinutes: parse.toInt(map['donnerstagMinutes']) ?? 0,
      freitagMinutes: parse.toInt(map['freitagMinutes']) ?? 0,
      samstagMinutes: parse.toInt(map['samstagMinutes']) ?? 0,
      sonntagMinutes: parse.toInt(map['sonntagMinutes']) ?? 0,
      isMonatsarbeitszeit: parse.toBool(map['isMonatsarbeitszeit']) ?? false,
      monatsarbeitszeitMinutes: parse.toInt(map['monatsarbeitszeitMinutes']),
      arbeitstageProWoche: parse.toInt(map['arbeitstageProWoche']) ?? 5,
      urlaubstageJahr: parse.toDouble(map['urlaubstageJahr']) ?? 20,
      urlaubsbasisWerktage: parse.toInt(map['urlaubsbasisWerktage']) ?? 5,
      zusatzurlaubstage: parse.toDouble(map['zusatzurlaubstage']) ?? 0,
      urlaubAlsStunden: parse.toBool(map['urlaubAlsStunden']) ?? false,
      pauseAb6hMinutes: parse.toInt(map['pauseAb6hMinutes']) ?? 30,
      pauseAb9hMinutes: parse.toInt(map['pauseAb9hMinutes']) ?? 45,
      rahmenVonMinutes: parse.toInt(map['rahmenVonMinutes']),
      rahmenBisMinutes: parse.toInt(map['rahmenBisMinutes']),
      kernzeitVonMinutes: parse.toInt(map['kernzeitVonMinutes']),
      kernzeitBisMinutes: parse.toInt(map['kernzeitBisMinutes']),
      pauseKarenzMinutes: parse.toInt(map['pauseKarenzMinutes']) ?? 0,
      kernzeitKarenzMinutes: parse.toInt(map['kernzeitKarenzMinutes']) ?? 0,
      azRunden: parse.toBool(map['azRunden']) ?? false,
      azRundenAufMinutes: parse.toInt(map['azRundenAufMinutes']) ?? 0,
      azRundenStart: parse.toBool(map['azRundenStart']) ?? false,
      azRundenEnde: parse.toBool(map['azRundenEnde']) ?? false,
      azMaximumMinutes: parse.toInt(map['azMaximumMinutes']),
      gleitzeit: parse.toBool(map['gleitzeit']) ?? false,
      fakultativeUeberstunden:
          parse.toBool(map['fakultativeUeberstunden']) ?? false,
      fakultativeUeberstundenTyp:
          map['fakultativeUeberstundenTyp'] as String?,
      fakultativeUeberstundenZeitraum:
          map['fakultativeUeberstundenZeitraum'] as String?,
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory SollzeitProfile.fromMap(Map<String, dynamic> map) {
    return SollzeitProfile(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      gueltigAb: FirestoreDateParser.readLocalDate(map['gueltig_ab']) ??
          DateTime.now(),
      montagMinutes: parse.toInt(map['montag_minutes']) ?? 0,
      dienstagMinutes: parse.toInt(map['dienstag_minutes']) ?? 0,
      mittwochMinutes: parse.toInt(map['mittwoch_minutes']) ?? 0,
      donnerstagMinutes: parse.toInt(map['donnerstag_minutes']) ?? 0,
      freitagMinutes: parse.toInt(map['freitag_minutes']) ?? 0,
      samstagMinutes: parse.toInt(map['samstag_minutes']) ?? 0,
      sonntagMinutes: parse.toInt(map['sonntag_minutes']) ?? 0,
      isMonatsarbeitszeit: parse.toBool(map['is_monatsarbeitszeit']) ?? false,
      monatsarbeitszeitMinutes: parse.toInt(map['monatsarbeitszeit_minutes']),
      arbeitstageProWoche: parse.toInt(map['arbeitstage_pro_woche']) ?? 5,
      urlaubstageJahr: parse.toDouble(map['urlaubstage_jahr']) ?? 20,
      urlaubsbasisWerktage: parse.toInt(map['urlaubsbasis_werktage']) ?? 5,
      zusatzurlaubstage: parse.toDouble(map['zusatzurlaubstage']) ?? 0,
      urlaubAlsStunden: parse.toBool(map['urlaub_als_stunden']) ?? false,
      pauseAb6hMinutes: parse.toInt(map['pause_ab_6h_minutes']) ?? 30,
      pauseAb9hMinutes: parse.toInt(map['pause_ab_9h_minutes']) ?? 45,
      rahmenVonMinutes: parse.toInt(map['rahmen_von_minutes']),
      rahmenBisMinutes: parse.toInt(map['rahmen_bis_minutes']),
      kernzeitVonMinutes: parse.toInt(map['kernzeit_von_minutes']),
      kernzeitBisMinutes: parse.toInt(map['kernzeit_bis_minutes']),
      pauseKarenzMinutes: parse.toInt(map['pause_karenz_minutes']) ?? 0,
      kernzeitKarenzMinutes: parse.toInt(map['kernzeit_karenz_minutes']) ?? 0,
      azRunden: parse.toBool(map['az_runden']) ?? false,
      azRundenAufMinutes: parse.toInt(map['az_runden_auf_minutes']) ?? 0,
      azRundenStart: parse.toBool(map['az_runden_start']) ?? false,
      azRundenEnde: parse.toBool(map['az_runden_ende']) ?? false,
      azMaximumMinutes: parse.toInt(map['az_maximum_minutes']),
      gleitzeit: parse.toBool(map['gleitzeit']) ?? false,
      fakultativeUeberstunden:
          parse.toBool(map['fakultative_ueberstunden']) ?? false,
      fakultativeUeberstundenTyp:
          map['fakultative_ueberstunden_typ'] as String?,
      fakultativeUeberstundenZeitraum:
          map['fakultative_ueberstunden_zeitraum'] as String?,
      createdByUid: map['created_by_uid'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'userId': userId,
      'gueltigAb': Timestamp.fromDate(_normalize(gueltigAb)),
      'montagMinutes': montagMinutes,
      'dienstagMinutes': dienstagMinutes,
      'mittwochMinutes': mittwochMinutes,
      'donnerstagMinutes': donnerstagMinutes,
      'freitagMinutes': freitagMinutes,
      'samstagMinutes': samstagMinutes,
      'sonntagMinutes': sonntagMinutes,
      'isMonatsarbeitszeit': isMonatsarbeitszeit,
      'monatsarbeitszeitMinutes': monatsarbeitszeitMinutes,
      'arbeitstageProWoche': arbeitstageProWoche,
      'urlaubstageJahr': urlaubstageJahr,
      'urlaubsbasisWerktage': urlaubsbasisWerktage,
      'zusatzurlaubstage': zusatzurlaubstage,
      'urlaubAlsStunden': urlaubAlsStunden,
      'pauseAb6hMinutes': pauseAb6hMinutes,
      'pauseAb9hMinutes': pauseAb9hMinutes,
      'rahmenVonMinutes': rahmenVonMinutes,
      'rahmenBisMinutes': rahmenBisMinutes,
      'kernzeitVonMinutes': kernzeitVonMinutes,
      'kernzeitBisMinutes': kernzeitBisMinutes,
      'pauseKarenzMinutes': pauseKarenzMinutes,
      'kernzeitKarenzMinutes': kernzeitKarenzMinutes,
      'azRunden': azRunden,
      'azRundenAufMinutes': azRundenAufMinutes,
      'azRundenStart': azRundenStart,
      'azRundenEnde': azRundenEnde,
      'azMaximumMinutes': azMaximumMinutes,
      'gleitzeit': gleitzeit,
      'fakultativeUeberstunden': fakultativeUeberstunden,
      'fakultativeUeberstundenTyp': fakultativeUeberstundenTyp,
      'fakultativeUeberstundenZeitraum': fakultativeUeberstundenZeitraum,
      'createdByUid': createdByUid,
      // Doc-ID wird vor dem Schreiben gesetzt (saveSollzeitProfile copyWith id)
      // → an createdAt festmachen, nicht an id==null (sonst nie geschrieben).
      if (createdAt == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'user_id': userId,
      'gueltig_ab': gueltigAb.toIso8601String(),
      'montag_minutes': montagMinutes,
      'dienstag_minutes': dienstagMinutes,
      'mittwoch_minutes': mittwochMinutes,
      'donnerstag_minutes': donnerstagMinutes,
      'freitag_minutes': freitagMinutes,
      'samstag_minutes': samstagMinutes,
      'sonntag_minutes': sonntagMinutes,
      'is_monatsarbeitszeit': isMonatsarbeitszeit,
      'monatsarbeitszeit_minutes': monatsarbeitszeitMinutes,
      'arbeitstage_pro_woche': arbeitstageProWoche,
      'urlaubstage_jahr': urlaubstageJahr,
      'urlaubsbasis_werktage': urlaubsbasisWerktage,
      'zusatzurlaubstage': zusatzurlaubstage,
      'urlaub_als_stunden': urlaubAlsStunden,
      'pause_ab_6h_minutes': pauseAb6hMinutes,
      'pause_ab_9h_minutes': pauseAb9hMinutes,
      'rahmen_von_minutes': rahmenVonMinutes,
      'rahmen_bis_minutes': rahmenBisMinutes,
      'kernzeit_von_minutes': kernzeitVonMinutes,
      'kernzeit_bis_minutes': kernzeitBisMinutes,
      'pause_karenz_minutes': pauseKarenzMinutes,
      'kernzeit_karenz_minutes': kernzeitKarenzMinutes,
      'az_runden': azRunden,
      'az_runden_auf_minutes': azRundenAufMinutes,
      'az_runden_start': azRundenStart,
      'az_runden_ende': azRundenEnde,
      'az_maximum_minutes': azMaximumMinutes,
      'gleitzeit': gleitzeit,
      'fakultative_ueberstunden': fakultativeUeberstunden,
      'fakultative_ueberstunden_typ': fakultativeUeberstundenTyp,
      'fakultative_ueberstunden_zeitraum': fakultativeUeberstundenZeitraum,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  SollzeitProfile copyWith({
    String? id,
    String? orgId,
    String? userId,
    DateTime? gueltigAb,
    int? montagMinutes,
    int? dienstagMinutes,
    int? mittwochMinutes,
    int? donnerstagMinutes,
    int? freitagMinutes,
    int? samstagMinutes,
    int? sonntagMinutes,
    bool? isMonatsarbeitszeit,
    int? monatsarbeitszeitMinutes,
    bool clearMonatsarbeitszeitMinutes = false,
    int? arbeitstageProWoche,
    double? urlaubstageJahr,
    int? urlaubsbasisWerktage,
    double? zusatzurlaubstage,
    bool? urlaubAlsStunden,
    int? pauseAb6hMinutes,
    int? pauseAb9hMinutes,
    int? rahmenVonMinutes,
    bool clearRahmenVonMinutes = false,
    int? rahmenBisMinutes,
    bool clearRahmenBisMinutes = false,
    int? kernzeitVonMinutes,
    bool clearKernzeitVonMinutes = false,
    int? kernzeitBisMinutes,
    bool clearKernzeitBisMinutes = false,
    int? pauseKarenzMinutes,
    int? kernzeitKarenzMinutes,
    bool? azRunden,
    int? azRundenAufMinutes,
    bool? azRundenStart,
    bool? azRundenEnde,
    int? azMaximumMinutes,
    bool clearAzMaximumMinutes = false,
    bool? gleitzeit,
    bool? fakultativeUeberstunden,
    String? fakultativeUeberstundenTyp,
    bool clearFakultativeUeberstundenTyp = false,
    String? fakultativeUeberstundenZeitraum,
    bool clearFakultativeUeberstundenZeitraum = false,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SollzeitProfile(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      userId: userId ?? this.userId,
      gueltigAb: gueltigAb ?? this.gueltigAb,
      montagMinutes: montagMinutes ?? this.montagMinutes,
      dienstagMinutes: dienstagMinutes ?? this.dienstagMinutes,
      mittwochMinutes: mittwochMinutes ?? this.mittwochMinutes,
      donnerstagMinutes: donnerstagMinutes ?? this.donnerstagMinutes,
      freitagMinutes: freitagMinutes ?? this.freitagMinutes,
      samstagMinutes: samstagMinutes ?? this.samstagMinutes,
      sonntagMinutes: sonntagMinutes ?? this.sonntagMinutes,
      isMonatsarbeitszeit: isMonatsarbeitszeit ?? this.isMonatsarbeitszeit,
      monatsarbeitszeitMinutes: clearMonatsarbeitszeitMinutes
          ? null
          : (monatsarbeitszeitMinutes ?? this.monatsarbeitszeitMinutes),
      arbeitstageProWoche: arbeitstageProWoche ?? this.arbeitstageProWoche,
      urlaubstageJahr: urlaubstageJahr ?? this.urlaubstageJahr,
      urlaubsbasisWerktage: urlaubsbasisWerktage ?? this.urlaubsbasisWerktage,
      zusatzurlaubstage: zusatzurlaubstage ?? this.zusatzurlaubstage,
      urlaubAlsStunden: urlaubAlsStunden ?? this.urlaubAlsStunden,
      pauseAb6hMinutes: pauseAb6hMinutes ?? this.pauseAb6hMinutes,
      pauseAb9hMinutes: pauseAb9hMinutes ?? this.pauseAb9hMinutes,
      rahmenVonMinutes: clearRahmenVonMinutes
          ? null
          : (rahmenVonMinutes ?? this.rahmenVonMinutes),
      rahmenBisMinutes: clearRahmenBisMinutes
          ? null
          : (rahmenBisMinutes ?? this.rahmenBisMinutes),
      kernzeitVonMinutes: clearKernzeitVonMinutes
          ? null
          : (kernzeitVonMinutes ?? this.kernzeitVonMinutes),
      kernzeitBisMinutes: clearKernzeitBisMinutes
          ? null
          : (kernzeitBisMinutes ?? this.kernzeitBisMinutes),
      pauseKarenzMinutes: pauseKarenzMinutes ?? this.pauseKarenzMinutes,
      kernzeitKarenzMinutes:
          kernzeitKarenzMinutes ?? this.kernzeitKarenzMinutes,
      azRunden: azRunden ?? this.azRunden,
      azRundenAufMinutes: azRundenAufMinutes ?? this.azRundenAufMinutes,
      azRundenStart: azRundenStart ?? this.azRundenStart,
      azRundenEnde: azRundenEnde ?? this.azRundenEnde,
      azMaximumMinutes: clearAzMaximumMinutes
          ? null
          : (azMaximumMinutes ?? this.azMaximumMinutes),
      gleitzeit: gleitzeit ?? this.gleitzeit,
      fakultativeUeberstunden:
          fakultativeUeberstunden ?? this.fakultativeUeberstunden,
      fakultativeUeberstundenTyp: clearFakultativeUeberstundenTyp
          ? null
          : (fakultativeUeberstundenTyp ?? this.fakultativeUeberstundenTyp),
      fakultativeUeberstundenZeitraum: clearFakultativeUeberstundenZeitraum
          ? null
          : (fakultativeUeberstundenZeitraum ??
              this.fakultativeUeberstundenZeitraum),
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
