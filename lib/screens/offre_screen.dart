import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controller/offre_controller.dart';
import 'offre_details_screen.dart'; // Un écran pour les détails de l'offre (à créer)

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
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              _offreController.filtrerOffresParStatut(value); // Filtrer par statut
            },
            itemBuilder: (context) {
              return ['ouverte', 'fermée', 'en cours']
                  .map((statut) => PopupMenuItem<String>(
                        value: statut,
                        child: Text(statut),
                      ))
                  .toList();
            },
          ),
        ],
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

            return ListTile(
              title: Text(offre.titre),
              subtitle: Text('Statut: ${offre.statut}'),
              trailing: Text('Date Fin: ${offre.dateFin.toLocal()}'),
              onTap: () {
                Get.to(() => OffreDetailsScreen(offre: offre)); // Afficher les détails
              },
            );
          },
        );
      }),
    );
  }
}
