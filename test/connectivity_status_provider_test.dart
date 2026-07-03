import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/providers/connectivity_status_provider.dart';

void main() {
  group('ConnectivityStatusProvider (OP1)', () {
    test('Initial-Check offline -> isOffline true + initialized', () async {
      final provider = ConnectivityStatusProvider(
        changes: const Stream<List<ConnectivityResult>>.empty(),
        check: () async => const <ConnectivityResult>[ConnectivityResult.none],
        debounce: Duration.zero,
        observeLifecycle: false,
      );
      await Future<void>.delayed(Duration.zero);
      expect(provider.initialized, isTrue);
      expect(provider.isOffline, isTrue);
      expect(provider.isOnline, isFalse);
      expect(provider.status, ConnectivityStatus.offline);
      provider.dispose();
    });

    test('Stream: none -> offline, dann mobile -> online (mit notify)',
        () async {
      final controller = StreamController<List<ConnectivityResult>>();
      final provider = ConnectivityStatusProvider(
        changes: controller.stream,
        check: () async => const <ConnectivityResult>[ConnectivityResult.wifi],
        debounce: Duration.zero,
        observeLifecycle: false,
      );
      await Future<void>.delayed(Duration.zero);
      expect(provider.isOnline, isTrue);

      var notifications = 0;
      provider.addListener(() => notifications++);

      controller.add(const <ConnectivityResult>[ConnectivityResult.none]);
      await Future<void>.delayed(Duration.zero);
      expect(provider.isOffline, isTrue);

      controller.add(const <ConnectivityResult>[ConnectivityResult.mobile]);
      await Future<void>.delayed(Duration.zero);
      expect(provider.isOnline, isTrue);

      expect(notifications, greaterThanOrEqualTo(2));
      await controller.close();
      provider.dispose();
    });

    test('Check wirft -> optimistisch online, aber initialized', () async {
      final provider = ConnectivityStatusProvider(
        changes: const Stream<List<ConnectivityResult>>.empty(),
        check: () async => throw Exception('kein Platform-Channel'),
        debounce: Duration.zero,
        observeLifecycle: false,
      );
      await Future<void>.delayed(Duration.zero);
      expect(provider.initialized, isTrue);
      expect(provider.isOnline, isTrue);
      provider.dispose();
    });
  });

  group('ConnectivityStatusProvider — Reachability-Probe (ZV-1.1)', () {
    test('Interface up, Probe schlägt fehl -> backendUnreachable', () async {
      final provider = ConnectivityStatusProvider(
        changes: const Stream<List<ConnectivityResult>>.empty(),
        check: () async => const <ConnectivityResult>[ConnectivityResult.wifi],
        reachabilityProbe: () async => false, // Captive-Portal
        debounce: Duration.zero,
        observeLifecycle: false,
      );
      await Future<void>.delayed(Duration.zero);
      expect(provider.status, ConnectivityStatus.backendUnreachable);
      expect(provider.isOnline, isFalse);
      expect(provider.isOffline, isTrue); // Banner soll auch hier zeigen
      expect(provider.isBackendUnreachable, isTrue);
      provider.dispose();
    });

    test('Interface up, Probe wirft -> backendUnreachable (nicht online)',
        () async {
      final provider = ConnectivityStatusProvider(
        changes: const Stream<List<ConnectivityResult>>.empty(),
        check: () async => const <ConnectivityResult>[ConnectivityResult.wifi],
        reachabilityProbe: () async => throw TimeoutException('probe'),
        debounce: Duration.zero,
        observeLifecycle: false,
      );
      await Future<void>.delayed(Duration.zero);
      expect(provider.status, ConnectivityStatus.backendUnreachable);
      provider.dispose();
    });

    test('Interface up, Probe ok -> online', () async {
      final provider = ConnectivityStatusProvider(
        changes: const Stream<List<ConnectivityResult>>.empty(),
        check: () async => const <ConnectivityResult>[ConnectivityResult.wifi],
        reachabilityProbe: () async => true,
        debounce: Duration.zero,
        observeLifecycle: false,
      );
      await Future<void>.delayed(Duration.zero);
      expect(provider.status, ConnectivityStatus.online);
      provider.dispose();
    });

    test('recheck() prüft erneut (offline -> online nach Wiederkehr)', () async {
      var reachable = false;
      final provider = ConnectivityStatusProvider(
        changes: const Stream<List<ConnectivityResult>>.empty(),
        check: () async => const <ConnectivityResult>[ConnectivityResult.wifi],
        reachabilityProbe: () async => reachable,
        debounce: Duration.zero,
        observeLifecycle: false,
      );
      await Future<void>.delayed(Duration.zero);
      expect(provider.isBackendUnreachable, isTrue);

      reachable = true;
      await provider.recheck();
      expect(provider.status, ConnectivityStatus.online);
      provider.dispose();
    });
  });

  group('ConnectivityStatusProvider — Debounce (ZV-1.1)', () {
    test('kurzer Offline-Blip wird entprellt (bleibt online)', () async {
      final controller = StreamController<List<ConnectivityResult>>();
      final provider = ConnectivityStatusProvider(
        changes: controller.stream,
        check: () async => const <ConnectivityResult>[ConnectivityResult.wifi],
        debounce: const Duration(milliseconds: 120),
        observeLifecycle: false,
      );
      await Future<void>.delayed(Duration.zero);
      expect(provider.isOnline, isTrue);

      // Blip: kurz none, dann vor Ablauf der Debounce wieder wifi.
      controller.add(const <ConnectivityResult>[ConnectivityResult.none]);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(provider.isOnline, isTrue, reason: 'Wechsel noch nicht entprellt');
      controller.add(const <ConnectivityResult>[ConnectivityResult.wifi]);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(provider.isOnline, isTrue, reason: 'Blip verschluckt');

      await controller.close();
      provider.dispose();
    });

    test('anhaltendes Offline setzt sich nach Debounce durch', () async {
      final controller = StreamController<List<ConnectivityResult>>();
      final provider = ConnectivityStatusProvider(
        changes: controller.stream,
        check: () async => const <ConnectivityResult>[ConnectivityResult.wifi],
        debounce: const Duration(milliseconds: 80),
        observeLifecycle: false,
      );
      await Future<void>.delayed(Duration.zero);

      controller.add(const <ConnectivityResult>[ConnectivityResult.none]);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(provider.isOffline, isTrue);

      await controller.close();
      provider.dispose();
    });
  });
}
