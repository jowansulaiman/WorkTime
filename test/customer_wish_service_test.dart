import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/customer_wish.dart';
import 'package:worktime_app/services/firestore_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late FirestoreService service;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = FirestoreService(firestore: firestore);
  });

  CustomerWish buildWish({String code = 'ABC-123'}) => CustomerWish(
        orgId: 'main-org',
        referenceCode: code,
        storeName: 'Tabak Börse',
        category: CustomerWishCategory.magazine,
        wishText: 'Spiegel Ausgabe 26',
        quantity: 2,
      );

  test('submitCustomerWish schreibt einen lesbaren Wunsch mit Status neu',
      () async {
    final id = await service.submitCustomerWish(buildWish());

    final wishes = await service.watchCustomerWishes('main-org').first;
    expect(wishes, hasLength(1));
    final wish = wishes.single;
    expect(wish.id, id);
    expect(wish.referenceCode, 'ABC-123');
    expect(wish.status, CustomerWishStatus.pending);
    expect(wish.source, CustomerWish.publicWebSource);
    expect(wish.quantity, 2);
    expect(wish.createdAt, isNotNull);
  });

  test('submit schreibt nur die allowlisteten Felder (+createdAt)', () async {
    await service.submitCustomerWish(buildWish());
    final snapshot = await firestore
        .collection('organizations')
        .doc('main-org')
        .collection('customerWishes')
        .get();

    expect(snapshot.docs, hasLength(1));
    expect(
      snapshot.docs.single.data().keys.toSet(),
      {
        'orgId',
        'referenceCode',
        'storeName',
        'category',
        'wishText',
        'quantity',
        'desiredDate',
        'customerName',
        'customerContact',
        'status',
        'source',
        'createdAt',
      },
    );
  });

  test('updateCustomerWishStatus ändert den Status', () async {
    final id = await service.submitCustomerWish(buildWish());

    await service.updateCustomerWishStatus(
      orgId: 'main-org',
      wishId: id,
      status: CustomerWishStatus.done,
      handledByUid: 'mitarbeiter-1',
    );

    final wishes = await service.watchCustomerWishes('main-org').first;
    expect(wishes.single.status, CustomerWishStatus.done);
    expect(wishes.single.handledByUid, 'mitarbeiter-1');
  });

  test('deleteCustomerWish entfernt den Wunsch', () async {
    final id = await service.submitCustomerWish(buildWish());
    await service.deleteCustomerWish(orgId: 'main-org', wishId: id);

    final wishes = await service.watchCustomerWishes('main-org').first;
    expect(wishes, isEmpty);
  });

  test('watchCustomerWishes ist nach createdAt absteigend sortiert', () async {
    await service.submitCustomerWish(buildWish(code: 'AAA-111'));
    await service.submitCustomerWish(buildWish(code: 'BBB-222'));

    final wishes = await service.watchCustomerWishes('main-org').first;
    expect(wishes, hasLength(2));
    expect(
      wishes.map((wish) => wish.referenceCode),
      containsAll(['AAA-111', 'BBB-222']),
    );
    // Sortierung: createdAt nicht-aufsteigend (neueste zuerst).
    for (var i = 0; i + 1 < wishes.length; i++) {
      expect(
        wishes[i].createdAt!.isBefore(wishes[i + 1].createdAt!),
        isFalse,
      );
    }
  });
}
