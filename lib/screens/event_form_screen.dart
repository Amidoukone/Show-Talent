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
        title: Text(
          widget.event != null ? 'Modifier l\'événement' : 'Créer un événement',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF214D4F), // Couleur de la barre supérieure
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Informations générales'),
            const SizedBox(height: 20),
            _buildTextField(
              controller: titleController,
              labelText: 'Titre',
              hintText: 'Saisissez le titre de l\'événement',
              icon: Icons.title,
            ),
            const SizedBox(height: 20),
            _buildTextField(
              controller: descriptionController,
              labelText: 'Description',
              hintText: 'Décrivez l\'événement',
              icon: Icons.description,
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            _buildTextField(
              controller: locationController,
              labelText: 'Lieu',
              hintText: 'Entrez l\'emplacement',
              icon: Icons.location_on,
            ),
            const SizedBox(height: 20),
            _buildSectionTitle('Dates'),
            const SizedBox(height: 10),
            _buildDatePicker('Date de début', startDate, (newDate) {
              setState(() {
                startDate = newDate;
              });
            }),
            const SizedBox(height: 10),
            _buildDatePicker('Date de fin', endDate, (newDate) {
              setState(() {
                endDate = newDate;
              });
            }),
            const SizedBox(height: 40),
            Center(
              child: ElevatedButton(
                onPressed: () {
                  if (titleController.text.isEmpty ||
                      descriptionController.text.isEmpty ||
                      locationController.text.isEmpty ||
                      startDate == null ||
                      endDate == null) {
                    Get.snackbar('Erreur', 'Veuillez remplir tous les champs',
                        backgroundColor: Colors.red.shade100, colorText: Colors.red);
                    return;
                  }

                  // Récupération de l'utilisateur actuel
                  AppUser currentUser = Get.find<UserController>().user!;

                  if (widget.event != null) {
                    // Mettre à jour un événement existant
                    Event updatedEvent = Event(
                      id: widget.event!.id,
                      titre: titleController.text,
                      description: descriptionController.text,
                      dateDebut: startDate!,
                      dateFin: endDate!,
                      organisateur: widget.event!.organisateur,
                      participants: widget.event!.participants,
                      statut: 'à venir',
                      lieu: locationController.text,
                      estPublic: widget.event!.estPublic,
                    );
                    eventController.updateEvent(updatedEvent, currentUser);
                  } else {
                    // Créer un nouvel événement
                    Event newEvent = Event(
                      id: FirebaseFirestore.instance.collection('events').doc().id,
                      titre: titleController.text,
                      description: descriptionController.text,
                      dateDebut: startDate!,
                      dateFin: endDate!,
                      organisateur: currentUser,
                      participants: [],
                      statut: 'à venir',
                      lieu: locationController.text,
                      estPublic: true,
                    );
                    eventController.createEvent(newEvent, currentUser);
                  }

                  // Retour à l'écran précédent après la soumission
                  Get.back();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF214D4F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                child: Text(widget.event != null ? 'Modifier' : 'Créer'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String labelText,
    required String hintText,
    required IconData icon,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        prefixIcon: Icon(icon, color: const Color(0xFF214D4F)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        filled: true,
        fillColor: Colors.grey.shade100,
        contentPadding: const EdgeInsets.all(20),
      ),
    );
  }

  Widget _buildDatePicker(String label, DateTime? date, Function(DateTime) onDateSelected) {
    return InkWell(
      onTap: () async {
        DateTime? pickedDate = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: ColorScheme.light(primary: const Color(0xFF214D4F)),
              ),
              child: child!,
            );
          },
        );
        onDateSelected(pickedDate!);
            },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(20),
          color: Colors.grey.shade100,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 16, color: Colors.black54),
            ),
            Text(
              date != null
                  ? DateFormat('dd MMM yyyy').format(date)
                  : 'Choisir une date',
              style: const TextStyle(fontSize: 16, color: Colors.black87, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
