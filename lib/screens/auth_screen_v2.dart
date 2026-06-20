import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/local_demo_data.dart';
import '../models/app_user.dart';
import '../providers/auth_provider.dart';
import '../ui/ui.dart';

/// Signal-Teal-Redesign (`redesign_v2`) des Anmelde-Flows. M3-Expressive-Optik
/// auf Basis der V2-Tokens + `lib/ui`-Komponenten. **Funktion identisch** zu
/// [AuthScreen] (V1): gleiche AuthProvider-Aufrufe, gleiche Validatoren, gleiche
/// deutschen Texte, gleiche Responsiveness. Umschaltung am Einstiegspunkt
/// (`_AuthGate`) per Flag.
class AuthScreenV2 extends StatefulWidget {
  const AuthScreenV2({super.key});

  @override
  State<AuthScreenV2> createState() => _AuthScreenV2State();
}

class _AuthScreenV2State extends State<AuthScreenV2> {
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  final _activateEmailController = TextEditingController();
  final _activatePasswordController = TextEditingController();
  int _tab = 0; // 0 = Login, 1 = Einladung

  @override
  void dispose() {
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _activateEmailController.dispose();
    _activatePasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final pagePadding = MobileBreakpoints.screenPadding(context);

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.secondaryContainer.withValues(alpha: 0.45),
              colorScheme.surface,
              colorScheme.primaryContainer.withValues(alpha: 0.28),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              pagePadding.left,
              context.spacing.lg,
              pagePadding.right,
              context.spacing.lg,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 760;
                    const intro = _IntroPanelV2();
                    final form = _AuthCardV2(
                      tab: _tab,
                      onTabChanged: (value) => setState(() => _tab = value),
                      loginEmailController: _loginEmailController,
                      loginPasswordController: _loginPasswordController,
                      activateEmailController: _activateEmailController,
                      activatePasswordController: _activatePasswordController,
                    );

                    if (stacked) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          intro,
                          SizedBox(height: context.spacing.md + context.spacing.xxs),
                          form,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Expanded(child: intro),
                        SizedBox(width: context.spacing.lg),
                        Expanded(child: form),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IntroPanelV2 extends StatelessWidget {
  const _IntroPanelV2();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        final spacing = context.spacing;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [colorScheme.primary, colorScheme.secondary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(context.radii.xxl),
          ),
          padding: EdgeInsets.all(compact ? spacing.lg - spacing.xs : spacing.lg + spacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _OnPrimaryPill(
                label: 'Digitale Arbeitsorganisation',
                colorScheme: colorScheme,
                textTheme: textTheme,
              ),
              SizedBox(height: spacing.md + spacing.xxs),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? spacing.md - spacing.xxs : spacing.md + spacing.xxs,
                  vertical: compact ? spacing.md - spacing.xxs : spacing.md,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(context.radii.xl),
                  border: Border.all(
                    color: colorScheme.onPrimary.withValues(alpha: 0.12),
                  ),
                ),
                child: AppLogo(height: compact ? 72 : 86),
              ),
              SizedBox(height: spacing.lg),
              Text(
                'Arbeitszeiten erfassen, Schichten planen und das Team im Blick behalten.',
                style: (compact ? textTheme.headlineSmall : textTheme.headlineMedium)
                    ?.copyWith(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: spacing.md - spacing.xxs),
              Text(
                'Die Software unterstuetzt bei Zeiterfassung, Einsatzplanung, '
                'Abwesenheiten und Auswertungen. So bleiben Arbeitsablaeufe '
                'uebersichtlich und wichtige Informationen schnell verfuegbar.',
                style: textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onPrimary.withValues(alpha: 0.92),
                  height: 1.35,
                ),
              ),
              SizedBox(height: spacing.lg),
              const _FeatureItemV2(
                icon: Icons.badge_outlined,
                title: 'Zeiterfassung',
                text: 'Arbeitsbeginn, Pausen und Arbeitsende sauber dokumentieren.',
              ),
              SizedBox(height: spacing.sm + spacing.xs),
              const _FeatureItemV2(
                icon: Icons.schedule_outlined,
                title: 'Schichtplanung',
                text: 'Einsaetze uebersichtlich planen und Verfuegbarkeiten oder Abwesenheiten direkt beruecksichtigen.',
              ),
              SizedBox(height: spacing.sm + spacing.xs),
              const _FeatureItemV2(
                icon: Icons.insights_outlined,
                title: 'Auswertungen',
                text: 'Monatsberichte, Uebersichten und Exporte fuer Verwaltung und Nachweise nutzen.',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OnPrimaryPill extends StatelessWidget {
  const _OnPrimaryPill({
    required this.label,
    required this.colorScheme,
    required this.textTheme,
  });

  final String label;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.spacing.sm + context.spacing.xs,
        vertical: context.spacing.sm,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(context.radii.pill),
      ),
      child: Text(
        label,
        style: textTheme.labelLarge?.copyWith(
          color: colorScheme.onPrimary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _FeatureItemV2 extends StatelessWidget {
  const _FeatureItemV2({
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
    final textTheme = Theme.of(context).textTheme;
    final spacing = context.spacing;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md - spacing.xxs),
      decoration: BoxDecoration(
        color: colorScheme.onPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(context.radii.lg),
        border: Border.all(color: colorScheme.onPrimary.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(spacing.sm + spacing.xxs),
            decoration: BoxDecoration(
              color: colorScheme.onPrimary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(context.radii.md),
            ),
            child: Icon(icon, color: colorScheme.onPrimary),
          ),
          SizedBox(width: spacing.sm + spacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.titleMedium?.copyWith(
                    color: colorScheme.onPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: spacing.xxs),
                Text(
                  text,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onPrimary.withValues(alpha: 0.92),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthCardV2 extends StatelessWidget {
  const _AuthCardV2({
    required this.tab,
    required this.onTabChanged,
    required this.loginEmailController,
    required this.loginPasswordController,
    required this.activateEmailController,
    required this.activatePasswordController,
  });

  final int tab;
  final ValueChanged<int> onTabChanged;
  final TextEditingController loginEmailController;
  final TextEditingController loginPasswordController;
  final TextEditingController activateEmailController;
  final TextEditingController activatePasswordController;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final spacing = context.spacing;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;

        return AppCard(
          padding: EdgeInsets.all(compact ? spacing.md + spacing.xxs : spacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: spacing.sm + spacing.xs,
                  vertical: spacing.sm,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(context.radii.pill),
                ),
                child: Text(
                  auth.authDisabled ? 'Demo-Zugang' : 'Sicherer Zugang',
                  style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              SizedBox(height: spacing.md),
              Text(
                'Anmeldung',
                style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              SizedBox(height: spacing.sm),
              Text(
                'Melde dich an, um Zeiten zu erfassen, Schichten einzusehen und Teamfunktionen zu nutzen.',
                style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              if (auth.errorMessage != null) ...[
                SizedBox(height: spacing.md),
                AppStatusBanner(
                  icon: Icons.error_outline,
                  message: auth.errorMessage!,
                  tone: AppStatusTone.error,
                  action: IconButton(
                    icon: Icon(Icons.close, size: context.iconSizes.sm),
                    onPressed: auth.clearError,
                    tooltip: 'Schliessen',
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
              if (auth.authDisabled) ...[
                SizedBox(height: spacing.md + spacing.xxs),
                _DemoAccountsV2(accounts: auth.localDemoAccounts),
                SizedBox(height: spacing.md + spacing.xxs),
                _EmailLoginFormV2(
                  emailController: loginEmailController,
                  passwordController: loginPasswordController,
                  submitLabel: 'Mit Demo-Account anmelden',
                ),
              ] else ...[
                SizedBox(height: spacing.md + spacing.xxs),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: auth.busy ? null : () => auth.signInWithGoogle(),
                    icon: const Icon(Icons.login),
                    label: const Text('Mit Google anmelden'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ),
                SizedBox(height: spacing.md + spacing.xxs),
                AppSegmented<int>(
                  selected: tab,
                  onChanged: onTabChanged,
                  segments: const [
                    AppSegment(value: 0, label: 'Login'),
                    AppSegment(value: 1, label: 'Einladung'),
                  ],
                ),
                SizedBox(height: spacing.md - spacing.xxs),
                AnimatedSwitcher(
                  duration: AppMotion.resolve(context, context.motion.short),
                  switchInCurve: context.motion.emphasizedEnter,
                  switchOutCurve: context.motion.emphasizedExit,
                  child: KeyedSubtree(
                    key: ValueKey(tab),
                    child: tab == 0
                        ? _EmailLoginFormV2(
                            emailController: loginEmailController,
                            passwordController: loginPasswordController,
                          )
                        : _InvitationActivationFormV2(
                            emailController: activateEmailController,
                            passwordController: activatePasswordController,
                          ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Gemeinsame E-Mail-Validierung (identisch zu V1).
final RegExp _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

class _EmailLoginFormV2 extends StatefulWidget {
  const _EmailLoginFormV2({
    required this.emailController,
    required this.passwordController,
    this.submitLabel = 'Mit E-Mail anmelden',
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final String submitLabel;

  @override
  State<_EmailLoginFormV2> createState() => _EmailLoginFormV2State();
}

class _EmailLoginFormV2State extends State<_EmailLoginFormV2> {
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppFormField(
            controller: widget.emailController,
            label: 'E-Mail',
            keyboardType: TextInputType.emailAddress,
            prefixIcon: const Icon(Icons.mail_outline),
            validator: (value) {
              if (value == null || !_emailRegex.hasMatch(value.trim())) {
                return 'Bitte eine gueltige E-Mail-Adresse eingeben';
              }
              return null;
            },
          ),
          SizedBox(height: context.spacing.md - context.spacing.xs),
          AppFormField(
            controller: widget.passwordController,
            label: 'Passwort',
            obscureText: true,
            prefixIcon: const Icon(Icons.lock_outline),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Bitte ein Passwort eingeben';
              }
              return null;
            },
          ),
          SizedBox(height: context.spacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
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
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: Text(widget.submitLabel),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvitationActivationFormV2 extends StatefulWidget {
  const _InvitationActivationFormV2({
    required this.emailController,
    required this.passwordController,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;

  @override
  State<_InvitationActivationFormV2> createState() =>
      _InvitationActivationFormV2State();
}

class _InvitationActivationFormV2State extends State<_InvitationActivationFormV2> {
  final _formKey = GlobalKey<FormState>();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final spacing = context.spacing;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppFormField(
            controller: widget.emailController,
            label: 'E-Mail aus der Einladung',
            keyboardType: TextInputType.emailAddress,
            prefixIcon: const Icon(Icons.mail_outline),
            validator: (value) {
              if (value == null || !_emailRegex.hasMatch(value.trim())) {
                return 'Bitte eine gueltige E-Mail-Adresse eingeben';
              }
              return null;
            },
          ),
          SizedBox(height: spacing.md - spacing.xs),
          AppFormField(
            controller: widget.passwordController,
            label: 'Neues Passwort',
            obscureText: true,
            prefixIcon: const Icon(Icons.lock_reset_outlined),
            validator: (value) {
              if (value == null || value.length < 6) {
                return 'Mindestens 6 Zeichen erforderlich';
              }
              return null;
            },
          ),
          SizedBox(height: spacing.md - spacing.xs),
          AppFormField(
            controller: _confirmPasswordController,
            label: 'Passwort bestaetigen',
            obscureText: true,
            prefixIcon: const Icon(Icons.lock_outline),
            validator: (value) {
              if (value != widget.passwordController.text) {
                return 'Passwoerter stimmen nicht ueberein';
              }
              return null;
            },
          ),
          SizedBox(height: spacing.md - spacing.xs),
          Text(
            'Der Account wird nur angelegt, wenn eine aktive Admin-Einladung fuer diese E-Mail existiert.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          SizedBox(height: spacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
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
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    )
                  : const Icon(Icons.person_add_alt_1),
              label: const Text('Einladung aktivieren'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoAccountsV2 extends StatelessWidget {
  const _DemoAccountsV2({required this.accounts});

  final List<LocalDemoAccount> accounts;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final spacing = context.spacing;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(context.radii.xl),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Lokale Demo-Profile',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          SizedBox(height: spacing.xs + spacing.xxs),
          Text(
            'Im Entwicklungsmodus kannst du dich direkt als Admin oder Mitarbeiter anmelden.',
            style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          SizedBox(height: spacing.md - spacing.xxs),
          for (final account in accounts) ...[
            _DemoAccountTileV2(account: account),
            if (account != accounts.last) SizedBox(height: spacing.sm + spacing.xs),
          ],
        ],
      ),
    );
  }
}

class _DemoAccountTileV2 extends StatelessWidget {
  const _DemoAccountTileV2({required this.account});

  final LocalDemoAccount account;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final spacing = context.spacing;
    return AppCard(
      color: colorScheme.surface,
      padding: EdgeInsets.all(spacing.md - spacing.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            account.name,
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          SizedBox(height: spacing.xs),
          Text(
            account.role.label,
            style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          SizedBox(height: spacing.sm),
          Text('E-Mail: ${account.email}'),
          Text('Passwort: ${account.password}'),
          SizedBox(height: spacing.xs + spacing.xxs),
          Text(
            account.description,
            style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          SizedBox(height: spacing.sm + spacing.xs),
          SizedBox(
            width: double.infinity,
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

/// V2-Variante des Firebase-Setup-Hinweises (kein Login moeglich).
class FirebaseSetupScreenV2 extends StatelessWidget {
  const FirebaseSetupScreenV2({super.key});

  @override
  Widget build(BuildContext context) {
    final pagePadding = MobileBreakpoints.screenPadding(context);
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                pagePadding.left,
                context.spacing.lg,
                pagePadding.right,
                context.spacing.lg,
              ),
              child: AppCard(
                padding: EdgeInsets.all(context.spacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(child: AppLogo(height: 92)),
                    SizedBox(height: context.spacing.md + context.spacing.xxs),
                    Text(
                      'Anmeldung derzeit nicht verfuegbar',
                      style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: context.spacing.sm + context.spacing.xs),
                    const Text(
                      'Die Anwendung kann in dieser Umgebung noch nicht fuer die Anmeldung bereitgestellt werden.',
                    ),
                    SizedBox(height: context.spacing.md),
                    const Text(
                      'Bitte wende dich an die zustaendige Person, damit die Bereitstellung abgeschlossen wird.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// V2-Variante des Sperr-Hinweises (Konto deaktiviert).
class AccessBlockedScreenV2 extends StatelessWidget {
  const AccessBlockedScreenV2({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: EdgeInsets.all(context.spacing.lg),
            child: AppCard(
              padding: EdgeInsets.all(context.spacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_person_outlined, size: context.iconSizes.hero),
                  SizedBox(height: context.spacing.md),
                  Text(
                    'Konto deaktiviert',
                    style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: context.spacing.sm),
                  const Text(
                    'Dieses Benutzerkonto wurde durch einen Admin deaktiviert. Bitte wende dich an die Verwaltung.',
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: context.spacing.lg - context.spacing.xs),
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
