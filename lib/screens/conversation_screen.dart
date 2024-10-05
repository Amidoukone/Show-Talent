import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/chat_controller.dart';
import 'package:show_talent/models/message_converstion.dart';
import 'package:show_talent/models/user.dart';
import 'package:show_talent/screens/select_user_screen.dart'; // L'écran pour sélectionner un utilisateur
import 'chat_screen.dart';

class ConversationsScreen extends StatelessWidget {
  final ChatController chatController = Get.put(ChatController());

  ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conversations')),
      body: Obx(() {
        // Vérifier si l'utilisateur a des conversations disponibles
        if (chatController.conversations.isEmpty) {
          return const Center(child: Text('Aucune conversation disponible.'));
        }

        // Afficher la liste des conversations
        return ListView.builder(
          itemCount: chatController.conversations.length,
          itemBuilder: (context, index) {
            Conversation conversation = chatController.conversations[index];
            AppUser currentUser = chatController.currentUser;

            // Identifier l'autre utilisateur de la conversation
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

                // Afficher les informations de l'autre utilisateur dans la conversation
                AppUser otherUser = snapshot.data!;
                return ListTile(
                  title: Text(otherUser.nom),
                  subtitle: Text('Dernier message: ${conversation.lastMessage ?? ''}'),
                  onTap: () {
                    // Rediriger vers l'écran de chat (ChatScreen) lorsqu'une conversation est sélectionnée
                    Get.to(() => ChatScreen(
                      conversationId: conversation.id,
                      currentUser: currentUser,
                      otherUserId: otherUserId,
                    ));
                  },
                );
              },
            );
          },
        );
      }),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Naviguer vers l'écran de sélection des utilisateurs
          Get.to(() => SelectUserScreen());  // Écran où l'on peut choisir un utilisateur pour démarrer une conversation
        },
        tooltip: 'Nouvelle conversation',
        child: const Icon(Icons.chat),
      ),
    );
  }
}
