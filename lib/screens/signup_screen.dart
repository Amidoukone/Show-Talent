import 'package:adfoot/l10n/generated/app_localizations.dart';
import 'package:adfoot/theme/ad_tokens.dart';
import 'package:adfoot/utils/account_role_policy.dart';
import 'package:adfoot/widgets/ad_button.dart';
import 'package:adfoot/widgets/ad_surface_card.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SignUpScreen extends StatelessWidget {
  const SignUpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final roleLabels = adminProvisionedRoles.join(', ');

    return Scaffold(
      backgroundColor: cs.surface,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AdSpacing.lg,
            vertical: AdSpacing.xl,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: AdSurfaceCard(
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
                  const SizedBox(height: AdSpacing.md),
                  Text(
                    l10n.signupTitle,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.signupSubtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AdSpacing.lg),
                  _InfoCard(
                    icon: Icons.admin_panel_settings_outlined,
                    color: cs.primary,
                    title: l10n.signupActiveRuleCardTitle,
                    // Meme regle que publicSignupDisabledMessage
                    // (account_role_policy.dart), traduite ici pour cet
                    // affichage. La constante Dart reste la source utilisee
                    // par auth_session_service.dart/user_repository.dart tant
                    // que ces flux ne sont pas eux-memes localises.
                    message: l10n.signupActiveRuleCardMessage,
                  ),
                  const SizedBox(height: 14),
                  _InfoCard(
                    icon: Icons.groups_outlined,
                    color: cs.secondary,
                    title: l10n.signupRolesCardTitle,
                    message: l10n.signupRolesCardMessage(roleLabels),
                  ),
                  const SizedBox(height: 14),
                  _InfoCard(
                    icon: Icons.list_alt_outlined,
                    color: cs.tertiary,
                    title: l10n.signupUserJourneyCardTitle,
                    message: l10n.signupUserJourneyCardMessage,
                  ),
                  const SizedBox(height: AdSpacing.xl),
                  AdButton(
                    label: l10n.commonBackToLogin,
                    onPressed: () => Get.back(),
                    leading: Icons.arrow_back_rounded,
                    kind: AdButtonKind.primary,
                  ),
                  const SizedBox(height: AdSpacing.xs),
                  TextButton(
                    onPressed: () => Get.back(),
                    child: Text(l10n.signupAlreadyHaveAccount),
                  ),
                ],
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
        borderRadius: BorderRadius.circular(AdRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.18)),
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
