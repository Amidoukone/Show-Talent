import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/controller/auth_controller.dart';
import 'package:adfoot/models/message_converstion.dart';
import '../controller/chat_controller.dart';
import '../models/user.dart';

class ChatScreen extends StatelessWidget {
  final String conversationId;
  final AppUser otherUser;
  final ChatController chatController = Get.find();
  final TextEditingController messageController = TextEditingController();

  ChatScreen({
    super.key,
    required this.conversationId,
    required this.otherUser,
  });

  @override
  Widget build(BuildContext context) {
    final currentUser = AuthController.instance.user;

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Erreur")),
        body: const Center(child: Text("Utilisateur non connecté.")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundImage: otherUser.photoProfil.isNotEmpty
                  ? NetworkImage(otherUser.photoProfil)
                  : null,
              child: otherUser.photoProfil.isEmpty
                  ? Text(
                      otherUser.nom.substring(0, 1).toUpperCase(),
                      style: const TextStyle(color: Colors.black),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                otherUser.nom,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Message>>(
              stream: chatController.getMessages(conversationId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text("Aucun message."));
                }

                final messages = snapshot.data!;

                // Marquer les messages comme lus
                _markMessagesAsRead(messages, currentUser.uid);

                return ListView.builder(
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isSentByUser = message.expediteurId == currentUser.uid;

                    return Align(
                      alignment: isSentByUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSentByUser
                              ? const Color.fromARGB(255, 38, 230, 12).withOpacity(0.2)
                              : const Color.fromARGB(255, 99, 222, 211).withOpacity(0.3),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(12),
                            topRight: const Radius.circular(12),
                            bottomLeft: isSentByUser
                                ? const Radius.circular(12)
                                : const Radius.circular(0),
                            bottomRight: isSentByUser
                                ? const Radius.circular(0)
                                : const Radius.circular(12),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(message.contenu, style: const TextStyle(fontSize: 16)),
                            const SizedBox(height: 5),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _formatTime(message.dateEnvoi),
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                ),
                                const SizedBox(width: 5),
                                if (isSentByUser)
                                  Icon(
                                    _getMessageIcon(message),
                                    size: 16,
                                    color: Colors.grey[700],
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: messageController,
                    decoration: InputDecoration(
                      hintText: "Tapez un message...",
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: const Color.fromARGB(255, 3, 121, 9),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: () {
                      final content = messageController.text.trim();
                      if (content.isNotEmpty) {
                        chatController.sendMessage(
                          conversationId: conversationId,
                          senderId: currentUser.uid,
                          recipientId: otherUser.uid,
                          content: content,
                        );
                        messageController.clear();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Marquer les messages comme lus
  void _markMessagesAsRead(List<Message> messages, String currentUserId) {
    for (var message in messages) {
      if (!message.estLu && message.destinataireId == currentUserId) {
        chatController.markMessageAsRead(
          conversationId: conversationId,
          messageId: message.id,
        );
      }
    }
  }

  /// Icône de statut d'envoi
  IconData _getMessageIcon(Message message) {
    return message.estLu ? Icons.done_all : Icons.done;
  }

  /// Formater l'heure
  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    if (now.difference(dateTime).inDays == 0) {
      return "${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}";
    } else {
      return "${dateTime.day}/${dateTime.month}/${dateTime.year}";
    }
  }
}
