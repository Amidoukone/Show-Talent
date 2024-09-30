import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controller/offre_controller.dart';

class PublierOffreScreen extends StatefulWidget {
  const PublierOffreScreen({super.key});

  @override
  _PublierOffreScreenState createState() => _PublierOffreScreenState();
}

class _PublierOffreScreenState extends State<PublierOffreScreen> {
  final TextEditingController titreController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  final DateTime dateDebut = DateTime.now();
  final DateTime dateFin = DateTime.now().add(const Duration(days: 30));

  bool isLoading = false; // Indicateur de chargement

  @override
  void dispose() {
    titreController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Publier une Offre')),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            TextField(
              controller: titreController,
              decoration: const InputDecoration(labelText: 'Titre de l\'offre'),
            ),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isLoading ? null : () async {
                if (titreController.text.isEmpty || descriptionController.text.isEmpty) {
                  Get.snackbar('Erreur', 'Veuillez remplir tous les champs');
                  return;
                }

                setState(() {
                  isLoading = true; // Début du chargement
                });

                try {
                  await OffreController.instance.publierOffre(
                    titreController.text,
                    descriptionController.text,
                    dateDebut,
                    dateFin,
                  );

                  // Message de succès
                  Get.snackbar('Succès', 'Offre publiée avec succès');

                  // Effacer les champs après la publication
                  titreController.clear();
                  descriptionController.clear();
                } catch (e) {
                  // Gérer les erreurs
                  Get.snackbar('Erreur', 'Erreur lors de la publication de l\'offre');
                } finally {
                  setState(() {
                    isLoading = false; // Fin du chargement
                  });
                }
              },
              child: isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Publier'),
            ),
          ],
        ),
      ),
    );
  }
}
