import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/app_config.dart';
import '../../core/app_logger.dart';
import '../../models/customer_feedback.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import 'public_legal_screen.dart';
import 'public_ui.dart';

/// Öffentliche Seite, über die Kunden ohne Login eine Rückmeldung abgeben:
/// eine Beschwerde, einen Verbesserungsvorschlag oder Lob. Nach dem Absenden
/// erhält der Kunde eine Referenznummer für eine eventuelle Nachfrage. Teilt
/// sich das flache Signal-Teal-Layout mit der Wunsch-Seite ([PublicPageScaffold]).
class PublicFeedbackScreen extends StatefulWidget {
  const PublicFeedbackScreen({
    super.key,
    required this.firestoreService,
    this.onSelectThemeMode,
  });

  final FirestoreService firestoreService;

  /// Callback zum Umschalten des Hell/Dunkel-Modus (von [PublicFeedbackApp]
  /// gesetzt). Ist er null, wird der Umschalter nicht angezeigt.
  final ValueChanged<ThemeMode>? onSelectThemeMode;

  @override
  State<PublicFeedbackScreen> createState() => _PublicFeedbackScreenState();
}

class _PublicFeedbackScreenState extends State<PublicFeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();

  late final List<String> _stores = AppConfig.publicStoreNameList;

  FeedbackType _type = FeedbackType.complaint;
  late String _store = _stores.isNotEmpty ? _stores.first : 'Laden';
  int? _rating;
  DateTime? _incidentDate;

  bool _submitting = false;
  String? _error;
  String? _resultCode;

  static final DateFormat _dateFormat = DateFormat('dd.MM.yyyy', 'de_DE');

  @override
  void dispose() {
    _messageController.dispose();
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

      final code = CustomerFeedback.generateReferenceCode();
      final feedback = CustomerFeedback(
        orgId: AppConfig.defaultOrganizationId,
        referenceCode: code,
        type: _type,
        message: _messageController.text,
        storeName: _store,
        rating: _rating,
        incidentDate: _incidentDate,
        customerName: _nameController.text,
        customerContact: _contactController.text,
      );
      await widget.firestoreService.submitCustomerFeedback(feedback);

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
            ? 'Rückmeldungen sind derzeit nicht aktiviert. Bitte wende dich direkt an den Laden.'
            : 'Anmeldung fehlgeschlagen. Bitte versuche es später erneut.',
        error,
      );
    } on FirebaseException catch (error) {
      // permission-denied = Konfigurationsfehler (z.B. orgId-Pin in den Rules
      // passt nicht zu APP_DEFAULT_ORG_ID) — ehrliche Meldung statt
      // irreführendem "Internetverbindung prüfen".
      _handleError(
        error.code == 'permission-denied'
            ? 'Rückmeldungen sind für diesen Laden nicht freigeschaltet. Bitte wende dich direkt an den Laden.'
            : 'Deine Rückmeldung konnte nicht gesendet werden. Bitte versuche es später erneut.',
        error,
      );
    } catch (error) {
      _handleError(
        'Deine Rückmeldung konnte nicht gesendet werden. Bitte prüfe deine Internetverbindung und versuche es erneut.',
        error,
      );
    }
  }

  void _handleError(String message, [Object? cause]) {
    if (cause != null) {
      // Zentral & release-fest loggen, damit die echte Ursache diagnostizierbar
      // ist (der generische Text verschluckt sie sonst). AppLogger ist
      // dependency-frei (nur dart:developer) und im public-Pfad ohne Provider
      // sicher nutzbar; maskiert E-Mails automatisch.
      AppLogger.warning('Feedback-Submit fehlgeschlagen', error: cause);
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
    _messageController.clear();
    _nameController.clear();
    _contactController.clear();
    setState(() {
      _type = FeedbackType.complaint;
      _store = _stores.isNotEmpty ? _stores.first : 'Laden';
      _rating = null;
      _incidentDate = null;
      _resultCode = null;
      _error = null;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _incidentDate ?? now,
      // Vorfall liegt in der Vergangenheit -> bis zu einem Jahr zurück erlauben.
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      helpText: 'Wann war das?',
    );
    if (picked != null) {
      setState(() => _incidentDate = picked);
    }
  }

  static IconData _typeIcon(FeedbackType type) => switch (type) {
        FeedbackType.complaint => Icons.report_problem_outlined,
        FeedbackType.suggestion => Icons.lightbulb_outline,
        FeedbackType.praise => Icons.favorite_outline,
      };

  String get _messageHint => switch (_type) {
        FeedbackType.complaint =>
          'Was ist passiert? Beschreibe dein Anliegen so genau wie möglich.',
        FeedbackType.suggestion =>
          'Was sollten wir verbessern? Beschreibe deinen Vorschlag.',
        FeedbackType.praise => 'Was hat dir gefallen?',
      };

  @override
  Widget build(BuildContext context) {
    return PublicPageScaffold(
      brand: PublicBrandContent(
        glyph: Icons.feedback_outlined,
        title: 'Deine\nRückmeldung',
        subtitle:
            'Beschwerde, Verbesserungsvorschlag oder Lob – dein Feedback '
            'hilft uns, besser zu werden. Anonym, ganz ohne Anmeldung.',
        trustText: 'Ohne Anmeldung. Deine Angaben bleiben bei uns.',
        steps: const [
          'Anliegen wählen',
          'Nachricht schreiben',
          'Nummer für Rückfragen erhalten',
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
    final typeGroup = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PublicFieldLabel('Art'),
        SizedBox(height: spacing.sm),
        PublicChipRow<FeedbackType>(
          values: FeedbackType.values,
          selected: _type,
          onSelected: (value) => setState(() => _type = value),
          labelOf: (value) => value.label,
          iconOf: _typeIcon,
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
                  left: hasStoreChoice ? storeGroup : typeGroup,
                  right: hasStoreChoice ? typeGroup : null,
                ),
                SizedBox(height: spacing.lg),
                const PublicFieldLabel('Deine Nachricht'),
                SizedBox(height: spacing.sm),
                TextFormField(
                  controller: _messageController,
                  maxLines: 4,
                  maxLength: 2000,
                  textInputAction: TextInputAction.newline,
                  decoration: publicFieldDecoration(context, hint: _messageHint),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Bitte beschreibe dein Anliegen.'
                      : null,
                ),
              ],
            ),
          ),
          SizedBox(height: spacing.md),
          PublicSection(
            index: '2',
            title: 'Details',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PublicRatingTile(
                  rating: _rating,
                  emptyLabel: 'Bewertung (optional)',
                  setLabel: 'Deine Bewertung',
                  onTap: (star) => setState(
                    // Erneutes Tippen auf den aktuellen Stern setzt die
                    // Bewertung zurück (kein separater Lösch-Button nötig).
                    () => _rating = (_rating == star) ? null : star,
                  ),
                ),
                SizedBox(height: spacing.md),
                PublicDateTile(
                  label: _incidentDate != null
                      ? 'Wann: ${_dateFormat.format(_incidentDate!)}'
                      : 'Wann war das? (optional)',
                  onPick: _pickDate,
                  hasDate: _incidentDate != null,
                  onClear: () => setState(() => _incidentDate = null),
                  clearTooltip: 'Datum entfernen',
                ),
              ],
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
                Text(
                  'Wenn wir dir antworten sollen, hinterlasse Name und Kontakt.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                SizedBox(height: spacing.md),
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
                        'Deine Angaben nutzen wir nur zur Bearbeitung deiner '
                        'Rückmeldung und geben sie nicht weiter.',
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
            idleLabel: 'Absenden',
            busyLabel: 'Wird gesendet …',
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(BuildContext context, String code) {
    return PublicSuccessView(
      key: const ValueKey('success'),
      code: code,
      headline: 'Danke für deine Rückmeldung!',
      lead: 'Wir kümmern uns darum. Falls du nachfragen möchtest, gib bitte '
          'diese Nummer an:',
      codeCaption: 'Deine Vorgangs-Nummer',
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
      resetLabel: 'Weitere Rückmeldung abgeben',
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
