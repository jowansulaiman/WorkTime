import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:worktime_app/models/absence_request.dart';
import 'package:worktime_app/models/shift.dart';
import 'package:worktime_app/models/shift_template.dart';
import 'package:worktime_app/models/work_entry.dart';
import 'package:worktime_app/models/work_template.dart';
import 'package:worktime_app/services/firestore_service.dart';

void main() {
  group('FirestoreService', () {
    late FakeFirebaseFirestore firestore;
    late FirestoreService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = FirestoreService(firestore: firestore);
    });

    test(
      'getApprovedVacationsForYear includes vacations overlapping the year boundary',
      () async {
        final collection = firestore
            .collection('organizations')
            .doc('org-1')
            .collection('absenceRequests');

        await collection.doc('vacation-overlap').set(
              AbsenceRequest(
                id: 'vacation-overlap',
                orgId: 'org-1',
                userId: 'employee-1',
                employeeName: 'Anna',
                startDate: DateTime(2025, 12, 30),
                endDate: DateTime(2026, 1, 3),
                type: AbsenceType.vacation,
                status: AbsenceStatus.approved,
              ).toFirestoreMap(),
            );

        await collection.doc('vacation-next-year').set(
              AbsenceRequest(
                id: 'vacation-next-year',
                orgId: 'org-1',
                userId: 'employee-1',
                employeeName: 'Anna',
                startDate: DateTime(2027, 1, 2),
                endDate: DateTime(2027, 1, 4),
                type: AbsenceType.vacation,
                status: AbsenceStatus.approved,
              ).toFirestoreMap(),
            );

        await collection.doc('sickness-overlap').set(
              AbsenceRequest(
                id: 'sickness-overlap',
                orgId: 'org-1',
                userId: 'employee-1',
                employeeName: 'Anna',
                startDate: DateTime(2025, 12, 31),
                endDate: DateTime(2026, 1, 2),
                type: AbsenceType.sickness,
                status: AbsenceStatus.approved,
              ).toFirestoreMap(),
            );

        final vacations = await service.getApprovedVacationsForYear(
          orgId: 'org-1',
          userId: 'employee-1',
          year: 2026,
        );

        expect(vacations, hasLength(1));
        expect(vacations.single.id, 'vacation-overlap');
      },
    );

    test(
      'getApprovedAbsencesInRange filters approved overlapping requests client side',
      () async {
        final collection = firestore
            .collection('organizations')
            .doc('org-1')
            .collection('absenceRequests');

        await collection.doc('approved-overlap').set(
              AbsenceRequest(
                id: 'approved-overlap',
                orgId: 'org-1',
                userId: 'employee-1',
                employeeName: 'Anna',
                startDate: DateTime(2026, 4, 10),
                endDate: DateTime(2026, 4, 12),
                type: AbsenceType.vacation,
                status: AbsenceStatus.approved,
              ).toFirestoreMap(),
            );
        await collection.doc('pending-overlap').set(
              AbsenceRequest(
                id: 'pending-overlap',
                orgId: 'org-1',
                userId: 'employee-1',
                employeeName: 'Anna',
                startDate: DateTime(2026, 4, 10),
                endDate: DateTime(2026, 4, 12),
                type: AbsenceType.vacation,
                status: AbsenceStatus.pending,
              ).toFirestoreMap(),
            );
        await collection.doc('approved-outside').set(
              AbsenceRequest(
                id: 'approved-outside',
                orgId: 'org-1',
                userId: 'employee-1',
                employeeName: 'Anna',
                startDate: DateTime(2026, 5, 1),
                endDate: DateTime(2026, 5, 3),
                type: AbsenceType.vacation,
                status: AbsenceStatus.approved,
              ).toFirestoreMap(),
            );

        final absences = await service.getApprovedAbsencesInRange(
          orgId: 'org-1',
          start: DateTime(2026, 4, 11),
          end: DateTime(2026, 4, 13),
          userId: 'employee-1',
        );

        expect(absences, hasLength(1));
        expect(absences.single.id, 'approved-overlap');
      },
    );

    test('watchWorkTemplates sorts templates client side by name', () async {
      final collection = firestore
          .collection('organizations')
          .doc('org-1')
          .collection('workTemplates');

      await collection.doc('template-2').set(
            WorkTemplate(
              id: 'template-2',
              orgId: 'org-1',
              userId: 'lead-1',
              name: 'Spaeter Start',
              startMinutes: 12 * 60,
              endMinutes: 20 * 60,
            ).toFirestoreMap(),
          );
      await collection.doc('template-1').set(
            WorkTemplate(
              id: 'template-1',
              orgId: 'org-1',
              userId: 'lead-1',
              name: 'Frueher Start',
              startMinutes: 6 * 60,
              endMinutes: 14 * 60,
            ).toFirestoreMap(),
          );

      final templates = await service
          .watchWorkTemplates(
            orgId: 'org-1',
            userId: 'lead-1',
          )
          .first;

      expect(templates.map((template) => template.name).toList(), [
        'Frueher Start',
        'Spaeter Start',
      ]);
    });

    test('watchShiftTemplates sorts templates client side by name', () async {
      final collection = firestore
          .collection('organizations')
          .doc('org-1')
          .collection('shiftTemplates');

      await collection.doc('template-2').set(
            ShiftTemplate(
              id: 'template-2',
              orgId: 'org-1',
              userId: 'lead-1',
              name: 'Spaetdienst',
              title: 'Spaetdienst',
              startMinutes: 14 * 60,
              endMinutes: 22 * 60,
            ).toFirestoreMap(),
          );
      await collection.doc('template-1').set(
        {
          'orgId': 'org-1',
          'userId': 'lead-1',
          'name': 'Fruehdienst',
          'title': 'Fruehdienst',
          'startMinutes': 8 * 60,
          'endMinutes': 16 * 60,
        },
      );

      final templates = await service
          .watchShiftTemplates(
            orgId: 'org-1',
            userId: 'lead-1',
          )
          .first;

      expect(templates.map((template) => template.name).toList(), [
        'Fruehdienst',
        'Spaetdienst',
      ]);
    });

    test(
      'saveShiftBatch falls back to direct Firestore writes when the function is missing',
      () async {
        service = FirestoreService(
          firestore: firestore,
          cloudFunctionInvoker: (_, __) async {
            throw FirebaseFunctionsException(
              message: 'missing',
              code: 'not-found',
            );
          },
        );

        await service.saveShiftBatch([
          Shift(
            orgId: 'org-1',
            userId: 'employee-1',
            employeeName: 'Anna',
            title: 'Fruehdienst',
            startTime: DateTime(2026, 4, 5, 8),
            endTime: DateTime(2026, 4, 5, 16),
          ),
        ]);

        final snapshot = await firestore
            .collection('organizations')
            .doc('org-1')
            .collection('shifts')
            .get();

        expect(snapshot.docs, hasLength(1));
        expect(snapshot.docs.single.data()['userId'], 'employee-1');
        expect(
            snapshot.docs.single.data()['status'], ShiftStatus.planned.value);
      },
    );

    test(
      'publishShiftBatch falls back to direct Firestore writes when the function is missing',
      () async {
        service = FirestoreService(
          firestore: firestore,
          cloudFunctionInvoker: (_, __) async {
            throw FirebaseFunctionsException(
              message: 'missing',
              code: 'unavailable',
            );
          },
        );

        final shifts = firestore
            .collection('organizations')
            .doc('org-1')
            .collection('shifts');
        await shifts.doc('shift-1').set(
              Shift(
                id: 'shift-1',
                orgId: 'org-1',
                userId: 'employee-1',
                employeeName: 'Anna',
                title: 'Fruehdienst',
                startTime: DateTime(2026, 4, 5, 8),
                endTime: DateTime(2026, 4, 5, 16),
              ).toFirestoreMap(),
            );

        await service.publishShiftBatch(
          orgId: 'org-1',
          shifts: [
            Shift(
              id: 'shift-1',
              orgId: 'org-1',
              userId: 'employee-1',
              employeeName: 'Anna',
              title: 'Fruehdienst',
              startTime: DateTime(2026, 4, 5, 8),
              endTime: DateTime(2026, 4, 5, 16),
            ),
          ],
          status: ShiftStatus.confirmed,
        );

        final snapshot = await shifts.doc('shift-1').get();

        expect(snapshot.data()?['status'], ShiftStatus.confirmed.value);
      },
    );

    test(
      'saveWorkEntry falls back to direct Firestore writes when the function is missing',
      () async {
        service = FirestoreService(
          firestore: firestore,
          cloudFunctionInvoker: (_, __) async {
            throw FirebaseFunctionsException(
              message: 'missing',
              code: 'not-found',
            );
          },
        );

        await service.saveWorkEntry(
          WorkEntry(
            orgId: 'org-1',
            userId: 'employee-1',
            date: DateTime(2026, 4, 5),
            startTime: DateTime(2026, 4, 5, 8),
            endTime: DateTime(2026, 4, 5, 16),
            breakMinutes: 30,
          ),
        );

        final snapshot = await firestore
            .collection('organizations')
            .doc('org-1')
            .collection('workEntries')
            .get();

        expect(snapshot.docs, hasLength(1));
        expect(snapshot.docs.single.data()['userId'], 'employee-1');
        expect(snapshot.docs.single.data()['breakMinutes'], 30.0);
      },
    );
  });
}
