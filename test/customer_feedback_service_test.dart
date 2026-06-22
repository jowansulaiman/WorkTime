import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/customer_feedback.dart';
import 'package:worktime_app/services/firestore_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late FirestoreService service;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = FirestoreService(firestore: firestore);
  });

  CustomerFeedback buildFeedback({String code = 'ABC-123'}) =>
      CustomerFeedback(
        orgId: 'main-org',
        referenceCode: code,
        type: FeedbackType.complaint,
        message: 'Die Schlange an der Kasse war zu lang.',
        storeName: 'Tabak Börse',
        rating: 2,
      );

  test('submitCustomerFeedback schreibt eine lesbare Rückmeldung mit Status neu',
      () async {
    final id = await service.submitCustomerFeedback(buildFeedback());

    final items = await service.watchCustomerFeedback('main-org').first;
    expect(items, hasLength(1));
    final item = items.single;
    expect(item.id, id);
    expect(item.referenceCode, 'ABC-123');
    expect(item.type, FeedbackType.complaint);
    expect(item.status, FeedbackStatus.pending);
    expect(item.source, CustomerFeedback.publicWebSource);
    expect(item.rating, 2);
    expect(item.createdAt, isNotNull);
  });

  test('submit schreibt nur die allowlisteten Felder (+createdAt)', () async {
    await service.submitCustomerFeedback(buildFeedback());
    final snapshot = await firestore
        .collection('organizations')
        .doc('main-org')
        .collection('customerFeedback')
        .get();

    expect(snapshot.docs, hasLength(1));
    expect(
      snapshot.docs.single.data().keys.toSet(),
      {
        'orgId',
        'referenceCode',
        'type',
        'message',
        'storeName',
        'rating',
        'incidentDate',
        'customerName',
        'customerContact',
        'status',
        'source',
        'createdAt',
      },
    );
  });

  test('updateCustomerFeedbackStatus ändert den Status', () async {
    final id = await service.submitCustomerFeedback(buildFeedback());

    await service.updateCustomerFeedbackStatus(
      orgId: 'main-org',
      feedbackId: id,
      status: FeedbackStatus.done,
      handledByUid: 'mitarbeiter-1',
    );

    final items = await service.watchCustomerFeedback('main-org').first;
    expect(items.single.status, FeedbackStatus.done);
    expect(items.single.handledByUid, 'mitarbeiter-1');
  });

  test('deleteCustomerFeedback entfernt die Rückmeldung', () async {
    final id = await service.submitCustomerFeedback(buildFeedback());
    await service.deleteCustomerFeedback(orgId: 'main-org', feedbackId: id);

    final items = await service.watchCustomerFeedback('main-org').first;
    expect(items, isEmpty);
  });

  test('watchCustomerFeedback ist nach createdAt absteigend sortiert',
      () async {
    await service.submitCustomerFeedback(buildFeedback(code: 'AAA-111'));
    await service.submitCustomerFeedback(buildFeedback(code: 'BBB-222'));

    final items = await service.watchCustomerFeedback('main-org').first;
    expect(items, hasLength(2));
    expect(
      items.map((item) => item.referenceCode),
      containsAll(['AAA-111', 'BBB-222']),
    );
    // Sortierung: createdAt nicht-aufsteigend (neueste zuerst).
    for (var i = 0; i + 1 < items.length; i++) {
      expect(
        items[i].createdAt!.isBefore(items[i + 1].createdAt!),
        isFalse,
      );
    }
  });
}
