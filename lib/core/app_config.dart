import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig._();

  static const bool disableAuthentication = bool.fromEnvironment(
    'APP_DISABLE_AUTH',
    defaultValue: false,
  );

  static const String defaultOrganizationId = String.fromEnvironment(
    'APP_DEFAULT_ORG_ID',
    defaultValue: 'main-org',
  );

  static const String defaultOrganizationName = String.fromEnvironment(
    'APP_DEFAULT_ORG_NAME',
    defaultValue: 'Worktime',
  );

  /// Laden-Namen, die auf der öffentlichen Kundenwunsch-Seite (`/wunsch`) zur
  /// Auswahl stehen. Klartext, da anonyme Kunden keine internen siteIds kennen
  /// und die Seite (bewusst) keine Stammdaten liest. Per
  /// `--dart-define=APP_PUBLIC_STORES="Laden A,Laden B"` überschreibbar.
  static const String publicStoreNames = String.fromEnvironment(
    'APP_PUBLIC_STORES',
    defaultValue: 'Strichmännchen,Tabak Börse',
  );

  static List<String> get publicStoreNameList => publicStoreNames
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);

  static const String bootstrapAdminEmails = String.fromEnvironment(
    'APP_BOOTSTRAP_ADMIN_EMAILS',
    defaultValue: '',
  );

  /// reCAPTCHA-v3-Site-Key für Firebase App Check (Web). Wird per
  /// `--dart-define=APP_APPCHECK_RECAPTCHA_KEY=<key>` gesetzt. Leer ⇒ App Check
  /// wird NICHT aktiviert (Dev/Test). Schützt v.a. den öffentlichen
  /// Schreibpfad (/wunsch); zusätzlich Enforcement in der Firebase-Console.
  static const String appCheckRecaptchaKey = String.fromEnvironment(
    'APP_APPCHECK_RECAPTCHA_KEY',
    defaultValue: '',
  );

  static bool get appCheckEnabled => appCheckRecaptchaKey.trim().isNotEmpty;

  // --- Rechtliche Pflichtangaben (Impressum / Datenschutz) -----------------
  // Betreiber-/Verantwortlichen-Stammdaten der öffentlichen Seiten (/wunsch,
  // /feedback, /impressum, /datenschutz). Bewusst per dart-define konfigurierbar
  // (analog `APP_PUBLIC_STORES`) — KEINE privaten Daten im Repo. Die Defaults
  // sind absichtlich leer: Solange die Pflichtfelder fehlen, zeigen Impressum &
  // Datenschutz einen sichtbaren „noch zu hinterlegen"-Hinweis statt falscher
  // Angaben (siehe `LegalInfo.isComplete`). Vor Veröffentlichung ausfüllen
  // (per dart-define ODER indem die Defaults hier ersetzt werden) und rechtlich
  // prüfen lassen.

  /// Inhaber/Betreiber bzw. vollständiger Firmenname (§ 5 DDG, Art. 13 DSGVO).
  /// Bei Handelsregister-Eintragung (e.K./OHG/GmbH …) MUSS hier die vollständige
  /// Firma inkl. Rechtsformzusatz stehen und `APP_LEGAL_REGISTER` gesetzt sein.
  static const String legalOperatorName = String.fromEnvironment(
    'APP_LEGAL_OPERATOR_NAME',
    defaultValue: '',
  );

  /// Straße und Hausnummer der ladungsfähigen Anschrift.
  static const String legalStreet = String.fromEnvironment(
    'APP_LEGAL_STREET',
    defaultValue: '',
  );

  /// PLZ und Ort der ladungsfähigen Anschrift (z. B. „24103 Kiel").
  static const String legalPostalCity = String.fromEnvironment(
    'APP_LEGAL_POSTAL_CITY',
    defaultValue: '',
  );

  /// Kontakt-E-Mail (Pflicht für schnelle elektronische Kontaktaufnahme).
  static const String legalEmail = String.fromEnvironment(
    'APP_LEGAL_EMAIL',
    defaultValue: '',
  );

  /// Kontakt-Telefonnummer (optional, aber empfohlen).
  static const String legalPhone = String.fromEnvironment(
    'APP_LEGAL_PHONE',
    defaultValue: '',
  );

  /// Vertretungsberechtigte Person (nur bei juristischen Personen / GmbH/UG).
  static const String legalRepresentative = String.fromEnvironment(
    'APP_LEGAL_REPRESENTATIVE',
    defaultValue: '',
  );

  /// Umsatzsteuer-Identifikationsnummer gem. § 27 a UStG (optional).
  static const String legalVatId = String.fromEnvironment(
    'APP_LEGAL_VAT_ID',
    defaultValue: '',
  );

  /// Registereintrag „Registergericht / Registernummer". Optional für reine
  /// Einzelunternehmen, aber **Pflicht** (§ 5 Abs. 1 Nr. 4 DDG), sobald im
  /// Handels-/Vereins-/Partnerschafts-/Genossenschaftsregister eingetragen.
  static const String legalRegisterEntry = String.fromEnvironment(
    'APP_LEGAL_REGISTER',
    defaultValue: '',
  );

  /// Inhaltlich Verantwortlicher i. S. d. § 18 Abs. 2 MStV. **Opt-in**: nur
  /// setzen, wenn das Angebot journalistisch-redaktionelle Inhalte enthält
  /// (reine Eingabeformulare lösen die MStV-Pflicht NICHT aus). Leer ⇒ der
  /// MStV-Block wird gar nicht angezeigt.
  static const String legalContentResponsible = String.fromEnvironment(
    'APP_LEGAL_CONTENT_RESPONSIBLE',
    defaultValue: '',
  );

  /// Stand/Datum der Rechtstexte (z. B. „Juni 2026"). Optional; wenn gesetzt,
  /// als „Stand: …" auf Impressum/Datenschutz angezeigt.
  static const String legalLastUpdated = String.fromEnvironment(
    'APP_LEGAL_LAST_UPDATED',
    defaultValue: '',
  );

  static const String firebaseFunctionsRegion = String.fromEnvironment(
    'FIREBASE_FUNCTIONS_REGION',
    defaultValue: 'europe-west3',
  );

  /// Schaltet die OktoPOS-Kassenanbindung in der UI frei (Admin-Aktion
  /// „Verkäufe aus Kasse übernehmen"). Default aus, bis die Schnittstelle beim
  /// Hersteller freigeschaltet, der Secret-Key (`OKTOPOS_API_KEYS`) gesetzt und
  /// das Config-Dokument `config/oktoposSync` (baseUrl + cashRegisterId je
  /// Standort) gepflegt ist. Per `--dart-define=APP_OKTOPOS_ENABLED=true` an.
  /// **Kein Secret** — nur ein Sichtbarkeits-Schalter; API-Key liegt
  /// ausschließlich serverseitig im Secret Manager.
  static const bool oktoposEnabled = bool.fromEnvironment(
    'APP_OKTOPOS_ENABLED',
    defaultValue: false,
  );

  /// Schaltet mobile Push-Benachrichtigungen (FCM) frei. Default aus, bis der
  /// APNs-Auth-Key (iOS), die sendenden Cloud Functions und (für Web, M6) der
  /// VAPID-Key bereitstehen — also bis zum Blaze-Cutover. Per
  /// `--dart-define=APP_PUSH_ENABLED=true` an. **Kein Secret** — nur ein
  /// Sichtbarkeits-/Aktivierungs-Schalter. Die FCM-Init ist zusätzlich gegen
  /// `DefaultFirebaseOptions.isConfigured` gegated → No-op im
  /// APP_DISABLE_AUTH-/Offline-Demo-Modus (kein Firebase ⇒ kein Messaging).
  static const bool pushEnabled = bool.fromEnvironment(
    'APP_PUSH_ENABLED',
    defaultValue: false,
  );

  /// Schaltet den **Passwortmanager** frei. Rein server-verschlüsselt (Cloud
  /// KMS + Callables) → funktioniert NUR mit echtem Firebase/Blaze. Default aus,
  /// bis KMS-Key + Callables deployt sind. Per
  /// `--dart-define=APP_PASSWORD_MANAGER_ENABLED=true` an. Zusätzlich gegen
  /// `disableAuthentication` gegated → im Offline-/Demo-Modus komplett
  /// ausgeblendet (kein halb-degradiertes Feature).
  static const bool _passwordManagerFlag = bool.fromEnvironment(
    'APP_PASSWORD_MANAGER_ENABLED',
    defaultValue: false,
  );

  /// Effektiv nur an, wenn der Schalter gesetzt UND echtes Firebase aktiv ist.
  static bool get passwordManagerEnabled =>
      _passwordManagerFlag && !disableAuthentication;

  /// Schaltet den **Arbeitsmodus / Laden-Tablet (Kiosk)** frei. Ein dediziertes,
  /// fest im Laden installiertes Tablet läuft mit `--dart-define=APP_KIOSK_ENABLED=true`
  /// → der Gate-Redirect lenkt es auf das Vollbild-Board (`/arbeitsmodus`) und
  /// die normale Shell ist nicht erreichbar. **Kein Secret** — nur ein
  /// Geräte-/Build-Schalter. Default aus (normale App). In Increment 0 offline
  /// testbar (zusammen mit `APP_DISABLE_AUTH`); die server-geprüfte PIN folgt.
  static const bool kioskModeEnabled = bool.fromEnvironment(
    'APP_KIOSK_ENABLED',
    defaultValue: false,
  );

  /// Fester Laden (Standort-`siteId`), an den das Kiosk-Tablet gebunden ist
  /// (E2: „fest pro Laden"). Bestimmt die Filterung von Kundenwünschen,
  /// Kühlschrank-Alarmen und Laden-To-Dos. Leer ⇒ erster verfügbarer Standort
  /// (Demo/Increment 0). Per `--dart-define=APP_KIOSK_SITE_ID=<siteId>`.
  static const String kioskSiteId = String.fromEnvironment(
    'APP_KIOSK_SITE_ID',
  );

  /// Web-Push-Zertifikat (VAPID public key) aus Firebase-Console → Cloud
  /// Messaging → Web Push certificates. NUR für Web nötig
  /// (`getToken(vapidKey:)`); leer ⇒ es wird kein Web-Token angefordert
  /// (mobiler Push bleibt davon unberührt). M6 (Stretch).
  static const String webPushVapidKey = String.fromEnvironment(
    'APP_WEB_PUSH_VAPID_KEY',
  );

  /// Build-Nummer dieses Binaries (no-feature-flags-force-update). Wird von der
  /// Release-Pipeline via `--dart-define=APP_BUILD_NUMBER=<github.run_number>`
  /// gesetzt; lokale/Dev-Builds bleiben bei 0 und werden NIE per Force-Update
  /// blockiert (siehe FeatureFlagProvider.requiresUpdate).
  static const int buildNumber = int.fromEnvironment(
    'APP_BUILD_NUMBER',
    defaultValue: 0,
  );

  /// Dev-/Test-Override fuer das Signal-Teal-Redesign (Flag `redesign_v2`).
  /// Erlaubt, die V2-Optik offline bzw. im APP_DISABLE_AUTH-Demo-Modus zu
  /// testen, wo es keine Remote-Config gibt
  /// (`flutter run --dart-define=APP_REDESIGN_V2=true`). Produktiv steuert das
  /// org-seitige Flag ueber den FeatureFlagProvider; dieser Override gewinnt
  /// immer (Aufloesung in RedesignFlags).
  static const bool redesignV2Override = bool.fromEnvironment(
    'APP_REDESIGN_V2',
    defaultValue: false,
  );

  static List<String> get bootstrapAdminEmailList => bootstrapAdminEmails
      .split(',')
      .map((value) => value.trim().toLowerCase())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);

  static void validateEnvironment() {
    // !kDebugMode deckt Release UND Profile ab. Ein Profile-Build ist
    // verteilungs-/performancenah und darf die Auth-Schranke ebenso wenig
    // umgehen wie ein Release-Build (probleme #32).
    if (!kDebugMode && disableAuthentication) {
      throw StateError(
        'APP_DISABLE_AUTH darf nur in Debug-Builds aktiviert sein '
        '(weder Release noch Profile).',
      );
    }
  }
}
