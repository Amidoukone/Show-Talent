import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/controller/event_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/models/event.dart';
import 'package:adfoot/models/user.dart';
import 'package:intl/intl.dart';

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
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(
          widget.event != null ? 'Modifier l\'événement' : 'Créer un événement',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF214D4F),
        centerTitle: true,
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                  if (endDate != null && endDate!.isBefore(startDate!)) {
                    endDate = null; // reset si fin < début
                  }
                });
              }, isStart: true),
              const SizedBox(height: 10),
              _buildDatePicker('Date de fin', endDate, (newDate) {
                setState(() {
                  endDate = newDate;
                });
              }),
              const SizedBox(height: 40),
              Center(
                child: ElevatedButton(
                  onPressed: _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF214D4F),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: Text(widget.event != null ? 'Modifier' : 'Créer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleSubmit() {
    if (titleController.text.isEmpty ||
        descriptionController.text.isEmpty ||
        locationController.text.isEmpty ||
        startDate == null ||
        endDate == null) {
      Get.snackbar('Erreur', 'Veuillez remplir tous les champs',
          backgroundColor: Colors.red.shade100, colorText: Colors.red);
      return;
    }

    AppUser currentUser = Get.find<UserController>().user!;

    if (widget.event != null) {
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
        createdAt: widget.event!.createdAt,
      );
      eventController.updateEvent(updatedEvent, currentUser);
    } else {
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
        createdAt: DateTime.now(),
      );
      eventController.createEvent(newEvent, currentUser);
    }

    Navigator.pop(context, true);
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
      textInputAction: TextInputAction.next,
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

  Widget _buildDatePicker(
    String label,
    DateTime? date,
    Function(DateTime) onDateSelected, {
    bool isStart = false,
  }) {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final firstDate = isStart
            ? now
            : startDate != null
                ? startDate!
                : now;

        DateTime? pickedDate = await showDatePicker(
          context: context,
          initialDate: date ?? firstDate,
          firstDate: firstDate,
          lastDate: DateTime(2100),
          builder: (context, child) {
            return Theme(
              data: ThemeData.light().copyWith(
                colorScheme: const ColorScheme.light(
                  primary: Color(0xFF214D4F),
                  onPrimary: Colors.white,
                  surface: Colors.white,
                  onSurface: Colors.black,
                ),
                dialogBackgroundColor: Colors.white,
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
          border: Border.all(color: const Color(0xFF214D4F)),
          borderRadius: BorderRadius.circular(20),
          color: Colors.grey.shade100,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 16, color: Colors.black54)),
            Text(
              date != null ? DateFormat('dd MMM yyyy').format(date) : 'Choisir une date',
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF214D4F),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
