import 'package:adfoot/screens/event_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/controller/event_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/models/event.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/screens/event_detail_screen.dart';
import 'package:adfoot/screens/profile_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';

class EventListScreen extends StatelessWidget {
  final EventController eventController = Get.put(EventController());
  final UserController userController = Get.find<UserController>();

  EventListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppUser currentUser = userController.user!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Liste des événements'),
        backgroundColor: const Color(0xFF214D4F),
        centerTitle: true,
      ),
      body: Obx(() {
        if (eventController.events.isEmpty) {
          return const Center(
            child: Text(
              'Aucun événement disponible pour l\'instant.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          );
        } else {
          return ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: eventController.events.length,
            itemBuilder: (context, index) {
              Event event = eventController.events[index];
              AppUser organiser = event.organisateur;
              bool isParticipant = event.participants.any((p) => p.uid == currentUser.uid);
              bool isOrganisateur = currentUser.uid == organiser.uid;

              return AnimatedEventCard(
                delay: Duration(milliseconds: 100 * index),
                child: _buildEventCard(context, event, organiser, isParticipant, isOrganisateur, currentUser),
              );
            },
          );
        }
      }),
      floatingActionButton: _buildFloatingActionButton(currentUser),
    );
  }

  bool _isValidPhotoUrl(String? url) {
    if (url == null) return false;
    url = url.trim();
    if (url.isEmpty) return false;
    if (!(url.startsWith('http://') || url.startsWith('https://'))) return false;
    return true;
  }

  Widget _buildEventCard(BuildContext context, Event event, AppUser organiser, bool isParticipant, bool isOrganisateur, AppUser currentUser) {
    return Card(
      color: Colors.white,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOrganiserSection(context, organiser),
            const SizedBox(height: 10),
            _buildEventDetails(event),
            const SizedBox(height: 5),
            Text(
              '${event.participants.length} joueur(s) inscrit(s)',
              style: const TextStyle(color: Colors.black87, fontSize: 14),
            ),
            const SizedBox(height: 20),
            isOrganisateur
                ? _buildOrganisateurActions(context, event)
                : _buildParticipantActions(context, event, currentUser, isParticipant),
          ],
        ),
      ),
    );
  }

  Widget _buildOrganiserSection(BuildContext context, AppUser organiser) {
    return Row(
      children: [
        GestureDetector(
          onTap: () {
            Get.to(() => ProfileScreen(uid: organiser.uid, isReadOnly: true));
          },
          child: _isValidPhotoUrl(organiser.photoProfil)
              ? CircleAvatar(
                  radius: 25,
                  backgroundImage: CachedNetworkImageProvider(organiser.photoProfil.trim()),
                )
              : CircleAvatar(
                  radius: 25,
                  backgroundColor: Colors.grey.shade300,
                  child: const Icon(Icons.person, size: 24, color: Colors.white70),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                organiser.nom.isNotEmpty ? organiser.nom : 'Utilisateur inconnu',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                organiser.role == 'club' ? 'Club' : 'Recruteur',
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEventDetails(Event event) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          event.titre,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 5),
        Text(
          'Lieu: ${event.lieu}',
          style: const TextStyle(color: Colors.grey, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 5),
        Text(
          'Statut: ${event.statut}',
          style: const TextStyle(color: Colors.grey, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildOrganisateurActions(BuildContext context, Event event) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        TextButton(
          onPressed: () {
            _markAsCompleted(context, event);
          },
          child: const Text(
            'Terminer',
            style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
          ),
        ),
        TextButton(
          onPressed: () {
            Get.to(() => EventDetailsScreen(event: event));
          },
          child: const Text(
            'Voir les détails',
            style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
          ),
        ),
        TextButton(
          onPressed: () {
            _confirmDeleteEvent(context, event);
          },
          child: const Text(
            'Supprimer',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildParticipantActions(BuildContext context, Event event, AppUser currentUser, bool isParticipant) {
    bool isDisabled = event.statut == 'Terminé' || event.statut == 'fermé';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        ElevatedButton.icon(
          onPressed: (!isParticipant && !isDisabled)
              ? () => eventController.registerToEvent(event.id, currentUser)
              : null,
          icon: const Icon(Icons.event_available, color: Colors.white),
          label: const Text(
            'S\'inscrire',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          style: ElevatedButton.styleFrom(
            elevation: 3,
            padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 12),
            backgroundColor: (!isParticipant && !isDisabled)
                ? const Color(0xFF2E7D32)
                : Colors.grey,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
        ),
        if (isParticipant && !isDisabled)
          OutlinedButton.icon(
            onPressed: () {
              _confirmUnregisterEvent(context, event, currentUser);
            },
            icon: const Icon(Icons.cancel, color: Colors.red),
            label: const Text(
              'Se désinscrire',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: () {
              Get.to(() => EventDetailsScreen(event: event));
            },
            icon: const Icon(Icons.info_outline, color: Color(0xFF2E7D32)),
            label: const Text('Voir les détails', style: TextStyle(color: Color(0xFF2E7D32))),
          ),
      ],
    );
  }

  FloatingActionButton? _buildFloatingActionButton(AppUser currentUser) {
    if (currentUser.role == 'club' || currentUser.role == 'recruteur') {
      return FloatingActionButton(
        onPressed: () {
          Get.to(() => EventFormScreen());
        },
        backgroundColor: const Color(0xFF214D4F),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      );
    }
    return null;
  }

  void _confirmDeleteEvent(BuildContext context, Event event) {
    Get.dialog(
      AlertDialog(
        title: const Text('Supprimer'),
        content: const Text('Voulez-vous vraiment supprimer cet événement ?'),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await eventController.deleteEvent(event.id, userController.user!);
              Get.snackbar('Succès', 'Événement supprimé avec succès.', backgroundColor: Colors.green.shade100, colorText: Colors.black87);
            },
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmUnregisterEvent(BuildContext context, Event event, AppUser currentUser) {
    Get.dialog(
      AlertDialog(
        title: const Text('Se désinscrire'),
        content: const Text('Voulez-vous vraiment vous désinscrire de cet événement ?'),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await eventController.unregisterFromEvent(event.id, currentUser);
            },
            child: const Text('Confirmer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _markAsCompleted(BuildContext context, Event event) {
    event.statut = 'Terminé';
    eventController.updateEvent(event, userController.user!);
    Get.snackbar('Succès', 'Événement marqué comme terminé.', backgroundColor: Colors.orange.shade100, colorText: Colors.black87);
  }
}

class AnimatedEventCard extends StatefulWidget {
  final Widget child;
  final Duration delay;

  const AnimatedEventCard({required this.child, required this.delay, super.key});

  @override
  State<AnimatedEventCard> createState() => _AnimatedEventCardState();
}

class _AnimatedEventCardState extends State<AnimatedEventCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _opacity = Tween<double>(begin: 0, end: 1).animate(_controller);
    _offset = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _offset,
        child: widget.child,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
