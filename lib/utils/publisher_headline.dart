/// What a viewer needs to know about a publisher, on the video itself.
///
/// A recruiter watching a clip is answering one question — is this player
/// worth my attention — and the facts that answer it are the poste, the club
/// and the ville. The app has held all three on `AppUser` (`position`,
/// `clubActuel`/`team`, `city`) and has indexed them for search since
/// `video_search_matcher.dart` was written, but the video showed only the
/// name and the raw account role. So the one place the question is actually
/// asked was the one place the answer was missing, and finding it meant
/// leaving the video.
///
/// Deliberately pure and string-typed rather than taking an `AppUser`: the
/// composition rules are presentation, they change more often than the model,
/// and they are worth testing without one.
class PublisherHeadline {
  const PublisherHeadline._();

  static const String separator = ' · ';

  /// The badge shown beside the publisher's name.
  ///
  /// A player's poste replaces the word "joueur", which the surrounding
  /// context already implies and which tells a recruiter nothing. Every other
  /// kind of account keeps its role, because *there* the role is the fact
  /// that matters: a clip published by a club is a different thing from the
  /// same clip published by the player in it.
  static String badge({required String? role, required String? position}) {
    final normalizedRole = _clean(role);
    final normalizedPosition = _clean(position);

    if (normalizedRole.toLowerCase() == 'joueur' &&
        normalizedPosition.isNotEmpty) {
      return normalizedPosition;
    }
    return normalizedRole;
  }

  /// The line under the name: where this player plays, and from where.
  ///
  /// Empty when nothing is known, which is the common case today — no
  /// production profile carried a club or a ville on 2026-08-24 — and the
  /// overlay renders nothing rather than an empty row. It fills in on its own
  /// as profiles are completed, which is the behaviour a scouting product
  /// wants: the feed gets more useful without another release.
  static String details({
    required String? club,
    required String? team,
    required String? city,
  }) {
    // `clubActuel` is what the player declares they play for now; `team` is
    // the older field. One of them, never both, or a profile that filled in
    // each of them separately would read "ASEC · ASEC".
    final resolvedClub = _firstNonEmpty([club, team]);

    return _join([resolvedClub, _clean(city)]);
  }

  static String _clean(String? value) => value?.trim() ?? '';

  static String _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final cleaned = _clean(value);
      if (cleaned.isNotEmpty) return cleaned;
    }
    return '';
  }

  static String _join(List<String> parts) {
    final kept = parts.where((part) => part.isNotEmpty).toList(growable: false);
    return kept.isEmpty ? '' : kept.join(separator);
  }
}
