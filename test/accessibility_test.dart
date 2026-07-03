import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/accessibility.dart';

void main() {
  group('Textskala-Leiter (Plan-Entscheidung E1 „gestuft")', () {
    test('Konstanten: global 2,0 / dicht 1,5', () {
      expect(kMaxTextScaleFactor, 2.0);
      expect(kDenseContentMaxTextScaleFactor, 1.5);
    });

    test('clampTextScaler klemmt global auf 2,0, kleiner bleibt unangetastet',
        () {
      expect(clampTextScaler(const TextScaler.linear(3.0)).scale(10), 20);
      expect(clampTextScaler(const TextScaler.linear(1.0)).scale(10), 10);
      expect(clampTextScaler(const TextScaler.linear(1.8)).scale(10), 18);
    });

    testWidgets('DenseContentTextScale klemmt dichten Teilbaum auf 1,5',
        (tester) async {
      double? innerScale;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2.0)),
              child: DenseContentTextScale(
                child: Builder(
                  builder: (inner) {
                    innerScale = MediaQuery.of(inner).textScaler.scale(10);
                    return const SizedBox();
                  },
                ),
              ),
            ),
          ),
        ),
      );
      expect(innerScale, 15); // 2,0 -> auf 1,5 geklemmt
    });

    testWidgets('DenseContentTextScale laesst kleinere Skalierung unangetastet',
        (tester) async {
      double? innerScale;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.2)),
              child: DenseContentTextScale(
                child: Builder(
                  builder: (inner) {
                    innerScale = MediaQuery.of(inner).textScaler.scale(10);
                    return const SizedBox();
                  },
                ),
              ),
            ),
          ),
        ),
      );
      expect(innerScale, 12); // unter 1,5 -> unveraendert
    });
  });
}
