import 'package:adfoot/controller/event_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/models/action_response.dart';
import 'package:adfoot/models/event.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/widgets/ad_feedback.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class EventFormScreen extends StatefulWidget {
  final Event? event;

  const EventFormScreen({super.key, this.event});

  @override
  State<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends State<EventFormScreen> {
  final EventController eventController = Get.find<EventController>();

  final TextEditingController titleController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController locationController = TextEditingController();
  final TextEditingController capacityController = TextEditingController();
  final TextEditingController tagsController = TextEditingController();
  final TextEditingController streamingController = TextEditingController();
  final TextEditingController flyerController = TextEditingController();

  DateTime? startDate;
  DateTime? endDate;

  bool estPublic = true;
  String statut = 'ouvert';
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();

    if (widget.event != null) {
      titleController.text = widget.event!.titre;
      descriptionController.text = widget.event!.description;
      locationController.text = widget.event!.lieu;
      capacityController.text = widget.event!.capaciteMax != null
          ? widget.event!.capaciteMax.toString()
          : '';
      tagsController.text = widget.event!.tags?.join(', ') ?? '';
      streamingController.text = widget.event!.streamingUrl ?? '';
      flyerController.text = widget.event!.flyerUrl ?? '';
      startDate = widget.event!.dateDebut;
      endDate = widget.event!.dateFin;
      estPublic = widget.event!.estPublic;
      statut = Event.normalizeStatus(widget.event!.statut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(
          widget.event != null
              ? 'Modifier l\'événement'
              : 'Créer un événement',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        centerTitle: true,
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(16),
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
              _buildTextField(
                controller: capacityController,
                labelText: 'Capacité maximale (optionnel)',
                hintText: 'Ex: 50',
                icon: Icons.groups,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 20),
              _buildTextField(
                controller: tagsController,
                labelText: 'Tags / Catégories (séparés par des virgules)',
                hintText: 'Ex: U19, Detection, Futsal',
                icon: Icons.sell_outlined,
              ),
              const SizedBox(height: 20),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Événement public'),
                subtitle:
                    const Text('Désactivez pour rendre l\'événement privé'),
                value: estPublic,
                onChanged: (v) => setState(() => estPublic = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: statut,
                decoration: const InputDecoration(
                  labelText: 'Statut',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'brouillon', child: Text('Brouillon')),
                  DropdownMenuItem(value: 'ouvert', child: Text('Ouvert')),
                  DropdownMenuItem(value: 'ferme', child: Text('Ferme')),
                  DropdownMenuItem(value: 'archive', child: Text('Archive')),
                ],
                onChanged: (v) => setState(() => statut = v ?? 'ouvert'),
              ),
              const SizedBox(height: 20),
              _buildSectionTitle('Dates'),
              const SizedBox(height: 10),
              _buildDatePicker('Date de début', startDate, (newDate) {
                setState(() {
                  startDate = newDate;
                  if (endDate != null && endDate!.isBefore(startDate!)) {
                    endDate = null;
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
                  onPressed: _isSubmitting ? null : _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdColors.brand,
                    foregroundColor: AdColors.brandOn,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 40, vertical: 15),
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

  Future<void> _handleSubmit() async {
    if (_isSubmitting) return;

    if (titleController.text.trim().isEmpty ||
        descriptionController.text.trim().isEmpty ||
        locationController.text.trim().isEmpty ||
        startDate == null ||
        endDate == null) {
      AdFeedback.error(
        'Erreur',
        'Veuillez remplir tous les champs obligatoires.',
      );
      return;
    }

    if (titleController.text.trim().length > 120) {
      AdFeedback.warning(
        'Titre trop long',
        'Limitez le titre à 120 caractères.',
      );
      return;
    }

    if (endDate!.isBefore(startDate!)) {
      AdFeedback.error(
        'Erreur date',
        'La date de fin doit être après la date de début.',
      );
      return;
    }

    int? capacite;
    if (capacityController.text.trim().isNotEmpty) {
      capacite = int.tryParse(capacityController.text.trim());
      if (capacite == null || capacite <= 0) {
        AdFeedback.error(
          'Capacité invalide',
          'Entrez un nombre positif.',
        );
        return;
      }
    }

    final tags = tagsController.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    final AppUser? currentUser = Get.find<UserController>().user;
    if (currentUser == null) {
      AdFeedback.error(
        'Erreur',
        'Utilisateur introuvable. Merci de vous reconnecter.',
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      if (widget.event != null) {
        final updatedEvent = Event(
          id: widget.event!.id,
          titre: titleController.text.trim(),
          description: descriptionController.text.trim(),
          dateDebut: startDate!,
          dateFin: endDate!,
          organisateur: widget.event!.organisateur,
          participants: widget.event!.participants,
          statut: Event.normalizeStatus(statut),
          lieu: locationController.text.trim(),
          estPublic: estPublic,
          createdAt: widget.event!.createdAt,
          capaciteMax: capacite,
          tags: tags.isEmpty ? null : tags,
          streamingUrl: streamingController.text.trim().isEmpty
              ? null
              : streamingController.text.trim(),
          flyerUrl: flyerController.text.trim().isEmpty
              ? null
              : flyerController.text.trim(),
        );

        final response =
            await eventController.updateEvent(updatedEvent, currentUser);
        if (!mounted) return;

        if (!response.success) {
          if (response.toast == ToastLevel.none) {
            return;
          }
          AdFeedback.error('Erreur', response.message);
          return;
        }

        AdFeedback.success('Succès', response.message);
        Navigator.pop(context, true);
      } else {
        final newEvent = Event(
          id: eventController.newEventId(),
          titre: titleController.text.trim(),
          description: descriptionController.text.trim(),
          dateDebut: startDate!,
          dateFin: endDate!,
          organisateur: currentUser,
          participants: const [],
          statut: Event.normalizeStatus(statut),
          lieu: locationController.text.trim(),
          estPublic: estPublic,
          createdAt: DateTime.now(),
          capaciteMax: capacite,
          tags: tags.isEmpty ? null : tags,
          streamingUrl: streamingController.text.trim().isEmpty
              ? null
              : streamingController.text.trim(),
          flyerUrl: flyerController.text.trim().isEmpty
              ? null
              : flyerController.text.trim(),
          views: 0,
        );

        final response =
            await eventController.createEvent(newEvent, currentUser);
        if (!mounted) return;

        if (!response.success) {
          if (response.toast == ToastLevel.none) {
            return;
          }
          AdFeedback.error('Erreur', response.message);
          return;
        }

        AdFeedback.success('Succès', response.message);
        Navigator.pop(context, true);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AdColors.onSurface,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String labelText,
    required String hintText,
    required IconData icon,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      textInputAction: TextInputAction.next,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        prefixIcon: Icon(icon, color: AdColors.brand),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        filled: true,
        fillColor: AdColors.surfaceCard,
        contentPadding: const EdgeInsets.all(20),
      ),
    );
  }

  Widget _buildDatePicker(
    String label,
    DateTime? date,
    ValueChanged<DateTime> onDateSelected, {
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

        final initialDate = date ?? firstDate;
        final pickedDate = await showDatePicker(
          context: context,
          initialDate: initialDate,
          firstDate: firstDate,
          lastDate: DateTime(2100),
          builder: (context, child) {
            return Theme(
              data: ThemeData.dark().copyWith(
                colorScheme: const ColorScheme.dark(
                  primary: AdColors.brand,
                  onPrimary: AdColors.brandOn,
                  surface: AdColors.surfaceCard,
                  onSurface: AdColors.onSurface,
                ),
                dialogTheme: const DialogThemeData(
                  backgroundColor: AdColors.surfaceCard,
                ),
              ),
              child: child!,
            );
          },
        );

        if (pickedDate == null) return;
        onDateSelected(pickedDate);
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
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                color: AdColors.onSurfaceMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
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

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    locationController.dispose();
    capacityController.dispose();
    tagsController.dispose();
    streamingController.dispose();
    flyerController.dispose();
    super.dispose();
  }
}
