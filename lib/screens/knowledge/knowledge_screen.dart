import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../models/doc_article.dart';
import '../../providers/auth_provider.dart';
import '../../services/doc_repository.dart';
import '../../theme/theme_extensions.dart';
import '../../ui/app_hero_card.dart';
import '../../ui/app_search_field.dart';
import '../../widgets/breadcrumb_app_bar.dart';
import '../../widgets/empty_state.dart';
import 'doc_icons.dart';
import 'knowledge_article_screen.dart';

/// **Wissen & Hilfe** — der In-App-Doku-Bereich. Alle angemeldeten Nutzer sehen
/// die Fach-/Bedien-Doku; Admins zusaetzlich den Abschnitt „Technik" (Entwickler-
/// Doku). Browsen nach Kapiteln oder Volltext-nahe Suche ueber Titel/Schlagworte.
class KnowledgeScreen extends StatefulWidget {
  KnowledgeScreen({
    super.key,
    this.parentLabel = 'Profil',
    DocRepository? repository,
  }) : repository = repository ?? DocRepository.instance;

  final String parentLabel;
  final DocRepository repository;

  @override
  State<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends State<KnowledgeScreen> {
  late final Future<DocManifest> _manifestFuture;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _manifestFuture = widget.repository.loadManifest();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openArticle(DocArticle article) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => KnowledgeArticleScreen(
          article: article,
          repository: widget.repository,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthProvider>().profile;
    final spacing = context.spacing;
    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: widget.parentLabel,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const BreadcrumbItem(label: 'Wissen'),
        ],
      ),
      body: FutureBuilder<DocManifest>(
        future: _manifestFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final manifest = snapshot.data;
          if (manifest == null) {
            return const EmptyState(
              icon: Icons.menu_book_outlined,
              message: 'Die Wissensdatenbank konnte nicht geladen werden.',
            );
          }
          return Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                    spacing.md, spacing.md, spacing.md, spacing.sm),
                child: AppSearchField(
                  controller: _searchController,
                  hint: 'Wissen durchsuchen …',
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Expanded(
                child: _query.trim().isEmpty
                    ? _Browse(
                        manifest: manifest,
                        profile: profile,
                        onOpen: _openArticle,
                      )
                    : _Results(
                        hits: widget.repository
                            .search(manifest, _query, profile),
                        onOpen: _openArticle,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Browse extends StatelessWidget {
  const _Browse({
    required this.manifest,
    required this.profile,
    required this.onOpen,
  });

  final DocManifest manifest;
  final AppUserProfile? profile;
  final void Function(DocArticle) onOpen;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final sections = manifest.sections
        .where((s) => s.visibleArticles(profile).isNotEmpty)
        .toList();
    if (sections.isEmpty) {
      return const EmptyState(
        icon: Icons.menu_book_outlined,
        message: 'Für dieses Profil sind noch keine Artikel freigegeben.',
      );
    }

    final children = <Widget>[
      const _IntroCard(),
    ];
    DocAudience? lastAudience;
    for (final section in sections) {
      if (section.audience != lastAudience) {
        children.add(_AudienceHeader(audience: section.audience));
        lastAudience = section.audience;
      }
      children.add(_SectionGroup(
        section: section,
        profile: profile,
        onOpen: onOpen,
      ));
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(spacing.md, spacing.xs, spacing.md, spacing.xl),
      children: children,
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = context.spacing;
    return Padding(
      padding: EdgeInsets.only(bottom: spacing.md),
      child: AppHeroCard(
        tone: AppHeroTone.accent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Wissen & Hilfe',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            SizedBox(height: spacing.xs),
            Text(
              'Anleitungen zu jedem Bereich der App – von der Zeiterfassung über '
              'den Schichtplan bis zur Kasse. Tippen Sie ein Thema an oder '
              'durchsuchen Sie das Wissen oben.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudienceHeader extends StatelessWidget {
  const _AudienceHeader({required this.audience});

  final DocAudience audience;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = context.spacing;
    final isDev = audience == DocAudience.entwickler;
    return Padding(
      padding: EdgeInsets.only(top: spacing.sm, bottom: spacing.sm),
      child: Row(
        children: [
          Icon(isDev ? Icons.terminal_rounded : Icons.auto_stories_outlined,
              size: context.iconSizes.sm, color: theme.colorScheme.primary),
          SizedBox(width: spacing.sm),
          Text(
            isDev ? 'Technik (für Entwickler)' : 'Anleitungen',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionGroup extends StatelessWidget {
  const _SectionGroup({
    required this.section,
    required this.profile,
    required this.onOpen,
  });

  final DocSection section;
  final AppUserProfile? profile;
  final void Function(DocArticle) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = context.spacing;
    final articles = section.visibleArticles(profile);
    return Padding(
      padding: EdgeInsets.only(bottom: spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(spacing.xs, spacing.xs, 0, spacing.sm),
            child: Row(
              children: [
                Icon(docIcon(section.icon),
                    size: context.iconSizes.md,
                    color: theme.colorScheme.primary),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: Text(section.title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          for (final article in articles)
            _ArticleTile(article: article, onOpen: onOpen),
        ],
      ),
    );
  }
}

class _ArticleTile extends StatelessWidget {
  const _ArticleTile({required this.article, required this.onOpen, this.showSection = false});

  final DocArticle article;
  final void Function(DocArticle) onOpen;
  final bool showSection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final spacing = context.spacing;
    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(context.radii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(context.radii.md),
          onTap: () => onOpen(article),
          child: Padding(
            padding: EdgeInsets.all(spacing.s12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(docIcon(article.sectionIcon),
                    size: context.iconSizes.sm,
                    color: scheme.onSurfaceVariant),
                SizedBox(width: spacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showSection)
                        Text(article.sectionTitle.toUpperCase(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              letterSpacing: 0.6,
                            )),
                      Text(article.title,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      if (article.summary.isNotEmpty) ...[
                        SizedBox(height: spacing.xxs),
                        Text(article.summary,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.35,
                            )),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.hits, required this.onOpen});

  final List<DocSearchHit> hits;
  final void Function(DocArticle) onOpen;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    if (hits.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off_rounded,
        message: 'Keine Treffer. Versuchen Sie ein anderes Stichwort.',
      );
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(spacing.md, spacing.sm, spacing.md, spacing.xl),
      children: [
        for (final hit in hits)
          _ArticleTile(article: hit.article, onOpen: onOpen, showSection: true),
      ],
    );
  }
}
