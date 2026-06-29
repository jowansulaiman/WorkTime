import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/urlaub_calculator.dart';
import 'package:worktime_app/models/sollzeit_profile.dart';

SollzeitProfile _profile(double urlaub) => SollzeitProfile(
      orgId: 'org-1',
      userId: 'emp-1',
      gueltigAb: DateTime(2024, 1, 1),
      urlaubstageJahr: urlaub,
    );

void main() {
  group('resolveUrlaubstageJahr (Vorrangregel §5.1)', () {
    test('SollzeitProfile gewinnt – auch beim Default-Wert', () {
      final r = resolveUrlaubstageJahr(
        sollzeit: _profile(26),
        annualVacationDays: 30,
        vertragVacationDays: 28,
      );
      expect(r.tage, 26);
      expect(r.quelle, UrlaubstageQuelle.sollzeitProfile);
      expect(r.ausAltfeld, isFalse);
    });

    test('Existenz des Profils ist das Signal (Default 20 schlägt Altfelder)',
        () {
      // Profil ohne explizit gesetzten Urlaub -> urlaubstageJahr == Default 20.
      final r = resolveUrlaubstageJahr(
        sollzeit: SollzeitProfile(
          orgId: 'o',
          userId: 'u',
          gueltigAb: DateTime(2024, 1, 1),
        ),
        annualVacationDays: 30,
      );
      expect(r.tage, 20);
      expect(r.quelle, UrlaubstageQuelle.sollzeitProfile);
    });

    test('ohne Profil: EmployeeProfile.annualVacationDays vor Vertrag', () {
      final r = resolveUrlaubstageJahr(
        annualVacationDays: 32,
        vertragVacationDays: 30,
      );
      expect(r.tage, 32);
      expect(r.quelle, UrlaubstageQuelle.mitarbeiterprofil);
      expect(r.ausAltfeld, isTrue);
    });

    test('ohne Profil/ohne Mitarbeiterfeld: Vertrag', () {
      final r = resolveUrlaubstageJahr(vertragVacationDays: 28);
      expect(r.tage, 28);
      expect(r.quelle, UrlaubstageQuelle.vertrag);
      expect(r.ausAltfeld, isTrue);
    });

    test('gar nichts hinterlegt: gesetzlicher Mindesturlaub (20)', () {
      final r = resolveUrlaubstageJahr();
      expect(r.tage, gesetzlicherMindesturlaub5Tage);
      expect(r.tage, 20);
      expect(r.quelle, UrlaubstageQuelle.gesetzlicherMindesturlaub);
      expect(r.ausAltfeld, isFalse);
    });
  });
}
