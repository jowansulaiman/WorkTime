import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_user.dart';
import '../providers/auth_provider.dart';
import '../providers/storage_mode_provider.dart';
import '../providers/theme_provider.dart';
import '../ui/app_quick_action.dart';
import '../widgets/breadcrumb_app_bar.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/theme_mode_button.dart';
import 'kiosk/kiosk_pin_setup_sheet.dart';
import 'notification_settings_screen.dart';
import 'settings/settings_appearance_screen.dart';
import 'settings/settings_org_screen.dart';
import 'settings/settings_profile_screen.dart';
import 'settings/settings_storage_screen.dart';
import 'settings/settings_timeclock_screen.dart';

/// Einstellungs-Hub: gruppiert alle Einstellungen als Kacheln, jede öffnet eine
/// fokussierte Unterseite. Ersetzt die frühere lange Scroll-Seite; die
/// Detail-Formulare liegen jetzt in `lib/screens/settings/`.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    this.parentLabel = 'Profil',
  });

  final String parentLabel;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.profile;
    final themeMode = context.watch<ThemeProvider>().themeMode;
    final storageLocation = context.watch<StorageModeProvider>().location;
    final colorScheme = Theme.of(context).colorScheme;

    void openPage(Widget page) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => page),
      );
    }

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: parentLabel,
            onTap: () => Navigator.of(context).pop(),
          ),
          const BreadcrumbItem(label: 'Einstellungen'),
        ],
        // Hell/Dunkel auch direkt aus dem Einstellungs-Hub erreichbar.
        actions: const [ThemeModeButton()],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Einstellungen',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Persoenliche Vorgaben, Erscheinungsbild und lokale Optionen — '
                  'nach Bereichen sortiert.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 20),
                if (user != null) ...[
                  _IdentityCard(user: user),
                  const SizedBox(height: 20),
                ],
                AdaptiveCardGrid(
                  minItemWidth: 240,
                  children: [
                    AppQuickActionCard(
                      icon: Icons.person_outline,
                      title: 'Konto & Profil',
                      subtitle: 'Anzeigename und Absprung in „Meine Akte".',
                      onTap: () => openPage(const SettingsProfileScreen()),
                    ),
                    AppQuickActionCard(
                      icon: themeModeIcon(themeMode),
                      title: 'Erscheinungsbild',
                      subtitle:
                          'Hell, Dunkel oder System · aktuell: ${themeModeLabel(themeMode)}.',
                      onTap: () => openPage(const SettingsAppearanceScreen()),
                    ),
                    AppQuickActionCard(
                      icon: Icons.notifications_outlined,
                      title: 'Benachrichtigungen',
                      subtitle: 'Kategorien und Ruhezeiten festlegen.',
                      onTap: () =>
                          openPage(const NotificationSettingsScreen()),
                    ),
                    AppQuickActionCard(
                      icon: Icons.schedule_outlined,
                      title: 'Stempeluhr & Vorlagen',
                      subtitle:
                          'Auto-Pause und persönliche Arbeitszeit-Vorlagen.',
                      onTap: () => openPage(const SettingsTimeclockScreen()),
                    ),
                    AppQuickActionCard(
                      icon: Icons.dns_outlined,
                      title: 'Datenspeicher',
                      subtitle:
                          'Hybrid, Cloud oder nur lokal · aktuell: ${_storageLabel(storageLocation)}.',
                      onTap: () => openPage(const SettingsStorageScreen()),
                    ),
                    AppQuickActionCard(
                      icon: Icons.password_outlined,
                      title: 'Arbeitsmodus',
                      subtitle: 'Kiosk-PIN für das Laden-Tablet festlegen.',
                      onTap: () => showKioskPinSetupSheet(context),
                    ),
                    if (user?.isAdmin ?? false)
                      AppQuickActionCard(
                        icon: Icons.tune_outlined,
                        title: 'Organisation',
                        subtitle:
                            'Automatische Schichtverteilung & MwSt (nur Admin).',
                        onTap: () => openPage(const SettingsOrgScreen()),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                const _InfoCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _storageLabel(DataStorageLocation location) => switch (location) {
      DataStorageLocation.hybrid => 'Hybrid',
      DataStorageLocation.cloud => 'Cloud',
      DataStorageLocation.local => 'Nur lokal',
    };

/// Kompakte Identitäts-Karte oben im Hub (Avatar, Name, Rolle, Organisation).
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.user});

  final AppUserProfile user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              child: Text(
                user.displayName.isEmpty
                    ? '?'
                    : user.displayName.substring(0, 1).toUpperCase(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(user.email),
                  Text(
                    '${user.role.label} · Organisation ${user.orgId}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Persoenliche Daten (Stammdaten, Urlaub, Lohn, Dokumente) stehen in '
          '„Meine Akte". Rollen, Einladungen und Organisation pflegt der Admin '
          'im Personalbereich.',
        ),
      ),
    );
  }
}
