import 'dart:async';

import 'package:adfoot/config/app_routes.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/l10n/generated/app_localizations.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/services/legal/terms_acceptance_service.dart';
import 'package:adfoot/services/users/user_repository.dart';
import 'package:adfoot/services/account_cleanup_service.dart';
import 'package:adfoot/services/app_logger.dart';
import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/theme/ad_tokens.dart';
import 'package:adfoot/utils/account_role_policy.dart';
import 'package:adfoot/utils/adfoot_support.dart';
import 'package:adfoot/widgets/ad_app_bar.dart';
import 'package:adfoot/widgets/app_version_label.dart';
import 'package:adfoot/widgets/ad_button.dart';
import 'package:adfoot/widgets/ad_dialogs.dart';
import 'package:adfoot/widgets/ad_feedback.dart';
import 'package:adfoot/widgets/ad_surface_card.dart';
import 'package:adfoot/widgets/ad_state_panel.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

enum _InfoTone { neutral, success, danger }

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthSessionService _authSessionService = AuthSessionService();
  final UserRepository _userRepository = UserRepository();
  final AccountCleanupService _cleanupService = AccountCleanupService();
  final TermsAcceptanceService _termsService = TermsAcceptanceService();
  static const String _profilePublicKey = 'profilePublic';
  static const String _allowMessagesKey = 'allowMessages';

  bool _isDeleting = false;
  bool _loadingRole = true;
  bool _sessionUnavailable = false;
  final Set<String> _savingPrivacySettings = <String>{};

  String _role = 'fan';

  bool _profilePublic = true;
  bool _allowMessages = true;

  @override
  void initState() {
    super.initState();
    _loadUserSettings();
    // Best effort: the cached config is already usable, this only picks up a
    // version published since the app started.
    unawaited(_termsService.fetchConfig());
  }

  Future<void> _loadUserSettings() async {
    final uid = _authSessionService.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _loadingRole = false;
        _sessionUnavailable = true;
      });
      return;
    }

    try {
      final settings = await _userRepository.fetchUserSettings(uid);
      if (!mounted) {
        return;
      }

      if (settings == null) {
        setState(() {
          _loadingRole = false;
          _sessionUnavailable = true;
        });
        return;
      }

      setState(() {
        _role = settings.role;
        _profilePublic = settings.profilePublic;
        _allowMessages = settings.allowMessages;
        _loadingRole = false;
      });
    } catch (e, st) {
      AppLogger.debug('SettingsScreen load user settings error: $e\n$st');
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingRole = false;
        _sessionUnavailable = true;
      });
      return;
    }
  }

  Future<void> _retryLoadUserSettings() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _loadingRole = true;
      _sessionUnavailable = false;
    });
    await _loadUserSettings();
  }

  Future<bool> _updatePrivacySetting({
    bool? profilePublic,
    bool? allowMessages,
  }) async {
    final uid = _authSessionService.currentUser?.uid;
    if (uid == null) return false;

    try {
      await _userRepository.updatePrivacySettings(
        uid,
        profilePublic: profilePublic,
        allowMessages: allowMessages,
      );
      if (Get.isRegistered<UserController>()) {
        await Get.find<UserController>().refreshUser();
      }
      return true;
    } catch (e, st) {
      AppLogger.debug('SettingsScreen update privacy setting error: $e\n$st');
      if (!mounted) return false;
      final l10n = AppLocalizations.of(context)!;
      AdFeedback.error(
        l10n.settingsGenericErrorTitle,
        l10n.settingsSaveFailureMessage,
      );
      return false;
    }
  }

  bool _isSavingPrivacySetting(String key) {
    return _savingPrivacySettings.contains(key);
  }

  Future<void> _handleProfileVisibilityChange(bool value) async {
    if (_isSavingPrivacySetting(_profilePublicKey)) {
      return;
    }

    final previous = _profilePublic;
    setState(() {
      _profilePublic = value;
      _savingPrivacySettings.add(_profilePublicKey);
    });

    final ok = await _updatePrivacySetting(profilePublic: value);
    if (!mounted) {
      return;
    }

    setState(() {
      if (!ok) {
        _profilePublic = previous;
      }
      _savingPrivacySettings.remove(_profilePublicKey);
    });

    if (ok) {
      final l10n = AppLocalizations.of(context)!;
      AdFeedback.info(
        l10n.settingsPrivacySectionTitle,
        value
            ? l10n.settingsProfileVisibleMessage
            : l10n.settingsProfileRestrictedMessage,
      );
    }
  }

  Future<void> _handleMessagePermissionChange(bool value) async {
    if (_isSavingPrivacySetting(_allowMessagesKey)) {
      return;
    }

    final previous = _allowMessages;
    setState(() {
      _allowMessages = value;
      _savingPrivacySettings.add(_allowMessagesKey);
    });

    final ok = await _updatePrivacySetting(allowMessages: value);
    if (!mounted) {
      return;
    }

    setState(() {
      if (!ok) {
        _allowMessages = previous;
      }
      _savingPrivacySettings.remove(_allowMessagesKey);
    });

    if (ok) {
      final l10n = AppLocalizations.of(context)!;
      AdFeedback.info(
        l10n.settingsMessagesToggleTitle,
        value
            ? l10n.settingsMessagesAllowedMessage
            : l10n.settingsMessagesDisabledMessage,
      );
    }
  }

  Future<void> _handleSignOut() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await AdDialogs.confirm(
      context: context,
      title: l10n.settingsSignOutAction,
      message: l10n.settingsSignOutConfirmMessage,
      confirmLabel: l10n.settingsSignOutAction,
      cancelLabel: l10n.commonCancel,
    );
    if (!confirmed) {
      return;
    }

    await _authSessionService.signOut();
    Get.offAllNamed(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_loadingRole) {
      return Scaffold(
        appBar: AdAppBar(
          title: l10n.settingsAppBarTitle,
          subtitle: l10n.settingsLoadingSubtitle,
          showBottomDivider: true,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AdStatePanel.loading(
              title: l10n.settingsLoadingTitle,
              message: l10n.settingsLoadingMessage,
            ),
          ),
        ),
      );
    }

    if (_sessionUnavailable) {
      return Scaffold(
        appBar: AdAppBar(
          title: l10n.settingsAppBarTitle,
          subtitle: l10n.settingsSessionSubtitle,
          showBottomDivider: true,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AdStatePanel.error(
              title: l10n.settingsSessionInvalidTitle,
              message: l10n.settingsSessionInvalidMessage,
              action: FilledButton.icon(
                onPressed: _retryLoadUserSettings,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(l10n.commonRetry),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AdAppBar(
        title: l10n.settingsAppBarTitle,
        subtitle: l10n.settingsMainSubtitle,
        showBottomDivider: true,
        actions: [
          IconButton(
            tooltip: l10n.settingsRefreshTooltip,
            onPressed: _isDeleting ? null : _retryLoadUserSettings,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildToolsHeader(),
                    const SizedBox(height: 16),
                    _buildSectionCard(
                      title: l10n.settingsAccountSectionTitle,
                      icon: Icons.manage_accounts_outlined,
                      children: [
                        _buildActionTile(
                          icon: Icons.logout_rounded,
                          title: l10n.settingsSignOutAction,
                          subtitle: l10n.settingsSignOutSubtitle,
                          enabled: !_isDeleting,
                          onTap: _handleSignOut,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildSectionCard(
                      title: l10n.settingsPrivacySectionTitle,
                      icon: Icons.privacy_tip_outlined,
                      children: [
                        if (_role != 'fan')
                          _buildSwitchTile(
                            icon: Icons.visibility_outlined,
                            title: l10n.settingsProfileVisibilityTitle,
                            subtitle: _profileVisibilityLabel(l10n),
                            value: _profilePublic,
                            loading: _isSavingPrivacySetting(_profilePublicKey),
                            enabled: !_isDeleting,
                            onChanged: _handleProfileVisibilityChange,
                          )
                        else
                          _buildInfoBlock(
                            icon: Icons.visibility_off_outlined,
                            title: l10n.settingsFanProfileTitle,
                            message: l10n.settingsFanProfileMessage,
                          ),
                        if (_role == 'joueur' ||
                            isOpportunityPublisherRole(_role)) ...[
                          _buildDivider(),
                          _buildSwitchTile(
                            icon: Icons.message_outlined,
                            title: l10n.settingsAllowMessagesTitle,
                            subtitle: _messagePermissionLabel(l10n),
                            value: _allowMessages,
                            loading: _isSavingPrivacySetting(_allowMessagesKey),
                            enabled: !_isDeleting,
                            onChanged: _handleMessagePermissionChange,
                          ),
                        ],
                        _buildDivider(),
                        _buildActionTile(
                          icon: Icons.info_outline_rounded,
                          title: l10n.settingsDataUsageTitle,
                          subtitle: l10n.settingsDataUsageSubtitle,
                          onTap: _showDataUsageNotice,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildSectionCard(
                      title: l10n.settingsSecuritySectionTitle,
                      icon: Icons.shield_outlined,
                      children: [
                        _buildInfoBlock(
                          icon: Icons.verified_user_outlined,
                          title: l10n.settingsOfficialRuleTitle,
                          message: l10n.settingsOfficialRuleMessage,
                        ),
                        _buildDivider(),
                        _buildChecklistItem(l10n.settingsChecklistPayment),
                        _buildChecklistItem(l10n.settingsChecklistKeepRecords),
                        _buildChecklistItem(l10n.settingsChecklistReport),
                        _buildDivider(),
                        _buildActionTile(
                          icon: Icons.support_agent_outlined,
                          title: l10n.settingsContactTeamTile,
                          subtitle: l10n.settingsContactTeamSubtitle(
                            _supportPhoneDisplay,
                          ),
                          onTap: _showSupportNotice,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildSectionCard(
                      title: l10n.settingsDocumentsSectionTitle,
                      icon: Icons.gavel_rounded,
                      children: [
                        _buildActionTile(
                          icon: Icons.description_outlined,
                          title: l10n.settingsTermsTile,
                          subtitle: _acceptedTermsSubtitle(l10n),
                          onTap: () => _openLegalDocument(
                            _termsService.cached.termsUrl,
                          ),
                        ),
                        _buildDivider(),
                        _buildActionTile(
                          icon: Icons.privacy_tip_outlined,
                          title: l10n.settingsPrivacyTile,
                          subtitle: l10n.settingsPrivacyTileSubtitle,
                          onTap: () => _openLegalDocument(
                            _termsService.cached.privacyUrl,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildSectionCard(
                      title: l10n.settingsSensitiveSectionTitle,
                      icon: Icons.warning_amber_rounded,
                      children: [
                        _buildInfoBlock(
                          icon: Icons.delete_forever_outlined,
                          title: l10n.settingsDeleteAccountInfoTitle,
                          message: l10n.settingsDeleteAccountInfoMessage,
                          tone: _InfoTone.danger,
                        ),
                        const SizedBox(height: 12),
                        AdButton(
                          label: l10n.settingsDeleteAccountAction,
                          leading: Icons.delete_forever_outlined,
                          kind: AdButtonKind.danger,
                          loading: _isDeleting,
                          onPressed: _isDeleting ? null : _confirmDeleteAccount,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Le dernier mot de l'ecran : quelle version tourne ici.
                    // Selectionnable, pour qu'un testeur puisse la coller dans
                    // son rapport plutot que la recopier.
                    const AppVersionLabel(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // OUTILS UI HELPERS
  // =========================================================

  void _showDataUsageNotice() {
    final l10n = AppLocalizations.of(context)!;
    AdFeedback.info(
      l10n.settingsDataUsageTitle,
      l10n.settingsDataUsageMessage,
      duration: const Duration(seconds: 5),
    );
  }

  // Le numéro vit dans AdfootSupport : l'écran d'ajout de vidéo renvoie vers
  // la même agence pour faire relever un plafond, et deux copies d'un numéro
  // de téléphone finissent toujours par diverger.
  static const String _supportPhoneDisplay = AdfootSupport.phoneDisplay;

  /// What this account accepted, so the record is visible to its subject.
  ///
  /// A consent the user cannot go back and read is a consent they have to take
  /// on trust, which is the opposite of the point.
  String _acceptedTermsSubtitle(AppLocalizations l10n) {
    final version = Get.isRegistered<UserController>()
        ? (Get.find<UserController>().user?.acceptedTermsVersion?.trim() ?? '')
        : '';
    if (version.isEmpty) {
      return l10n.settingsReadDocument;
    }
    return l10n.settingsAcceptedVersionLabel(version);
  }

  Future<void> _openLegalDocument(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (opened) return;
    } catch (error, stackTrace) {
      AppLogger.warning(
        'could not open a legal document',
        source: 'legal/open_document',
        error: error,
        stackTrace: stackTrace,
        metadata: <String, dynamic>{'url': url},
      );
    }

    if (!mounted) return;
    // Meme message que TermsAcceptanceScreen pour le meme cas (document
    // legal qui ne s'ouvre pas) : reutilise ses cles plutot que d'en dupliquer
    // le texte.
    final l10n = AppLocalizations.of(context)!;
    AdFeedback.error(
      l10n.termsOpenFailureTitle,
      l10n.termsOpenFailureMessage(url),
    );
  }

  Future<void> _showSupportNotice() async {
    final opened = await AdfootSupport.openWhatsApp();
    if (opened) {
      return;
    }

    if (!mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    AdFeedback.info(
      l10n.settingsSupportNoticeTitle,
      l10n.settingsSupportNoticeMessage(
        AdfootSupport.website,
        _supportPhoneDisplay,
      ),
      duration: const Duration(seconds: 5),
    );
  }

  /// The header of Outils, deliberately anonymous.
  ///
  /// It used to carry the account's name, e-mail, role badge and a "Voir
  /// profil" button — a second, half-complete copy of the profile living
  /// inside a settings screen, and the reason the same information could be
  /// edited from two places. Identity, and everything editable about it, now
  /// belongs to the Profil destination. Outils keeps the session and the
  /// account controls, and only says where the rest went.
  Widget _buildToolsHeader() {
    final l10n = AppLocalizations.of(context)!;
    return AdSurfaceCard(
      padding: const EdgeInsets.all(AdSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AdColors.brand.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AdRadius.lg),
                  border: Border.all(
                    color: AdColors.brand.withValues(alpha: 0.22),
                  ),
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  color: AdColors.brand,
                  size: 25,
                ),
              ),
              const SizedBox(width: AdSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.settingsHeaderTitle,
                      style: const TextStyle(
                        color: AdColors.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.settingsHeaderSubtitle,
                      style: const TextStyle(
                        color: AdColors.onSurfaceMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AdSpacing.md),
          _buildInfoBlock(
            icon: Icons.person_outline,
            title: l10n.settingsProfileInProfileTabTitle,
            message: l10n.settingsProfileInProfileTabMessage,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
    String? subtitle,
  }) {
    return AdSurfaceCard(
      padding: const EdgeInsets.all(AdSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AdColors.surfaceCardAlt,
                  borderRadius: BorderRadius.circular(AdRadius.md),
                  border: Border.all(color: AdColors.divider),
                ),
                child: Icon(icon, color: AdColors.brand, size: 20),
              ),
              const SizedBox(width: AdSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AdColors.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AdColors.onSurfaceMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AdSpacing.md),
          ...children,
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    final foreground = enabled
        ? AdColors.onSurface
        : AdColors.onSurfaceDisabled;
    final muted = enabled
        ? AdColors.onSurfaceMuted
        : AdColors.onSurfaceDisabled;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AdRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AdSpacing.sm),
          child: Row(
            children: [
              _buildTileIcon(
                icon,
                enabled ? AdColors.brand : AdColors.onSurfaceDisabled,
              ),
              const SizedBox(width: AdSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: muted,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: muted, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
    bool loading = false,
  }) {
    final canChange = enabled && !loading;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AdSpacing.sm),
      child: Row(
        children: [
          _buildTileIcon(
            icon,
            canChange ? AdColors.brand : AdColors.onSurfaceDisabled,
          ),
          const SizedBox(width: AdSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AdColors.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AdColors.onSurfaceMuted,
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AdSpacing.sm),
          if (loading) ...[
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AdSpacing.xs),
          ],
          Switch(
            value: value,
            activeThumbColor: AdColors.brand,
            onChanged: canChange ? onChanged : null,
          ),
        ],
      ),
    );
  }

  Widget _buildTileIcon(IconData icon, Color color) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AdRadius.md),
      ),
      child: Icon(icon, color: color, size: 19),
    );
  }

  Widget _buildInfoBlock({
    required IconData icon,
    required String title,
    required String message,
    _InfoTone tone = _InfoTone.neutral,
  }) {
    Color accent;
    switch (tone) {
      case _InfoTone.success:
        accent = AdColors.success;
        break;
      case _InfoTone.danger:
        accent = AdColors.error;
        break;
      case _InfoTone.neutral:
        accent = AdColors.info;
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AdSpacing.md),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AdRadius.md),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 21),
          const SizedBox(width: AdSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AdColors.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    color: AdColors.onSurfaceMuted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistItem(String message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AdSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            color: AdColors.success,
            size: 19,
          ),
          const SizedBox(width: AdSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AdColors.onSurfaceMuted,
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(
      height: AdSpacing.lg,
      thickness: 1,
      color: AdColors.divider,
    );
  }

  // =========================================================
  // SUPPRESSION COMPTE
  // =========================================================

  Future<void> _confirmDeleteAccount() async {
    final uid = _authSessionService.currentUser?.uid;
    if (uid == null) return;

    final l10n = AppLocalizations.of(context)!;
    final confirmed = await AdDialogs.confirm(
      context: context,
      title: l10n.settingsDeleteAccountAction,
      message: l10n.settingsDeleteAccountConfirmMessage,
      confirmLabel: l10n.settingsDeleteAction,
      cancelLabel: l10n.commonCancel,
      danger: true,
    );
    if (!confirmed) return;
    if (!mounted) return;

    setState(() => _isDeleting = true);

    final blockingDialog = AdDialogs.showLoading(
      context: context,
      title: l10n.settingsDeleteAccountInfoTitle,
      message: l10n.settingsDeletingMessage,
    );
    var dialogOpen = true;
    void closeBlockingDialog() {
      if (!dialogOpen) return;
      dialogOpen = false;
      blockingDialog.close();
    }

    try {
      await _cleanupService.deleteAccountAndData(
        uid: uid,
        deleteAuthUser: true,
      );

      closeBlockingDialog();
      if (!mounted) return;

      Get.offAllNamed(AppRoutes.login);
      AdFeedback.success(
        l10n.settingsAccountDeletedTitle,
        l10n.settingsAccountDeletedMessage,
      );
    } on AccountCleanupException catch (error) {
      closeBlockingDialog();

      if (error.requiresRecentLogin) {
        await _promptReauthenticationForDeletion(error.message);
        return;
      }

      AdFeedback.error(l10n.settingsDeleteFailureTitle, error.message);
    } catch (e, st) {
      closeBlockingDialog();
      AppLogger.debug('SettingsScreen account deletion error: $e\n$st');
      AdFeedback.error(
        l10n.settingsDeleteFailureTitle,
        l10n.settingsDeleteGenericFailureMessage,
      );
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Future<void> _promptReauthenticationForDeletion(String message) async {
    if (!mounted) return;

    final l10n = AppLocalizations.of(context)!;
    final reconnectNow = await AdDialogs.confirm(
      context: context,
      title: l10n.settingsReauthRequiredTitle,
      message: l10n.settingsReauthRequiredMessage(message),
      confirmLabel: l10n.settingsReauthConfirm,
      cancelLabel: l10n.settingsReauthLater,
      danger: false,
    );

    if (!reconnectNow) return;

    try {
      await _authSessionService.signOut();
    } catch (_) {}

    if (!mounted) return;
    Get.offAllNamed(AppRoutes.login);
    AdFeedback.info(
      l10n.settingsReauthNoticeTitle,
      l10n.settingsReauthNoticeMessage,
      duration: const Duration(seconds: 5),
    );
  }

  // =========================================================
  // 🧩 HELPERS
  // =========================================================

  String _profileVisibilityLabel(AppLocalizations l10n) {
    switch (_role) {
      case 'joueur':
        return l10n.settingsVisibilityPlayer;
      case 'coach':
        return l10n.settingsVisibilityCoach;
      case 'recruteur':
      case 'agent':
      case 'club':
        return l10n.settingsVisibilityRecruiterAgentClub;
      default:
        return l10n.settingsVisibilityDefault;
    }
  }

  String _messagePermissionLabel(AppLocalizations l10n) {
    switch (_role) {
      case 'joueur':
        return l10n.settingsMessagesPlayer;
      case 'club':
        return l10n.settingsMessagesClub;
      case 'recruteur':
        return l10n.settingsMessagesRecruiter;
      case 'agent':
        return l10n.settingsMessagesAgent;
      default:
        return l10n.settingsMessagesDefault;
    }
  }
}
