import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controller/search_controller.dart'; // Le contrôleur renommé

class SearchScreen extends StatelessWidget {
  final CustomSearchController searchController = Get.put(CustomSearchController()); // Utilisation du nouveau nom

  SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recherche'),
      ),
      body: Column(
        children: [
          TextField(
            decoration: const InputDecoration(labelText: 'Rechercher'),
            onChanged: (query) {
              searchController.search(query);  // Utilisation de la méthode du nouveau contrôleur
            },
          ),
          Obx(() {
            // Affichage des résultats de recherche
            if (searchController.searchedUsers.isEmpty) {
              return const Text('Aucun résultat');
            }
            return Expanded(
              child: ListView.builder(
                itemCount: searchController.searchedUsers.length,
                itemBuilder: (context, index) {
                  final user = searchController.searchedUsers[index];
                  return ListTile(
                    title: Text(user.name),
                    subtitle: Text(user.email),
                  );
                },
              ),
            );
          }),
        ],
      ),
    );
  }
}
