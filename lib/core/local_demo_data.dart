import '../models/app_user.dart';
import '../models/contact.dart';
import '../models/customer_order.dart';
import '../models/employee_site_assignment.dart';
import '../models/product.dart';
import '../models/site_definition.dart';
import '../models/supplier.dart';
import '../models/user_settings.dart';

class LocalDemoAccount {
  const LocalDemoAccount({
    required this.uid,
    required this.email,
    required this.password,
    required this.name,
    required this.role,
    required this.description,
  });

  final String uid;
  final String email;
  final String password;
  final String name;
  final UserRole role;
  final String description;

  AppUserProfile toProfile({required String orgId}) {
    return AppUserProfile(
      uid: uid,
      orgId: orgId,
      email: email,
      role: role,
      isActive: true,
      settings: UserSettings(
        name: name,
        hourlyRate: role == UserRole.employee ? 16.5 : 0,
        dailyHours: 8,
        currency: 'EUR',
        vacationDays: 30,
      ),
    );
  }
}

class LocalDemoData {
  LocalDemoData._();

  static const LocalDemoAccount adminAccount = LocalDemoAccount(
    uid: 'local-demo-admin',
    email: 'admin@demo.local',
    password: 'demo1234',
    name: 'Lokaler Admin',
    role: UserRole.admin,
    description: 'Voller Zugriff auf Teamverwaltung, Planung und Auswertungen.',
  );

  static const LocalDemoAccount employeeAccount = LocalDemoAccount(
    uid: 'local-test-peter',
    email: 'peter@example.com',
    password: 'demo1234',
    name: 'Peter',
    role: UserRole.employee,
    description:
        'Mitarbeiterprofil fuer Zeiterfassung, Schichten und Abwesenheiten.',
  );

  static const LocalDemoAccount employeeSecondAccount = LocalDemoAccount(
    uid: 'local-test-maria',
    email: 'maria@example.com',
    password: 'demo1234',
    name: 'Maria',
    role: UserRole.employee,
    description:
        'Zweites Mitarbeiterprofil fuer Tests mit mehreren Mitarbeitern.',
  );

  static const LocalDemoAccount teamLeadAccount = LocalDemoAccount(
    uid: 'local-test-lea',
    email: 'lea.teamlead@example.com',
    password: 'demo1234',
    name: 'Lea',
    role: UserRole.teamlead,
    description:
        'Teamleiterprofil mit Zugriff auf Planung, Freigaben und Teamansichten.',
  );

  static const List<LocalDemoAccount> accounts = [
    adminAccount,
    employeeAccount,
    employeeSecondAccount,
    teamLeadAccount,
  ];

  static LocalDemoAccount? accountForUid(String? uid) {
    if (uid == null || uid.trim().isEmpty) {
      return null;
    }
    final normalizedUid = uid.trim();
    for (final account in accounts) {
      if (account.uid == normalizedUid) {
        return account;
      }
    }
    return null;
  }

  static LocalDemoAccount? accountForEmail(String email) {
    final normalizedEmail = email.trim().toLowerCase();
    for (final account in accounts) {
      if (account.email.toLowerCase() == normalizedEmail) {
        return account;
      }
    }
    return null;
  }

  static AppUserProfile? profileForUid(
    String? uid, {
    required String orgId,
  }) {
    final account = accountForUid(uid);
    return account?.toProfile(orgId: orgId);
  }

  static AppUserProfile? authenticate({
    required String email,
    required String password,
    required String orgId,
  }) {
    final account = accountForEmail(email);
    if (account == null || account.password != password.trim()) {
      return null;
    }
    return account.toProfile(orgId: orgId);
  }

  static bool isDemoUser(AppUserProfile? profile) {
    if (profile == null) {
      return false;
    }
    return accountForUid(profile.uid) != null ||
        accountForEmail(profile.email) != null;
  }

  static List<AppUserProfile> profilesForOrg(String orgId) {
    return accounts
        .map((account) => account.toProfile(orgId: orgId))
        .toList(growable: false);
  }

  static List<SiteDefinition> sitesForOrg({
    required String orgId,
    required String createdByUid,
  }) {
    return [
      SiteDefinition(
        id: 'demo-site-$orgId-berlin',
        orgId: orgId,
        name: 'Hauptstandort Berlin',
        code: 'BER-HQ',
        street: 'Invalidenstrasse 117',
        postalCode: '10115',
        city: 'Berlin',
        federalState: 'Berlin',
        countryCode: SiteDefinition.germanyCountryCode,
        latitude: 52.5321,
        longitude: 13.3849,
        description: 'Dummy-Standort fuer Tests im lokalen Modus.',
        createdByUid: createdByUid,
      ),
      SiteDefinition(
        id: 'demo-site-$orgId-hamburg',
        orgId: orgId,
        name: 'Filiale Hamburg',
        code: 'HAM',
        street: 'Spitalerstrasse 22',
        postalCode: '20095',
        city: 'Hamburg',
        federalState: 'Hamburg',
        countryCode: SiteDefinition.germanyCountryCode,
        latitude: 53.5511,
        longitude: 9.9937,
        description: 'Zweiter Dummy-Standort fuer Schicht- und Standorttests.',
        createdByUid: createdByUid,
      ),
    ];
  }

  static String berlinSiteId(String orgId) => 'demo-site-$orgId-berlin';
  static String hamburgSiteId(String orgId) => 'demo-site-$orgId-hamburg';

  /// Demo-Lieferanten fuer den lokalen Modus (Warenwirtschaft).
  static List<Supplier> suppliersForOrg({
    required String orgId,
    required String createdByUid,
  }) {
    return [
      Supplier(
        id: 'demo-supplier-$orgId-tabak',
        orgId: orgId,
        name: 'Nord Tabakwaren GmbH',
        contactPerson: 'Frau Petersen',
        email: 'service@nord-tabak.de',
        orderEmail: 'bestellung@nord-tabak.de',
        phone: '0431 555100',
        customerNumber: 'KD-4711',
        leadTimeDays: 2,
        createdByUid: createdByUid,
      ),
      Supplier(
        id: 'demo-supplier-$orgId-getraenke',
        orgId: orgId,
        name: 'Getraenke Service Kiel',
        contactPerson: 'Herr Voss',
        email: 'info@getraenke-kiel.de',
        phone: '0431 555200',
        customerNumber: 'GSK-208',
        leadTimeDays: 1,
        createdByUid: createdByUid,
      ),
    ];
  }

  /// Demo-Artikel fuer den lokalen Modus. Einige liegen bewusst unter dem
  /// Mindestbestand, damit die Nachbestell-Warnung sichtbar ist.
  static List<Product> productsForOrg({
    required String orgId,
    required String createdByUid,
  }) {
    final tabakSupplier = 'demo-supplier-$orgId-tabak';
    final getraenkeSupplier = 'demo-supplier-$orgId-getraenke';
    final berlin = berlinSiteId(orgId);
    final hamburg = hamburgSiteId(orgId);
    return [
      Product(
        id: 'demo-product-$orgId-1',
        orgId: orgId,
        siteId: berlin,
        siteName: 'Hauptstandort Berlin',
        name: 'Marlboro Rot (Stange)',
        category: 'Zigaretten',
        unit: 'Stange',
        barcode: '4033100112233',
        supplierId: tabakSupplier,
        supplierName: 'Nord Tabakwaren GmbH',
        purchasePriceCents: 7800,
        sellingPriceCents: 8500,
        currentStock: 4,
        minStock: 6,
        reorderQuantity: 10,
        createdByUid: createdByUid,
      ),
      Product(
        id: 'demo-product-$orgId-2',
        orgId: orgId,
        siteId: berlin,
        siteName: 'Hauptstandort Berlin',
        name: 'Feuerzeug Clipper',
        category: 'Raucherbedarf',
        unit: 'Stück',
        supplierId: tabakSupplier,
        supplierName: 'Nord Tabakwaren GmbH',
        purchasePriceCents: 65,
        sellingPriceCents: 150,
        currentStock: 38,
        minStock: 20,
        createdByUid: createdByUid,
      ),
      Product(
        id: 'demo-product-$orgId-3',
        orgId: orgId,
        siteId: berlin,
        siteName: 'Hauptstandort Berlin',
        name: 'Cola 0,5 l',
        category: 'Getraenke',
        unit: 'Flasche',
        supplierId: getraenkeSupplier,
        supplierName: 'Getraenke Service Kiel',
        purchasePriceCents: 60,
        sellingPriceCents: 200,
        currentStock: 9,
        minStock: 24,
        reorderQuantity: 48,
        createdByUid: createdByUid,
      ),
      Product(
        id: 'demo-product-$orgId-4',
        orgId: orgId,
        siteId: hamburg,
        siteName: 'Filiale Hamburg',
        name: 'Pueblo Tabak 30g',
        category: 'Drehtabak',
        unit: 'Beutel',
        supplierId: tabakSupplier,
        supplierName: 'Nord Tabakwaren GmbH',
        purchasePriceCents: 480,
        sellingPriceCents: 650,
        currentStock: 12,
        minStock: 8,
        createdByUid: createdByUid,
      ),
      Product(
        id: 'demo-product-$orgId-5',
        orgId: orgId,
        siteId: hamburg,
        siteName: 'Filiale Hamburg',
        name: 'Zeitschrift Der Spiegel',
        category: 'Presse',
        unit: 'Stück',
        currentStock: 3,
        minStock: 5,
        createdByUid: createdByUid,
      ),
    ];
  }

  /// Demo-Kundenbestellungen (Sonderbestellungen) fuer den lokalen Modus.
  /// Eine Bestellung liegt bewusst ueberfaellig und unvorbereitet vor, damit die
  /// "nicht vorbereitet"-Warnung (Liste, Dashboard, Benachrichtigungen) ohne
  /// Firebase sichtbar ist.
  static List<CustomerOrder> customerOrdersForOrg({
    required String orgId,
    required String createdByUid,
  }) {
    final berlin = berlinSiteId(orgId);
    final hamburg = hamburgSiteId(orgId);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 12);
    DateTime atNoon(int addDays) => today.add(Duration(days: addDays));

    return [
      // 1) Ueberfaellig + nicht vorbereitet -> Warnung.
      CustomerOrder(
        id: 'demo-customerOrder-$orgId-1',
        orgId: orgId,
        siteId: berlin,
        siteName: 'Hauptstandort Berlin',
        customerName: 'Herr Schmidt',
        customerContact: '0151 2345678',
        orderNumber: 'KB-${now.year}-0001',
        status: CustomerOrderStatus.open,
        recurrence: CustomerOrderRecurrence.weekly,
        pickupDate: atNoon(-1),
        notes: 'Holt jeden Freitag ab.',
        createdByUid: createdByUid,
        items: const [
          CustomerOrderItem(
            name: 'Pueblo Tabak 30g',
            category: 'Drehtabak',
            unit: 'Beutel',
            quantity: 5,
            unitPriceCents: 650,
          ),
          CustomerOrderItem(
            name: 'OCB Slim Blättchen',
            category: 'Raucherbedarf',
            unit: 'Heft',
            quantity: 3,
            unitPriceCents: 90,
          ),
        ],
      ),
      // 2) Bald faellig (morgen) + nicht vorbereitet -> Warnung.
      CustomerOrder(
        id: 'demo-customerOrder-$orgId-2',
        orgId: orgId,
        siteId: hamburg,
        siteName: 'Filiale Hamburg',
        customerName: 'Frau Meier',
        customerContact: 'meier@example.com',
        orderNumber: 'KB-${now.year}-0002',
        status: CustomerOrderStatus.open,
        recurrence: CustomerOrderRecurrence.monthly,
        pickupDate: atNoon(1),
        createdByUid: createdByUid,
        items: const [
          CustomerOrderItem(
            name: 'Zeitschrift Der Spiegel',
            category: 'Presse',
            unit: 'Stück',
            quantity: 1,
            unitPriceCents: 650,
          ),
        ],
      ),
      // 3) Vorbereitet, Abholung in drei Tagen -> keine Warnung.
      CustomerOrder(
        id: 'demo-customerOrder-$orgId-3',
        orgId: orgId,
        siteId: berlin,
        siteName: 'Hauptstandort Berlin',
        customerName: 'Café Sonnenschein',
        customerContact: '0431 998877',
        orderNumber: 'KB-${now.year}-0003',
        status: CustomerOrderStatus.prepared,
        recurrence: CustomerOrderRecurrence.none,
        pickupDate: atNoon(3),
        preparedAt: now,
        createdByUid: createdByUid,
        items: const [
          CustomerOrderItem(
            name: 'Marlboro Rot (Stange)',
            category: 'Zigaretten',
            unit: 'Stange',
            quantity: 2,
            unitPriceCents: 8500,
          ),
        ],
      ),
    ];
  }

  /// Demo-Kontakte fuer den lokalen Modus (Kunden, Lieferanten, Behoerden …).
  static List<Contact> contactsForOrg({
    required String orgId,
    required String createdByUid,
  }) {
    final berlin = berlinSiteId(orgId);
    final hamburg = hamburgSiteId(orgId);
    return [
      Contact(
        id: 'demo-contact-$orgId-nordtabak',
        orgId: orgId,
        name: 'Nord-Tabak Großhandel GmbH',
        type: ContactType.wholesaler,
        contactPerson: 'Frau Petersen',
        email: 'service@nord-tabak.de',
        phone: '0431 1234560',
        website: 'https://nord-tabak.de',
        street: 'Eichhofstraße 12',
        postalCode: '24116',
        city: 'Kiel',
        customerNumber: 'KD-44213',
        notes: 'Hauptlieferant Tabakwaren, Lieferung Di + Fr.',
        tags: const ['Tabak', 'Stammlieferant'],
        isFavorite: true,
        createdByUid: createdByUid,
      ),
      Contact(
        id: 'demo-contact-$orgId-presse',
        orgId: orgId,
        name: 'Kieler Pressevertrieb',
        type: ContactType.supplier,
        contactPerson: 'Herr Brandt',
        email: 'bestellung@kn-pressevertrieb.de',
        phone: '0431 9988770',
        street: 'Fleethörn 1',
        postalCode: '24103',
        city: 'Kiel',
        notes: 'Zeitschriften & Zeitungen, Remission montags.',
        tags: const ['Presse'],
        createdByUid: createdByUid,
      ),
      Contact(
        id: 'demo-contact-$orgId-getraenke',
        orgId: orgId,
        name: 'Förde Getränke Service',
        type: ContactType.serviceProvider,
        contactPerson: 'Frau Johannsen',
        email: 'info@foerde-getraenke.de',
        phone: '0431 556677',
        mobile: '0170 5566778',
        city: 'Kiel',
        siteId: hamburg,
        siteName: 'Filiale Hamburg',
        notes: 'Kühlgeräte-Wartung und Getränkebelieferung.',
        createdByUid: createdByUid,
      ),
      Contact(
        id: 'demo-contact-$orgId-zoll',
        orgId: orgId,
        name: 'Hauptzollamt Kiel',
        type: ContactType.authority,
        email: 'poststelle.hza-kiel@zoll.bund.de',
        phone: '0431 200840',
        street: 'Am Sophienhof 11',
        postalCode: '24114',
        city: 'Kiel',
        notes: 'Tabaksteuer / Steuerzeichen.',
        tags: const ['Tabaksteuer'],
        createdByUid: createdByUid,
      ),
      Contact(
        id: 'demo-contact-$orgId-steuer',
        orgId: orgId,
        name: 'Steuerkanzlei Albrecht & Partner',
        type: ContactType.taxAdvisor,
        contactPerson: 'Herr Albrecht',
        email: 'kanzlei@albrecht-stb.de',
        phone: '0431 778899',
        street: 'Holtenauer Straße 88',
        postalCode: '24105',
        city: 'Kiel',
        isFavorite: true,
        createdByUid: createdByUid,
      ),
      Contact(
        id: 'demo-contact-$orgId-vermieter',
        orgId: orgId,
        name: 'Hausverwaltung Möller',
        type: ContactType.landlord,
        contactPerson: 'Frau Möller',
        email: 'verwaltung@moeller-immobilien.de',
        phone: '0431 445566',
        siteId: berlin,
        siteName: 'Hauptstandort Berlin',
        notes: 'Mietobjekt Ladenfläche, Nebenkosten jährlich.',
        createdByUid: createdByUid,
      ),
      Contact(
        id: 'demo-contact-$orgId-stammkunde',
        orgId: orgId,
        name: 'Jörg Hansen',
        type: ContactType.customer,
        mobile: '0151 23456789',
        notes: 'Stammkunde, Sonderbestellungen Zigarren.',
        tags: const ['Stammkunde', 'Zigarren'],
        createdByUid: createdByUid,
      ),
    ];
  }

  static List<EmployeeSiteAssignment> siteAssignmentsForOrg({
    required String orgId,
    required String createdByUid,
  }) {
    return [
      EmployeeSiteAssignment(
        id: 'demo-assignment-$orgId-admin',
        orgId: orgId,
        userId: adminAccount.uid,
        siteId: 'demo-site-$orgId-berlin',
        siteName: 'Hauptstandort Berlin',
        isPrimary: true,
        createdByUid: createdByUid,
      ),
      EmployeeSiteAssignment(
        id: 'demo-assignment-$orgId-peter',
        orgId: orgId,
        userId: employeeAccount.uid,
        siteId: 'demo-site-$orgId-hamburg',
        siteName: 'Filiale Hamburg',
        isPrimary: true,
        createdByUid: createdByUid,
      ),
      EmployeeSiteAssignment(
        id: 'demo-assignment-$orgId-maria',
        orgId: orgId,
        userId: employeeSecondAccount.uid,
        siteId: 'demo-site-$orgId-berlin',
        siteName: 'Hauptstandort Berlin',
        isPrimary: true,
        createdByUid: createdByUid,
      ),
      EmployeeSiteAssignment(
        id: 'demo-assignment-$orgId-lea',
        orgId: orgId,
        userId: teamLeadAccount.uid,
        siteId: 'demo-site-$orgId-hamburg',
        siteName: 'Filiale Hamburg',
        isPrimary: true,
        createdByUid: createdByUid,
      ),
    ];
  }
}
