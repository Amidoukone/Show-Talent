import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/controller/offre_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/models/offre.dart';
import 'package:intl/intl.dart';
import 'package:adfoot/screens/offre_screen.dart';

class OffreFormScreen extends StatefulWidget {
  const OffreFormScreen({super.key});

  @override
  _OffreFormScreenState createState() => _OffreFormScreenState();
}

class _OffreFormScreenState extends State<OffreFormScreen> {
  final OffreController offreController = Get.find();
  final UserController userController = Get.find<UserController>();
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _titreController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  DateTime? _dateDebut;
  DateTime? _dateFin;
  late bool isEditing;
  late Offre? editingOffre;

  @override
  void initState() {
    super.initState();
    isEditing = Get.arguments != null;

    if (isEditing) {
      editingOffre = Get.arguments as Offre;
      _titreController.text = editingOffre!.titre;
      _descriptionController.text = editingOffre!.description;
      _dateDebut = editingOffre!.dateDebut;
      _dateFin = editingOffre!.dateFin;
    } else {
      editingOffre = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Text(
          isEditing ? 'Modifier l\'offre' : 'Nouvelle offre',
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Get.back(),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle('Informations générales'),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _titreController,
                  decoration: _buildInputDecoration(
                    'Titre de l\'offre',
                    'Entrez le titre de l\'offre',
                    Icons.work_outline,
                  ),
                  validator: (value) =>
                      value!.isEmpty ? 'Le titre est requis' : null,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _descriptionController,
                  decoration: _buildInputDecoration(
                    'Description',
                    'Décrivez l\'offre en détail',
                    Icons.description_outlined,
                  ),
                  maxLines: 5,
                  validator: (value) =>
                      value!.isEmpty ? 'La description est requise' : null,
                ),
                const SizedBox(height: 24),
                _buildSectionTitle('Période'),
                const SizedBox(height: 16),
                _buildDatePicker('Date de début', _dateDebut, (picked) {
                  setState(() => _dateDebut = picked);
                }, isStart: true),
                const SizedBox(height: 16),
                _buildDatePicker('Date de fin', _dateFin, (picked) {
                  setState(() => _dateFin = picked);
                }),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _submitForm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color.fromARGB(255, 55, 144, 33),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      isEditing ? 'Mettre à jour' : 'Publier l\'offre',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  InputDecoration _buildInputDecoration(
      String label, String hint, IconData icon) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: Colors.grey),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.grey),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.grey),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.teal),
      ),
      filled: true,
      fillColor: Colors.grey[50],
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
            : _dateDebut != null
                ? _dateDebut!
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
        if (pickedDate != null) {
          onDateSelected(pickedDate);
        }
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
            Text(label,
                style: const TextStyle(fontSize: 16, color: Colors.black54)),
            Text(
              date != null
                  ? DateFormat('dd MMM yyyy').format(date)
                  : 'Choisir une date',
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

  void _submitForm() {
    if (_formKey.currentState!.validate() &&
        _dateDebut != null &&
        _dateFin != null) {
      if (_dateDebut!.isAfter(_dateFin!)) {
        _showSnackbar('Erreur', 'La date de début doit précéder la date de fin',
            Colors.red);
        return;
      }

      final currentUser = userController.user!;

      final offre = Offre(
        id: isEditing ? editingOffre!.id : DateTime.now().toIso8601String(),
        titre: _titreController.text,
        description: _descriptionController.text,
        dateDebut: _dateDebut!,
        dateFin: _dateFin!,
        recruteur: currentUser,
        candidats: isEditing ? editingOffre!.candidats : [],
        statut: 'ouverte',
        dateCreation: isEditing
            ? editingOffre!.dateCreation
            : DateTime.now(),
      );

      if (isEditing) {
        offreController.modifierOffre(offre, currentUser);
      } else {
        offreController.publierOffre(offre, currentUser);
      }

      _showSnackbar(
        'Succès',
        isEditing
            ? 'Offre mise à jour avec succès.'
            : 'Offre publiée avec succès.',
        Colors.green,
      );
      Get.off(() => OffreScreen());
    }
  }

  void _showSnackbar(String title, String message, Color color) {
    Get.snackbar(
      title,
      message,
      backgroundColor: color.withOpacity(0.2),
      colorText: Colors.black87,
      snackPosition: SnackPosition.TOP,
    );
  }

  @override
  void dispose() {
    _titreController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}
