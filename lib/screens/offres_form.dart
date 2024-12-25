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

  @override
  void initState() {
    super.initState();

    // Définir si c'est une modification ou une création
    isEditing = Get.arguments != null;

    // Charger les données si modification
    if (isEditing) {
      final offre = Get.arguments as Offre;
      _titreController.text = offre.titre;
      _descriptionController.text = offre.description;
      _dateDebut = offre.dateDebut;
      _dateFin = offre.dateFin;
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
                Row(
                  children: [
                    Expanded(
                      child: _buildDateButton(
                        'Date de début',
                        _dateDebut,
                        () => _selectDate(context, true),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildDateButton(
                        'Date de fin',
                        _dateFin,
                        () => _selectDate(context, false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _submitForm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
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

  Widget _buildDateButton(String label, DateTime? date, VoidCallback onPress) {
    return InkWell(
      onTap: onPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(12),
          color: Colors.grey[50],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              date == null
                  ? 'Sélectionner'
                  : DateFormat('dd/MM/yyyy').format(date),
              style: TextStyle(
                fontSize: 16,
                color: date == null ? Colors.grey : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _dateDebut = picked;
        } else {
          _dateFin = picked;
        }
      });
    }
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
        id: isEditing
            ? (Get.arguments as Offre).id
            : DateTime.now().toIso8601String(),
        titre: _titreController.text,
        description: _descriptionController.text,
        dateDebut: _dateDebut!,
        dateFin: _dateFin!,
        recruteur: currentUser,
        candidats: isEditing ? (Get.arguments as Offre).candidats : [],
        statut: 'ouverte',
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
