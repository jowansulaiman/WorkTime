import '../models/ad_media.dart';
import '../models/audit_log_entry.dart';
import '../models/clock_entry.dart';
import '../models/signage_display.dart';
import '../models/store_task.dart';
import '../models/work_entry.dart';
import '../models/work_task.dart';
import '../models/work_template.dart';
import '../models/zeitkonto_snapshot.dart';
import 'local_demo_data.dart';

/// Reproduzierbare Beispieldaten fuer die operativen Bereiche des lokalen
/// Demo-Modus. Alle IDs sind stabil, damit ein erneuter Start keine Duplikate
/// erzeugt. Datumswerte werden relativ zum aktuellen Monat erzeugt, damit die
/// Standardfilter der Oberflaeche die Datensaetze sofort anzeigen.
class LocalDemoOperationsData {
  LocalDemoOperationsData._();

  static DateTime _monthDay(DateTime now, int day, [int hour = 12]) =>
      DateTime(now.year, now.month, day, hour);

  static List<WorkEntry> workEntriesForOrg({
    required String orgId,
    DateTime? now,
  }) {
    final anchor = now ?? DateTime.now();
    final siteId = LocalDemoData.tabakSiteId(orgId);
    const siteName = 'Tabak Börse';
    const statuses = WorkEntryStatus.values;
    final result = <WorkEntry>[];

    for (
      var userIndex = 0;
      userIndex < LocalDemoData.accounts.length;
      userIndex++
    ) {
      final account = LocalDemoData.accounts[userIndex];
      for (var statusIndex = 0; statusIndex < statuses.length; statusIndex++) {
        final day = 2 + statusIndex;
        final start = _monthDay(anchor, day, 8 + (userIndex % 2));
        final status = statuses[statusIndex];
        result.add(
          WorkEntry(
            id: 'demo-work-$orgId-${account.uid}-${status.value}',
            orgId: orgId,
            userId: account.uid,
            date: start,
            startTime: start,
            endTime: start.add(
              Duration(hours: status == WorkEntryStatus.rejected ? 5 : 8),
            ),
            breakMinutes: status == WorkEntryStatus.rejected ? 15 : 30,
            siteId: siteId,
            siteName: siteName,
            note: switch (status) {
              WorkEntryStatus.draft => 'Noch zu prüfende manuelle Erfassung',
              WorkEntryStatus.submitted => 'Aus Stempelung eingereicht',
              WorkEntryStatus.approved => 'Regulärer Arbeitstag',
              WorkEntryStatus.rejected => 'Testfall: Zeitangabe unplausibel',
            },
            category:
                status == WorkEntryStatus.rejected
                    ? 'Korrekturfall'
                    : 'Verkauf',
            status: status,
            approvedByUid:
                status == WorkEntryStatus.approved ||
                        status == WorkEntryStatus.rejected
                    ? LocalDemoData.adminAccount.uid
                    : null,
            approvedAt:
                status == WorkEntryStatus.approved ||
                        status == WorkEntryStatus.rejected
                    ? start.add(const Duration(days: 1))
                    : null,
            correctionReason:
                status == WorkEntryStatus.rejected
                    ? 'Endzeit muss mit Stempelung abgeglichen werden.'
                    : null,
            correctedByUid:
                status == WorkEntryStatus.rejected
                    ? LocalDemoData.adminAccount.uid
                    : null,
            correctedAt:
                status == WorkEntryStatus.rejected
                    ? start.add(const Duration(days: 1))
                    : null,
            updatedAt: start.add(const Duration(hours: 9)),
          ),
        );
      }
    }
    return result;
  }

  static List<WorkTemplate> workTemplatesForOrg(String orgId) => [
    for (final account in LocalDemoData.accounts) ...[
      WorkTemplate(
        id: 'demo-work-template-$orgId-${account.uid}-frueh',
        orgId: orgId,
        userId: account.uid,
        name: 'Frühdienst',
        startMinutes: 7 * 60,
        endMinutes: 15 * 60,
        breakMinutes: 30,
        note: 'Standardvorlage mit Pause',
      ),
      WorkTemplate(
        id: 'demo-work-template-$orgId-${account.uid}-spaet',
        orgId: orgId,
        userId: account.uid,
        name: 'Spätdienst',
        startMinutes: 11 * 60,
        endMinutes: 19 * 60,
        breakMinutes: 30,
      ),
    ],
  ];

  static List<ClockEntry> clockEntriesForOrg({
    required String orgId,
    DateTime? now,
  }) {
    final anchor = now ?? DateTime.now();
    final siteId = LocalDemoData.tabakSiteId(orgId);
    const siteName = 'Tabak Börse';
    final result = <ClockEntry>[];

    for (final account in LocalDemoData.accounts) {
      final completedStart = _monthDay(anchor, 6, 8);
      result.addAll([
        ClockEntry(
          id: 'demo-clock-$orgId-${account.uid}-completed',
          orgId: orgId,
          userId: account.uid,
          userName: account.name,
          siteId: siteId,
          siteName: siteName,
          kommen: completedStart,
          gehen: completedStart.add(const Duration(hours: 8, minutes: 30)),
          pauseMinuten: 30,
          nettoMinutes: 480,
          status: ClockStatus.completed,
          shiftId: 'demo-shift-$orgId-${account.uid}-completed',
          source: 'app',
          workEntryId: 'demo-work-$orgId-${account.uid}-approved',
          createdByUid: account.uid,
          createdAt: completedStart,
          updatedAt: completedStart.add(const Duration(hours: 9)),
        ),
        ClockEntry(
          id: 'demo-clock-$orgId-${account.uid}-klaerung',
          orgId: orgId,
          userId: account.uid,
          userName: account.name,
          siteId: siteId,
          siteName: siteName,
          kommen: _monthDay(anchor, 7, 6),
          gehen: _monthDay(anchor, 7, 20),
          pauseMinuten: 0,
          nettoMinutes: 840,
          status: ClockStatus.klaerung,
          manuellErfasst: true,
          klaerung: true,
          anmerkung: 'Testfall: sehr lange Buchung ohne Pause',
          source: 'kiosk',
          deviceId: 'demo-kiosk-tabak',
          sessionId: 'demo-session-$orgId',
          createdByUid: account.uid,
          createdAt: _monthDay(anchor, 7, 6),
          updatedAt: _monthDay(anchor, 7, 20),
        ),
        ClockEntry(
          id: 'demo-clock-$orgId-${account.uid}-deaktiviert',
          orgId: orgId,
          userId: account.uid,
          userName: account.name,
          siteId: siteId,
          siteName: siteName,
          kommen: _monthDay(anchor, 8, 9),
          gehen: _monthDay(anchor, 8, 9).add(const Duration(minutes: 5)),
          status: ClockStatus.deaktiviert,
          manuellErfasst: true,
          anmerkung: 'Versehentliche Doppelstempelung',
          korrigiertVonUid: LocalDemoData.adminAccount.uid,
          korrekturGrund: 'Doppelte Buchung deaktiviert',
          createdByUid: account.uid,
          createdAt: _monthDay(anchor, 8, 9),
          updatedAt: _monthDay(anchor, 8, 10),
        ),
      ]);
    }

    // Nur Peter startet mit einer offenen Stempelung. So kann der typische
    // Kommen-/Gehen-Fall getestet werden, ohne den Admin-Login zu blockieren.
    const peter = LocalDemoData.employeeAccount;
    result.add(
      ClockEntry(
        id: 'demo-clock-$orgId-${peter.uid}-ongoing',
        orgId: orgId,
        userId: peter.uid,
        userName: peter.name,
        siteId: siteId,
        siteName: siteName,
        kommen: anchor.subtract(const Duration(hours: 2)),
        status: ClockStatus.ongoing,
        source: 'app',
        createdByUid: peter.uid,
        createdAt: anchor.subtract(const Duration(hours: 2)),
        updatedAt: anchor.subtract(const Duration(hours: 2)),
      ),
    );
    return result;
  }

  static List<ZeitkontoSnapshot> zeitkontoSnapshotsForOrg({
    required String orgId,
    DateTime? now,
  }) {
    final anchor = now ?? DateTime.now();
    final result = <ZeitkontoSnapshot>[];
    for (var index = 0; index < LocalDemoData.accounts.length; index++) {
      final account = LocalDemoData.accounts[index];
      for (var offset = 1; offset <= 3; offset++) {
        final month = DateTime(anchor.year, anchor.month - offset);
        final overtime = (index.isEven ? 90 : -45) + offset * 10;
        final carry = index.isEven ? 120 : -60;
        result.add(
          ZeitkontoSnapshot(
            id: ZeitkontoSnapshot.buildId(account.uid, month.year, month.month),
            orgId: orgId,
            userId: account.uid,
            jahr: month.year,
            monat: month.month,
            sollMinutes: 9600,
            istMinutes: 9600 + overtime,
            ueberstundenMinutes: overtime,
            ausgezahltMinutes: offset == 2 && overtime > 0 ? 60 : 0,
            uebertragMinutes: carry,
            saldoMinutes:
                carry + overtime - (offset == 2 && overtime > 0 ? 60 : 0),
            geplantMinutes: 9720,
            urlaubstageGesamt: 30,
            urlaubstageGenommen: offset == 1 ? 5 : 3,
            urlaubstageRest: offset == 1 ? 25 : 27,
            kranktage: index % 4 == 0 ? 2 : 0,
            abgeschlossen: true,
            abgeschlossenVon: LocalDemoData.adminAccount.uid,
            abgeschlossenAm: DateTime(month.year, month.month + 1, 2, 10),
            createdByUid: LocalDemoData.adminAccount.uid,
            createdAt: DateTime(month.year, month.month + 1, 2, 10),
            updatedAt: DateTime(month.year, month.month + 1, 2, 10),
          ),
        );
      }
    }
    return result;
  }

  static List<StoreTask> storeTasksForOrg({
    required String orgId,
    required String createdByUid,
    DateTime? now,
  }) {
    final anchor = now ?? DateTime.now();
    final today = DateTime(anchor.year, anchor.month, anchor.day);
    final tabak = LocalDemoData.tabakSiteId(orgId);
    final strich = LocalDemoData.strichmaennchenSiteId(orgId);
    return [
      StoreTask(
        id: 'demo-store-task-$orgId-overdue',
        orgId: orgId,
        siteId: tabak,
        title: 'MHD-Regal kontrollieren',
        description: 'Alle Kühlschrank- und Snackartikel prüfen.',
        dueDate: today.subtract(const Duration(days: 1)),
        priority: TaskPriority.high,
        createdByUid: createdByUid,
        createdAt: today.subtract(const Duration(days: 3)),
        updatedAt: today.subtract(const Duration(days: 3)),
      ),
      StoreTask(
        id: 'demo-store-task-$orgId-broadcast',
        orgId: orgId,
        title: 'Wochenwerbung aufbauen',
        description: 'Aufsteller laut Kampagnenplan im Eingangsbereich.',
        dueDate: today,
        priority: TaskPriority.medium,
        completedBySite: {
          strich: StoreTaskCompletion(
            employeeId: LocalDemoData.employeeSecondAccount.uid,
            name: LocalDemoData.employeeSecondAccount.name,
            at: anchor.subtract(const Duration(hours: 1)),
          ),
        },
        createdByUid: createdByUid,
        createdAt: today.subtract(const Duration(days: 2)),
        updatedAt: anchor.subtract(const Duration(hours: 1)),
      ),
      StoreTask(
        id: 'demo-store-task-$orgId-low',
        orgId: orgId,
        siteId: strich,
        title: 'Preisschilder sortieren',
        description: 'Neue Schilder alphabetisch in die Ablage einsortieren.',
        priority: TaskPriority.low,
        createdByUid: createdByUid,
        createdAt: today.subtract(const Duration(days: 1)),
        updatedAt: today.subtract(const Duration(days: 1)),
      ),
    ];
  }

  static List<AdMedia> adMediaForOrg({
    required String orgId,
    required String createdByUid,
    DateTime? now,
  }) {
    final anchor = now ?? DateTime.now();
    return [
      AdMedia(
        id: 'demo-media-$orgId-sommer',
        orgId: orgId,
        title: 'Sommer-Angebot',
        storagePath: 'demo/$orgId/sommer.jpg',
        downloadUrl:
            'https://placehold.co/1920x1080/00695c/ffffff.png?text=Sommer-Angebot',
        fileSize: 245000,
        createdByUid: createdByUid,
        createdAt: anchor.subtract(const Duration(days: 14)),
      ),
      AdMedia(
        id: 'demo-media-$orgId-paket',
        orgId: orgId,
        title: 'Paketshop-Service',
        storagePath: 'demo/$orgId/paket.png',
        downloadUrl:
            'https://placehold.co/1920x1080/1565c0/ffffff.png?text=Paketshop-Service',
        contentType: 'image/png',
        fileSize: 198000,
        createdByUid: createdByUid,
        createdAt: anchor.subtract(const Duration(days: 7)),
      ),
      AdMedia(
        id: 'demo-media-$orgId-lotto',
        orgId: orgId,
        title: 'Lotto-Annahmeschluss',
        storagePath: 'demo/$orgId/lotto.jpg',
        downloadUrl:
            'https://placehold.co/1920x1080/f9a825/212121.png?text=Lotto-Annahmeschluss',
        fileSize: 225000,
        createdByUid: createdByUid,
        createdAt: anchor.subtract(const Duration(days: 2)),
      ),
      AdMedia(
        id: 'demo-media-$orgId-unbenutzt',
        orgId: orgId,
        title: 'Entwurf (noch nicht verwendet)',
        storagePath: 'demo/$orgId/entwurf.png',
        downloadUrl:
            'https://placehold.co/1920x1080/6a1b9a/ffffff.png?text=Kampagnen-Entwurf',
        contentType: 'image/png',
        fileSize: 175000,
        createdByUid: createdByUid,
        createdAt: anchor.subtract(const Duration(days: 1)),
      ),
    ];
  }

  static List<SignageDisplay> signageDisplaysForOrg({
    required String orgId,
    required String createdByUid,
    DateTime? now,
  }) {
    final anchor = now ?? DateTime.now();
    return [
      SignageDisplay(
        id: 'demo-display-$orgId-tabak',
        orgId: orgId,
        name: 'Schaufenster Tabak Börse',
        siteId: LocalDemoData.tabakSiteId(orgId),
        pairingToken: 'demo-$orgId-tabak-display-token',
        slideSeconds: 8,
        fit: SignageFit.cover,
        transition: SignageTransition.kenBurns,
        mediaIds: ['demo-media-$orgId-sommer', 'demo-media-$orgId-lotto'],
        createdByUid: createdByUid,
        createdAt: anchor.subtract(const Duration(days: 30)),
        updatedAt: anchor.subtract(const Duration(days: 1)),
      ),
      SignageDisplay(
        id: 'demo-display-$orgId-strich',
        orgId: orgId,
        name: 'Kassenmonitor Strichmännchen',
        siteId: LocalDemoData.strichmaennchenSiteId(orgId),
        pairingToken: 'demo-$orgId-strich-display-token',
        slideSeconds: 12,
        fit: SignageFit.contain,
        transition: SignageTransition.slide,
        mediaIds: ['demo-media-$orgId-paket'],
        createdByUid: createdByUid,
        createdAt: anchor.subtract(const Duration(days: 20)),
        updatedAt: anchor.subtract(const Duration(days: 2)),
      ),
      SignageDisplay(
        id: 'demo-display-$orgId-paket-inactive',
        orgId: orgId,
        name: 'Reserve-Display Paketshop',
        siteId: LocalDemoData.paketshopSiteId(orgId),
        pairingToken: 'demo-$orgId-paket-display-token',
        transition: SignageTransition.none,
        isActive: false,
        createdByUid: createdByUid,
        createdAt: anchor.subtract(const Duration(days: 10)),
        updatedAt: anchor.subtract(const Duration(days: 3)),
      ),
      SignageDisplay(
        id: 'demo-display-$orgId-fade',
        orgId: orgId,
        name: 'Übergangstest Fade',
        pairingToken: 'demo-$orgId-fade-display-token',
        transition: SignageTransition.fade,
        mediaIds: ['demo-media-$orgId-sommer'],
        createdByUid: createdByUid,
        createdAt: anchor.subtract(const Duration(days: 5)),
        updatedAt: anchor.subtract(const Duration(days: 1)),
      ),
      SignageDisplay(
        id: 'demo-display-$orgId-zoom',
        orgId: orgId,
        name: 'Übergangstest Zoom',
        pairingToken: 'demo-$orgId-zoom-display-token',
        transition: SignageTransition.zoom,
        mediaIds: ['demo-media-$orgId-lotto'],
        createdByUid: createdByUid,
        createdAt: anchor.subtract(const Duration(days: 4)),
        updatedAt: anchor.subtract(const Duration(hours: 12)),
      ),
    ];
  }

  /// Baut dieselbe denormalisierte Sicht, die im Cloud-Modus unter
  /// `publicDisplays/{token}` liegt. Damit lassen sich Pairing, aktive,
  /// pausierte und leere Player auch ohne Firebase pruefen.
  static PublicDisplayData? publicDisplayDataForToken({
    required String orgId,
    required String token,
    DateTime? now,
  }) {
    final displays = signageDisplaysForOrg(
      orgId: orgId,
      createdByUid: LocalDemoData.adminAccount.uid,
      now: now,
    );
    SignageDisplay? display;
    for (final candidate in displays) {
      if (candidate.pairingToken == token) {
        display = candidate;
        break;
      }
    }
    if (display == null) return null;

    final mediaById = {
      for (final item in adMediaForOrg(
        orgId: orgId,
        createdByUid: LocalDemoData.adminAccount.uid,
        now: now,
      ))
        if (item.id != null) item.id!: item,
    };
    return PublicDisplayData(
      name: display.name,
      slideSeconds: display.slideSeconds,
      fit: display.fit,
      transition: display.transition,
      isActive: display.isActive,
      slides: [
        for (final mediaId in display.mediaIds)
          if (mediaById[mediaId] case final media?)
            PublicDisplaySlide(
              url: media.downloadUrl,
              seconds: display.slideSeconds,
              title: media.title,
            ),
      ],
    );
  }

  static List<AuditLogEntry> auditEntriesForOrg({
    required String orgId,
    DateTime? now,
  }) {
    final anchor = now ?? DateTime.now();
    const types = ['Produkt', 'Schicht', 'Kontakt', 'Zeiteintrag'];
    const summaries = [
      'Demo-Artikel angelegt',
      'Schichtzeit angepasst',
      'Veralteten Testkontakt gelöscht',
      'Fehlstempelung fachlich korrigiert',
    ];
    return [
      for (var i = 0; i < AuditAction.values.length; i++)
        AuditLogEntry(
          id: 'demo-audit-$orgId-${AuditAction.values[i].name}',
          orgId: orgId,
          action: AuditAction.values[i],
          entityType: types[i],
          entityId: 'demo-entity-$i',
          summary: summaries[i],
          actorUid: LocalDemoData.adminAccount.uid,
          actorName: LocalDemoData.adminAccount.name,
          createdAt: anchor.subtract(Duration(hours: i + 1)),
        ),
    ];
  }
}
