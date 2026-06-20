import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/price_history_entry.dart';
import 'package:worktime_app/models/product.dart';
import 'package:worktime_app/models/stock_movement.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

void main() {
  // Nicht-Demo-Nutzer, damit _maybeSeedLocalDemo NICHT greift.
  const user = AppUserProfile(
    uid: 'owner-1',
    orgId: 'org-1',
    email: 'owner@laden.test',
    role: UserRole.admin,
    isActive: true,
    settings: UserSettings(name: 'Inhaber'),
  );

  late FakeFirebaseFirestore firestore;
  late FirestoreService firestoreService;

  InventoryProvider newLocalProvider() => InventoryProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
    firestore = FakeFirebaseFirestore();
    firestoreService = FirestoreService(firestore: firestore);
  });

  Future<InventoryProvider> seededLocalProvider(List<Product> products) async {
    final provider = newLocalProvider();
    await provider.updateSession(user);
    for (final product in products) {
      await provider.saveProduct(product);
    }
    return provider;
  }

  group('productByBarcode / productsByBarcode', () {
    test('findet aktiven Artikel per exaktem Barcode', () async {
      final provider = await seededLocalProvider(const [
        Product(
          orgId: 'org-1',
          siteId: 'site-1',
          name: 'Feuerzeug',
          barcode: '4011200296908',
        ),
      ]);

      final hit = provider.productByBarcode('4011200296908');
      expect(hit, isNotNull);
      expect(hit!.name, 'Feuerzeug');
    });

    test('trimmt fuehrende/abschliessende Leerzeichen beim Suchen', () async {
      final provider = await seededLocalProvider(const [
        Product(
          orgId: 'org-1',
          siteId: 'site-1',
          name: 'Kaugummi',
          barcode: '7622210449283',
        ),
      ]);

      expect(provider.productByBarcode('  7622210449283 '), isNotNull);
    });

    test('leerer/whitespace-Code liefert keinen Treffer', () async {
      final provider = await seededLocalProvider(const [
        Product(
          orgId: 'org-1',
          siteId: 'site-1',
          name: 'Kaugummi',
          barcode: '7622210449283',
        ),
      ]);

      expect(provider.productByBarcode(''), isNull);
      expect(provider.productByBarcode('   '), isNull);
      expect(provider.productsByBarcode('  '), isEmpty);
    });

    test('Standort-Scoping: gleicher Barcode in zwei Laeden -> nur passender',
        () async {
      final provider = await seededLocalProvider(const [
        Product(
          orgId: 'org-1',
          siteId: 'strichmaennchen',
          name: 'Cola Strichmaennchen',
          barcode: '5449000000996',
        ),
        Product(
          orgId: 'org-1',
          siteId: 'tabak-boerse',
          name: 'Cola Tabak Boerse',
          barcode: '5449000000996',
        ),
      ]);

      final hit = provider.productByBarcode(
        '5449000000996',
        siteId: 'tabak-boerse',
      );
      expect(hit, isNotNull);
      expect(hit!.name, 'Cola Tabak Boerse');

      // Ohne Standort: beide sind Treffer.
      expect(provider.productsByBarcode('5449000000996'), hasLength(2));
    });

    test('inaktive Artikel sind standardmaessig kein Treffer, '
        'mit includeInactive aber findbar', () async {
      final provider = await seededLocalProvider(const [
        Product(
          orgId: 'org-1',
          siteId: 'site-1',
          name: 'Altes Produkt',
          barcode: '4006381333931',
          isActive: false,
        ),
      ]);

      expect(provider.productByBarcode('4006381333931'), isNull);
      final inactive = provider.productByBarcode(
        '4006381333931',
        includeInactive: true,
      );
      expect(inactive, isNotNull);
      expect(inactive!.isActive, isFalse);
    });

    test('mehrere aktive Treffer im selben Laden werden alle zurueckgegeben',
        () async {
      final provider = await seededLocalProvider(const [
        Product(
          orgId: 'org-1',
          siteId: 'site-1',
          name: 'Dublette A',
          barcode: '4001234567890',
        ),
        Product(
          orgId: 'org-1',
          siteId: 'site-1',
          name: 'Dublette B',
          barcode: '4001234567890',
        ),
      ]);

      expect(
        provider.productsByBarcode('4001234567890', siteId: 'site-1'),
        hasLength(2),
      );
    });

    test('unbekannter Barcode liefert null/leer', () async {
      final provider = await seededLocalProvider(const [
        Product(
          orgId: 'org-1',
          siteId: 'site-1',
          name: 'Feuerzeug',
          barcode: '4011200296908',
        ),
      ]);

      expect(provider.productByBarcode('0000000000000'), isNull);
      expect(provider.productsByBarcode('0000000000000'), isEmpty);
    });
  });

  group('adjustStock – stabile clientMutationId (Doppel-Scan-Schutz)', () {
    test('zweimaliges Buchen mit gleicher Id bucht nur einmal (Cloud-Modus)',
        () async {
      final provider = InventoryProvider(firestoreService: firestoreService);
      await provider.updateSession(user, localStorageOnly: false);
      await provider.saveProduct(
        const Product(
          orgId: 'org-1',
          siteId: 'site-1',
          name: 'Feuerzeug',
          currentStock: 10,
          barcode: '4011200296908',
        ),
      );
      // Stream-Events durchlaufen lassen, bis der Artikel mit Id da ist.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final productId = provider.products.single.id!;

      const mutationId = 'scan-session-1::feuerzeug::1';
      await provider.adjustStock(
        productId: productId,
        delta: 5,
        type: StockMovementType.receipt,
        clientMutationId: mutationId,
      );
      await provider.adjustStock(
        productId: productId,
        delta: 5,
        type: StockMovementType.receipt,
        clientMutationId: mutationId,
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // Nur eine der beiden identischen Buchungen wird angewendet: 10 + 5 = 15.
      expect(provider.products.single.currentStock, 15);
    });
  });

  group('updateProductPrices – Preisabweichung + Historie', () {
    test('aenderter VK aktualisiert Preis und schreibt einen Historie-Eintrag',
        () async {
      final provider = await seededLocalProvider(const [
        Product(
          orgId: 'org-1',
          siteId: 'site-1',
          name: 'Cola',
          barcode: '5449000000996',
          sellingPriceCents: 199,
        ),
      ]);
      final product = provider.products.single;

      final logged =
          await provider.updateProductPrices(product, newSellingCents: 219);

      expect(logged, 1);
      expect(provider.products.single.sellingPriceCents, 219);
      expect(provider.priceHistory, hasLength(1));
      final entry = provider.priceHistory.single;
      expect(entry.field, PriceField.selling);
      expect(entry.oldCents, 199);
      expect(entry.newCents, 219);

      // Historie ueberlebt den Neustart (lokale Persistenz).
      final restored = newLocalProvider();
      await restored.updateSession(user);
      expect(restored.priceHistory, hasLength(1));
    });

    test('unveraenderter Preis schreibt nichts', () async {
      final provider = await seededLocalProvider(const [
        Product(
          orgId: 'org-1',
          siteId: 'site-1',
          name: 'Cola',
          barcode: '5449000000996',
          sellingPriceCents: 199,
        ),
      ]);
      final product = provider.products.single;

      final logged =
          await provider.updateProductPrices(product, newSellingCents: 199);

      expect(logged, 0);
      expect(provider.priceHistory, isEmpty);
    });

    test('EK und VK gemeinsam aendern protokolliert beide', () async {
      final provider = await seededLocalProvider(const [
        Product(
          orgId: 'org-1',
          siteId: 'site-1',
          name: 'Cola',
          barcode: '5449000000996',
          purchasePriceCents: 80,
          sellingPriceCents: 199,
        ),
      ]);
      final product = provider.products.single;

      final logged = await provider.updateProductPrices(
        product,
        newPurchaseCents: 90,
        newSellingCents: 219,
      );

      expect(logged, 2);
      expect(
        provider.priceHistory.map((e) => e.field).toSet(),
        {PriceField.purchase, PriceField.selling},
      );
    });

    test('priceHistoryFor liefert nur die Eintraege des Artikels (local)',
        () async {
      final provider = await seededLocalProvider(const [
        Product(
          orgId: 'org-1',
          siteId: 'site-1',
          name: 'Cola',
          barcode: '5449000000996',
          sellingPriceCents: 199,
        ),
        Product(
          orgId: 'org-1',
          siteId: 'site-1',
          name: 'Fanta',
          barcode: '5449000011527',
          sellingPriceCents: 199,
        ),
      ]);
      final cola = provider.products.firstWhere((p) => p.name == 'Cola');
      final fanta = provider.products.firstWhere((p) => p.name == 'Fanta');

      await provider.updateProductPrices(cola, newSellingCents: 219);

      final colaHistory = await provider.priceHistoryFor(cola.id!);
      final fantaHistory = await provider.priceHistoryFor(fanta.id!);

      expect(colaHistory, hasLength(1));
      expect(colaHistory.single.newCents, 219);
      expect(fantaHistory, isEmpty);
    });
  });
}
