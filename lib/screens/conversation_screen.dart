import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/chat_controller.dart';
import 'package:show_talent/models/user.dart';
import 'package:show_talent/screens/chat_screen.dart';
import 'package:show_talent/screens/select_user_screen.dart';

class ConversationsScreen extends StatelessWidget {
  final ChatController chatController = Get.put(ChatController());

  ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conversations')),
      body: Obx(() {
        if (chatController.conversations.isEmpty) {
          return const Center(child: Text('Aucune conversation disponible.'));
        }

        return ListView.builder(
          itemCount: chatController.conversations.length,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          itemBuilder: (context, index) {
            var conversation = chatController.conversations[index];
            var currentUser = chatController.currentUser;

            // Identifie l'autre utilisateur dans la conversation
            String otherUserId = conversation.utilisateur1Id == currentUser.uid
                ? conversation.utilisateur2Id
                : conversation.utilisateur1Id;

            return FutureBuilder<AppUser?>(
              future: chatController.getUserById(otherUserId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox.shrink(); // Supprime le message de chargement une fois les données reçues
                }

                if (snapshot.data == null) {
                  return const ListTile(
                    title: Text('Utilisateur introuvable'),
                  ); // Afficher si l'utilisateur n'existe pas
                }

                var otherUser = snapshot.data!;

                return FutureBuilder<int>(
                  future: chatController.getUnreadMessagesCount(conversation.id),
                  builder: (context, unreadSnapshot) {
                    int unreadCount = unreadSnapshot.data ?? 0;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          title: Text(
                            otherUser.nom,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Colors.black87,
                            ),
                          ),
                          subtitle: Text(
                            'Dernier message: ${conversation.lastMessage ?? ''}',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 14,
                            ),
                          ),
                          trailing: unreadCount > 0
                              ? CircleAvatar(
                                  backgroundColor: Colors.red,
                                  radius: 12,
                                  child: Text(
                                    unreadCount.toString(),
                                    style: const TextStyle(color: Colors.white, fontSize: 12),
                                  ),
                                )
                              : null,
                          onTap: () async {
                            // Marquer les messages comme "Lu" lorsque la conversation est ouverte
                            await chatController.markMessagesAsRead(conversation.id);

                            // Ouvrir l'écran de chat et forcer la mise à jour du badge des messages non lus
                            final result = await Get.to(() => ChatScreen(
                                  conversationId: conversation.id,
                                  currentUser: currentUser,
                                  otherUserId: otherUserId,
                                ));

                            if (result == true) {
                              // Si l'utilisateur revient à la liste des conversations, forcer la mise à jour des badges
                              chatController.fetchConversations(); // Rafraîchir l'état après avoir ouvert la conversation
                            }
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      }),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Get.to(() => const SelectUserScreen()); // Permettre de démarrer une nouvelle conversation
        },
        tooltip: 'Nouvelle conversation',
        backgroundColor: Colors.green[800], 
        child: const Icon(
          Icons.chat,
          color: Colors.white, 
        ),
      ),
    );
  }
}
