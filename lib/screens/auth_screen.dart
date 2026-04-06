import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/local_demo_data.dart';
import '../models/app_user.dart';
import '../providers/auth_provider.dart';
import '../widgets/app_logo.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  final _activateEmailController = TextEditingController();
  final _activatePasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _activateEmailController.dispose();
    _activatePasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 760;
                final intro = _IntroPanel(colorScheme: colorScheme);
                final form = _AuthCard(
                  tabController: _tabController,
                  loginEmailController: _loginEmailController,
                  loginPasswordController: _loginPasswordController,
                  activateEmailController: _activateEmailController,
                  activatePasswordController: _activatePasswordController,
                );

                if (stacked) {
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      intro,
                      const SizedBox(height: 20),
                      form,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: intro),
                    const SizedBox(width: 24),
                    Expanded(child: form),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _IntroPanel extends StatelessWidget {
  const _IntroPanel({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primary,
            colorScheme.secondary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: colorScheme.onPrimary.withValues(alpha: 0.12),
              ),
            ),
            child: const AppLogo(height: 86),
          ),
          const SizedBox(height: 28),
          Text(
            'Arbeitszeiten erfassen, Schichten planen und das Team im Blick behalten.',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          Text(
            'Die Software unterstuetzt bei Zeiterfassung, Einsatzplanung, '
            'Abwesenheiten und Auswertungen. So bleiben Arbeitsablaeufe '
            'uebersichtlich und wichtige Informationen schnell verfuegbar.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onPrimary.withValues(alpha: 0.92),
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 24),
          const _FeatureItem(
            icon: Icons.badge_outlined,
            title: 'Zeiterfassung',
            text: 'Arbeitsbeginn, Pausen und Arbeitsende sauber dokumentieren.',
          ),
          const SizedBox(height: 12),
          const _FeatureItem(
            icon: Icons.schedule_outlined,
            title: 'Schichtplanung',
            text:
                'Einsaetze uebersichtlich planen und Verfuegbarkeiten oder Abwesenheiten direkt beruecksichtigen.',
          ),
          const SizedBox(height: 12),
          const _FeatureItem(
            icon: Icons.insights_outlined,
            title: 'Auswertungen',
            text:
                'Monatsberichte, Uebersichten und Exporte fuer Verwaltung und Nachweise nutzen.',
          ),
        ],
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  const _FeatureItem({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colorScheme.onPrimary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: colorScheme.onPrimary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onPrimary.withValues(alpha: 0.92),
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AuthCard extends StatelessWidget {
  const _AuthCard({
    required this.tabController,
    required this.loginEmailController,
    required this.loginPasswordController,
    required this.activateEmailController,
    required this.activatePasswordController,
  });

  final TabController tabController;
  final TextEditingController loginEmailController;
  final TextEditingController loginPasswordController;
  final TextEditingController activateEmailController;
  final TextEditingController activatePasswordController;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Anmeldung',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Melde dich an, um Zeiten zu erfassen, Schichten einzusehen und Teamfunktionen zu nutzen.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            if (auth.errorMessage != null) ...[
              const SizedBox(height: 16),
              _ErrorBanner(
                message: auth.errorMessage!,
                onDismiss: auth.clearError,
              ),
            ],
            if (auth.authDisabled) ...[
              const SizedBox(height: 18),
              _LocalDemoAccountsSection(
                accounts: auth.localDemoAccounts,
              ),
              const SizedBox(height: 18),
              _EmailLoginForm(
                emailController: loginEmailController,
                passwordController: loginPasswordController,
                submitLabel: 'Mit Demo-Account anmelden',
              ),
            ] else ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: auth.busy ? null : () => auth.signInWithGoogle(),
                icon: const Icon(Icons.login),
                label: const Text('Mit Google anmelden'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
              const SizedBox(height: 18),
              TabBar(
                controller: tabController,
                tabs: const [
                  Tab(text: 'Login'),
                  Tab(text: 'Einladung'),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 340,
                child: TabBarView(
                  controller: tabController,
                  children: [
                    _EmailLoginForm(
                      emailController: loginEmailController,
                      passwordController: loginPasswordController,
                    ),
                    _InvitationActivationForm(
                      emailController: activateEmailController,
                      passwordController: activatePasswordController,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmailLoginForm extends StatefulWidget {
  const _EmailLoginForm({
    required this.emailController,
    required this.passwordController,
    this.submitLabel = 'Mit E-Mail anmelden',
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final String submitLabel;

  @override
  State<_EmailLoginForm> createState() => _EmailLoginFormState();
}

class _EmailLoginFormState extends State<_EmailLoginForm> {
  final _formKey = GlobalKey<FormState>();

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            controller: widget.emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'E-Mail',
              prefixIcon: Icon(Icons.mail_outline),
            ),
            validator: (value) {
              if (value == null || !_emailRegex.hasMatch(value.trim())) {
                return 'Bitte eine gueltige E-Mail-Adresse eingeben';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: widget.passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Passwort',
              prefixIcon: Icon(Icons.lock_outline),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Bitte ein Passwort eingeben';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: auth.busy
                ? null
                : () {
                    if (!_formKey.currentState!.validate()) return;
                    auth.signInWithEmailPassword(
                      email: widget.emailController.text,
                      password: widget.passwordController.text,
                    );
                  },
            icon: auth.busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            label: Text(widget.submitLabel),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalDemoAccountsSection extends StatelessWidget {
  const _LocalDemoAccountsSection({
    required this.accounts,
  });

  final List<LocalDemoAccount> accounts;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Lokale Demo-Profile',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Im Entwicklungsmodus kannst du dich direkt als Admin oder Mitarbeiter anmelden.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 14),
          for (final account in accounts) ...[
            _LocalDemoAccountTile(account: account),
            if (account != accounts.last) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _LocalDemoAccountTile extends StatelessWidget {
  const _LocalDemoAccountTile({
    required this.account,
  });

  final LocalDemoAccount account;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            account.name,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            account.role.label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          Text('E-Mail: ${account.email}'),
          Text('Passwort: ${account.password}'),
          const SizedBox(height: 6),
          Text(
            account.description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: auth.busy
                  ? null
                  : () => auth.signInWithLocalDemoProfile(account.uid),
              icon: const Icon(Icons.login),
              label: Text('Als ${account.role.label} anmelden'),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvitationActivationForm extends StatefulWidget {
  const _InvitationActivationForm({
    required this.emailController,
    required this.passwordController,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;

  @override
  State<_InvitationActivationForm> createState() =>
      _InvitationActivationFormState();
}

class _InvitationActivationFormState extends State<_InvitationActivationForm> {
  final _formKey = GlobalKey<FormState>();
  final _confirmPasswordController = TextEditingController();

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            controller: widget.emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'E-Mail aus der Einladung',
              prefixIcon: Icon(Icons.mail_outline),
            ),
            validator: (value) {
              if (value == null || !_emailRegex.hasMatch(value.trim())) {
                return 'Bitte eine gueltige E-Mail-Adresse eingeben';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: widget.passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Neues Passwort',
              prefixIcon: Icon(Icons.lock_reset_outlined),
            ),
            validator: (value) {
              if (value == null || value.length < 6) {
                return 'Mindestens 6 Zeichen erforderlich';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Passwort bestaetigen',
              prefixIcon: Icon(Icons.lock_outline),
            ),
            validator: (value) {
              if (value != widget.passwordController.text) {
                return 'Passwoerter stimmen nicht ueberein';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          Text(
            'Der Account wird nur angelegt, wenn eine aktive Admin-Einladung fuer diese E-Mail existiert.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: auth.busy
                ? null
                : () {
                    if (!_formKey.currentState!.validate()) return;
                    auth.activateInvite(
                      email: widget.emailController.text,
                      password: widget.passwordController.text,
                    );
                  },
            icon: auth.busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.person_add_alt_1),
            label: const Text('Einladung aktivieren'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, this.onDismiss});

  final String message;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline,
              color: colorScheme.onErrorContainer, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: colorScheme.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              icon: Icon(Icons.close,
                  size: 18, color: colorScheme.onErrorContainer),
              onPressed: onDismiss,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Schliessen',
            ),
        ],
      ),
    );
  }
}

class FirebaseSetupScreen extends StatelessWidget {
  const FirebaseSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: AppLogo(height: 92),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Anmeldung derzeit nicht verfuegbar',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Die Anwendung kann in dieser Umgebung noch nicht fuer die Anmeldung bereitgestellt werden.',
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Bitte wende dich an die zustaendige Person, damit die Bereitstellung abgeschlossen wird.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AccessBlockedScreen extends StatelessWidget {
  const AccessBlockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_person_outlined, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Konto deaktiviert',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Dieses Benutzerkonto wurde durch einen Admin deaktiviert. Bitte wende dich an die Verwaltung.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => context.read<AuthProvider>().signOut(),
                    child: const Text('Abmelden'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
