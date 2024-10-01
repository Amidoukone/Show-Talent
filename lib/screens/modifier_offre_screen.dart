import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controller/offre_controller.dart';
import '../models/offre.dart';
import 'offre_details_screen.dart';  // Import pour redirection

class ModifierOffreScreen extends StatefulWidget {
  final Offre offre;
  const ModifierOffreScreen({required this.offre, super.key});

  @override
  _ModifierOffreScreenState createState() => _ModifierOffreScreenState();
}

class _ModifierOffreScreenState extends State<ModifierOffreScreen> {
  final TextEditingController titreController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  DateTime? dateDebut;
  DateTime? dateFin;

  @override
  void initState() {
    super.initState();
    titreController.text = widget.offre.titre;
    descriptionController.text = widget.offre.description;
    dateDebut = widget.offre.dateDebut;
    dateFin = widget.offre.dateFin;
  }

  @override
  void dispose() {
    titreController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Modifier une Offre')),
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
              onPressed: () async {
                if (titreController.text.isEmpty || descriptionController.text.isEmpty) {
                  Get.snackbar('Erreur', 'Veuillez remplir tous les champs');
                  return;
                }

                try {
                  await OffreController.instance.modifierOffre(
                    widget.offre.id,
                    titreController.text,
                    descriptionController.text,
                    dateDebut!,
                    dateFin!,
                  );

                  Get.snackbar('Succès', 'Offre modifiée avec succès');

                  // Redirection après modification : retour à la page OffreDetailsScreen
                  Get.off(() => OffreDetailsScreen(offre: widget.offre));

                } catch (e) {
                  Get.snackbar('Erreur', 'Erreur lors de la modification de l\'offre');
                }
              },
              child: const Text('Modifier l\'Offre'),
            ),
          ],
        ),
      ),
    );
  }
}
