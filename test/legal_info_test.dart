import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/legal_info.dart';
import 'package:worktime_app/screens/public/public_legal_app.dart';

/// Reine Logik-Tripwires für die Rechtsseiten — ohne Binding, unabhängig von der
/// UI. Sichern (a) die „nicht leer online gehen"-Schwelle `LegalInfo.isComplete`
/// und (b) die URL-Routen-Erkennung inkl. aller Datenschutz-Aliasse/Groß-Klein.
void main() {
  group('LegalInfo.isComplete', () {
    const full = LegalInfo(
      operatorName: 'Erika Mustermann',
      street: 'Holstenstraße 1',
      postalCity: '24103 Kiel',
      email: 'kontakt@example.de',
      phone: '0431 1234567',
    );

    test('vollständig (Name+Anschrift+E-Mail+Telefon) ⇒ true', () {
      expect(full.isComplete, isTrue);
    });

    test('jedes fehlende Pflichtfeld ⇒ false', () {
      expect(
          const LegalInfo(
            street: 'Holstenstraße 1',
            postalCity: '24103 Kiel',
            email: 'kontakt@example.de',
            phone: '0431 1',
          ).isComplete,
          isFalse,
          reason: 'ohne operatorName');
      expect(
          const LegalInfo(
            operatorName: 'Erika Mustermann',
            postalCity: '24103 Kiel',
            email: 'kontakt@example.de',
            phone: '0431 1',
          ).isComplete,
          isFalse,
          reason: 'ohne street');
      expect(
          const LegalInfo(
            operatorName: 'Erika Mustermann',
            street: 'Holstenstraße 1',
            email: 'kontakt@example.de',
            phone: '0431 1',
          ).isComplete,
          isFalse,
          reason: 'ohne postalCity');
      expect(
          const LegalInfo(
            operatorName: 'Erika Mustermann',
            street: 'Holstenstraße 1',
            postalCity: '24103 Kiel',
            phone: '0431 1',
          ).isComplete,
          isFalse,
          reason: 'ohne email');
      expect(
          const LegalInfo(
            operatorName: 'Erika Mustermann',
            street: 'Holstenstraße 1',
            postalCity: '24103 Kiel',
            email: 'kontakt@example.de',
          ).isComplete,
          isFalse,
          reason: 'ohne phone');
    });

    test('optionale Felder (vatId/register/representative/lastUpdated) ändern '
        'isComplete nicht', () {
      expect(
        full.isComplete,
        const LegalInfo(
          operatorName: 'Erika Mustermann',
          street: 'Holstenstraße 1',
          postalCity: '24103 Kiel',
          email: 'kontakt@example.de',
          phone: '0431 1234567',
          vatId: 'DE123456789',
          registerEntry: 'Amtsgericht Kiel HRA 1',
          representative: 'Erika Mustermann',
          lastUpdated: 'Juni 2026',
        ).isComplete,
      );
    });

    test('Default aus leerer Konfiguration ⇒ NICHT veröffentlichungsbereit', () {
      // Schützt davor, dass ein Release versehentlich mit leeren APP_LEGAL_*
      // online geht: ohne gesetzte Defines greift der sichtbare Setup-Hinweis.
      expect(LegalInfo.fromConfig().isComplete, isFalse);
    });
  });

  group('Routen-Erkennung (reine Matcher)', () {
    test('Impressum matcht nur „impressum" (case-insensitiv)', () {
      expect(matchesImpressumSegments(['impressum']), isTrue);
      expect(matchesImpressumSegments(['Impressum']), isTrue);
      expect(matchesImpressumSegments(['foo', 'IMPRESSUM']), isTrue);
      expect(matchesImpressumSegments(['datenschutz']), isFalse);
      expect(matchesImpressumSegments(['wunsch']), isFalse);
      expect(matchesImpressumSegments(const <String>[]), isFalse);
    });

    test('Datenschutz matcht alle vier Aliasse (case-insensitiv)', () {
      for (final alias in const [
        'datenschutz',
        'datenschutzerklaerung',
        'datenschutzerklärung',
        'privacy',
      ]) {
        expect(matchesDatenschutzSegments([alias]), isTrue, reason: alias);
        expect(matchesDatenschutzSegments([alias.toUpperCase()]), isTrue,
            reason: '$alias (groß)');
      }
      expect(matchesDatenschutzSegments(['impressum']), isFalse);
      expect(matchesDatenschutzSegments(['wunsch']), isFalse);
      expect(matchesDatenschutzSegments(const <String>[]), isFalse);
    });
  });
}
