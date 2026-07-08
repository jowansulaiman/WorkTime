import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/employment_contract.dart';
import 'package:worktime_app/screens/team_management_screen.dart';

/// Fokussierter Test der extrahierten Speicher-Logik des
/// Mitglieder-Konfigurations-Sheets (W4, Vertrag-Editor-Datenverlust-Fix):
/// `buildMemberContractForSave` schreibt einen bestehenden Vertrag via
/// copyWith fort, statt ihn per Konstruktor neu zu bauen — `monthlyGrossCents`
/// und `validUntil` bleiben erhalten, `weeklyHours` wird nicht mehr blind mit
/// `dailyHours × 5` überschrieben.
void main() {
  EmploymentContract bestehenderVertrag({
    double weeklyHours = 40,
    double dailyHours = 8,
    int? monthlyIncomeLimitCents,
    EmploymentType type = EmploymentType.fullTime,
    bool isMinor = false,
    bool isPregnant = false,
  }) {
    return EmploymentContract(
      id: 'contract-1',
      orgId: 'org-1',
      userId: 'user-1',
      label: 'Arbeitsvertrag 2025',
      type: type,
      validFrom: DateTime(2025, 1, 1),
      validUntil: DateTime(2026, 12, 31),
      weeklyHours: weeklyHours,
      dailyHours: dailyHours,
      hourlyRate: 18,
      salaryKind: SalaryKind.monthly,
      monthlyGrossCents: 245000,
      currency: 'EUR',
      vacationDays: 26,
      maxDailyMinutes: 540,
      monthlyIncomeLimitCents: monthlyIncomeLimitCents,
      weeklyMaxHours: 20,
      monthlyMaxHours: 85,
      isMinor: isMinor,
      isPregnant: isPregnant,
      createdByUid: 'admin-1',
      createdAt: DateTime(2025, 1, 2, 10, 30),
    );
  }

  /// Ruft den Builder mit den Sheet-Defaults für den gegebenen Vertrag auf —
  /// einzelne Parameter lassen sich wie eine Nutzer-Eingabe übersteuern.
  EmploymentContract speichern(
    EmploymentContract? existing, {
    String? label = 'Arbeitsvertrag 2025',
    EmploymentType type = EmploymentType.fullTime,
    SalaryKind salaryKind = SalaryKind.monthly,
    DateTime? validFrom,
    double dailyHours = 8,
    double hourlyRate = 18,
    String currency = 'EUR',
    int fallbackVacationDays = 30,
    double? weeklyMaxHours = 20,
    double? monthlyMaxHours = 85,
  }) {
    return buildMemberContractForSave(
      existing: existing,
      orgId: 'org-1',
      userId: 'user-1',
      label: label,
      type: type,
      salaryKind: salaryKind,
      validFrom: validFrom ?? DateTime(2025, 1, 1),
      dailyHours: dailyHours,
      hourlyRate: hourlyRate,
      currency: currency,
      fallbackVacationDays: fallbackVacationDays,
      weeklyMaxHours: weeklyMaxHours,
      monthlyMaxHours: monthlyMaxHours,
    );
  }

  group('buildMemberContractForSave — bestehender Vertrag', () {
    test(
        'erhält monthlyGrossCents, validUntil, vacationDays, createdAt und id '
        'beim Speichern (bisheriger Datenverlust-Blocker)', () {
      final existing = bestehenderVertrag();

      final gespeichert = speichern(existing, hourlyRate: 19.5);

      expect(gespeichert.id, 'contract-1');
      expect(gespeichert.monthlyGrossCents, 245000,
          reason: 'Kanonisches Festgehalt darf nicht genullt werden');
      expect(gespeichert.validUntil, DateTime(2026, 12, 31),
          reason: 'Vertragsende darf nicht genullt werden');
      expect(gespeichert.vacationDays, 26,
          reason: 'Nicht im Sheet editierbares Feld bleibt unangetastet');
      expect(gespeichert.createdAt, DateTime(2025, 1, 2, 10, 30));
      expect(gespeichert.createdByUid, 'admin-1');
      // Die Nutzer-Eingabe kommt trotzdem an:
      expect(gespeichert.hourlyRate, 19.5);
    });

    test('behält individuell gepflegte weeklyHours bei unveränderten dailyHours',
        () {
      final existing = bestehenderVertrag(weeklyHours: 32, dailyHours: 8);

      final gespeichert = speichern(existing, dailyHours: 8);

      expect(gespeichert.weeklyHours, 32,
          reason: 'weeklyHours darf nicht blind mit dailyHours × 5 '
              'überschrieben werden');
    });

    test(
        'behält individuell gepflegte weeklyHours auch bei geänderten '
        'dailyHours (Wochenwert entsprach nicht der 5-Tage-Ableitung)', () {
      final existing = bestehenderVertrag(weeklyHours: 32, dailyHours: 8);

      final gespeichert = speichern(existing, dailyHours: 6);

      expect(gespeichert.dailyHours, 6);
      expect(gespeichert.weeklyHours, 32);
    });

    test(
        'leitet weeklyHours neu ab, wenn dailyHours geändert und der '
        'Wochenwert zuvor exakt die 5-Tage-Ableitung war', () {
      final existing = bestehenderVertrag(weeklyHours: 40, dailyHours: 8);

      final gespeichert = speichern(existing, dailyHours: 6);

      expect(gespeichert.dailyHours, 6);
      expect(gespeichert.weeklyHours, 30);
    });

    test('setzt und leert Max-Stunden-Grenzen über die clear-Flags', () {
      final existing = bestehenderVertrag();

      final geleert =
          speichern(existing, weeklyMaxHours: null, monthlyMaxHours: null);
      expect(geleert.weeklyMaxHours, isNull,
          reason: 'Leeres Feld muss die Grenze wirklich löschen (clearX)');
      expect(geleert.monthlyMaxHours, isNull);

      final gesetzt =
          speichern(existing, weeklyMaxHours: 25, monthlyMaxHours: 100);
      expect(gesetzt.weeklyMaxHours, 25);
      expect(gesetzt.monthlyMaxHours, 100);
    });

    test(
        'Minijob behält eine vorhandene Verdienstgrenze, Standard 60300 ohne '
        'eigene Grenze, Wechsel weg vom Minijob leert sie', () {
      final mitEigenerGrenze = bestehenderVertrag(
        type: EmploymentType.miniJob,
        monthlyIncomeLimitCents: 52000,
      );
      expect(
        speichern(mitEigenerGrenze, type: EmploymentType.miniJob)
            .monthlyIncomeLimitCents,
        52000,
      );

      final ohneGrenze = bestehenderVertrag();
      expect(
        speichern(ohneGrenze, type: EmploymentType.miniJob)
            .monthlyIncomeLimitCents,
        60300,
      );

      final zurueckZuVollzeit = bestehenderVertrag(
        type: EmploymentType.miniJob,
        monthlyIncomeLimitCents: 60300,
      );
      expect(
        speichern(zurueckZuVollzeit, type: EmploymentType.fullTime)
            .monthlyIncomeLimitCents,
        isNull,
      );
    });

    test('Schutzregeln-Ableitung bleibt: minderjährig → 480 Minuten Tageslimit',
        () {
      final existing = bestehenderVertrag(isMinor: true);

      final gespeichert = speichern(existing);

      expect(gespeichert.isMinor, isTrue);
      expect(gespeichert.maxDailyMinutes, 480);
    });

    test('geleertes Bezeichnungsfeld behält die bisherige Bezeichnung', () {
      final existing = bestehenderVertrag();

      final gespeichert = speichern(existing, label: null);

      expect(gespeichert.label, 'Arbeitsvertrag 2025');
    });
  });

  group('buildMemberContractForSave — neuer Vertrag', () {
    test('baut neuen Vertrag wie bisher (weeklyHours = dailyHours × 5)', () {
      final neu = speichern(
        null,
        label: 'Standardvertrag',
        dailyHours: 7,
        fallbackVacationDays: 28,
        weeklyMaxHours: null,
        monthlyMaxHours: null,
      );

      expect(neu.id, isNull);
      expect(neu.weeklyHours, 35);
      expect(neu.dailyHours, 7);
      expect(neu.vacationDays, 28);
      expect(neu.monthlyGrossCents, isNull);
      expect(neu.validUntil, isNull);
      expect(neu.maxDailyMinutes, 600);
      expect(neu.monthlyIncomeLimitCents, isNull);
    });

    test('neuer Minijob-Vertrag bekommt die Standard-Verdienstgrenze 60300',
        () {
      final neu = speichern(null, type: EmploymentType.miniJob);
      expect(neu.monthlyIncomeLimitCents, 60300);
    });
  });
}
