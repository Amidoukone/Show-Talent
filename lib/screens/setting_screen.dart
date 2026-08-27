import 'package:adfoot/config/app_routes.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/services/users/user_repository.dart';
import 'package:adfoot/services/account_cleanup_service.dart';
import 'package:adfoot/services/app_logger.dart';
import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/theme/ad_tokens.dart';
import 'package:adfoot/utils/account_role_policy.dart';
import 'package:adfoot/utils/adfoot_support.dart';
import 'package:adfoot/widgets/ad_app_bar.dart';
import 'package:adfoot/widgets/ad_button.dart';
import 'package:adfoot/widgets/ad_dialogs.dart';
import 'package:adfoot/widgets/ad_feedback.dart';
import 'package:adfoot/widgets/ad_surface_card.dart';
import 'package:adfoot/widgets/ad_state_panel.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

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
      AdFeedback.error('Erreur', 'Impossible de sauvegarder les paramètres.');
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
      AdFeedback.info(
        'Confidentialité',
        value
            ? 'Votre profil est maintenant visible.'
            : 'Votre profil est désormais restreint.',
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
      AdFeedback.info(
        'Messages',
        value
            ? 'Les messages sont autorisés.'
            : 'Les messages sont désactivés.',
      );
    }
  }

  Future<void> _handleSignOut() async {
    final confirmed = await AdDialogs.confirm(
      context: context,
      title: 'Se déconnecter',
      message: 'Voulez-vous fermer votre session Adfoot sur cet appareil ?',
      confirmLabel: 'Se déconnecter',
      cancelLabel: 'Annuler',
    );
    if (!confirmed) {
      return;
    }

    await _authSessionService.signOut();
    Get.offAllNamed(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingRole) {
      return Scaffold(
        appBar: const AdAppBar(
          title: 'Outils',
          subtitle: 'Chargement du compte',
          showBottomDivider: true,
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: AdStatePanel.loading(
              title: 'Chargement des outils',
              message: 'Synchronisation des paramètres du compte.',
            ),
          ),
        ),
      );
    }

    if (_sessionUnavailable) {
      return Scaffold(
        appBar: const AdAppBar(
          title: 'Outils',
          subtitle: 'Session du compte',
          showBottomDivider: true,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AdStatePanel.error(
              title: 'Session invalide',
              message: 'Impossible de charger les paramètres du compte.',
              action: FilledButton.icon(
                onPressed: _retryLoadUserSettings,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AdAppBar(
        title: 'Outils',
        subtitle: 'Compte et sécurité',
        showBottomDivider: true,
        actions: [
          IconButton(
            tooltip: 'Actualiser',
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
                      title: 'Compte',
                      icon: Icons.manage_accounts_outlined,
                      children: [
                        _buildActionTile(
                          icon: Icons.logout_rounded,
                          title: 'Se déconnecter',
                          subtitle: 'Fermer la session sur cet appareil.',
                          enabled: !_isDeleting,
                          onTap: _handleSignOut,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildSectionCard(
                      title: 'Confidentialité',
                      icon: Icons.privacy_tip_outlined,
                      children: [
                        if (_role != 'fan')
                          _buildSwitchTile(
                            icon: Icons.visibility_outlined,
                            title: 'Visibilité du profil',
                            subtitle: _profileVisibilityLabel(),
                            value: _profilePublic,
                            loading: _isSavingPrivacySetting(_profilePublicKey),
                            enabled: !_isDeleting,
                            onChanged: _handleProfileVisibilityChange,
                          )
                        else
                          _buildInfoBlock(
                            icon: Icons.visibility_off_outlined,
                            title: 'Profil fan',
                            message:
                                'La visibilité du profil fan reste limitée aux usages nécessaires de la plateforme.',
                          ),
                        if (_role == 'joueur' ||
                            isOpportunityPublisherRole(_role)) ...[
                          _buildDivider(),
                          _buildSwitchTile(
                            icon: Icons.message_outlined,
                            title: 'Autoriser les messages',
                            subtitle: _messagePermissionLabel(),
                            value: _allowMessages,
                            loading: _isSavingPrivacySetting(_allowMessagesKey),
                            enabled: !_isDeleting,
                            onChanged: _handleMessagePermissionChange,
                          ),
                        ],
                        _buildDivider(),
                        _buildActionTile(
                          icon: Icons.info_outline_rounded,
                          title: 'Utilisation des données',
                          subtitle:
                              'Scouting, opportunités sportives et mise en relation encadrée.',
                          onTap: _showDataUsageNotice,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildSectionCard(
                      title: 'Sécurité et opportunités',
                      icon: Icons.shield_outlined,
                      children: [
                        _buildInfoBlock(
                          icon: Icons.verified_user_outlined,
                          title: 'Règle officielle Adfoot',
                          message:
                              'Avant tout essai, contrat, voyage ou paiement, faites vérifier l’opportunité par l’équipe Adfoot.',
                        ),
                        _buildDivider(),
                        _buildChecklistItem(
                          'Ne payez jamais un agent ou intermédiaire sans validation officielle.',
                        ),
                        _buildChecklistItem(
                          'Conservez les échanges importants dans les canaux Adfoot.',
                        ),
                        _buildChecklistItem(
                          'Signalez toute promesse floue, pression ou demande suspecte.',
                        ),
                        _buildDivider(),
                        _buildActionTile(
                          icon: Icons.support_agent_outlined,
                          title: 'Contacter l’équipe Adfoot',
                          subtitle: 'Ouvrir WhatsApp : $_supportPhoneDisplay',
                          onTap: _showSupportNotice,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildSectionCard(
                      title: 'Zone sensible',
                      icon: Icons.warning_amber_rounded,
                      children: [
                        _buildInfoBlock(
                          icon: Icons.delete_forever_outlined,
                          title: 'Suppression du compte',
                          message:
                              'Cette action supprime définitivement votre compte et les données associées.',
                          tone: _InfoTone.danger,
                        ),
                        const SizedBox(height: 12),
                        AdButton(
                          label: 'Supprimer mon compte',
                          leading: Icons.delete_forever_outlined,
                          kind: AdButtonKind.danger,
                          loading: _isDeleting,
                          onPressed: _isDeleting ? null : _confirmDeleteAccount,
                        ),
                      ],
                    ),
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
    AdFeedback.info(
      'Utilisation des données',
      'Les données servent à sécuriser le profil, les opportunités et les mises en relation Adfoot.',
      duration: const Duration(seconds: 5),
    );
  }

  // Le numéro vit dans AdfootSupport : l'écran d'ajout de vidéo renvoie vers
  // la même agence pour faire relever un plafond, et deux copies d'un numéro
  // de téléphone finissent toujours par diverger.
  static const String _supportPhoneDisplay = AdfootSupport.phoneDisplay;

  Future<void> _showSupportNotice() async {
    final opened = await AdfootSupport.openWhatsApp();
    if (opened) {
      return;
    }

    if (!mounted) {
      return;
    }
    AdFeedback.info(
      'Équipe Adfoot',
      'Faites vérifier toute opportunité via ${AdfootSupport.website} ou WhatsApp : $_supportPhoneDisplay.',
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
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Paramètres du compte',
                      style: TextStyle(
                        color: AdColors.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Confidentialité, sécurité et session de cet appareil.',
                      style: TextStyle(
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
            title: 'Vos informations sont dans Profil',
            message:
                'Nom, photo, bio et profil complet se consultent et se '
                'modifient depuis l’onglet Profil.',
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

    final confirmed = await AdDialogs.confirm(
      context: context,
      title: 'Supprimer mon compte',
      message:
          'Cette action supprimera définitivement votre compte et '
          'toutes vos données. Voulez-vous continuer ?',
      confirmLabel: 'Supprimer',
      cancelLabel: 'Annuler',
      danger: true,
    );
    if (!confirmed) return;
    if (!mounted) return;

    setState(() => _isDeleting = true);

    final blockingDialog = AdDialogs.showLoading(
      context: context,
      title: 'Suppression du compte',
      message: 'Suppression en cours, veuillez patienter.',
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
        'Compte supprimé',
        'Votre compte a été supprimé avec succès.',
      );
    } on AccountCleanupException catch (error) {
      closeBlockingDialog();

      if (error.requiresRecentLogin) {
        await _promptReauthenticationForDeletion(error.message);
        return;
      }

      AdFeedback.error('Suppression impossible', error.message);
    } catch (e, st) {
      closeBlockingDialog();
      AppLogger.debug('SettingsScreen account deletion error: $e\n$st');
      AdFeedback.error(
        'Suppression impossible',
        'Une erreur est survenue pendant la suppression. Merci de réessayer.',
      );
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Future<void> _promptReauthenticationForDeletion(String message) async {
    if (!mounted) return;

    final reconnectNow = await AdDialogs.confirm(
      context: context,
      title: 'Vérification de sécurité requise',
      message: '$message\n\nReconnectez-vous puis relancez la suppression.',
      confirmLabel: 'Me reconnecter',
      cancelLabel: 'Plus tard',
      danger: false,
    );

    if (!reconnectNow) return;

    try {
      await _authSessionService.signOut();
    } catch (_) {}

    if (!mounted) return;
    Get.offAllNamed(AppRoutes.login);
    AdFeedback.info(
      'Reconnexion',
      'Connectez-vous de nouveau puis relancez la suppression du compte.',
      duration: const Duration(seconds: 5),
    );
  }

  // =========================================================
  // 🧩 HELPERS
  // =========================================================

  String _profileVisibilityLabel() {
    switch (_role) {
      case 'joueur':
        return 'Visible par les clubs, recruteurs et agents.';
      case 'coach':
        return 'Visible par les clubs, joueurs et recruteurs.';
      case 'recruteur':
      case 'agent':
      case 'club':
        return 'Visible par les joueurs.';
      default:
        return 'Visibilité limitée.';
    }
  }

  String _messagePermissionLabel() {
    switch (_role) {
      case 'joueur':
        return 'Autoriser clubs et recruteurs à vous contacter.';
      case 'club':
        return 'Autoriser les joueurs à vous contacter.';
      case 'recruteur':
        return 'Autoriser les joueurs et clubs à vous contacter.';
      case 'agent':
        return 'Autoriser les talents et partenaires à vous contacter.';
      default:
        return 'Contrôler les demandes de contact depuis Adfoot.';
    }
  }
}
