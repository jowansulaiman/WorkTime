import 'package:flutter/material.dart';

import '../../core/legal_info.dart';
import '../../theme/app_theme.dart';
import 'public_ui.dart';

/// Welche rechtliche Pflichtseite gerendert wird.
enum PublicLegalPage {
  impressum,
  datenschutz;

  String get title => switch (this) {
        PublicLegalPage.impressum => 'Impressum',
        PublicLegalPage.datenschutz => 'Datenschutzerklärung',
      };
}

/// Öffentliche, login-freie Rechtsseite (Impressum bzw. Datenschutzerklärung).
///
/// Wird auf zwei Wegen erreicht: per Footer-Link aus den öffentlichen
/// Formularseiten ([Navigator.push]) und als eigenständige Web-Route
/// (`/impressum`, `/datenschutz`) über [PublicLegalApp]. Reine Statik — kein
/// Firebase, kein Schreibpfad. Optik: dasselbe flache Signal-Teal-Design-System
/// wie die übrigen öffentlichen Seiten ([public_ui]).
class PublicLegalScreen extends StatelessWidget {
  const PublicLegalScreen({
    super.key,
    required this.page,
    this.info,
    this.onSelectThemeMode,
  });

  final PublicLegalPage page;

  /// Betreiber-/Verantwortlichen-Stammdaten. Standard: aus den `APP_LEGAL_*`-
  /// dart-defines. Tests injizieren hier vollständige bzw. leere Daten.
  final LegalInfo? info;

  /// Callback zum Umschalten Hell/Dunkel (vom Shell gesetzt). `null` blendet den
  /// Umschalter aus.
  final ValueChanged<ThemeMode>? onSelectThemeMode;

  /// Maximale Lesebreite der Rechts-Dokumente (langer Fließtext liest sich in
  /// einer schmaleren Spalte besser als über die volle Desktop-Breite).
  static const double _maxWidth = 760;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final spacing = context.spacing;
    final info = this.info ?? LegalInfo.fromConfig();

    final sections = switch (page) {
      PublicLegalPage.impressum => buildImpressumSections(context, info),
      PublicLegalPage.datenschutz => buildDatenschutzSections(context, info),
    };

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  spacing.lg, spacing.lg, spacing.lg, spacing.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTopBar(context),
                  SizedBox(height: spacing.lg),
                  Semantics(
                    header: true,
                    child:
                        Text(page.title, style: theme.textTheme.displaySmall),
                  ),
                  if (info.lastUpdated.isNotEmpty) ...[
                    SizedBox(height: spacing.xs),
                    Text(
                      'Stand: ${info.lastUpdated}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                  SizedBox(height: spacing.md),
                  if (!info.isComplete) ...[
                    const PublicLegalSetupNotice(),
                    SizedBox(height: spacing.lg),
                  ],
                  for (final section in sections) ...[
                    section,
                    SizedBox(height: spacing.md),
                  ],
                  SizedBox(height: spacing.xs),
                  // Cross-Link: vom Impressum zum Datenschutz und umgekehrt.
                  PublicLegalLinks(
                    onImpressum: page == PublicLegalPage.impressum
                        ? null
                        : () => _openOther(context, PublicLegalPage.impressum),
                    onDatenschutz: page == PublicLegalPage.datenschutz
                        ? null
                        : () => _openOther(context, PublicLegalPage.datenschutz),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Wechselt zur jeweils anderen Rechtsseite — immer per `pushReplacement`,
  /// damit keine Kette aus Rechtsseiten entsteht: Aus dem Formular gestapelt
  /// bleibt der Zurück-Pfeil auf das Formular gerichtet; als eigenständige Route
  /// (`/impressum`) ersetzt der Cross-Link die Wurzel, sodass kein irreführender
  /// Zurück-Pfeil auf die zuvor gezeigte Rechtsseite erscheint.
  void _openOther(BuildContext context, PublicLegalPage other) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => PublicLegalScreen(
          page: other,
          info: info,
          onSelectThemeMode: onSelectThemeMode,
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final spacing = context.spacing;
    final canPop = Navigator.of(context).canPop();
    return Row(
      children: [
        if (canPop) ...[
          IconButton(
            tooltip: 'Zurück',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          SizedBox(width: spacing.xs),
        ],
        const PublicLogoChip(),
        const Spacer(),
        if (onSelectThemeMode != null) _buildThemeToggle(context),
      ],
    );
  }

  Widget _buildThemeToggle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IconButton.filledTonal(
      tooltip: isDark ? 'Heller Modus' : 'Dunkler Modus',
      icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
      onPressed: () =>
          onSelectThemeMode?.call(isDark ? ThemeMode.light : ThemeMode.dark),
    );
  }
}

/// Sichtbarer Warnhinweis, solange die Pflichtangaben (Name, Anschrift, E-Mail)
/// nicht hinterlegt sind. Bewusst auffällig: eine unvollständige Rechtsseite
/// soll im Build sofort auffallen, nicht still falsch online gehen.
class PublicLegalSetupNotice extends StatelessWidget {
  const PublicLegalSetupNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = theme.appColors;
    final spacing = context.spacing;
    return Semantics(
      container: true,
      child: Container(
        padding: EdgeInsets.all(spacing.md),
        decoration: BoxDecoration(
          color: appColors.warningContainer,
          borderRadius: BorderRadius.circular(context.radii.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded,
                color: appColors.onWarningContainer,
                size: context.iconSizes.sm,
                semanticLabel: 'Warnung'),
            SizedBox(width: spacing.sm),
            Expanded(
              child: Text(
                'Diese Angaben sind noch nicht vollständig hinterlegt. Vor der '
                'Veröffentlichung müssen Betreiber, Anschrift und Kontakt '
                'ergänzt werden (dart-defines APP_LEGAL_*).',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: appColors.onWarningContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Inhalts-Bausteine (rein, ohne Seiteneffekte) — von Screen UND Tests genutzt.
// Die Texte sind ein sorgfältiges Muster für ein Einzelunternehmen in
// Schleswig-Holstein; der Betreiber muss sie vor dem Go-Live rechtlich prüfen
// und an die tatsächlichen Verhältnisse anpassen.
// ===========================================================================

/// Platzhalter-Klammer, wenn ein Feld (noch) leer ist — macht im Layout
/// sichtbar, welche Angabe fehlt, statt eine leere Zeile zu hinterlassen.
String _orPlaceholder(String value, String placeholder) =>
    value.isNotEmpty ? value : '[$placeholder]';

/// Adresszeilen des Betreibers (Name, optional Vertretung, Straße, PLZ/Ort).
List<String> _operatorAddressLines(LegalInfo info) => [
      _orPlaceholder(info.operatorName, 'Name des Betreibers / der Inhaberin'),
      if (info.representative.isNotEmpty) 'vertreten durch ${info.representative}',
      _orPlaceholder(info.street, 'Straße und Hausnummer'),
      _orPlaceholder(info.postalCity, 'PLZ und Ort'),
    ];

List<Widget> buildImpressumSections(BuildContext context, LegalInfo info) {
  return [
    PublicSection(
      title: 'Angaben gemäß § 5 DDG',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LegalAddressBlock(lines: _operatorAddressLines(info)),
          if (info.registerEntry.isNotEmpty) ...[
            SizedBox(height: context.spacing.md),
            _LegalKeyValue(label: 'Register', value: info.registerEntry),
          ],
        ],
      ),
    ),
    PublicSection(
      title: 'Kontakt',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LegalKeyValue(
            label: 'Telefon',
            value: _orPlaceholder(info.phone, 'Telefonnummer'),
          ),
          SizedBox(height: context.spacing.sm),
          _LegalKeyValue(
            label: 'E-Mail',
            value: _orPlaceholder(info.email, 'E-Mail-Adresse'),
          ),
        ],
      ),
    ),
    if (info.vatId.isNotEmpty)
      PublicSection(
        title: 'Umsatzsteuer-ID',
        child: _LegalParagraph(
          'Umsatzsteuer-Identifikationsnummer gemäß § 27 a Umsatzsteuergesetz: '
          '${info.vatId}',
        ),
      ),
    // § 18 Abs. 2 MStV verlangt einen inhaltlich Verantwortlichen NUR für
    // journalistisch-redaktionelle Angebote. Reine Eingabeformulare lösen die
    // Pflicht nicht aus → nur anzeigen, wenn der Betreiber bewusst jemanden
    // benannt hat (Opt-in via APP_LEGAL_CONTENT_RESPONSIBLE).
    if (info.contentResponsible.isNotEmpty)
      PublicSection(
        title: 'Verantwortlich für den Inhalt nach § 18 Abs. 2 MStV',
        child: _LegalAddressBlock(
          lines: [
            info.contentResponsible,
            _orPlaceholder(info.street, 'Straße und Hausnummer'),
            _orPlaceholder(info.postalCity, 'PLZ und Ort'),
          ],
        ),
      ),
    const PublicSection(
      title: 'Verbraucherstreitbeilegung',
      child: _LegalParagraph(
        'Wir sind nicht bereit und nicht verpflichtet, an Streitbeilegungs'
        'verfahren vor einer Verbraucherschlichtungsstelle teilzunehmen '
        '(§ 36 Verbraucherstreitbeilegungsgesetz).',
      ),
    ),
    const PublicSection(
      title: 'Haftung für Inhalte',
      child: _LegalParagraph(
        'Die Inhalte dieser Seiten wurden mit größter Sorgfalt erstellt. Für '
        'die Richtigkeit, Vollständigkeit und Aktualität der Inhalte können '
        'wir jedoch keine Gewähr übernehmen. Als Diensteanbieter sind wir gemäß '
        '§ 7 Abs. 1 DDG für eigene Inhalte auf diesen Seiten nach den '
        'allgemeinen Gesetzen verantwortlich.',
      ),
    ),
  ];
}

List<Widget> buildDatenschutzSections(BuildContext context, LegalInfo info) {
  final spacing = context.spacing;
  return [
    PublicSection(
      title: '1. Verantwortlicher',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _LegalParagraph(
            'Verantwortlich für die Datenverarbeitung auf diesen Seiten im '
            'Sinne der Datenschutz-Grundverordnung (DSGVO) ist:',
          ),
          SizedBox(height: spacing.md),
          _LegalAddressBlock(lines: _operatorAddressLines(info)),
          SizedBox(height: spacing.md),
          _LegalKeyValue(
            label: 'E-Mail',
            value: _orPlaceholder(info.email, 'E-Mail-Adresse'),
          ),
          if (info.phone.isNotEmpty) ...[
            SizedBox(height: spacing.sm),
            _LegalKeyValue(label: 'Telefon', value: info.phone),
          ],
          SizedBox(height: spacing.md),
          _LegalParagraph(
            'Einen Datenschutzbeauftragten haben wir nicht bestellt (gesetzlich '
            'nicht erforderlich). Anfragen zum Datenschutz richtest du bitte an '
            '${_orPlaceholder(info.email, 'E-Mail-Adresse')}.',
          ),
        ],
      ),
    ),
    const PublicSection(
      title: '2. Geltungsbereich',
      child: _LegalParagraph(
        'Diese Datenschutzerklärung gilt für unsere öffentlichen Online-'
        'Angebote, über die du uns ohne Anmeldung erreichen kannst: das '
        'Wunsch-Formular und das Feedback-/Beschwerde-Formular. Für unsere '
        'interne Mitarbeiter-Anwendung gelten gesonderte Hinweise.',
      ),
    ),
    const PublicSection(
      title: '3. Welche Daten wir verarbeiten',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LegalSubheading('Von dir angegebene Daten'),
          _LegalParagraph(
            'Beim Absenden eines Wunsches oder einer Rückmeldung verarbeiten '
            'wir die Angaben, die du im Formular machst: deine Nachricht bzw. '
            'deinen Wunsch, die Kategorie, den gewählten Laden, ggf. Menge, '
            'einen Wunsch- oder Vorfallstermin sowie eine optionale Bewertung. '
            'Name und Kontaktdaten (Telefon oder E-Mail) sind freiwillig – du '
            'gibst sie nur an, wenn du eine Rückmeldung von uns möchtest.',
          ),
          _LegalBullet(
            'Pflicht ist allein dein Wunsch- bzw. Nachrichtentext; alle '
            'weiteren Angaben sind freiwillig.',
          ),
          _LegalBullet(
            'Bitte gib im Freitextfeld nur das an, was für dein Anliegen nötig '
            'ist, und keine besonderen Kategorien personenbezogener Daten '
            '(z. B. Gesundheits-, Religions- oder ähnliche sensible Daten nach '
            'Art. 9 DSGVO).',
          ),
          _LegalSubheading('Automatisch verarbeitete Daten'),
          _LegalParagraph(
            'Damit eine Übermittlung technisch möglich ist, melden wir dich '
            'anonym an (Firebase Anonymous Authentication). Beim Identitäts'
            'dienst entsteht dabei eine zufällige, pseudonyme Kennung, die nicht '
            'mit deiner Identität verknüpft ist; im Web ist sie auf die aktuelle '
            'Browser-Sitzung beschränkt und wird nicht dauerhaft gespeichert. '
            'Zusammen mit deiner Eingabe wird der Zeitpunkt der Übermittlung '
            'gespeichert. In unserer eigenen Anwendungsdatenbank speichern wir '
            'weder deine IP-Adresse noch Standortdaten.',
          ),
          _LegalParagraph(
            'Technisch bedingt verarbeitet unser Hosting-/Backend-Dienstleister '
            '(Google/Firebase) beim Aufruf der Seite und bei jeder Übermittlung '
            'Verbindungsdaten einschließlich deiner IP-Adresse zu Server-Log- '
            'und Sicherheitszwecken. Rechtsgrundlage ist Art. 6 Abs. 1 lit. f '
            'DSGVO (berechtigtes Interesse an Sicherheit und Betrieb).',
          ),
          _LegalSubheading('Schutz vor Missbrauch'),
          _LegalParagraph(
            'Zum Schutz vor automatisiertem Missbrauch (Bots, Spam) setzen wir '
            'Firebase App Check in Verbindung mit Google reCAPTCHA ein, sofern '
            'aktiviert. Dabei werden Geräte- und Nutzungsinformationen an '
            'Google übermittelt und ausgewertet. Anbieter ist Google; dabei '
            'kann eine Übermittlung in die USA erfolgen.',
          ),
        ],
      ),
    ),
    const PublicSection(
      title: '4. Zwecke und Rechtsgrundlagen',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LegalBullet(
            'Bearbeitung deines Wunsches bzw. deiner Rückmeldung und – falls '
            'gewünscht – Kontaktaufnahme. Rechtsgrundlage: Art. 6 Abs. 1 lit. b '
            'DSGVO (Bearbeitung deiner Anfrage) bzw. Art. 6 Abs. 1 lit. f DSGVO '
            '(berechtigtes Interesse an gutem Kundenservice).',
          ),
          _LegalBullet(
            'Freiwillige Kontaktangaben verarbeiten wir auf Grundlage deiner '
            'Einwilligung, Art. 6 Abs. 1 lit. a DSGVO, die du durch die Eingabe '
            'erteilst und jederzeit widerrufen kannst.',
          ),
          _LegalBullet(
            'Sicherheit und störungsfreier Betrieb (Missbrauchsschutz). '
            'Rechtsgrundlage: Art. 6 Abs. 1 lit. f DSGVO.',
          ),
        ],
      ),
    ),
    const PublicSection(
      title: '5. Empfänger und Auftragsverarbeiter',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LegalParagraph(
            'Für Hosting, Datenbank (Cloud Firestore) und die anonyme '
            'Anmeldung nutzen wir Dienste von Google (Firebase), Anbieter '
            'Google Ireland Limited, Gordon House, Barrow Street, Dublin 4, '
            'Irland. Mit Google besteht ein Vertrag zur Auftragsverarbeitung '
            'nach Art. 28 DSGVO. Die Daten unserer Datenbank werden in einem '
            'Rechenzentrum in der Europäischen Union gespeichert.',
          ),
          _LegalParagraph(
            'Beim Missbrauchsschutz (App Check / reCAPTCHA) kann eine '
            'Übermittlung von Daten an Google in die USA erfolgen. Grundlage '
            'hierfür sind die Standardvertragsklauseln der EU-Kommission bzw. '
            'der Angemessenheitsbeschluss zum EU-US Data Privacy Framework. Eine '
            'Kopie der Standardvertragsklauseln ist auf Anfrage über die oben '
            'genannte Kontakt-E-Mail erhältlich.',
          ),
        ],
      ),
    ),
    const PublicSection(
      title: '6. Speicherdauer',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LegalParagraph(
            'Wir speichern deine Angaben nur so lange, wie es für die '
            'Bearbeitung deines Anliegens erforderlich ist. Die Löschung '
            'erfolgt durch uns nach Erledigung; eine automatische Löschung nach '
            'fester Frist ist technisch nicht eingerichtet. Bestehen gesetzliche '
            'Aufbewahrungspflichten, löschen wir erst nach deren Ablauf.',
          ),
          _LegalParagraph(
            'Freiwillig angegebene Kontaktdaten (Einwilligung) löschen wir, '
            'sobald du deine Einwilligung widerrufst oder die Löschung '
            'verlangst.',
          ),
        ],
      ),
    ),
    PublicSection(
      title: '7. Deine Rechte',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _LegalParagraph(
            'Dir stehen nach der DSGVO folgende Rechte zu:',
          ),
          const _LegalBullet('Auskunft über die zu dir gespeicherten Daten '
              '(Art. 15 DSGVO),'),
          const _LegalBullet('Berichtigung unrichtiger Daten (Art. 16 DSGVO),'),
          const _LegalBullet('Löschung (Art. 17 DSGVO),'),
          const _LegalBullet(
              'Einschränkung der Verarbeitung (Art. 18 DSGVO),'),
          const _LegalBullet('Datenübertragbarkeit (Art. 20 DSGVO),'),
          const _LegalBullet('Widerspruch gegen die Verarbeitung '
              '(Art. 21 DSGVO),'),
          const _LegalBullet('Widerruf einer erteilten Einwilligung mit '
              'Wirkung für die Zukunft (Art. 7 Abs. 3 DSGVO).'),
          SizedBox(height: spacing.sm),
          _LegalParagraph(
            'Zur Ausübung genügt eine formlose Nachricht an '
            '${_orPlaceholder(info.email, 'E-Mail-Adresse')}.',
          ),
        ],
      ),
    ),
    const PublicSection(
      title: '8. Beschwerderecht bei der Aufsichtsbehörde',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LegalParagraph(
            'Du hast das Recht, dich bei einer Datenschutz-Aufsichtsbehörde zu '
            'beschweren. Für unsere Standorte in Schleswig-Holstein zuständig '
            'ist:',
          ),
          SizedBox(height: 8),
          _LegalAddressBlock(
            lines: [
              'Unabhängiges Landeszentrum für Datenschutz Schleswig-Holstein',
              'Holstenstraße 98',
              '24103 Kiel',
            ],
          ),
        ],
      ),
    ),
    const PublicSection(
      title: '9. Keine Pflicht zur Bereitstellung, keine automatisierte '
          'Entscheidung',
      child: _LegalParagraph(
        'Die Angabe deiner Kontaktdaten ist freiwillig; ohne einen Wunsch- '
        'bzw. Nachrichtentext können wir dein Anliegen jedoch nicht '
        'bearbeiten. Eine automatisierte Entscheidungsfindung einschließlich '
        'Profiling nach Art. 22 DSGVO findet nicht statt.',
      ),
    ),
  ];
}

/// Adressblock: je Zeile ein [Text] mit etwas Zeilenhöhe (Visitenkarten-Optik).
class _LegalAddressBlock extends StatelessWidget {
  const _LegalAddressBlock({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(line, style: theme.textTheme.bodyLarge),
          ),
      ],
    );
  }
}

/// „Label: Wert"-Zeile (Telefon, E-Mail, Register …).
class _LegalKeyValue extends StatelessWidget {
  const _LegalKeyValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RichText(
      text: TextSpan(
        style: theme.textTheme.bodyLarge,
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }
}

/// Unterüberschrift innerhalb einer Sektion.
class _LegalSubheading extends StatelessWidget {
  const _LegalSubheading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: context.spacing.md, bottom: context.spacing.xs),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style:
              theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// Fließtext-Absatz mit angenehmer Zeilenhöhe.
class _LegalParagraph extends StatelessWidget {
  const _LegalParagraph(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: context.spacing.xs),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
      ),
    );
  }
}

/// Aufzählungspunkt (Bullet + Text).
class _LegalBullet extends StatelessWidget {
  const _LegalBullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = context.spacing;
    return Padding(
      padding: EdgeInsets.only(top: spacing.xs, bottom: spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          SizedBox(width: spacing.sm),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
