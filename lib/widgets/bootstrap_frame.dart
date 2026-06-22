import 'package:flutter/material.dart';

import 'app_logo.dart';

/// Zentrierter, schmaler Rahmen für Start-/Lade-/Fehlerschirme. Geteilt von
/// [AppBootstrap] (vor der Provider-Kette) und dem go_router `/start`-Splash,
/// damit Loading-Optik an einer Stelle gepflegt wird.
class BootstrapFrame extends StatelessWidget {
  const BootstrapFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Statuskarte mit Logo, optionalem Loader, Titel/Meldung und optionaler Aktion.
/// Für Bootstrap-Lade- und Fehlerzustände.
class StartupStatusCard extends StatelessWidget {
  const StartupStatusCard({
    super.key,
    required this.title,
    required this.message,
    this.showLoader = false,
    this.actionLabel,
    this.onActionPressed,
  });

  final String title;
  final String message;
  final bool showLoader;
  final String? actionLabel;
  final VoidCallback? onActionPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppLogo(height: 78),
            const SizedBox(height: 20),
            if (showLoader) ...[
              const CircularProgressIndicator.adaptive(),
              const SizedBox(height: 20),
            ],
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (actionLabel != null && onActionPressed != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onActionPressed,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
