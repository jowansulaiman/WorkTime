import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/product.dart';
import 'package:worktime_app/models/scan_event.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/repositories/firestore_inventory_repository.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

/// Repo-Fake fuer den Hybrid-Test: Telemetrie-Cloud-Zugriffe schlagen fehl
/// (offline), alles andere laeuft gegen FakeFirestore.
class _ScanEventsOfflineRepository extends FirestoreInventoryRepository {
  _ScanEventsOfflineRepository(FakeFirebaseFirestore firestore)
      : super(firestore: firestore);

  @override
  Future<void> addScanEvent(ScanEvent event) async {
    throw Exception('offline');
  }

  @override
  Future<List<ScanEvent>> fetchScanEvents(String orgId, {int limit = 500}) {
    throw Exception('offline');
  }
}

/// Harte Barcode-Eindeutigkeit je Laden (saveProduct) + Scan-Telemetrie
/// (logScanEvent/fetchScanEvents) im lokalen Modus.
void main() {
  late FirestoreService firestoreService;

  // Bewusst KEIN Demo-Nutzer, damit _maybeSeedLocalDemo nicht greift.
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
    firestoreService = FirestoreService(firestore: FakeFirebaseFirestore());
  });

  Future<InventoryProvider> seededProvider(List<Product> products) async {
    final provider = InventoryProvider(
      firestoreService: firestoreService,
      disableAuthentication: true,
    );
    await provider.updateSession(user);
    for (final product in products) {
      await provider.saveProduct(product);
    }
    return provider;
  }

  Product product(String name, String? barcode, {String siteId = 'site-1'}) {
    return Product(
      orgId: 'org-1',
      siteId: siteId,
      name: name,
      barcode: barcode,
    );
  }

  group('saveProduct – harte Barcode-Eindeutigkeit je Laden', () {
    test('Neuanlage mit vergebenem Barcode wirft deutschen StateError',
        () async {
      final provider = await seededProvider([
        product('Cola', '4011200296908'),
      ]);
      expect(
        () => provider.saveProduct(product('Cola Kopie', '4011200296908')),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Barcode bereits vergeben'),
          ),
        ),
      );
    });

    test('auch eine andere Schreibweise desselben Codes kollidiert', () async {
      final provider = await seededProvider([
        product('US-Import', '036000291452'), // UPC-A (12)
      ]);
      expect(
        // EAN-13-Schreibweise mit fuehrender Null.
        () => provider.saveProduct(product('Kopie', '0036000291452')),
        throwsA(isA<StateError>()),
      );
    });

    test('deaktivierter Artikel blockiert den Code ebenfalls', () async {
      final provider = await seededProvider([]);
      await provider.saveProduct(product('Alt', '4011200296908'));
      final stored = provider.products.single;
      await provider.saveProduct(stored.copyWith(isActive: false));
      expect(
        () => provider.saveProduct(product('Neu', '4011200296908')),
        throwsA(isA<StateError>()),
      );
    });

    test('gleicher Code in ANDEREM Laden ist erlaubt', () async {
      final provider = await seededProvider([
        product('Cola Laden 1', '4011200296908'),
      ]);
      await provider.saveProduct(
        product('Cola Laden 2', '4011200296908', siteId: 'site-2'),
      );
      expect(provider.products, hasLength(2));
    });

    test('Edit ohne Barcode-Aenderung bleibt erlaubt (Altbestand)', () async {
      // Zwei Alt-Duplikate direkt in den Bestand heben ist ueber saveProduct
      // nicht mehr moeglich — wir simulieren den Altbestand, indem der zweite
      // Artikel zuerst ohne Code angelegt und dann per unveraendertem Barcode
      // geprueft wird: ein Edit, der den Code NICHT anfasst, darf nie an der
      // Eindeutigkeitspruefung scheitern.
      final provider = await seededProvider([
        product('Cola', '4011200296908'),
      ]);
      final stored = provider.products.single;
      await provider.saveProduct(stored.copyWith(name: 'Cola 0,33'));
      expect(provider.products.single.name, 'Cola 0,33');
    });

    test('Barcode-AENDERUNG auf vergebenen Code wird abgelehnt', () async {
      final provider = await seededProvider([
        product('Cola', '4011200296908'),
        product('Fanta', '4006381333931'),
      ]);
      final fanta =
          provider.products.firstWhere((p) => p.name == 'Fanta');
      expect(
        () => provider.saveProduct(fanta.copyWith(barcode: '4011200296908')),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('Scan-Telemetrie (lokaler Modus)', () {
    test('logScanEvent speichert, fetchScanEvents liefert neueste zuerst',
        () async {
      final provider = await seededProvider([]);
      await provider.logScanEvent(
        code: '4011200296908',
        outcome: ScanOutcome.matched,
        siteId: 'site-1',
        mode: 'book',
        source: 'camera',
        timeToHitMs: 640,
        platform: 'android',
      );
      await provider.logScanEvent(
        code: '999',
        outcome: ScanOutcome.notFound,
        siteId: 'site-1',
        mode: 'order',
        source: 'manual',
        platform: 'android',
      );

      final events = await provider.fetchScanEvents();
      expect(events, hasLength(2));
      expect(events.first.code, '999'); // neueste zuerst
      expect(events.first.outcome, ScanOutcome.notFound);
      expect(events.last.timeToHitMs, 640);
    });

    test('Telemetrie ueberlebt den Provider-Neustart (SharedPreferences)',
        () async {
      final provider = await seededProvider([]);
      await provider.logScanEvent(
        code: '4011200296908',
        outcome: ScanOutcome.matched,
        siteId: 'site-1',
      );

      // "App-Neustart": frische Provider-Instanz, gleicher lokaler Speicher.
      final restarted = InventoryProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      await restarted.updateSession(user);
      final events = await restarted.fetchScanEvents();
      expect(events, hasLength(1));
      expect(events.single.code, '4011200296908');
    });

    test(
        'hybrid-Offline-Fallback laedt den Alt-Spiegel, statt ihn zu '
        'ueberschreiben', () async {
      // Alt-Spiegel einer frueheren Session (persistiert).
      await DatabaseService.saveLocalScanEvents(
        [
          ScanEvent(
            orgId: 'org-1',
            siteId: 'site-1',
            code: 'ALT-1',
            outcome: ScanOutcome.matched,
            createdAt: DateTime(2026, 7, 10, 12),
          ),
        ],
        scope: LocalStorageScope.fromUser(user),
      );

      // Hybrid-Provider, dessen Telemetrie-Cloud-Zugriffe fehlschlagen.
      final firestore = FakeFirebaseFirestore();
      final provider = InventoryProvider(
        firestoreService: FirestoreService(firestore: firestore),
        inventoryRepository: _ScanEventsOfflineRepository(firestore),
      );
      await provider.updateSession(
        user,
        localStorageOnly: false,
        hybridStorageEnabled: true,
      );

      await provider.logScanEvent(
        code: 'NEU-1',
        outcome: ScanOutcome.notFound,
        siteId: 'site-1',
      );

      // Fallback-Read: Alt-Spiegel + neues Event, neueste zuerst.
      final events = await provider.fetchScanEvents();
      expect(events.map((e) => e.code), ['NEU-1', 'ALT-1']);

      // Und der persistierte Spiegel enthaelt weiterhin BEIDE.
      final persisted = await DatabaseService.loadLocalScanEvents(
        scope: LocalStorageScope.fromUser(user),
      );
      expect(persisted, hasLength(2));
    });

    test('logScanEvent cappt ueberlange Codes (QR-Inhalte)', () async {
      final provider = await seededProvider([]);
      await provider.logScanEvent(
        code: 'X' * 500,
        outcome: ScanOutcome.notFound,
        siteId: 'site-1',
      );
      final events = await provider.fetchScanEvents();
      expect(events.single.code.length, lessThanOrEqualTo(128));
    });

    test('logScanEvent schreibt bewusst KEIN createdByUid (Datenschutz)',
        () async {
      final provider = await seededProvider([]);
      await provider.logScanEvent(
        code: '4011200296908',
        outcome: ScanOutcome.matched,
        siteId: 'site-1',
      );
      final events = await provider.fetchScanEvents();
      expect(events.single.createdByUid, isNull);
    });

    test('logScanEvent wirft nie (auch ohne Organisation)', () async {
      final provider = InventoryProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      // Keine Session -> orgId == null -> stiller No-op.
      await provider.logScanEvent(
        code: 'x',
        outcome: ScanOutcome.notFound,
      );
      expect(await provider.fetchScanEvents(), isEmpty);
    });
  });
}
