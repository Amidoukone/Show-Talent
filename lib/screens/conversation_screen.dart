import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
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
  final AuthController authController = Get.find<AuthController>();

  @override
  Widget build(BuildContext context) {
    final currentUserId = authController.user?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Conversations"),
        centerTitle: true,
      ),
      body: currentUserId == null
          ? const Center(child: Text("Utilisateur non connecté."))
          : Obx(() {
              if (chatController.conversations.isEmpty) {
                return const Center(child: Text("Aucune conversation."));
              }

              // Trier par date du dernier message
              final conversations = List.from(chatController.conversations);
              conversations.sort((a, b) =>
                  (b.lastMessageDate ?? DateTime(0))
                      .compareTo(a.lastMessageDate ?? DateTime(0)));

              return ListView.builder(
                itemCount: conversations.length,
                itemBuilder: (context, index) {
                  final conversation = conversations[index];

                  // Trouver l'autre utilisateur
                  final otherUserId = conversation.utilisateurIds.firstWhere(
                    (id) => id != currentUserId,
                    orElse: () => '',
                  );

                  if (otherUserId.isEmpty) {
                    return const ListTile(title: Text("Utilisateur inconnu"));
                  }

                  return FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('users')
                        .doc(otherUserId)
                        .get(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const ListTile(title: Text("Chargement..."));
                      }

                      if (!snapshot.hasData || snapshot.data == null) {
                        return const ListTile(title: Text("Utilisateur inconnu"));
                      }

                      final Map<String, dynamic>? userData =
                          snapshot.data?.data() as Map<String, dynamic>?;
                      if (userData == null) {
                        return const ListTile(title: Text("Erreur utilisateur"));
                      }

                      final otherUser = AppUser.fromMap(userData);
                      final int unreadCount = conversation.unreadMessagesCount;

                      return GestureDetector(
                        onLongPress: () => _confirmDelete(conversation.id),
                        child: ListTile(
                          leading: CircleAvatar(
                            radius: 25,
                            backgroundImage: otherUser.photoProfil.isNotEmpty
                                ? NetworkImage(otherUser.photoProfil)
                                : null,
                            child: otherUser.photoProfil.isEmpty
                                ? Text(
                                    otherUser.nom.substring(0, 1).toUpperCase(),
                                    style: const TextStyle(
                                        color: Colors.black, fontSize: 18),
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
                          trailing: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _formatDateOrTime(conversation.lastMessageDate),
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              if (unreadCount > 0)
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.teal,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    "$unreadCount",
                                    style: const TextStyle(color: Colors.white, fontSize: 12),
                                  ),
                                ),
                            ],
                          ),
                          onTap: () async {
                            try {
                              if (unreadCount > 0) {
                                await chatController.markMessagesAsRead(
                                    conversation.id, currentUserId);
                              }

                              Get.to(() => ChatScreen(
                                    conversationId: conversation.id,
                                    otherUser: otherUser,
                                  ));
                            } catch (e) {
                              Get.snackbar('Erreur',
                                  'Impossible d\'ouvrir la conversation : $e',
                                  backgroundColor: Colors.red,
                                  colorText: Colors.white);
                            }
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
          Get.to(() => const SelectUserScreen());
        },
        backgroundColor: const Color.fromARGB(255, 20, 147, 4),
        child: const Icon(Icons.message, color: Colors.white),
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

  /// Formater l'heure ou la date du dernier message
  String _formatDateOrTime(DateTime? dateTime) {
    if (dateTime == null) return "Inconnue";

    final now = DateTime.now();
    final isToday = now.difference(dateTime).inDays == 0;

    if (isToday) {
      return DateFormat('HH:mm').format(dateTime);
    } else {
      return DateFormat('dd/MM/yyyy').format(dateTime);
    }
  }
}
