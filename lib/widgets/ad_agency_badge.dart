import 'package:flutter/material.dart';

import 'package:adfoot/models/user.dart';
import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/theme/ad_tokens.dart';

/// Le libelle du badge, en un seul endroit.
///
/// Le profil et les listes de recherche l'affichent : trois copies d'une
/// chaine finissent toujours par diverger, et deux libelles differents pour
/// la meme chose se lisent comme deux statuts differents.
const String kAgencyPlayerBadgeLabel = 'Joueur agence';

/// La regle d'affichage du badge, en un seul endroit elle aussi.
///
/// Delegue a [AppUser.isAgencyPlayerAt] : joueur, dossier `adfoot`, non echu.
bool showsAgencyBadge(AppUser? user) {
  if (user == null) return false;
  return user.isAgencyPlayerAt(DateTime.now());
}

/// Le badge des joueurs que l'agence porte, tel qu'il apparait dans une
/// liste — resultats de recherche, annuaire de contacts.
///
/// Volontairement compact : dans une liste il accompagne un nom deja court,
/// et il ne doit ni pousser le nom hors de l'ecran ni se faire passer pour
/// l'element principal de la ligne. La version pleine taille du profil reste
/// une pastille `_InfoPill`, alignee sur les autres badges de l'entete.
///
/// N'affiche jamais l'echeance ni la reference du dossier : ce sont des
/// informations commerciales internes, et une liste est vue par tout le monde.
class AdAgencyBadge extends StatelessWidget {
  const AdAgencyBadge({super.key, this.showLabel = true});

  /// A false, seule l'icone est rendue — pour une ligne tres etroite.
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: showLabel ? 8 : 5,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: AdColors.brand,
        borderRadius: BorderRadius.circular(AdRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.workspace_premium_rounded,
            size: 13,
            color: AdColors.brandOn,
          ),
          if (showLabel) ...[
            const SizedBox(width: 4),
            const Text(
              kAgencyPlayerBadgeLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AdColors.brandOn,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
