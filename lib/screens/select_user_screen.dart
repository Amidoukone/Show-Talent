import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/controller/auth_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/controller/chat_controller.dart';
import 'package:adfoot/models/user.dart';
import 'chat_screen.dart';

class SelectUserScreen extends StatefulWidget {
  const SelectUserScreen({super.key});

  @override
  _SelectUserScreenState createState() => _SelectUserScreenState();
}

class _SelectUserScreenState extends State<SelectUserScreen> {
  final UserController userController = Get.put(UserController());
  final ChatController chatController = Get.put(ChatController());
  final TextEditingController searchController =
      TextEditingController(); // Contrôleur pour la recherche
  RxString searchTerm = ''.obs; // Observable pour stocker le terme de recherche

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sélectionner un utilisateur'),
        backgroundColor: const Color(0xFF214D4F),
      ),
      body: Column(
        children: [
          // Barre de recherche
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
                // Met à jour le terme de recherche en le passant en minuscules
                searchTerm.value = value.toLowerCase();
              },
            ),
          ),
          // Liste des utilisateurs
          Expanded(
            child: Obx(() {
              // Filtrer pour exclure l'utilisateur courant et les utilisateurs sans nom renseigné
              var users = userController.userList.where((user) {
                return user.uid != AuthController.instance.user!.uid &&
                    user.nom.isNotEmpty;
              }).toList();

              // S'il n'y a aucun utilisateur valide, afficher un message approprié
              if (users.isEmpty) {
                return const Center(
                  child: Text('Aucun utilisateur disponible.'),
                );
              }

              // Filtrer la liste selon le terme de recherche saisi
              var filteredUsers = users.where((user) {
                return user.nom.toLowerCase().contains(searchTerm.value);
              }).toList();

              if (filteredUsers.isEmpty) {
                return const Center(
                  child: Text('Aucun utilisateur trouvé.'),
                );
              }

              return ListView.builder(
                itemCount: filteredUsers.length,
                itemBuilder: (context, index) {
                  AppUser user = filteredUsers[index];

                  return ListTile(
                    leading: CircleAvatar(
                      radius: 25,
                      backgroundColor: Colors.grey[200],
                      // Si photoProfil est renseignée, on affiche l'image, sinon on affiche la première lettre du nom
                      backgroundImage: user.photoProfil.isNotEmpty
                          ? NetworkImage(user.photoProfil)
                          : null,
                      child: user.photoProfil.isEmpty
                          ? Text(
                              user.nom[0].toUpperCase(),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                  color: Colors.black),
                            )
                          : null,
                    ),
                    title: Text(
                      user.nom,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    subtitle: Text(
                      user.role.isNotEmpty ? user.role : 'Rôle inconnu',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    onTap: () async {
                      // Créer ou récupérer une conversation avec l'utilisateur sélectionné
                      String conversationId =
                          await chatController.createOrGetConversation(
                        currentUserId: AuthController.instance.user!.uid,
                        otherUserId: user.uid,
                      );

                      // Redirection vers ChatScreen après la création de la conversation
                      Get.to(() => ChatScreen(
                            conversationId: conversationId,
                            otherUser: user,
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
