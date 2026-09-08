import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../controller/profile_controller.dart';
import '../models/user.dart';
import '../widgets/ad_app_bar.dart';
import '../widgets/ad_button.dart';
import '../widgets/ad_dialogs.dart';
import '../widgets/ad_feedback.dart';
import '../widgets/ad_profile_cards.dart';
import '../widgets/profile_action_notice.dart';
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
  bool _isDirty = false;
  String? _saveFailureTitle;
  String? _saveFailureMessage;

  AppUser get _user => widget.user;
  ProfileController get _profileController => widget.profileController;

  bool get _isAgent => _user.isAgent;

  bool get _hasAdvancedProfileSection =>
      _user.isPlayer || _user.isClub || _user.isRecruiter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _handleBackNavigation({Object? result}) async {
    if (!_isDirty) {
      if (mounted) Navigator.of(context).pop(result);
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final shouldDiscard = await AdDialogs.confirm(
      context: context,
      title: l10n.editProfileDiscardConfirmTitle,
      message: l10n.editProfileDiscardConfirmMessage,
      confirmLabel: l10n.editProfileDiscardAction,
      cancelLabel: l10n.eventFormContinueEditingAction,
      danger: true,
    );
    if (shouldDiscard && mounted) {
      Navigator.of(context).pop(result);
    }
  }

  Map<String, dynamic> _mergePatchMaps(
    Map<String, dynamic> base,
    Map<String, dynamic> next,
  ) {
    final merged = Map<String, dynamic>.from(base);
    next.forEach((key, value) {
      final current = merged[key];
      if (current is Map && value is Map) {
        merged[key] = _mergePatchMaps(
          Map<String, dynamic>.from(current),
          Map<String, dynamic>.from(value),
        );
        return;
      }
      merged[key] = value;
    });
    return merged;
  }

  void _showSaveFailure({
    required AppLocalizations l10n,
    int? tabIndex,
    required String message,
    String? title,
  }) {
    if (!mounted) {
      return;
    }
    final resolvedTitle = title ?? l10n.editProfileSaveFailureFallbackTitle;
    if (tabIndex != null && tabIndex >= 0 && tabIndex < _tabController.length) {
      _tabController.animateTo(tabIndex);
    }
    setState(() {
      _saveFailureTitle = resolvedTitle;
      _saveFailureMessage = message;
    });
    AdFeedback.error(
      resolvedTitle,
      message,
      duration: const Duration(seconds: 6),
    );
  }

  Future<void> _save() async {
    if (_saving || !_hasAdvancedProfileSection) {
      return;
    }

    final l10n = AppLocalizations.of(context)!;

    setState(() {
      _saving = true;
      _saveFailureTitle = null;
      _saveFailureMessage = null;
    });
    try {
      bool saved = false;

      if (_user.isPlayer) {
        final profileState = _playerProfileKey.currentState;
        final scoutState = _playerScoutKey.currentState;

        if (profileState == null || !profileState.validate()) {
          _showSaveFailure(
            l10n: l10n,
            tabIndex: 0,
            message: l10n.editAdvancedProfilePlayerSaveFailedMessage,
          );
          return;
        }

        if (scoutState == null || !scoutState.validate()) {
          _showSaveFailure(
            l10n: l10n,
            tabIndex: 1,
            message: l10n.editAdvancedProfileScoutSaveFailedMessage,
          );
          return;
        }

        try {
          final patch = _mergePatchMaps(
            profileState.buildPatch(),
            scoutState.buildPatch(),
          );
          await _profileController.updateProfilePatch(_user.uid, patch);
        } on ProfileAccessRevokedException {
          _showSaveFailure(
            l10n: l10n,
            tabIndex: _tabController.index,
            title:
                _profileController.lastProfileWriteErrorTitle ??
                l10n.editProfileSaveDeniedTitle,
            message:
                _profileController.lastProfileWriteErrorMessage ??
                l10n.editProfileSaveDeniedMessage,
          );
          return;
        } catch (_) {
          _showSaveFailure(
            l10n: l10n,
            tabIndex: _tabController.index,
            message:
                _profileController.lastProfileWriteErrorMessage ??
                l10n.editAdvancedProfilePlayerGenericSaveFailedMessage,
          );
          return;
        }

        saved = true;
      } else if (_user.isClub) {
        saved = await _clubKey.currentState?.save(showFeedback: false) ?? false;
      } else if (_user.isRecruiter) {
        saved =
            await _agentKey.currentState?.save(showFeedback: false) ?? false;
      }

      if (!saved) {
        final message =
            _profileController.lastProfileWriteErrorMessage ??
            l10n.editAdvancedProfileGenericSaveFailedMessage;
        if (mounted) {
          setState(() {
            _saveFailureTitle = l10n.editProfileSaveFailureFallbackTitle;
            _saveFailureMessage = message;
          });
        }
        AdFeedback.error(
          l10n.editProfileSaveFailureFallbackTitle,
          message,
          duration: const Duration(seconds: 6),
        );
        return;
      }

      if (!mounted) {
        return;
      }

      _isDirty = false;
      AdFeedback.success(
        l10n.editProfileSaveSuccessTitle,
        l10n.editAdvancedProfileSaveSuccessMessage,
      );
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _buildPlayerBody(BuildContext context, AppLocalizations l10n) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            children: [
              AdFormHeaderCard(
                title: l10n.editAdvancedProfilePlayerTitle,
                subtitle: l10n.editAdvancedProfilePlayerSubtitle,
                icon: Icons.shield_outlined,
              ),
              if (_saveFailureMessage != null) ...[
                const SizedBox(height: 12),
                ProfileActionNotice(
                  title:
                      _saveFailureTitle ??
                      l10n.editProfileSaveFailureFallbackTitle,
                  message: _saveFailureMessage!,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TabBar(
            controller: _tabController,
            tabs: [
              Tab(text: l10n.profileFallbackTitle),
              Tab(text: l10n.editAdvancedProfileStatsTabLabel),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _tabController.index,
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                child: AdSectionCard(
                  title: l10n.editProfileHeaderTitlePlayer,
                  subtitle: l10n.editAdvancedProfilePlayerSectionSubtitle,
                  icon: Icons.person_outline,
                  child: PlayerAdvancedForm(
                    key: _playerProfileKey,
                    user: _user,
                    profileController: _profileController,
                    autoCloseOnSave: false,
                    showSubmitButton: false,
                    showSectionTitle: false,
                    onDirty: () => _isDirty = true,
                  ),
                ),
              ),
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                child: AdSectionCard(
                  title: l10n.profileAdvancedTitlePlayer,
                  subtitle: l10n.editAdvancedProfileScoutSectionSubtitle,
                  icon: Icons.bar_chart_rounded,
                  child: PlayerStatsAvailabilityForm(
                    key: _playerScoutKey,
                    user: _user,
                    profileController: _profileController,
                    autoCloseOnSave: false,
                    showSubmitButton: false,
                    showSectionTitle: false,
                    onDirty: () => _isDirty = true,
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
    BuildContext context,
    AppLocalizations l10n, {
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
          AdFormHeaderCard(title: title, subtitle: subtitle, icon: icon),
          if (_saveFailureMessage != null) ...[
            const SizedBox(height: 12),
            ProfileActionNotice(
              title:
                  _saveFailureTitle ??
                  l10n.editProfileSaveFailureFallbackTitle,
              message: _saveFailureMessage!,
            ),
          ],
          const SizedBox(height: 16),
          AdSectionCard(
            title: sectionTitle,
            subtitle: sectionSubtitle,
            icon: icon,
            child: child,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    Widget body;

    if (_user.isPlayer) {
      body = _buildPlayerBody(context, l10n);
    } else if (_user.isClub) {
      body = _buildSingleSectionBody(
        context,
        l10n,
        title: l10n.editProfileHeaderTitleClub,
        subtitle: l10n.editAdvancedProfileClubSubtitle,
        sectionTitle: l10n.editAdvancedProfileClubSectionTitle,
        sectionSubtitle: l10n.editAdvancedProfileClubSectionSubtitle,
        icon: Icons.groups_outlined,
        child: ClubAdvancedForm(
          key: _clubKey,
          user: _user,
          profileController: _profileController,
          autoCloseOnSave: false,
          showSubmitButton: false,
          showSectionTitle: false,
          onDirty: () => _isDirty = true,
        ),
      );
    } else if (_user.isRecruiter) {
      body = _buildSingleSectionBody(
        context,
        l10n,
        title: _isAgent
            ? l10n.editProfileHeaderTitleAgent
            : l10n.editProfileHeaderTitleRecruiter,
        subtitle: _isAgent
            ? l10n.editAdvancedProfileAgentSubtitle
            : l10n.editAdvancedProfileRecruiterSubtitle,
        sectionTitle: _isAgent
            ? l10n.editAdvancedProfileAgentSectionTitle
            : l10n.editAdvancedProfileRecruiterSectionTitle,
        sectionSubtitle: _isAgent
            ? l10n.editAdvancedProfileAgentSectionSubtitle
            : l10n.editAdvancedProfileRecruiterSectionSubtitle,
        icon: Icons.badge_outlined,
        child: AgentAdvancedForm(
          key: _agentKey,
          user: _user,
          profileController: _profileController,
          autoCloseOnSave: false,
          showSubmitButton: false,
          showSectionTitle: false,
          onDirty: () => _isDirty = true,
        ),
      );
    } else {
      body = Center(child: Text(l10n.profileNoAdvancedProfileMessage));
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBackNavigation(result: result);
      },
      child: Scaffold(
        appBar: AdAppBar(
          title: l10n.profileAdvancedTitleDefault,
          subtitle: l10n.editAdvancedProfileSubtitle,
          showBottomDivider: true,
        ),
        body: SafeArea(child: body),
        bottomNavigationBar: _hasAdvancedProfileSection
            ? SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: AdButton(
                    onPressed: _saving ? null : _save,
                    loading: _saving,
                    leading: Icons.save_outlined,
                    label: _saving
                        ? l10n.editProfileSavingAction
                        : l10n.editProfileSaveAction,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}
