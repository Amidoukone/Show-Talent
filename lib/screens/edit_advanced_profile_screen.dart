// lib/screens/edit_advanced_profile_screen.dart
import 'package:flutter/material.dart';
import '../models/user.dart';
import '../controller/profile_controller.dart';
import '../widgets/advanced/player_advanced_form.dart';
import '../widgets/advanced/player_stats_availability_form.dart';
import '../widgets/advanced/club_advanced_form.dart';
import '../widgets/advanced/agent_advanced_form.dart';

class EditAdvancedProfileScreen extends StatelessWidget {
  final AppUser user;
  final ProfileController profileController;

  const EditAdvancedProfileScreen({
    super.key,
    required this.user,
    required this.profileController,
  });

  @override
  Widget build(BuildContext context) {
    Widget body;

    if (user.isPlayer) {
      body = SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            PlayerAdvancedForm(
              user: user,
              profileController: profileController,
              // 👉 important : ne pas Get.back() automatiquement depuis les forms
              // on reste dans l’écran
              autoCloseOnSave: false,
            ),
            const Divider(height: 32),
            PlayerStatsAvailabilityForm(
              user: user,
              profileController: profileController,
              autoCloseOnSave: false,
            ),
          ],
        ),
      );
    } else if (user.isClub) {
      body = ClubAdvancedForm(
        user: user,
        profileController: profileController,
      );
    } else if (user.isRecruiter) {
      body = AgentAdvancedForm(
        user: user,
        profileController: profileController,
      );
    } else {
      body = const Center(child: Text('Aucun profil avancé pour ce rôle'));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil avancé'),
        centerTitle: true,
      ),
      body: SafeArea(child: body),
    );
  }
}
