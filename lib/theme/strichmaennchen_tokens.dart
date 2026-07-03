import 'package:flutter/material.dart';

/// Design-Tokens **1:1 übernommen** aus der bestehenden Strichmännchen-Webseite
/// (`/Users/jowan/Documents/dev/Strichmänschen`, `styles.css` `:root` +
/// `.status-pill.is-open`). Zweck: neue Funktionen (MHD-/Ablauf-Warnung,
/// Zeitwirtschaft-Ausbau, …) optisch exakt an die Ladenseite angleichen.
///
/// **Regel:** Keine erfundenen Farben. Jeder Wert unten steht 1:1 im
/// Referenzprojekt — die Quellzeile ist am Konstanten-Kommentar vermerkt.
/// Alpha-Varianten (Border/Muted) sind die im Referenz-CSS real genutzten
/// `rgba(...)`-Ableitungen der Basistokens, ausgedrückt über `withValues`.
///
/// Die einzige **Ergänzung** ist die semantische Zuordnung `warning → --yellow`
/// (im Referenzprojekt gibt es keinen eigenen Warn-Token; `--yellow` ist dort
/// die Aufmerksamkeitsfarbe: CTA-Button, `::selection`, Scroll-Progress-Start).
/// Begründung siehe [warning].
@immutable
class StrichTokens {
  const StrichTokens._();

  // ===========================================================================
  // 1) ROH-PALETTE — exakt aus styles.css :root (Zeilen 3–14)
  // ===========================================================================

  /// `--navy` · `#061b36` — dominante Marken-/Dunkelfläche, dunkler Button,
  /// Header-Text. (styles.css:3)
  static const Color navy = Color(0xFF061B36);

  /// `--navy-soft` · `#0b2d55` — hellerer Navy-Ton (Verläufe, sekundär dunkel).
  /// (styles.css:4)
  static const Color navySoft = Color(0xFF0B2D55);

  /// `--ink` · `#171615` — Fließtext / Primärtext auf hellem Grund.
  /// (styles.css:5)
  static const Color ink = Color(0xFF171615);

  /// `--paper` · `#f4efe4` — warmes Creme, Seitenhintergrund. (styles.css:6)
  static const Color paper = Color(0xFFF4EFE4);

  /// `--paper-deep` · `#e7dcc7` — tieferes Papier, alternative Fläche.
  /// (styles.css:7)
  static const Color paperDeep = Color(0xFFE7DCC7);

  /// `--white` · `#fffdf8` — warmes Weiß, Kartenfläche (kein reines Weiß).
  /// (styles.css:8)
  static const Color white = Color(0xFFFFFDF8);

  /// `--gold` · `#caa65a` — Standard-Akzent der Karten, Sekundär-Markenfarbe.
  /// (styles.css:9)
  static const Color gold = Color(0xFFCAA65A);

  /// `--yellow` · `#f0c738` — CTA-Button, `::selection`, Aufmerksamkeit.
  /// (styles.css:10)
  static const Color yellow = Color(0xFFF0C738);

  /// `--rose` · `#b8435a` — Rose-Akzent, „geschlossen"-Status, Gefahr.
  /// (styles.css:11)
  static const Color rose = Color(0xFFB8435A);

  /// `--green` · `#2d6d55` — tiefer Grün-Akzent (Karten). (styles.css:12)
  static const Color green = Color(0xFF2D6D55);

  /// `--blue` · `#246ca0` — Blau-Akzent (Info). (styles.css:13)
  static const Color blue = Color(0xFF246CA0);

  /// `.status-pill.is-open` · `#2fad64` — helles „geöffnet"-/Positiv-Signal
  /// (Status-Punkt). Einziger Hex außerhalb von `:root`. (styles.css:351)
  static const Color openGreen = Color(0xFF2FAD64);

  /// Reines Weiß `#ffffff` — im Referenz-CSS **nur** als `rgba(255,255,255,α)`
  /// für **Glaskanten/Overlays auf dunklen (Navy-)Flächen** (z. B.
  /// `.btn-secondary` Rand @0.36 / Fläche @0.12, styles.css:207–208; Lightbox
  /// @0.18). Bewusst getrennt vom warmen [white] `#fffdf8`: auf Dunkel wirkt das
  /// warme Weiß gelbstichig, daher hier reines Weiß. Nutzung z. B.
  /// `StrichTokens.pureWhite.withValues(alpha: 0.36)` für Glasränder.
  static const Color pureWhite = Color(0xFFFFFFFF);

  /// Reines Schwarz `#000000` — im Referenz-CSS **nur** als `rgba(0,0,0,α)` in
  /// **Schlagschatten** (α 0.22–0.42, z. B. styles.css:1085). Für `BoxShadow`
  /// via `StrichTokens.shadow.withValues(alpha: …)`. Getrennt von der farbigen
  /// Marken-Schattierung `rgba(6,27,54,·)` (Navy-getönter Weichschatten, [navy]).
  static const Color shadow = Color(0xFF000000);

  // ===========================================================================
  // 2) SEMANTISCHE TOKENS — die angeforderten Rollen
  // ===========================================================================

  /// Marken-Primär = **navy**. (Im Referenzprojekt ist Navy die dominante
  /// Identitäts-/Dunkelfarbe.) Für gefüllte **Handlungs-Buttons** siehe
  /// [primaryAction] — im Referenz-CSS ist `.btn-primary` gelb, nicht navy.
  static const Color primary = navy;
  static const Color onPrimary = white; // weißer Text auf Navy (Referenz)

  /// Aktions-/CTA-Füllung = **yellow** mit **ink**-Text (Referenz `.btn-primary`,
  /// styles.css:200–203).
  static const Color primaryAction = yellow;
  static const Color onPrimaryAction = ink;

  /// Sekundär = **gold** (Standard-Kartenakzent). Dunkler Text darauf.
  static const Color secondary = gold;
  static const Color onSecondary = navy;

  /// Seitenhintergrund = **paper**; tiefere Fläche = [backgroundDeep].
  static const Color background = paper;
  static const Color backgroundDeep = paperDeep;

  /// Kartenfläche = **white** (warmes Weiß).
  static const Color surface = white;

  /// Primärtext = **ink**; auf dunklem Grund = [textOnDark].
  static const Color text = ink;
  static const Color textOnDark = paper;

  /// Gedämpfter Text = `--ink` @ 72 % (Referenz: `rgba(23,22,21,0.72)`).
  /// Auf Navy-Flächen stattdessen [mutedOnDark] verwenden.
  static Color get muted => ink.withValues(alpha: 0.72);

  /// Gedämpfter Text auf dunklem Grund = `--navy` @ 72 %
  /// (Referenz: `rgba(6,27,54,0.72)` wird auf hellem Grund genutzt; auf Navy
  /// spiegelbildlich `--paper` @ 72 %).
  static Color get mutedOnDark => paper.withValues(alpha: 0.72);

  /// Hairline-Border = `--line` = `rgba(23,22,21,0.14)` (styles.css:14).
  static Color get border => ink.withValues(alpha: 0.14);

  /// Kräftigerer Rand (Outline-Button `.btn-line`) = `rgba(6,27,54,0.28)`
  /// (styles.css:219).
  static Color get borderStrong => navy.withValues(alpha: 0.28);

  /// Karten-Rand über Navy-Tönung = `rgba(6,27,54,0.12)` (styles.css:632).
  static Color get borderCard => navy.withValues(alpha: 0.12);

  // --- Statusfarben ---------------------------------------------------------

  /// Erfolg/„geöffnet" = **openGreen** `#2fad64` (Status-Punkt). Für **gefüllte
  /// Flächen mit Text** stattdessen [successDeep] (`--green`) nehmen —
  /// `#2fad64` hat mit Weiß nur ~2.8:1 (ok als Punkt/Icon, zu wenig für Text;
  /// `--green` #2d6d55 kommt auf ~6.0:1 und ist texttauglich).
  static const Color success = openGreen;
  static const Color successDeep = green; // #2d6d55, Text-tauglich mit Weiß
  static const Color onSuccess = white;

  /// **Warnung = `--yellow` `#f0c738`** mit **ink**-Text.
  /// ⚠️ Ergänzende Zuordnung: Das Referenzprojekt hat *keinen* eigenen Warn-Token.
  /// `--yellow` ist dort aber durchgängig die Aufmerksamkeitsfarbe (CTA,
  /// `::selection` styles.css:69, Scroll-Progress-Verlauf styles.css:117) und
  /// damit die palettentreue Wahl für die MHD-/Ablauf-Warnung. Kollisionsfrei,
  /// weil die WorkTime-CTA-Rolle vom navy/teal-`primary` der App gefüllt wird —
  /// Gelb ist hier für „Warnung" frei. Weichere Vorstufe: [warningSoft] (`--gold`).
  static const Color warning = yellow;
  static const Color warningSoft = gold; // #caa65a, „bald fällig"-Vorstufe
  static const Color onWarning = ink;

  /// Gefahr/Fehler/„geschlossen" = **rose** `#b8435a` mit weißem Text.
  static const Color danger = rose;
  static const Color onDanger = white;

  /// Info = **blue** `#246ca0` mit weißem Text.
  static const Color info = blue;
  static const Color onInfo = white;

  // ===========================================================================
  // 3) VERLÄUFE — 1:1 aus dem Referenz-CSS
  // ===========================================================================

  /// Scroll-Progress-/Signal-Verlauf: gelb → rose → blau (styles.css:117).
  static const List<Color> signalGradient = <Color>[yellow, rose, blue];

  /// Die vier Karten-Akzente in Referenz-Reihenfolge (`.offer-card`
  /// accent-Klassen, styles.css:629/652/656/660): gold, rose, grün, blau.
  static const List<Color> cardAccents = <Color>[gold, rose, green, blue];
}
