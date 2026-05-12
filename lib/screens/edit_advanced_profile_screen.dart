import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controller/profile_controller.dart';
import '../models/user.dart';
import '../widgets/advanced/agent_advanced_form.dart';
import '../widgets/advanced/club_advanced_form.dart';
import '../widgets/advanced/player_advanced_form.dart';
import '../widgets/advanced/player_stats_availability_form.dart';

class EditAdvancedProfileScreen extends StatefulWidget {
  final AppUser user;
  final ProfileController profileController;

  const EditAdvancedProfileScreen({
    super.key,
    required this.user,
    required this.profileController,
  });

  @override
  State<EditAdvancedProfileScreen> createState() =>
      _EditAdvancedProfileScreenState();
}

class _EditAdvancedProfileScreenState extends State<EditAdvancedProfileScreen>
    with SingleTickerProviderStateMixin {
  final _playerProfileKey = GlobalKey<PlayerAdvancedFormState>();
  final _playerScoutKey = GlobalKey<PlayerStatsAvailabilityFormState>();
  final _clubKey = GlobalKey<ClubAdvancedFormState>();
  final _agentKey = GlobalKey<AgentAdvancedFormState>();

  late final TabController _tabController;
  bool _saving = false;

  AppUser get _user => widget.user;
  ProfileController get _profileController => widget.profileController;

  bool get _isAgent => _user.isAgent;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }

    setState(() => _saving = true);
    try {
      bool saved = false;

      if (_user.isPlayer) {
        final profileSaved =
            await _playerProfileKey.currentState?.save(showFeedback: false) ??
                false;
        if (!profileSaved) {
          _tabController.animateTo(0);
          return;
        }

        final scoutSaved =
            await _playerScoutKey.currentState?.save(showFeedback: false) ??
                false;
        if (!scoutSaved) {
          _tabController.animateTo(1);
          return;
        }

        saved = true;
      } else if (_user.isClub) {
        saved = await _clubKey.currentState?.save(showFeedback: false) ?? false;
      } else if (_user.isRecruiter) {
        saved =
            await _agentKey.currentState?.save(showFeedback: false) ?? false;
      }

      if (!saved || !mounted) {
        return;
      }

      Get.snackbar('Succès', 'Informations avancées mises à jour');
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _buildHeader({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: scheme.primary.withValues(alpha: 0.12),
            foregroundColor: scheme.primary,
            child: Icon(icon),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          child,
        ],
      ),
    );
  }

  Widget _buildPlayerBody(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: _buildHeader(
            context: context,
            title: 'Dossier joueur',
            subtitle:
                'Les informations sont réparties en deux volets pour vous aider à compléter votre profil sportif avec méthode.',
            icon: Icons.shield_outlined,
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Profil'),
              Tab(text: 'Stats'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                child: _buildSectionCard(
                  context: context,
                  title: 'Profil joueur',
                  subtitle:
                      'Renseignez le gabarit, le pied préféré, les postes et les qualités fortes du joueur.',
                  child: PlayerAdvancedForm(
                    key: _playerProfileKey,
                    user: _user,
                    profileController: _profileController,
                    autoCloseOnSave: false,
                    showSubmitButton: false,
                    showSectionTitle: false,
                  ),
                ),
              ),
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                child: _buildSectionCard(
                  context: context,
                  title: 'Dossier scout',
                  subtitle:
                      'Renseignez vos statistiques et votre disponibilité pour compléter votre dossier joueur.',
                  child: PlayerStatsAvailabilityForm(
                    key: _playerScoutKey,
                    user: _user,
                    profileController: _profileController,
                    autoCloseOnSave: false,
                    showSubmitButton: false,
                    showSectionTitle: false,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSingleSectionBody(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String sectionTitle,
    required String sectionSubtitle,
    required IconData icon,
    required Widget child,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      child: Column(
        children: [
          _buildHeader(
            context: context,
            title: title,
            subtitle: subtitle,
            icon: icon,
          ),
          _buildSectionCard(
            context: context,
            title: sectionTitle,
            subtitle: sectionSubtitle,
            child: child,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;

    if (_user.isPlayer) {
      body = _buildPlayerBody(context);
    } else if (_user.isClub) {
      body = _buildSingleSectionBody(
        context,
        title: 'Profil club',
        subtitle:
            'Renseignez la structure du club, les catégories suivies et les priorités de recrutement pour présenter un cadre sportif clair.',
        sectionTitle: 'Organisation sportive',
        sectionSubtitle:
            'Complétez les éléments qui aident les joueurs, agents et recruteurs à comprendre votre projet de club.',
        icon: Icons.groups_outlined,
        child: ClubAdvancedForm(
          key: _clubKey,
          user: _user,
          profileController: _profileController,
          autoCloseOnSave: false,
          showSubmitButton: false,
          showSectionTitle: false,
        ),
      );
    } else if (_user.isRecruiter) {
      body = _buildSingleSectionBody(
        context,
        title: _isAgent ? 'Profil agent' : 'Profil recruteur',
        subtitle: _isAgent
            ? 'Renseignez votre licence, votre pays d’exercice et vos zones d’intervention pour présenter un cadre de représentation crédible.'
            : 'Renseignez vos références, votre zone de travail et vos informations de licence pour cadrer votre activité de recrutement.',
        sectionTitle:
            _isAgent ? 'Cadre de représentation' : 'Cadre de recrutement',
        sectionSubtitle: _isAgent
            ? 'Complétez les éléments qui permettent aux joueurs et clubs d’identifier votre périmètre d’accompagnement.'
            : 'Complétez les éléments qui permettent aux joueurs et clubs d’identifier votre périmètre de recrutement.',
        icon: Icons.badge_outlined,
        child: AgentAdvancedForm(
          key: _agentKey,
          user: _user,
          profileController: _profileController,
          autoCloseOnSave: false,
          showSubmitButton: false,
          showSectionTitle: false,
        ),
      );
    } else {
      body = const Center(child: Text('Aucun profil avancé pour ce rôle'));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Informations avancées'),
        centerTitle: true,
      ),
      body: SafeArea(child: body),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Sauvegarde...' : 'Enregistrer'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
          ),
        ),
      ),
    );
  }
}
