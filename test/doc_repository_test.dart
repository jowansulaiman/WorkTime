import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/services/doc_repository.dart';

class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.files);
  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final value = files[key];
    if (value == null) {
      throw Exception('Asset nicht gefunden: $key');
    }
    final bytes = utf8.encode(value);
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }
}

AppUserProfile _admin() => AppUserProfile.fromMap({
      'uid': 'u',
      'org_id': 'o',
      'email': 'a@b.c',
      'role': 'admin',
      'is_active': true,
    });

void main() {
  const manifest = '''
  {
    "sections": [
      {"id":"s","title":"Start","audience":"mitarbeiter","icon":"today","order":1,
       "articles":[
         {"slug":"da","title":"Da","file":"mitarbeiter/da.md","roleGate":"all","summary":"Über Urlaub","keywords":["urlaub","antrag"]},
         {"slug":"weg","title":"Weg","file":"mitarbeiter/weg.md","roleGate":"all","summary":"fehlt","keywords":["kasse"]}
       ]}
    ]
  }''';

  late DocRepository repo;
  setUp(() {
    repo = DocRepository(
      bundle: _FakeBundle({
        'docs/manifest.json': manifest,
        'docs/mitarbeiter/da.md': '# Da\n\nInhalt vorhanden.',
        // 'weg.md' fehlt absichtlich.
      }),
    );
  });

  test('loadManifest liest und cached', () async {
    final m = await repo.loadManifest();
    expect(m.allArticles.length, 2);
    expect(identical(await repo.loadManifest(), m), isTrue);
  });

  test('loadArticleBody liefert Inhalt bzw. Pending-Marker bei fehlender Datei',
      () async {
    final m = await repo.loadManifest();
    final present = await repo.loadArticleBody(m.articleBySlug('da')!);
    expect(present, contains('Inhalt vorhanden'));
    final missing = await repo.loadArticleBody(m.articleBySlug('weg')!);
    expect(missing, kDocArticlePendingMarker);
  });

  test('search bewertet Titel/Schlagworte und respektiert Sichtbarkeit',
      () async {
    final m = await repo.loadManifest();
    final hits = repo.search(m, 'urlaub', _admin());
    expect(hits, isNotEmpty);
    expect(hits.first.article.slug, 'da');
    expect(repo.search(m, 'urlaub', null), isEmpty); // kein Profil → nichts
    expect(repo.search(m, '', _admin()), isEmpty); // leere Suche
  });
}
