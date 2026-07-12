import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/ad_media.dart';
import 'package:worktime_app/models/signage_display.dart';

void main() {
  group('AdMedia – Zwei-Serialisierung', () {
    const media = AdMedia(
      id: 'm1',
      orgId: 'org-1',
      title: 'Sommeraktion',
      storagePath: 'organizations/org-1/signage/m1.jpg',
      downloadUrl: 'https://example/x?alt=media&token=abc',
      contentType: 'image/png',
      fileSize: 12345,
      createdByUid: 'u1',
    );

    test('toMap/fromMap (snake_case) rundläuft', () {
      final restored = AdMedia.fromMap(media.toMap());
      expect(restored.id, 'm1');
      expect(restored.orgId, 'org-1');
      expect(restored.title, 'Sommeraktion');
      expect(restored.storagePath, media.storagePath);
      expect(restored.downloadUrl, media.downloadUrl);
      expect(restored.contentType, 'image/png');
      expect(restored.fileSize, 12345);
      expect(restored.createdByUid, 'u1');
    });

    test('toFirestoreMap ist camelCase + trägt titleLower (Sortierschlüssel)',
        () {
      final map = media.toFirestoreMap();
      expect(map['title'], 'Sommeraktion');
      expect(map['titleLower'], 'sommeraktion');
      expect(map['storagePath'], media.storagePath);
      expect(map['downloadUrl'], media.downloadUrl);
      // createdAt setzt das Repository via serverTimestamp beim Anlegen.
      expect(map.containsKey('createdAt'), isFalse);
    });

    test('fromFirestore liest camelCase + Timestamp', () {
      final map = {
        ...media.toFirestoreMap(),
        'createdAt': Timestamp.fromDate(DateTime(2026, 7, 8)),
      };
      final restored = AdMedia.fromFirestore('m1', map);
      expect(restored.id, 'm1');
      expect(restored.title, 'Sommeraktion');
      expect(restored.createdAt, DateTime(2026, 7, 8));
    });
  });

  group('SignageDisplay – Zwei-Serialisierung', () {
    const display = SignageDisplay(
      id: 'd1',
      orgId: 'org-1',
      name: 'Schaufenster',
      siteId: 'site-a',
      pairingToken: 'TOKEN123',
      slideSeconds: 12,
      fit: SignageFit.contain,
      transition: SignageTransition.kenBurns,
      mediaIds: ['m1', 'm2', 'm3'],
      isActive: false,
      createdByUid: 'u1',
    );

    test('toMap/fromMap rundläuft inkl. mediaIds + fit/transition-Enum', () {
      final restored = SignageDisplay.fromMap(display.toMap());
      expect(restored.id, 'd1');
      expect(restored.name, 'Schaufenster');
      expect(restored.siteId, 'site-a');
      expect(restored.pairingToken, 'TOKEN123');
      expect(restored.slideSeconds, 12);
      expect(restored.fit, SignageFit.contain);
      expect(restored.transition, SignageTransition.kenBurns);
      expect(restored.mediaIds, ['m1', 'm2', 'm3']);
      expect(restored.isActive, isFalse);
    });

    test('toFirestoreMap ist camelCase + nameLower + transition', () {
      final map = display.toFirestoreMap();
      expect(map['name'], 'Schaufenster');
      expect(map['nameLower'], 'schaufenster');
      expect(map['fit'], 'contain');
      expect(map['transition'], 'ken_burns');
      expect(map['mediaIds'], ['m1', 'm2', 'm3']);
      expect(map['pairingToken'], 'TOKEN123');
    });

    test('fromFirestore liest camelCase', () {
      final restored =
          SignageDisplay.fromFirestore('d1', display.toFirestoreMap());
      expect(restored.name, 'Schaufenster');
      expect(restored.fit, SignageFit.contain);
      expect(restored.transition, SignageTransition.kenBurns);
      expect(restored.mediaIds, ['m1', 'm2', 'm3']);
    });

    test('copyWith(clearSiteId) leert den Standort', () {
      final cleared = display.copyWith(clearSiteId: true);
      expect(cleared.siteId, isNull);
      // ohne clear bleibt der Wert erhalten
      expect(display.copyWith(name: 'X').siteId, 'site-a');
    });
  });

  group('SignageFit', () {
    test('value/fromValue rundläuft; unbekannt -> cover (Default)', () {
      for (final fit in SignageFit.values) {
        expect(SignageFit.fromValue(fit.value), fit);
      }
      expect(SignageFit.fromValue('unbekannt'), SignageFit.cover);
      expect(SignageFit.fromValue(null), SignageFit.cover);
    });
  });

  group('SignageTransition', () {
    test('value/fromValue rundläuft; unbekannt -> fade (Default)', () {
      for (final t in SignageTransition.values) {
        expect(SignageTransition.fromValue(t.value), t);
      }
      // Dart-Name != Wire-Wert bei kenBurns.
      expect(SignageTransition.kenBurns.value, 'ken_burns');
      expect(SignageTransition.fromValue('unbekannt'), SignageTransition.fade);
      expect(SignageTransition.fromValue(null), SignageTransition.fade);
    });
  });

  group('PublicDisplayData (Player-Projektion)', () {
    test('fromMap parst Folien + verwirft URL-lose Einträge', () {
      final data = PublicDisplayData.fromMap({
        'name': 'Schaufenster',
        'slideSeconds': 10,
        'fit': 'contain',
        'transition': 'zoom',
        'isActive': true,
        'slides': [
          {'url': 'https://a/1.jpg', 'seconds': 8, 'title': 'Eins'},
          {'url': '', 'seconds': 5, 'title': 'ohne URL'}, // verworfen
          {'url': 'https://a/2.jpg', 'seconds': 12, 'title': 'Zwei'},
        ],
      });
      expect(data.name, 'Schaufenster');
      expect(data.fit, SignageFit.contain);
      expect(data.transition, SignageTransition.zoom);
      expect(data.isActive, isTrue);
      expect(data.slides, hasLength(2));
      expect(data.slides.first.url, 'https://a/1.jpg');
      expect(data.slides.first.seconds, 8);
      expect(data.slides.last.title, 'Zwei');
    });

    test('fromMap ohne slides -> leere Liste (kein Crash)', () {
      final data = PublicDisplayData.fromMap({'name': 'X'});
      expect(data.slides, isEmpty);
      expect(data.isActive, isTrue);
    });
  });
}
