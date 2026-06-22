import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/customer_feedback.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../widgets/breadcrumb_app_bar.dart';
import '../widgets/empty_state.dart';

/// Interner Eingang der über die öffentliche Webseite (/feedback) abgegebenen
/// Rückmeldungen (Beschwerden, Verbesserungsvorschläge, Lob). Anders als die
/// Kundenwünsche ist der Eingang NUR für Manager (canManageFeedback) sichtbar —
/// Beschwerden können sensibel sein.
///
/// Rückmeldungen sind reine Cloud-Daten (anonym von außen erzeugt), daher liest
/// der Screen direkt per [FirestoreService]-Stream — kein Provider/lokaler
/// Spiegel.
class CustomerFeedbackScreen extends StatefulWidget {
  const CustomerFeedbackScreen({
    super.key,
    this.parentLabel = 'Laden',
    this.firestoreService,
  });

  final String parentLabel;

  /// Injizierbar für Tests; sonst eigene Instanz (FirebaseFirestore.instance).
  final FirestoreService? firestoreService;

  @override
  State<CustomerFeedbackScreen> createState() => _CustomerFeedbackScreenState();
}

class _CustomerFeedbackScreenState extends State<CustomerFeedbackScreen> {
  late final FirestoreService _service =
      widget.firestoreService ?? FirestoreService();

  bool _showClosed = false;

  static final DateFormat _dateTimeFormat =
      DateFormat('dd.MM.yyyy HH:mm', 'de_DE');
  static final DateFormat _dateFormat = DateFormat('dd.MM.yyyy', 'de_DE');

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthProvider>().profile;

    final appBar = BreadcrumbAppBar(
      breadcrumbs: [
        BreadcrumbItem(
          label: widget.parentLabel,
          onTap: () => Navigator.of(context).pop(),
        ),
        const BreadcrumbItem(label: 'Kundenfeedback'),
      ],
    );

    // Eingang ist manager-only (Beschwerden können sensibel sein) — anders als
    // der Kundenwunsch-Eingang, den jedes aktive Mitglied sieht.
    if (profile == null || !profile.canManageFeedback) {
      return Scaffold(
        appBar: appBar,
        body: const Center(
          child: Text('Keine Berechtigung für das Kundenfeedback.'),
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: StreamBuilder<List<CustomerFeedback>>(
              stream: _service.watchCustomerFeedback(profile.orgId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('Feedback konnte nicht geladen werden.'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final all = snapshot.data!;
                final visible = _showClosed
                    ? all
                    : all.where((item) => item.status.isOpen).toList();
                final openCount =
                    all.where((item) => item.status.isOpen).length;

                return Column(
                  children: [
                    _buildHeader(context, openCount),
                    Expanded(
                      child: visible.isEmpty
                          ? const Center(
                              child: EmptyState(
                                icon: Icons.inbox_outlined,
                                title: 'Kein Feedback',
                                message:
                                    'Über die öffentliche Seite (/feedback) abgegebene Rückmeldungen erscheinen hier.',
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: visible.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) => _FeedbackCard(
                                feedback: visible[index],
                                dateTimeFormat: _dateTimeFormat,
                                dateFormat: _dateFormat,
                                onStatus: (status) =>
                                    _updateStatus(visible[index], status),
                                onDelete: () => _delete(visible[index]),
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, int openCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Text(
            openCount == 1
                ? '1 offene Rückmeldung'
                : '$openCount offene Rückmeldungen',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Spacer(),
          FilterChip(
            label: const Text('Erledigte zeigen'),
            selected: _showClosed,
            onSelected: (value) => setState(() => _showClosed = value),
          ),
        ],
      ),
    );
  }

  Future<void> _updateStatus(
    CustomerFeedback feedback,
    FeedbackStatus status,
  ) async {
    final id = feedback.id;
    if (id == null) {
      return;
    }
    final profile = context.read<AuthProvider>().profile;
    try {
      await _service.updateCustomerFeedbackStatus(
        orgId: feedback.orgId,
        feedbackId: id,
        status: status,
        handledByUid: profile?.uid,
      );
    } catch (_) {
      _snack('Status konnte nicht geändert werden.');
    }
  }

  Future<void> _delete(CustomerFeedback feedback) async {
    final id = feedback.id;
    if (id == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rückmeldung löschen?'),
        content: Text('Vorgang ${feedback.referenceCode} wird gelöscht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await _service.deleteCustomerFeedback(
          orgId: feedback.orgId, feedbackId: id);
    } catch (_) {
      _snack('Rückmeldung konnte nicht gelöscht werden.');
    }
  }

  void _snack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({
    required this.feedback,
    required this.dateTimeFormat,
    required this.dateFormat,
    required this.onStatus,
    required this.onDelete,
  });

  final CustomerFeedback feedback;
  final DateFormat dateTimeFormat;
  final DateFormat dateFormat;
  final ValueChanged<FeedbackStatus> onStatus;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rating = feedback.rating;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _TypeChip(type: feedback.type),
                const SizedBox(width: 8),
                Text(
                  feedback.referenceCode,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                _StatusChip(status: feedback.status),
                const Spacer(),
                PopupMenuButton<_FeedbackAction>(
                  onSelected: (action) {
                    switch (action) {
                      case _FeedbackAction.seen:
                        onStatus(FeedbackStatus.seen);
                      case _FeedbackAction.done:
                        onStatus(FeedbackStatus.done);
                      case _FeedbackAction.rejected:
                        onStatus(FeedbackStatus.rejected);
                      case _FeedbackAction.delete:
                        onDelete();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: _FeedbackAction.seen,
                      child: Text('Als gesehen markieren'),
                    ),
                    PopupMenuItem(
                      value: _FeedbackAction.done,
                      child: Text('Als erledigt markieren'),
                    ),
                    PopupMenuItem(
                      value: _FeedbackAction.rejected,
                      child: Text('Ablehnen'),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: _FeedbackAction.delete,
                      child: Text('Löschen'),
                    ),
                  ],
                ),
              ],
            ),
            if (rating != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  for (var star = 1; star <= 5; star++)
                    Icon(
                      star <= rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (feedback.storeName.trim().isNotEmpty)
                  _InfoChip(icon: Icons.store, label: feedback.storeName),
                if (feedback.incidentDate != null)
                  _InfoChip(
                    icon: Icons.event,
                    label: dateFormat.format(feedback.incidentDate!),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(feedback.message, style: theme.textTheme.bodyLarge),
            if (feedback.hasContact) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.person_outline,
                      size: 18, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      [
                        if (feedback.customerName?.trim().isNotEmpty ?? false)
                          feedback.customerName!.trim(),
                        if (feedback.customerContact?.trim().isNotEmpty ?? false)
                          feedback.customerContact!.trim(),
                      ].join(' · '),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ],
            if (feedback.createdAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'Eingegangen: ${dateTimeFormat.format(feedback.createdAt!.toLocal())}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _FeedbackAction { seen, done, rejected, delete }

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type});

  final FeedbackType type;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, Color bg, Color fg) = switch (type) {
      FeedbackType.complaint => (
          Icons.report_problem_outlined,
          scheme.errorContainer,
          scheme.onErrorContainer
        ),
      FeedbackType.suggestion => (
          Icons.lightbulb_outline,
          scheme.secondaryContainer,
          scheme.onSecondaryContainer
        ),
      FeedbackType.praise => (
          Icons.favorite_outline,
          scheme.primaryContainer,
          scheme.onPrimaryContainer
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            type.label,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: fg, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final FeedbackStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg) = switch (status) {
      FeedbackStatus.pending => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer
        ),
      FeedbackStatus.seen => (
          scheme.secondaryContainer,
          scheme.onSecondaryContainer
        ),
      FeedbackStatus.done => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant
        ),
      FeedbackStatus.rejected => (
          scheme.errorContainer,
          scheme.onErrorContainer
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
