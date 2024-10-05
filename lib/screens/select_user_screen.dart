import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/user_controller.dart';
import 'package:show_talent/controller/chat_controller.dart';
import 'package:show_talent/models/user.dart';
import 'chat_screen.dart';

class SelectUserScreen extends StatefulWidget {
  const SelectUserScreen({super.key});

  @override
  _SelectUserScreenState createState() => _SelectUserScreenState();
}

class _SelectUserScreenState extends State<SelectUserScreen> {
  final UserController userController = Get.put(UserController());
  final ChatController chatController = Get.put(ChatController());
  final TextEditingController searchController = TextEditingController(); // Contrôleur pour la recherche
  RxString searchTerm = ''.obs; // Observable pour stocker le terme de recherche

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sélectionner un utilisateur'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: 'Rechercher un utilisateur...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onChanged: (value) {
                searchTerm.value = value.toLowerCase(); // Met à jour le terme de recherche
              },
            ),
          ),
          Expanded(
            child: Obx(() {
              // Vérifier si la liste des utilisateurs est vide
              if (userController.userList.isEmpty) {
                return const Center(child: Text('Aucun utilisateur disponible.'));
              }

              // Filtrer la liste des utilisateurs selon le terme de recherche
              var filteredUsers = userController.userList.where((user) {
                return user.nom.toLowerCase().contains(searchTerm.value);
              }).toList();

              if (filteredUsers.isEmpty) {
                return const Center(child: Text('Aucun utilisateur trouvé.'));
              }

              return ListView.builder(
                itemCount: filteredUsers.length,
                itemBuilder: (context, index) {
                  AppUser user = filteredUsers[index];
                  return ListTile(
                    title: Text(user.nom),
                    subtitle: Text(user.email),
                    onTap: () async {
                      // Créer une nouvelle conversation avec l'utilisateur sélectionné
                      String conversationId = await chatController.createConversation(
                        chatController.currentUser, // L'utilisateur actuel
                        user, // L'utilisateur sélectionné
                      );

                      // Redirection vers ChatScreen après la création de la conversation
                      Get.to(() => ChatScreen(
                        conversationId: conversationId,
                        currentUser: chatController.currentUser,
                        otherUserId: user.uid,
                      ));
                    },
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}
