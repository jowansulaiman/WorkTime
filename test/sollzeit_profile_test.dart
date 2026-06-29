import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/sollzeit_profile.dart';

SollzeitProfile _sample() => SollzeitProfile(
      orgId: 'org-1',
      userId: 'emp-1',
      gueltigAb: DateTime(2026, 1, 1),
      montagMinutes: 480,
      dienstagMinutes: 480,
      mittwochMinutes: 480,
      donnerstagMinutes: 480,
      freitagMinutes: 300,
      samstagMinutes: 0,
      sonntagMinutes: 0,
      isMonatsarbeitszeit: true,
      monatsarbeitszeitMinutes: 10080,
      arbeitstageProWoche: 5,
      urlaubstageJahr: 30,
      urlaubsbasisWerktage: 5,
      zusatzurlaubstage: 2,
      urlaubAlsStunden: true,
      pauseAb6hMinutes: 30,
      pauseAb9hMinutes: 45,
      rahmenVonMinutes: 360,
      rahmenBisMinutes: 1200,
      kernzeitVonMinutes: 540,
      kernzeitBisMinutes: 900,
      pauseKarenzMinutes: 5,
      kernzeitKarenzMinutes: 10,
      azRunden: true,
      azRundenAufMinutes: 15,
      azRundenStart: true,
      azRundenEnde: true,
      azMaximumMinutes: 600,
      gleitzeit: true,
      fakultativeUeberstunden: true,
      fakultativeUeberstundenTyp: 'monatlich',
      fakultativeUeberstundenZeitraum: 'Monat',
    );

void main() {
  group('SollzeitProfile Serialisierung', () {
    test('lokaler Round-Trip (snake_case + ISO) erhält alle Felder', () {
      final restored = SollzeitProfile.fromMap(_sample().toMap());

      expect(restored.orgId, 'org-1');
      expect(restored.userId, 'emp-1');
      expect(restored.gueltigAb.year, 2026);
      expect(restored.gueltigAb.month, 1);
      expect(restored.gueltigAb.day, 1);
      expect(restored.montagMinutes, 480);
      expect(restored.freitagMinutes, 300);
      expect(restored.samstagMinutes, 0);
      expect(restored.isMonatsarbeitszeit, isTrue);
      expect(restored.monatsarbeitszeitMinutes, 10080);
      expect(restored.arbeitstageProWoche, 5);
      expect(restored.urlaubstageJahr, 30);
      expect(restored.urlaubsbasisWerktage, 5);
      expect(restored.zusatzurlaubstage, 2);
      expect(restored.urlaubAlsStunden, isTrue);
      expect(restored.pauseAb6hMinutes, 30);
      expect(restored.pauseAb9hMinutes, 45);
      expect(restored.rahmenVonMinutes, 360);
      expect(restored.rahmenBisMinutes, 1200);
      expect(restored.kernzeitVonMinutes, 540);
      expect(restored.kernzeitBisMinutes, 900);
      expect(restored.pauseKarenzMinutes, 5);
      expect(restored.kernzeitKarenzMinutes, 10);
      expect(restored.azRunden, isTrue);
      expect(restored.azRundenAufMinutes, 15);
      expect(restored.azRundenStart, isTrue);
      expect(restored.azRundenEnde, isTrue);
      expect(restored.azMaximumMinutes, 600);
      expect(restored.gleitzeit, isTrue);
      expect(restored.fakultativeUeberstunden, isTrue);
      expect(restored.fakultativeUeberstundenTyp, 'monatlich');
      expect(restored.fakultativeUeberstundenZeitraum, 'Monat');
    });

    test('Firestore Round-Trip (camelCase + Timestamp) über FakeFirestore',
        () async {
      final firestore = FakeFirebaseFirestore();
      final ref = firestore.collection('sollzeitProfiles').doc();
      await ref.set(_sample().toFirestoreMap());
      final snap = await ref.get();
      final restored = SollzeitProfile.fromFirestore(snap.id, snap.data()!);

      expect(restored.id, ref.id);
      expect(restored.userId, 'emp-1');
      // gueltigAb wird beim Schreiben auf lokale Mittagszeit normalisiert.
      expect(restored.gueltigAb.year, 2026);
      expect(restored.gueltigAb.month, 1);
      expect(restored.gueltigAb.day, 1);
      expect(restored.montagMinutes, 480);
      expect(restored.urlaubstageJahr, 30);
      expect(restored.azMaximumMinutes, 600);
      expect(restored.fakultativeUeberstundenTyp, 'monatlich');
      // serverTimestamp wird von FakeFirestore aufgelöst.
      expect(restored.updatedAt, isNotNull);
    });

    test('nullable Felder bleiben null + Defaults greifen im Round-Trip', () {
      final profile = SollzeitProfile(
        orgId: 'o',
        userId: 'u',
        gueltigAb: DateTime(2026, 6, 1),
      );
      final restored = SollzeitProfile.fromMap(profile.toMap());
      expect(restored.monatsarbeitszeitMinutes, isNull);
      expect(restored.rahmenVonMinutes, isNull);
      expect(restored.kernzeitVonMinutes, isNull);
      expect(restored.azMaximumMinutes, isNull);
      expect(restored.fakultativeUeberstundenTyp, isNull);
      // Defaults greifen.
      expect(restored.arbeitstageProWoche, 5);
      expect(restored.urlaubstageJahr, 20);
      expect(restored.pauseAb6hMinutes, 30);
      expect(restored.pauseAb9hMinutes, 45);
    });
  });

  group('SollzeitProfile Helfer', () {
    test('sollMinutesForWeekday liefert das richtige Tagessoll', () {
      final p = _sample();
      expect(p.sollMinutesForWeekday(DateTime.monday), 480);
      expect(p.sollMinutesForWeekday(DateTime.friday), 300);
      expect(p.sollMinutesForWeekday(DateTime.saturday), 0);
      expect(p.sollMinutesForWeekday(DateTime.sunday), 0);
    });

    test('wochensollMinutes summiert alle Tage', () {
      expect(_sample().wochensollMinutes, 480 * 4 + 300);
    });

    test('effektiveArbeitstage zählt Tage mit Soll > 0', () {
      expect(_sample().effektiveArbeitstage, 5);
    });

    test('effektiveArbeitstage fällt auf arbeitstageProWoche zurück', () {
      final p = SollzeitProfile(
        orgId: 'o',
        userId: 'u',
        gueltigAb: DateTime(2026, 1, 1),
        isMonatsarbeitszeit: true,
        monatsarbeitszeitMinutes: 8000,
        arbeitstageProWoche: 4,
      );
      expect(p.effektiveArbeitstage, 4);
    });

    test('Tie-Break: gleiche gueltigAb -> Sortierung nach updatedAt/id stabil',
        () {
      final base = _sample();
      final a = base.copyWith(id: 'a', updatedAt: DateTime(2026, 1, 10));
      final b = base.copyWith(id: 'b', updatedAt: DateTime(2026, 1, 20));
      // Provider-Sortierregel nachbilden: gueltigAb desc, updatedAt desc, id desc.
      final list = [a, b]..sort((x, y) {
          final byDate = y.gueltigAb.compareTo(x.gueltigAb);
          if (byDate != 0) return byDate;
          return y.updatedAt!.compareTo(x.updatedAt!);
        });
      expect(list.first.id, 'b'); // jüngeres updatedAt zuerst
    });

    test('isEffectiveOn vergleicht gegen gueltigAb', () {
      final p = SollzeitProfile(
        orgId: 'o',
        userId: 'u',
        gueltigAb: DateTime(2026, 3, 1),
      );
      expect(p.isEffectiveOn(DateTime(2026, 2, 28)), isFalse);
      expect(p.isEffectiveOn(DateTime(2026, 3, 1)), isTrue);
      expect(p.isEffectiveOn(DateTime(2026, 6, 15)), isTrue);
    });
  });

  group('SollzeitProfile copyWith', () {
    test('clear-Flags leeren nullable Felder', () {
      final cleared = _sample().copyWith(
        clearMonatsarbeitszeitMinutes: true,
        clearKernzeitVonMinutes: true,
        clearAzMaximumMinutes: true,
        clearFakultativeUeberstundenTyp: true,
      );
      expect(cleared.monatsarbeitszeitMinutes, isNull);
      expect(cleared.kernzeitVonMinutes, isNull);
      expect(cleared.azMaximumMinutes, isNull);
      expect(cleared.fakultativeUeberstundenTyp, isNull);
      // unveränderte nullable bleiben erhalten.
      expect(cleared.kernzeitBisMinutes, 900);
      expect(cleared.rahmenVonMinutes, 360);
    });

    test('copyWith überschreibt einzelne Werte', () {
      final updated = _sample().copyWith(urlaubstageJahr: 26, gleitzeit: false);
      expect(updated.urlaubstageJahr, 26);
      expect(updated.gleitzeit, isFalse);
      expect(updated.montagMinutes, 480);
    });
  });
}
