import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/work_provider.dart';
import '../../routing/shell_tab.dart';
import '../../widgets/account_delete_confirm_dialog.dart';
import '../../widgets/breadcrumb_app_bar.dart';

/// Unterseite „Konto & Profil" des Einstellungs-Hubs: Anzeigename und der
/// Absprung in „Meine Akte". Persönliche Stammdaten (Lohn/Urlaub/Sollzeit)
/// bleiben bewusst in der Personalakte.
class SettingsProfileScreen extends StatefulWidget {
  const SettingsProfileScreen({super.key});

  @override
  State<SettingsProfileScreen> createState() => _SettingsProfileScreenState();
}

class _SettingsProfileScreenState extends State<SettingsProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  bool _saving = false;
  bool _deleting = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    _nameCtrl = TextEditingController(
      text: context.read<WorkProvider>().settings.name,
    );
    _initialized = true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AuthProvider>().profile;
    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: 'Einstellungen',
            onTap: () => Navigator.of(context).pop(),
          ),
          const BreadcrumbItem(label: 'Konto & Profil'),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (currentUser != null) ...[
                    _AccountInfoCard(user: currentUser),
                    const SizedBox(height: 20),
                  ],
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Anzeigename',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Personaldaten (Stammdaten/Urlaub/Lohn/Dokumente) liegen in
                  // der eigenen Akte — hier nur der Absprung.
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(Icons.badge_outlined),
                      title: const Text('Meine Akte'),
                      subtitle: const Text(
                          'Stammdaten, Urlaub, Lohnabrechnungen & '
                          'Dokumente einsehen.'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(AppRoutes.meineAkte),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator.adaptive(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(_saving ? 'Wird gespeichert...' : 'Speichern'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                  const SizedBox(height: 32),
                  _buildDangerZone(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Gefahrenzone: das eigene Konto **komplett** löschen (Plan
  /// `plan/account-loeschung.md`). Bewusst deutlich vom übrigen Formular
  /// abgesetzt; irreversibel, daher Reauth + destruktive Bestätigung.
  Widget _buildDangerZone(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_outlined,
                    color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Text(
                  'Gefahrenzone',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Dein Konto und alle persönlichen Daten werden unwiderruflich '
              'gelöscht. Gesetzlich aufbewahrungspflichtige Zeit- und '
              'Lohndaten bleiben anonymisiert erhalten. Dieser Schritt kann '
              'nicht rückgängig gemacht werden.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                icon: _deleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_forever_outlined),
                label: Text(_deleting ? 'Wird gelöscht...' : 'Konto löschen'),
                onPressed: _deleting ? null : _deleteAccount,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteAccount() async {
    final auth = context.read<AuthProvider>();
    final result = await AccountDeleteConfirmDialog.show(
      context,
      needsPassword: auth.primaryProviderId == 'password',
      message: 'Dieser Schritt ist unwiderruflich. Persönliche Daten werden '
          'gelöscht, aufbewahrungspflichtige Zeit-/Lohndaten anonymisiert.',
    );
    if (result == null || !result.confirmed || !mounted) {
      return;
    }

    setState(() => _deleting = true);
    try {
      // 1) Identität neu bestätigen (Sicherheits-Gate).
      final reauthed = await auth.reauthenticate(password: result.password);
      if (!reauthed) {
        if (mounted) {
          _showError(auth.errorMessage ?? 'Bestätigung fehlgeschlagen.');
        }
        return;
      }
      // 2) Konto löschen. Bei Erfolg leitet das Router-Gate automatisch auf
      // die Anmeldung um (profile == null) — dieser Screen wird entfernt.
      final ok = await auth.deleteOwnAccount();
      if (!ok && mounted) {
        _showError(auth.errorMessage ?? 'Konto konnte nicht gelöscht werden.');
      }
    } finally {
      if (mounted) {
        setState(() => _deleting = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _saving = true);

    // Nur den Anzeigenamen ändern. Personaldaten (Stundenlohn/Urlaub/Soll-
    // Stunden/Währung) gehören dem Personalbereich — die bestehenden Werte
    // werden unverändert mitgeschrieben, damit der Rules-Pin (PA-0.3,
    // `settingsPayrollFieldsUnchanged`) das Self-Update nicht verweigert.
    final work = context.read<WorkProvider>();
    final updated = work.settings.copyWith(name: _nameCtrl.text.trim());

    try {
      await work.updateSettings(updated);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Profil gespeichert'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler beim Speichern: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

class _AccountInfoCard extends StatelessWidget {
  const _AccountInfoCard({required this.user});

  final AppUserProfile user;

  @override
  Widget build(BuildContext context) {
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
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Text(user.email),
                  Text(
                    '${user.role.label} · Organisation ${user.orgId}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
