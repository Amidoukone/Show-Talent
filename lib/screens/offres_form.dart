import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/controller/offre_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/models/offre.dart';
import 'package:intl/intl.dart';
import 'package:adfoot/screens/offre_screen.dart';
import 'package:adfoot/theme/ad_colors.dart';

class OffreFormScreen extends StatefulWidget {
  const OffreFormScreen({super.key});

  @override
  State<OffreFormScreen> createState() => OffreFormScreenState();
}

/// Classe publique (évite l'erreur "private type in public API")
class OffreFormScreenState extends State<OffreFormScreen> {
  final OffreController offreController = Get.find();
  final UserController userController = Get.find<UserController>();
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _titreController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _localisationController = TextEditingController();
  final TextEditingController _remunerationController = TextEditingController();
  final TextEditingController _niveauController = TextEditingController();
  final TextEditingController _posteController = TextEditingController();
  final TextEditingController _pieceJointeController = TextEditingController();

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
      _localisationController.text = editingOffre!.localisation ?? '';
      _remunerationController.text = editingOffre!.remuneration ?? '';
      _niveauController.text = editingOffre!.niveau ?? '';
      _posteController.text = editingOffre!.posteRecherche ?? '';
      _pieceJointeController.text = editingOffre!.pieceJointeUrl ?? '';
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
                      value == null || value.isEmpty ? 'Le titre est requis' : null,
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
                      value == null || value.isEmpty ? 'La description est requise' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _posteController,
                  decoration: _buildInputDecoration(
                    'Poste recherché',
                    'Ex: Attaquant, Milieu',
                    Icons.sports_soccer,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _niveauController,
                  decoration: _buildInputDecoration(
                    'Niveau / Section',
                    'Ex: U19, Sénior, Pro',
                    Icons.leaderboard_outlined,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _localisationController,
                  decoration: _buildInputDecoration(
                    'Localisation',
                    'Ville, Pays ou région',
                    Icons.place_outlined,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _remunerationController,
                  decoration: _buildInputDecoration(
                    'Rémunération (optionnel)',
                    'Ex: 2k-3k €/mois',
                    Icons.payments_outlined,
                  ),
                ),
                const SizedBox(height: 24),
                _buildSectionTitle('Période'),
                const SizedBox(height: 16),
                _buildDatePicker(
                  'Date de début',
                  _dateDebut,
                  (picked) => setState(() => _dateDebut = picked),
                  isStart: true,
                ),
                const SizedBox(height: 16),
                _buildDatePicker(
                  'Date de fin',
                  _dateFin,
                  (picked) => setState(() => _dateFin = picked),
                ),
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
    String label,
    String hint,
    IconData icon,
  ) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: Colors.grey),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
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

        final initialDate = date ?? firstDate;

        final pickedDate = await showDatePicker(
          context: context,
          initialDate: initialDate,
          firstDate: firstDate,
          lastDate: DateTime(2100),
        );

        if (pickedDate != null) {
          onDateSelected(pickedDate);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
        decoration: BoxDecoration(
          border: Border.all(color: AdColors.divider),
          borderRadius: BorderRadius.circular(20),
          color: AdColors.surfaceCard,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 16,
                    color: AdColors.onSurfaceMuted,
                    fontWeight: FontWeight.w600)),
            Text(
              date != null
                  ? DateFormat('dd MMM yyyy').format(date)
                  : 'Choisir une date',
              style: const TextStyle(
                fontSize: 16,
                color: AdColors.brand,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submitForm() {
    if (!_formKey.currentState!.validate() ||
        _dateDebut == null ||
        _dateFin == null) {
      return;
    }

    if (_dateDebut!.isAfter(_dateFin!)) {
      _showSnackbar(
        'Erreur',
        'La date de début doit précéder la date de fin',
        Colors.red,
      );
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
      dateCreation:
          isEditing ? editingOffre!.dateCreation : DateTime.now(),
      localisation:
          _localisationController.text.trim().isEmpty ? null : _localisationController.text.trim(),
      remuneration:
          _remunerationController.text.trim().isEmpty ? null : _remunerationController.text.trim(),
      niveau:
          _niveauController.text.trim().isEmpty ? null : _niveauController.text.trim(),
      posteRecherche:
          _posteController.text.trim().isEmpty ? null : _posteController.text.trim(),
      pieceJointeUrl:
          _pieceJointeController.text.trim().isEmpty ? null : _pieceJointeController.text.trim(),
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

  void _showSnackbar(String title, String message, Color color) {
    Get.snackbar(
      title,
      message,
      backgroundColor: color.withValues(alpha: 0.2),
      colorText: Colors.black87,
      snackPosition: SnackPosition.TOP,
    );
  }

  @override
  void dispose() {
    _titreController.dispose();
    _descriptionController.dispose();
    _localisationController.dispose();
    _remunerationController.dispose();
    _niveauController.dispose();
    _posteController.dispose();
    _pieceJointeController.dispose();
    super.dispose();
  }
}
