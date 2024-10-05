import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/auth_controller.dart';
import '../controller/offre_controller.dart';
import 'offre_details_screen.dart';

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
    _offreController.getAllOffres();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offres'),
        backgroundColor: const Color(0xFF214D4F),  // Couleur principale
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
                color: const Color(0xFFE6EEFA),  // Couleur secondaire
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        offre.titre,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFF214D4F),  // Texte en vert foncé
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Statut: ${offre.statut}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Date Fin: ${offre.dateFin.toLocal()}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (AuthController.instance.user?.role == 'joueur')
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () async {
                              await _offreController.postulerOffre(offre);
                            },
                            icon: const Icon(Icons.check_circle_outline, size: 18),
                            label: const Text('Postuler'),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF214D4F),  // Couleur principale
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                          ),
                        ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            Get.to(() => OffreDetailsScreen(offre: offre));
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF214D4F),
                          ),
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
