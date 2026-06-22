import 'app_config.dart';

/// Gebündelte Betreiber-/Verantwortlichen-Stammdaten für Impressum (§ 5 DDG)
/// und Datenschutzerklärung (Art. 13 DSGVO) der öffentlichen Seiten.
///
/// Bewusst ein reines Wertobjekt (kein Widget, keine Seiteneffekte), damit die
/// Inhalts-Bausteine in `public_legal_screen.dart` rein bleiben und Tests sowohl
/// den „vollständig hinterlegt"- als auch den „Platzhalter"-Zweig prüfen können,
/// ohne dart-defines setzen zu müssen. Produktiv liest [LegalInfo.fromConfig]
/// die `APP_LEGAL_*`-dart-defines aus [AppConfig].
class LegalInfo {
  const LegalInfo({
    this.operatorName = '',
    this.street = '',
    this.postalCity = '',
    this.email = '',
    this.phone = '',
    this.representative = '',
    this.vatId = '',
    this.registerEntry = '',
    this.contentResponsible = '',
    this.lastUpdated = '',
  });

  /// Inhaber/Betreiber bzw. vollständiger Firmenname.
  final String operatorName;

  /// Straße und Hausnummer.
  final String street;

  /// PLZ und Ort (z. B. „24103 Kiel").
  final String postalCity;

  /// Kontakt-E-Mail.
  final String email;

  /// Kontakt-Telefonnummer (optional).
  final String phone;

  /// Vertretungsberechtigte Person (nur juristische Personen).
  final String representative;

  /// Umsatzsteuer-Identifikationsnummer (§ 27 a UStG, optional).
  final String vatId;

  /// Registereintrag „Registergericht / Registernummer" (optional).
  final String registerEntry;

  /// Inhaltlich Verantwortlicher (§ 18 Abs. 2 MStV, optional). Greift nur bei
  /// journalistisch-redaktionellen Angeboten — reine Eingabeformulare lösen die
  /// Pflicht NICHT aus. Daher Opt-in: nur wenn gesetzt, erscheint der Block.
  final String contentResponsible;

  /// Stand/Datum der Rechtstexte (z. B. „Juni 2026"), optional. Wenn gesetzt,
  /// wird es als „Stand: …" angezeigt (Art. 13 DSGVO empfiehlt einen Stand).
  final String lastUpdated;

  /// Liest die `APP_LEGAL_*`-dart-defines. Werte werden getrimmt, damit ein
  /// versehentliches Leerzeichen nicht als „gesetzt" zählt.
  factory LegalInfo.fromConfig() => LegalInfo(
        operatorName: AppConfig.legalOperatorName.trim(),
        street: AppConfig.legalStreet.trim(),
        postalCity: AppConfig.legalPostalCity.trim(),
        email: AppConfig.legalEmail.trim(),
        phone: AppConfig.legalPhone.trim(),
        representative: AppConfig.legalRepresentative.trim(),
        vatId: AppConfig.legalVatId.trim(),
        registerEntry: AppConfig.legalRegisterEntry.trim(),
        contentResponsible: AppConfig.legalContentResponsible.trim(),
        lastUpdated: AppConfig.legalLastUpdated.trim(),
      );

  /// Minimal-Pflichtangaben eines Einzelunternehmer-Impressums (§ 5 DDG): Name,
  /// ladungsfähige Anschrift (Straße + PLZ/Ort) sowie zwei schnelle Kontaktwege
  /// (E-Mail UND Telefon — § 5 Abs. 1 Nr. 2 DDG verlangt unmittelbare
  /// Kommunikation; die Läden haben ohnehin Telefon). Erst wenn alle vorliegen,
  /// gelten die Rechtsseiten als „veröffentlichungsbereit"; sonst zeigen sie
  /// einen sichtbaren Hinweis.
  bool get isComplete =>
      operatorName.isNotEmpty &&
      street.isNotEmpty &&
      postalCity.isNotEmpty &&
      email.isNotEmpty &&
      phone.isNotEmpty;
}
