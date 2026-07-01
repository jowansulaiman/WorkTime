import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/notification_prefs.dart';
import '../providers/auth_provider.dart';

/// Push-Einstellungen (M5): Master-Schalter, Kategorie-Schalter (deckungsgleich
/// mit den fünf Android-Channels) und Ruhezeiten. Persistiert über
/// `AuthProvider.updateNotificationPrefs` ins eigene `users/{uid}`-Doc; der
/// Server respektiert die Präferenzen vor dem Versand.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late NotificationPrefs _prefs;

  @override
  void initState() {
    super.initState();
    _prefs = context.read<AuthProvider>().profile?.notificationPrefs ??
        const NotificationPrefs();
  }

  void _apply(NotificationPrefs next) {
    setState(() => _prefs = next);
    context.read<AuthProvider>().updateNotificationPrefs(next);
  }

  Future<void> _pickQuietTime({required bool start}) async {
    final initialMinutes =
        start ? _prefs.quietStartMinutes : _prefs.quietEndMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
          hour: initialMinutes ~/ 60, minute: initialMinutes % 60),
    );
    if (picked == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    _apply(start
        ? _prefs.copyWith(quietStartMinutes: minutes)
        : _prefs.copyWith(quietEndMinutes: minutes));
  }

  @override
  Widget build(BuildContext context) {
    final master = _prefs.masterEnabled;
    String fmt(int minutes) =>
        TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60).format(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Benachrichtigungen')),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  child: SwitchListTile(
                    value: master,
                    onChanged: (v) =>
                        _apply(_prefs.copyWith(masterEnabled: v)),
                    title: const Text('Push-Benachrichtigungen'),
                    subtitle:
                        const Text('Mitteilungen auf dieses Gerät senden.'),
                    secondary: const Icon(Icons.notifications_active_outlined),
                  ),
                ),
                const SizedBox(height: 20),
                _sectionTitle(context, 'Kategorien'),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _category(
                        'Genehmigungen',
                        'Abwesenheits- und Tauschanträge.',
                        _prefs.genehmigungen,
                        (v) => _apply(_prefs.copyWith(genehmigungen: v)),
                        master,
                      ),
                      const Divider(height: 1),
                      _category(
                        'Schichtplan',
                        'Veröffentlichte und geänderte Schichten.',
                        _prefs.schichtplan,
                        (v) => _apply(_prefs.copyWith(schichtplan: v)),
                        master,
                      ),
                      const Divider(height: 1),
                      _category(
                        'Aufgaben & Kühlschrank',
                        'Operative To-dos und Feedback.',
                        _prefs.aufgaben,
                        (v) => _apply(_prefs.copyWith(aufgaben: v)),
                        master,
                      ),
                      const Divider(height: 1),
                      _category(
                        'Kundenwünsche',
                        'Neue Kundenwünsche zum Vorbereiten.',
                        _prefs.kundenwuensche,
                        (v) => _apply(_prefs.copyWith(kundenwuensche: v)),
                        master,
                      ),
                      const Divider(height: 1),
                      _category(
                        'Bestand & Nachbestellung',
                        'Artikel unter Meldebestand.',
                        _prefs.bestand,
                        (v) => _apply(_prefs.copyWith(bestand: v)),
                        master,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _sectionTitle(context, 'Ruhezeiten'),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: _prefs.quietHoursEnabled,
                        onChanged: master
                            ? (v) => _apply(
                                _prefs.copyWith(quietHoursEnabled: v))
                            : null,
                        title: const Text('Nicht stören'),
                        subtitle: const Text(
                            'Nur „Genehmigungen" kommen während dieser Zeit.'),
                        secondary: const Icon(Icons.bedtime_outlined),
                      ),
                      if (_prefs.quietHoursEnabled && master) ...[
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.nightlight_outlined),
                          title: const Text('Von'),
                          trailing: Text(fmt(_prefs.quietStartMinutes)),
                          onTap: () => _pickQuietTime(start: true),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.wb_sunny_outlined),
                          title: const Text('Bis'),
                          trailing: Text(fmt(_prefs.quietEndMinutes)),
                          onTap: () => _pickQuietTime(start: false),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Alle Vorgänge findest du auch unter „Anfragen". '
                  'Push ist nur der Auslöser.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _category(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
    bool enabled,
  ) {
    return SwitchListTile(
      value: value && enabled,
      onChanged: enabled ? onChanged : null,
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
        ),
      );
}
