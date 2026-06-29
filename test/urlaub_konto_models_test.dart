import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/absence_request.dart';
import 'package:worktime_app/models/urlaubsanpassung.dart';
import 'package:worktime_app/models/urlaubskonto_jahr.dart';

void main() {
  group('UrlaubskontoJahr', () {
    UrlaubskontoJahr sample() => UrlaubskontoJahr(
          orgId: 'org-1',
          userId: 'emp-1',
          jahr: 2026,
          vortragVorjahrTage: 7.5,
          vortragVerfaelltAm: DateTime(2026, 3, 31),
          hinweisErteiltAm: DateTime(2026, 1, 10),
          gewaehrterMehrurlaubTage: 2,
        );

    test('documentId = userId-jahr', () {
      expect(sample().documentId, 'emp-1-2026');
    });

    test('defaultVerfall = 31.3.', () {
      expect(UrlaubskontoJahr.defaultVerfall(2026), DateTime(2026, 3, 31, 12));
    });

    test('lokaler Round-Trip', () {
      final r = UrlaubskontoJahr.fromMap(sample().toMap());
      expect(r.jahr, 2026);
      expect(r.vortragVorjahrTage, 7.5);
      expect(r.vortragVerfaelltAm, DateTime(2026, 3, 31, 12));
      expect(r.hinweisErteiltAm, DateTime(2026, 1, 10, 12));
      expect(r.gewaehrterMehrurlaubTage, 2);
    });

    test('Firestore Round-Trip + createdAt beim Anlegen', () async {
      final fs = FakeFirebaseFirestore();
      final ref = fs.collection('urlaubskontoJahre').doc('emp-1-2026');
      await ref.set(sample().copyWith(id: 'emp-1-2026').toFirestoreMap());
      final snap = await ref.get();
      final r = UrlaubskontoJahr.fromFirestore(snap.id, snap.data()!);
      expect(r.id, 'emp-1-2026');
      expect(r.vortragVorjahrTage, 7.5);
      expect(r.hinweisErteiltAm, DateTime(2026, 1, 10, 12));
      // createdAt-Guard greift (id war beim Schreiben gesetzt).
      expect(snap.data()!.containsKey('createdAt'), isTrue);
    });

    test('copyWith clear-Flags', () {
      final c =
          sample().copyWith(clearHinweisErteiltAm: true, clearVortragVerfaelltAm: true);
      expect(c.hinweisErteiltAm, isNull);
      expect(c.vortragVerfaelltAm, isNull);
      expect(c.vortragVorjahrTage, 7.5);
    });
  });

  group('Urlaubsanpassung', () {
    test('Round-Trip + signierte Tage + Enum', () {
      const a = Urlaubsanpassung(
        orgId: 'org-1',
        userId: 'emp-1',
        jahr: 2026,
        tage: -2.5,
        art: UrlaubsAnpassungArt.abzugFrist,
        anmerkung: 'Verfall',
      );
      final r = Urlaubsanpassung.fromMap(a.toMap());
      expect(r.tage, -2.5);
      expect(r.art, UrlaubsAnpassungArt.abzugFrist);
      expect(r.anmerkung, 'Verfall');
      expect(UrlaubsAnpassungArtX.fromValue('quatsch'),
          UrlaubsAnpassungArt.allgemein);
    });
  });

  group('AbsenceRequest M-U-Erweiterung', () {
    test('halfDay/period/hours/vertreter/eau round-trippen (beide Formate)', () {
      final a = AbsenceRequest(
        orgId: 'org-1',
        userId: 'emp-1',
        employeeName: 'Test',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2026, 6, 1),
        type: AbsenceType.timeOff,
        halfDay: true,
        halfDayPeriod: HalfDayPeriod.nachmittags,
        hours: 4.0,
        vertreterUserIds: const ['emp-2', 'emp-3'],
        eauAttached: true,
      );
      final local = AbsenceRequest.fromMap(a.toMap());
      expect(local.halfDay, isTrue);
      expect(local.halfDayPeriod, HalfDayPeriod.nachmittags);
      expect(local.hours, 4.0);
      expect(local.vertreterUserIds, ['emp-2', 'emp-3']);
      expect(local.eauAttached, isTrue);
      expect(local.type, AbsenceType.timeOff);
    });

    test('Firestore Round-Trip der neuen Felder', () async {
      final fs = FakeFirebaseFirestore();
      final ref = fs.collection('absenceRequests').doc();
      await ref.set(AbsenceRequest(
        orgId: 'org-1',
        userId: 'emp-1',
        employeeName: 'Test',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2026, 6, 2),
        type: AbsenceType.specialLeave,
        vertreterUserIds: const ['emp-2'],
      ).toFirestoreMap());
      final snap = await ref.get();
      final r = AbsenceRequest.fromFirestore(snap.id, snap.data()!);
      expect(r.type, AbsenceType.specialLeave);
      expect(r.vertreterUserIds, ['emp-2']);
      expect(r.halfDay, isFalse);
    });

    test('AbsenceType fromValue-Default + alle Werte round-trippen', () {
      for (final t in AbsenceType.values) {
        expect(AbsenceTypeX.fromValue(t.value), t);
      }
      expect(AbsenceTypeX.fromValue('unbekannt'), AbsenceType.vacation);
    });
  });
}
