import 'package:adfoot/utils/account_role_policy.dart';
import 'package:adfoot/widgets/ad_button.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SignUpScreen extends StatelessWidget {
  const SignUpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final roleLabels = adminProvisionedRoles.join(', ');

    return Scaffold(
      backgroundColor: cs.surface,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.center,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.asset(
                          'assets/logo.png',
                          height: 80,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Creation de compte centralisee',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'L application mobile ne cree plus de comptes directement.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w600,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    _InfoCard(
                      icon: Icons.admin_panel_settings_outlined,
                      color: cs.primary,
                      title: 'Regle active',
                      message: publicSignupDisabledMessage,
                    ),
                    const SizedBox(height: 14),
                    _InfoCard(
                      icon: Icons.groups_outlined,
                      color: cs.secondary,
                      title: 'Roles concernes',
                      message:
                          'Tous les comptes sont maintenant provisionnes dans le portail admin: $roleLabels.',
                    ),
                    const SizedBox(height: 14),
                    _InfoCard(
                      icon: Icons.list_alt_outlined,
                      color: cs.tertiary,
                      title: 'Parcours utilisateur',
                      message: '1. Contacter l administration Adfoot.\n'
                          '2. Recevoir le lien de definition du mot de passe.\n'
                          '3. Valider l adresse e-mail.\n'
                          '4. Se connecter ensuite dans l application mobile.',
                    ),
                    const SizedBox(height: 24),
                    AdButton(
                      label: 'Retour a la connexion',
                      onPressed: () => Get.back(),
                      leading: Icons.arrow_back_rounded,
                      kind: AdButtonKind.primary,
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Get.back(),
                      child: const Text('J’ai déjà un compte'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.8),
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
