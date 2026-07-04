import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Prüft die reale Doku auf der Platte (cwd = Paket-Root): jede im
/// `docs/manifest.json` referenzierte Datei existiert, beginnt mit `# Titel`,
/// hat ein gültiges `roleGate`/`audience`, und alle `article:`-Querverweise
/// zeigen auf existierende Slugs.
void main() {
  test('manifest.json ist konsistent mit den Markdown-Dateien', () {
    final manifest =
        json.decode(File('docs/manifest.json').readAsStringSync()) as Map;
    final sections = manifest['sections'] as List;

    final slugs = <String>{};
    final articles = <Map>[];
    for (final section in sections) {
      expect(['mitarbeiter', 'entwickler'], contains(section['audience']));
      for (final article in (section['articles'] as List)) {
        final a = article as Map;
        expect(slugs.add(a['slug'] as String), isTrue,
            reason: 'Doppelter slug: ${a['slug']}');
        articles.add(a);
      }
    }
    expect(articles.length, greaterThanOrEqualTo(40));

    final linkRe = RegExp(r'\]\(article:([a-z0-9-]+)\)');
    for (final a in articles) {
      final file = File('docs/${a['file']}');
      expect(file.existsSync(), isTrue, reason: 'Datei fehlt: ${a['file']}');
      final text = file.readAsStringSync();
      expect(text.trimLeft().startsWith('# '), isTrue,
          reason: '${a['file']} beginnt nicht mit "# Titel"');
      expect(['all', 'manager', 'admin'], contains(a['roleGate']),
          reason: 'Ungültiges roleGate in ${a['slug']}');
      for (final m in linkRe.allMatches(text)) {
        expect(slugs.contains(m.group(1)), isTrue,
            reason: 'Kaputter article:-Link "${m.group(1)}" in ${a['file']}');
      }
    }
  });
}
