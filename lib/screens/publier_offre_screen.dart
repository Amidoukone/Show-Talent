import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart'; // Pour formater les dates
import 'package:show_talent/controller/offre_controller.dart';
import 'package:show_talent/models/offre.dart';

class PublierOffreScreen extends StatefulWidget {
  final bool isEditing;
  final Offre? offre;

  const PublierOffreScreen({this.isEditing = false, this.offre, super.key});

  @override
  _PublierOffreScreenState createState() => _PublierOffreScreenState();
}

class _PublierOffreScreenState extends State<PublierOffreScreen> {
  final OffreController _offreController = Get.find<OffreController>();

  final TextEditingController titreController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  DateTime? dateDebut;
  DateTime? dateFin;
  
  @override
  void initState() {
    super.initState();
    if (widget.isEditing && widget.offre != null) {
      titreController.text = widget.offre!.titre;
      descriptionController.text = widget.offre!.description;
      dateDebut = widget.offre!.dateDebut;
      dateFin = widget.offre!.dateFin;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Modifier l\'offre' : 'Publier une offre'),
        backgroundColor: const Color(0xFF214D4F),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: titreController,
              decoration: const InputDecoration(labelText: 'Titre de l\'offre'),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(labelText: 'Description de l\'offre'),
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            _buildDatePicker('Date de début', dateDebut, (newDate) {
              setState(() {
                dateDebut = newDate;
              });
            }),
            const SizedBox(height: 20),
            _buildDatePicker('Date de fin', dateFin, (newDate) {
              setState(() {
                dateFin = newDate;
              });
            }),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                if (widget.isEditing && widget.offre != null) {
                  _offreController.modifierOffre(
                    widget.offre!.id,
                    titreController.text,
                    descriptionController.text,
                    dateDebut ?? DateTime.now(),
                    dateFin ?? DateTime.now(),
                  );
                } else {
                  _offreController.publierOffre(
                    titreController.text,
                    descriptionController.text,
                    dateDebut ?? DateTime.now(),
                    dateFin ?? DateTime.now(),
                  );
                }
                Get.back();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF214D4F), // Fond vert
                foregroundColor: Colors.white, // Texte blanc
              ),
              child: Text(widget.isEditing ? 'Modifier' : 'Publier'),
            ),
          ],
        ),
      ),
    );
  }

  // Widget pour afficher le DatePicker
  Widget _buildDatePicker(String label, DateTime? date, Function(DateTime) onDateSelected) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        TextButton(
          onPressed: () async {
            DateTime? pickedDate = await showDatePicker(
              context: context,
              initialDate: date ?? DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (pickedDate != null) {
              onDateSelected(pickedDate);
            }
          },
          child: Text(
            date != null ? DateFormat('yyyy-MM-dd').format(date) : 'Choisir la date',
            style: const TextStyle(color: Colors.blue),
          ),
        ),
      ],
    );
  }
}
