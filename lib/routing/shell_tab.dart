/// Die sieben Haupt-Tabs der App-Shell. Die **Reihenfolge ist kanonisch** und
/// entspricht 1:1 den `StatefulShellRoute`-Branches in `app_router.dart`:
/// der Branch-Index ist `ShellTab.values.indexOf(tab)` (stabil 0..6, unabhängig
/// davon, welche Tabs ein Nutzer per Permission tatsächlich sieht).
///
/// Niemals eine Listenposition der sichtbaren Nav-Items als Branch-Index nutzen
/// — immer über diese Enum mappen.
enum ShellTab {
  today,
  plan,
  time,
  inbox,
  contacts,
  shop,
  profile,
}

/// Pfad jeder Shell-Branch (deutsche URLs, in der Domain sichtbar).
const Map<ShellTab, String> shellTabPaths = <ShellTab, String>{
  ShellTab.today: '/',
  ShellTab.plan: '/plan',
  ShellTab.time: '/zeit',
  ShellTab.inbox: '/anfragen',
  ShellTab.contacts: '/kontakte',
  ShellTab.shop: '/laden',
  ShellTab.profile: '/profil',
};

/// Branch-Index einer [ShellTab] (kanonisch, = Position in [ShellTab.values]).
int shellBranchIndex(ShellTab tab) => ShellTab.values.indexOf(tab);

/// Deutsche URL-Pfade der App. Shell-Tab-Pfade stehen in [shellTabPaths]; hier
/// die Gate- und Hauptbereich-Routen. Liegt bewusst neben [ShellTab], damit
/// sowohl `app_router.dart` als auch die Screens die Konstanten teilen können
/// (kein zyklischer Import über den Router).
abstract final class AppRoutes {
  // Gate-Routen (Vollbild, Root-Navigator).
  static const String start = '/start'; // Splash / Lade-Zustand
  static const String login = '/anmelden';
  static const String setup = '/einrichtung';
  static const String blocked = '/gesperrt';
  static const String update = '/aktualisierung';

  // Arbeitsmodus / Laden-Tablet (Kiosk): Vollbild-Board statt Shell. Aktiv nur
  // im Kiosk-Build (`AppConfig.kioskModeEnabled`); der Gate-Redirect erzwingt
  // diese Route und sperrt die normale Navigation.
  static const String kiosk = '/arbeitsmodus';

  // Hauptbereich-Routen (über die Shell gepusht, single canonical route je Screen).
  static const String kennzahlen = '/kennzahlen'; // Management-Dashboard (REPORTING-4)
  static const String mitteilungen = '/mitteilungen'; // Inbox (PERSONAL-9/Q4)
  static const String inventory = '/warenwirtschaft';
  static const String customerOrders = '/bestellungen';
  static const String paketshop = '/paketshop'; // Paketshop (Plan §7.6)
  static const String personal = '/personal';
  // Mitarbeiter-Detail (AllTec-1:1): deep-linkbare Top-Level-Route mit
  // Path-Parameter `:id` (uid). Bau siehe plan/personal-alltec-1zu1.md.
  static const String personalDetail = '/personal/:id';
  // Kontakt-Detail (AllTec-1:1): deep-linkbare Top-Level-Route mit Path-
  // Parameter `:id` (contactId). Lese-Gate = canViewContacts (jedes aktive
  // Mitglied), NICHT admin-only wie Personal. Bau siehe
  // plan/kontakte-alltec-1zu1.md.
  static const String contactDetail = '/kontakte/:id';
  static const String meineAkte = '/meine-akte'; // Mitarbeiter-Selbstsicht (PA-2.4)
  static const String finance = '/buchhaltung';
  static const String feedbackInbox = '/feedback-eingang';
  static const String auditLog = '/protokoll';
  static const String settings = '/einstellungen';
  static const String monthReport = '/monatsbericht';
  static const String statistics = '/statistik';
  static const String customerWishes = '/kundenwuensche';
  static const String scanner = '/scanner';
  static const String orderAnalytics = '/bestell-auswertung';
  static const String bestandInsights = '/bestand-insights';
  static const String sortiment = '/sortimentsanalyse';
  // Geführter Inventur-Modus (Bestandszählung je Standort/Warengruppe):
  // Zähl-Liste + Differenz-Vorschau + Buchung via recordStocktake. Gate =
  // canManageInventory (er bucht Bestand), enger als die übrige Warenwirtschaft.
  static const String inventur = '/inventur';
  static const String staffingProfile = '/besetzungs-profil';
  static const String dailyClosing = '/tagesabschluss';
  static const String kassenbericht = '/kassenbericht';
  static const String passwords = '/passwoerter';
  static const String storeHealth = '/laden-benchmark';
  static const String cashierAnomaly = '/kassierer-pruefung';

  /// Digitale Werbe-Displays (Store-TVs): admin-only Verwaltung (Bilder,
  /// Playlists, Displays). Der öffentliche Player läuft NICHT über den go_router,
  /// sondern als isolierte Web-Route `/anzeige/<token>` (siehe main.dart).
  static const String signage = '/werbung';

  /// Wissens-/Hilfe-Bereich (In-App-Doku, Bereich „Wissen"). Fach-Doku fuer alle
  /// angemeldeten Nutzer; die Entwickler-/Technik-Doku gated der Screen intern
  /// auf Admins.
  static const String knowledge = '/wissen';

  // Zeitwirtschaft-Bereich (Sub-Routen unter dem `/zeit`-Tab-Hub). Der Hub
  // selbst ist der Tab-Inhalt von `ShellTab.time` (`/zeit`); diese Routen werden
  // via `context.push(...)` über die Shell gepusht (Back → Hub).
  static const String zeitErfassung = '/zeit/erfassung';
  static const String zeitStempeln = '/zeit/stempeln';
  static const String zeitStundenkonto = '/zeit/stundenkonto';
  static const String zeitAbwesenheiten = '/zeit/abwesenheiten';
  static const String zeitAbwesenheitenKalender = '/zeit/abwesenheiten/kalender';
  static const String zeitMonatsabschluss = '/zeit/monatsabschluss';
  static const String zeitMitarbeiterabschluss = '/zeit/mitarbeiterabschluss';
  static const String zeitLohnlauf = '/zeit/lohnlauf';

  /// Konkreter Deep-Link auf die Mitarbeiter-Detailseite `/personal/{uid}`
  /// (füllt den `:id`-Parameter von [personalDetail]).
  static String personalDetailPath(String uid) => '/personal/$uid';

  /// Konkreter Deep-Link auf die Kontakt-Detailseite `/kontakte/{contactId}`
  /// (füllt den `:id`-Parameter von [contactDetail]).
  static String contactDetailPath(String contactId) => '/kontakte/$contactId';
}
