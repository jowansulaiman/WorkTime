import 'package:flutter/material.dart';

/// Force-Update-Gate (no-feature-flags-force-update): wird angezeigt, wenn der
/// Server eine hoehere Mindest-Build-Nummer fordert als diese App-Version hat.
/// Bewusst ohne Abmelden-/Weiter-Aktion – ein zu alter Client soll keine
/// (potenziell inkompatiblen) Schreibpfade mehr erreichen.
class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({
    super.key,
    this.message,
    required this.minimumBuildNumber,
    required this.currentBuildNumber,
  });

  final String? message;
  final int minimumBuildNumber;
  final int currentBuildNumber;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                  const Icon(Icons.system_update_outlined, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Update erforderlich',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message ??
                        'Diese App-Version wird nicht mehr unterstützt. Bitte '
                            'installiere die neueste Version, um fortzufahren.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Installiert: Build $currentBuildNumber · '
                    'benötigt: Build $minimumBuildNumber',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
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
