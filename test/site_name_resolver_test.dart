import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/site_name_resolver.dart';
import 'package:worktime_app/models/site_definition.dart';

void main() {
  const sites = [
    SiteDefinition(id: 's1', orgId: 'o', name: 'Strichmännchen'),
    SiteDefinition(id: 's2', orgId: 'o', name: 'Tabak Börse'),
  ];

  group('resolveSiteName', () {
    test('liefert den aktuellen Namen aus der siteId (SSoT)', () {
      // Snapshot ist veraltet ("Alter Name"), Resolver gewinnt.
      expect(
        resolveSiteName(sites, 's2', fallback: 'Alter Name'),
        'Tabak Börse',
      );
    });

    test('fällt auf den Snapshot zurück, wenn der Standort fehlt', () {
      expect(
        resolveSiteName(sites, 'geloescht', fallback: 'Ex-Laden'),
        'Ex-Laden',
      );
    });

    test('null/leere siteId → Fallback (oder null)', () {
      expect(resolveSiteName(sites, null, fallback: 'Allgemein'), 'Allgemein');
      expect(resolveSiteName(sites, '', fallback: null), isNull);
      expect(resolveSiteName(const [], null), isNull);
    });

    test('leerer Fallback wird zu null normalisiert', () {
      expect(resolveSiteName(sites, 'unbekannt', fallback: '   '), isNull);
    });
  });
}
