import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:show_talent/screens/profile_screen.dart';

class SettingsScreen extends StatelessWidget {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Paramètres"),
        backgroundColor: const Color(0xFF214D4F),  // Couleur principale
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person, color: Color(0xFF214D4F)),  // Icônes stylisées
            title: const Text('Voir le profil'),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => ProfileScreen(uid: _auth.currentUser!.uid),
              ));
            },
          ),
          ListTile(
            leading: const Icon(Icons.notifications, color: Color(0xFF214D4F)),
            title: const Text('Notifications'),
            onTap: () {
              Get.snackbar('Notifications', 'Gestion des notifications en cours...');
            },
          ),
          ListTile(
            leading: const Icon(Icons.lock, color: Color(0xFF214D4F)),
            title: const Text('Confidentialité'),
            onTap: () {
              Get.snackbar('Confidentialité', 'Paramètres de confidentialité en cours...');
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Color(0xFF214D4F)),
            title: const Text('Se déconnecter'),
            onTap: () async {
              await _auth.signOut();
              Get.offAllNamed('/login'); 
            },
          ),
        ],
      ),
    );
  }
}
