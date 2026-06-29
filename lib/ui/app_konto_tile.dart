import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';
import 'app_card.dart';

/// Farbton einer [KontoZeile] – bindet an benannte Theme-Rollen / [AppThemeColors],
/// nie an Hex (Signal-Teal-Redesign).
enum KontoZeileTon { normal, gedaempft, gut, warnung }

/// Eine Zeile in der Aufstellung eines [AppKontoTile] (z. B.
/// „+ Vortrag Vorjahr   3,0 Tage"). Reines Wert-Objekt, domänenfrei – der
/// aufrufende Screen baut die Zeilen aus `UrlaubsReport`/`ZeitkontoResult`.
class KontoZeile {
  const KontoZeile(
    this.label,
    this.wert, {
    this.ton = KontoZeileTon.normal,
    this.summe = false,
    this.dividerDavor = false,
  });

  final String label;
  final String wert;
  final KontoZeileTon ton;

  /// Hebt Label + Wert hervor (Zwischen-/Endsumme).
  final bool summe;

  /// Zeichnet einen [Divider] **vor** dieser Zeile.
  final bool dividerDavor;
}

/// Wiederverwendbare Konto-Kachel (Plan §6.1, IDA `ZeitStundenkontoListTile`/
/// `ZeitVacationStatusListTile`): aufklappbare Kachel mit Kopf = Titel +
/// fetter Kennzahl, Körper = +/−/=-Aufstellung. Domänenfrei – nutzt
/// ausschliesslich Design-Tokens; Aufrufer (z. B. `abwesenheit_screen`,
/// MA-Detail) mappen ihre Wert-Objekte auf [KontoZeile]n.
class AppKontoTile extends StatelessWidget {
  const AppKontoTile({
    super.key,
    required this.icon,
    required this.title,
    required this.kennzahl,
    required this.zeilen,
    this.kennzahlTon = KontoZeileTon.normal,
    this.untertitel,
    this.banner,
    this.initiallyExpanded = false,
  });

  final IconData icon;
  final String title;

  /// Die im Kopf rechts angezeigte Kennzahl (z. B. „12,0 Tage").
  final String kennzahl;
  final KontoZeileTon kennzahlTon;

  /// Optionaler kleiner Untertitel unter dem Titel.
  final String? untertitel;

  /// Optionaler Hinweis-Banner (z. B. §9-/Hinweisobliegenheit), unter der
  /// Aufstellung gerendert.
  final Widget? banner;

  final List<KontoZeile> zeilen;
  final bool initiallyExpanded;

  static Color _farbe(BuildContext context, KontoZeileTon ton) {
    final theme = Theme.of(context);
    return switch (ton) {
      KontoZeileTon.normal => theme.colorScheme.onSurface,
      KontoZeileTon.gedaempft => theme.colorScheme.onSurfaceVariant,
      KontoZeileTon.gut => theme.appColors.success,
      KontoZeileTon.warnung => theme.appColors.warning,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = context.spacing;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Theme(
        // Entfernt die Standard-Trennlinien des ExpansionTile (Card hat Rahmen).
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: EdgeInsets.symmetric(horizontal: spacing.md, vertical: spacing.xs),
          childrenPadding: EdgeInsets.fromLTRB(
            spacing.md,
            0,
            spacing.md,
            spacing.md,
          ),
          leading: Icon(icon, color: theme.colorScheme.primary, size: context.iconSizes.md),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              SizedBox(width: spacing.sm),
              Text(
                kennzahl,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: _farbe(context, kennzahlTon),
                ),
              ),
            ],
          ),
          subtitle: untertitel == null
              ? null
              : Text(
                  untertitel!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
          children: [
            for (final z in zeilen) ...[
              if (z.dividerDavor) const Divider(height: 1),
              Padding(
                padding: EdgeInsets.symmetric(vertical: spacing.xxs),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      z.label,
                      style: (z.summe
                              ? theme.textTheme.titleSmall
                              : theme.textTheme.bodyMedium)
                          ?.copyWith(color: _farbe(context, z.ton)),
                    ),
                    Text(
                      z.wert,
                      style: (z.summe
                              ? theme.textTheme.titleSmall
                              : theme.textTheme.bodyMedium)
                          ?.copyWith(
                        color: _farbe(context, z.ton),
                        fontWeight: z.summe ? FontWeight.w800 : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (banner != null) ...[
              SizedBox(height: spacing.sm),
              banner!,
            ],
          ],
        ),
      ),
    );
  }
}
