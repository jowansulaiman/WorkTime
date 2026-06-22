import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/employee_profile.dart';

EmployeeProfile _sample() => EmployeeProfile(
      orgId: 'org-1',
      userId: 'emp-1',
      salutation: 'Frau',
      titleAcademic: 'Dr.',
      birthDate: DateTime(1990, 5, 17),
      nationality: 'deutsch',
      street: 'Holstenstraße',
      houseNumber: '12a',
      postalCode: '24103',
      city: 'Kiel',
      addressExtra: 'Hinterhaus',
      privatePhone: '0431 12345',
      privateMobile: '0170 9999999',
      privateEmail: 'lea@example.com',
      personnelNumber: 'P-0007',
      status: EmployeeStatus.probezeit,
      personnelGroup: PersonnelGroup.angestellter,
      hireDate: DateTime(2026, 3, 1),
      exitDate: DateTime(2027, 2, 28),
      probationEnd: DateTime(2026, 9, 1),
      limitedUntil: DateTime(2027, 2, 28),
      maritalStatus: MaritalStatus.verheiratet,
      confession: Confession.evangelisch,
      childrenCount: 2,
      taxId: '12345678901',
      socialSecurityNumber: '65 170590 L 123',
      healthInsurance: 'AOK Nordwest',
      healthInsuranceType: HealthInsuranceType.gesetzlich,
      healthInsuranceSurchargePercent: 1.7,
      iban: 'DE02120300000000202051',
      bic: 'BYLADEM1001',
      accountHolder: 'Lea Muster',
      annualVacationDays: 28,
      emergencyContactName: 'Max Muster',
      emergencyContactPhone: '0171 2223334',
      note: 'Lieber vormittags erreichbar.',
    );

void main() {
  group('EmployeeProfile Serialisierung', () {
    test('lokaler Round-Trip (snake_case + ISO) erhält alle Felder', () {
      final original = _sample();
      final restored = EmployeeProfile.fromMap(original.toMap());

      expect(restored.userId, 'emp-1');
      expect(restored.salutation, 'Frau');
      expect(restored.titleAcademic, 'Dr.');
      expect(restored.birthDate, DateTime(1990, 5, 17));
      expect(restored.nationality, 'deutsch');
      expect(restored.street, 'Holstenstraße');
      expect(restored.houseNumber, '12a');
      expect(restored.postalCode, '24103');
      expect(restored.city, 'Kiel');
      expect(restored.addressExtra, 'Hinterhaus');
      expect(restored.privatePhone, '0431 12345');
      expect(restored.privateMobile, '0170 9999999');
      expect(restored.privateEmail, 'lea@example.com');
      expect(restored.personnelNumber, 'P-0007');
      expect(restored.status, EmployeeStatus.probezeit);
      expect(restored.personnelGroup, PersonnelGroup.angestellter);
      expect(restored.hireDate, DateTime(2026, 3, 1));
      expect(restored.exitDate, DateTime(2027, 2, 28));
      expect(restored.probationEnd, DateTime(2026, 9, 1));
      expect(restored.limitedUntil, DateTime(2027, 2, 28));
      expect(restored.maritalStatus, MaritalStatus.verheiratet);
      expect(restored.confession, Confession.evangelisch);
      expect(restored.childrenCount, 2);
      expect(restored.taxId, '12345678901');
      expect(restored.socialSecurityNumber, '65 170590 L 123');
      expect(restored.healthInsurance, 'AOK Nordwest');
      expect(restored.healthInsuranceType, HealthInsuranceType.gesetzlich);
      expect(restored.healthInsuranceSurchargePercent, 1.7);
      expect(restored.iban, 'DE02120300000000202051');
      expect(restored.bic, 'BYLADEM1001');
      expect(restored.accountHolder, 'Lea Muster');
      expect(restored.annualVacationDays, 28);
      expect(restored.emergencyContactName, 'Max Muster');
      expect(restored.emergencyContactPhone, '0171 2223334');
      expect(restored.note, 'Lieber vormittags erreichbar.');
    });

    test('Firestore Round-Trip (camelCase + Timestamp) erhält Felder/Daten', () {
      final original = _sample();
      final map = original.toFirestoreMap();

      // Datums-Felder sind Timestamps, Enums ihre .value-Strings.
      expect(map['birthDate'], isA<Timestamp>());
      expect(map['hireDate'], isA<Timestamp>());
      expect(map['status'], 'probezeit');
      expect(map['confession'], 'evangelisch');
      // updatedAt ist FieldValue (serverTimestamp) -> für fromFirestore irrelevant.
      map['updatedAt'] = Timestamp.fromDate(DateTime(2026, 6, 22));

      final restored = EmployeeProfile.fromFirestore('emp-1', map);
      expect(restored.id, 'emp-1');
      expect(restored.birthDate, DateTime(1990, 5, 17, 12));
      expect(restored.hireDate, DateTime(2026, 3, 1, 12));
      expect(restored.status, EmployeeStatus.probezeit);
      expect(restored.personnelGroup, PersonnelGroup.angestellter);
      expect(restored.maritalStatus, MaritalStatus.verheiratet);
      expect(restored.confession, Confession.evangelisch);
      expect(restored.healthInsuranceType, HealthInsuranceType.gesetzlich);
      expect(restored.healthInsuranceSurchargePercent, 1.7);
      expect(restored.childrenCount, 2);
      expect(restored.iban, 'DE02120300000000202051');
    });

    test('leere Strings werden in toFirestoreMap zu null getrimmt', () {
      const profile = EmployeeProfile(
        orgId: 'org-1',
        userId: 'emp-1',
        salutation: '   ',
        city: '',
      );
      final map = profile.toFirestoreMap();
      expect(map['salutation'], isNull);
      expect(map['city'], isNull);
    });

    test('createdAt wird nur beim Erst-Write (createdAt == null) gesetzt', () {
      const fresh = EmployeeProfile(orgId: 'org-1', userId: 'emp-1');
      expect(fresh.toFirestoreMap().containsKey('createdAt'), isTrue,
          reason: 'Erst-Anlage -> serverTimestamp für createdAt');

      final existing = EmployeeProfile(
        orgId: 'org-1',
        userId: 'emp-1',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(existing.toFirestoreMap().containsKey('createdAt'), isFalse,
          reason: 'Folge-Speicherung lässt createdAt weg (merge erhält Wert)');
    });
  });

  group('EmployeeProfile Enums', () {
    test('fromValue der optionalen Enums liefert null bei unbekannt/null', () {
      expect(MaritalStatusX.fromValue(null), isNull);
      expect(MaritalStatusX.fromValue('quatsch'), isNull);
      expect(ConfessionX.fromValue('unknown'), isNull);
      expect(PersonnelGroupX.fromValue(null), isNull);
      expect(HealthInsuranceTypeX.fromValue('x'), isNull);
    });

    test('EmployeeStatus.fromValue fällt auf aktiv zurück (Default-Branch)', () {
      expect(EmployeeStatusX.fromValue(null), EmployeeStatus.aktiv);
      expect(EmployeeStatusX.fromValue('quatsch'), EmployeeStatus.aktiv);
      expect(EmployeeStatusX.fromValue('gekuendigt'), EmployeeStatus.gekuendigt);
    });

    test('value/fromValue sind stabil (Round-Trip über alle Werte)', () {
      for (final v in MaritalStatus.values) {
        expect(MaritalStatusX.fromValue(v.value), v);
      }
      for (final v in Confession.values) {
        expect(ConfessionX.fromValue(v.value), v);
      }
      for (final v in PersonnelGroup.values) {
        expect(PersonnelGroupX.fromValue(v.value), v);
      }
      for (final v in EmployeeStatus.values) {
        expect(EmployeeStatusX.fromValue(v.value), v);
      }
      for (final v in HealthInsuranceType.values) {
        expect(HealthInsuranceTypeX.fromValue(v.value), v);
      }
    });

    test('Confession.isChurchTaxable nur ev./kath.', () {
      expect(Confession.evangelisch.isChurchTaxable, isTrue);
      expect(Confession.katholisch.isChurchTaxable, isTrue);
      expect(Confession.keine.isChurchTaxable, isFalse);
      expect(Confession.sonstige.isChurchTaxable, isFalse);
    });
  });

  group('EmployeeProfile abgeleitete Sichten', () {
    test('isEmpty erkennt eine leere Akte (nur Identität + Default-Status)', () {
      const empty = EmployeeProfile(orgId: 'org-1', userId: 'emp-1');
      expect(empty.isEmpty, isTrue);

      const withOneField = EmployeeProfile(
        orgId: 'org-1',
        userId: 'emp-1',
        city: 'Kiel',
      );
      expect(withOneField.isEmpty, isFalse);

      const withChildren = EmployeeProfile(
        orgId: 'org-1',
        userId: 'emp-1',
        childrenCount: 1,
      );
      expect(withChildren.isEmpty, isFalse);
    });

    test('formattedAddress baut eine einzeilige Adresse oder null', () {
      const none = EmployeeProfile(orgId: 'o', userId: 'u');
      expect(none.formattedAddress, isNull);

      const full = EmployeeProfile(
        orgId: 'o',
        userId: 'u',
        street: 'Holstenstraße',
        houseNumber: '12',
        postalCode: '24103',
        city: 'Kiel',
      );
      expect(full.formattedAddress, 'Holstenstraße 12, 24103 Kiel');

      const cityOnly = EmployeeProfile(orgId: 'o', userId: 'u', city: 'Kiel');
      expect(cityOnly.formattedAddress, 'Kiel');
    });

    test('documentId ist die userId', () {
      expect(_sample().documentId, 'emp-1');
    });

    test('copyWith überschreibt nur gesetzte Felder', () {
      final base = _sample();
      final changed = base.copyWith(city: 'Hamburg', childrenCount: 3);
      expect(changed.city, 'Hamburg');
      expect(changed.childrenCount, 3);
      // unverändert:
      expect(changed.street, 'Holstenstraße');
      expect(changed.confession, Confession.evangelisch);
    });
  });
}
