import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/services/barcode_scanner.dart';
import 'package:worktime_app/services/scan_feedback.dart';
import 'package:worktime_app/widgets/barcode_scan_field.dart';

/// Kamera-Fake ohne Platform-Channel: [emit] speist einen Code in den Stream.
class _FakeBarcodeScanner implements BarcodeScanner {
  final StreamController<String> controller =
      StreamController<String>.broadcast();
  ScannerTarget _target = ScannerTarget.retail;

  void emit(String code) => controller.add(code);

  @override
  Stream<String> get codes => controller.stream;
  @override
  bool get isAvailable => true;
  @override
  bool get supportsTorch => false;
  @override
  bool get supportsZoom => false;
  @override
  bool get supportsPhotoAnalysis => false;
  @override
  ScannerTarget get target => _target;
  @override
  Future<void> setTarget(ScannerTarget target) async => _target = target;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> toggleTorch() async {}
  @override
  Future<void> switchCamera() async {}
  @override
  Future<void> setZoom(double scale) async {}
  @override
  Future<List<String>> analyzePhoto(String path) async => const [];
  @override
  Widget buildPreview(BuildContext context) =>
      const SizedBox(key: Key('fake-preview'));
  @override
  Future<void> dispose() async {}
}

Future<BuildContext> _pumpHost(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          ctx = context;
          return const SizedBox();
        }),
      ),
    ),
  );
  return ctx;
}

void main() {
  testWidgets('Kamera-Scan liefert den rohen Code zurück (extended-Ziel)',
      (tester) async {
    final fake = _FakeBarcodeScanner();
    addTearDown(() => fake.controller.close());
    final ctx = await _pumpHost(tester);

    String? result;
    unawaited(
      showBarcodeScanSheet(
        ctx,
        title: 'Paket scannen',
        scanner: fake,
        feedback: const NoopScanFeedback(),
      ).then((v) => result = v),
    );
    await tester.pumpAndSettle();

    expect(find.text('Paket scannen'), findsOneWidget);
    expect(find.byKey(const Key('fake-preview')), findsOneWidget);
    // Ziel wurde auf extended gesetzt (opake Paket-/Fach-Codes).
    expect(fake.target, ScannerTarget.extended);

    fake.emit('H0001234567890');
    await tester.pumpAndSettle();

    expect(result, 'H0001234567890');
  });

  testWidgets('manuelle Eingabe liefert den getippten Code', (tester) async {
    final fake = _FakeBarcodeScanner();
    addTearDown(() => fake.controller.close());
    final ctx = await _pumpHost(tester);

    String? result;
    unawaited(
      showBarcodeScanSheet(
        ctx,
        scanner: fake,
        feedback: const NoopScanFeedback(),
      ).then((v) => result = v),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'FACH-A2-XYZ');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();

    expect(result, 'FACH-A2-XYZ');
  });
}
