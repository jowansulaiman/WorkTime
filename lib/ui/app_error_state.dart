import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';

/// Vereinheitlichter Fehlerzustand (Signal-Teal-Redesign): Icon + Titel +
/// verstaendliche Nachricht + optionale „Erneut versuchen"-Aktion.
///
/// Ersetzt die verstreuten roh-`$error`-Anzeigen und file-private Fehler-Banner
/// (Anf. 17 „verstaendliche Fehlermeldungen"). Nutzt ausschliesslich Tokens
/// (`context.spacing`/`iconSizes`) und benannte Theme-Rollen — der Fehlerton
/// kommt aus `colorScheme.error`/`errorContainer`, nie aus Hex.
///
/// Screenreader: der Block ist eine `liveRegion`, damit ein neu erscheinender
/// Fehler angesagt wird; Titel + Nachricht werden zusammen vorgelesen.
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    required this.message,
    this.title = 'Etwas ist schiefgelaufen',
    this.icon = Icons.error_outline_rounded,
    this.onRetry,
    this.retryLabel = 'Erneut versuchen',
    this.details,
    this.compact = false,
  });

  /// Verstaendliche, handlungsleitende Kurznachricht (deutsch, ohne Stacktrace).
  final String message;

  /// Kurzer Titel ueber der Nachricht.
  final String title;

  final IconData icon;

  /// Optionaler Rueckruf fuer „Erneut versuchen". Fehlt er, wird kein Button
  /// gezeigt.
  final VoidCallback? onRetry;

  final String retryLabel;

  /// Optionaler technischer Detailtext (gedaempft, klein) — fuer Nutzer
  /// sekundaer, z. B. ein Fehlercode. Niemals ein roher Stacktrace.
  final String? details;

  /// Kompakt (linksbuendig, kleineres Icon) fuer Inline-Nutzung in Listen/
  /// Sheets; Default ist der zentrierte Vollflaechen-Zustand.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final spacing = context.spacing;
    final crossAxis =
        compact ? CrossAxisAlignment.start : CrossAxisAlignment.center;
    final textAlign = compact ? TextAlign.start : TextAlign.center;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxis,
      children: [
        Icon(
          icon,
          size: compact ? context.iconSizes.lg : context.iconSizes.hero,
          color: scheme.error,
        ),
        SizedBox(height: spacing.sm + spacing.xs),
        MergeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: crossAxis,
            children: [
              Text(
                title,
                textAlign: textAlign,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: spacing.xs + spacing.xxs),
              Text(
                message,
                textAlign: textAlign,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (details != null) ...[
          SizedBox(height: spacing.xs),
          Text(
            details!,
            textAlign: textAlign,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
        if (onRetry != null) ...[
          SizedBox(height: spacing.md),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(retryLabel),
          ),
        ],
      ],
    );

    final live = Semantics(liveRegion: true, container: true, child: content);

    if (compact) {
      return Padding(
        padding: EdgeInsets.all(spacing.md),
        child: live,
      );
    }
    return Center(
      child: Padding(
        padding: EdgeInsets.all(spacing.xl),
        child: live,
      ),
    );
  }
}
