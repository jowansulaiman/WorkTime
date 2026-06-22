import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/app_config.dart';
import '../../models/customer_wish.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import 'public_legal_screen.dart';
import 'public_ui.dart';

/// Öffentliche Seite, über die Kunden ohne Login einen Wunsch abgeben
/// (Zeitschrift, Zigaretten, Tabak …). Nach dem Absenden erhält der Kunde eine
/// Referenznummer, die er im Laden nennt. Optik: flaches Signal-Teal-Layout mit
/// seitlicher Marken-Schiene und in nummerierte Zonen gegliedertem Formular
/// (siehe [PublicPageScaffold]).
class PublicWishScreen extends StatefulWidget {
  const PublicWishScreen({
    super.key,
    required this.firestoreService,
    this.onSelectThemeMode,
  });

  final FirestoreService firestoreService;

  /// Callback zum Umschalten des Hell/Dunkel-Modus (von [PublicWishApp]
  /// gesetzt). Ist er null, wird der Umschalter nicht angezeigt.
  final ValueChanged<ThemeMode>? onSelectThemeMode;

  @override
  State<PublicWishScreen> createState() => _PublicWishScreenState();
}

class _PublicWishScreenState extends State<PublicWishScreen> {
  final _formKey = GlobalKey<FormState>();
  final _wishController = TextEditingController();
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();

  late final List<String> _stores = AppConfig.publicStoreNameList;

  CustomerWishCategory _category = CustomerWishCategory.magazine;
  late String _store = _stores.isNotEmpty ? _stores.first : 'Laden';
  int _quantity = 1;
  DateTime? _desiredDate;

  bool _submitting = false;
  String? _error;
  String? _resultCode;

  static final DateFormat _dateFormat = DateFormat('dd.MM.yyyy', 'de_DE');

  @override
  void dispose() {
    _wishController.dispose();
    _nameController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();

    // Ohne initialisiertes Firebase (z.B. lokaler Vorschau-Lauf ohne
    // Firebase-Konfiguration) kann nicht geschrieben werden — ehrliche Meldung
    // statt "Internetverbindung prüfen".
    if (Firebase.apps.isEmpty) {
      _handleError(
        'Diese Seite ist hier nicht mit dem Backend verbunden '
        '(keine Firebase-Konfiguration). Sie funktioniert nur im echten '
        'Web-Build mit Firebase – siehe Go-Live-Schritte.',
      );
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      // Anonymes Sign-in: firestore.rules verlangt request.auth != null.
      // Schlägt fehl, wenn der Anonymous-Provider im Firebase-Projekt nicht
      // aktiviert ist (operation-not-allowed) -> klare Meldung.
      final auth = FirebaseAuth.instance;
      // Session-Persistenz (nur Web): anonyme Tokens akkumulieren NICHT
      // dauerhaft in der IndexedDB des Kunden-Browsers.
      if (kIsWeb) {
        await auth.setPersistence(Persistence.SESSION);
      }
      if (auth.currentUser == null) {
        await auth.signInAnonymously();
      }

      final code = CustomerWish.generateReferenceCode();
      final wish = CustomerWish(
        orgId: AppConfig.defaultOrganizationId,
        referenceCode: code,
        storeName: _store,
        category: _category,
        wishText: _wishController.text,
        quantity: _quantity,
        desiredDate: _desiredDate,
        customerName: _nameController.text,
        customerContact: _contactController.text,
      );
      await widget.firestoreService.submitCustomerWish(wish);

      if (!mounted) {
        return;
      }
      setState(() {
        _resultCode = code;
        _submitting = false;
      });
    } on FirebaseAuthException catch (error) {
      _handleError(
        error.code == 'operation-not-allowed'
            ? 'Die Wunsch-Abgabe ist derzeit nicht aktiviert. Bitte wende dich direkt an den Laden.'
            : 'Anmeldung fehlgeschlagen. Bitte versuche es später erneut.',
        error,
      );
    } on FirebaseException catch (error) {
      // permission-denied = Konfigurationsfehler (z.B. orgId-Pin in den Rules
      // passt nicht zu APP_DEFAULT_ORG_ID) — ehrliche Meldung statt
      // irreführendem "Internetverbindung prüfen".
      _handleError(
        error.code == 'permission-denied'
            ? 'Die Wunsch-Abgabe ist für diesen Laden nicht freigeschaltet. Bitte wende dich direkt an den Laden.'
            : 'Dein Wunsch konnte nicht gesendet werden. Bitte versuche es später erneut.',
        error,
      );
    } catch (error) {
      _handleError(
        'Dein Wunsch konnte nicht gesendet werden. Bitte prüfe deine Internetverbindung und versuche es erneut.',
        error,
      );
    }
  }

  void _handleError(String message, [Object? cause]) {
    if (cause != null) {
      // In die Konsole loggen, damit die echte Ursache diagnostizierbar ist
      // (der generische Text verschluckt sie sonst).
      debugPrint('Kundenwunsch-Submit fehlgeschlagen: $cause');
    }
    if (!mounted) {
      return;
    }
    setState(() {
      // Im Debug-Build die echte Fehlermeldung sichtbar machen.
      _error =
          (kDebugMode && cause != null) ? '$message\n\n[Debug] $cause' : message;
      _submitting = false;
    });
  }

  void _reset() {
    _formKey.currentState?.reset();
    _wishController.clear();
    _nameController.clear();
    _contactController.clear();
    setState(() {
      _category = CustomerWishCategory.magazine;
      _store = _stores.isNotEmpty ? _stores.first : 'Laden';
      _quantity = 1;
      _desiredDate = null;
      _resultCode = null;
      _error = null;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _desiredDate ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Wunschtermin wählen',
    );
    if (picked != null) {
      setState(() => _desiredDate = picked);
    }
  }

  static IconData _categoryIcon(CustomerWishCategory category) =>
      switch (category) {
        CustomerWishCategory.magazine => Icons.menu_book_outlined,
        CustomerWishCategory.cigarettes => Icons.smoking_rooms_outlined,
        CustomerWishCategory.tobacco => Icons.grass_outlined,
        CustomerWishCategory.other => Icons.more_horiz,
      };

  @override
  Widget build(BuildContext context) {
    return PublicPageScaffold(
      brand: PublicBrandContent(
        glyph: Icons.redeem_outlined,
        title: 'Wunsch\nabgeben',
        subtitle:
            'Sag uns, was du brauchst – Zeitschrift, Zigaretten, Tabak oder '
            'etwas anderes. Du bekommst eine Nummer, die du im Laden nennst.',
        trustText: 'Ohne Anmeldung. Deine Angaben bleiben bei uns.',
        steps: const [
          'Wunsch beschreiben',
          'Nummer erhalten',
          'Im Laden nennen',
        ],
        singleStoreName: _stores.length == 1 ? _stores.first : null,
      ),
      trailingAction:
          widget.onSelectThemeMode != null ? _buildThemeToggle(context) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSwitcher(
            duration: AppMotion.resolve(context, context.motion.medium),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SizeTransition(
                sizeFactor: animation,
                axisAlignment: -1,
                child: child,
              ),
            ),
            child: _resultCode != null
                ? _buildSuccess(context, _resultCode!)
                : _buildForm(context),
          ),
          PublicLegalLinks(
            onImpressum: () => _openLegal(PublicLegalPage.impressum),
            onDatenschutz: () => _openLegal(PublicLegalPage.datenschutz),
          ),
        ],
      ),
    );
  }

  /// Öffnet Impressum bzw. Datenschutz als gestapelte Seite (Zurück-Pfeil führt
  /// zum Formular). Reicht den Theme-Umschalter weiter, damit der Hell/Dunkel-
  /// Modus auch auf der Rechtsseite verfügbar bleibt.
  void _openLegal(PublicLegalPage page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PublicLegalScreen(
          page: page,
          onSelectThemeMode: widget.onSelectThemeMode,
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final spacing = context.spacing;

    final hasStoreChoice = _stores.length > 1;
    final storeGroup = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PublicFieldLabel('Laden'),
        SizedBox(height: spacing.sm),
        PublicChipRow<String>(
          values: _stores,
          selected: _store,
          onSelected: (value) => setState(() => _store = value),
          labelOf: (value) => value,
        ),
      ],
    );
    final categoryGroup = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PublicFieldLabel('Kategorie'),
        SizedBox(height: spacing.sm),
        PublicChipRow<CustomerWishCategory>(
          values: CustomerWishCategory.values,
          selected: _category,
          onSelected: (value) => setState(() => _category = value),
          labelOf: (value) => value.label,
          iconOf: _categoryIcon,
        ),
      ],
    );

    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('form'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PublicSection(
            index: '1',
            title: 'Worum geht es?',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PublicFieldPair(
                  left: hasStoreChoice ? storeGroup : categoryGroup,
                  right: hasStoreChoice ? categoryGroup : null,
                ),
                SizedBox(height: spacing.lg),
                const PublicFieldLabel('Dein Wunsch'),
                SizedBox(height: spacing.sm),
                TextFormField(
                  controller: _wishController,
                  maxLines: 3,
                  maxLength: 2000,
                  textInputAction: TextInputAction.newline,
                  decoration: publicFieldDecoration(
                    context,
                    hint:
                        'z. B. „Spiegel Ausgabe 26“ oder „Stange Marlboro Gold“',
                  ),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Bitte beschreibe deinen Wunsch.'
                      : null,
                ),
              ],
            ),
          ),
          SizedBox(height: spacing.md),
          PublicSection(
            index: '2',
            title: 'Details',
            child: PublicFieldPair(
              left: PublicStepperTile(
                value: _quantity,
                label: 'Menge',
                onMinus:
                    _quantity > 1 ? () => setState(() => _quantity--) : null,
                onPlus:
                    _quantity < 999 ? () => setState(() => _quantity++) : null,
              ),
              right: PublicDateTile(
                label: _desiredDate != null
                    ? 'Wunschtermin: ${_dateFormat.format(_desiredDate!)}'
                    : 'Wunschtermin hinzufügen (optional)',
                onPick: _pickDate,
                hasDate: _desiredDate != null,
                onClear: () => setState(() => _desiredDate = null),
                clearTooltip: 'Termin entfernen',
              ),
            ),
          ),
          SizedBox(height: spacing.md),
          PublicSection(
            index: '3',
            title: 'Kontakt',
            titleTrailing: '(optional)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PublicFieldPair(
                  left: TextFormField(
                    controller: _nameController,
                    maxLength: 200,
                    textInputAction: TextInputAction.next,
                    decoration: publicFieldDecoration(
                      context,
                      hint: 'Dein Name',
                      icon: Icons.person_outline,
                    ),
                  ),
                  right: TextFormField(
                    controller: _contactController,
                    maxLength: 200,
                    decoration: publicFieldDecoration(
                      context,
                      hint: 'Telefon oder E-Mail',
                      icon: Icons.call_outlined,
                    ),
                  ),
                ),
                SizedBox(height: spacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline,
                        size: context.iconSizes.sm,
                        color: scheme.onSurfaceVariant),
                    SizedBox(width: spacing.sm),
                    Expanded(
                      child: Text(
                        'Deine Angaben nutzen wir nur zur Bearbeitung deines '
                        'Wunsches und geben sie nicht weiter.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: spacing.lg),
          if (_error != null) ...[
            PublicErrorBanner(message: _error!),
            SizedBox(height: spacing.md),
          ],
          PublicSubmitButton(
            submitting: _submitting,
            onPressed: _submit,
            idleLabel: 'Wunsch absenden',
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(BuildContext context, String code) {
    return PublicSuccessView(
      key: const ValueKey('success'),
      code: code,
      headline: 'Wunsch erhalten – danke!',
      lead: 'Nenne diese Nummer im Laden, dann finden wir deinen Wunsch sofort:',
      codeCaption: 'DEINE WUNSCH-NUMMER',
      copyLabel: 'Nummer kopieren',
      onCopy: () async {
        await Clipboard.setData(ClipboardData(text: code));
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nummer kopiert')),
        );
      },
      resetLabel: 'Weiteren Wunsch abgeben',
      onReset: _reset,
    );
  }

  /// Hell/Dunkel-Umschalter. Liest die aktuell gerenderte Helligkeit (auch im
  /// System-Modus korrekt) und schaltet auf den jeweils anderen, festen Modus.
  Widget _buildThemeToggle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IconButton.filledTonal(
      tooltip: isDark ? 'Heller Modus' : 'Dunkler Modus',
      icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
      onPressed: () => widget.onSelectThemeMode?.call(
        isDark ? ThemeMode.light : ThemeMode.dark,
      ),
    );
  }
}
