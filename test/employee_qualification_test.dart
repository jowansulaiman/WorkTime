import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/employee_qualification.dart';

void main() {
  EmployeeQualification quali({DateTime? gueltigBis}) => EmployeeQualification(
        orgId: 'org-1',
        userId: 'emp-1',
        qualificationName: 'Kassenschulung',
        gueltigBis: gueltigBis,
      );

  group('EmployeeQualification.gueltigkeitStatus (PA-1.3)', () {
    final now = DateTime(2026, 7, 3, 10);

    test('ohne gueltigBis: unbefristet gültig', () {
      expect(quali().gueltigkeitStatus(now), QualiGueltigkeit.gueltig);
    });

    test('gueltigBis weit in der Zukunft: gültig', () {
      expect(
        quali(gueltigBis: DateTime(2026, 12, 31)).gueltigkeitStatus(now),
        QualiGueltigkeit.gueltig,
      );
    });

    test('gueltigBis gestern: abgelaufen', () {
      expect(
        quali(gueltigBis: DateTime(2026, 7, 2)).gueltigkeitStatus(now),
        QualiGueltigkeit.abgelaufen,
      );
    });

    test('gueltigBis in 10 Tagen (< Warnfrist 30): läuft ab', () {
      expect(
        quali(gueltigBis: DateTime(2026, 7, 13)).gueltigkeitStatus(now),
        QualiGueltigkeit.laeuftAb,
      );
    });

    test('gueltigBis heute: läuft ab (bis Tagesende gültig)', () {
      expect(
        quali(gueltigBis: DateTime(2026, 7, 3)).gueltigkeitStatus(now),
        QualiGueltigkeit.laeuftAb,
      );
    });

    test('gueltigBis in 31 Tagen (außerhalb Warnfrist): gültig', () {
      expect(
        quali(gueltigBis: DateTime(2026, 8, 3)).gueltigkeitStatus(now),
        QualiGueltigkeit.gueltig,
      );
    });

    test('warnTage konfigurierbar: 7-Tage-Fenster', () {
      final q = quali(gueltigBis: DateTime(2026, 7, 20));
      expect(q.gueltigkeitStatus(now, warnTage: 7), QualiGueltigkeit.gueltig);
      expect(
        q.gueltigkeitStatus(DateTime(2026, 7, 15), warnTage: 7),
        QualiGueltigkeit.laeuftAb,
      );
    });
  });

  group('EmployeeQualification.documentId (PERSONAL-6, weiche Nachweis-FK)', () {
    EmployeeQualification withDoc(String? docId) => EmployeeQualification(
          id: 'q1',
          orgId: 'org-1',
          userId: 'emp-1',
          qualificationName: 'Kassenschulung',
          documentId: docId,
        );

    test('Firestore-Format (camelCase) rundtrippt documentId', () {
      final map = withDoc('doc-42').toFirestoreMap();
      expect(map['documentId'], 'doc-42');
      final back = EmployeeQualification.fromFirestore('q1', map);
      expect(back.documentId, 'doc-42');
    });

    test('lokales Format (snake_case) rundtrippt documentId', () {
      final map = withDoc('doc-42').toMap();
      expect(map['document_id'], 'doc-42');
      final back = EmployeeQualification.fromMap(map);
      expect(back.documentId, 'doc-42');
    });

    test('null documentId bleibt null in beiden Formaten', () {
      expect(withDoc(null).toFirestoreMap()['documentId'], isNull);
      expect(withDoc(null).toMap()['document_id'], isNull);
      expect(
        EmployeeQualification.fromFirestore('q1', withDoc(null).toFirestoreMap())
            .documentId,
        isNull,
      );
      expect(
        EmployeeQualification.fromMap(withDoc(null).toMap()).documentId,
        isNull,
      );
    });

    test('copyWith aktualisiert documentId', () {
      expect(withDoc('a').copyWith(documentId: 'b').documentId, 'b');
    });

    test('copyWith(clearDocumentId) leert die Referenz', () {
      final cleared = withDoc('doc-42').copyWith(clearDocumentId: true);
      expect(cleared.documentId, isNull);
    });

    test('copyWith ohne documentId lässt Wert unverändert', () {
      expect(withDoc('doc-42').copyWith(bemerkung: 'x').documentId, 'doc-42');
    });
  });
}
