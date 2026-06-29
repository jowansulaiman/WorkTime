import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/employee_ausbildung.dart';
import 'package:worktime_app/models/employee_child.dart';
import 'package:worktime_app/models/employee_qualification.dart';

void main() {
  group('EmployeeChild', () {
    EmployeeChild sample() => EmployeeChild(
          orgId: 'org-1',
          userId: 'emp-1',
          vorname: 'Mia',
          name: 'Muster',
          geschlecht: 'w',
          steuerIdKind: '12345678901',
          geburtstag: DateTime(2015, 4, 7),
          zaehltFuerFreibetrag: false,
        );

    test('lokaler Round-Trip (snake_case)', () {
      final r = EmployeeChild.fromMap(sample().toMap());
      expect(r.orgId, 'org-1');
      expect(r.userId, 'emp-1');
      expect(r.vorname, 'Mia');
      expect(r.name, 'Muster');
      expect(r.anzeigeName, 'Mia Muster');
      expect(r.geschlecht, 'w');
      expect(r.steuerIdKind, '12345678901');
      // Tages-Datum auf lokale Mittagszeit normalisiert (12:00, Konvention).
      expect(r.geburtstag, DateTime(2015, 4, 7, 12));
      expect(r.zaehltFuerFreibetrag, isFalse);
    });

    test('Firestore Round-Trip (camelCase + Timestamp)', () async {
      final fs = FakeFirebaseFirestore();
      final ref = fs.collection('employeeChildren').doc();
      await ref.set(sample().toFirestoreMap());
      final snap = await ref.get();
      final r = EmployeeChild.fromFirestore(snap.id, snap.data()!);
      expect(r.id, ref.id);
      expect(r.vorname, 'Mia');
      expect(r.geburtstag, DateTime(2015, 4, 7, 12));
      expect(r.zaehltFuerFreibetrag, isFalse);
      expect(r.updatedAt, isNotNull);
    });

    test('copyWith clear-Flags + Default zaehltFuerFreibetrag', () {
      const minimal = EmployeeChild(orgId: 'o', userId: 'u');
      expect(minimal.zaehltFuerFreibetrag, isTrue);
      expect(minimal.anzeigeName, 'Kind');
      final cleared = sample().copyWith(
        clearGeschlecht: true,
        clearSteuerIdKind: true,
        clearGeburtstag: true,
      );
      expect(cleared.geschlecht, isNull);
      expect(cleared.steuerIdKind, isNull);
      expect(cleared.geburtstag, isNull);
      expect(cleared.vorname, 'Mia');
    });
  });

  group('EmployeeQualification', () {
    EmployeeQualification sample() => EmployeeQualification(
          orgId: 'org-1',
          userId: 'emp-1',
          qualificationId: 'q-1',
          qualificationName: 'Kasse',
          erwerb: QualiErwerb.intern,
          erworbenAm: DateTime(2024, 3, 1),
          gueltigBis: DateTime(2026, 3, 1),
          bemerkung: 'jährlich auffrischen',
        );

    test('lokaler Round-Trip + Enum', () {
      final r = EmployeeQualification.fromMap(sample().toMap());
      expect(r.qualificationId, 'q-1');
      expect(r.qualificationName, 'Kasse');
      expect(r.erwerb, QualiErwerb.intern);
      expect(r.erworbenAm, DateTime(2024, 3, 1, 12));
      expect(r.gueltigBis, DateTime(2026, 3, 1, 12));
      expect(r.bemerkung, 'jährlich auffrischen');
    });

    test('Firestore Round-Trip', () async {
      final fs = FakeFirebaseFirestore();
      final ref = fs.collection('employeeQualifications').doc();
      await ref.set(sample().toFirestoreMap());
      final snap = await ref.get();
      final r = EmployeeQualification.fromFirestore(snap.id, snap.data()!);
      expect(r.qualificationName, 'Kasse');
      expect(r.erwerb, QualiErwerb.intern);
      expect(r.gueltigBis, DateTime(2026, 3, 1, 12));
    });

    test('istGueltig: unbefristet immer, sonst bis Stichtag', () {
      final unbefristet = sample().copyWith(clearGueltigBis: true);
      expect(unbefristet.istGueltig(DateTime(2099, 1, 1)), isTrue);
      expect(sample().istGueltig(DateTime(2025, 6, 1)), isTrue);
      expect(sample().istGueltig(DateTime(2026, 3, 1)), isTrue); // letzter Tag
      expect(sample().istGueltig(DateTime(2026, 3, 2)), isFalse);
    });

    test('fromValue-Default für unbekannten Erwerb', () {
      expect(QualiErwerbX.fromValue('quatsch'), QualiErwerb.vorab);
      expect(QualiErwerbX.fromValue(null), QualiErwerb.vorab);
    });
  });

  group('EmployeeAusbildung', () {
    EmployeeAusbildung sample() => EmployeeAusbildung(
          orgId: 'org-1',
          userId: 'emp-1',
          bezeichnung: 'Kaufmann im Einzelhandel',
          beginn: DateTime(2023, 8, 1),
          ende: DateTime(2026, 7, 31),
          ausbilderUserId: 'emp-2',
          noteZwischen: '2,0',
          noteAbschluss: '1,7',
          bemerkung: 'verkürzt',
        );

    test('lokaler Round-Trip', () {
      final r = EmployeeAusbildung.fromMap(sample().toMap());
      expect(r.bezeichnung, 'Kaufmann im Einzelhandel');
      expect(r.beginn, DateTime(2023, 8, 1, 12));
      expect(r.ende, DateTime(2026, 7, 31, 12));
      expect(r.ausbilderUserId, 'emp-2');
      expect(r.noteZwischen, '2,0');
      expect(r.noteAbschluss, '1,7');
      expect(r.bemerkung, 'verkürzt');
    });

    test('Firestore Round-Trip', () async {
      final fs = FakeFirebaseFirestore();
      final ref = fs.collection('employeeAusbildungen').doc();
      await ref.set(sample().toFirestoreMap());
      final snap = await ref.get();
      final r = EmployeeAusbildung.fromFirestore(snap.id, snap.data()!);
      expect(r.bezeichnung, 'Kaufmann im Einzelhandel');
      expect(r.beginn, DateTime(2023, 8, 1, 12));
      expect(r.ausbilderUserId, 'emp-2');
    });

    test('copyWith clear-Flags', () {
      final cleared = sample().copyWith(
        clearEnde: true,
        clearAusbilderUserId: true,
        clearNoteAbschluss: true,
      );
      expect(cleared.ende, isNull);
      expect(cleared.ausbilderUserId, isNull);
      expect(cleared.noteAbschluss, isNull);
      expect(cleared.beginn, DateTime(2023, 8, 1));
    });
  });
}
