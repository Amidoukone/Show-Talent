import 'package:flutter/material.dart';

import 'package:adfoot/utils/country_codes.dart';

/// Choisir un pays dans une liste fermée, avec recherche.
///
/// Partagé par les nationalités du joueur et les pays d'intervention de
/// l'agent : deux copies d'un sélecteur finissent par diverger sur la
/// recherche, sur la casse ou sur ce qu'elles renvoient, et c'est le genre
/// d'écart que personne ne remarque avant qu'un pays devienne introuvable
/// d'un côté seulement.
///
/// Renvoie un code ISO alpha-2, ou null si l'utilisateur referme la feuille.
Future<String?> showCountryPicker(
  BuildContext context, {
  Iterable<String> excluded = const <String>[],
}) {
  final available = countriesByName()
      .where((entry) => !excluded.contains(entry.key))
      .toList();

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _CountryPickerSheet(countries: available),
  );
}

class _CountryPickerSheet extends StatefulWidget {
  const _CountryPickerSheet({required this.countries});

  final List<MapEntry<String, String>> countries;

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    // Une liste de cent pays sans champ de recherche est une liste qu'on fait
    // defiler jusqu'a renoncer.
    final visible = query.isEmpty
        ? widget.countries
        : widget.countries
              .where((entry) => entry.value.toLowerCase().contains(query))
              .toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Rechercher un pays',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Expanded(
                child: visible.isEmpty
                    ? const Center(child: Text('Aucun pays trouvé.'))
                    : ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final entry = visible[index];
                          return ListTile(
                            title: Text(entry.value),
                            onTap: () => Navigator.of(context).pop(entry.key),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
