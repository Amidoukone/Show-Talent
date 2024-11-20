import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/offre_controller.dart';
import 'package:show_talent/controller/user_controller.dart';
import 'package:show_talent/models/offre.dart';
import 'package:intl/intl.dart';

class OffreFormScreen extends StatefulWidget {
  const OffreFormScreen({Key? key}) : super(key: key);

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

  @override
  void initState() {
    super.initState();
    if (Get.arguments != null) {
      final offre = Get.arguments as Offre;
      _titreController.text = offre.titre;
      _descriptionController.text = offre.description;
      _dateDebut = offre.dateDebut;
      _dateFin = offre.dateFin;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = Get.arguments != null;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Text(
          isEditing ? 'Modifier l\'offre' : 'Nouvelle offre',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Get.back(),
        ),
      ),
      body: SingleChildScrollView(
        child: Container(
          padding: EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle('Informations générales'),
                SizedBox(height: 16),
                TextFormField(
                  controller: _titreController,
                  decoration: _buildInputDecoration(
                    'Titre de l\'offre',
                    'Entrez le titre de l\'offre',
                    Icons.work_outline,
                  ),
                  validator: (value) => value!.isEmpty ? 'Le titre est requis' : null,
                ),
                SizedBox(height: 20),
                TextFormField(
                  controller: _descriptionController,
                  decoration: _buildInputDecoration(
                    'Description',
                    'Décrivez l\'offre en détail',
                    Icons.description_outlined,
                  ),
                  maxLines: 5,
                  validator: (value) => value!.isEmpty ? 'La description est requise' : null,
                ),
                SizedBox(height: 24),
                _buildSectionTitle('Période'),
                SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildDateButton(
                        'Date de début',
                        _dateDebut,
                        () => _selectDate(context, true),
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: _buildDateButton(
                        'Date de fin',
                        _dateFin,
                        () => _selectDate(context, false),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 32),
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
                      style: TextStyle(
                        fontSize: 16,
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
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  InputDecoration _buildInputDecoration(String label, String hint, IconData icon) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: Colors.grey),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.teal),
      ),
      filled: true,
      fillColor: Colors.grey[50],
    );
  }

  Widget _buildDateButton(String label, DateTime? date, VoidCallback onPress) {
    return InkWell(
      onTap: onPress,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
            SizedBox(height: 4),
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
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.teal,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
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
        Get.snackbar(
          'Erreur',
          'La date de début doit être avant la date de fin',
          backgroundColor: Colors.red[100],
          colorText: Colors.red[900],
          snackPosition: SnackPosition.TOP,
        );
        return;
      }

      final currentUser = userController.user!;
      final offre = Offre(
        id: Get.arguments?.id ?? DateTime.now().toIso8601String(),
        titre: _titreController.text,
        description: _descriptionController.text,
        dateDebut: _dateDebut!,
        dateFin: _dateFin!,
        recruteur: currentUser,
        candidats: Get.arguments?.candidats ?? [],
        statut: 'ouverte',
      );

      if (Get.arguments != null) {
        offreController.modifierOffre(offre, currentUser);
      } else {
        offreController.publierOffre(offre, currentUser);
      }

      Get.back();
      Get.snackbar(
        'Succès',
        Get.arguments != null ? 'Offre mise à jour' : 'Offre publiée',
        backgroundColor: Colors.green[100],
        colorText: Colors.green[900],
        snackPosition: SnackPosition.TOP,
      );
    }
  }

  @override
  void dispose() {
    _titreController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}