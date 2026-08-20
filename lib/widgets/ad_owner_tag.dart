import 'package:adfoot/widgets/ad_avatar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/user.dart';
import '../screens/profile_screen.dart';
import '../theme/ad_colors.dart';

/// Compact tag shown instead of a full author/organiser identity block on
/// your own content (offer, event...) -- seeing your own name/photo on
/// your own post adds nothing and just pushes the actual content down.
class AdOwnerTag extends StatelessWidget {
  const AdOwnerTag({
    super.key,
    required this.label,
    this.icon = Icons.person_pin_rounded,
  });

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AdColors.brand.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AdColors.brand.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AdColors.brand),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AdColors.brand,
            ),
          ),
        ],
      ),
    );
  }
}

/// Lighter single-line identity row (avatar + "name · role") used on list
/// cards for someone else's content -- a full two-line block is reserved
/// for detail views, where there's room for it.
class AdCompactIdentityRow extends StatelessWidget {
  const AdCompactIdentityRow({super.key, required this.user});

  final AppUser user;

  bool get _hasPhoto => user.photoProfil.trim().startsWith('http');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => Get.to(() => ProfileScreen(uid: user.uid, isReadOnly: true)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AdAvatar(
            radius: 13,
            backgroundColor: AdColors.surfaceCardAlt,
            photoUrl: _hasPhoto ? user.photoProfil : '',
            fallback: const Icon(Icons.person, size: 14, color: Colors.white70),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${user.nom} · ${user.role}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
