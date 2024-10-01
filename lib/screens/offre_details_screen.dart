import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/models/user.dart';
import 'package:show_talent/screens/profile_screen.dart';
import '../controller/offre_controller.dart';
import '../models/offre.dart';
import '../controller/auth_controller.dart';
import 'modifier_offre_screen.dart';  // Import pour l'écran de modification

class OffreDetailsScreen extends StatelessWidget {
  final Offre offre;
  const OffreDetailsScreen({required this.offre, super.key});

  @override
  Widget build(BuildContext context) {
    AppUser? user = AuthController.instance.user;

    return Scaffold(
      appBar: AppBar(
        title: Text(offre.titre),
        actions: [
          // Si l'utilisateur est le recruteur, il peut modifier ou supprimer l'offre
          if (user?.uid == offre.recruteur.uid) 
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'modifier') {
                  // Rediriger vers l'écran de modification
                  Get.to(() => ModifierOffreScreen(offre: offre));
                } else if (value == 'supprimer') {
                  // Demander confirmation avant de supprimer
                  _confirmDelete(context, offre);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem<String>(
                  value: 'modifier',
                  child: Text('Modifier'),
                ),
                const PopupMenuItem<String>(
                  value: 'supprimer',
                  child: Text('Supprimer'),
                ),
              ],
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Description : ${offre.description}', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 10),
            Text('Date début : ${offre.dateDebut.toLocal()}'),
            Text('Date fin : ${offre.dateFin.toLocal()}'),
            const SizedBox(height: 20),

            // Si l'utilisateur est le recruteur, afficher la liste des candidats
            if (user?.uid == offre.recruteur.uid) ...[
              const Text('Liste des candidats :', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: offre.candidats.length,
                  itemBuilder: (context, index) {
                    AppUser candidat = offre.candidats[index];
                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(candidat.nom),
                        subtitle: Text(candidat.email),
                        onTap: () {
                          // Rediriger vers le profil du candidat en mode lecture seule
                          Get.to(() => ProfileScreen(uid: candidat.uid, isReadOnly: true));
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Méthode pour demander confirmation avant suppression
  void _confirmDelete(BuildContext context, Offre offre) {
    Get.defaultDialog(
      title: 'Confirmation',
      middleText: 'Êtes-vous sûr de vouloir supprimer cette offre ?',
      textConfirm: 'Oui',
      textCancel: 'Annuler',
      confirmTextColor: Colors.white,
      onConfirm: () {
        OffreController.instance.supprimerOffre(offre.id);
        Get.back(); // Fermer la boîte de dialogue
        Get.back(); // Revenir à l'écran précédent
      },
      onCancel: () => Get.back(), // Fermer la boîte de dialogue
    );
  }
}
