import 'package:adfoot/controller/chat_controller.dart';
import 'package:adfoot/config/app_routes.dart';
import 'package:adfoot/controller/offre_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/models/action_response.dart';
import 'package:adfoot/models/offre.dart';
import 'package:adfoot/screens/chat_screen.dart';
import 'package:adfoot/screens/offres_form.dart';
import 'package:adfoot/screens/profile_screen.dart';
import 'package:adfoot/utils/account_role_policy.dart';
import 'package:adfoot/widgets/ad_button.dart';
import 'package:adfoot/widgets/ad_dialogs.dart';
import 'package:adfoot/widgets/ad_feedback.dart';
import 'package:adfoot/widgets/ad_state_panel.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

// Palette
import 'package:adfoot/theme/ad_colors.dart';

class OffreScreen extends StatefulWidget {
  const OffreScreen({super.key});

  @override
  State<OffreScreen> createState() => _OffreScreenState();
}

class _OffreScreenState extends State<OffreScreen> {
  final OffreController offreController = Get.find<OffreController>();
  final UserController userController = Get.find<UserController>();
  final ChatController chatController = Get.find<ChatController>();

  final TextEditingController _searchController = TextEditingController();

  String _selectedStatus = 'tous';
  final String _selectedRole = 'tous';
  String _sort = 'recentes';

  /// Anti-spam: only one view counted per offer per session.
  final Set<String> _viewedOffres = <String>{};
  String _normalizeStatus(String rawStatus) {
    final value = rawStatus.trim().toLowerCase();
    switch (value) {
      case 'ouverte':
        return 'ouverte';
      case 'fermee':
      case 'fermée':
        return 'fermee';
      case 'archivee':
      case 'archivée':
        return 'archivee';
      case 'brouillon':
        return 'brouillon';
      default:
        return value;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Liste des Offres',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
      ),
      body: Obx(() {
        final currentUser = userController.user;
        final offres = _filteredOffres(offreController.offres);

        if (offreController.isLoading && offres.isEmpty) {
          return _buildSkeletons();
        }

        if (offres.isEmpty) {
          return _buildEmptyState(currentUser);
        }

        return Column(
          children: [
            _buildFilters(),
            Expanded(
              child: ListView.builder(
                itemCount: offres.length,
                padding: const EdgeInsets.all(8.0),
                itemBuilder: (context, index) {
                  final offre = offres[index];

                  // =========================================================
                  // View increment with anti-rebuild protection.
                  // =========================================================
                  if (currentUser != null &&
                      currentUser.uid != offre.recruteur.uid &&
                      !_viewedOffres.contains(offre.id)) {
                    _viewedOffres.add(offre.id);

                    // Fire-and-forget to keep UI responsive.
                    offreController.incrementVues(
                      offre: offre,
                      viewer: currentUser,
                    );
                  }

                  final isOwner = currentUser?.uid == offre.recruteur.uid;
                  final isPostulable = currentUser?.role == 'joueur' &&
                      offre.statut == 'ouverte';

                  return Card(
                    margin:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 5,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildRecruteurSection(context, offre),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      offre.titre,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      offre.description,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              _StatusBadge(status: offre.statut),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (offreController.isLoading)
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 8),
                                  child: LinearProgressIndicator(minHeight: 2),
                                ),
                              if (offre.posteRecherche?.isNotEmpty ?? false)
                                _buildChip(
                                    Icons.sports_soccer, offre.posteRecherche!),
                              if (offre.niveau?.isNotEmpty ?? false)
                                _buildChip(Icons.star_border, offre.niveau!),
                              if (offre.localisation?.isNotEmpty ?? false)
                                _buildChip(
                                    Icons.place_outlined, offre.localisation!),
                              if (offre.remuneration?.isNotEmpty ?? false)
                                _buildChip(Icons.payments_outlined,
                                    offre.remuneration!),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.event,
                                  size: 16, color: AdColors.onSurfaceMuted),
                              const SizedBox(width: 4),
                              Text(
                                'Valide jusqu\'au : ${DateFormat('dd MMM yyyy').format(offre.dateFin)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AdColors.onSurfaceMuted,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.remove_red_eye_outlined,
                                  size: 16, color: AdColors.onSurfaceMuted),
                              const SizedBox(width: 4),
                              Text(
                                '${offre.vues ?? 0} vues',
                                style: TextStyle(color: cs.onSurface),
                              ),
                              const SizedBox(width: 12),
                              Icon(Icons.group_outlined,
                                  size: 16, color: AdColors.onSurfaceMuted),
                              const SizedBox(width: 4),
                              Text(
                                '${offre.candidats.length} candidatures',
                                style: TextStyle(color: cs.onSurface),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _buildActionButtons(
                            context,
                            offre,
                            isOwner,
                            isPostulable,
                            currentUser,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      }),
      floatingActionButton: _buildFloatingButton(),
    );
  }

  // =========================================================
  // Filtering / sorting
  // =========================================================
  List<Offre> _filteredOffres(List<Offre> source) {
    final query = _searchController.text.toLowerCase().trim();

    List<Offre> filtered = source.where((o) {
      final matchesSearch = query.isEmpty ||
          o.titre.toLowerCase().contains(query) ||
          o.description.toLowerCase().contains(query);

      final matchesStatus = _selectedStatus == 'tous'
          ? true
          : _normalizeStatus(o.statut) == _selectedStatus;

      final matchesRole =
          _selectedRole == 'tous' ? true : o.recruteur.role == _selectedRole;

      return matchesSearch && matchesStatus && matchesRole;
    }).toList();

    if (_sort == 'fin') {
      filtered.sort((a, b) => a.dateFin.compareTo(b.dateFin));
    } else {
      filtered.sort((a, b) => b.dateCreation.compareTo(a.dateCreation));
    }

    return filtered;
  }

  // =========================================================
  // UI builders
  // =========================================================
  Widget _buildSkeletons() {
    return ListView.builder(
      itemCount: 3,
      padding: const EdgeInsets.all(12),
      itemBuilder: (_, __) => Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: 14, width: 120, color: Colors.grey.shade300),
              const SizedBox(height: 10),
              Container(
                  height: 16,
                  width: double.infinity,
                  color: Colors.grey.shade300),
              const SizedBox(height: 8),
              Container(
                  height: 16,
                  width: double.infinity,
                  color: Colors.grey.shade300),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(dynamic currentUser) {
    final isPublisher = isOpportunityPublisherRole(currentUser?.role);
    final actionLabel = isPublisher ? 'Créer une offre' : 'Voir les clubs';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AdStatePanel(
          icon: Icons.search_off,
          title: 'Aucune offre disponible',
          message: isPublisher
              ? 'Publiez votre première offre pour démarrer.'
              : 'Aucune offre ne correspond aux filtres actuels.',
          action: AdButton(
            expanded: false,
            label: actionLabel,
            onPressed: () {
              if (isPublisher) {
                Get.to(() => const OffreFormScreen());
                return;
              }

              Get.offAllNamed(
                AppRoutes.main,
                arguments: {'tab': 2},
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: const BoxDecoration(
        color: AdColors.surfaceAlt,
        border: Border(
          bottom: BorderSide(color: AdColors.divider),
        ),
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: cs.onSurface),
            decoration: InputDecoration(
              hintText: 'Rechercher une offre...',
              prefixIcon: const Icon(Icons.search),
              // Keep theme-driven input styling.
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'Toutes',
                  selected: _selectedStatus == 'tous',
                  onTap: () => setState(() => _selectedStatus = 'tous'),
                ),
                _FilterChip(
                  label: 'Ouvertes',
                  selected: _selectedStatus == 'ouverte',
                  onTap: () => setState(() => _selectedStatus = 'ouverte'),
                ),
                _FilterChip(
                  label: 'Fermées',
                  selected: _selectedStatus == 'fermee',
                  onTap: () => setState(() => _selectedStatus = 'fermee'),
                ),
                _FilterChip(
                  label: 'Archivées',
                  selected: _selectedStatus == 'archivee',
                  onTap: () => setState(() => _selectedStatus = 'archivee'),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _sort,
                  underline: const SizedBox.shrink(),
                  dropdownColor: AdColors.surfaceCard,
                  style: TextStyle(
                      color: cs.onSurface, fontWeight: FontWeight.w600),
                  items: const [
                    DropdownMenuItem(
                        value: 'recentes', child: Text('Plus récentes')),
                    DropdownMenuItem(
                        value: 'fin', child: Text('Se terminant bientôt')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _sort = v);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(IconData icon, String label) {
    final cs = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(icon, size: 16, color: cs.primary),
      label: Text(label, style: TextStyle(color: cs.onSurface)),
      backgroundColor: AdColors.surfaceCard,
      side: const BorderSide(color: AdColors.divider),
    );
  }

  bool _isValidPhotoUrl(String? url) {
    if (url == null) return false;
    final t = url.trim();
    return t.isNotEmpty &&
        (t.startsWith('http://') || t.startsWith('https://'));
  }

  Widget _buildRecruteurSection(BuildContext context, Offre offre) {
    final cs = Theme.of(context).colorScheme;
    final bool valid = _isValidPhotoUrl(offre.recruteur.photoProfil);

    return Row(
      children: [
        GestureDetector(
          onTap: () {
            Get.to(() => ProfileScreen(
                  uid: offre.recruteur.uid,
                  isReadOnly: true,
                ));
          },
          child: CircleAvatar(
            radius: 25,
            backgroundColor: AdColors.surfaceCardAlt,
            backgroundImage:
                valid ? NetworkImage(offre.recruteur.photoProfil) : null,
            child:
                valid ? null : const Icon(Icons.person, color: Colors.white70),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                offre.recruteur.nom,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
              Text(
                offre.recruteur.role,
                style: const TextStyle(
                    fontSize: 14, color: AdColors.onSurfaceMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    Offre offre,
    bool isOwner,
    bool isPostulable,
    dynamic currentUser,
  ) {
    if (isOwner) {
      final normalizedStatus = _normalizeStatus(offre.statut);
      return Wrap(
        spacing: 8,
        children: [
          DropdownButton<String>(
            value: normalizedStatus,
            dropdownColor: AdColors.surfaceCard,
            items: const [
              DropdownMenuItem(value: 'brouillon', child: Text('Brouillon')),
              DropdownMenuItem(value: 'ouverte', child: Text('Ouverte')),
              DropdownMenuItem(value: 'fermee', child: Text('Fermée')),
              DropdownMenuItem(value: 'archivee', child: Text('Archivée')),
            ],
            onChanged: (v) async {
              if (v != null) {
                if (currentUser == null) {
                  AdFeedback.error(
                    'Erreur',
                    'Utilisateur introuvable. Merci de vous reconnecter.',
                  );
                  return;
                }
                final response =
                    await offreController.changerStatut(offre, v, currentUser);
                response.showToast(includeSuccess: true);
              }
            },
          ),
          TextButton.icon(
            onPressed: () =>
                Get.to(() => const OffreFormScreen(), arguments: offre),
            icon: const Icon(Icons.edit),
            label: const Text('Modifier'),
          ),
          TextButton.icon(
            onPressed: () => _confirmDelete(context, offre),
            icon: const Icon(Icons.delete, color: Colors.red),
            label: const Text('Supprimer'),
          ),
          ElevatedButton.icon(
            onPressed: () => _showCandidats(context, offre),
            icon: const Icon(Icons.group),
            label: const Text('Voir candidats'),
          ),
        ],
      );
    }

    if (isPostulable) {
      final bool inscrit =
          offre.candidats.any((c) => c.uid == currentUser?.uid);

      return ElevatedButton(
        onPressed: () async {
          if (currentUser == null) {
            AdFeedback.error(
              'Erreur',
              'Utilisateur introuvable. Merci de vous reconnecter.',
            );
            return;
          }

          final response = inscrit
              ? await offreController.seDesinscrireOffre(currentUser, offre)
              : await offreController.postulerOffre(currentUser, offre);

          response.showToast(includeSuccess: true);
        },
        child: Text(inscrit ? 'Se désinscrire' : 'Postuler'),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildFloatingButton() {
    final currentUser = userController.user;
    if (isOpportunityPublisherRole(currentUser?.role)) {
      return FloatingActionButton(
        onPressed: () => Get.to(() => const OffreFormScreen()),
        child: const Icon(Icons.add),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _confirmDelete(BuildContext context, Offre offre) async {
    final confirmed = await AdDialogs.confirm(
      context: context,
      title: 'Supprimer cette offre',
      message: 'Voulez-vous vraiment supprimer cette offre ?',
      confirmLabel: 'Supprimer',
      cancelLabel: 'Annuler',
      danger: true,
    );
    if (!confirmed) return;

    final currentUser = userController.user;
    if (currentUser == null) {
      AdFeedback.error(
        'Erreur',
        'Utilisateur introuvable. Merci de vous reconnecter.',
      );
      return;
    }

    final response = await offreController.supprimerOffre(
      offre.id,
      currentUser,
      offre,
    );

    if (response.success) {
      AdFeedback.success(
        'Offre supprimée',
        "L'offre a été supprimée avec succès.",
      );
    } else if (response.toast == ToastLevel.none) {
      return;
    } else {
      AdFeedback.error(
        'Erreur',
        response.message,
      );
    }
  }

  void _showCandidats(BuildContext context, Offre offre) {
    Get.bottomSheet(
      StatefulBuilder(builder: (context, setState) {
        String sort = 'nom';

        final sorted = [...offre.candidats];
        if (sort == 'role') {
          sorted.sort((a, b) => a.role.compareTo(b.role));
        } else {
          sorted.sort((a, b) => a.nom.compareTo(b.nom));
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: AdColors.surfaceAlt,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Liste des candidats',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  DropdownButton<String>(
                    value: sort,
                    dropdownColor: AdColors.surfaceCard,
                    items: const [
                      DropdownMenuItem(value: 'nom', child: Text('Par nom')),
                      DropdownMenuItem(value: 'role', child: Text('Par rôle')),
                    ],
                    onChanged: (v) => setState(() => sort = v ?? 'nom'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (sorted.isEmpty)
                const Text('Aucun candidat pour l\'instant')
              else
                ListView.separated(
                  shrinkWrap: true,
                  itemCount: sorted.length,
                  separatorBuilder: (_, __) => const Divider(height: 12),
                  itemBuilder: (_, i) {
                    final candidat = sorted[i];
                    final valid = _isValidPhotoUrl(candidat.photoProfil);

                    return Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AdColors.surfaceCardAlt,
                          backgroundImage:
                              valid ? NetworkImage(candidat.photoProfil) : null,
                          child: valid ? null : const Icon(Icons.person),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                candidat.nom,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              Text(
                                candidat.role,
                                style: const TextStyle(
                                    color: AdColors.onSurfaceMuted),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chat_bubble_outline),
                          onPressed: () async {
                            final current = userController.user;
                            if (current == null) return;

                            final conversationId =
                                await chatController.createOrGetConversation(
                              currentUserId: current.uid,
                              otherUserId: candidat.uid,
                            );

                            Get.to(() => ChatScreen(
                                  conversationId: conversationId,
                                  otherUser: candidat,
                                ));
                          },
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
        );
      }),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Color bg;
    Color fg;

    final normalized = status.trim().toLowerCase();

    switch (normalized) {
      case 'ouverte':
        bg = cs.primary.withValues(alpha: 0.14);
        fg = cs.primary;
        break;
      case 'fermee':
      case 'fermée':
        bg = AdColors.error.withValues(alpha: 0.14);
        fg = AdColors.error;
        break;
      case 'archivee':
      case 'archivée':
        bg = AdColors.onSurfaceMuted.withValues(alpha: 0.14);
        fg = AdColors.onSurfaceMuted;
        break;
      default:
        bg = cs.secondary.withValues(alpha: 0.14);
        fg = cs.secondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: const BorderSide(color: AdColors.divider).toBorder(),
      ),
      child: Text(
        status,
        style: TextStyle(fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: cs.primary.withValues(alpha: 0.18),
        backgroundColor: AdColors.surfaceCard,
        labelStyle: TextStyle(
          color: selected ? cs.primary : cs.onSurface,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        ),
        side: const BorderSide(color: AdColors.divider),
      ),
    );
  }
}

extension _BorderSideX on BorderSide {
  Border toBorder() => Border.fromBorderSide(this);
}
