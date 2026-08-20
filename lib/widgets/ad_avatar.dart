import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A profile photo that cannot report itself as a crash.
///
/// Every avatar in the app used to be a bare
/// `CircleAvatar(backgroundImage: NetworkImage(url))`. That builds a
/// `DecorationImage` with no `onError` listener, and Flutter's
/// `ImageStreamCompleter.reportError` routes an unlistened failure straight to
/// `FlutterError.onError` — which this app wires to
/// `FirebaseCrashlytics.recordFlutterFatalError`. A profile photo whose
/// Storage object was deleted, or simply a fetch that died on a weak network,
/// was therefore booked as a **fatal crash**, and the user was left staring at
/// an empty circle because nothing switched to the fallback either.
///
/// It also refetched: `NetworkImage` goes through Flutter's in-memory image
/// cache only, so the same avatar was downloaded again on every screen and
/// again after any memory pressure. [CachedNetworkImageProvider] keeps it on
/// disk, which is what the rest of the app already does for thumbnails.
///
/// [fallback] is what shows when there is no photo *and* when loading one
/// fails, so the two cases finally look the same to the user.
class AdAvatar extends StatefulWidget {
  const AdAvatar({
    super.key,
    required this.photoUrl,
    required this.backgroundColor,
    this.fallback,
    this.fallbackImage,
    this.radius,
    this.foregroundColor,
  });

  final String photoUrl;
  final Color backgroundColor;
  final Widget? fallback;

  /// Local stand-in drawn as the background when there is no usable photo.
  ///
  /// For the call sites whose placeholder is a bundled image rather than an
  /// icon or initials: a `child` is centred, a background fills the circle,
  /// and only the latter looks like an avatar.
  final ImageProvider? fallbackImage;
  final double? radius;
  final Color? foregroundColor;

  @override
  State<AdAvatar> createState() => _AdAvatarState();
}

class _AdAvatarState extends State<AdAvatar> {
  /// Set once the provider reports a failure, so the widget stops asking for
  /// an image that is not coming and shows [AdAvatar.fallback] instead.
  bool _loadFailed = false;

  @override
  void didUpdateWidget(covariant AdAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A recycled tile pointing at a different person deserves a fresh attempt.
    if (oldWidget.photoUrl != widget.photoUrl) {
      _loadFailed = false;
    }
  }

  String get _url => widget.photoUrl.trim();

  bool get _canShowPhoto => _url.isNotEmpty && !_loadFailed;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: widget.backgroundColor,
      foregroundColor: widget.foregroundColor,
      backgroundImage: _canShowPhoto
          ? CachedNetworkImageProvider(_url)
          : widget.fallbackImage,
      onBackgroundImageError: _canShowPhoto
          ? (_, _) {
              // Runs from the image stream, which can fire during layout —
              // hence the post-frame hop rather than a direct setState.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || _loadFailed) return;
                setState(() => _loadFailed = true);
              });
            }
          : null,
      child: _canShowPhoto || widget.fallbackImage != null
          ? null
          : widget.fallback,
    );
  }
}
