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
    final location = [
      user.city,
      user.region,
      user.country,
    ].where((value) => value?.trim().isNotEmpty == true).join(', ');
    final teamLabel = user.team?.isNotEmpty == true
        ? user.team
        : user.clubActuel;

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
                    Text(
                      user.nom,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _profileRoleLabel(user).toUpperCase(),
                      style: const TextStyle(
                        color: AdColors.onSurfaceMuted,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
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
                        if (user.age != null)
                          _InfoPill(
                            icon: Icons.cake_outlined,
                            label: '${user.age} ans',
                          ),
                        if (teamLabel?.isNotEmpty == true)
                          _InfoPill(
                            icon: Icons.flag_outlined,
                            label: teamLabel!,
                          ),
                        if (location.isNotEmpty)
                          _InfoPill(
                            icon: Icons.place_outlined,
                            label: location,
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
    final maxLabelWidth = (MediaQuery.of(context).size.width - 120).clamp(
      80.0,
      320.0,
    );

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
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxLabelWidth),
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

/// Ce qu'il reste a renseigner pour que le dossier scout soit exploitable.
///
/// Affiche uniquement au titulaire du profil (voir l'appel dans
/// `_buildAdvancedFootballSectionClean`). La liste est celle de
/// [AppUser.missingScoutRequirements] : cet ecran ne decide de rien, il
/// recopie. Deux endroits qui decident, c'est un ecran qui reclame un champ
/// dont la regle n'a plus besoin.
///
/// Le libelle porte la raison plutot que l'injonction : un joueur a qui l'on
/// demande sa date de naissance sans dire pourquoi la saisit mal ou pas du
/// tout.
class _MissingScoutRequirements extends StatelessWidget {
  const _MissingScoutRequirements({required this.missing});

  final List<String> missing;

  @override
  Widget build(BuildContext context) {
    if (missing.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AdColors.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Il reste à renseigner',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: AdColors.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Un club ne peut pas décider sur un dossier incomplet.',
            style: TextStyle(fontSize: 12, color: AdColors.onSurfaceMuted),
          ),
          const SizedBox(height: 8),
          // Une colonne, pas une ligne : ces libelles sont des phrases, et un
          // Wrap horizontal les couperait sur un ecran etroit.
          ...missing.map(
            (requirement) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.radio_button_unchecked,
                      size: 14,
                      color: AdColors.warning,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      requirement,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AdColors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
