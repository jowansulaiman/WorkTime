import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/contact_organization.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/contact_provider.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

const _user = AppUserProfile(
  uid: 'owner-1',
  orgId: 'org-1',
  email: 'owner@laden.test',
  role: UserRole.admin,
  isActive: true,
  settings: UserSettings(name: 'Inhaber'),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  group('ContactOrganization Zwei-Serialisierung', () {
    const org = ContactOrganization(
      id: 'o-1',
      orgId: 'org-1',
      name: 'Agentur für Arbeit Kiel',
      type: OrganizationType.agenturFuerArbeit,
      city: 'Kiel',
      website: 'https://arbeitsagentur.de',
      isActive: false,
    );

    test('snake_case (local) round-trip', () {
      final o = ContactOrganization.fromMap(org.toMap());
      expect(o.name, 'Agentur für Arbeit Kiel');
      expect(o.type, OrganizationType.agenturFuerArbeit);
      expect(o.city, 'Kiel');
      expect(o.website, 'https://arbeitsagentur.de');
      expect(o.isActive, isFalse);
    });

    test('camelCase (Firestore) round-trip', () {
      final o = ContactOrganization.fromFirestore('o-1', org.toFirestoreMap());
      expect(o.type, OrganizationType.agenturFuerArbeit);
      expect(o.city, 'Kiel');
      expect(o.isActive, isFalse);
    });

    test('fromValue faellt auf sonstige', () {
      expect(OrganizationTypeX.fromValue('quatsch'), OrganizationType.sonstige);
    });
  });

  test('ContactProvider: Organisation lokal anlegen + löschen', () async {
    final firestore = FakeFirebaseFirestore();
    final provider = ContactProvider(
      firestoreService: FirestoreService(firestore: firestore),
      disableAuthentication: true,
    );
    addTearDown(provider.dispose);

    await provider.updateSession(_user);
    expect(provider.organizations, isEmpty);

    await provider.saveOrganization(const ContactOrganization(
      orgId: 'org-1',
      name: 'Jobcenter Kiel',
      type: OrganizationType.jobcenter,
    ));
    expect(provider.organizations, hasLength(1));
    final saved = provider.organizations.first;
    expect(saved.name, 'Jobcenter Kiel');
    expect(saved.id, isNotNull);

    await provider.deleteOrganization(saved.id!);
    expect(provider.organizations, isEmpty);
  });
}
