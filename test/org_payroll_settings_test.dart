import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/org_payroll_settings.dart';
import 'package:worktime_app/models/payroll_settings.dart';

OrgPayrollSettings _sample() => OrgPayrollSettings(
      orgId: 'org-1',
      jahr: 2026,
      settings: PayrollSettings.defaults2026().copyWith(
        year: 2026,
        umlageU1Rate: 0.013,
        umlageU2Rate: 0.003,
        insolvenzgeldumlageRate: 0.0009,
        uvRate: 0.015,
        u1Applies: false,
        healthAdditionalRate: 0.017,
      ),
      createdByUid: 'admin-1',
    );

void main() {
  group('OrgPayrollSettings Serialisierung', () {
    test('documentId ist das Bezugsjahr', () {
      expect(_sample().documentId, '2026');
    });

    test('lokaler Round-Trip (snake_case + ISO) erhält Sätze + Umlagen', () {
      final restored = OrgPayrollSettings.fromMap(_sample().toMap());

      expect(restored.orgId, 'org-1');
      expect(restored.jahr, 2026);
      expect(restored.createdByUid, 'admin-1');
      // Eingebettete Settings inkl. AG-Umlagen.
      expect(restored.settings.umlageU1Rate, closeTo(0.013, 1e-9));
      expect(restored.settings.umlageU2Rate, closeTo(0.003, 1e-9));
      expect(
          restored.settings.insolvenzgeldumlageRate, closeTo(0.0009, 1e-9));
      expect(restored.settings.uvRate, closeTo(0.015, 1e-9));
      expect(restored.settings.u1Applies, isFalse);
      expect(restored.settings.healthAdditionalRate, closeTo(0.017, 1e-9));
    });

    test('Firestore Round-Trip (camelCase + Timestamp) über FakeFirestore',
        () async {
      final firestore = FakeFirebaseFirestore();
      final ref = firestore.collection('payrollConfig').doc('2026');
      await ref.set(_sample().copyWith(id: '2026').toFirestoreMap());
      final snap = await ref.get();
      final restored =
          OrgPayrollSettings.fromFirestore(snap.id, snap.data()!);

      expect(restored.id, '2026');
      expect(restored.jahr, 2026);
      expect(restored.orgId, 'org-1');
      expect(restored.settings.uvRate, closeTo(0.015, 1e-9));
      expect(restored.settings.u1Applies, isFalse);
      // serverTimestamp wird von FakeFirestore aufgelöst.
      expect(restored.updatedAt, isNotNull);
    });

    test('createdAt wird beim ersten Anlegen geschrieben, danach nicht mehr', () {
      // Erstes Anlegen: createdAt fehlt -> serverTimestamp wird gesetzt.
      final neu = OrgPayrollSettings.defaultsFor(orgId: 'org-1', jahr: 2026)
          .copyWith(id: '2026');
      expect(neu.createdAt, isNull);
      expect(neu.toFirestoreMap().containsKey('createdAt'), isTrue);

      // Update (createdAt bereits vorhanden) -> NICHT erneut gesendet, damit
      // der gespeicherte Wert via merge erhalten bleibt.
      final bestehend = neu.copyWith(createdAt: DateTime(2026, 1, 2));
      expect(bestehend.toFirestoreMap().containsKey('createdAt'), isFalse);
      // updatedAt wird immer geschrieben.
      expect(bestehend.toFirestoreMap().containsKey('updatedAt'), isTrue);
    });

    test('jahr wird notfalls aus der Doc-ID abgeleitet', () {
      // Dokument ohne explizites jahr-Feld (Alt-/Teil-Dokument).
      final restored = OrgPayrollSettings.fromFirestore('2027', {
        'orgId': 'org-1',
        'settings': PayrollSettings.defaults2026().toMap(),
      });
      expect(restored.jahr, 2027);
    });

    test('fehlende settings fallen tolerant auf Jahres-Defaults zurück', () {
      final restored = OrgPayrollSettings.fromFirestore('2026', {
        'orgId': 'org-1',
        'jahr': 2026,
      });
      // Keine Exception, sinnvolle Defaults statt 0-Sätze.
      expect(restored.settings.healthRate,
          PayrollSettings.defaults2026().healthRate);
      expect(restored.settings.umlageU1Rate,
          PayrollSettings.defaults2026().umlageU1Rate);
    });
  });

  group('OrgPayrollSettings Defaults & copyWith', () {
    test('defaultSettingsForYear wählt 2025 vs. 2026', () {
      expect(OrgPayrollSettings.defaultSettingsForYear(2025).year, 2025);
      expect(OrgPayrollSettings.defaultSettingsForYear(2025).minijobCeilingCents,
          PayrollSettings.defaults2025().minijobCeilingCents);
      expect(OrgPayrollSettings.defaultSettingsForYear(2026).year, 2026);
      // Spätere Jahre erben die 2026er-Sätze, behalten aber ihr Bezugsjahr.
      expect(OrgPayrollSettings.defaultSettingsForYear(2027).year, 2027);
      expect(OrgPayrollSettings.defaultSettingsForYear(2027).minijobCeilingCents,
          PayrollSettings.defaults2026().minijobCeilingCents);
    });

    test('defaultsFor liefert Fallback mit Jahres-Doc-ID', () {
      final config =
          OrgPayrollSettings.defaultsFor(orgId: 'org-1', jahr: 2026);
      expect(config.id, '2026');
      expect(config.documentId, '2026');
      expect(config.settings.year, 2026);
      expect(config.createdAt, isNull);
    });

    test('copyWith clear-Flag leert nullable Meta', () {
      final base = _sample().copyWith(createdByUid: 'admin-1');
      final cleared = base.copyWith(clearCreatedByUid: true);
      expect(cleared.createdByUid, isNull);
      // Andere Felder bleiben erhalten.
      expect(cleared.jahr, 2026);
      expect(cleared.settings.uvRate, closeTo(0.015, 1e-9));
    });
  });
}
