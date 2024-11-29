import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:show_talent/models/message_converstion.dart';
import '../controller/auth_controller.dart';
import '../controller/chat_controller.dart';
import '../models/user.dart';
import 'chat_screen.dart';
import 'select_user_screen.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  _ConversationsScreenState createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  final ChatController chatController = Get.put(ChatController());
  final TextEditingController searchController = TextEditingController();
  RxString searchTerm = ''.obs;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Conversations"),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              _showSearchBar();
            },
          ),
        ],
      ),
      body: Obx(() {
        if (chatController.conversations.isEmpty) {
          return const Center(child: Text("Aucune conversation."));
        }

        // Filtrer les conversations selon le terme de recherche
        final filteredConversations = chatController.conversations.where((conversation) {
          String otherUserId = conversation.utilisateurIds.firstWhere(
            (id) => id != AuthController.instance.user?.uid,
            orElse: () => '',
          );

          final otherUser = _getOtherUser(otherUserId);
          if (otherUser != null) {
            return otherUser.nom.toLowerCase().contains(searchTerm.value.toLowerCase());
          }
          return false;
        }).toList();

        if (filteredConversations.isEmpty) {
          return const Center(child: Text("Aucune conversation trouvée."));
        }

        // Trier les conversations par `lastMessageDate`
        filteredConversations.sort((a, b) =>
            b.lastMessageDate?.compareTo(a.lastMessageDate ?? DateTime(0)) ?? 0);

        return ListView.builder(
          itemCount: filteredConversations.length,
          itemBuilder: (context, index) {
            Conversation conversation = filteredConversations[index];
            String otherUserId = conversation.utilisateurIds.firstWhere(
              (id) => id != AuthController.instance.user?.uid,
              orElse: () => '',
            );

            if (otherUserId.isEmpty) {
              return const ListTile(
                title: Text("Utilisateur inconnu"),
              );
            }

            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(otherUserId)
                  .get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const ListTile(
                    title: Text("Chargement..."),
                  );
                }

                if (!snapshot.hasData || snapshot.data == null) {
                  return const ListTile(
                    title: Text("Utilisateur inconnu"),
                  );
                }

                // Convertir les données Firestore en AppUser
                final Map<String, dynamic>? userData =
                    snapshot.data?.data() as Map<String, dynamic>?;
                if (userData == null) {
                  return const ListTile(
                    title: Text("Erreur utilisateur"),
                  );
                }

                final AppUser otherUser = AppUser.fromMap(userData);

                // Calcul du nombre de messages non lus
                final int unreadCount = conversation.unreadMessagesCount;

                return GestureDetector(
                  onLongPress: () {
                    _confirmDelete(conversation.id);
                  },
                  child: ListTile(
                    leading: CircleAvatar(
                      radius: 25,
                      backgroundImage: otherUser.photoProfil.isNotEmpty
                          ? NetworkImage(otherUser.photoProfil)
                          : null,
                      child: otherUser.photoProfil.isEmpty
                          ? Text(
                              otherUser.nom.substring(0, 1).toUpperCase(),
                              style: const TextStyle(color: Colors.black, fontSize: 18),
                            )
                          : null,
                    ),
                    title: Text(
                      otherUser.nom,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      conversation.lastMessage ?? "Aucun message",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.grey),
                    ),
                    trailing: unreadCount > 0
                        ? Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color.fromARGB(255, 13, 69, 55),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              "$unreadCount",
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          )
                        : null,
                    onTap: () async {
                      // Marquer les messages comme lus
                      if (unreadCount > 0) {
                        await chatController.markMessagesAsRead(conversation.id, AuthController.instance.user!.uid);
                      }

                      // Redirection vers l'écran de chat
                      Get.to(() => ChatScreen(
                            conversationId: conversation.id,
                            otherUser: otherUser,
                          ));
                    },
                  ),
                );
              },
            );
          },
        );
      }),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Redirige vers l'écran de sélection d'utilisateur
          Get.to(() => const SelectUserScreen());
        },
        backgroundColor: const Color.fromARGB(255, 20, 147, 4), // Couleur verte claire
        child: const Icon(Icons.message, color: Colors.white),
      ),
    );
  }

  /// Formater la date pour un affichage simplifié
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (now.difference(date).inDays == 0) {
      return "${date.hour}:${date.minute.toString().padLeft(2, '0')}";
    } else {
      return "${date.day}/${date.month}/${date.year}";
    }
  }

  /// Afficher la barre de recherche
  void _showSearchBar() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Recherche"),
        content: TextField(
          controller: searchController,
          decoration: const InputDecoration(hintText: "Rechercher une conversation"),
          onChanged: (value) {
            searchTerm.value = value;
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              searchController.clear();
              searchTerm.value = '';
              Navigator.of(context).pop();
            },
            child: const Text("Annuler"),
          ),
        ],
      ),
    );
  }

  /// Confirmer la suppression d'une conversation
  void _confirmDelete(String conversationId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Supprimer la conversation"),
        content: const Text("Voulez-vous vraiment supprimer cette conversation ?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Annuler"),
          ),
          TextButton(
            onPressed: () {
              chatController.deleteConversation(conversationId);
              Navigator.pop(context);
            },
            child: const Text("Supprimer", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// Récupérer les données de l'autre utilisateur
  AppUser? _getOtherUser(String userId) {
    try {
      return AppUser.fromMap({
        "nom": "Exemple",
        "photoProfil": "",
      });
    } catch (e) {
      print("Erreur lors de la récupération de l'utilisateur : $e");
      return null;
    }
  }
}
