
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/chat_controller.dart';
import 'package:show_talent/models/message.dart';
import 'package:show_talent/models/user.dart';


class ChatScreen extends StatelessWidget {
  final String conversationId;
  final AppUser currentUser;
  final AppUser otherUser;
  final ChatController chatController = Get.put(ChatController());

  ChatScreen({super.key, 
    required this.conversationId,
    required this.currentUser,
    required this.otherUser,
  }) {
    // Initialisation des utilisateurs dans le contrôleur
    chatController.initUsers(currentUser, otherUser);
  }

  @override
  Widget build(BuildContext context) {
    chatController.fetchMessages(conversationId);

    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: Column(
        children: [
          Expanded(
            child: Obx(() {
              if (chatController.messages.isEmpty) {
                return const Center(child: Text('Aucun message.'));
              } else {
                return ListView.builder(
                  itemCount: chatController.messages.length,
                  itemBuilder: (context, index) {
                    Message message = chatController.messages[index];
                    return ListTile(
                      title: Text(message.contenu),
                      subtitle: Text(
                        message.estLu ? 'Lu' : 'Non lu',
                        style: TextStyle(
                          color: message.estLu ? Colors.green : Colors.red,
                        ),
                      ),
                    );
                  },
                );
              }
            }),
          ),
          // Ajout d'un champ pour envoyer un message
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(hintText: 'Écrivez un message...'),
                    onSubmitted: (text) {
                      // Envoi du message
                      Message newMessage = Message(
                        id: '', // L'ID est généré par Firestore
                        expediteur: chatController.currentUser, // Utilisateur actuel
                        destinataire: chatController.otherUser, // Utilisateur ciblé
                        contenu: text,
                        dateEnvoi: DateTime.now(),
                        estLu: false,
                      );
                      chatController.sendMessage(conversationId, newMessage);
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () {
                    // Logique de l'envoi manuelle si besoin
                  },
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}
