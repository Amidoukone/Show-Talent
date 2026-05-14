import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/controller/follow_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/screens/profile_screen.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/widgets/ad_feedback.dart';
import 'package:adfoot/widgets/ad_state_panel.dart';

class FollowListScreen extends StatefulWidget {
  final String uid;
  final String listType; // 'followers' ou 'followings'

  const FollowListScreen({
    super.key,
    required this.uid,
    required this.listType,
  });

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  final FollowController _followController = Get.find<FollowController>();

  List<FollowUserItem> _items = const <FollowUserItem>[];
  bool _isLoading = true;
  bool _hasLoadError = false;

  @override
  void initState() {
    super.initState();
    _reloadFollowList();
  }

  Future<void> _reloadFollowList() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _hasLoadError = false;
      });
    }

    try {
      final raw = await _followController.fetchFollowList(
        widget.uid,
        widget.listType,
      );
      final items = raw.map((m) => FollowUserItem.fromMap(m)).toList();

      if (!mounted) {
        return;
      }

      setState(() {
        _items = items;
        _isLoading = false;
        _hasLoadError = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _items = const <FollowUserItem>[];
        _isLoading = false;
        _hasLoadError = true;
      });
    }
  }

  void _updateItemFollowState(String uid, bool isFollowing) {
    final index = _items.indexWhere((item) => item.uid == uid);
    if (index < 0 || !mounted) {
      return;
    }

    setState(() {
      _items[index].isFollowing = isFollowing;
    });
  }

  void _removeItem(String uid) {
    if (!mounted) {
      return;
    }

    setState(() {
      _items = _items.where((item) => item.uid != uid).toList(growable: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.listType == 'followers' ? 'Abonnés' : 'Abonnements',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _reloadFollowList,
        child: Builder(
          builder: (context) {
            if (_isLoading) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 240),
                  Center(child: CircularProgressIndicator()),
                ],
              );
            }

            if (_hasLoadError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: AdStatePanel.error(
                      title: 'Chargement impossible',
                      message: 'Une erreur est survenue. Veuillez réessayer.',
                    ),
                  ),
                ],
              );
            }

            if (_items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: AdStatePanel.empty(
                      title: widget.listType == 'followers'
                          ? 'Aucun abonne'
                          : 'Aucun abonnement',
                      message: widget.listType == 'followers'
                          ? "Aucun abonne pour l'instant."
                          : "Aucun abonnement pour l'instant.",
                    ),
                  ),
                ],
              );
            }

            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final u = _items[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 5.0,
                    horizontal: 10.0,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundImage: u.photoProfil.isNotEmpty
                          ? NetworkImage(u.photoProfil)
                          : const AssetImage('assets/default_avatar.jpg')
                              as ImageProvider,
                      backgroundColor: Colors.grey.shade200,
                    ),
                    title: Text(
                      u.nom,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      u.role,
                      style: const TextStyle(color: Colors.grey),
                    ),
                    trailing: _FollowListButton(
                      u: u,
                      listOwnerUid: widget.uid,
                      listType: widget.listType,
                      onFollowStateChanged: (value) =>
                          _updateItemFollowState(u.uid, value),
                      onRemove: () => _removeItem(u.uid),
                    ),
                    onTap: () {
                      Get.to(() => ProfileScreen(uid: u.uid, isReadOnly: true));
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Bouton “S’abonner / Se désabonner” optimisé dans la liste
class _FollowListButton extends StatefulWidget {
  final FollowUserItem u;
  final String listOwnerUid;
  final String listType;
  final ValueChanged<bool> onFollowStateChanged;
  final VoidCallback onRemove;

  const _FollowListButton({
    required this.u,
    required this.listOwnerUid,
    required this.listType,
    required this.onFollowStateChanged,
    required this.onRemove,
  });

  @override
  State<_FollowListButton> createState() => _FollowListButtonState();
}

class _FollowListButtonState extends State<_FollowListButton> {
  bool _isLoading = false;
  final AuthSessionService _authSessionService = AuthSessionService();

  @override
  Widget build(BuildContext context) {
    final currentUserId = Get.find<UserController>().user?.uid ??
        _authSessionService.currentUser?.uid;
    final followCtrl = Get.find<FollowController>();

    // Si c'est son propre compte → ne pas afficher le bouton
    if (currentUserId == null || widget.u.uid == currentUserId) {
      return const SizedBox.shrink();
    }

    final bool isFollowing = widget.u.isFollowing;

    return ElevatedButton(
      onPressed: () async {
        if (_isLoading) return;

        final bool nextFollowState = !isFollowing;
        setState(() {
          _isLoading = true;
          widget.u.isFollowing = nextFollowState;
        });
        widget.onFollowStateChanged(nextFollowState);

        try {
          final bool success = isFollowing
              ? await followCtrl.unfollowUser(currentUserId, widget.u.uid)
              : await followCtrl.followUser(currentUserId, widget.u.uid);

          if (!success) {
            widget.u.isFollowing = isFollowing;
            widget.onFollowStateChanged(isFollowing);
            AdFeedback.error('Erreur', "Impossible d'effectuer l'action.");
          } else if (isFollowing &&
              widget.listType == 'followings' &&
              currentUserId == widget.listOwnerUid) {
            widget.onRemove();
          }
        } catch (_) {
          widget.u.isFollowing = isFollowing;
          widget.onFollowStateChanged(isFollowing);
          AdFeedback.error('Erreur', "Impossible d'effectuer l'action.");
        } finally {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: widget.u.isFollowing
            ? const Color.fromARGB(255, 158, 50, 42)
            : const Color.fromARGB(255, 7, 99, 79),
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      ),
      child: _isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(
              widget.u.isFollowing ? 'Se désabonner' : 'S’abonner',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
    );
  }
}

/// Modèle local pour la ligne utilisateur dans la liste Follow
class FollowUserItem {
  final String uid;
  final String nom;
  final String photoProfil;
  final String role;
  bool isFollowing;

  FollowUserItem({
    required this.uid,
    required this.nom,
    required this.photoProfil,
    required this.role,
    required this.isFollowing,
  });

  factory FollowUserItem.fromMap(Map<String, dynamic> m) {
    return FollowUserItem(
      uid: m['uid'] as String,
      nom: (m['nom'] as String?) ?? '',
      photoProfil: (m['photoProfil'] as String?) ?? '',
      role: (m['role'] as String?) ?? '',
      isFollowing: (m['isFollowing'] as bool?) ?? false,
    );
  }
}
