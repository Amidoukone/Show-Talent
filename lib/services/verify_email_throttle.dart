// lib/services/verify_email_throttle.dart
/// Throttle global (mémoire de process) pour l'envoi d'email de vérification.
/// Évite les rafales qui déclenchent "too-many-requests" côté Firebase.
class VerifyEmailThrottle {
  static DateTime? lastSentAt;
  static const Duration minInterval = Duration(seconds: 60);

  /// Peut-on envoyer un email maintenant ?
  static bool canSendNow() {
    final last = lastSentAt;
    if (last == null) return true;
    return DateTime.now().difference(last) >= minInterval;
  }

  /// Marque un envoi immédiat (pour démarrer l'intervalle).
  static void markSentNow() {
    lastSentAt = DateTime.now();
  }
}
