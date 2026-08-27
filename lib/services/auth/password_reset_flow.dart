/// The one screen session routing is not allowed to take away.
///
/// Tapping a "mot de passe oublié" link opens the app rather than a browser:
/// the reset link lives at `<authDomain>/__/auth/action`, and
/// AndroidManifest.xml claims that path as a verified App Link. The handler
/// then routes to [AppRoutes.resetPassword] — and, until this latch existed,
/// lost the race that followed.
///
/// Two other owners navigate on their own schedule at exactly that moment:
/// `SplashScreen` resolves the session and replaces the stack, and
/// `UserController` does the same on every `idTokenChanges` event, which
/// always fires on a cold start. Both call `Get.offAllNamed`, so whichever
/// landed last won. The user's report was precise: the reset page appears and
/// "l'application s'ouvre directement" before a password can be typed.
///
/// A route check alone does not fix it — the losing navigation is often
/// already queued when the reset screen mounts. So the flow is claimed the
/// moment a reset link is recognised, before the network round-trip that
/// validates the code, and released only when the reset screen is done with
/// it.
///
/// The deadline is a safety net, not a UX timer: nothing reads it while the
/// screen is alive and being used, and an `oobCode` is valid for an hour
/// anyway. It exists so that a flow abandoned in a way no `end()` covers —
/// the process kept alive in the background for hours — cannot leave session
/// routing muted for the rest of the app's life.
class PasswordResetFlow {
  PasswordResetFlow._();

  /// Long enough to read an e-mail, switch apps and type a password twice;
  /// far short of an app session.
  static const Duration _maxDuration = Duration(minutes: 15);

  static DateTime? _startedAt;

  /// Whether a password reset currently owns the screen.
  static bool get isInProgress {
    final startedAt = _startedAt;
    if (startedAt == null) {
      return false;
    }

    if (DateTime.now().difference(startedAt) >= _maxDuration) {
      _startedAt = null;
      return false;
    }

    return true;
  }

  /// Claims the screen for a reset that is about to be validated.
  static void begin() {
    _startedAt = DateTime.now();
  }

  /// Releases the screen — the reset finished, failed, or was abandoned.
  static void end() {
    _startedAt = null;
  }
}
