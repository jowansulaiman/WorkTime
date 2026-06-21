import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/audit_log_entry.dart';

void main() {
  group('AuditLogEntry', () {
    test('AuditAction value/label/fromValue', () {
      expect(AuditAction.created.value, 'created');
      expect(AuditAction.deleted.label, 'Gelöscht');
      expect(AuditActionX.fromValue('updated'), AuditAction.updated);
      expect(AuditActionX.fromValue('unbekannt'), AuditAction.updated);
    });

    test('snake_case Round-Trip (lokal)', () {
      final entry = AuditLogEntry(
        id: 'a1',
        orgId: 'org-1',
        action: AuditAction.deleted,
        entityType: 'Kontakt',
        entityId: 'c-9',
        summary: 'Kontakt „Hansen" gelöscht.',
        actorUid: 'u1',
        actorName: 'Inhaber',
        createdAt: DateTime(2026, 6, 21, 10, 30),
      );
      final restored = AuditLogEntry.fromMap(entry.toMap());
      expect(restored.action, AuditAction.deleted);
      expect(restored.entityType, 'Kontakt');
      expect(restored.entityId, 'c-9');
      expect(restored.summary, contains('gelöscht'));
      expect(restored.actorName, 'Inhaber');
      expect(restored.createdAt, DateTime(2026, 6, 21, 10, 30));
    });

    test('camelCase fromFirestore (ID separat)', () {
      const entry = AuditLogEntry(
        orgId: 'org-1',
        action: AuditAction.created,
        entityType: 'Lohnabrechnung',
        summary: 'Peter Juni: Brutto 3.000 €',
        actorUid: 'u1',
      );
      final map = entry.toFirestoreMap()..remove('createdAt');
      final restored = AuditLogEntry.fromFirestore('x1', map);
      expect(restored.id, 'x1');
      expect(restored.action, AuditAction.created);
      expect(restored.entityType, 'Lohnabrechnung');
    });
  });
}
