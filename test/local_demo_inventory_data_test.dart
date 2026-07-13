import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/ean.dart';
import 'package:worktime_app/core/local_demo_data.dart';
import 'package:worktime_app/core/local_demo_inventory_data.dart';
import 'package:worktime_app/models/contact.dart';
import 'package:worktime_app/models/contact_details.dart';
import 'package:worktime_app/models/contact_organization.dart';
import 'package:worktime_app/models/customer_feedback.dart';
import 'package:worktime_app/models/customer_order.dart';
import 'package:worktime_app/models/customer_wish.dart';
import 'package:worktime_app/models/product_batch.dart';
import 'package:worktime_app/models/purchase_order.dart';
import 'package:worktime_app/models/scan_event.dart';
import 'package:worktime_app/models/stock_movement.dart';

void main() {
  const orgId = 'org-demo-test';
  const actorUid = 'demo-actor';
  final now = DateTime(2026, 7, 13, 8, 37);

  late LocalDemoInventoryBundle data;

  setUp(() {
    data = LocalDemoInventoryData.allForOrg(
      orgId: orgId,
      actorUid: actorUid,
      now: now,
    );
  });

  group('LocalDemoInventoryData Abdeckung', () {
    test('liefert Artikel und operative Listen fuer alle drei Standorte', () {
      final expectedSites = LocalDemoInventoryData.siteIdsForOrg(orgId).toSet();

      expect(data.products.map((item) => item.siteId).toSet(), expectedSites);
      for (final siteId in expectedSites) {
        expect(
          data.products.where((item) => item.siteId == siteId).length,
          greaterThanOrEqualTo(4),
        );
      }
      expect(data.orderCarts.map((item) => item.siteId).toSet(), expectedSites);
      expect(
        data.weeklyOrderLists.map((item) => item.siteId).toSet(),
        expectedSites,
      );
      expect(
        data.fridgeRefillLists.map((item) => item.siteId).toSet(),
        expectedSites,
      );

      expect(data.products.any((item) => item.currentStock < 0), isTrue);
      expect(data.products.any((item) => item.isOutOfStock), isTrue);
      expect(data.products.any((item) => item.needsReorder), isTrue);
      expect(data.products.any((item) => item.fridgeNeedsRefill), isTrue);
      expect(data.products.any((item) => !item.isActive), isTrue);
      expect(
        data.products.any((item) => item.sellingPriceCents == null),
        isTrue,
      );
      expect(
        data.products.map((item) => item.barcode).whereType<String>(),
        everyElement(predicate<String>(isValidEanChecksum)),
      );
    });

    test('deckt Chargen-, Bestell-, Bewegungs- und Scan-Enums ab', () {
      expect(
        data.productBatches.map((item) => item.status).toSet(),
        BatchStatus.values.toSet(),
      );
      expect(
        data.purchaseOrders.map((item) => item.status).toSet(),
        PurchaseOrderStatus.values.toSet(),
      );
      expect(
        data.purchaseOrders
            .map((item) => item.expectedDeliveryState(now))
            .toSet(),
        ExpectedDeliveryDayState.values.toSet(),
      );
      expect(
        data.stockMovements.map((item) => item.type).toSet(),
        StockMovementType.values.toSet(),
      );
      expect(
        data.scanEvents.map((item) => item.outcome).toSet(),
        ScanOutcome.values.toSet(),
      );
    });

    test('deckt Kundenauftrag-Status und Wiederholungen ab', () {
      expect(
        data.customerOrders.map((item) => item.status).toSet(),
        CustomerOrderStatus.values.toSet(),
      );
      expect(
        data.customerOrders.map((item) => item.recurrence).toSet(),
        CustomerOrderRecurrence.values.toSet(),
      );
      expect(
        data.customerOrders.any(
          (item) =>
              item.status == CustomerOrderStatus.open &&
              item.pickupDate!.isBefore(now) &&
              !item.isPrepared,
        ),
        isTrue,
      );
    });

    test('bildet jede Wunsch-Kategorie mit jedem Workflow-Status ab', () {
      expect(
        data.customerWishes,
        hasLength(
          CustomerWishCategory.values.length * CustomerWishStatus.values.length,
        ),
      );
      for (final category in CustomerWishCategory.values) {
        for (final status in CustomerWishStatus.values) {
          expect(
            data.customerWishes.where(
              (item) => item.category == category && item.status == status,
            ),
            hasLength(1),
          );
        }
      }
    });

    test('bildet jeden Feedback-Typ mit jedem Workflow-Status ab', () {
      expect(
        data.customerFeedback,
        hasLength(FeedbackType.values.length * FeedbackStatus.values.length),
      );
      for (final type in FeedbackType.values) {
        for (final status in FeedbackStatus.values) {
          expect(
            data.customerFeedback.where(
              (item) => item.type == type && item.status == status,
            ),
            hasLength(1),
          );
        }
      }
    });

    test('deckt CRM-Typen, Status und Organisationsarten ab', () {
      expect(
        data.contacts.map((item) => item.type).toSet(),
        ContactType.values.toSet(),
      );
      expect(
        data.contacts.map((item) => item.status).toSet(),
        ContactStatus.values.toSet(),
      );
      expect(
        data.contacts.map((item) => item.kind).toSet(),
        ContactKind.values.toSet(),
      );
      expect(
        data.contactOrganizations.map((item) => item.type).toSet(),
        OrganizationType.values.toSet(),
      );

      final wholesaler = data.contacts.singleWhere(
        (item) =>
            item.id == LocalDemoInventoryData.contactId(orgId, 'nord-tabak'),
      );
      expect(
        wholesaler.addresses.map((item) => item.type).toSet(),
        AddressType.values.toSet(),
      );
      expect(
        wholesaler.channels.map((item) => item.type).toSet(),
        ChannelType.values.toSet(),
      );
      expect(wholesaler.contactPersons, isNotEmpty);
      expect(wholesaler.bankAccounts.any((item) => item.deactivated), isTrue);

      final customer = data.contacts.singleWhere(
        (item) =>
            item.id == LocalDemoInventoryData.contactId(orgId, 'joerg-hansen'),
      );
      expect(
        customer.consents.map((item) => item.consentType).toSet(),
        ConsentType.values.toSet(),
      );
      expect(customer.consents.any((item) => item.withdrawnAt != null), isTrue);
    });
  });

  group('LocalDemoInventoryData Beziehungen', () {
    test('alle Warenwirtschafts-Fremdschluessel sind aufloesbar', () {
      final supplierIds = data.suppliers.map((item) => item.id).toSet();
      final productsById = {
        for (final product in data.products) product.id!: product,
      };

      for (final product in data.products) {
        if (product.supplierId != null) {
          expect(supplierIds, contains(product.supplierId));
        }
      }
      for (final batch in data.productBatches) {
        final product = productsById[batch.productId];
        expect(product, isNotNull);
        expect(product!.siteId, batch.siteId);
      }
      for (final order in data.purchaseOrders) {
        expect(supplierIds, contains(order.supplierId));
        for (final item in order.items) {
          final product = productsById[item.productId];
          expect(product, isNotNull);
          expect(product!.siteId, order.siteId);
        }
      }
      for (final movement in data.stockMovements) {
        final product = productsById[movement.productId];
        expect(product, isNotNull);
        expect(product!.siteId, movement.siteId);
      }
      for (final history in data.priceHistory) {
        expect(productsById, contains(history.productId));
      }
      for (final scan in data.scanEvents.where(
        (item) => item.productId != null,
      )) {
        expect(productsById, contains(scan.productId));
      }
    });

    test(
      'eingebettete Filiallisten referenzieren Artikel desselben Standorts',
      () {
        final productsById = {
          for (final product in data.products) product.id!: product,
        };

        for (final list in [...data.orderCarts, ...data.weeklyOrderLists]) {
          for (final item in list.items.where(
            (entry) => entry.productId != null,
          )) {
            expect(productsById[item.productId]!.siteId, list.siteId);
          }
        }
        for (final list in data.fridgeRefillLists) {
          for (final item in list.items.where(
            (entry) => entry.productId != null,
          )) {
            expect(productsById[item.productId]!.siteId, list.siteId);
          }
        }
        expect(
          data.fridgeRefillLists
              .expand((list) => list.items)
              .any((item) => item.isFreeText),
          isTrue,
        );
      },
    );

    test(
      'CRM-, Wunsch- und Kundenauftrags-Links zeigen auf vorhandene IDs',
      () {
        final contactIds = data.contacts.map((item) => item.id).toSet();
        final wishIds = data.customerWishes.map((item) => item.id).toSet();
        final productIds = data.products.map((item) => item.id).toSet();

        for (final supplier in data.suppliers.where(
          (item) => item.contactId != null,
        )) {
          expect(contactIds, contains(supplier.contactId));
        }
        for (final contact in data.contacts) {
          if (contact.parentContactId != null) {
            expect(contactIds, contains(contact.parentContactId));
          }
          for (final person in contact.contactPersons) {
            expect(contactIds, contains(person.personContactId));
          }
        }
        for (final wish in data.customerWishes.where(
          (item) => item.contactId != null,
        )) {
          expect(contactIds, contains(wish.contactId));
        }
        for (final feedback in data.customerFeedback.where(
          (item) => item.contactId != null,
        )) {
          expect(contactIds, contains(feedback.contactId));
        }
        for (final order in data.customerOrders) {
          if (order.contactId != null) {
            expect(contactIds, contains(order.contactId));
          }
          if (order.sourceWishId != null) {
            expect(wishIds, contains(order.sourceWishId));
          }
          for (final item in order.items.where(
            (entry) => entry.productId != null,
          )) {
            expect(productIds, contains(item.productId));
          }
        }
      },
    );

    test('Cloud-Fakten referenzieren Artikel und Zaehldaten konsistent', () {
      final productsById = {
        for (final product in data.products) product.id!: product,
      };
      final countIds = data.cloudCashCounts.map((item) => item.id).toSet();

      for (final receipt in data.cloudPosReceipts) {
        for (final line in receipt.lines.where(
          (item) => item.productId != null,
        )) {
          final product = productsById[line.productId];
          expect(product, isNotNull);
          expect(product!.siteId, receipt.siteId);
        }
      }
      for (final closing in data.cloudCashClosings.where(
        (item) => item.cashCountId != null,
      )) {
        expect(countIds, contains(closing.cashCountId));
        final count = data.cloudCashCounts.singleWhere(
          (item) => item.id == closing.cashCountId,
        );
        expect(count.siteId, closing.siteId);
        expect(count.businessDay, closing.businessDay);
        expect(
          closing.cashDifferenceCents,
          closing.cashCountedCents! - closing.cashExpectedCents!,
        );
      }
    });
  });

  group('LocalDemoInventoryData Cloud-Faelle und Stabilitaet', () {
    test(
      'enthaelt Verkauf, Retoure, Trainingsbeleg und Datenqualitaetsfaelle',
      () {
        expect(data.cloudPosReceipts.any((item) => item.training), isTrue);
        expect(
          data.cloudPosReceipts.any((item) => item.type == 'cash'),
          isTrue,
        );
        expect(
          data.cloudPosReceipts.any(
            (item) => item.type == 'refund' && (item.grossCents ?? 0) < 0,
          ),
          isTrue,
        );
        expect(
          data.cloudPosReceipts.any(
            (item) => item.type == 'refund' && (item.grossCents ?? 0) > 0,
          ),
          isTrue,
        );
        expect(data.cloudPosReceipts.any((item) => item.taxes.isEmpty), isTrue);
        expect(
          data.cloudPosDailyStats.any((item) => item.positiveRefundCount > 0),
          isTrue,
        );
        expect(
          data.cloudPosDailyStats.any(
            (item) => item.netUncoveredGrossCents > 0,
          ),
          isTrue,
        );
      },
    );

    test('enthaelt Kassensturz exakt, zu hoch, zu niedrig und blind', () {
      final differences =
          data.cloudCashCounts
              .map((item) => item.differenceCents)
              .whereType<int>()
              .toSet();
      expect(differences.any((value) => value < 0), isTrue);
      expect(differences, contains(0));
      expect(differences.any((value) => value > 0), isTrue);
      expect(
        data.cloudCashCounts.any(
          (item) =>
              item.source == 'kiosk' &&
              item.expectedCents == null &&
              item.differenceCents == null,
        ),
        isTrue,
      );
      expect(
        data.cloudCashClosings.any((item) => item.bookedToFinance),
        isTrue,
      );
      expect(
        data.cloudCashClosings.any((item) => item.cashCountId == null),
        isTrue,
      );
    });

    test('gleicher Anchor erzeugt dieselben stabilen Demo-IDs', () {
      final again = LocalDemoInventoryData.allForOrg(
        orgId: orgId,
        actorUid: actorUid,
        now: now,
      );

      expect(
        again.products.map((item) => item.id),
        data.products.map((item) => item.id),
      );
      expect(
        again.customerWishes.map((item) => item.id),
        data.customerWishes.map((item) => item.id),
      );
      expect(
        again.cloudPosReceipts.map((item) => item.id),
        data.cloudPosReceipts.map((item) => item.id),
      );

      final allIds = <String?>[
        ...data.suppliers.map((item) => item.id),
        ...data.products.map((item) => item.id),
        ...data.productBatches.map((item) => item.id),
        ...data.purchaseOrders.map((item) => item.id),
        ...data.stockMovements.map((item) => item.id),
        ...data.priceHistory.map((item) => item.id),
        ...data.scanEvents.map((item) => item.id),
        ...data.customerOrders.map((item) => item.id),
        ...data.contacts.map((item) => item.id),
        ...data.contactOrganizations.map((item) => item.id),
        ...data.customerWishes.map((item) => item.id),
        ...data.customerFeedback.map((item) => item.id),
        ...data.cloudPosReceipts.map((item) => item.id),
        ...data.cloudPosDailyStats.map((item) => item.id),
        ...data.cloudCashCounts.map((item) => item.id),
        ...data.cloudCashClosings.map((item) => item.id),
      ];
      expect(allIds, everyElement(isNotNull));
      expect(allIds.cast<String>(), everyElement(startsWith('demo-')));
      expect(allIds.toSet(), hasLength(allIds.length));
    });

    test('verwendet die etablierten drei Demo-Standort-IDs', () {
      expect(LocalDemoInventoryData.siteIdsForOrg(orgId), [
        LocalDemoData.tabakSiteId(orgId),
        LocalDemoData.strichmaennchenSiteId(orgId),
        LocalDemoData.paketshopSiteId(orgId),
      ]);
    });
  });
}
