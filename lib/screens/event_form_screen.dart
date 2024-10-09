import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/event_controller.dart';
import 'package:show_talent/controller/user_controller.dart';
import 'package:show_talent/models/event.dart';
import 'package:show_talent/models/user.dart';
import 'package:intl/intl.dart'; // Pour formater les dates

class EventFormScreen extends StatefulWidget {
  final Event? event;

  const EventFormScreen({super.key, this.event});

  @override
  _EventFormScreenState createState() => _EventFormScreenState();
}

class _EventFormScreenState extends State<EventFormScreen> {
  final EventController eventController = Get.put(EventController());
  final TextEditingController titleController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController locationController = TextEditingController();
  DateTime? startDate;
  DateTime? endDate;

  @override
  void initState() {
    super.initState();
    if (widget.event != null) {
      titleController.text = widget.event!.titre;
      descriptionController.text = widget.event!.description;
      locationController.text = widget.event!.lieu;
      startDate = widget.event!.dateDebut;
      endDate = widget.event!.dateFin;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.event != null ? 'Modifier l\'événement' : 'Créer un événement'),
        backgroundColor: const Color(0xFF214D4F), // Couleur de la barre supérieure
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildTextField(
              controller: titleController,
              labelText: 'Titre',
            ),
            const SizedBox(height: 20), // Espacement ajouté entre les champs
            _buildTextField(
              controller: descriptionController,
              labelText: 'Description',
              maxLines: 3, // Permet d'avoir un champ plus grand pour la description
            ),
            const SizedBox(height: 20), // Espacement ajouté
            _buildTextField(
              controller: locationController,
              labelText: 'Lieu',
            ),
            const SizedBox(height: 20), // Espacement ajouté avant le date picker
            _buildDatePicker('Date de début', startDate, (newDate) {
              setState(() {
                startDate = newDate;
              });
            }),
            const SizedBox(height: 20),
            _buildDatePicker('Date de fin', endDate, (newDate) {
              setState(() {
                endDate = newDate;
              });
            }),
            const SizedBox(height: 40), // Plus d'espacement avant le bouton
            ElevatedButton(
              onPressed: () {
                if (widget.event != null) {
                  Event updatedEvent = Event(
                    id: widget.event!.id,
                    titre: titleController.text,
                    description: descriptionController.text,
                    dateDebut: startDate ?? DateTime.now(),
                    dateFin: endDate ?? DateTime.now().add(const Duration(hours: 2)),
                    organisateur: widget.event!.organisateur,
                    participants: widget.event!.participants,
                    statut: 'à venir',
                    lieu: locationController.text,
                    estPublic: widget.event!.estPublic, // Garder l'état initial
                  );
                  eventController.updateEvent(updatedEvent);
                } else {
                  AppUser currentUser = Get.find<UserController>().user!;
                  Event newEvent = Event(
                    id: FirebaseFirestore.instance.collection('events').doc().id,
                    titre: titleController.text,
                    description: descriptionController.text,
                    dateDebut: startDate ?? DateTime.now(),
                    dateFin: endDate ?? DateTime.now().add(const Duration(hours: 2)),
                    organisateur: currentUser,
                    participants: [],
                    statut: 'à venir',
                    lieu: locationController.text,
                    estPublic: true, // Valeur par défaut
                  );
                  eventController.createEvent(newEvent);
                }
                Get.back();
              },
              child: Text(widget.event != null ? 'Modifier' : 'Créer'),
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white, backgroundColor: const Color(0xFF214D4F), // Texte en blanc
                padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 12.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Méthode utilitaire pour construire les champs de texte
  Widget _buildTextField({
    required TextEditingController controller,
    required String labelText,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: labelText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 15.0, horizontal: 20.0),
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
