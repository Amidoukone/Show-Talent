import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/chat_controller.dart';
import 'package:show_talent/models/message_converstion.dart';
import 'package:show_talent/models/user.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final AppUser currentUser;
  final String otherUserId;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.currentUser,
    required this.otherUserId,
  });

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatController chatController = Get.put(ChatController());
  late Future<AppUser?> otherUser;
  final TextEditingController messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    otherUser = chatController.getUserById(widget.otherUserId);
    chatController.fetchMessages(widget.conversationId);
  }

  // Widget pour styliser les bulles de messages
  Widget buildMessageBubble(Message message, bool isSentByCurrentUser) {
    return Align(
      alignment: isSentByCurrentUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () {
          if (isSentByCurrentUser) {
            chatController.deleteMessage(widget.conversationId, message.id);
          }
        },
        child: Container(
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
          decoration: BoxDecoration(
            color: isSentByCurrentUser ? Colors.blueAccent : Colors.grey.shade300,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(12),
              topRight: const Radius.circular(12),
              bottomLeft: isSentByCurrentUser ? const Radius.circular(12) : Radius.zero,
              bottomRight: isSentByCurrentUser ? Radius.zero : const Radius.circular(12),
            ),
          ),
          child: Column(
            crossAxisAlignment: isSentByCurrentUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(
                message.contenu,
                style: TextStyle(
                  color: isSentByCurrentUser ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 5),
              if (isSentByCurrentUser)
                Text(
                  message.estLu ? 'Lu' : 'Non lu',
                  style: TextStyle(
                    fontSize: 10,
                    color: isSentByCurrentUser ? Colors.white70 : Colors.black54,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<AppUser?>(
          future: otherUser,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Text('Chargement...');
            }
            if (snapshot.hasError || snapshot.data == null) {
              return const Text('Erreur');
            }
            return Text('Chat avec ${snapshot.data!.nom}');
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              chatController.deleteConversation(widget.conversationId);
              Get.back(); // Retourner à la liste des conversations après la suppression
            },
          ),
        ],
      ),
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
                    bool isSentByCurrentUser = message.expediteurId == widget.currentUser.uid;

                    return buildMessageBubble(message, isSentByCurrentUser);
                  },
                );
              }
            }),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: messageController,
                    decoration: const InputDecoration(hintText: 'Écrivez un message...'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () {
                    if (messageController.text.trim().isNotEmpty) {
                      Message newMessage = Message(
                        id: '', // Firestore générera automatiquement l'ID
                        expediteurId: widget.currentUser.uid,
                        destinataireId: widget.otherUserId,
                        contenu: messageController.text.trim(),
                        dateEnvoi: DateTime.now(),
                        estLu: false,
                      );
                      chatController.sendMessage(widget.conversationId, newMessage);
                      messageController.clear(); // Vider le champ après l'envoi
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
