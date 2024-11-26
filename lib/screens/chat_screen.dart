import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/auth_controller.dart';
import 'package:show_talent/models/message_converstion.dart';
import '../controller/chat_controller.dart';
import '../models/user.dart';

class ChatScreen extends StatelessWidget {
  final String conversationId;
  final AppUser otherUser; // Utilisateur complet pour la conversation
  final ChatController chatController = Get.find();

  ChatScreen({
    required this.conversationId,
    required this.otherUser,
  });

  final TextEditingController messageController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
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
            Text(otherUser.nom), // Nom de l'autre utilisateur
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

                if (!snapshot.hasData || snapshot.data == null) {
                  return const Center(child: Text("Aucun message."));
                }

                final messages = snapshot.data!;

                // Marquer les messages comme lus
                _markMessagesAsRead(messages);

                return ListView.builder(
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isSentByUser = message.expediteurId ==
                        AuthController.instance.user!.uid;

                    return Align(
                      alignment: isSentByUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                          vertical: 5,
                          horizontal: 10,
                        ),
                        padding: const EdgeInsets.all(10),
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
                            Text(
                              message.contenu,
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 5),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _formatTime(message.dateEnvoi),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(width: 5),
                                if (isSentByUser)
                                  Icon(
                                    _getMessageIcon(message),
                                    size: 16,
                                    color: message.estLu
                                        ? const Color.fromARGB(255, 12, 62, 48)
                                        : const Color.fromARGB(255, 73, 252, 19),
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
                      fillColor: Colors.grey[200],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
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
                          senderId: AuthController.instance.user!.uid,
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
  void _markMessagesAsRead(List<Message> messages) {
    for (var message in messages) {
      if (!message.estLu &&
          message.destinataireId == AuthController.instance.user!.uid) {
        chatController.markMessageAsRead(
          conversationId: conversationId,
          messageId: message.id,
        );
      }
    }
  }

  /// Obtenir l'icône appropriée pour le message
  IconData _getMessageIcon(Message message) {
    if (message.estLu) {
      return Icons.done_all; // Double tick bleu
    } else {
      return Icons.done; // Simple tick gris
    }
  }

  /// Formater l'heure pour l'affichage
  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    if (now.difference(dateTime).inDays == 0) {
      return "${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}";
    } else {
      return "${dateTime.day}/${dateTime.month}/${dateTime.year}";
    }
  }
}
