import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';

/// Tokenisiertes Suchfeld (Signal-Teal-Redesign) — die eine kanonische
/// screen-lokale Suche (Anf. 24 „Such- und Filterfunktionen").
///
/// Ersetzt die verstreuten roh-`TextField`-Suchen je Liste. Zeigt ein
/// Such-Prefix und einen Loeschen-Suffix (nur bei Eingabe), meldet Aenderungen
/// via [onChanged] und Enter via [onSubmitted]. Nutzt nur Tokens + benannte
/// Theme-Rollen (gefuellt auf `surfaceContainerHigh`, Radius `context.radii.md`).
///
/// Der Controller ist optional: ohne uebergebenen [controller] verwaltet das
/// Widget einen internen (und raeumt ihn auf). Der Loeschen-Button ist ein
/// echtes 48-dp-Tap-Target mit Semantics-Label.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    this.controller,
    this.hint = 'Suchen',
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.autofocus = false,
    this.enabled = true,
    this.focusNode,
    this.semanticLabel,
  });

  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Zusaetzlicher Rueckruf, wenn das Feld ueber den Loeschen-Button geleert
  /// wird (nach [onChanged] mit leerem String).
  final VoidCallback? onClear;

  final bool autofocus;
  final bool enabled;
  final FocusNode? focusNode;

  /// Screenreader-Label; Default aus [hint].
  final String? semanticLabel;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  TextEditingController? _internal;
  TextEditingController get _controller =>
      widget.controller ?? (_internal ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(AppSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      _controller.addListener(_onControllerChanged);
    }
  }

  void _onControllerChanged() {
    // Nur fuer die Sichtbarkeit des Loeschen-Buttons neu bauen.
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _internal?.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
    widget.onClear?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasText = _controller.text.isNotEmpty;
    final radius = BorderRadius.circular(context.radii.md);

    return Semantics(
      textField: true,
      label: widget.semanticLabel ?? widget.hint,
      child: TextField(
        controller: _controller,
        focusNode: widget.focusNode,
        enabled: widget.enabled,
        autofocus: widget.autofocus,
        textInputAction: TextInputAction.search,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: scheme.surfaceContainerHigh,
          hintText: widget.hint,
          prefixIcon: Icon(Icons.search_rounded, size: context.iconSizes.md),
          suffixIcon: hasText
              ? IconButton(
                  onPressed: _clear,
                  icon: const Icon(Icons.close_rounded),
                  iconSize: context.iconSizes.sm,
                  tooltip: 'Suche leeren',
                  visualDensity: VisualDensity.standard,
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(color: scheme.primary, width: 1.5),
          ),
        ),
      ),
    );
  }
}
