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
    // Charger les informations de l'autre utilisateur
    otherUser = chatController.getUserById(widget.otherUserId);
    chatController.fetchMessages(widget.conversationId); // Charger les messages de la conversation
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
                    // Envoyer le message si le champ de texte n'est pas vide
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
