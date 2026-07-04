import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// **Passwortmanager §8.3 — Kategorie eines Eintrags.** `.value` ist der
/// serialisierte snake_case-String (muss mit `firestore.rules` + Callables
/// übereinstimmen); `fromValue` hat einen Default-Branch (wirft nie).
enum PasswordCategory {
  kvg,
  lotto,
  post,
  supplierPortal,
  internalSystem,
  authorityPortal,
  other,
}

extension PasswordCategoryX on PasswordCategory {
  String get value => switch (this) {
        PasswordCategory.kvg => 'kvg',
        PasswordCategory.lotto => 'lotto',
        PasswordCategory.post => 'post',
        PasswordCategory.supplierPortal => 'supplier_portal',
        PasswordCategory.internalSystem => 'internal_system',
        PasswordCategory.authorityPortal => 'authority_portal',
        PasswordCategory.other => 'other',
      };

  String get label => switch (this) {
        PasswordCategory.kvg => 'KVG',
        PasswordCategory.lotto => 'Lotto',
        PasswordCategory.post => 'Post',
        PasswordCategory.supplierPortal => 'Lieferantenportal',
        PasswordCategory.internalSystem => 'Internes System',
        PasswordCategory.authorityPortal => 'Behördenportal',
        PasswordCategory.other => 'Sonstige',
      };

  static PasswordCategory fromValue(String? value) => switch (value) {
        'kvg' => PasswordCategory.kvg,
        'lotto' => PasswordCategory.lotto,
        'post' => PasswordCategory.post,
        'supplier_portal' => PasswordCategory.supplierPortal,
        'internal_system' => PasswordCategory.internalSystem,
        'authority_portal' => PasswordCategory.authorityPortal,
        _ => PasswordCategory.other,
      };
}

/// **Passwortmanager §8.3 — Sichtbarkeits-Scope.** `personal` = nur Owner (+
/// Admin); `shared` = zentral, Zielgruppe über die audience-Felder.
enum PasswordScope { personal, shared }

extension PasswordScopeX on PasswordScope {
  String get value => switch (this) {
        PasswordScope.personal => 'personal',
        PasswordScope.shared => 'shared',
      };

  String get label => switch (this) {
        PasswordScope.personal => 'Eigenes Passwort',
        PasswordScope.shared => 'Zentral / freigegeben',
      };

  static PasswordScope fromValue(String? value) => switch (value) {
        'shared' => PasswordScope.shared,
        _ => PasswordScope.personal,
      };
}

/// Entschlüsseltes Secret (Ergebnis von `revealPasswordSecret`). Existiert nur
/// transient — wird NIE persistiert oder im Provider-State gehalten.
class PasswordSecret {
  const PasswordSecret({
    this.username = '',
    this.password = '',
    this.notes = '',
  });

  final String username;
  final String password;
  final String notes;
}

/// **Passwortmanager §8.1 — Metadaten eines Eintrags** (client-lesbar über den
/// `listPasswordEntries`-Callable). Enthält bewusst KEINE Sensitiva:
/// Benutzername, Passwort, Notizen, `keyVersion`, `strengthMeta` liegen
/// ausschließlich verschlüsselt im client-unlesbaren `passwordSecrets`-Doc.
///
/// Zwei-Serialisierungs-Regel: camelCase (`toFirestoreMap`/`fromFirestore`)
/// für Firestore, snake_case (`toMap`/`fromMap`) für Callable-Payloads.
class PasswordEntry {
  const PasswordEntry({
    this.id,
    required this.orgId,
    required this.title,
    this.category = PasswordCategory.other,
    this.siteId,
    this.siteName,
    required this.ownerUid,
    this.ownerLabel = '',
    this.scope = PasswordScope.personal,
    this.audienceUids = const [],
    this.audienceRoles = const [],
    this.audienceSiteIds = const [],
    this.url,
    this.hasSecret = false,
    this.createdAt,
    this.createdByUid = '',
    this.updatedAt,
    this.updatedByUid = '',
    this.lastRotatedAt,
  });

  final String? id;
  final String orgId;
  final String title;
  final PasswordCategory category;
  final String? siteId;
  final String? siteName;

  /// uid des Erstellers/Besitzers.
  final String ownerUid;
  final String ownerLabel;

  final PasswordScope scope;

  /// Zielgruppe bei [PasswordScope.shared]: freigegebene Mitarbeiter (uids),
  /// Rollen (`.value`-Strings) und Filialen. `audienceUids` wird serverseitig
  /// zusätzlich aus `audienceSiteIds` materialisiert (Query-Optimierung).
  final List<String> audienceUids;
  final List<String> audienceRoles;
  final List<String> audienceSiteIds;

  final String? url;

  /// Ob ein verschlüsseltes Secret hinterlegt ist (server-gesetzt).
  final bool hasSecret;

  final DateTime? createdAt;
  final String createdByUid;
  final DateTime? updatedAt;
  final String updatedByUid;

  /// Zeitpunkt des letzten Passwortwechsels (für „alt"-Hinweis).
  final DateTime? lastRotatedAt;

  static List<String> _readStringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).toList(growable: false);
  }

  factory PasswordEntry.fromFirestore(String id, Map<String, dynamic> map) {
    return PasswordEntry(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      category: PasswordCategoryX.fromValue(map['category']?.toString()),
      siteId: map['siteId']?.toString(),
      siteName: map['siteName']?.toString(),
      ownerUid: (map['ownerUid'] ?? '').toString(),
      ownerLabel: (map['ownerLabel'] ?? '').toString(),
      scope: PasswordScopeX.fromValue(map['scope']?.toString()),
      audienceUids: _readStringList(map['audienceUids']),
      audienceRoles: _readStringList(map['audienceRoles']),
      audienceSiteIds: _readStringList(map['audienceSiteIds']),
      url: map['url']?.toString(),
      hasSecret: parse.toBool(map['hasSecret']) ?? false,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      createdByUid: (map['createdByUid'] ?? '').toString(),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
      updatedByUid: (map['updatedByUid'] ?? '').toString(),
      lastRotatedAt: FirestoreDateParser.readDate(map['lastRotatedAt']),
    );
  }

  factory PasswordEntry.fromMap(Map<String, dynamic> map) {
    return PasswordEntry(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      category: PasswordCategoryX.fromValue(map['category']?.toString()),
      siteId: map['site_id']?.toString(),
      siteName: map['site_name']?.toString(),
      ownerUid: (map['owner_uid'] ?? '').toString(),
      ownerLabel: (map['owner_label'] ?? '').toString(),
      scope: PasswordScopeX.fromValue(map['scope']?.toString()),
      audienceUids: _readStringList(map['audience_uids']),
      audienceRoles: _readStringList(map['audience_roles']),
      audienceSiteIds: _readStringList(map['audience_site_ids']),
      url: map['url']?.toString(),
      hasSecret: parse.toBool(map['has_secret']) ?? false,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      createdByUid: (map['created_by_uid'] ?? '').toString(),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
      updatedByUid: (map['updated_by_uid'] ?? '').toString(),
      lastRotatedAt: FirestoreDateParser.readLocalDate(map['last_rotated_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() => {
        'orgId': orgId,
        'title': title,
        'category': category.value,
        'siteId': siteId,
        'siteName': siteName,
        'ownerUid': ownerUid,
        'ownerLabel': ownerLabel,
        'scope': scope.value,
        'audienceUids': audienceUids,
        'audienceRoles': audienceRoles,
        'audienceSiteIds': audienceSiteIds,
        'url': url,
        'hasSecret': hasSecret,
        'createdAt': createdAt == null
            ? FieldValue.serverTimestamp()
            : Timestamp.fromDate(createdAt!),
        'createdByUid': createdByUid,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedByUid': updatedByUid,
        'lastRotatedAt':
            lastRotatedAt == null ? null : Timestamp.fromDate(lastRotatedAt!),
      };

  Map<String, dynamic> toMap() => {
        'id': id,
        'org_id': orgId,
        'title': title,
        'category': category.value,
        'site_id': siteId,
        'site_name': siteName,
        'owner_uid': ownerUid,
        'owner_label': ownerLabel,
        'scope': scope.value,
        'audience_uids': audienceUids,
        'audience_roles': audienceRoles,
        'audience_site_ids': audienceSiteIds,
        'url': url,
        'has_secret': hasSecret,
        'created_at': createdAt?.toIso8601String(),
        'created_by_uid': createdByUid,
        'updated_at': updatedAt?.toIso8601String(),
        'updated_by_uid': updatedByUid,
        'last_rotated_at': lastRotatedAt?.toIso8601String(),
      };

  PasswordEntry copyWith({
    String? id,
    String? orgId,
    String? title,
    PasswordCategory? category,
    String? siteId,
    String? siteName,
    String? ownerUid,
    String? ownerLabel,
    PasswordScope? scope,
    List<String>? audienceUids,
    List<String>? audienceRoles,
    List<String>? audienceSiteIds,
    String? url,
    bool? hasSecret,
    DateTime? createdAt,
    String? createdByUid,
    DateTime? updatedAt,
    String? updatedByUid,
    DateTime? lastRotatedAt,
    bool clearSiteId = false,
    bool clearSiteName = false,
    bool clearUrl = false,
    bool clearLastRotatedAt = false,
  }) {
    return PasswordEntry(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      title: title ?? this.title,
      category: category ?? this.category,
      siteId: clearSiteId ? null : (siteId ?? this.siteId),
      siteName: clearSiteName ? null : (siteName ?? this.siteName),
      ownerUid: ownerUid ?? this.ownerUid,
      ownerLabel: ownerLabel ?? this.ownerLabel,
      scope: scope ?? this.scope,
      audienceUids: audienceUids ?? this.audienceUids,
      audienceRoles: audienceRoles ?? this.audienceRoles,
      audienceSiteIds: audienceSiteIds ?? this.audienceSiteIds,
      url: clearUrl ? null : (url ?? this.url),
      hasSecret: hasSecret ?? this.hasSecret,
      createdAt: createdAt ?? this.createdAt,
      createdByUid: createdByUid ?? this.createdByUid,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedByUid: updatedByUid ?? this.updatedByUid,
      lastRotatedAt:
          clearLastRotatedAt ? null : (lastRotatedAt ?? this.lastRotatedAt),
    );
  }
}
