import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/redesign_flags.dart';
import '../../providers/theme_provider.dart';
import '../../widgets/breadcrumb_app_bar.dart';

/// Unterseite „Erscheinungsbild" des Einstellungs-Hubs: Farbschema
/// (System/Hell/Dunkel) und — nur im Entwicklungsmodus — der Redesign-Schalter.
///
/// Der Modus lässt sich zusätzlich mit einem Tap über den Sonne/Mond-Knopf in
/// der App-Leiste bzw. Navigations-Rail wechseln.
class SettingsAppearanceScreen extends StatelessWidget {
  const SettingsAppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: 'Einstellungen',
            onTap: () => Navigator.of(context).pop(),
          ),
          const BreadcrumbItem(label: 'Erscheinungsbild'),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Farbschema',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Bestimmt, ob die App hell oder dunkel dargestellt wird. '
                  '„System" folgt der Einstellung deines Geräts.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
                const _ThemeSelector(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tipp: Der Sonne/Mond-Knopf oben in der App-Leiste '
                        'wechselt hell/dunkel mit einem Tap.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                  ],
                ),
                const _RedesignToggle(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector();

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final current = themeProvider.themeMode;
    final options = [
      (ThemeMode.system, Icons.brightness_auto, 'System'),
      (ThemeMode.light, Icons.light_mode, 'Hell'),
      (ThemeMode.dark, Icons.dark_mode, 'Dunkel'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: options.map((option) {
            final (mode, icon, label) = option;
            final selected = current == mode;
            final colorScheme = Theme.of(context).colorScheme;
            return Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => themeProvider.setThemeMode(mode),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.all(4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: selected
                        ? colorScheme.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        color: selected
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: TextStyle(
                          color: selected
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// Laufzeit-Schalter fuer das Signal-Teal-Redesign (nur im Demo-/Dev-Modus
/// sichtbar). Setzt den persistierten Override in [ThemeProvider]; Theme und
/// flag-gegatete Screens schalten live um (kein Neustart, kein dart-define).
class _RedesignToggle extends StatelessWidget {
  const _RedesignToggle();

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.disableAuthentication && !kDebugMode) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    final on = RedesignFlags.isOn(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: SwitchListTile(
          value: on,
          onChanged: (value) =>
              context.read<ThemeProvider>().setRedesignV2Override(value),
          title: const Text('Neues Design (Signal Teal)'),
          subtitle: const Text(
            'Vorschau des Redesigns — live umschaltbar (nur Entwicklungsmodus).',
          ),
          secondary: Icon(Icons.auto_awesome, color: colorScheme.primary),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
      ),
    );
  }
}
