import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/controller/offre_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/models/offre.dart';
import 'package:adfoot/screens/offres_form.dart';
import 'package:adfoot/screens/profile_screen.dart';
import 'package:intl/intl.dart';

class OffreScreen extends StatelessWidget {
  final OffreController offreController = Get.put(OffreController());
  final UserController userController = Get.find<UserController>();

  OffreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Liste des Offres',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF214D4F),
      ),
      body: Obx(() {
        final offres = offreController.offres;
        final currentUser = userController.user;

        return offres.isEmpty
            ? const Center(
                child: Text(
                  "Aucune offre disponible",
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              )
            : ListView.builder(
                itemCount: offres.length,
                padding: const EdgeInsets.all(8.0),
                itemBuilder: (context, index) {
                  final offre = offres[index];
                  final isOwner = currentUser?.uid == offre.recruteur.uid;
                  final isPostulable =
                      currentUser?.role == 'joueur' && offre.statut == 'ouverte';

                  return Card(
                    margin:
                        const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 5,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildRecruteurSection(context, offre),
                          const SizedBox(height: 12),
                          Text(
                            offre.titre,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color.fromARGB(255, 12, 40, 37),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            offre.description,
                            style: const TextStyle(
                                fontSize: 14, color: Colors.black87),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Valide jusqu\'au : ${DateFormat('dd MMM yyyy').format(offre.dateFin)}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Statut : ${offre.statut}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: offre.statut == 'ouverte'
                                      ? const Color.fromARGB(255, 17, 69, 45)
                                      : Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _buildActionButtons(context, offre, isOwner,
                              isPostulable, currentUser),
                        ],
                      ),
                    ),
                  );
                },
              );
      }),
      floatingActionButton: _buildFloatingButton(),
    );
  }

  bool _isValidPhotoUrl(String? url) {
    if (url == null) return false;
    final trimmed = url.trim();
    if (trimmed.isEmpty) return false;
    return trimmed.startsWith('http://') || trimmed.startsWith('https://');
  }

  Widget _buildRecruteurSection(BuildContext context, Offre offre) {
    final String photoUrl = offre.recruteur.photoProfil;
    final bool isValidPhoto = _isValidPhotoUrl(photoUrl);

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
            backgroundColor: Colors.grey.shade200,
            backgroundImage: isValidPhoto ? NetworkImage(photoUrl) : null,
            child: isValidPhoto
                ? null
                : const Icon(Icons.person, size: 24, color: Colors.white70),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                offre.recruteur.nom.isNotEmpty
                    ? offre.recruteur.nom
                    : 'Nom inconnu',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                offre.recruteur.role.isNotEmpty
                    ? offre.recruteur.role
                    : 'Rôle inconnu',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context, Offre offre, bool isOwner,
      bool isPostulable, dynamic currentUser) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.person, size: 18, color: Colors.black54),
            const SizedBox(width: 4),
            Text(
              '${offre.candidats.length} joueur(s) ont postulé',
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (isOwner)
          Wrap(
            spacing: 8.0,
            runSpacing: 4.0,
            children: [
              TextButton.icon(
                onPressed: () =>
                    Get.to(() => OffreFormScreen(), arguments: offre),
                icon: const Icon(Icons.edit, color: Colors.blue),
                label: const Text("Modifier"),
              ),
              TextButton.icon(
                onPressed: () => _changeStatus(offre),
                icon: const Icon(Icons.lock, color: Colors.orange),
                label: const Text("Fermer"),
              ),
              TextButton.icon(
                onPressed: () => _confirmDelete(context, offre),
                icon: const Icon(Icons.delete, color: Colors.red),
                label: const Text("Supprimer"),
              ),
              ElevatedButton.icon(
                onPressed: () => _showCandidats(context, offre),
                icon: const Icon(Icons.group, size: 16),
                label: const Text('Voir les candidats'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 12, 40, 37),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          )
        else if (isPostulable)
          StatefulBuilder(
            builder: (context, setState) {
              bool isInscrit = offre.candidats
                  .any((candidat) => candidat.uid == currentUser!.uid);

              return ElevatedButton(
                onPressed: () async {
                  if (isInscrit) {
                    await offreController
                        .seDesinscrireOffre(currentUser!, offre);
                  } else {
                    await offreController.postulerOffre(currentUser!, offre);
                  }
                  setState(() => isInscrit = !isInscrit);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isInscrit ? Colors.red : Colors.teal.shade600,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  elevation: 3,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isInscrit ? Icons.close : Icons.send,
                        color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      isInscrit ? "Se désinscrire" : "Postuler",
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildFloatingButton() {
    final currentUser = userController.user;
    if (currentUser?.role == 'club' || currentUser?.role == 'recruteur') {
      return FloatingActionButton(
        onPressed: () {
          Get.to(() => OffreFormScreen());
        },
        backgroundColor: const Color.fromARGB(255, 12, 40, 37),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      );
    }
    return Container();
  }

  void _confirmDelete(BuildContext context, Offre offre) {
    Get.dialog(
      AlertDialog(
        title: const Text('Confirmation'),
        content: const Text('Voulez-vous vraiment supprimer cette offre ?'),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () async {
              await offreController.supprimerOffre(
                  offre.id, userController.user!, offre);
              if (Get.isDialogOpen == true) Get.back();
            },
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _changeStatus(Offre offre) {
    offre.statut = 'fermée';
    offreController.modifierOffre(offre, userController.user!);
    Get.snackbar('Succès', 'Le statut de l\'offre est maintenant "Fermée".');
  }

  void _showCandidats(BuildContext context, Offre offre) {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(16.0),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Liste des candidats',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Color.fromARGB(255, 12, 40, 37)),
            ),
            const SizedBox(height: 12),
            if (offre.candidats.isEmpty)
              const Text(
                "Aucun candidat pour l’instant",
                style: TextStyle(color: Colors.grey),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: offre.candidats.length,
                separatorBuilder: (_, __) => const Divider(height: 12),
                itemBuilder: (context, index) {
                  final candidat = offre.candidats[index];
                  final bool valid = _isValidPhotoUrl(candidat.photoProfil);

                  return GestureDetector(
                    onTap: () {
                      Get.to(() => ProfileScreen(
                            uid: candidat.uid,
                            isReadOnly: true,
                          ));
                    },
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.grey.shade200,
                          backgroundImage:
                              valid ? NetworkImage(candidat.photoProfil) : null,
                          child: valid
                              ? null
                              : const Icon(Icons.person,
                                  size: 28, color: Colors.white70),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                candidat.nom.isNotEmpty
                                    ? candidat.nom
                                    : "Nom inconnu",
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                candidat.role.isNotEmpty
                                    ? candidat.role
                                    : "Rôle inconnu",
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
