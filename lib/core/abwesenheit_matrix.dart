import '../models/absence_request.dart';

/// Anrechnungsregel je [AbsenceType] (Plan §5.4a). **Eine** Quelle, die
/// Stundenkonto-Calculator, Lohn-/Brutto-Herleitung, Urlaubsanspruch und
/// DATEV-Mapping gemeinsam lesen – statt die Eigenschaften über die Module zu
/// verstreuen.
class AbwesenheitsRegel {
  const AbwesenheitsRegel({
    required this.bezahlt,
    required this.alsSollAngerechnet,
    required this.urlaubswirksam,
    required this.halbtagFaehig,
    this.efzgBegrenzt = false,
    this.datevAusfallschluessel,
  });

  /// Lohnfortzahlung durch den Arbeitgeber (bei [efzgBegrenzt] nur im EFZG-Zeitraum).
  final bool bezahlt;

  /// Wird als erfüllte **Sollzeit** angerechnet (Ist = Soll, kein Minus im
  /// Stundenkonto). Bei [efzgBegrenzt] nur die ersten [efzgMaxKalendertage].
  final bool alsSollAngerechnet;

  /// Zählt als **genommener Urlaub** (mindert den Resturlaub).
  final bool urlaubswirksam;

  /// Kann halbtägig beantragt werden (0,5).
  final bool halbtagFaehig;

  /// Lohnfortzahlung nur befristet (EFZG 6 Wochen je Krankheitsfall).
  final bool efzgBegrenzt;

  /// DATEV-Ausfallschlüssel (Hinweis; das verbindliche Mapping baut M-D).
  final String? datevAusfallschluessel;
}

/// EFZG-Lohnfortzahlung: 6 Wochen = 42 Kalendertage je Krankheitsfall.
const int efzgMaxKalendertage = 42;

/// §5.4a-Matrix. Default für unbekannte/zukünftige Arten: neutral (nicht
/// bezahlt, nicht angerechnet), damit kein falsches Plus im Stundenkonto entsteht.
const Map<AbsenceType, AbwesenheitsRegel> abwesenheitsMatrix = {
  AbsenceType.vacation: AbwesenheitsRegel(
    bezahlt: true,
    alsSollAngerechnet: true,
    urlaubswirksam: true,
    halbtagFaehig: true,
    datevAusfallschluessel: 'U',
  ),
  AbsenceType.sickness: AbwesenheitsRegel(
    bezahlt: true,
    alsSollAngerechnet: true,
    urlaubswirksam: false,
    halbtagFaehig: true,
    efzgBegrenzt: true, // bezahlt/angerechnet nur die ersten 42 Kalendertage
    datevAusfallschluessel: 'K',
  ),
  AbsenceType.childSick: AbwesenheitsRegel(
    bezahlt: true,
    alsSollAngerechnet: true,
    urlaubswirksam: false,
    halbtagFaehig: true,
    // Audit-Korrektur M3: erkrankung_kind = „K" (nicht „KK").
    datevAusfallschluessel: 'K',
  ),
  AbsenceType.specialLeave: AbwesenheitsRegel(
    bezahlt: true,
    alsSollAngerechnet: true,
    urlaubswirksam: false,
    halbtagFaehig: true,
    datevAusfallschluessel: 'SU',
  ),
  AbsenceType.unpaidLeave: AbwesenheitsRegel(
    bezahlt: false,
    alsSollAngerechnet: false, // kein Soll, kein Ist
    urlaubswirksam: false,
    halbtagFaehig: true,
    datevAusfallschluessel: 'UU',
  ),
  AbsenceType.timeOff: AbwesenheitsRegel(
    bezahlt: true, // aus dem Stundenkonto
    alsSollAngerechnet: true,
    urlaubswirksam: false,
    halbtagFaehig: true,
    datevAusfallschluessel: 'ZA',
  ),
  AbsenceType.parentalLeave: AbwesenheitsRegel(
    bezahlt: false,
    alsSollAngerechnet: false,
    urlaubswirksam: false,
    halbtagFaehig: false,
    datevAusfallschluessel: 'EZ',
  ),
  AbsenceType.maternity: AbwesenheitsRegel(
    bezahlt: true, // Mutterschutzlohn separat
    alsSollAngerechnet: false,
    urlaubswirksam: false,
    halbtagFaehig: false,
    datevAusfallschluessel: 'MU',
  ),
  AbsenceType.vocationalSchool: AbwesenheitsRegel(
    bezahlt: true,
    alsSollAngerechnet: true,
    urlaubswirksam: false,
    halbtagFaehig: true,
    datevAusfallschluessel: 'BS',
  ),
  AbsenceType.volunteering: AbwesenheitsRegel(
    bezahlt: true,
    alsSollAngerechnet: true,
    urlaubswirksam: false,
    halbtagFaehig: true,
    datevAusfallschluessel: 'EH',
  ),
  AbsenceType.shortTimeWork: AbwesenheitsRegel(
    bezahlt: false, // KUG der Agentur, ist-soll-neutral (E6 weggelassen)
    alsSollAngerechnet: false,
    urlaubswirksam: false,
    halbtagFaehig: false,
  ),
  AbsenceType.unavailable: AbwesenheitsRegel(
    bezahlt: false,
    alsSollAngerechnet: false,
    urlaubswirksam: false,
    halbtagFaehig: true,
  ),
};

/// Neutrale Default-Regel (kein Plus/Minus), falls eine Art (noch) nicht in der
/// Matrix steht.
const AbwesenheitsRegel _defaultRegel = AbwesenheitsRegel(
  bezahlt: false,
  alsSollAngerechnet: false,
  urlaubswirksam: false,
  halbtagFaehig: true,
);

/// Regel für [type] (nie null – fällt auf [_defaultRegel] zurück).
AbwesenheitsRegel regelFor(AbsenceType type) =>
    abwesenheitsMatrix[type] ?? _defaultRegel;
