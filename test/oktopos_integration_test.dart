import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/product.dart';
import 'package:worktime_app/models/stock_movement.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

/// Tests für die OktoPOS-Kassenanbindung: Model-Felder (Zwei-Serialisierungs-
/// Regel) für den Kassen-Sync sowie der Provider-Trigger (Callable-Pfad).
void main() {
  group('Product.externalPosId – Zwei-Serialisierungs-Regel', () {
    test('Firestore round-trip (camelCase) erhält externalPosId', () {
      const product = Product(
        orgId: 'org-1',
        siteId: 'site-1',
        name: 'Marlboro Rot',
        barcode: '4012345678901',
        externalPosId: 'POS-99',
      );
      final restored = Product.fromFirestore('p1', product.toFirestoreMap());
      expect(restored.externalPosId, 'POS-99');
    });

    test('lokaler round-trip (snake_case) erhält externalPosId', () {
      const product = Product(
        orgId: 'org-1',
        siteId: 'site-1',
        name: 'Marlboro Rot',
        externalPosId: 'POS-99',
      );
      expect(product.toMap()['external_pos_id'], 'POS-99');
      final restored = Product.fromMap(product.toMap());
      expect(restored.externalPosId, 'POS-99');
    });

    test('copyWith clearExternalPosId leert das Feld, sonst bleibt es', () {
      const product = Product(
        orgId: 'o',
        siteId: 's',
        name: 'x',
        externalPosId: 'POS-1',
      );
      expect(product.copyWith(clearExternalPosId: true).externalPosId, isNull);
      expect(product.copyWith().externalPosId, 'POS-1');
      expect(product.copyWith(externalPosId: 'POS-2').externalPosId, 'POS-2');
    });
  });

  group('StockMovement.source/externalRef – Kassen-Provenienz', () {
    test('Firestore round-trip erhält source + externalRef', () {
      const movement = StockMovement(
        orgId: 'org-1',
        siteId: 'site-1',
        productId: 'p1',
        type: StockMovementType.issue,
        quantityDelta: -2,
        source: 'oktopos',
        externalRef: 'BON-4711',
      );
      final restored =
          StockMovement.fromFirestore('m1', movement.toFirestoreMap());
      expect(restored.source, 'oktopos');
      expect(restored.externalRef, 'BON-4711');
      expect(restored.isFromPos, isTrue);
    });

    test('lokaler round-trip (snake_case) erhält source + externalRef', () {
      const movement = StockMovement(
        orgId: 'org-1',
        siteId: 'site-1',
        productId: 'p1',
        type: StockMovementType.issue,
        quantityDelta: -2,
        source: 'oktopos',
        externalRef: 'BON-4711',
      );
      expect(movement.toMap()['external_ref'], 'BON-4711');
      final restored = StockMovement.fromMap(movement.toMap());
      expect(restored.source, 'oktopos');
      expect(restored.externalRef, 'BON-4711');
    });

    test('manuelle Bewegung trägt keine POS-Provenienz', () {
      const movement = StockMovement(
        orgId: 'o',
        siteId: 's',
        productId: 'p',
        type: StockMovementType.adjustment,
        quantityDelta: 1,
      );
      expect(movement.isFromPos, isFalse);
      // toFirestoreMap muss den Key tragen (sonst bricht die Rules-Allowlist),
      // aber als null für manuelle Buchungen.
      expect(movement.toFirestoreMap().containsKey('source'), isTrue);
      expect(movement.toFirestoreMap()['source'], isNull);
    });
  });

  group('InventoryProvider.triggerOktoposSync', () {
    const user = AppUserProfile(
      uid: 'owner-1',
      orgId: 'org-1',
      email: 'owner@laden.test',
      role: UserRole.admin,
      isActive: true,
      settings: UserSettings(name: 'Inhaber'),
    );

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      DatabaseService.resetCachedPrefs();
    });

    test('cloud-Modus ruft den Callable mit orgId/siteId und liefert Summary',
        () async {
      String? capturedName;
      Map<String, dynamic>? capturedPayload;
      final service = FirestoreService(
        firestore: FakeFirebaseFirestore(),
        cloudFunctionInvoker: (name, payload) async {
          capturedName = name;
          capturedPayload = payload;
          return <String, dynamic>{
            'appliedMovements': 3,
            'reversedMovements': 1,
            'unmatchedLineItems': 0,
          };
        },
      );
      final provider = InventoryProvider(firestoreService: service);
      await provider.updateSession(user, localStorageOnly: false);
      await Future<void>.delayed(Duration.zero);

      final result = await provider.triggerOktoposSync(siteId: 'site-1');

      expect(capturedName, 'syncOktoposTransactions');
      expect(capturedPayload?['orgId'], 'org-1');
      expect(capturedPayload?['siteId'], 'site-1');
      expect((result['appliedMovements'] as num).toInt(), 3);
    });

    test('lokaler Demo-Modus wirft (keine Firebase-Anbindung)', () async {
      final service = FirestoreService(firestore: FakeFirebaseFirestore());
      final provider = InventoryProvider(
        firestoreService: service,
        disableAuthentication: true,
      );
      await provider.updateSession(user);

      expect(
        () => provider.triggerOktoposSync(siteId: 'site-1'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('OktoPOS-Einstellungen (merge-sicher, Cursor überlebt)', () {
    const user = AppUserProfile(
      uid: 'owner-1',
      orgId: 'org-1',
      email: 'owner@laden.test',
      role: UserRole.admin,
      isActive: true,
      settings: UserSettings(name: 'Inhaber'),
    );

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      DatabaseService.resetCachedPrefs();
    });

    test('saveOktoposConfig überschreibt den serverseitigen Cursor nicht',
        () async {
      final firestore = FakeFirebaseFirestore();
      // Cursor wie von der Cloud Function (Admin SDK) vorab geschrieben.
      await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('config')
          .doc('oktoposSync')
          .set({
        'sites': {
          'site-1': {'lastBusinessDay': '2026-06-20'},
        },
      });
      final service = FirestoreService(firestore: firestore);
      final provider = InventoryProvider(firestoreService: service);
      await provider.updateSession(user, localStorageOnly: false);
      await Future<void>.delayed(Duration.zero);

      await provider.saveOktoposConfig(
        baseUrl: 'https://demo.example/v1',
        enabled: true,
        defaultSize: 50,
        cashRegisterBySiteId: const {'site-1': 1, 'site-2': null},
      );

      final config = await provider.loadOktoposConfig();
      expect(config, isNotNull);
      expect(config!['baseUrl'], 'https://demo.example/v1');
      expect(config['enabled'], true);
      final sites = config['sites'] as Map;
      final site1 = sites['site-1'] as Map;
      expect(site1['cashRegisterId'], 1);
      // Der Cloud-Function-Cursor überlebt den Admin-Save (Nested-Merge).
      expect(site1['lastBusinessDay'], '2026-06-20');
      expect((sites['site-2'] as Map)['cashRegisterId'], isNull);
    });

    test('saveOktoposConfig wirft im lokalen Demo-Modus', () async {
      final service = FirestoreService(firestore: FakeFirebaseFirestore());
      final provider = InventoryProvider(
        firestoreService: service,
        disableAuthentication: true,
      );
      await provider.updateSession(user);

      expect(
        () => provider.saveOktoposConfig(
          baseUrl: 'https://x/v1',
          enabled: false,
          defaultSize: 50,
          cashRegisterBySiteId: const {},
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('M5 – Artikel-Push (Product.taxRatePercent + Provider)', () {
    const user = AppUserProfile(
      uid: 'owner-1',
      orgId: 'org-1',
      email: 'owner@laden.test',
      role: UserRole.admin,
      isActive: true,
      settings: UserSettings(name: 'Inhaber'),
    );

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      DatabaseService.resetCachedPrefs();
    });

    test('Product.taxRatePercent round-trippt und lässt sich leeren', () {
      const product = Product(
        orgId: 'o',
        siteId: 's',
        name: 'Zigaretten',
        sellingPriceCents: 950,
        taxRatePercent: 19,
      );
      expect(
        Product.fromFirestore('p', product.toFirestoreMap()).taxRatePercent,
        19,
      );
      expect(product.toMap()['tax_rate_percent'], 19);
      expect(Product.fromMap(product.toMap()).taxRatePercent, 19);
      expect(product.copyWith(clearTaxRatePercent: true).taxRatePercent, isNull);
      expect(product.copyWith(taxRatePercent: 7).taxRatePercent, 7);
    });

    test('pushOktoposArticles ruft den Callable und liefert Summary', () async {
      String? capturedName;
      Map<String, dynamic>? capturedPayload;
      final service = FirestoreService(
        firestore: FakeFirebaseFirestore(),
        cloudFunctionInvoker: (name, payload) async {
          capturedName = name;
          capturedPayload = payload;
          return <String, dynamic>{
            'created': 5,
            'updated': 2,
            'failed': 0,
            'skipped': 1,
          };
        },
      );
      final provider = InventoryProvider(firestoreService: service);
      await provider.updateSession(user, localStorageOnly: false);
      await Future<void>.delayed(Duration.zero);

      final result = await provider.pushOktoposArticles(siteId: 'site-1');

      expect(capturedName, 'pushOktoposArticles');
      expect(capturedPayload?['orgId'], 'org-1');
      expect(capturedPayload?['siteId'], 'site-1');
      expect((result['created'] as num).toInt(), 5);
    });

    test('pushOktoposArticles wirft im lokalen Demo-Modus', () async {
      final service = FirestoreService(firestore: FakeFirebaseFirestore());
      final provider = InventoryProvider(
        firestoreService: service,
        disableAuthentication: true,
      );
      await provider.updateSession(user);

      expect(
        () => provider.pushOktoposArticles(siteId: 'site-1'),
        throwsA(isA<StateError>()),
      );
    });

    test('saveOktoposConfig schreibt Push-Einstellungen merge-sicher', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('config')
          .doc('oktoposSync')
          .set({
        'sites': {
          'site-1': {'lastBusinessDay': '2026-06-20'},
        },
      });
      final service = FirestoreService(firestore: firestore);
      final provider = InventoryProvider(firestoreService: service);
      await provider.updateSession(user, localStorageOnly: false);
      await Future<void>.delayed(Duration.zero);

      await provider.saveOktoposConfig(
        baseUrl: 'https://demo.example/v1',
        enabled: false,
        defaultSize: 50,
        cashRegisterBySiteId: const {'site-1': 1},
        distributionChannel: 'INHOUSE',
        defaultUnitToken: 'Stück',
        defaultTaxRate: 19,
        cashierCanChangePrice: true,
      );

      final config = await provider.loadOktoposConfig();
      final push = config!['push'] as Map;
      expect(push['distributionChannel'], 'INHOUSE');
      expect(push['defaultUnitToken'], 'Stück');
      expect(push['defaultTaxRate'], 19);
      expect(push['cashierCanChangePrice'], true);
      // Push-Speichern darf den serverseitigen Cursor nicht überschreiben.
      expect(
        ((config['sites'] as Map)['site-1'] as Map)['lastBusinessDay'],
        '2026-06-20',
      );
    });
  });

  group('M6a – Kunden-Push (Provider + Config)', () {
    const user = AppUserProfile(
      uid: 'owner-1',
      orgId: 'org-1',
      email: 'owner@laden.test',
      role: UserRole.admin,
      isActive: true,
      settings: UserSettings(name: 'Inhaber'),
    );

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      DatabaseService.resetCachedPrefs();
    });

    test('pushOktoposCustomers ruft den Callable und liefert Summary', () async {
      String? capturedName;
      Map<String, dynamic>? capturedPayload;
      final service = FirestoreService(
        firestore: FakeFirebaseFirestore(),
        cloudFunctionInvoker: (name, payload) async {
          capturedName = name;
          capturedPayload = payload;
          return <String, dynamic>{'created': 4, 'skipped': 2, 'failed': 0};
        },
      );
      final provider = InventoryProvider(firestoreService: service);
      await provider.updateSession(user, localStorageOnly: false);
      await Future<void>.delayed(Duration.zero);

      final result = await provider.pushOktoposCustomers(siteId: 'site-1');

      expect(capturedName, 'pushOktoposCustomers');
      expect(capturedPayload?['orgId'], 'org-1');
      expect(capturedPayload?['siteId'], 'site-1');
      expect((result['created'] as num).toInt(), 4);
    });

    test('pushOktoposCustomers wirft im lokalen Demo-Modus', () async {
      final service = FirestoreService(firestore: FakeFirebaseFirestore());
      final provider = InventoryProvider(
        firestoreService: service,
        disableAuthentication: true,
      );
      await provider.updateSession(user);

      expect(
        () => provider.pushOktoposCustomers(siteId: 'site-1'),
        throwsA(isA<StateError>()),
      );
    });

    test('saveOktoposConfig schreibt customerGroupName merge-sicher', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('config')
          .doc('oktoposSync')
          .set({
        'sites': {
          'site-1': {'lastBusinessDay': '2026-06-20'},
        },
      });
      final service = FirestoreService(firestore: firestore);
      final provider = InventoryProvider(firestoreService: service);
      await provider.updateSession(user, localStorageOnly: false);
      await Future<void>.delayed(Duration.zero);

      await provider.saveOktoposConfig(
        baseUrl: 'https://demo.example/v1',
        enabled: false,
        defaultSize: 50,
        cashRegisterBySiteId: const {},
        customerGroupName: 'Stammkunde',
      );

      final config = await provider.loadOktoposConfig();
      expect(config!['customerGroupName'], 'Stammkunde');
      expect(
        ((config['sites'] as Map)['site-1'] as Map)['lastBusinessDay'],
        '2026-06-20',
      );
    });
  });
}
