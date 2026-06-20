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
    final location = user.city ?? user.region ?? user.country;
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
                      child: CircleAvatar(
                        backgroundColor: AdColors.surfaceCardAlt,
                        backgroundImage: user.photoProfil.isNotEmpty
                            ? NetworkImage(user.photoProfil)
                            : null,
                        child: profileController.isLoadingPhoto.value
                            ? const CircularProgressIndicator()
                            : (user.photoProfil.isEmpty
                                  ? Text(
                                      _profileInitials(user),
                                      style: const TextStyle(
                                        color: AdColors.onSurface,
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    )
                                  : null),
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
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
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
                        if (location?.isNotEmpty == true)
                          _InfoPill(
                            icon: Icons.place_outlined,
                            label: location!,
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

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          video.thumbnailUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback(),
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) {
              return child;
            }

            return fallback();
          },
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AdColors.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdColors.divider),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AdColors.brand),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
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
