import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/doc_article.dart';

AppUserProfile _user(String role, {bool active = true}) =>
    AppUserProfile.fromMap({
      'uid': 'u',
      'org_id': 'o',
      'email': 'a@b.c',
      'role': role,
      'is_active': active,
    });

Map<String, dynamic> _manifest() => {
      'sections': [
        {
          'id': 'sec-b',
          'title': 'Zweiter',
          'audience': 'mitarbeiter',
          'icon': 'today',
          'order': 2,
          'articles': [
            {'slug': 'b1', 'title': 'B1', 'file': 'mitarbeiter/b1.md', 'roleGate': 'all', 'summary': 's', 'keywords': ['urlaub']},
          ],
        },
        {
          'id': 'sec-a',
          'title': 'Erster',
          'audience': 'mitarbeiter',
          'icon': 'rocket_launch',
          'order': 1,
          'articles': [
            {'slug': 'a-all', 'title': 'Alle', 'file': 'mitarbeiter/a-all.md', 'roleGate': 'all'},
            {'slug': 'a-mgr', 'title': 'Manager', 'file': 'mitarbeiter/a-mgr.md', 'roleGate': 'manager'},
            {'slug': 'a-adm', 'title': 'Admin', 'file': 'mitarbeiter/a-adm.md', 'roleGate': 'admin'},
          ],
        },
        {
          'id': 'sec-dev',
          'title': 'Technik',
          'audience': 'entwickler',
          'icon': 'architecture',
          'order': 20,
          'articles': [
            {'slug': 'dev-x', 'title': 'Dev X', 'file': 'entwickler/dev-x.md', 'roleGate': 'admin'},
          ],
        },
      ],
    };

void main() {
  group('DocManifest parsing', () {
    test('sortiert Abschnitte nach order und baut Asset-Pfade', () {
      final m = DocManifest.fromManifest(_manifest());
      expect(m.sections.map((s) => s.id), ['sec-a', 'sec-b', 'sec-dev']);
      expect(m.articleBySlug('b1')?.assetPath, 'docs/mitarbeiter/b1.md');
      expect(m.allArticles.length, 5);
      expect(m.articleBySlug('a-mgr')?.roleGate, DocRoleGate.manager);
      expect(m.articleBySlug('dev-x')?.audience, DocAudience.entwickler);
    });
  });

  group('DocArticle.isVisibleTo', () {
    final m = DocManifest.fromManifest(_manifest());
    DocArticle a(String slug) => m.articleBySlug(slug)!;

    test('Mitarbeiter sieht nur roleGate all der Fach-Doku', () {
      final emp = _user('employee');
      expect(a('a-all').isVisibleTo(emp), isTrue);
      expect(a('a-mgr').isVisibleTo(emp), isFalse);
      expect(a('a-adm').isVisibleTo(emp), isFalse);
      expect(a('dev-x').isVisibleTo(emp), isFalse);
    });

    test('Teamleitung sieht all + manager, nicht admin/entwickler', () {
      final tl = _user('teamlead');
      expect(a('a-all').isVisibleTo(tl), isTrue);
      expect(a('a-mgr').isVisibleTo(tl), isTrue);
      expect(a('a-adm').isVisibleTo(tl), isFalse);
      expect(a('dev-x').isVisibleTo(tl), isFalse);
    });

    test('Admin sieht alles inkl. Entwickler-Doku', () {
      final adm = _user('admin');
      expect(a('a-all').isVisibleTo(adm), isTrue);
      expect(a('a-mgr').isVisibleTo(adm), isTrue);
      expect(a('a-adm').isVisibleTo(adm), isTrue);
      expect(a('dev-x').isVisibleTo(adm), isTrue);
    });

    test('kein/inaktives Profil sieht nichts', () {
      expect(a('a-all').isVisibleTo(null), isFalse);
      expect(a('a-all').isVisibleTo(_user('admin', active: false)), isFalse);
    });
  });
}
