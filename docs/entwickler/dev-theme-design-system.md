# Theme & Design-System

Das Erscheinungsbild ist **Material 3** mit `AppTheme.light/dark` (`lib/theme/app_theme.dart`), `fontFamily: NotoSans`. Neue UI-Bausteine leben im Design-System **V2** unter `lib/ui/`.

## ColorScheme: nur benannte Rollen

Das `ColorScheme` ist nach `fromSeed` fast komplett überschrieben. Nutzen Sie ausschließlich **benannte Rollen**:

- `surfaceContainerLow` = Card-Hintergrund
- `onSurfaceVariant` = gedämpfter Text
- `secondaryContainer` = ausgewählt

## Status-Farben nie hardcoden

> [!WARNING]
> success/warning/info **nie hardcoden** → `Theme.of(context).appColors` (ThemeExtension `AppThemeColors` in `lib/theme/theme_extensions.dart`).

## Design-Tokens

`theme_extensions.dart` liefert Tokens als ThemeExtensions, Zugriff über `BuildContext`:

- `context.spacing` (`AppSpacing`: xxs…xxl, plus Halbschritte s6/s12)
- `context.radii` (`AppRadii`: xs…xxl, pill; V2-Werte)
- `context.motion` (`AppMotion` – immer `AppMotion.resolve(context, …)` für Reduce-Motion)
- `context.elevation`, `context.iconSizes`

Für Zahlen-Rollen (Uhr, Beträge): `style.tabular` (`kTabularFigures`) – **nur gezielt**, nie global.

## lib/ui (V2)

Ein Import genügt: `package:worktime_app/ui/ui.dart` re-exportiert Tokens **und** alle V2-Komponenten (`AppCard`, `AppSectionCard`, `AppSearchField`, `AppHeroCard`, `AppErrorState`, `AppOfflineBanner`, …). V2-Komponenten konsumieren **nur Tokens** – kein Hex, keine festen dp.

> [!NOTE]
> Reuse-Widgets in `home_screen.dart` (`_SectionCard`, `_EmptyState`, `_InfoChip`, …) sind file-private → nicht importierbar. Bei Bedarf nach `lib/widgets/` bzw. `lib/ui/` heben statt kopieren.

## Strichmännchen-Rebrand

Es gibt ein opt-in **Strichmännchen-Theme** (`AppThemeColors.strichmaennchenLight/Dark`, `StrichTokens`), das die Store-Palette 1:1 übernimmt und das DS2-Kontrast-Gate (`test/contrast_audit_test.dart`) erfüllt. Der app-weite Flip ist vorbereitet, aber noch nicht Default.

## Weiter

- [Überblick & Tech-Stack](article:dev-ueberblick-tech-stack)
- [Beitragen & Konventionen](article:dev-beitragen-konventionen)
