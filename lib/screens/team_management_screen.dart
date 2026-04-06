import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import 'package:provider/provider.dart';

import '../models/app_user.dart';
import '../models/compliance_rule_set.dart';
import '../models/employee_site_assignment.dart';
import '../models/employment_contract.dart';
import '../models/qualification_definition.dart';
import '../models/site_definition.dart';
import '../models/team_definition.dart';
import '../models/travel_time_rule.dart';
import '../models/user_invite.dart';
import '../models/user_settings.dart';
import '../providers/auth_provider.dart';
import '../providers/team_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/breadcrumb_app_bar.dart';

Future<bool> _confirmDelete(BuildContext context, String itemName) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('$itemName loeschen?'),
      content: Text('$itemName wird unwiderruflich geloescht.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Loeschen'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

class TeamManagementScreen extends StatefulWidget {
  const TeamManagementScreen({
    super.key,
    this.parentLabel = 'Profil',
  });

  final String parentLabel;

  @override
  State<TeamManagementScreen> createState() => _TeamManagementScreenState();
}

class _TeamManagementScreenState extends State<TeamManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String _memberSearch = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final team = context.watch<TeamProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = theme.appColors;

    if (!auth.isAdmin) {
      return const Center(
        child: Text('Teamverwaltung ist nur fuer Admins verfuegbar.'),
      );
    }

    final activeMembers =
        team.members.where((member) => member.isActive).length;
    final inactiveMembers = team.members.length - activeMembers;

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: widget.parentLabel,
            onTap: () => Navigator.of(context).pop(),
          ),
          const BreadcrumbItem(label: 'Teamverwaltung'),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: _TeamHeroBanner(
                      activeMembers: activeMembers,
                      inactiveMembers: inactiveMembers,
                      siteCount: team.sites.length,
                      teamCount: team.teams.length,
                      inviteCount: team.invites.length,
                      colorScheme: colorScheme,
                      appColors: appColors,
                    ),
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabBarDelegate(
                    tabBar: TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      dividerColor: Colors.transparent,
                      indicator: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      labelColor: colorScheme.onPrimary,
                      unselectedLabelColor: colorScheme.onSurfaceVariant,
                      labelStyle: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      unselectedLabelStyle:
                          theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      tabs: [
                        Tab(
                          icon: const Icon(Icons.people_alt_outlined),
                          text: 'Mitarbeiter (${team.members.length})',
                        ),
                        Tab(
                          icon: const Icon(Icons.storefront_outlined),
                          text: 'Standorte (${team.sites.length})',
                        ),
                        const Tab(
                          icon: Icon(Icons.groups_2_outlined),
                          text: 'Teams & Qualifikationen',
                        ),
                        const Tab(
                          icon: Icon(Icons.gavel_outlined),
                          text: 'Regelwerk',
                        ),
                      ],
                    ),
                    color: theme.scaffoldBackgroundColor,
                  ),
                ),
              ],
              body: TabBarView(
                controller: _tabController,
                children: [
                  _MembersTab(
                    searchQuery: _memberSearch,
                    onSearchChanged: (query) =>
                        setState(() => _memberSearch = query),
                    onOpenInviteEditor: () => _openInviteEditor(context),
                    onOpenMemberEditor: (member) =>
                        _openMemberEditor(context, member),
                  ),
                  _SitesTab(
                    onOpenSiteEditor: ({SiteDefinition? site}) =>
                        _openSiteEditor(context, site: site),
                    onOpenTravelTimeRuleEditor: ({TravelTimeRule? rule}) =>
                        _openTravelTimeRuleEditor(context, rule: rule),
                  ),
                  _TeamsAndQualificationsTab(
                    onOpenTeamEditor: ({TeamDefinition? teamDefinition}) =>
                        _openTeamEditor(context,
                            teamDefinition: teamDefinition),
                    onOpenQualificationEditor: (
                            {QualificationDefinition? qualification}) =>
                        _openQualificationEditor(context,
                            qualification: qualification),
                  ),
                  _ComplianceTab(
                    onOpenRuleSetEditor: (ruleSet) =>
                        _openRuleSetEditor(context, ruleSet: ruleSet),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openInviteEditor(BuildContext context) async {
    final currentUser = context.read<AuthProvider>().profile;
    final teamProvider = context.read<TeamProvider>();
    if (currentUser == null) {
      return;
    }
    final result = await showModalBottomSheet<UserInvite>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: _InviteEditorSheet(currentUser: currentUser),
      ),
    );

    if (result == null) {
      return;
    }
    await teamProvider.saveInvite(result);
  }

  Future<void> _openMemberEditor(
    BuildContext context,
    AppUserProfile member,
  ) async {
    final teamProvider = context.read<TeamProvider>();
    final existingContract = teamProvider.contracts
        .where((contract) => contract.userId == member.uid)
        .firstOrNull;
    final existingAssignments = teamProvider.siteAssignments
        .where((assignment) => assignment.userId == member.uid)
        .toList(growable: false);
    final result = await showModalBottomSheet<_MemberConfigurationResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: _MemberEditorSheet(
          member: member,
          sites: teamProvider.sites,
          qualifications: teamProvider.qualifications,
          contract: existingContract,
          assignments: existingAssignments,
        ),
      ),
    );

    if (result == null) {
      return;
    }
    await teamProvider.saveMemberConfiguration(
      profile: result.profile,
      contract: result.contract,
      siteAssignments: result.assignments,
    );
  }

  Future<void> _openTeamEditor(
    BuildContext context, {
    TeamDefinition? teamDefinition,
  }) async {
    final currentUser = context.read<AuthProvider>().profile;
    final teamProvider = context.read<TeamProvider>();
    if (currentUser == null) {
      return;
    }
    final result = await showModalBottomSheet<TeamDefinition>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: _TeamEditorSheet(
          currentUser: currentUser,
          members:
              teamProvider.members.where((member) => member.isActive).toList(),
          teamDefinition: teamDefinition,
        ),
      ),
    );

    if (result == null) {
      return;
    }
    await teamProvider.saveTeam(result);
  }

  Future<void> _openSiteEditor(
    BuildContext context, {
    SiteDefinition? site,
  }) async {
    final currentUser = context.read<AuthProvider>().profile;
    if (currentUser == null) {
      return;
    }
    final result = await showModalBottomSheet<SiteDefinition>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: _SiteEditorSheet(currentUser: currentUser, site: site),
      ),
    );
    if (result == null) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    try {
      await context.read<TeamProvider>().saveSite(result);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', ''))),
      );
    }
  }

  Future<void> _openQualificationEditor(
    BuildContext context, {
    QualificationDefinition? qualification,
  }) async {
    final currentUser = context.read<AuthProvider>().profile;
    if (currentUser == null) {
      return;
    }
    final result = await showModalBottomSheet<QualificationDefinition>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: _QualificationEditorSheet(
          currentUser: currentUser,
          qualification: qualification,
        ),
      ),
    );
    if (result == null) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    await context.read<TeamProvider>().saveQualification(result);
  }

  Future<void> _openRuleSetEditor(
    BuildContext context, {
    required ComplianceRuleSet ruleSet,
  }) async {
    final currentUser = context.read<AuthProvider>().profile;
    if (currentUser == null) {
      return;
    }
    final result = await showModalBottomSheet<ComplianceRuleSet>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: _RuleSetEditorSheet(
          currentUser: currentUser,
          ruleSet: ruleSet,
        ),
      ),
    );
    if (result == null) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    await context.read<TeamProvider>().saveRuleSet(result);
  }

  Future<void> _openTravelTimeRuleEditor(
    BuildContext context, {
    TravelTimeRule? rule,
  }) async {
    final currentUser = context.read<AuthProvider>().profile;
    final teamProvider = context.read<TeamProvider>();
    if (currentUser == null) {
      return;
    }
    if (teamProvider.sites.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Bitte zuerst mindestens zwei Standorte anlegen.',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    final result = await showModalBottomSheet<TravelTimeRule>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: _TravelTimeRuleEditorSheet(
          currentUser: currentUser,
          sites: teamProvider.sites,
          rule: rule,
        ),
      ),
    );
    if (result == null) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    await context.read<TeamProvider>().saveTravelTimeRule(result);
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  const _TabBarDelegate({required this.tabBar, required this.color});

  final TabBar tabBar;
  final Color color;

  @override
  double get minExtent => tabBar.preferredSize.height + 20;

  @override
  double get maxExtent => tabBar.preferredSize.height + 20;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: color,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: tabBar,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) =>
      tabBar != oldDelegate.tabBar || color != oldDelegate.color;
}

class _TeamHeroBanner extends StatelessWidget {
  const _TeamHeroBanner({
    required this.activeMembers,
    required this.inactiveMembers,
    required this.siteCount,
    required this.teamCount,
    required this.inviteCount,
    required this.colorScheme,
    required this.appColors,
  });

  final int activeMembers;
  final int inactiveMembers;
  final int siteCount;
  final int teamCount;
  final int inviteCount;
  final ColorScheme colorScheme;
  final AppThemeColors appColors;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.surfaceContainerLow,
            colorScheme.secondaryContainer.withValues(alpha: 0.82),
            appColors.infoContainer.withValues(alpha: 0.72),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Teamverwaltung',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Organisation, Mitarbeiter und Compliance zentral verwalten.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _TeamOverviewChip(
                  icon: Icons.people_alt_outlined,
                  label: '$activeMembers aktiv',
                  color: colorScheme.primary,
                ),
                if (inactiveMembers > 0)
                  _TeamOverviewChip(
                    icon: Icons.person_off_outlined,
                    label: '$inactiveMembers inaktiv',
                    color: colorScheme.outline,
                  ),
                _TeamOverviewChip(
                  icon: Icons.storefront_outlined,
                  label: '$siteCount Standorte',
                  color: colorScheme.tertiary,
                ),
                _TeamOverviewChip(
                  icon: Icons.groups_2_outlined,
                  label: '$teamCount Teams',
                  color: colorScheme.secondary,
                ),
                if (inviteCount > 0)
                  _TeamOverviewChip(
                    icon: Icons.mark_email_unread_outlined,
                    label: '$inviteCount Einladungen',
                    color: appColors.info,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamOverviewChip extends StatelessWidget {
  const _TeamOverviewChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _TeamTabIntroCard extends StatelessWidget {
  const _TeamTabIntroCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

class _ResponsiveTeamGrid extends StatelessWidget {
  const _ResponsiveTeamGrid({
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const minTileWidth = 320.0;
        if (width <= minTileWidth) {
          return Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }

        var columns = (width / minTileWidth).floor();
        if (columns < 1) {
          columns = 1;
        }
        if (columns > 3) {
          columns = 3;
        }
        const spacing = 12.0;
        final itemWidth = columns == 1
            ? width
            : (width - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(
                width: itemWidth,
                child: child,
              ),
          ],
        );
      },
    );
  }
}

class _MembersTab extends StatelessWidget {
  const _MembersTab({
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onOpenInviteEditor,
    required this.onOpenMemberEditor,
  });

  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onOpenInviteEditor;
  final void Function(AppUserProfile member) onOpenMemberEditor;

  @override
  Widget build(BuildContext context) {
    final team = context.watch<TeamProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final contractByUser = {
      for (final contract in team.contracts) contract.userId: contract,
    };
    final assignmentsByUser = <String, List<EmployeeSiteAssignment>>{};
    for (final assignment in team.siteAssignments) {
      assignmentsByUser
          .putIfAbsent(assignment.userId, () => [])
          .add(assignment);
    }

    final query = searchQuery.toLowerCase();
    final filteredMembers = query.isEmpty
        ? team.members
        : team.members.where((member) {
            return member.displayName.toLowerCase().contains(query) ||
                member.email.toLowerCase().contains(query);
          }).toList(growable: false);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _TeamTabIntroCard(
          icon: Icons.people_alt_outlined,
          title: 'Mitarbeiter und Einladungen',
          subtitle:
              'Profile, Rollen, Sollstunden und Standortzuweisungen an einer Stelle pflegen.',
          color: colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 720;
                final searchField = TextField(
                  onChanged: onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Mitarbeiter suchen...',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                );
                final inviteButton = FilledButton.icon(
                  onPressed: onOpenInviteEditor,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Einladen'),
                );

                if (narrow) {
                  return Column(
                    children: [
                      searchField,
                      const SizedBox(height: 12),
                      SizedBox(width: double.infinity, child: inviteButton),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: searchField),
                    const SizedBox(width: 12),
                    inviteButton,
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (team.invites.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.mark_email_unread_outlined,
            title: 'Offene Einladungen (${team.invites.length})',
          ),
          const SizedBox(height: 12),
          _ResponsiveTeamGrid(
            children: [
              for (final invite in team.invites)
                _InviteCard(
                  invite: invite,
                  onDelete: () async {
                    if (await _confirmDelete(context, 'Einladung')) {
                      if (context.mounted) {
                        context.read<TeamProvider>().deleteInvite(invite.id!);
                      }
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        _SectionHeader(
          icon: Icons.people_alt_outlined,
          title: 'Mitarbeiter (${filteredMembers.length})',
        ),
        const SizedBox(height: 12),
        if (filteredMembers.isEmpty)
          const _TeamEmptyState(
            icon: Icons.group_outlined,
            text: 'Keine Mitarbeiter gefunden.',
          )
        else
          _ResponsiveTeamGrid(
            children: [
              for (final member in filteredMembers)
                _MemberCard(
                  member: member,
                  contract: contractByUser[member.uid],
                  assignments: assignmentsByUser[member.uid] ?? const [],
                  onEdit: () => onOpenMemberEditor(member),
                  onToggleActive: () =>
                      context.read<TeamProvider>().setMemberActive(
                            uid: member.uid,
                            isActive: !member.isActive,
                          ),
                ),
            ],
          ),
      ],
    );
  }
}

class _SitesTab extends StatelessWidget {
  const _SitesTab({
    required this.onOpenSiteEditor,
    required this.onOpenTravelTimeRuleEditor,
  });

  final void Function({SiteDefinition? site}) onOpenSiteEditor;
  final void Function({TravelTimeRule? rule}) onOpenTravelTimeRuleEditor;

  @override
  Widget build(BuildContext context) {
    final team = context.watch<TeamProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final siteNamesById = {
      for (final site in team.sites)
        if (site.id != null) site.id!: site.name,
    };

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _TeamTabIntroCard(
          icon: Icons.storefront_outlined,
          title: 'Standorte und Wege',
          subtitle:
              'Standorte, Adressdaten und Fahrtzeiten fuer den operativen Einsatz pflegen.',
          color: colorScheme.tertiary,
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: () => onOpenSiteEditor(),
                  icon: const Icon(Icons.add),
                  label: const Text('Standort anlegen'),
                ),
                OutlinedButton.icon(
                  onPressed: () => onOpenTravelTimeRuleEditor(),
                  icon: const Icon(Icons.route_outlined),
                  label: const Text('Fahrtzeitregel'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _SectionHeader(
          icon: Icons.storefront_outlined,
          title: 'Standorte (${team.sites.length})',
        ),
        const SizedBox(height: 12),
        if (team.sites.isEmpty)
          const _TeamEmptyState(
            icon: Icons.storefront_outlined,
            text: 'Noch keine Standorte angelegt.',
          )
        else
          _ResponsiveTeamGrid(
            children: [
              for (final site in team.sites)
                _SiteCard(
                  site: site,
                  onEdit: () => onOpenSiteEditor(site: site),
                  onDelete: () async {
                    if (await _confirmDelete(context, 'Standort')) {
                      if (context.mounted) {
                        context.read<TeamProvider>().deleteSite(site.id!);
                      }
                    }
                  },
                ),
            ],
          ),
        if (team.travelTimeRules.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionHeader(
            icon: Icons.route_outlined,
            title: 'Fahrtzeiten (${team.travelTimeRules.length})',
          ),
          const SizedBox(height: 12),
          _ResponsiveTeamGrid(
            children: [
              for (final rule in team.travelTimeRules)
                _TravelTimeRuleCard(
                  rule: rule,
                  siteNamesById: siteNamesById,
                  onEdit: () => onOpenTravelTimeRuleEditor(rule: rule),
                  onDelete: () async {
                    if (await _confirmDelete(context, 'Fahrtzeitregel')) {
                      if (context.mounted) {
                        context
                            .read<TeamProvider>()
                            .deleteTravelTimeRule(rule.id!);
                      }
                    }
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _TeamsAndQualificationsTab extends StatelessWidget {
  const _TeamsAndQualificationsTab({
    required this.onOpenTeamEditor,
    required this.onOpenQualificationEditor,
  });

  final void Function({TeamDefinition? teamDefinition}) onOpenTeamEditor;
  final void Function({QualificationDefinition? qualification})
      onOpenQualificationEditor;

  @override
  Widget build(BuildContext context) {
    final team = context.watch<TeamProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final memberNames = {
      for (final member in team.members) member.uid: member.displayName,
    };

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _TeamTabIntroCard(
          icon: Icons.groups_2_outlined,
          title: 'Teams und Qualifikationen',
          subtitle:
              'Arbeitsgruppen, Besetzungen und benoetigte Qualifikationen uebersichtlich pflegen.',
          color: colorScheme.secondary,
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: () => onOpenTeamEditor(),
                  icon: const Icon(Icons.add),
                  label: const Text('Team anlegen'),
                ),
                OutlinedButton.icon(
                  onPressed: () => onOpenQualificationEditor(),
                  icon: const Icon(Icons.add),
                  label: const Text('Qualifikation'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _SectionHeader(
          icon: Icons.groups_2_outlined,
          title: 'Teams (${team.teams.length})',
        ),
        const SizedBox(height: 12),
        if (team.teams.isEmpty)
          const _TeamEmptyState(
            icon: Icons.groups_2_outlined,
            text: 'Noch keine Teams angelegt.',
          )
        else
          _ResponsiveTeamGrid(
            children: [
              for (final entry in team.teams)
                _TeamCard(
                  team: entry,
                  memberNames: entry.memberIds
                      .map((id) => memberNames[id] ?? id)
                      .toList(growable: false),
                  onEdit: () => onOpenTeamEditor(teamDefinition: entry),
                  onDelete: () async {
                    if (await _confirmDelete(context, 'Team')) {
                      if (context.mounted) {
                        context.read<TeamProvider>().deleteTeam(entry.id!);
                      }
                    }
                  },
                ),
            ],
          ),
        const SizedBox(height: 20),
        _SectionHeader(
          icon: Icons.verified_user_outlined,
          title: 'Qualifikationen (${team.qualifications.length})',
        ),
        const SizedBox(height: 12),
        if (team.qualifications.isEmpty)
          const _TeamEmptyState(
            icon: Icons.verified_user_outlined,
            text: 'Noch keine Qualifikationen hinterlegt.',
          )
        else
          _ResponsiveTeamGrid(
            children: [
              for (final qualification in team.qualifications)
                _QualificationCard(
                  qualification: qualification,
                  onEdit: () =>
                      onOpenQualificationEditor(qualification: qualification),
                  onDelete: () async {
                    if (await _confirmDelete(context, 'Qualifikation')) {
                      if (context.mounted) {
                        context
                            .read<TeamProvider>()
                            .deleteQualification(qualification.id!);
                      }
                    }
                  },
                ),
            ],
          ),
      ],
    );
  }
}

class _ComplianceTab extends StatelessWidget {
  const _ComplianceTab({required this.onOpenRuleSetEditor});

  final void Function(ComplianceRuleSet ruleSet) onOpenRuleSetEditor;

  Future<void> _updateProtectionRules(
    BuildContext context,
    AppUserProfile member, {
    bool? isMinor,
    bool? isPregnant,
  }) async {
    try {
      await context.read<TeamProvider>().saveMemberProtectionRules(
            userId: member.uid,
            isMinor: isMinor,
            isPregnant: isPregnant,
          );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }

  Future<void> _updateWorkRuleSettings(
    BuildContext context,
    AppUserProfile member,
    WorkRuleSettings settings,
  ) async {
    try {
      await context.read<TeamProvider>().saveMemberWorkRuleSettings(
            userId: member.uid,
            settings: settings,
          );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final team = context.watch<TeamProvider>();
    final ruleSet = team.ruleSets.isEmpty ? null : team.ruleSets.first;
    final colorScheme = Theme.of(context).colorScheme;
    final contractsByUser = <String, EmploymentContract>{};
    for (final contract in team.contracts) {
      contractsByUser.putIfAbsent(contract.userId, () => contract);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _TeamTabIntroCard(
          icon: Icons.gavel_outlined,
          title: 'Arbeitsrechtliche Compliance',
          subtitle:
              'Basis-Regelwerk und mitarbeiterbezogene Schutzregeln zentral verwalten.',
          color: colorScheme.secondary,
          trailing: ruleSet == null
              ? null
              : FilledButton.tonalIcon(
                  onPressed: () => onOpenRuleSetEditor(ruleSet),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Bearbeiten'),
                ),
        ),
        const SizedBox(height: 16),
        if (ruleSet == null) ...[
          const _TeamEmptyState(
            icon: Icons.rule_folder_outlined,
            text: 'Noch kein Regelwerk vorhanden.',
          ),
        ] else ...[
          _ResponsiveTeamGrid(
            children: [
              _ComplianceDetailCard(
                icon: Icons.hotel_outlined,
                title: 'Mindest-Ruhezeit',
                value: '${ruleSet.minRestMinutes ~/ 60} Stunden',
                subtitle:
                    '${ruleSet.minRestMinutes} Minuten zwischen zwei Schichten',
                color: colorScheme.primary,
              ),
              _ComplianceDetailCard(
                icon: Icons.coffee_outlined,
                title: 'Pausenregelung',
                value: ruleSet.breakRules
                    .map((rule) =>
                        'ab ${rule.afterMinutes ~/ 60}h: ${rule.requiredBreakMinutes} min')
                    .join(', '),
                subtitle: 'Pflichtpausen nach Arbeitszeitgesetz',
                color: colorScheme.tertiary,
              ),
              _ComplianceDetailCard(
                icon: Icons.timer_outlined,
                title: 'Maximale Schichtdauer',
                value:
                    '${(ruleSet.maxPlannedMinutesPerDay / 60).toStringAsFixed(1)} Stunden',
                subtitle:
                    '${ruleSet.maxPlannedMinutesPerDay} Minuten pro Tag maximal planbar',
                color: colorScheme.error,
              ),
              _ComplianceDetailCard(
                icon: Icons.euro_outlined,
                title: 'Minijob-Grenze',
                value:
                    '${(ruleSet.minijobMonthlyLimitCents / 100).toStringAsFixed(0)} EUR',
                subtitle:
                    'Monatliche Einkommensgrenze fuer geringfuegige Beschaeftigung',
                color: colorScheme.secondary,
              ),
              _ComplianceDetailCard(
                icon: Icons.nightlight_outlined,
                title: 'Nachtfenster',
                value:
                    '${(ruleSet.nightWindowStartMinutes ~/ 60).toString().padLeft(2, '0')}:${(ruleSet.nightWindowStartMinutes % 60).toString().padLeft(2, '0')} - '
                    '${(ruleSet.nightWindowEndMinutes ~/ 60).toString().padLeft(2, '0')}:${(ruleSet.nightWindowEndMinutes % 60).toString().padLeft(2, '0')} Uhr',
                subtitle: ruleSet.warnForwardRotation
                    ? 'Vorwaertsrotation wird gewarnt'
                    : 'Kein Vorwaertsrotations-Hinweis',
                color: colorScheme.outline,
              ),
            ],
          ),
          const SizedBox(height: 20),
          const _SectionHeader(
            icon: Icons.manage_accounts_outlined,
            title: 'Regelaktivierung pro Mitarbeiter',
          ),
          const SizedBox(height: 12),
          Text(
            'Jugendarbeitsschutz und Mutterschutz werden hier je Mitarbeiter aktiviert oder deaktiviert.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          _ResponsiveTeamGrid(
            children: [
              for (final member in team.members)
                _MemberRuleActivationCard(
                  member: member,
                  contract: contractsByUser[member.uid],
                  settings: member.workRuleSettings,
                  onMinorChanged: (value) {
                    _updateProtectionRules(
                      context,
                      member,
                      isMinor: value,
                    );
                  },
                  onPregnancyChanged: (value) {
                    _updateProtectionRules(
                      context,
                      member,
                      isPregnant: value,
                    );
                  },
                  onWorkRuleSettingsChanged: (settings) {
                    _updateWorkRuleSettings(
                      context,
                      member,
                      settings,
                    );
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ComplianceDetailCard extends StatelessWidget {
  const _ComplianceDetailCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberRuleActivationCard extends StatelessWidget {
  const _MemberRuleActivationCard({
    required this.member,
    required this.contract,
    required this.settings,
    required this.onMinorChanged,
    required this.onPregnancyChanged,
    required this.onWorkRuleSettingsChanged,
  });

  final AppUserProfile member;
  final EmploymentContract? contract;
  final WorkRuleSettings settings;
  final ValueChanged<bool> onMinorChanged;
  final ValueChanged<bool> onPregnancyChanged;
  final ValueChanged<WorkRuleSettings> onWorkRuleSettingsChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final activeLabels = <String>[
      if (contract?.isMinor == true) 'Jugendarbeitsschutz',
      if (contract?.isPregnant == true) 'Mutterschutz',
    ];
    final contractLabel = [
      if (contract?.label?.trim().isNotEmpty ?? false) contract!.label!.trim(),
      contract?.type.label ?? 'Standardvertrag',
    ].join(' · ');
    final totalActiveRules = settings.enabledCount + activeLabels.length;
    const totalRuleCount = WorkRuleSettings.ruleCount + 2;

    return Card(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: CircleAvatar(
          backgroundColor: colorScheme.secondaryContainer,
          foregroundColor: colorScheme.onSecondaryContainer,
          child: Text(
            member.displayName.isEmpty
                ? '?'
                : member.displayName.substring(0, 1).toUpperCase(),
          ),
        ),
        title: Text(
          member.displayName,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          '$contractLabel\n$totalActiveRules von $totalRuleCount Regeln aktiv',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        children: [
          if (activeLabels.isEmpty)
            Text(
              'Keine mitarbeiterbezogenen Schutzregeln aktiv.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final label in activeLabels)
                  Chip(
                    avatar: const Icon(Icons.verified_user_outlined, size: 18),
                    label: Text(label),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          Text(
            'Spezielle Schutzregeln',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          SwitchListTile.adaptive(
            value: contract?.isMinor ?? false,
            contentPadding: EdgeInsets.zero,
            title: const Text('Jugendarbeitsschutz'),
            subtitle: const Text(
              '8h Tagesgrenze, Nachtarbeits-Schutz und 12h Ruhezeit',
            ),
            onChanged: onMinorChanged,
          ),
          SwitchListTile.adaptive(
            value: contract?.isPregnant ?? false,
            contentPadding: EdgeInsets.zero,
            title: const Text('Mutterschutz'),
            subtitle: const Text(
              '8,5h Tagesgrenze und Nachtschicht-Schutz',
            ),
            onChanged: onPregnancyChanged,
          ),
          const SizedBox(height: 8),
          Text(
            'Regelwerk',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          SwitchListTile.adaptive(
            value: settings.enforceMinRestTime,
            contentPadding: EdgeInsets.zero,
            title: const Text('Ruhezeit'),
            subtitle: const Text(
              'Mindest-Ruhezeit zwischen zwei Einsaetzen pruefen',
            ),
            onChanged: (value) => onWorkRuleSettingsChanged(
              settings.copyWith(enforceMinRestTime: value),
            ),
          ),
          SwitchListTile.adaptive(
            value: settings.enforceBreakAfterSixHours,
            contentPadding: EdgeInsets.zero,
            title: const Text('Pause ab > 6 Stunden'),
            subtitle: const Text('Pflichtpause nach der 6-Stunden-Regel'),
            onChanged: (value) => onWorkRuleSettingsChanged(
              settings.copyWith(enforceBreakAfterSixHours: value),
            ),
          ),
          SwitchListTile.adaptive(
            value: settings.enforceBreakAfterNineHours,
            contentPadding: EdgeInsets.zero,
            title: const Text('Pause ab > 9 Stunden'),
            subtitle: const Text('Zusatzpause nach der 9-Stunden-Regel'),
            onChanged: (value) => onWorkRuleSettingsChanged(
              settings.copyWith(enforceBreakAfterNineHours: value),
            ),
          ),
          SwitchListTile.adaptive(
            value: settings.enforceMaxDailyMinutes,
            contentPadding: EdgeInsets.zero,
            title: const Text('Tagesgrenze'),
            subtitle: const Text('Maximal planbare Minuten pro Tag pruefen'),
            onChanged: (value) => onWorkRuleSettingsChanged(
              settings.copyWith(enforceMaxDailyMinutes: value),
            ),
          ),
          SwitchListTile.adaptive(
            value: settings.enforceMinijobLimit,
            contentPadding: EdgeInsets.zero,
            title: const Text('Minijob-Grenze'),
            subtitle: const Text('Monatliche Einkommensgrenze pruefen'),
            onChanged: (value) => onWorkRuleSettingsChanged(
              settings.copyWith(enforceMinijobLimit: value),
            ),
          ),
          SwitchListTile.adaptive(
            value: settings.warnDailyAverageExceeded,
            contentPadding: EdgeInsets.zero,
            title: const Text('Hinweis auf > 8h Tagesarbeit'),
            subtitle: const Text('Warnung fuer Ausgleichszeitraum anzeigen'),
            onChanged: (value) => onWorkRuleSettingsChanged(
              settings.copyWith(warnDailyAverageExceeded: value),
            ),
          ),
          SwitchListTile.adaptive(
            value: settings.warnForwardRotation,
            contentPadding: EdgeInsets.zero,
            title: const Text('Hinweis Vorwaertsrotation'),
            subtitle: const Text('Rueckwaertsrotation als Warnung markieren'),
            onChanged: (value) => onWorkRuleSettingsChanged(
              settings.copyWith(warnForwardRotation: value),
            ),
          ),
          SwitchListTile.adaptive(
            value: settings.warnOvertime,
            contentPadding: EdgeInsets.zero,
            title: const Text('Hinweis Ueberstunden'),
            subtitle: const Text('Abweichung von Sollstunden anzeigen'),
            onChanged: (value) => onWorkRuleSettingsChanged(
              settings.copyWith(warnOvertime: value),
            ),
          ),
          SwitchListTile.adaptive(
            value: settings.warnSundayWork,
            contentPadding: EdgeInsets.zero,
            title: const Text('Hinweis Sonntagsarbeit'),
            subtitle: const Text('Sonntagseinsaetze als Warnung markieren'),
            onChanged: (value) => onWorkRuleSettingsChanged(
              settings.copyWith(warnSundayWork: value),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }
}

class _ManagementCardShell extends StatelessWidget {
  const _ManagementCardShell({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    this.badges = const [],
    this.child,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final List<Widget> badges;
  final Widget? child;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, color: accent),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                ],
              ),
              if (badges.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: badges,
                ),
              ],
              if (child != null) ...[
                const SizedBox(height: 14),
                child!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamMetaChip extends StatelessWidget {
  const _TeamMetaChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.contract,
    required this.assignments,
    required this.onEdit,
    required this.onToggleActive,
  });

  final AppUserProfile member;
  final EmploymentContract? contract;
  final List<EmployeeSiteAssignment> assignments;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).appColors;
    final accent = member.isActive ? colorScheme.primary : colorScheme.outline;
    final contractLabel = contract == null
        ? 'Kein Vertrag'
        : '${contract!.type.label} · ${contract!.dailyHours.toStringAsFixed(1)} h Soll';
    final siteNames = assignments
        .map((item) => item.siteName.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final primarySite = assignments.firstWhereOrNull((item) => item.isPrimary);
    final qualificationCount =
        assignments.expand((item) => item.qualificationIds).toSet().length;
    final permissionSummary = member.isAdmin
        ? 'Vollzugriff'
        : _permissionSummaryLabel(member.effectivePermissions);

    return _ManagementCardShell(
      icon: member.isActive ? Icons.person_outline : Icons.person_off_outlined,
      accent: accent,
      title: member.displayName,
      subtitle: member.email,
      badges: [
        _TeamMetaChip(
          icon: Icons.security_outlined,
          label: member.role.label,
          color: accent,
        ),
        _TeamMetaChip(
          icon: Icons.schedule_outlined,
          label: contractLabel,
          color: colorScheme.secondary,
        ),
        _TeamMetaChip(
          icon: Icons.verified_user_outlined,
          label: permissionSummary,
          color: colorScheme.tertiary,
        ),
        _TeamMetaChip(
          icon: member.isActive
              ? Icons.check_circle_outline
              : Icons.pause_circle_outline,
          label: member.isActive ? 'Aktiv' : 'Inaktiv',
          color: member.isActive ? appColors.success : colorScheme.outline,
        ),
        if (siteNames.isNotEmpty)
          _TeamMetaChip(
            icon: Icons.storefront_outlined,
            label: '${siteNames.length} Standorte',
            color: colorScheme.tertiary,
          ),
        if (qualificationCount > 0)
          _TeamMetaChip(
            icon: Icons.verified_user_outlined,
            label: '$qualificationCount Qualifikationen',
            color: colorScheme.secondary,
          ),
      ],
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'edit') {
            onEdit();
          } else if (value == 'toggle') {
            onToggleActive();
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: 'edit',
            child: Text('Bearbeiten'),
          ),
          PopupMenuItem(
            value: 'toggle',
            child: Text(member.isActive ? 'Deaktivieren' : 'Aktivieren'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (primarySite != null)
            Text(
              'Primaerstandort: ${primarySite.siteName}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          if (siteNames.isNotEmpty) ...[
            if (primarySite != null) const SizedBox(height: 6),
            Text(
              siteNames.join(', '),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({
    required this.invite,
    required this.onDelete,
  });

  final UserInvite invite;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).appColors;
    return _ManagementCardShell(
      icon: Icons.mail_outline,
      accent: appColors.info,
      title: invite.settings.name.isEmpty ? invite.email : invite.settings.name,
      subtitle: invite.email,
      badges: [
        _TeamMetaChip(
          icon: Icons.pending_outlined,
          label: 'Ausstehend',
          color: appColors.info,
        ),
        _TeamMetaChip(
          icon: Icons.security_outlined,
          label: invite.role.label,
          color: colorScheme.primary,
        ),
        _TeamMetaChip(
          icon: Icons.schedule_outlined,
          label: '${invite.settings.dailyHours.toStringAsFixed(1)} h Soll',
          color: colorScheme.secondary,
        ),
        _TeamMetaChip(
          icon: Icons.verified_user_outlined,
          label: invite.role == UserRole.admin
              ? 'Vollzugriff'
              : _permissionSummaryLabel(invite.effectivePermissions),
          color: colorScheme.tertiary,
        ),
      ],
      trailing: IconButton(
        tooltip: 'Einladung loeschen',
        onPressed: onDelete,
        icon: const Icon(Icons.delete_outline),
      ),
    );
  }
}

String _permissionSummaryLabel(UserPermissions permissions) {
  final labels = permissions.summaryLabels();
  if (labels.isEmpty) {
    return 'Eingeschraenkt';
  }
  return labels.take(3).join(' · ');
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({
    required this.team,
    required this.memberNames,
    required this.onEdit,
    required this.onDelete,
  });

  final TeamDefinition team;
  final List<String> memberNames;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final membersLabel =
        memberNames.isEmpty ? 'Keine Mitglieder' : memberNames.join(', ');
    final colorScheme = Theme.of(context).colorScheme;
    return _ManagementCardShell(
      icon: Icons.groups_2_outlined,
      accent: colorScheme.secondary,
      title: team.name,
      subtitle: '${team.memberIds.length} Mitglieder',
      badges: [
        _TeamMetaChip(
          icon: Icons.people_alt_outlined,
          label: '${team.memberIds.length} Mitglieder',
          color: colorScheme.secondary,
        ),
      ],
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'edit') {
            onEdit();
          } else if (value == 'delete') {
            onDelete();
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'edit',
            child: Text('Bearbeiten'),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Text('Loeschen'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            membersLabel,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          if (team.description?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(
              team.description!.trim(),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

class _SiteCard extends StatelessWidget {
  const _SiteCard({
    required this.site,
    required this.onEdit,
    required this.onDelete,
  });

  final SiteDefinition site;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final meta = [
      if (site.code?.trim().isNotEmpty == true) site.code!,
      if (site.federalState?.trim().isNotEmpty == true) site.federalState!,
      'Deutschland',
    ].join(' · ');
    final detailLines = [
      if (site.displayAddress.isNotEmpty) site.displayAddress,
      if (site.description?.trim().isNotEmpty == true) site.description!.trim(),
    ];
    final subtitle = [
      if (meta.isNotEmpty) meta,
      ...detailLines,
    ].join('\n');
    return _ManagementCardShell(
      icon: Icons.storefront_outlined,
      accent: colorScheme.tertiary,
      title: site.name,
      subtitle: subtitle.isEmpty ? 'Keine Adressdaten hinterlegt' : subtitle,
      badges: [
        if (site.displayCode.isNotEmpty)
          _TeamMetaChip(
            icon: Icons.badge_outlined,
            label: site.displayCode,
            color: colorScheme.primary,
          ),
        if (site.federalState?.trim().isNotEmpty == true)
          _TeamMetaChip(
            icon: Icons.map_outlined,
            label: site.federalState!,
            color: colorScheme.tertiary,
          ),
      ],
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'edit') {
            onEdit();
          } else if (value == 'delete') {
            onDelete();
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Bearbeiten')),
          PopupMenuItem(value: 'delete', child: Text('Loeschen')),
        ],
      ),
    );
  }
}

class _QualificationCard extends StatelessWidget {
  const _QualificationCard({
    required this.qualification,
    required this.onEdit,
    required this.onDelete,
  });

  final QualificationDefinition qualification;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final avatarColor = _tryParseQualificationColor(qualification.color);
    final colorScheme = Theme.of(context).colorScheme;

    return _ManagementCardShell(
      icon: Icons.verified_user_outlined,
      accent: avatarColor ?? colorScheme.secondary,
      title: qualification.name,
      subtitle: qualification.description ?? 'Keine Beschreibung',
      badges: [
        _TeamMetaChip(
          icon: Icons.palette_outlined,
          label: qualification.color?.trim().isNotEmpty == true
              ? qualification.color!
              : 'Standardfarbe',
          color: avatarColor ?? colorScheme.secondary,
        ),
      ],
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'edit') {
            onEdit();
          } else if (value == 'delete') {
            onDelete();
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Bearbeiten')),
          PopupMenuItem(value: 'delete', child: Text('Loeschen')),
        ],
      ),
    );
  }
}

class _TravelTimeRuleCard extends StatelessWidget {
  const _TravelTimeRuleCard({
    required this.rule,
    required this.siteNamesById,
    required this.onEdit,
    required this.onDelete,
  });

  final TravelTimeRule rule;
  final Map<String, String> siteNamesById;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fromLabel = siteNamesById[rule.fromSiteId] ?? rule.fromSiteId;
    final toLabel = siteNamesById[rule.toSiteId] ?? rule.toSiteId;
    return _ManagementCardShell(
      icon: Icons.route_outlined,
      accent: colorScheme.primary,
      title: '$fromLabel → $toLabel',
      subtitle:
          '${rule.travelMinutes} min${rule.countsAsWorkTime ? ' · als Arbeitszeit' : ''}',
      onTap: onEdit,
      badges: [
        _TeamMetaChip(
          icon: Icons.schedule_outlined,
          label: '${rule.travelMinutes} min',
          color: colorScheme.primary,
        ),
        _TeamMetaChip(
          icon: rule.countsAsWorkTime
              ? Icons.paid_outlined
              : Icons.hourglass_disabled_outlined,
          label: rule.countsAsWorkTime ? 'Arbeitszeit' : 'Nur Info',
          color: rule.countsAsWorkTime
              ? colorScheme.secondary
              : colorScheme.outline,
        ),
      ],
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'edit') {
            onEdit();
          } else if (value == 'delete') {
            onDelete();
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'edit',
            child: Text('Bearbeiten'),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Text('Loeschen'),
          ),
        ],
      ),
    );
  }
}

class _MemberConfigurationResult {
  const _MemberConfigurationResult({
    required this.profile,
    required this.contract,
    required this.assignments,
  });

  final AppUserProfile profile;
  final EmploymentContract contract;
  final List<EmployeeSiteAssignment> assignments;
}

class _TeamEmptyState extends StatelessWidget {
  const _TeamEmptyState({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.75);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(icon, size: 40, color: muted),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: muted)),
        ],
      ),
    );
  }
}

class _InviteEditorSheet extends StatefulWidget {
  const _InviteEditorSheet({required this.currentUser});

  final AppUserProfile currentUser;

  @override
  State<_InviteEditorSheet> createState() => _InviteEditorSheetState();
}

class _InviteEditorSheetState extends State<_InviteEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _hoursCtrl = TextEditingController(text: '8.0');
  String _currency = 'EUR';
  UserRole _role = UserRole.employee;
  UserPermissions _permissions =
      UserPermissions.defaultsForRole(UserRole.employee);

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    _rateCtrl.dispose();
    _hoursCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Einladung anlegen',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailCtrl,
              decoration: const InputDecoration(
                labelText: 'E-Mail',
                prefixIcon: Icon(Icons.mail_outline),
              ),
              validator: (value) {
                if ((value ?? '').trim().isEmpty || !(value!.contains('@'))) {
                  return 'Bitte gueltige E-Mail eingeben';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<UserRole>(
              initialValue: _role,
              decoration: const InputDecoration(
                labelText: 'Rolle',
                prefixIcon: Icon(Icons.security_outlined),
              ),
              items: UserRole.values
                  .map(
                    (role) => DropdownMenuItem(
                      value: role,
                      child: Text(role.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _role = value;
                    _permissions = UserPermissions.defaultsForRole(value);
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            _PermissionsSection(
              role: _role,
              permissions: _permissions,
              onChanged: (value) => setState(() => _permissions = value),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _hoursCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Soll-Stunden pro Tag',
                prefixIcon: Icon(Icons.schedule),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _rateCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Stundenlohn',
                prefixIcon: Icon(Icons.euro),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _currency,
              decoration: const InputDecoration(
                labelText: 'Waehrung',
                prefixIcon: Icon(Icons.currency_exchange),
              ),
              items: const [
                DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                DropdownMenuItem(value: 'CHF', child: Text('CHF')),
                DropdownMenuItem(value: 'USD', child: Text('USD')),
                DropdownMenuItem(value: 'GBP', child: Text('GBP')),
              ],
              onChanged: (value) {
                setState(() => _currency = value ?? 'EUR');
              },
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.send),
              label: const Text('Einladung speichern'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    Navigator.of(context).pop(
      UserInvite(
        orgId: widget.currentUser.orgId,
        email: _emailCtrl.text.trim(),
        role: _role,
        settings: UserSettings(
          name: _nameCtrl.text.trim(),
          hourlyRate: double.tryParse(_rateCtrl.text) ?? 0,
          dailyHours: double.tryParse(_hoursCtrl.text) ?? 8,
          currency: _currency,
        ),
        permissions: _permissions,
        createdByUid: widget.currentUser.uid,
      ),
    );
  }
}

class _MemberEditorSheet extends StatefulWidget {
  const _MemberEditorSheet({
    required this.member,
    required this.sites,
    required this.qualifications,
    this.contract,
    this.assignments = const [],
  });

  final AppUserProfile member;
  final List<SiteDefinition> sites;
  final List<QualificationDefinition> qualifications;
  final EmploymentContract? contract;
  final List<EmployeeSiteAssignment> assignments;

  @override
  State<_MemberEditorSheet> createState() => _MemberEditorSheetState();
}

class _MemberEditorSheetState extends State<_MemberEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _rateCtrl;
  late final TextEditingController _hoursCtrl;
  late final TextEditingController _contractLabelCtrl;
  late String _currency;
  late UserRole _role;
  late EmploymentType _employmentType;
  late DateTime _validFrom;
  late UserPermissions _permissions;
  Set<String> _selectedSiteIds = <String>{};
  String? _primarySiteId;
  Set<String> _selectedQualificationIds = <String>{};
  final Map<String, TextEditingController> _roleCtrls = {};

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.member.settings.name);
    _rateCtrl = TextEditingController(
      text: widget.member.settings.hourlyRate.toStringAsFixed(2),
    );
    _hoursCtrl = TextEditingController(
      text: widget.member.settings.dailyHours.toStringAsFixed(1),
    );
    _contractLabelCtrl = TextEditingController(
      text: widget.contract?.label ?? 'Standardvertrag',
    );
    _currency = widget.member.settings.currency;
    _role = widget.member.role;
    _permissions = widget.member.effectivePermissions;
    _employmentType = widget.contract?.type ?? EmploymentType.fullTime;
    _validFrom = widget.contract?.validFrom ?? DateTime.now();
    _selectedSiteIds = widget.assignments.map((item) => item.siteId).toSet();
    _primarySiteId =
        widget.assignments.firstWhereOrNull((item) => item.isPrimary)?.siteId ??
            widget.assignments.firstOrNull?.siteId;
    _selectedQualificationIds =
        widget.assignments.expand((item) => item.qualificationIds).toSet();
    for (final assignment in widget.assignments) {
      _roleCtrls[assignment.siteId] =
          TextEditingController(text: assignment.role ?? '');
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _rateCtrl.dispose();
    _hoursCtrl.dispose();
    _contractLabelCtrl.dispose();
    for (final controller in _roleCtrls.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mitarbeiter bearbeiten',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<UserRole>(
              initialValue: _role,
              decoration: const InputDecoration(
                labelText: 'Rolle',
                prefixIcon: Icon(Icons.security_outlined),
              ),
              items: UserRole.values
                  .map(
                    (role) => DropdownMenuItem(
                      value: role,
                      child: Text(role.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _role = value;
                    _permissions = UserPermissions.defaultsForRole(value);
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            _PermissionsSection(
              role: _role,
              permissions: _permissions,
              onChanged: (value) => setState(() => _permissions = value),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _hoursCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Soll-Stunden pro Tag',
                prefixIcon: Icon(Icons.schedule),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _rateCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Stundenlohn',
                prefixIcon: Icon(Icons.euro),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _currency,
              decoration: const InputDecoration(
                labelText: 'Waehrung',
                prefixIcon: Icon(Icons.currency_exchange),
              ),
              items: const [
                DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                DropdownMenuItem(value: 'CHF', child: Text('CHF')),
                DropdownMenuItem(value: 'USD', child: Text('USD')),
                DropdownMenuItem(value: 'GBP', child: Text('GBP')),
              ],
              onChanged: (value) {
                setState(() => _currency = value ?? 'EUR');
              },
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              'Vertrag',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _contractLabelCtrl,
              decoration: const InputDecoration(
                labelText: 'Vertragsbezeichnung',
                prefixIcon: Icon(Icons.description_outlined),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<EmploymentType>(
              initialValue: _employmentType,
              decoration: const InputDecoration(
                labelText: 'Arbeitszeitmodell',
                prefixIcon: Icon(Icons.assignment_ind_outlined),
              ),
              items: EmploymentType.values
                  .map(
                    (type) => DropdownMenuItem(
                      value: type,
                      child: Text(type.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _employmentType = value);
                }
              },
            ),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.calendar_today_outlined),
                title: const Text('Gueltig ab'),
                subtitle: Text(DateFormat('dd.MM.yyyy').format(_validFrom)),
                onTap: _pickValidFrom,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Jugendarbeitsschutz und Mutterschutz werden zentral im Tab Regelwerk pro Mitarbeiter verwaltet.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              'Standorte und Qualifikationen',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            if (widget.sites.isEmpty)
              const Text('Bitte zuerst Standorte anlegen.')
            else
              Column(
                children: [
                  for (final site in widget.sites) ...[
                    Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FilterChip(
                              label: Text(site.name),
                              selected: _selectedSiteIds.contains(site.id),
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedSiteIds.add(site.id!);
                                    _primarySiteId ??= site.id;
                                  } else {
                                    _selectedSiteIds.remove(site.id);
                                    if (_primarySiteId == site.id) {
                                      _primarySiteId =
                                          _selectedSiteIds.firstOrNull;
                                    }
                                  }
                                });
                              },
                            ),
                            if (_selectedSiteIds.contains(site.id)) ...[
                              const SizedBox(height: 10),
                              CheckboxListTile(
                                value: _primarySiteId == site.id,
                                title: const Text('Primaerstandort'),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                onChanged: (value) {
                                  setState(() {
                                    if (value == true) {
                                      _primarySiteId = site.id;
                                    } else if (_primarySiteId == site.id) {
                                      _primarySiteId = _selectedSiteIds
                                          .where((candidate) =>
                                              candidate != site.id)
                                          .firstOrNull;
                                    }
                                  });
                                },
                              ),
                              TextFormField(
                                controller: _roleCtrls.putIfAbsent(
                                  site.id!,
                                  () => TextEditingController(),
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Rolle an diesem Standort',
                                  prefixIcon: Icon(Icons.badge_outlined),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            const SizedBox(height: 8),
            Text(
              'Qualifikationen',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final qualification in widget.qualifications)
                  FilterChip(
                    label: Text(qualification.name),
                    selected:
                        _selectedQualificationIds.contains(qualification.id),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedQualificationIds.add(qualification.id!);
                        } else {
                          _selectedQualificationIds.remove(qualification.id);
                        }
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Speichern'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final isMinor = widget.contract?.isMinor ?? false;
    final isPregnant = widget.contract?.isPregnant ?? false;
    final maxDailyMinutes = isMinor
        ? 480
        : (isPregnant ? 510 : (widget.contract?.maxDailyMinutes ?? 600));

    final siteAssignments = widget.sites
        .where((site) => _selectedSiteIds.contains(site.id))
        .map(
          (site) => EmployeeSiteAssignment(
            orgId: widget.member.orgId,
            userId: widget.member.uid,
            siteId: site.id!,
            siteName: site.name,
            role: _roleCtrls[site.id!]?.text.trim().isEmpty ?? true
                ? null
                : _roleCtrls[site.id!]!.text.trim(),
            qualificationIds: _selectedQualificationIds.toList(growable: false),
            isPrimary: _primarySiteId == site.id,
          ),
        )
        .toList(growable: false);

    Navigator.of(context).pop(
      _MemberConfigurationResult(
        profile: widget.member.copyWith(
          role: _role,
          permissions: _permissions,
          settings: widget.member.settings.copyWith(
            name: _nameCtrl.text.trim(),
            hourlyRate: double.tryParse(_rateCtrl.text) ?? 0,
            dailyHours: double.tryParse(_hoursCtrl.text) ?? 8,
            currency: _currency,
          ),
        ),
        contract: EmploymentContract(
          id: widget.contract?.id,
          orgId: widget.member.orgId,
          userId: widget.member.uid,
          label: _contractLabelCtrl.text.trim().isEmpty
              ? null
              : _contractLabelCtrl.text.trim(),
          type: _employmentType,
          validFrom: _validFrom,
          weeklyHours: (double.tryParse(_hoursCtrl.text) ?? 8) * 5,
          dailyHours: double.tryParse(_hoursCtrl.text) ?? 8,
          hourlyRate: double.tryParse(_rateCtrl.text) ?? 0,
          currency: _currency,
          vacationDays: widget.member.settings.vacationDays,
          maxDailyMinutes: maxDailyMinutes,
          monthlyIncomeLimitCents:
              _employmentType == EmploymentType.miniJob ? 60300 : null,
          isMinor: isMinor,
          isPregnant: isPregnant,
        ),
        assignments: siteAssignments,
      ),
    );
  }

  Future<void> _pickValidFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _validFrom,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      locale: const Locale('de', 'DE'),
    );
    if (picked != null) {
      setState(() => _validFrom = picked);
    }
  }
}

class _PermissionsSection extends StatelessWidget {
  const _PermissionsSection({
    required this.role,
    required this.permissions,
    required this.onChanged,
  });

  final UserRole role;
  final UserPermissions permissions;
  final ValueChanged<UserPermissions> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (role == UserRole.admin) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.admin_panel_settings_outlined,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Zugriffsrechte',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Admins haben immer Vollzugriff auf alle Bereiche. '
                      'Die Einzelrechte werden automatisch voll gesetzt.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Zugriffsrechte',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Der Admin legt fest, welche Bereiche sichtbar sind und wo '
              'bearbeitet werden darf.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              value: permissions.canViewSchedule,
              contentPadding: EdgeInsets.zero,
              title: const Text('Schichtplan ansehen'),
              subtitle: const Text('Plan-Tab und eigene Schichten sehen'),
              onChanged: (value) {
                onChanged(
                  permissions.copyWith(
                    canViewSchedule: value,
                    canEditSchedule:
                        value ? permissions.canEditSchedule : false,
                  ),
                );
              },
            ),
            SwitchListTile.adaptive(
              value: permissions.canEditSchedule,
              contentPadding: EdgeInsets.zero,
              title: const Text('Schichtplan bearbeiten'),
              subtitle: const Text(
                'Schichten planen sowie Anfragen und Tausch bearbeiten',
              ),
              onChanged: (value) {
                onChanged(
                  permissions.copyWith(
                    canViewSchedule: value ? true : permissions.canViewSchedule,
                    canEditSchedule: value,
                  ),
                );
              },
            ),
            SwitchListTile.adaptive(
              value: permissions.canViewTimeTracking,
              contentPadding: EdgeInsets.zero,
              title: const Text('Zeiterfassung ansehen'),
              subtitle: const Text('Zeit-Tab und eigene Zeiten sehen'),
              onChanged: (value) {
                onChanged(
                  permissions.copyWith(
                    canViewTimeTracking: value,
                    canEditTimeEntries:
                        value ? permissions.canEditTimeEntries : false,
                  ),
                );
              },
            ),
            SwitchListTile.adaptive(
              value: permissions.canEditTimeEntries,
              contentPadding: EdgeInsets.zero,
              title: const Text('Zeiteintraege bearbeiten'),
              subtitle: const Text(
                'Eintraege, Vorlagen und Stempeluhr aktiv verwenden',
              ),
              onChanged: (value) {
                onChanged(
                  permissions.copyWith(
                    canViewTimeTracking:
                        value ? true : permissions.canViewTimeTracking,
                    canEditTimeEntries: value,
                  ),
                );
              },
            ),
            SwitchListTile.adaptive(
              value: permissions.canViewReports,
              contentPadding: EdgeInsets.zero,
              title: const Text('Berichte ansehen'),
              subtitle: const Text(
                'Monatsbericht und Statistiken aufrufen',
              ),
              onChanged: (value) {
                onChanged(permissions.copyWith(canViewReports: value));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SiteEditorSheet extends StatefulWidget {
  const _SiteEditorSheet({
    required this.currentUser,
    this.site,
  });

  final AppUserProfile currentUser;
  final SiteDefinition? site;

  @override
  State<_SiteEditorSheet> createState() => _SiteEditorSheetState();
}

class _SiteEditorSheetState extends State<_SiteEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _codeCtrl;
  late final TextEditingController _streetCtrl;
  late final TextEditingController _postalCodeCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _descriptionCtrl;
  String? _selectedFederalState;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.site?.name ?? '');
    _codeCtrl = TextEditingController(text: widget.site?.code ?? '');
    _streetCtrl = TextEditingController(text: widget.site?.street ?? '');
    _postalCodeCtrl =
        TextEditingController(text: widget.site?.postalCode ?? '');
    _cityCtrl = TextEditingController(text: widget.site?.city ?? '');
    _selectedFederalState = SiteDefinition.normalizeGermanFederalState(
      widget.site?.federalState,
    );
    _descriptionCtrl =
        TextEditingController(text: widget.site?.description ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _streetCtrl.dispose();
    _postalCodeCtrl.dispose();
    _cityCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.site == null ? 'Standort anlegen' : 'Standort bearbeiten',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Standortname',
                prefixIcon: Icon(Icons.storefront_outlined),
              ),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Bitte Namen eingeben' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _codeCtrl,
              decoration: const InputDecoration(
                labelText: 'Code',
                prefixIcon: Icon(Icons.tag_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _streetCtrl,
              decoration: const InputDecoration(
                labelText: 'Strasse und Hausnummer',
                prefixIcon: Icon(Icons.home_work_outlined),
              ),
              validator: (value) {
                final trimmed = (value ?? '').trim();
                if (trimmed.isEmpty) {
                  return 'Bitte eine Adresse eingeben';
                }
                if (!RegExp(r'\d').hasMatch(trimmed)) {
                  return 'Bitte Strasse und Hausnummer eingeben';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _postalCodeCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'PLZ',
                      prefixIcon: Icon(Icons.markunread_mailbox_outlined),
                    ),
                    validator: (value) {
                      if (!SiteDefinition.isValidGermanPostalCode(
                        value ?? '',
                      )) {
                        return 'Deutsche PLZ mit 5 Ziffern';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _cityCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Ort',
                      prefixIcon: Icon(Icons.location_city_outlined),
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Bitte Ort eingeben'
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedFederalState,
              decoration: const InputDecoration(
                labelText: 'Bundesland',
                prefixIcon: Icon(Icons.map_outlined),
              ),
              items: SiteDefinition.germanFederalStates
                  .map(
                    (state) => DropdownMenuItem<String>(
                      value: state,
                      child: Text(state),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                setState(() => _selectedFederalState = value);
              },
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Bitte Bundesland auswaehlen'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: 'Deutschland',
              enabled: false,
              decoration: const InputDecoration(
                labelText: 'Land',
                prefixIcon: Icon(Icons.flag_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Beschreibung',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Speichern'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    Navigator.of(context).pop(
      SiteDefinition(
        id: widget.site?.id,
        orgId: widget.currentUser.orgId,
        name: _nameCtrl.text.trim(),
        code: _codeCtrl.text.trim().isEmpty ? null : _codeCtrl.text.trim(),
        street:
            _streetCtrl.text.trim().isEmpty ? null : _streetCtrl.text.trim(),
        postalCode: _postalCodeCtrl.text.trim().isEmpty
            ? null
            : _postalCodeCtrl.text.trim(),
        city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
        federalState: _selectedFederalState,
        countryCode: SiteDefinition.germanyCountryCode,
        latitude: widget.site?.latitude,
        longitude: widget.site?.longitude,
        description: _descriptionCtrl.text.trim().isEmpty
            ? null
            : _descriptionCtrl.text.trim(),
        createdByUid: widget.currentUser.uid,
      ),
    );
  }
}

class _QualificationEditorSheet extends StatefulWidget {
  const _QualificationEditorSheet({
    required this.currentUser,
    this.qualification,
  });

  final AppUserProfile currentUser;
  final QualificationDefinition? qualification;

  @override
  State<_QualificationEditorSheet> createState() =>
      _QualificationEditorSheetState();
}

class _QualificationEditorSheetState extends State<_QualificationEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _colorCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.qualification?.name ?? '');
    _descriptionCtrl =
        TextEditingController(text: widget.qualification?.description ?? '');
    _colorCtrl = TextEditingController(text: widget.qualification?.color ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descriptionCtrl.dispose();
    _colorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.qualification == null
                  ? 'Qualifikation anlegen'
                  : 'Qualifikation bearbeiten',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixIcon: Icon(Icons.verified_user_outlined),
              ),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Bitte Namen eingeben' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Beschreibung',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _colorCtrl,
              decoration: const InputDecoration(
                labelText: 'Farbe (#RRGGBB)',
                prefixIcon: Icon(Icons.palette_outlined),
              ),
              validator: (value) {
                final normalized = _normalizeQualificationColor(value);
                if ((value ?? '').trim().isEmpty || normalized != null) {
                  return null;
                }
                return 'Bitte Farbe als #RRGGBB oder #AARRGGBB eingeben';
              },
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Speichern'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final normalizedColor = _normalizeQualificationColor(_colorCtrl.text);
    Navigator.of(context).pop(
      QualificationDefinition(
        id: widget.qualification?.id,
        orgId: widget.currentUser.orgId,
        name: _nameCtrl.text.trim(),
        description: _descriptionCtrl.text.trim().isEmpty
            ? null
            : _descriptionCtrl.text.trim(),
        color: normalizedColor,
        createdByUid: widget.currentUser.uid,
      ),
    );
  }
}

String? _normalizeQualificationColor(String? raw) {
  final trimmed = raw?.trim() ?? '';
  if (trimmed.isEmpty) {
    return null;
  }

  final hex = trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
  final normalized = hex.toUpperCase();
  final isValid = RegExp(r'^(?:[0-9A-F]{6}|[0-9A-F]{8})$').hasMatch(normalized);
  if (!isValid) {
    return null;
  }

  return '#$normalized';
}

Color? _tryParseQualificationColor(String? raw) {
  final normalized = _normalizeQualificationColor(raw);
  if (normalized == null) {
    return null;
  }

  final hex = normalized.substring(1);
  final value = int.tryParse(
    hex.length == 6 ? 'FF$hex' : hex,
    radix: 16,
  );
  if (value == null) {
    return null;
  }

  return Color(value);
}

class _RuleSetEditorSheet extends StatefulWidget {
  const _RuleSetEditorSheet({
    required this.currentUser,
    required this.ruleSet,
  });

  final AppUserProfile currentUser;
  final ComplianceRuleSet ruleSet;

  @override
  State<_RuleSetEditorSheet> createState() => _RuleSetEditorSheetState();
}

class _RuleSetEditorSheetState extends State<_RuleSetEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _restCtrl;
  late final TextEditingController _break6Ctrl;
  late final TextEditingController _break9Ctrl;
  late final TextEditingController _maxDailyCtrl;
  late final TextEditingController _minijobCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.ruleSet.name);
    _restCtrl = TextEditingController(
      text: widget.ruleSet.minRestMinutes.toString(),
    );
    _break6Ctrl = TextEditingController(
      text: widget.ruleSet.breakRules
              .firstWhereOrNull(
                (rule) => rule.afterMinutes == 360,
              )
              ?.requiredBreakMinutes
              .toString() ??
          '30',
    );
    _break9Ctrl = TextEditingController(
      text: widget.ruleSet.breakRules
              .firstWhereOrNull(
                (rule) => rule.afterMinutes == 540,
              )
              ?.requiredBreakMinutes
              .toString() ??
          '45',
    );
    _maxDailyCtrl = TextEditingController(
      text: widget.ruleSet.maxPlannedMinutesPerDay.toString(),
    );
    _minijobCtrl = TextEditingController(
      text: (widget.ruleSet.minijobMonthlyLimitCents / 100).toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _restCtrl.dispose();
    _break6Ctrl.dispose();
    _break9Ctrl.dispose();
    _maxDailyCtrl.dispose();
    _minijobCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Regelwerk bearbeiten',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixIcon: Icon(Icons.rule_folder_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _restCtrl,
              decoration: const InputDecoration(
                labelText: 'Mindest-Ruhezeit (Minuten)',
                prefixIcon: Icon(Icons.hotel_outlined),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _break6Ctrl,
              decoration: const InputDecoration(
                labelText: 'Pause ab > 6h (Minuten)',
                prefixIcon: Icon(Icons.coffee_outlined),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _break9Ctrl,
              decoration: const InputDecoration(
                labelText: 'Pause ab > 9h (Minuten)',
                prefixIcon: Icon(Icons.free_breakfast_outlined),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _maxDailyCtrl,
              decoration: const InputDecoration(
                labelText: 'Max. geplante Minuten pro Tag',
                prefixIcon: Icon(Icons.timer_outlined),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _minijobCtrl,
              decoration: const InputDecoration(
                labelText: 'Minijob-Grenze (EUR)',
                prefixIcon: Icon(Icons.euro_outlined),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Speichern'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    Navigator.of(context).pop(
      widget.ruleSet.copyWith(
        name: _nameCtrl.text.trim(),
        minRestMinutes: int.tryParse(_restCtrl.text) ?? 660,
        breakRules: [
          BreakRule(
            afterMinutes: 360,
            requiredBreakMinutes: int.tryParse(_break6Ctrl.text) ?? 30,
          ),
          BreakRule(
            afterMinutes: 540,
            requiredBreakMinutes: int.tryParse(_break9Ctrl.text) ?? 45,
          ),
        ],
        maxPlannedMinutesPerDay: int.tryParse(_maxDailyCtrl.text) ?? 600,
        minijobMonthlyLimitCents:
            (double.tryParse(_minijobCtrl.text) ?? 603) * 100 ~/ 1,
      ),
    );
  }
}

class _TravelTimeRuleEditorSheet extends StatefulWidget {
  const _TravelTimeRuleEditorSheet({
    required this.currentUser,
    required this.sites,
    this.rule,
  });

  final AppUserProfile currentUser;
  final List<SiteDefinition> sites;
  final TravelTimeRule? rule;

  @override
  State<_TravelTimeRuleEditorSheet> createState() =>
      _TravelTimeRuleEditorSheetState();
}

class _TravelTimeRuleEditorSheetState
    extends State<_TravelTimeRuleEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  final _minutesCtrl = TextEditingController(text: '30');
  String? _fromSiteId;
  String? _toSiteId;
  bool _countsAsWorkTime = true;

  @override
  void initState() {
    super.initState();
    _minutesCtrl.text = (widget.rule?.travelMinutes ?? 30).toString();
    _countsAsWorkTime = widget.rule?.countsAsWorkTime ?? true;
    if (widget.rule != null) {
      _fromSiteId = widget.rule!.fromSiteId;
      _toSiteId = widget.rule!.toSiteId;
    } else if (widget.sites.length >= 2) {
      _fromSiteId = widget.sites.first.id;
      _toSiteId = widget.sites[1].id;
    }
  }

  @override
  void dispose() {
    _minutesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.rule == null
                  ? 'Fahrtzeitregel anlegen'
                  : 'Fahrtzeitregel bearbeiten',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _fromSiteId,
              decoration: const InputDecoration(
                labelText: 'Von Standort',
                prefixIcon: Icon(Icons.store_mall_directory_outlined),
              ),
              items: widget.sites
                  .map(
                    (site) => DropdownMenuItem(
                      value: site.id,
                      child: Text(site.name),
                    ),
                  )
                  .toList(),
              validator: (value) =>
                  value == null ? 'Bitte Startstandort waehlen' : null,
              onChanged: (value) => setState(() => _fromSiteId = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _toSiteId,
              decoration: const InputDecoration(
                labelText: 'Zu Standort',
                prefixIcon: Icon(Icons.storefront_outlined),
              ),
              items: widget.sites
                  .map(
                    (site) => DropdownMenuItem(
                      value: site.id,
                      child: Text(site.name),
                    ),
                  )
                  .toList(),
              validator: (value) =>
                  value == null ? 'Bitte Zielstandort waehlen' : null,
              onChanged: (value) => setState(() => _toSiteId = value),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _minutesCtrl,
              decoration: const InputDecoration(
                labelText: 'Fahrtzeit in Minuten',
                prefixIcon: Icon(Icons.timer_outlined),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                final minutes = int.tryParse(value ?? '');
                if (minutes == null || minutes <= 0) {
                  return 'Bitte eine gueltige Fahrtzeit eingeben';
                }
                return null;
              },
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _countsAsWorkTime,
              title: const Text('Als Arbeitszeit beruecksichtigen'),
              onChanged: (value) => setState(() => _countsAsWorkTime = value),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Speichern'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_fromSiteId == _toSiteId) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Start- und Zielstandort muessen unterschiedlich sein.',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    Navigator.of(context).pop(
      (widget.rule ??
              TravelTimeRule(
                orgId: widget.currentUser.orgId,
                fromSiteId: _fromSiteId!,
                toSiteId: _toSiteId!,
                travelMinutes: int.tryParse(_minutesCtrl.text) ?? 30,
                countsAsWorkTime: _countsAsWorkTime,
                createdByUid: widget.currentUser.uid,
              ))
          .copyWith(
        orgId: widget.currentUser.orgId,
        fromSiteId: _fromSiteId!,
        toSiteId: _toSiteId!,
        travelMinutes: int.tryParse(_minutesCtrl.text) ?? 30,
        countsAsWorkTime: _countsAsWorkTime,
        createdByUid: widget.currentUser.uid,
      ),
    );
  }
}

class _TeamEditorSheet extends StatefulWidget {
  const _TeamEditorSheet({
    required this.currentUser,
    required this.members,
    this.teamDefinition,
  });

  final AppUserProfile currentUser;
  final List<AppUserProfile> members;
  final TeamDefinition? teamDefinition;

  @override
  State<_TeamEditorSheet> createState() => _TeamEditorSheetState();
}

class _TeamEditorSheetState extends State<_TeamEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descriptionCtrl;
  late Set<String> _selectedMemberIds;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.teamDefinition?.name ?? '');
    _descriptionCtrl = TextEditingController(
      text: widget.teamDefinition?.description ?? '',
    );
    _selectedMemberIds = {
      ...?widget.teamDefinition?.memberIds,
    };
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.teamDefinition != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEdit ? 'Team bearbeiten' : 'Neues Team',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Teamname',
                prefixIcon: Icon(Icons.groups_2_outlined),
              ),
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return 'Bitte Teamname eingeben';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Beschreibung',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Mitglieder',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            if (widget.members.isEmpty)
              Text(
                'Keine aktiven Mitglieder vorhanden.',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final member in widget.members)
                    FilterChip(
                      label: Text(member.displayName),
                      selected: _selectedMemberIds.contains(member.uid),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedMemberIds.add(member.uid);
                          } else {
                            _selectedMemberIds.remove(member.uid);
                          }
                        });
                      },
                    ),
                ],
              ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: Text(isEdit ? 'Aktualisieren' : 'Team speichern'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    Navigator.of(context).pop(
      TeamDefinition(
        id: widget.teamDefinition?.id,
        orgId: widget.currentUser.orgId,
        name: _nameCtrl.text.trim(),
        memberIds: _selectedMemberIds.toList(growable: false),
        description: _descriptionCtrl.text.trim().isEmpty
            ? null
            : _descriptionCtrl.text.trim(),
        createdByUid: widget.currentUser.uid,
      ),
    );
  }
}
