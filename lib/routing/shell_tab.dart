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

  // Hauptbereich-Routen (über die Shell gepusht, single canonical route je Screen).
  static const String inventory = '/warenwirtschaft';
  static const String customerOrders = '/bestellungen';
  static const String personal = '/personal';
  static const String finance = '/buchhaltung';
  static const String feedbackInbox = '/feedback-eingang';
  static const String auditLog = '/protokoll';
  static const String team = '/team';
  static const String settings = '/einstellungen';
  static const String monthReport = '/monatsbericht';
  static const String statistics = '/statistik';
  static const String customerWishes = '/kundenwuensche';
  static const String scanner = '/scanner';
}
