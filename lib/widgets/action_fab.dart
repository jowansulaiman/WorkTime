import 'package:flutter/material.dart';

import '../core/accessibility.dart';

/// Eine Aktion innerhalb eines [ExpandableFab].
///
/// [emphasized] hebt eine einzelne Aktion farblich hervor (z. B. die wichtigste
/// unter mehreren Zweitaktionen, etwa „In den Warenkorb").
@immutable
class FabAction {
  const FabAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool emphasized;
}

/// Moderner Aktions-FAB mit aufklappbarem „Speed-Dial".
///
/// * Genau **eine** Aktion → ein einzelner, beschrifteter [FloatingActionButton]
///   (kein Aufklappen nötig). Bleibt ein echter `FloatingActionButton`, damit
///   Material-Semantik und bestehende Widget-Tests erhalten bleiben.
/// * **Mehrere** Aktionen → ein runder Umschalt-FAB, der die beschrifteten
///   Zweitaktionen gestaffelt nach oben auffächert.
///
/// Eingeklappt belegt der FAB nur die Fläche eines einzelnen Buttons – damit
/// wird kein Listeninhalt mehr von einem dauerhaften Button-Stapel verdeckt
/// (Listen sollten dennoch ~[kFabSafeBottomInset] Bodenabstand reservieren).
class ExpandableFab extends StatefulWidget {
  const ExpandableFab({
    super.key,
    required this.actions,
    required this.heroTag,
    this.openIcon = Icons.add,
    this.expandTooltip = 'Aktionen anzeigen',
    this.collapseTooltip = 'Aktionen ausblenden',
  });

  /// Aktionen in Anzeigereihenfolge von oben nach unten. Der letzte Eintrag
  /// sitzt am nächsten zum Umschalt-Button und erscheint zuerst.
  final List<FabAction> actions;

  /// Eindeutiger Hero-Tag des primären Buttons (Pflicht, da ggf. mehrere FABs
  /// gleichzeitig im Baum sind).
  final Object heroTag;

  /// Symbol des eingeklappten Umschalt-Buttons (dreht beim Öffnen zu „×").
  final IconData openIcon;
  final String expandTooltip;
  final String collapseTooltip;

  @override
  State<ExpandableFab> createState() => _ExpandableFabState();
}

class _ExpandableFabState extends State<ExpandableFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respektiert die „Bewegung reduzieren"-Systemeinstellung.
    _controller.duration = context.motionDuration(
      const Duration(milliseconds: 280),
    );
  }

  @override
  void didUpdateWidget(ExpandableFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Wird dieselbe State-Instanz für einen anderen FAB wiederverwendet – etwa
    // beim Tabwechsel, da alle Tabs denselben Scaffold-FAB-Slot belegen –, den
    // Aufklapp-Zustand zurücksetzen. Sonst erschiene das Speed-Dial beim
    // Zurückkehren unerwartet bereits geöffnet.
    if (oldWidget.heroTag != widget.heroTag) {
      _open = false;
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _runAction(VoidCallback onPressed) {
    if (_open) {
      setState(() => _open = false);
      _controller.reverse();
    }
    onPressed();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.actions.isEmpty) {
      return const SizedBox.shrink();
    }

    // Einzelaktion: schlichter, beschrifteter FAB ohne Aufklappen.
    if (widget.actions.length == 1) {
      final action = widget.actions.single;
      return FloatingActionButton.extended(
        heroTag: widget.heroTag,
        onPressed: action.onPressed,
        icon: Icon(action.icon),
        label: Text(action.label),
      );
    }

    final count = widget.actions.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < count; i++)
          _RevealSlot(
            controller: _controller,
            expanded: _open,
            position: count - 1 - i,
            child: _SpeedDialAction(
              action: widget.actions[i],
              onTap: () => _runAction(widget.actions[i].onPressed),
            ),
          ),
        _ToggleButton(
          heroTag: widget.heroTag,
          controller: _controller,
          openIcon: widget.openIcon,
          tooltip: _open ? widget.collapseTooltip : widget.expandTooltip,
          onPressed: _toggle,
        ),
      ],
    );
  }
}

/// Runder Umschalt-Button des Speed-Dials. Das Symbol dreht beim Öffnen von
/// „+" zu „×".
class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.heroTag,
    required this.controller,
    required this.openIcon,
    required this.tooltip,
    required this.onPressed,
  });

  final Object heroTag;
  final AnimationController controller;
  final IconData openIcon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // Farbe/Form aus dem FloatingActionButton-Theme – identisch zum
    // Einzelaktions-FAB, damit alle primären FABs gleich aussehen.
    return FloatingActionButton(
      heroTag: heroTag,
      tooltip: tooltip,
      onPressed: onPressed,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Transform.rotate(
          // 0 → 45°: aus „+" wird ein „×".
          angle: controller.value * 0.7853981633974483,
          child: Icon(openIcon),
        ),
      ),
    );
  }
}

/// Eine Zeile im aufgeklappten Speed-Dial: Beschriftungs-Chip links, runder
/// Mini-Button rechts.
class _SpeedDialAction extends StatelessWidget {
  const _SpeedDialAction({required this.action, required this.onTap});

  final FabAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // Nicht-Surface-Rollen, damit der runde Button auch im Dark Mode eine
    // sichtbare Kante gegen den (gleichfarbigen) Scaffold-Hintergrund hat.
    final background = action.emphasized
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHigh;
    final foreground = action.emphasized
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;
    final border = BorderSide(
      color: colorScheme.outlineVariant.withValues(alpha: 0.6),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Beschriftungs-Chip (gut lesbar über Listeninhalt).
        _SoftShadow(
          borderRadius: BorderRadius.circular(10),
          child: Material(
            color: colorScheme.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: border,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Text(
                action.label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Runder Mini-Button.
        _SoftShadow(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            color: background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: action.emphasized ? BorderSide.none : border,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Tooltip(
                  message: action.label,
                  child: Icon(action.icon, color: foreground, size: 22),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Weicher, neutraler Schatten für die schwebenden Speed-Dial-Elemente.
class _SoftShadow extends StatelessWidget {
  const _SoftShadow({required this.child, required this.borderRadius});

  final Widget child;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Gestaffelt ein-/ausblendender Platz im Speed-Dial. Eingeklappt nimmt er
/// keinen Platz ein und schluckt keine Taps.
class _RevealSlot extends StatelessWidget {
  const _RevealSlot({
    required this.controller,
    required this.expanded,
    required this.position,
    required this.child,
  });

  final AnimationController controller;
  final bool expanded;

  /// 0 = nächster am Umschalt-Button (erscheint zuerst), größer = später.
  final int position;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = (position * 0.12).clamp(0.0, 0.4);
    final end = (start + 0.6).clamp(0.0, 1.0);
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        final t = ((controller.value - start) / (end - start)).clamp(0.0, 1.0);
        final eased = Curves.easeOutCubic.transform(t);
        if (eased <= 0.001 && !expanded) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Opacity(
            opacity: eased,
            child: Transform.translate(
              offset: Offset(0, (1 - eased) * 16),
              child: IgnorePointer(
                ignoring: !expanded,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Empfohlener Bodenabstand (Bottom-Padding) für scrollbare Inhalte, damit die
/// letzte Zeile nicht vom eingeklappten FAB verdeckt wird.
const double kFabSafeBottomInset = 96;
