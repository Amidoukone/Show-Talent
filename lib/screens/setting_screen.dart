import 'package:flutter/material.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:show_talent/screens/profile_screen.dart';  // Pour la déconnexion

class SettingsScreen extends StatelessWidget {
  final FirebaseAuth _auth = FirebaseAuth.instance;

SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Paramètres"),
        backgroundColor: Colors.red,
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Voir le profil'),
            onTap: () {
              // Naviguer vers l'écran du profil
              Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => ProfileScreen(uid: _auth.currentUser!.uid),
              ));
            },
          ),
          ListTile(
            leading: const Icon(Icons.notifications),
            title: const Text('Notifications'),
            onTap: () {
              // Ajouter une page ou des actions pour gérer les notifications
              Get.snackbar('Notifications', 'Gestion des notifications en cours...');
            },
          ),
          ListTile(
            leading: const Icon(Icons.lock),
            title: const Text('Confidentialité'),
            onTap: () {
              // Ajouter une page ou des actions pour gérer les paramètres de confidentialité
              Get.snackbar('Confidentialité', 'Paramètres de confidentialité en cours...');
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Se déconnecter'),
            onTap: () async {
              // Se déconnecter de Firebase
              await _auth.signOut();
              Get.offAllNamed('/login'); // Redirige vers la page de connexion
            },
          ),
        ],
      ),
    );
  }
}
