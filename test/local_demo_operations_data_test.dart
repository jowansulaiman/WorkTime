import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/local_demo_data.dart';
import 'package:worktime_app/core/local_demo_operations_data.dart';
import 'package:worktime_app/models/audit_log_entry.dart';
import 'package:worktime_app/models/clock_entry.dart';
import 'package:worktime_app/models/signage_display.dart';
import 'package:worktime_app/models/work_entry.dart';

void main() {
  const orgId = 'demo-org-test';
  final now = DateTime(2026, 7, 13, 12);

  test('operative Demo-Daten decken alle Zeit- und Auditstatus ab', () {
    final work = LocalDemoOperationsData.workEntriesForOrg(
      orgId: orgId,
      now: now,
    );
    final clocks = LocalDemoOperationsData.clockEntriesForOrg(
      orgId: orgId,
      now: now,
    );
    final audit = LocalDemoOperationsData.auditEntriesForOrg(
      orgId: orgId,
      now: now,
    );

    expect(
      work.map((entry) => entry.status).toSet(),
      WorkEntryStatus.values.toSet(),
    );
    expect(
      clocks.map((entry) => entry.status).toSet(),
      ClockStatus.values.toSet(),
    );
    expect(
      audit.map((entry) => entry.action).toSet(),
      AuditAction.values.toSet(),
    );
    expect(
      clocks.where((entry) => entry.status == ClockStatus.ongoing),
      hasLength(1),
    );
  });

  test(
    'jeder Demo-Login hat Arbeitszeiten und Vorlagen im aktuellen Monat',
    () {
      final entries = LocalDemoOperationsData.workEntriesForOrg(
        orgId: orgId,
        now: now,
      );
      final templates = LocalDemoOperationsData.workTemplatesForOrg(orgId);

      for (final account in LocalDemoData.accounts) {
        expect(
          entries.where((entry) => entry.userId == account.uid),
          hasLength(WorkEntryStatus.values.length),
        );
        expect(
          entries
              .where((entry) => entry.userId == account.uid)
              .every(
                (entry) =>
                    entry.date.year == now.year &&
                    entry.date.month == now.month,
              ),
          isTrue,
        );
        expect(
          templates.where((template) => template.userId == account.uid),
          hasLength(2),
        );
      }
    },
  );

  test(
    'Ladenaufgaben und Signage enthalten offene, erledigte und pausierte Faelle',
    () {
      final tasks = LocalDemoOperationsData.storeTasksForOrg(
        orgId: orgId,
        createdByUid: LocalDemoData.adminAccount.uid,
        now: now,
      );
      final displays = LocalDemoOperationsData.signageDisplaysForOrg(
        orgId: orgId,
        createdByUid: LocalDemoData.adminAccount.uid,
        now: now,
      );

      expect(tasks.any((task) => task.completedBySite.isNotEmpty), isTrue);
      expect(tasks.any((task) => task.completedBySite.isEmpty), isTrue);
      expect(tasks.any((task) => task.siteId == null), isTrue);
      expect(displays.any((display) => display.isActive), isTrue);
      expect(displays.any((display) => !display.isActive), isTrue);
      expect(displays.any((display) => display.mediaIds.length > 1), isTrue);
      expect(displays.any((display) => display.mediaIds.isEmpty), isTrue);
      expect(
        displays.map((display) => display.transition).toSet(),
        SignageTransition.values.toSet(),
      );
    },
  );

  test('stabile IDs machen die Fabriken reproduzierbar', () {
    final first = LocalDemoOperationsData.workEntriesForOrg(
      orgId: orgId,
      now: now,
    );
    final second = LocalDemoOperationsData.workEntriesForOrg(
      orgId: orgId,
      now: now,
    );

    expect(first.map((entry) => entry.id), second.map((entry) => entry.id));
  });

  test('oeffentliche Display-Projektion loest Playlist-Medien auf', () {
    final data = LocalDemoOperationsData.publicDisplayDataForToken(
      orgId: orgId,
      token: 'demo-$orgId-tabak-display-token',
      now: now,
    );

    expect(data, isNotNull);
    expect(data!.slides, hasLength(2));
    expect(
      data.slides.every((slide) => slide.url.startsWith('https://')),
      isTrue,
    );
    expect(
      LocalDemoOperationsData.publicDisplayDataForToken(
        orgId: orgId,
        token: 'unbekannt',
        now: now,
      ),
      isNull,
    );
  });
}
