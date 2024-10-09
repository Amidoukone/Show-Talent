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
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16), // Espacement pour toute la liste
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
                  return const ListTile(
                    title: Text('Chargement...'),
                    subtitle: Text('En attente des informations utilisateur'),
                  );
                }

                var otherUser = snapshot.data!;

                return FutureBuilder<int>(
                  future: chatController.getUnreadMessagesCount(conversation.id),
                  builder: (context, unreadSnapshot) {
                    int unreadCount = unreadSnapshot.data ?? 0;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10), // Espacement entre les conversations
                      child: Card(
                        elevation: 4, // Légère ombre pour donner un effet de surélévation
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15), // Coins arrondis pour un design moderne
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // Plus d'espace interne
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

                            // Ouvrir l'écran de chat pour discuter
                            // et attendre le retour à la page des conversations pour rafraîchir l'état
                            final result = await Get.to(() => ChatScreen(
                                  conversationId: conversation.id,
                                  currentUser: currentUser,
                                  otherUserId: otherUserId,
                                ));

                            if (result == true) {
                              // Rafraîchir les conversations et mettre à jour les badges après retour
                              chatController.fetchConversations();  // Forcer la mise à jour
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
        child: const Icon(Icons.chat),
      ),
    );
  }
}
