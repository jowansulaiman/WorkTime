import '../core/firestore_num_parser.dart' as parse;
import 'app_user.dart';

/// Zielgruppe eines Doku-Artikels. `mitarbeiter` = Fach-/Bedien-Doku (fuer alle
/// angemeldeten Nutzer), `entwickler` = technische Doku (nur Admins im Viewer).
enum DocAudience {
  mitarbeiter,
  entwickler;

  static DocAudience fromValue(String? value) {
    return value?.trim().toLowerCase() == 'entwickler'
        ? DocAudience.entwickler
        : DocAudience.mitarbeiter;
  }
}

/// Sichtbarkeits-Gate eines Artikels — abgestuft, damit die Doku denselben
/// Rollen folgt wie die App selbst (siehe `RoutePermissions` / `AppUserProfile`).
enum DocRoleGate {
  /// Jeder angemeldete, aktive Nutzer.
  all,

  /// Fuehrungskraefte (Admin oder Schichtleitung / `canManageShifts`).
  manager,

  /// Nur Admins.
  admin;

  static DocRoleGate fromValue(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'admin':
        return DocRoleGate.admin;
      case 'manager':
        return DocRoleGate.manager;
      default:
        return DocRoleGate.all;
    }
  }
}

/// Ein einzelner Doku-Artikel (eine `.md`-Datei). Traegt zur Vereinfachung des
/// Viewers/der Suche auch den Kontext seines Abschnitts (Titel/Icon/Audience).
class DocArticle {
  const DocArticle({
    required this.slug,
    required this.title,
    required this.assetPath,
    required this.roleGate,
    required this.summary,
    required this.keywords,
    required this.sectionId,
    required this.sectionTitle,
    required this.sectionIcon,
    required this.audience,
  });

  /// Eindeutiger Kurz-Schluessel (kebab-case). Ziel von `article:<slug>`-Links.
  final String slug;
  final String title;

  /// Voller Asset-Pfad, z. B. `docs/mitarbeiter/willkommen.md`.
  final String assetPath;
  final DocRoleGate roleGate;
  final String summary;
  final List<String> keywords;

  final String sectionId;
  final String sectionTitle;
  final String sectionIcon;
  final DocAudience audience;

  /// Darf [profile] diesen Artikel sehen? Entwickler-Doku ist immer admin-only;
  /// darueber hinaus greift das feingranulare [roleGate].
  bool isVisibleTo(AppUserProfile? profile) {
    if (profile == null || !profile.isActive) {
      return false;
    }
    if (audience == DocAudience.entwickler && !profile.isAdmin) {
      return false;
    }
    return switch (roleGate) {
      DocRoleGate.all => true,
      DocRoleGate.manager => profile.isAdmin || profile.canManageShifts,
      DocRoleGate.admin => profile.isAdmin,
    };
  }

  factory DocArticle.fromManifest(
    Map<String, dynamic> map, {
    required String sectionId,
    required String sectionTitle,
    required String sectionIcon,
    required DocAudience audience,
  }) {
    final file = (map['file'] ?? '').toString();
    return DocArticle(
      slug: (map['slug'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      assetPath: 'docs/$file',
      roleGate: DocRoleGate.fromValue(map['roleGate']?.toString()),
      summary: (map['summary'] ?? '').toString(),
      keywords: _stringList(map['keywords']),
      sectionId: sectionId,
      sectionTitle: sectionTitle,
      sectionIcon: sectionIcon,
      audience: audience,
    );
  }
}

/// Ein Abschnitt (Kapitel) der Doku mit seinen Artikeln.
class DocSection {
  const DocSection({
    required this.id,
    required this.title,
    required this.audience,
    required this.icon,
    required this.order,
    required this.articles,
  });

  final String id;
  final String title;
  final DocAudience audience;

  /// Material-Icon-Name (aufgeloest via `docIcon(...)`).
  final String icon;
  final int order;
  final List<DocArticle> articles;

  /// Die fuer [profile] sichtbaren Artikel dieses Abschnitts.
  List<DocArticle> visibleArticles(AppUserProfile? profile) =>
      articles.where((a) => a.isVisibleTo(profile)).toList();

  factory DocSection.fromManifest(Map<String, dynamic> map) {
    final id = (map['id'] ?? '').toString();
    final title = (map['title'] ?? '').toString();
    final icon = (map['icon'] ?? 'menu_book').toString();
    final audience = DocAudience.fromValue(map['audience']?.toString());
    final articles = <DocArticle>[
      for (final raw in _mapList(map['articles']))
        DocArticle.fromManifest(
          raw,
          sectionId: id,
          sectionTitle: title,
          sectionIcon: icon,
          audience: audience,
        ),
    ];
    return DocSection(
      id: id,
      title: title,
      audience: audience,
      icon: icon,
      order: parse.toInt(map['order']) ?? 0,
      articles: articles,
    );
  }
}

/// Der komplette Doku-Baum (`docs/manifest.json`).
class DocManifest {
  const DocManifest({required this.sections});

  final List<DocSection> sections;

  /// Alle Artikel flach (fuer Suche / `slug`-Aufloesung).
  List<DocArticle> get allArticles =>
      sections.expand((s) => s.articles).toList();

  DocArticle? articleBySlug(String slug) {
    for (final s in sections) {
      for (final a in s.articles) {
        if (a.slug == slug) {
          return a;
        }
      }
    }
    return null;
  }

  factory DocManifest.fromManifest(Map<String, dynamic> map) {
    final sections = <DocSection>[
      for (final raw in _mapList(map['sections']))
        DocSection.fromManifest(raw),
    ]..sort((a, b) => a.order.compareTo(b.order));
    return DocManifest(sections: sections);
  }
}

List<String> _stringList(dynamic value) {
  if (value is List) {
    return value.map((e) => e.toString()).toList();
  }
  return const <String>[];
}

List<Map<String, dynamic>> _mapList(dynamic value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }
  return const <Map<String, dynamic>>[];
}
