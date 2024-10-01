import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/auth_controller.dart';
import '../controller/offre_controller.dart';
import 'offre_details_screen.dart';  // Un écran pour les détails de l'offre

class OffresScreen extends StatefulWidget {
  const OffresScreen({super.key});

  @override
  _OffresScreenState createState() => _OffresScreenState();
}

class _OffresScreenState extends State<OffresScreen> {
  final OffreController _offreController = Get.find<OffreController>();

  @override
  void initState() {
    super.initState();
    _offreController.getAllOffres(); // Charger toutes les offres
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offres'),
      ),
      body: Obx(() {
        var offresList = _offreController.offresFiltrees.isNotEmpty
            ? _offreController.offresFiltrees
            : _offreController.offres;

        if (offresList.isEmpty) {
          return const Center(child: Text('Aucune offre disponible'));
        }

        return ListView.builder(
          itemCount: offresList.length,
          itemBuilder: (context, index) {
            var offre = offresList[index];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10.0), // Ajout de padding pour un meilleur espacement
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Titre de l'offre
                      Text(
                        offre.titre,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 1, // Limite à une ligne pour les titres longs
                        overflow: TextOverflow.ellipsis, // Troncature des titres longs
                      ),
                      const SizedBox(height: 5),
                      // Statut de l'offre
                      Text(
                        'Statut: ${offre.statut}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 5),
                      // Date de fin
                      Text(
                        'Date Fin: ${offre.dateFin.toLocal()}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Bouton de postulation si l'utilisateur est un joueur
                      if (AuthController.instance.user?.role == 'joueur') // Si l'utilisateur est un joueur
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () async {
                              await _offreController.postulerOffre(offre);
                            },
                            icon: const Icon(Icons.check_circle_outline, size: 18),
                            label: const Text('Postuler'),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color.fromARGB(255, 4, 60, 60),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                          ),
                        ),
                      const SizedBox(height: 5),
                      // Ajouter un bouton pour afficher les détails
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            // Appeler l'écran de détails lors du clic
                            Get.to(() => OffreDetailsScreen(offre: offre));
                          },
                          child: const Text('Voir détails'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
