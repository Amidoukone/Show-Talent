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
                return ListTile(
                  title: Text(otherUser.nom),
                  subtitle: Text('Dernier message: ${conversation.lastMessage ?? ''}'),
                  onTap: () {
                    // Ouvrir l'écran de chat pour discuter
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
          Get.to(() => const SelectUserScreen()); // Permettre de démarrer une nouvelle conversation
        },
        tooltip: 'Nouvelle conversation',
        child: const Icon(Icons.chat),
      ),
    );
  }
}
