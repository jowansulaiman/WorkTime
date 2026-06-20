/// Gemeinsame UI-Komponenten-Bibliothek (Signal-Teal-Redesign, `redesign_v2`).
///
/// Getrennt vom Legacy-`lib/widgets/`: saubere Bestands-Widgets werden hier nur
/// re-exportiert, neue V2-Komponenten konsumieren ausschliesslich Design-Tokens
/// (kein Hex, keine festen dp). Ein Import (`package:worktime_app/ui/ui.dart`)
/// genuegt fuer alle V2-Bausteine + Tokens.
library;

import '../widgets/empty_state.dart';

// --- Design-Tokens (Spacing/Radii/Motion/Elevation/IconSizes + AppThemeColors)
export '../theme/theme_extensions.dart';

// --- Saubere Bestands-Widgets (unveraendert wiederverwendet) ----------------
export '../widgets/app_logo.dart';
export '../widgets/breadcrumb_app_bar.dart';
export '../widgets/empty_state.dart';
export '../widgets/info_chip.dart';
export '../widgets/responsive_layout.dart';
export '../widgets/section_card.dart';
export '../widgets/section_header.dart';

// --- Neue V2-Komponenten ----------------------------------------------------
export 'app_bottom_sheet_scaffold.dart';
export 'app_card.dart';
export 'app_confirm_dialog.dart';
export 'app_form_field.dart';
export 'app_hero_card.dart';
export 'app_quick_action.dart';
export 'app_section_card.dart';
export 'app_segmented.dart';
export 'app_stat_cards.dart';
export 'app_status.dart';

/// Alias auf das saubere [EmptyState]-Widget. Loest die zuvor mehrfach
/// kopierten file-private `_EmptyState`-Klone (Home/Statistik/Planer) auf —
/// Aufrufer migrieren auf `AppEmptyState(icon:, message:)`.
typedef AppEmptyState = EmptyState;
