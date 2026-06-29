import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/sfn_zuschlag.dart';
import 'package:worktime_app/models/pay_line_type.dart';
import 'package:worktime_app/models/payroll_record.dart';

void main() {
  group('PayLine-Enums', () {
    test('PayLineKind value/fromValue round-trip + Default zulage', () {
      for (final k in PayLineKind.values) {
        expect(PayLineKindX.fromValue(k.value), k);
      }
      expect(PayLineKindX.fromValue('quatsch'), PayLineKind.zulage);
      expect(PayLineKindX.fromValue(null), PayLineKind.zulage);
      expect(PayLineKind.zuschlag3b.value, 'zuschlag3b');
    });

    test('PayWertTyp/PayInterval Defaults', () {
      expect(PayWertTypX.fromValue('prozent'), PayWertTyp.prozent);
      expect(PayWertTypX.fromValue(null), PayWertTyp.nominal);
      expect(PayIntervalX.fromValue('jaehrlich'), PayInterval.jaehrlich);
      expect(PayIntervalX.fromValue('quatsch'), PayInterval.monatlich);
    });
  });

  group('PayLineType', () {
    test('isValidDatevLohnartNr: weiche Validierung (max 4-stellig numerisch)',
        () {
      expect(PayLineType.isValidDatevLohnartNr(null), isTrue);
      expect(PayLineType.isValidDatevLohnartNr(''), isTrue);
      expect(PayLineType.isValidDatevLohnartNr('1'), isTrue);
      expect(PayLineType.isValidDatevLohnartNr('9999'), isTrue);
      expect(PayLineType.isValidDatevLohnartNr('12345'), isFalse); // 5-stellig
      expect(PayLineType.isValidDatevLohnartNr('12a'), isFalse); // nicht numerisch
    });

    test('toMap/fromMap (snake_case) trippt rund', () {
      const type = PayLineType(
        id: 'plt-1',
        orgId: 'org-1',
        name: 'Nachtzuschlag',
        datevLohnartNr: '4120',
        kind: PayLineKind.zuschlag3b,
        wertTyp: PayWertTyp.prozent,
        intervall: PayInterval.monatlich,
        steuerfrei: true,
        svFrei: false,
        deaktiviert: false,
      );
      final r = PayLineType.fromMap(type.toMap());
      expect(r.name, 'Nachtzuschlag');
      expect(r.datevLohnartNr, '4120');
      expect(r.kind, PayLineKind.zuschlag3b);
      expect(r.wertTyp, PayWertTyp.prozent);
      expect(r.intervall, PayInterval.monatlich);
      expect(r.steuerfrei, isTrue);
      expect(r.svFrei, isFalse);
    });

    test('toFirestoreMap/fromFirestore (camelCase) trippt rund', () {
      const type = PayLineType(
        orgId: 'org-1',
        name: 'VwL AG-Zuschuss',
        kind: PayLineKind.vwl,
      );
      final map = type.toFirestoreMap();
      final r = PayLineType.fromFirestore('plt-2', map);
      expect(r.id, 'plt-2');
      expect(r.name, 'VwL AG-Zuschuss');
      expect(r.kind, PayLineKind.vwl);
    });

    test('copyWith clearDatevLohnartNr löscht die Nummer', () {
      const type = PayLineType(
          orgId: 'org-1', name: 'X', datevLohnartNr: '4120');
      expect(type.copyWith(clearDatevLohnartNr: true).datevLohnartNr, isNull);
      expect(type.copyWith(datevLohnartNr: '8001').datevLohnartNr, '8001');
    });
  });

  group('PayrollLine – Steuer-/SV-Aufteilung', () {
    test('ganz steuerpflichtige Zeile (Grundlohn)', () {
      const line = PayrollLine(
        name: 'Grundlohn',
        amountCents: 200000,
        kind: PayLineKind.grundlohn,
      );
      expect(line.effektivSteuerfreiCents, 0);
      expect(line.steuerpflichtigCents, 200000);
      expect(line.effektivSvFreiCents, 0);
      expect(line.svPflichtigCents, 200000);
    });

    test('ganz steuerfreie Zeile via Flag', () {
      const line = PayrollLine(
        name: 'Steuerfreier Zuschuss',
        amountCents: 5000,
        kind: PayLineKind.zulage,
        steuerfrei: true,
        svFrei: true,
      );
      expect(line.effektivSteuerfreiCents, 5000);
      expect(line.steuerpflichtigCents, 0);
      expect(line.svPflichtigCents, 0);
    });

    test('§3b-Factory bindet den Rechenkern korrekt an die Zeile', () {
      final anteil = computeSfn3bAnteil(
        art: SfnZuschlagsart.nacht,
        grundlohnCentsProStunde: 6000, // 60 €/h → über beiden Caps
        dauer: const Duration(hours: 1),
      );
      // gesamt 1500 / steuerfrei 1250 / svFrei 625 (siehe sfn_zuschlag_test)
      final line = PayrollLine.zuschlag3b(
        anteil: anteil,
        name: 'Nachtzuschlag §3b',
        datevLohnartNr: '4120',
      );
      expect(line.kind, PayLineKind.zuschlag3b);
      expect(line.amountCents, 1500);
      expect(line.steuerfreiAnteilCents, 1250);
      expect(line.svFreiAnteilCents, 625);
      // Anteilsfelder haben Vorrang vor den Flags:
      expect(line.effektivSteuerfreiCents, 1250);
      expect(line.steuerpflichtigCents, 250);
      expect(line.effektivSvFreiCents, 625);
      expect(line.svPflichtigCents, 875);
    });

    test('PayrollLine dual-serial. (beide Formate) trippt rund', () {
      final anteil = computeSfn3bAnteil(
        art: SfnZuschlagsart.sonntag,
        grundlohnCentsProStunde: 3000,
        dauer: const Duration(hours: 2),
      );
      final line = PayrollLine.zuschlag3b(anteil: anteil, name: 'Sonntag §3b');

      final rFs = PayrollLine.fromFirestore(line.toFirestoreMap());
      expect(rFs.amountCents, line.amountCents);
      expect(rFs.steuerfreiAnteilCents, line.steuerfreiAnteilCents);
      expect(rFs.svFreiAnteilCents, line.svFreiAnteilCents);
      expect(rFs.kind, PayLineKind.zuschlag3b);

      final rLocal = PayrollLine.fromMap(line.toMap());
      expect(rLocal.amountCents, line.amountCents);
      expect(rLocal.steuerfreiAnteilCents, line.steuerfreiAnteilCents);
      expect(rLocal.svFreiAnteilCents, line.svFreiAnteilCents);
    });
  });

  group('PayrollRecord.lines', () {
    PayrollRecord buildRecord(List<PayrollLine> lines) => PayrollRecord(
          orgId: 'org-1',
          userId: 'u-1',
          periodYear: 2026,
          periodMonth: 6,
          grossCents: 200000,
          lines: lines,
        );

    final zuschlag = PayrollLine.zuschlag3b(
      anteil: computeSfn3bAnteil(
        art: SfnZuschlagsart.nacht,
        grundlohnCentsProStunde: 6000,
        dauer: const Duration(hours: 1),
      ),
      name: 'Nacht §3b',
    );
    const grundlohn = PayrollLine(
      name: 'Grundlohn',
      amountCents: 200000,
      kind: PayLineKind.grundlohn,
    );

    test('Summen-Getter', () {
      final rec = buildRecord([grundlohn, zuschlag]);
      expect(rec.linesTotalCents, 201500); // 200000 + 1500
      expect(rec.steuerpflichtigeLinesCents, 200250); // 200000 + 250
      expect(rec.svPflichtigeLinesCents, 200875); // 200000 + 875
    });

    test('toMap/fromMap trippt die Zeilen rund', () {
      final rec = buildRecord([grundlohn, zuschlag]);
      final r = PayrollRecord.fromMap(rec.toMap());
      expect(r.lines, hasLength(2));
      expect(r.lines[0].kind, PayLineKind.grundlohn);
      expect(r.lines[1].kind, PayLineKind.zuschlag3b);
      expect(r.lines[1].steuerfreiAnteilCents, 1250);
      expect(r.linesTotalCents, 201500);
    });

    test('toFirestoreMap/fromFirestore trippt die Zeilen rund', () {
      final rec = buildRecord([grundlohn, zuschlag]);
      final r = PayrollRecord.fromFirestore('u-1-2026-06', rec.toFirestoreMap());
      expect(r.lines, hasLength(2));
      expect(r.lines[1].amountCents, 1500);
      expect(r.svPflichtigeLinesCents, 200875);
    });

    test('Abwärtskompatibel: fehlender lines-Schlüssel ⇒ leere Liste', () {
      final r = PayrollRecord.fromMap({
        'org_id': 'org-1',
        'user_id': 'u-1',
        'period_year': 2026,
        'period_month': 6,
      });
      expect(r.lines, isEmpty);
      expect(r.linesTotalCents, 0);
    });

    test('copyWith ersetzt die Zeilen', () {
      final rec = buildRecord([grundlohn]);
      final r = rec.copyWith(lines: [grundlohn, zuschlag]);
      expect(r.lines, hasLength(2));
      expect(rec.lines, hasLength(1)); // Original unverändert
    });

    test('null-Anteile überleben den Round-trip (keine 0-Coercion)', () {
      // Flag-steuerfreie Zeile OHNE partielle Anteile (Anteilsfelder null):
      // würde parse.toInt fälschlich auf 0 coercen, käme effektivSteuerfrei = 0
      // statt amountCents heraus → steuerpflichtigeLinesCents würde überzählt.
      const vollfrei = PayrollLine(
        name: 'Steuerfreier Zuschuss',
        amountCents: 5000,
        kind: PayLineKind.zulage,
        steuerfrei: true,
        svFrei: true,
      );
      final rec = buildRecord([vollfrei, grundlohn]);

      for (final r in [
        PayrollRecord.fromMap(rec.toMap()),
        PayrollRecord.fromFirestore('u-1-2026-06', rec.toFirestoreMap()),
      ]) {
        expect(r.lines.first.steuerfreiAnteilCents, isNull);
        expect(r.lines.first.svFreiAnteilCents, isNull);
        // Flag greift weiterhin → ganze Zeile frei.
        expect(r.lines.first.effektivSteuerfreiCents, 5000);
        expect(r.lines.first.steuerpflichtigCents, 0);
        // Nur der Grundlohn ist steuerpflichtig (nicht 5000 + 200000).
        expect(r.steuerpflichtigeLinesCents, 200000);
        expect(r.svPflichtigeLinesCents, 200000);
      }
    });
  });
}
