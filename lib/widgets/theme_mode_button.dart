import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';

/// Kompakter Hell/Dunkel-Umschalter für App-Leiste und Navigations-Rail.
///
/// So ist das Erscheinungsbild ohne Umweg über die Einstellungen erreichbar:
/// - **Tippen** wechselt sofort zwischen hellem und dunklem Design (bezogen auf
///   die aktuell wirksame Helligkeit — bei „System" also auf die Plattform).
/// - **Langes Drücken** (oder **Rechtsklick**) öffnet die explizite Auswahl
///   *System · Hell · Dunkel* mit Häkchen am aktiven Modus.
///
/// Liest [ThemeProvider] direkt aus dem Provider-Baum; nur in Bereichen
/// einsetzen, die den Provider-Stack sehen (App-Shell), nicht in isolierten,
/// provider-losen Widget-Tests.
class ThemeModeButton extends StatelessWidget {
  const ThemeModeButton({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<ThemeProvider>().themeMode;
    // Eine einzige Gesten-Oberfläche (InkResponse) besitzt Tap, Langdruck und
    // Rechtsklick — ein verschachtelter IconButton würde sich sonst in der
    // Gesten-Arena um den Langdruck streiten. 48px-Trefferzone bleibt erhalten.
    return Tooltip(
      message: 'Design: ${themeModeLabel(mode)}\n'
          'Tippen wechselt hell/dunkel · lang drücken für Optionen',
      child: InkResponse(
        radius: 22,
        onTap: () => _quickToggle(context, mode),
        onLongPress: () => showThemeModeMenu(context),
        onSecondaryTap: () => showThemeModeMenu(context),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(child: Icon(themeModeIcon(mode))),
        ),
      ),
    );
  }

  /// Wechselt hart zwischen Hell und Dunkel — ausgehend von der *wirksamen*
  /// Helligkeit. Bei [ThemeMode.system] wird die Plattform-Helligkeit gespiegelt,
  /// damit der Tap immer „auf das andere Aussehen" schaltet.
  void _quickToggle(BuildContext context, ThemeMode mode) {
    final provider = context.read<ThemeProvider>();
    final effectiveDark = switch (mode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system =>
        MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };
    provider.setThemeMode(effectiveDark ? ThemeMode.light : ThemeMode.dark);
  }
}

/// Icon für den jeweiligen Theme-Modus.
IconData themeModeIcon(ThemeMode mode) => switch (mode) {
      ThemeMode.system => Icons.brightness_auto_outlined,
      ThemeMode.light => Icons.light_mode_outlined,
      ThemeMode.dark => Icons.dark_mode_outlined,
    };

/// Deutsches Label für den jeweiligen Theme-Modus.
String themeModeLabel(ThemeMode mode) => switch (mode) {
      ThemeMode.system => 'System',
      ThemeMode.light => 'Hell',
      ThemeMode.dark => 'Dunkel',
    };

/// Öffnet die explizite Modus-Auswahl (System · Hell · Dunkel) als Popup-Menü,
/// verankert am aufrufenden Widget. Setzt die Auswahl über [ThemeProvider].
Future<void> showThemeModeMenu(BuildContext context) async {
  final provider = context.read<ThemeProvider>();
  final current = provider.themeMode;
  final colorScheme = Theme.of(context).colorScheme;

  final box = context.findRenderObject() as RenderBox?;
  final overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null) {
    return;
  }
  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  final bottomRight =
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay);
  final position = RelativeRect.fromLTRB(
    topLeft.dx,
    bottomRight.dy,
    overlay.size.width - bottomRight.dx,
    overlay.size.height - bottomRight.dy,
  );

  final selected = await showMenu<ThemeMode>(
    context: context,
    position: position,
    items: [
      for (final mode in ThemeMode.values)
        PopupMenuItem<ThemeMode>(
          value: mode,
          child: Row(
            children: [
              Icon(
                themeModeIcon(mode),
                size: 20,
                color: mode == current
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Text(themeModeLabel(mode)),
              if (mode == current) ...[
                const Spacer(),
                Icon(Icons.check_rounded, size: 18, color: colorScheme.primary),
              ],
            ],
          ),
        ),
    ],
  );

  if (selected != null) {
    await provider.setThemeMode(selected);
  }
}
