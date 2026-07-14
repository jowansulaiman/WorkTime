import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/shift_swap_request.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/screens/kiosk/kiosk_swap_service.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

const _maria = AppUserProfile(
  uid: 'emp-2',
  orgId: 'org-1',
  email: 'maria@example.com',
  role: UserRole.employee,
  isActive: true,
  settings: UserSettings(name: 'Maria'),
);

ShiftSwapRequest _swap({
  required String id,
  required String targetUid,
  required String targetName,
  SwapStatus status = SwapStatus.pending,
  String orgId = 'org-1',
  DateTime? createdAt,
}) {
  return ShiftSwapRequest(
    id: id,
    orgId: orgId,
    requesterUid: 'emp-1',
    requesterName: 'Peter',
    requesterShiftId: 'shift-p',
    targetUid: targetUid,
    targetName: targetName,
    targetShiftId: 'shift-m',
    kind: SwapKind.exchange,
    status: status,
    requesterShiftStart: DateTime(2026, 6, 22, 8),
    targetShiftStart: DateTime(2026, 6, 23, 9),
    requesterShiftLabel: 'Frühdienst',
    targetShiftLabel: 'Spätdienst',
    createdAt: createdAt ?? DateTime(2026, 6, 20, 10),
  );
}

Future<void> _seed(List<ShiftSwapRequest> requests) {
  // Tauschanfragen sind org-skopiert — die Nutzer-Scope liest denselben Namespace.
  return DatabaseService.saveLocalSwapRequests(
    requests,
    scope: LocalStorageScope.fromUser(_maria),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  group('DevKioskSwapService (lokaler Offline-/Demo-Pfad)', () {
    test('incomingPending liefert nur offene, an mich gerichtete Anfragen',
        () async {
      await _seed([
        _swap(id: 'a', targetUid: 'emp-2', targetName: 'Maria'), // offen an Maria
        _swap(
            id: 'b',
            targetUid: 'emp-2',
            targetName: 'Maria',
            status: SwapStatus.acceptedByColleague), // nicht mehr offen
        _swap(id: 'c', targetUid: 'emp-9', targetName: 'Otto'), // fremdes Ziel
        _swap(id: 'd', targetUid: 'emp-2', targetName: 'Maria', orgId: 'org-2'),
      ]);
      final svc = DevKioskSwapService();
      final incoming = await svc.incomingPending(_maria);
      expect(incoming.map((r) => r.id), ['a']);
    });

    test('incomingPending sortiert neueste zuerst', () async {
      await _seed([
        _swap(
            id: 'alt',
            targetUid: 'emp-2',
            targetName: 'Maria',
            createdAt: DateTime(2026, 6, 1)),
        _swap(
            id: 'neu',
            targetUid: 'emp-2',
            targetName: 'Maria',
            createdAt: DateTime(2026, 6, 10)),
      ]);
      final incoming = await DevKioskSwapService().incomingPending(_maria);
      expect(incoming.map((r) => r.id), ['neu', 'alt']);
    });

    test('respond(accept:true) setzt acceptedByColleague und persistiert',
        () async {
      await _seed([_swap(id: 'a', targetUid: 'emp-2', targetName: 'Maria')]);
      await DevKioskSwapService()
          .respond(_maria, requestId: 'a', accept: true);
      final stored = await DatabaseService.loadLocalSwapRequests(
          scope: LocalStorageScope.fromUser(_maria));
      expect(stored.single.status, SwapStatus.acceptedByColleague);
      expect(stored.single.updatedAt, isNotNull);
      // Danach ist sie nicht mehr „offen".
      expect(await DevKioskSwapService().incomingPending(_maria), isEmpty);
    });

    test('respond(accept:false) setzt declinedByColleague', () async {
      await _seed([_swap(id: 'a', targetUid: 'emp-2', targetName: 'Maria')]);
      await DevKioskSwapService()
          .respond(_maria, requestId: 'a', accept: false);
      final stored = await DatabaseService.loadLocalSwapRequests(
          scope: LocalStorageScope.fromUser(_maria));
      expect(stored.single.status, SwapStatus.declinedByColleague);
    });

    test('respond auf fremdes Ziel wirft und ändert nichts', () async {
      await _seed([_swap(id: 'c', targetUid: 'emp-9', targetName: 'Otto')]);
      await expectLater(
        DevKioskSwapService().respond(_maria, requestId: 'c', accept: true),
        throwsA(isA<StateError>()),
      );
      final stored = await DatabaseService.loadLocalSwapRequests(
          scope: LocalStorageScope.fromUser(_maria));
      expect(stored.single.status, SwapStatus.pending);
    });

    test('respond auf bereits geschlossene Anfrage wirft', () async {
      await _seed([
        _swap(
            id: 'a',
            targetUid: 'emp-2',
            targetName: 'Maria',
            status: SwapStatus.confirmed),
      ]);
      await expectLater(
        DevKioskSwapService().respond(_maria, requestId: 'a', accept: true),
        throwsA(isA<StateError>()),
      );
    });

    test('respond auf unbekannte id wirft', () async {
      await _seed([_swap(id: 'a', targetUid: 'emp-2', targetName: 'Maria')]);
      await expectLater(
        DevKioskSwapService().respond(_maria, requestId: 'x', accept: true),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('ServerKioskSwapService (cloudFunctionInvoker-Seam)', () {
    test('getKioskIncomingSwaps parst die snake_case-Liste der Callable',
        () async {
      final service = FirestoreService(
        cloudFunctionInvoker: (name, p) async {
          expect(name, 'getKioskIncomingSwaps');
          expect(p['sid'], 'srv-1');
          return <String, dynamic>{
            'requests': [
              _swap(id: 'a', targetUid: 'emp-2', targetName: 'Maria').toMap(),
            ],
          };
        },
      );
      final list =
          await ServerKioskSwapService(service).incomingPending(_maria, sid: 'srv-1');
      expect(list, hasLength(1));
      expect(list.single.id, 'a');
      expect(list.single.targetUid, 'emp-2');
      expect(list.single.status, SwapStatus.pending);
    });

    test('incomingPending ohne sid ruft keine Callable und liefert leer',
        () async {
      var called = false;
      final service = FirestoreService(
        cloudFunctionInvoker: (name, p) async {
          called = true;
          return <String, dynamic>{'requests': []};
        },
      );
      final list = await ServerKioskSwapService(service).incomingPending(_maria);
      expect(list, isEmpty);
      expect(called, isFalse);
    });

    test('respond sendet sid, requestId und accept an kioskRespondSwap',
        () async {
      Map<String, dynamic>? payload;
      final service = FirestoreService(
        cloudFunctionInvoker: (name, p) async {
          payload = {'name': name, ...p};
          return <String, dynamic>{'ok': true, 'status': 'accepted_by_colleague'};
        },
      );
      await ServerKioskSwapService(service)
          .respond(_maria, requestId: 'a', accept: true, sid: 'srv-1');
      expect(payload?['name'], 'kioskRespondSwap');
      expect(payload?['sid'], 'srv-1');
      expect(payload?['requestId'], 'a');
      expect(payload?['accept'], true);
    });
  });
}
