import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/doc_article.dart';
import '../../providers/auth_provider.dart';
import '../../services/doc_repository.dart';
import '../../theme/theme_extensions.dart';
import '../../widgets/breadcrumb_app_bar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/markdown_view.dart';
import 'doc_icons.dart';

/// Liest einen einzelnen Doku-Artikel. Gepusht (imperativ) aus dem
/// [KnowledgeScreen] oder aus `article:<slug>`-Querverweisen anderer Artikel.
class KnowledgeArticleScreen extends StatefulWidget {
  KnowledgeArticleScreen({
    super.key,
    required this.article,
    DocRepository? repository,
  }) : repository = repository ?? DocRepository.instance;

  final DocArticle article;
  final DocRepository repository;

  @override
  State<KnowledgeArticleScreen> createState() => _KnowledgeArticleScreenState();
}

class _KnowledgeArticleScreenState extends State<KnowledgeArticleScreen> {
  late Future<String> _bodyFuture;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _bodyFuture = widget.repository.loadArticleBody(widget.article);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _openArticle(String slug) async {
    final profile = context.read<AuthProvider>().profile;
    final manifest = await widget.repository.loadManifest();
    final target = manifest.articleBySlug(slug);
    if (!mounted) {
      return;
    }
    if (target == null || !target.isVisibleTo(profile)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dieser Artikel ist nicht verfügbar.')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => KnowledgeArticleScreen(
          article: target,
          repository: widget.repository,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final article = widget.article;
    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: 'Wissen',
            onTap: () => Navigator.of(context).maybePop(),
          ),
          BreadcrumbItem(label: article.sectionTitle),
        ],
      ),
      body: FutureBuilder<String>(
        future: _bodyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final body = snapshot.data ?? kDocArticlePendingMarker;
          if (body.trim() == kDocArticlePendingMarker) {
            return _PendingArticle(article: article);
          }
          return Scrollbar(
            controller: _scrollController,
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: MarkdownView(
                    data: body,
                    onOpenArticle: _openArticle,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PendingArticle extends StatelessWidget {
  const _PendingArticle({required this.article});

  final DocArticle article;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = context.spacing;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(docIcon(article.sectionIcon),
                size: context.iconSizes.hero,
                color: theme.colorScheme.primary),
            SizedBox(height: spacing.md),
            Text(article.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            SizedBox(height: spacing.sm),
            Text(
              article.summary.isEmpty
                  ? 'Dieser Artikel wird gerade erstellt.'
                  : article.summary,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            SizedBox(height: spacing.lg),
            const EmptyState(
              icon: Icons.edit_note_outlined,
              message: 'Dieser Wissens-Artikel wird gerade geschrieben und '
                  'steht in Kürze zur Verfügung.',
            ),
          ],
        ),
      ),
    );
  }
}
