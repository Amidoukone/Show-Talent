import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

import 'package:adfoot/screens/profile_screen.dart';
import 'package:adfoot/services/account_cleanup_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AccountCleanupService _cleanupService = AccountCleanupService();

  bool _isDeleting = false;
  bool _loadingRole = true;

  // 🔑 rôle utilisateur
  String _role = 'fan';

  // 🔐 états confidentialité (frontend-only)
  bool _profilePublic = true;
  bool _allowMessages = true;

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final doc =
          await _firestore.collection('users').doc(user.uid).get();
      final data = doc.data();
      if (data != null && data['role'] != null) {
        _role = data['role'];
      }
    } catch (_) {}
    setState(() => _loadingRole = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingRole) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
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
        padding: const EdgeInsets.only(bottom: 24),
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
              final user = _auth.currentUser;
              if (user == null) return;

              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProfileScreen(uid: user.uid),
                ),
              );
            },
          ),

          ListTile(
            leading: Icon(Icons.logout, color: cs.primary),
            title: const Text('Se déconnecter'),
            enabled: !_isDeleting,
            onTap: () async {
              await _auth.signOut();
              Get.offAllNamed('/login');
            },
          ),

          const Divider(height: 32),

          // =====================================================
          // 🔐 CONFIDENTIALITÉ (MULTI-RÔLES)
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
                  : (value) {
                      setState(() => _profilePublic = value);
                      Get.snackbar(
                        'Confidentialité',
                        value
                            ? 'Votre profil est maintenant visible.'
                            : 'Votre profil est désormais restreint.',
                      );
                    },
            ),

          if (_role == 'joueur' || _role == 'club')
            SwitchListTile(
              secondary: const Icon(Icons.message),
              title: const Text('Autoriser les messages'),
              subtitle: Text(_messagePermissionLabel()),
              value: _allowMessages,
              onChanged: _isDeleting
                  ? null
                  : (value) {
                      setState(() => _allowMessages = value);
                      Get.snackbar(
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
              Get.snackbar(
                'Données personnelles',
                'ADFOOT ne vend jamais vos données.\n'
                'Elles servent uniquement à connecter les talents '
                'aux opportunités sportives.',
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
            onTap: _isDeleting ? null : () => _confirmDeleteAccount(context),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // 🔥 SUPPRESSION COMPTE
  // =========================================================
  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer mon compte'),
        content: const Text(
          'Cette action supprimera définitivement votre compte et '
          'toutes vos données.\n\nVoulez-vous continuer ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Supprimer',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isDeleting = true);

    Get.dialog(
      const Center(child: CircularProgressIndicator()),
      barrierDismissible: false,
    );

    await _cleanupService.deleteAccountAndData(
      uid: user.uid,
      deleteAuthUser: true,
    );

    if (Get.isDialogOpen ?? false) Get.back();
    if (!mounted) return;

    Get.offAllNamed('/login');
    Get.snackbar(
      'Compte supprimé',
      'Votre compte a été supprimé avec succès.',
    );
  }

  // =========================================================
  // 🧩 Helpers
  // =========================================================
  String _profileVisibilityLabel() {
    switch (_role) {
      case 'joueur':
        return 'Visible par les clubs et recruteurs.';
      case 'recruteur':
        return 'Visible par les joueurs.';
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
