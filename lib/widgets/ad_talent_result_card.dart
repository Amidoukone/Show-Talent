import 'package:flutter/material.dart';

import 'package:adfoot/l10n/generated/app_localizations.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/theme/ad_tokens.dart';
import 'package:adfoot/utils/country_codes.dart';
import 'package:adfoot/widgets/ad_avatar.dart';

/// Compact scout-facing summary of a player, built only from public profile
/// fields and their explicit trust/availability state.
class AdTalentResultCard extends StatelessWidget {
  const AdTalentResultCard({
    super.key,
    required this.user,
    required this.l10n,
    required this.onTap,
  });

  final AppUser user;
  final AppLocalizations l10n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final football = user.football;
    final isEnglish = l10n.localeName == 'en';
    final photoUrl = user.photoProfil.trim();
    final positions = football.positions
        .map((position) => isEnglish ? position.labelEn : position.labelFr)
        .join(' · ');
    final nationalities = football.nationalities
        .take(2)
        .map(countryLabel)
        .join(' · ');
    final clubName = football.currentClubName?.trim();

    return Card(
      margin: const EdgeInsets.only(bottom: AdSpacing.sm),
      color: AdColors.surfaceCard,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AdRadius.lg),
        side: const BorderSide(color: AdColors.divider),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AdSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdAvatar(
                radius: 27,
                backgroundColor: AdColors.surfaceCardAlt,
                photoUrl: photoUrl.startsWith('http') ? photoUrl : '',
                fallback: const Icon(
                  Icons.person_outline_rounded,
                  color: AdColors.onSurfaceMuted,
                ),
              ),
              const SizedBox(width: AdSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            user.nom,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        if (user.isProfileTrusted) ...[
                          const SizedBox(width: AdSpacing.xs),
                          Tooltip(
                            message: user.profileTrustLabel,
                            child: const Icon(
                              Icons.verified_rounded,
                              color: AdColors.info,
                              size: 19,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (positions.isNotEmpty) ...[
                      const SizedBox(height: AdSpacing.xxs),
                      Text(
                        positions,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: AdColors.brand,
                        ),
                      ),
                    ],
                    const SizedBox(height: AdSpacing.sm),
                    Wrap(
                      spacing: AdSpacing.md,
                      runSpacing: AdSpacing.xs,
                      children: [
                        if (football.birthYear != null)
                          _TalentFact(
                            icon: Icons.calendar_today_outlined,
                            label: l10n.talentSearchBirthYear(
                              football.birthYear!,
                            ),
                          ),
                        if (nationalities.isNotEmpty)
                          _TalentFact(
                            icon: Icons.flag_outlined,
                            label: nationalities,
                          ),
                        if (clubName != null && clubName.isNotEmpty)
                          _TalentFact(
                            icon: Icons.shield_outlined,
                            label: clubName,
                          ),
                        if (football.currentClubLevel != null)
                          _TalentFact(
                            icon: Icons.stadium_outlined,
                            label: isEnglish
                                ? football.currentClubLevel!.labelEn
                                : football.currentClubLevel!.labelFr,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (user.openToOpportunities == true) ...[
                const SizedBox(width: AdSpacing.xs),
                Tooltip(
                  message: l10n.talentSearchOpenOnlyLabel,
                  child: const Icon(
                    Icons.how_to_reg_outlined,
                    color: AdColors.success,
                    size: 21,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TalentFact extends StatelessWidget {
  const _TalentFact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AdColors.onSurfaceMuted),
        const SizedBox(width: AdSpacing.xxs),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AdColors.onSurfaceMuted,
            ),
          ),
        ),
      ],
    );
  }
}
