import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/services/fcm_token_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late FcmTokenRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = FcmTokenRepository(firestore: firestore);
  });

  Future<QuerySnapshot<Map<String, dynamic>>> tokensOf(String uid) =>
      firestore.collection('users').doc(uid).collection('fcmTokens').get();

  test('saveToken legt ein Token-Doc je Installation mit genau der '
      'Rules-Allowlist an', () async {
    await repo.saveToken(
      uid: 'u1',
      orgId: 'org-1',
      installationId: 'inst-A',
      token: 'tok-123',
      platform: 'android',
    );

    final snap = await firestore
        .collection('users')
        .doc('u1')
        .collection('fcmTokens')
        .doc('inst-A')
        .get();
    expect(snap.exists, isTrue);
    final data = snap.data()!;
    expect(data['token'], 'tok-123');
    expect(data['platform'], 'android');
    expect(data['orgId'], 'org-1');
    // Muss exakt der hasOnly-Allowlist in firestore.rules entsprechen.
    expect(
      data.keys.toSet(),
      <String>{'token', 'platform', 'orgId', 'appVersion', 'updatedAt'},
    );
  });

  test('Self-Refresh überschreibt dasselbe Doc (kein Waisen-Doc)', () async {
    await repo.saveToken(
      uid: 'u1',
      orgId: 'org-1',
      installationId: 'inst-A',
      token: 'old',
      platform: 'android',
    );
    await repo.saveToken(
      uid: 'u1',
      orgId: 'org-1',
      installationId: 'inst-A',
      token: 'new',
      platform: 'android',
    );

    final col = await tokensOf('u1');
    expect(col.docs.length, 1);
    expect(col.docs.single.data()['token'], 'new');
  });

  test('mehrere Geräte → mehrere Token-Docs', () async {
    await repo.saveToken(
      uid: 'u1',
      orgId: 'org-1',
      installationId: 'inst-A',
      token: 'a',
      platform: 'android',
    );
    await repo.saveToken(
      uid: 'u1',
      orgId: 'org-1',
      installationId: 'inst-B',
      token: 'b',
      platform: 'ios',
    );

    final col = await tokensOf('u1');
    expect(col.docs.length, 2);
  });

  test('deleteToken entfernt das Geräte-Doc (Logout-Cleanup)', () async {
    await repo.saveToken(
      uid: 'u1',
      orgId: 'org-1',
      installationId: 'inst-A',
      token: 'tok',
      platform: 'ios',
    );
    await repo.deleteToken(uid: 'u1', installationId: 'inst-A');

    final snap = await firestore
        .collection('users')
        .doc('u1')
        .collection('fcmTokens')
        .doc('inst-A')
        .get();
    expect(snap.exists, isFalse);
  });
}
