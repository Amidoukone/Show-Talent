import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/offre_controller.dart';
import 'package:show_talent/controller/user_controller.dart';
import 'package:show_talent/models/offre.dart';
import 'package:show_talent/screens/offres_form.dart';

class OffreScreen extends StatelessWidget {
  final OffreController offreController = Get.put(OffreController());
  final UserController userController = Get.find<UserController>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Liste des Offres',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.teal,
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
                  final isPostulable = currentUser?.role == 'joueur' && offre.statut == 'ouverte';

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 5,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            offre.titre,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            offre.description,
                            style: const TextStyle(fontSize: 14, color: Colors.black87),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2, // Limite la description pour éviter le débordement
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Statut : ${offre.statut}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: offre.statut == 'ouverte' ? Colors.green : Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (isOwner)
                                ElevatedButton.icon(
                                  onPressed: () => _showCandidats(context, offre),
                                  icon: const Icon(Icons.group, size: 16),
                                  label: const Text('Voir les candidats'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal.shade700,
                                    foregroundColor: Colors.white, // Texte blanc
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (isOwner)
                            Wrap( // Utilisation de Wrap pour éviter le débordement horizontal
                              spacing: 8.0,
                              runSpacing: 4.0,
                              children: [
                                TextButton.icon(
                                  onPressed: () => Get.to(() => OffreFormScreen(), arguments: offre),
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
                              ],
                            ),
                          if (isPostulable)
                            ElevatedButton(
                              onPressed: () {
                                if (offre.candidats.any((c) => c.uid == currentUser!.uid)) {
                                  Get.snackbar(
                                    'Postulation existante',
                                    'Vous avez déjà postulé à cette offre.',
                                    backgroundColor: Colors.orange.shade100,
                                    colorText: Colors.black87,
                                  );
                                } else {
                                  offreController.postulerOffre(currentUser!, offre);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('Postuler'),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
      }),
      floatingActionButton: Obx(() {
        final currentUser = userController.user;
        if (currentUser?.role == 'club' || currentUser?.role == 'recruteur') {
          return FloatingActionButton(
            onPressed: () {
              Get.to(() => OffreFormScreen());
            },
            backgroundColor: Colors.teal,
            child: const Icon(Icons.add),
          );
        }
        return Container();
      }),
    );
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
            onPressed: () {
              offreController.supprimerOffre(offre.id, userController.user!, offre);
              Get.back();
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
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.teal),
            ),
            const SizedBox(height: 10),
            ...offre.candidats.map((candidat) => Card(
                  margin: const EdgeInsets.symmetric(vertical: 4.0),
                  elevation: 2.0,
                  child: ListTile(
                    title: Text(candidat.nom),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Email : ${candidat.email}'),
                        Text(
                          'Position : ${candidat.position ?? 'Position inconnue'}',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
