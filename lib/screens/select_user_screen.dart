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
  // ✅ Ne pas recréer un ChatController : on réutilise l’existant
  final ChatController chatController = Get.isRegistered<ChatController>()
      ? Get.find<ChatController>()
      : Get.put(ChatController(), permanent: true);
  final AuthController authController = Get.find<AuthController>();

  final TextEditingController searchController = TextEditingController();
  RxString searchTerm = ''.obs;

  @override
  Widget build(BuildContext context) {
    final currentUid = authController.user?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sélectionner un utilisateur'),
        backgroundColor: const Color(0xFF214D4F),
      ),
      body: currentUid == null
          ? const Center(child: Text("Utilisateur non connecté."))
          : Column(
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
                      searchTerm.value = value.toLowerCase();
                    },
                  ),
                ),
                Expanded(
                  child: Obx(() {
                    var users = userController.userList.where((user) {
                      return user.uid != currentUid &&
                          user.nom.isNotEmpty &&
                          user.emailVerified == true &&
                          user.estActif == true;
                    }).toList();

                    if (users.isEmpty) {
                      return const Center(
                        child: Text('Aucun utilisateur disponible.'),
                      );
                    }

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
                            try {
                              String conversationId =
                                  await chatController.createOrGetConversation(
                                currentUserId: currentUid,
                                otherUserId: user.uid,
                              );

                              Get.to(() => ChatScreen(
                                    conversationId: conversationId,
                                    otherUser: user,
                                  ));
                            } catch (e) {
                              Get.snackbar(
                                'Erreur',
                                'Impossible de démarrer la conversation : $e',
                                backgroundColor: Colors.red,
                                colorText: Colors.white,
                              );
                            }
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
