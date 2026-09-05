part of 'profile_screen.dart';

class _HeaderCard extends StatelessWidget {
  final AppUser user;
  final bool isOwnProfile;
  final bool isReadOnly;
  final VoidCallback onViewPhoto;
  final VoidCallback onChangePhoto;
  final ProfileController profileController;

  const _HeaderCard({
    required this.user,
    required this.isOwnProfile,
    required this.isReadOnly,
    required this.onViewPhoto,
    required this.onChangePhoto,
    required this.profileController,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            color: AdColors.surfaceCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AdColors.divider),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Obx(
                () => GestureDetector(
                  onTap: user.photoProfil.isNotEmpty ? onViewPhoto : null,
                  child: Hero(
                    tag: 'profile-photo-${user.uid}',
                    child: Container(
                      width: 96,
                      height: 96,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AdColors.brand.withValues(alpha: 0.42),
                        ),
                      ),
                      // Stack rather than CircleAvatar's `child`: the
                      // upload spinner has to sit *over* the photo already on
                      // screen, which a `child` cannot do once a background
                      // image is set.
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          AdAvatar(
                            backgroundColor: AdColors.surfaceCardAlt,
                            photoUrl: user.photoProfil,
                            fallback: Text(
                              _profileInitials(user),
                              style: const TextStyle(
                                color: AdColors.onSurface,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (profileController.isLoadingPhoto.value)
                            const Center(child: CircularProgressIndicator()),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Ni le nom ni le role ne sont repris ici : la barre du
                    // haut les porte deja, a trois centimetres au-dessus, en
                    // titre et en sous-titre. Les afficher deux fois ne disait
                    // rien de plus et volait la seule place ou un recruteur
                    // cherche des faits.
                    //
                    // Meme raison pour l'age, le club et la localisation, qui
                    // vivaient ici en pastilles et vivent toujours dans les
                    // sections en dessous : une fiche qui repete se lit deux
                    // fois plus lentement.

                    // The account's e-mail, for its owner only.
                    //
                    // It used to live in the Outils header, which was the one
                    // surface telling you *which* account this device is
                    // signed in as — and Outils no longer carries any
                    // identity at all. The line belongs to the profile, so it
                    // moved here rather than disappearing. Never shown to a
                    // visitor: an e-mail address is credential-adjacent, not
                    // public profile data, and no other profile field on this
                    // card is hidden from anyone.
                    if (isOwnProfile &&
                        !isReadOnly &&
                        user.email.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.alternate_email_rounded,
                            size: 15,
                            color: AdColors.onSurfaceMuted,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              user.email.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AdColors.onSurfaceMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // En tete de la rangee : pour un recruteur, savoir
                        // qui accompagne le joueur passe avant le niveau de
                        // completude du dossier.
                        if (showsAgencyBadge(user))
                          _InfoPill(
                            icon: Icons.workspace_premium_rounded,
                            label: kAgencyPlayerBadgeLabel,
                            style: _profileLevelStyle(kAgencyPlayerBadgeLabel),
                          ),
                        if (user.isProfileTrusted)
                          _InfoPill(
                            icon: Icons.verified_rounded,
                            label: user.profileTrustLabel,
                            style: _profileLevelStyle(user.profileTrustLabel),
                          ),
                        _InfoPill(
                          icon: Icons.military_tech_outlined,
                          label: user.profileLevelLabel,
                          style: _profileLevelStyle(user.profileLevelLabel),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Bouton photo positionne proprement, sans overflow
        if (isOwnProfile && !isReadOnly)
          Positioned(
            top: 10,
            right: 10,
            child: IconButton(
              tooltip: 'Changer la photo',
              icon: const Icon(Icons.camera_alt_outlined),
              color: AdColors.brand,
              onPressed: onChangePhoto,
            ),
          ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  final VoidCallback onTap;

  const _StatChip({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 126),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AdColors.surfaceCardAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AdColors.divider),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: AdColors.onSurfaceMuted)),
          ],
        ),
      ),
    );
  }
}

/// Visual treatment for a non-public lifecycle stage.
class _VideoStateBadge {
  const _VideoStateBadge({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  /// Returns `null` for a live video: the overwhelmingly common case must
  /// stay visually clean, so only the states that need explaining get chrome.
  static _VideoStateBadge? forVideo(Video video) {
    switch (video.lifecycle) {
      case VideoLifecycle.live:
        return null;
      case VideoLifecycle.processing:
        return const _VideoStateBadge(
          label: VideoUiStrings.videoStateProcessing,
          icon: Icons.hourglass_top_rounded,
          color: AdColors.info,
        );
      case VideoLifecycle.underReview:
        return const _VideoStateBadge(
          label: VideoUiStrings.videoStateUnderReview,
          icon: Icons.shield_moon_outlined,
          color: AdColors.warning,
        );
      case VideoLifecycle.moderated:
        return const _VideoStateBadge(
          label: VideoUiStrings.videoStateModerated,
          icon: Icons.visibility_off_outlined,
          color: AdColors.error,
        );
      case VideoLifecycle.failed:
        return const _VideoStateBadge(
          label: VideoUiStrings.videoStateFailed,
          icon: Icons.error_outline_rounded,
          color: AdColors.error,
        );
    }
  }
}

class _VideoTile extends StatelessWidget {
  final Video video;
  final VoidCallback onTap;

  const _VideoTile({required this.video, required this.onTap});

  @override
  Widget build(BuildContext context) {
    Widget fallback() {
      return Container(
        color: AdColors.surfaceCardAlt,
        alignment: Alignment.center,
        child: const Icon(
          Icons.play_circle_outline_rounded,
          color: AdColors.onSurfaceMuted,
          size: 28,
        ),
      );
    }

    // Only the owner ever receives a non-live video from the repository, so
    // this badge is implicitly private to them (see fetchUserVideos).
    final badge = _VideoStateBadge.forVideo(video);

    // An empty URL is a real case now that the owner sees videos before they
    // are live: a still is only guaranteed once the upload has been
    // finalized. Checking up front keeps it out of the image widget entirely
    // rather than relying on it to fail its way into an error builder, which
    // costs a failed resolution and logs an exception per tile per rebuild.
    //
    // CachedNetworkImage, not Image.network: `VideoController` already warms
    // these stills into `DefaultCacheManager`, and that is the store
    // CachedNetworkImage reads. `Image.network` has no disk cache at all, so
    // it ignored the prefetch entirely and re-downloaded every thumbnail on
    // every scroll — and again after every app restart.
    Widget thumbnail = video.thumbnailUrl.trim().isEmpty
        ? fallback()
        : CachedNetworkImage(
            imageUrl: video.thumbnailUrl,
            fit: BoxFit.cover,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            placeholder: (_, _) => fallback(),
            errorWidget: (_, _, _) => fallback(),
          );

    if (badge != null) {
      // Dim the still so the badge stays readable over a bright frame, and so
      // the tile reads as "not live yet" before the label is even parsed.
      thumbnail = Stack(
        fit: StackFit.expand,
        children: [
          thumbnail,
          Container(color: Colors.black.withValues(alpha: 0.45)),
          Positioned(
            left: 4,
            right: 4,
            bottom: 4,
            // Dark chip with a colored icon/label rather than a colored chip
            // with white text: `warning` and `brand` are light enough that
            // white-on-color would fail contrast, and a single chip treatment
            // keeps the three states legible over any video frame.
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: AdColors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(badge.icon, size: 12, color: badge.color),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      badge.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: badge.color,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: thumbnail,
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final _ProfileLevelStyle? style;

  const _InfoPill({required this.label, required this.icon, this.style});

  @override
  Widget build(BuildContext context) {
    final resolvedStyle = style;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: resolvedStyle?.backgroundColor ?? AdColors.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: resolvedStyle?.borderColor ?? AdColors.divider,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            resolvedStyle?.icon ?? icon,
            size: 18,
            color: resolvedStyle?.foregroundColor ?? AdColors.brand,
          ),
          const SizedBox(width: 6),
          // `Flexible`, et non une largeur calculee sur l'ecran.
          //
          // La pastille vit dans un `Wrap`, lui-meme dans la colonne qui suit
          // l'avatar : la place reelle, c'est la largeur de l'ecran moins
          // l'avatar (96), l'ecart (14) et les paddings (2x16), soit environ
          // 142 px. La contrainte precedente n'en retirait que 120 et
          // debordait donc d'une bonne cinquantaine de pixels : l'ellipse ne
          // se declenchait jamais et un libelle long -- « Ville, Region,
          // Pays » -- sortait du cadre par la droite.
          //
          // Le parent connait sa largeur ; le lui demander plutot que la
          // deviner rend le correctif insensible a tout ce qu'on ajoutera
          // autour.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: resolvedStyle?.foregroundColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

/// Ce qu'il reste a renseigner, en deux rangs qui ne pesent pas pareil.
///
/// Affiche uniquement au titulaire du profil (voir l'appel dans
/// `_buildAdvancedFootballSectionClean`). Les listes viennent de
/// [AppUser.missingSearchRequirements] et
/// [AppUser.missingScoutOnlyRequirements] : cet ecran ne decide de rien et ne
/// soustrait rien, il recopie. Deux endroits qui decident, c'est un ecran qui
/// reclame un champ dont la regle n'a plus besoin.
///
/// Le premier rang existe parce que l'ancienne version n'en avait qu'un. Neuf
/// exigences y etaient alignees a l'identique, alors que trois d'entre elles
/// -- date de naissance, poste, nationalite -- decident si la fiche existe
/// dans une recherche, et les six autres seulement si elle est complete. Un
/// joueur remplissait sa taille et son pied fort, voyait la liste raccourcir,
/// et restait introuvable de tout recruteur sans qu'aucun ecran ne fasse la
/// difference.
///
/// Le libelle porte la raison plutot que l'injonction : un joueur a qui l'on
/// demande sa date de naissance sans dire pourquoi la saisit mal ou pas du
/// tout.
class _MissingScoutRequirements extends StatelessWidget {
  const _MissingScoutRequirements({
    required this.blocking,
    required this.missing,
    this.hiddenByChoice = false,
  });

  /// Ce qui empeche la fiche d'apparaitre dans une recherche.
  final List<String> blocking;

  /// Ce qui manque au dossier une fois la trouvabilite acquise.
  final List<String> missing;

  /// La fiche est complete, mais son titulaire l'a mise hors des recherches.
  final bool hiddenByChoice;

  @override
  Widget build(BuildContext context) {
    if (blocking.isEmpty && missing.isEmpty && !hiddenByChoice) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AdColors.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: blocking.isEmpty ? AdColors.divider : AdColors.warning,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (blocking.isNotEmpty) ...[
            _block(
              title: 'Votre fiche n’apparaît dans aucune recherche',
              subtitle:
                  'Un recruteur qui filtre par poste, par âge ou par '
                  'nationalité ne peut pas vous trouver tant qu’il manque :',
              entries: blocking,
              icon: Icons.error_outline_rounded,
              color: AdColors.warning,
              emphasised: true,
            ),
            if (missing.isNotEmpty) const SizedBox(height: 14),
          ],
          // Dit seulement une fois la trouvabilite acquise : annoncer « vous
          // etes trouvable » au-dessus d'un bloc qui dit le contraire serait
          // la contradiction que ce widget existe pour supprimer.
          if (hiddenByChoice) ...[
            _block(
              title: 'Votre fiche est complète, mais masquée',
              subtitle:
                  'Vous avez choisi de ne pas apparaître dans les recherches. '
                  'Rendez votre profil public pour être trouvé.',
              entries: const <String>[],
              icon: Icons.visibility_off_outlined,
              color: AdColors.onSurfaceMuted,
            ),
            if (missing.isNotEmpty) const SizedBox(height: 14),
          ],
          if (missing.isNotEmpty)
            _block(
              title: blocking.isEmpty
                  ? 'Il reste à renseigner'
                  : 'Puis, pour un dossier complet',
              subtitle: 'Un club ne peut pas décider sur un dossier incomplet.',
              entries: missing,
              icon: Icons.radio_button_unchecked,
              color: AdColors.onSurfaceMuted,
            ),
        ],
      ),
    );
  }

  Widget _block({
    required String title,
    required String subtitle,
    required List<String> entries,
    required IconData icon,
    required Color color,
    bool emphasised = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: emphasised ? AdColors.warning : AdColors.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 12,
            color: AdColors.onSurfaceMuted,
          ),
        ),
        if (entries.isNotEmpty) const SizedBox(height: 8),
        // Une colonne, pas une ligne : ces libelles sont des phrases, et un
        // Wrap horizontal les couperait sur un ecran etroit.
        ...entries.map(
          (requirement) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(icon, size: 14, color: color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    requirement,
                    style: TextStyle(
                      fontSize: 13,
                      color: AdColors.onSurface,
                      fontWeight: emphasised ? FontWeight.w700 : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
