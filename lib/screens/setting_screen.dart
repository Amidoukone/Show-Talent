import 'package:adfoot/config/app_routes.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/services/users/user_repository.dart';
import 'package:adfoot/screens/profile_screen.dart';
import 'package:adfoot/services/account_cleanup_service.dart';
import 'package:adfoot/utils/account_role_policy.dart';
import 'package:adfoot/widgets/ad_dialogs.dart';
import 'package:adfoot/widgets/ad_feedback.dart';
import 'package:adfoot/widgets/ad_state_panel.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthSessionService _authSessionService = AuthSessionService();
  final UserRepository _userRepository = UserRepository();
  final AccountCleanupService _cleanupService = AccountCleanupService();

  bool _isDeleting = false;
  bool _loadingRole = true;
  bool _sessionUnavailable = false;

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
      if (settings != null) {
        _role = settings.role;
        _profilePublic = settings.profilePublic;
        _allowMessages = settings.allowMessages;
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _loadingRole = false);
    }
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
      return true;
    } catch (e) {
      AdFeedback.error(
        'Erreur',
        'Impossible de sauvegarder les paramètres.',
      );
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingRole) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_sessionUnavailable) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Paramètres'),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: AdStatePanel.error(
              title: 'Session invalide',
              message: 'Impossible de charger les paramètres du compte.',
            ),
          ),
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Paramètres"),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // =====================================================
          // 👤 COMPTE
          // =====================================================
          _sectionTitle("Compte"),

          ListTile(
            leading: Icon(Icons.person, color: cs.primary),
            title: const Text('Voir le profil'),
            enabled: !_isDeleting,
            onTap: () {
              final uid = _authSessionService.currentUser?.uid;
              if (uid == null) return;

              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProfileScreen(uid: uid),
                ),
              );
            },
          ),

          ListTile(
            leading: Icon(Icons.logout, color: cs.primary),
            title: const Text('Se déconnecter'),
            enabled: !_isDeleting,
            onTap: () async {
              await _authSessionService.signOut();
              Get.offAllNamed(AppRoutes.login);
            },
          ),

          const Divider(height: 32),

          // =====================================================
          // 🔐 CONFIDENTIALITÉ
          // =====================================================
          _sectionTitle("Confidentialité"),

          if (_role != 'fan')
            SwitchListTile(
              secondary: const Icon(Icons.visibility),
              title: const Text('Visibilité du profil'),
              subtitle: Text(_profileVisibilityLabel()),
              value: _profilePublic,
              onChanged: _isDeleting
                  ? null
                  : (value) async {
                      final previous = _profilePublic;
                      setState(() => _profilePublic = value);

                      final ok = await _updatePrivacySetting(
                        profilePublic: value,
                      );
                      if (!ok && mounted) {
                        setState(() => _profilePublic = previous);
                        return;
                      }

                      AdFeedback.info(
                        'Confidentialité',
                        value
                            ? 'Votre profil est maintenant visible.'
                            : 'Votre profil est désormais restreint.',
                      );
                    },
            ),

          if (_role == 'joueur' || isOpportunityPublisherRole(_role))
            SwitchListTile(
              secondary: const Icon(Icons.message),
              title: const Text('Autoriser les messages'),
              subtitle: Text(_messagePermissionLabel()),
              value: _allowMessages,
              onChanged: _isDeleting
                  ? null
                  : (value) async {
                      final previous = _allowMessages;
                      setState(() => _allowMessages = value);

                      final ok = await _updatePrivacySetting(
                        allowMessages: value,
                      );
                      if (!ok && mounted) {
                        setState(() => _allowMessages = previous);
                        return;
                      }

                      AdFeedback.info(
                        'Messages',
                        value
                            ? 'Les messages sont autorisés.'
                            : 'Les messages sont désactivés.',
                      );
                    },
            ),

          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Utilisation des données'),
            subtitle: const Text(
              'Vos données sont utilisées uniquement dans le cadre '
              'du scouting et de la mise en relation.',
            ),
            onTap: () {
              AdFeedback.info(
                'Données personnelles',
                "Adfoot ne vend jamais vos données.\n"
                    'Elles servent uniquement à connecter les talents '
                    'aux opportunités sportives.',
                duration: const Duration(seconds: 5),
              );
            },
          ),

          const Divider(height: 32),

          // =====================================================
          // 🛡️ SÉCURITÉ & OPPORTUNITÉS PROFESSIONNELLES
          // =====================================================
          _sectionTitle("Sécurité & opportunités"),

          _securityIntroCard(cs),
          const SizedBox(height: 12),
          _riskAwarenessCard(cs),
          const SizedBox(height: 12),
          _officialRuleCard(cs),
          const SizedBox(height: 8),

          ListTile(
            leading: Icon(Icons.support_agent, color: cs.primary),
            title: const Text("Contacter l'équipe Adfoot"),
            subtitle: const Text(
              "Vérification d'opportunités et accompagnement sécurisé",
            ),
            onTap: () {
              AdFeedback.info(
                'Équipe Adfoot',
                "Avant toute décision, contactez-nous.\n\n"
                    "adfoot.org\nWhatsApp : +223 70 66 83 64",
                duration: const Duration(seconds: 6),
              );
            },
          ),

          const Divider(height: 32),

          // =====================================================
          // ❌ ZONE DANGEREUSE
          // =====================================================
          _sectionTitle("Zone dangereuse"),

          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text(
              'Supprimer mon compte',
              style: TextStyle(color: Colors.red),
            ),
            subtitle: const Text(
              'Suppression définitive du compte et de toutes les données.',
            ),
            enabled: !_isDeleting,
            onTap: _isDeleting ? null : _confirmDeleteAccount,
          ),
        ],
      ),
    );
  }

  // =========================================================
  // 🛡️ SECURITY UI BLOCKS
  // =========================================================

  Widget _securityIntroCard(ColorScheme cs) {
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.primary.withValues(alpha: 0.15)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield, color: cs.primary),
                const SizedBox(width: 8),
                const Text(
                  "Votre sécurité avant tout",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              "Adfoot facilite la mise en relation entre joueurs, clubs, "
              "agents et recruteurs. Cependant, nous ne pouvons pas contrôler "
              "chaque individu présent sur la plateforme.",
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _riskAwarenessCard(ColorScheme cs) {
    return Card(
      elevation: 0,
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              "⚠️ Risques fréquents",
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text("• Faux agents demandant de l'argent"),
            Text("• Promesses de contrats sans documents officiels"),
            Text("• Voyages non encadrés ou dangereux"),
            Text("• Exploitation de jeunes joueurs"),
          ],
        ),
      ),
    );
  }

  Widget _officialRuleCard(ColorScheme cs) {
    return Card(
      elevation: 0,
      color: cs.primary.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              "Règle officielle Adfoot",
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            Text(
              "Si un club, un agent ou un recruteur vous propose une opportunité, "
              "contactez Adfoot avant toute décision.\n\n"
              "Notre agence vérifie la fiabilité, sécurise les démarches "
              "et vous accompagne de manière professionnelle.",
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // 🔥 SUPPRESSION COMPTE
  // =========================================================

  Future<void> _confirmDeleteAccount() async {
    final uid = _authSessionService.currentUser?.uid;
    if (uid == null) return;

    final confirmed = await AdDialogs.confirm(
      context: context,
      title: 'Supprimer mon compte',
      message: 'Cette action supprimera définitivement votre compte et '
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

      AdFeedback.error(
        'Suppression impossible',
        error.message,
      );
    } catch (e) {
      closeBlockingDialog();
      AdFeedback.error(
        'Suppression impossible',
        "Une erreur est survenue pendant la suppression : $e",
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
      default:
        return '';
    }
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
    );
  }
}
