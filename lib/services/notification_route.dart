/// Where tapping a push notification should land the user.
///
/// The values here mirror the `data.type` payloads the backend actually
/// sends — `video_moderation` (admin_content_actions.ts notifyVideoOwner),
/// and `message` / `offre` / `event` (actions.ts sendUserPush and
/// sendFanoutToPlayers). Anything else resolves to [none]: an unknown type is
/// a payload from a newer backend than this build, and opening an arbitrary
/// screen is worse than simply bringing the app forward.
enum NotificationDestination {
  /// Nothing actionable — the tap only foregrounds the app.
  none,

  /// The recipient's own profile.
  ///
  /// Moderation notifications are about a video *they* uploaded, and their own
  /// profile is the only surface that renders a video which is not public yet:
  /// the `processing` / `under_review` / `failed` badges live there. Deep
  /// linking into the player instead would break on `rejected`, where the
  /// document no longer exists at all — adminRejectVideo deletes it.
  ownProfile,

  /// The conversations tab.
  conversations,

  /// The offers tab.
  offers,

  /// The events tab.
  events,
}

/// A resolved notification tap: where to go, and what it was about.
class NotificationRoute {
  const NotificationRoute({
    required this.destination,
    this.type = '',
    this.targetId,
  });

  static const NotificationRoute none = NotificationRoute(
    destination: NotificationDestination.none,
  );

  /// Screen to open.
  final NotificationDestination destination;

  /// Raw `data.type` as sent by the backend, kept for logging.
  final String type;

  /// Id of the entity the notification was about (video, conversation,
  /// offer, event), when the payload carried one.
  final String? targetId;

  bool get isActionable => destination != NotificationDestination.none;

  @override
  String toString() =>
      'NotificationRoute(destination: $destination, type: $type, '
      'targetId: $targetId)';
}

/// Maps an FCM `data` payload to a destination.
///
/// Tolerant by construction: FCM delivers `data` as a string map, keys can be
/// absent, and a malformed payload must never throw on a background isolate
/// where nothing would catch it.
NotificationRoute resolveNotificationRoute(Map<String, dynamic>? data) {
  if (data == null || data.isEmpty) {
    return NotificationRoute.none;
  }

  final type = (data['type'] ?? '').toString().trim().toLowerCase();
  if (type.isEmpty) {
    return NotificationRoute.none;
  }

  String? readId(List<String> keys) {
    for (final key in keys) {
      final value = (data[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  switch (type) {
    case 'video_moderation':
      return NotificationRoute(
        destination: NotificationDestination.ownProfile,
        type: type,
        targetId: readId(const ['videoId', 'id']),
      );
    case 'message':
      return NotificationRoute(
        destination: NotificationDestination.conversations,
        type: type,
        targetId: readId(const ['id', 'conversationId']),
      );
    case 'offre':
      return NotificationRoute(
        destination: NotificationDestination.offers,
        type: type,
        targetId: readId(const ['id', 'offreId']),
      );
    case 'event':
      return NotificationRoute(
        destination: NotificationDestination.events,
        type: type,
        targetId: readId(const ['id', 'eventId']),
      );
    default:
      return NotificationRoute.none;
  }
}
