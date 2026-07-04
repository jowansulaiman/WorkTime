import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../models/app_user.dart';
import '../models/doc_article.dart';

/// Ein Treffer der Doku-Suche samt Relevanz-Score.
class DocSearchHit {
  const DocSearchHit(this.article, this.score);
  final DocArticle article;
  final int score;
}

/// Marker-Body, den [DocRepository.loadArticleBody] liefert, wenn die `.md`-Datei
/// (noch) nicht als Asset vorhanden ist. So bleibt der Viewer robust, waehrend
/// die Doku waechst — statt eines Absturzes zeigt der Artikel einen Hinweis.
const String kDocArticlePendingMarker = '@@doc-pending@@';

/// Laedt den Doku-Baum (`docs/manifest.json`) und die einzelnen Artikel-`.md`
/// aus dem Asset-Bundle. [bundle] ist injizierbar (Tests nutzen ein Fake).
class DocRepository {
  DocRepository({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  /// Prozessweite Standard-Instanz (liest die gebuendelten Assets). Die Screens
  /// verwenden diese; Tests konstruieren eine eigene mit Fake-Bundle.
  static final DocRepository instance = DocRepository();

  final AssetBundle _bundle;
  DocManifest? _manifest;
  final Map<String, String> _bodyCache = <String, String>{};

  Future<DocManifest> loadManifest() async {
    final cached = _manifest;
    if (cached != null) {
      return cached;
    }
    final raw = await _bundle.loadString('docs/manifest.json');
    final decoded = json.decode(raw);
    final map = (decoded as Map).map((k, v) => MapEntry(k.toString(), v));
    final manifest = DocManifest.fromManifest(map);
    _manifest = manifest;
    return manifest;
  }

  /// Roh-Markdown eines Artikels. Fehlt das Asset (Doku noch in Arbeit), wird
  /// [kDocArticlePendingMarker] zurueckgegeben statt zu werfen.
  Future<String> loadArticleBody(DocArticle article) async {
    final cached = _bodyCache[article.assetPath];
    if (cached != null) {
      return cached;
    }
    String body;
    try {
      body = await _bundle.loadString(article.assetPath);
    } catch (_) {
      body = kDocArticlePendingMarker;
    }
    _bodyCache[article.assetPath] = body;
    return body;
  }

  /// Metadaten-Suche (Titel, Schlagworte, Zusammenfassung, Abschnitt) ueber alle
  /// fuer [profile] sichtbaren Artikel. Bewusst kein Volltext — schnell + offline.
  List<DocSearchHit> search(
    DocManifest manifest,
    String query,
    AppUserProfile? profile,
  ) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return const <DocSearchHit>[];
    }
    final terms =
        normalized.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final hits = <DocSearchHit>[];
    for (final article in manifest.allArticles) {
      if (!article.isVisibleTo(profile)) {
        continue;
      }
      final title = article.title.toLowerCase();
      final summary = article.summary.toLowerCase();
      final keywords = article.keywords.map((k) => k.toLowerCase()).join(' ');
      final section = article.sectionTitle.toLowerCase();
      var score = 0;
      for (final term in terms) {
        if (title.contains(term)) score += 10;
        if (title.startsWith(term)) score += 6;
        if (keywords.contains(term)) score += 6;
        if (summary.contains(term)) score += 3;
        if (section.contains(term)) score += 2;
      }
      if (score > 0) {
        hits.add(DocSearchHit(article, score));
      }
    }
    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits;
  }

  @visibleForTesting
  void clearCache() {
    _manifest = null;
    _bodyCache.clear();
  }
}
