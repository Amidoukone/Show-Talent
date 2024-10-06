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

  bool isLoading = false;

  @override
  void dispose() {
    titreController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Publier une Offre'),
        backgroundColor: const Color(0xFF214D4F),  // Couleur principale
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            TextField(
              controller: titreController,
              decoration: const InputDecoration(
                labelText: 'Titre de l\'offre',
                filled: true,
                fillColor: Color(0xFFE6EEFA),  // Couleur secondaire
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                filled: true,
                fillColor: Color(0xFFE6EEFA),  // Couleur secondaire
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isLoading ? null : () async {
                if (titreController.text.isEmpty || descriptionController.text.isEmpty) {
                  Get.snackbar('Erreur', 'Veuillez remplir tous les champs');
                  return;
                }

                setState(() {
                  isLoading = true;
                });

                try {
                  await OffreController.instance.publierOffre(
                    titreController.text,
                    descriptionController.text,
                    dateDebut,
                    dateFin,
                  );

                  Get.snackbar('Succès', 'Offre publiée avec succès');
                  titreController.clear();
                  descriptionController.clear();
                } catch (e) {
                  Get.snackbar('Erreur', 'Erreur lors de la publication');
                } finally {
                  setState(() {
                    isLoading = false;
                  });
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF214D4F),
                minimumSize: const Size(double.infinity, 50),
              ),
              child: isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                      'Publier',
                      style: TextStyle(color: Colors.white), 
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
