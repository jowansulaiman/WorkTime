import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/datev_export_run.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String sha(String c) => c * 64;

  late FakeFirebaseFirestore firestore;
  late FirestoreService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
    firestore = FakeFirebaseFirestore();
    service = FirestoreService(firestore: firestore);
  });
  group('DatevExportRun (Q2)', () {
    test('camelCase round-trippt (fromFirestore/toFirestoreMap)', () {
      final run = DatevExportRun(
        orgId: 'org-1',
        exportArt: DatevExportArt.finanz,
        kind: 'extf_buchungsstapel',
        periodYear: 2026,
        createdByUid: 'admin-1',
        entryCount: 42,
        sollCents: 100000,
        habenCents: 100000,
        fileName: 'EXTF_2026.csv',
        fileSha256:
            sha('a'),
        generatedAtMillis: 1752400000000,
        entriesSnapshot: [
          {'konto': '8400', 'betragCents': 1190},
        ],
        snapshotRowCount: 1,
        acceptedWarningCodes: ['closing_unbooked'],
        problemeAnzahl: 1,
        monatFestgeschrieben: true,
        overrideBestaetigt: true,
      );
      final map = run.toFirestoreMap();
      expect(map['exportArt'], 'finanz');
      expect(map['fileSha256'], sha('a'));
      // createdAt ist ein serverTimestamp-Sentinel (kein Wert) — nicht asserten.

      final restored = DatevExportRun.fromFirestore('run-1', map);
      expect(restored.id, 'run-1');
      expect(restored.exportArt, DatevExportArt.finanz);
      expect(restored.kind, 'extf_buchungsstapel');
      expect(restored.entryCount, 42);
      expect(restored.entriesSnapshot?.single['konto'], '8400');
      expect(restored.acceptedWarningCodes, ['closing_unbooked']);
      expect(restored.monatFestgeschrieben, isTrue);
      expect(restored.schemaVersion, 1);
    });

    test('enum fromValue hat Default-Branch (unbekannt → finanz)', () {
      expect(DatevExportArtX.fromValue('lohn'), DatevExportArt.lohn);
      expect(DatevExportArtX.fromValue('zzz'), DatevExportArt.finanz);
      expect(DatevExportArtX.fromValue(null), DatevExportArt.finanz);
    });

    test('canRebuildByteIdentical: Lohn per rowsSnapshot, Finanz per entries', () {
      final lohn = DatevExportRun(
        orgId: 'o',
        exportArt: DatevExportArt.lohn,
        kind: 'lodas_bewegungsdaten',
        periodYear: 2026,
        createdByUid: 'a',
        fileName: 'l.txt',
        fileSha256: sha('b'),
        rowsSnapshot: [
          {'personalnummer': '7', 'lohnartNr': '100', 'betragCents': 300000},
        ],
      );
      expect(lohn.canRebuildByteIdentical, isTrue);

      final truncated = DatevExportRun(
        orgId: 'o',
        exportArt: DatevExportArt.finanz,
        kind: 'extf_buchungsstapel',
        periodYear: 2026,
        createdByUid: 'a',
        fileName: 'f.csv',
        fileSha256: sha('c'),
        snapshotTruncated: true,
      );
      expect(truncated.canRebuildByteIdentical, isFalse);
    });
  });

  group('FirestoreService datevExportRuns (Q2)', () {
    test('create legt Doc an, watch filtert nach Art', () async {
      final finanzId = await service.createDatevExportRun(DatevExportRun(
        orgId: 'org-1',
        exportArt: DatevExportArt.finanz,
        kind: 'extf_buchungsstapel',
        periodYear: 2026,
        createdByUid: 'admin-1',
        fileName: 'f.csv',
        fileSha256: sha('a'),
      ));
      expect(finanzId, isNotEmpty);

      await service.createDatevExportRun(DatevExportRun(
        orgId: 'org-1',
        exportArt: DatevExportArt.lohn,
        kind: 'lodas_bewegungsdaten',
        periodYear: 2026,
        createdByUid: 'admin-1',
        fileName: 'l.txt',
        fileSha256: sha('b'),
      ));

      final finanzRuns =
          await service.watchDatevExportRuns('org-1', DatevExportArt.finanz).first;
      expect(finanzRuns, hasLength(1));
      expect(finanzRuns.single.kind, 'extf_buchungsstapel');

      final lohnRuns =
          await service.watchDatevExportRuns('org-1', DatevExportArt.lohn).first;
      expect(lohnRuns, hasLength(1));
      expect(lohnRuns.single.kind, 'lodas_bewegungsdaten');
    });
  });
}
