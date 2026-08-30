import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:adfoot/services/app_logger.dart';

/// Which version of the terms this app requires, and where to read them.
///
/// Two sources, on purpose:
///
/// - [bundledVersion] ships with the build and is what the app falls back to
///   when the network is down or `config/legal` has never been written. A
///   first launch on a dead connection must still be able to state *which*
///   text the user is accepting.
/// - `config/legal` in Firestore can raise it without a release. Article 18 of
///   the terms promises users are told in the app before a substantial change
///   takes effect; that promise is unkeepable if honouring it requires
///   shipping a build and waiting for the fleet to update.
///
/// A version is compared as an opaque string, never ordered: the question is
/// only "is this the text the user accepted", and any difference means no.
class TermsConfig {
  const TermsConfig({
    required this.requiredVersion,
    required this.termsUrl,
    required this.privacyUrl,
    required this.effectiveOn,
  });

  final String requiredVersion;
  final String termsUrl;
  final String privacyUrl;

  /// Human-readable date shown next to the version, or an empty string.
  final String effectiveOn;

  /// The version this build requires on its own, before any config is read.
  ///
  /// Empty on purpose, and it is the switch that keeps the release and the
  /// legal publication independent.
  ///
  /// The gate points users at adfoot.org/legal/terms.html. Shipping it before
  /// that page exists would send every user to a 404 and ask them to accept a
  /// text they cannot read — worse than no gate at all. So the app ships with
  /// the gate dormant, and it is switched on for the whole fleet by writing
  /// `config/legal.requiredVersion` the day the terms are published, with no
  /// new build and no wait for the fleet to update.
  ///
  /// Failing open is deliberate here: consent is a legal requirement, but a
  /// consent screen that cannot resolve its own requirement must not lock
  /// paying-attention users out of an app that otherwise works.
  static const String bundledVersion = '';
  static const String bundledTermsUrl = 'https://adfoot.org/legal/terms.html';
  static const String bundledPrivacyUrl =
      'https://adfoot.org/legal/privacy-policy.html';

  static const TermsConfig bundled = TermsConfig(
    requiredVersion: bundledVersion,
    termsUrl: bundledTermsUrl,
    privacyUrl: bundledPrivacyUrl,
    effectiveOn: '',
  );

  /// Reads `config/legal`, ignoring anything malformed.
  ///
  /// A blank or non-string version leaves [bundledVersion] in place rather
  /// than locking the whole fleet out of the app behind a version nobody can
  /// ever match. The same reasoning applies to the URLs: a broken link is
  /// better replaced by the one that shipped than by nothing at all.
  factory TermsConfig.fromData(Map<String, dynamic> data) {
    String pick(String key, String fallback) {
      final raw = data[key];
      if (raw is! String) return fallback;
      final trimmed = raw.trim();
      return trimmed.isEmpty ? fallback : trimmed;
    }

    return TermsConfig(
      requiredVersion: pick('requiredVersion', bundledVersion),
      termsUrl: pick('termsUrl', bundledTermsUrl),
      privacyUrl: pick('privacyUrl', bundledPrivacyUrl),
      effectiveOn: pick('effectiveOn', ''),
    );
  }

  /// True while no acceptance is required at all.
  ///
  /// See [bundledVersion]: an empty required version means the terms are not
  /// published yet, or the config could not be read.
  bool get isGateActive => requiredVersion.trim().isNotEmpty;

  /// True when [acceptedVersion] satisfies this config.
  bool isSatisfiedBy(String? acceptedVersion) {
    if (!isGateActive) return true;
    final accepted = acceptedVersion?.trim() ?? '';
    return accepted.isNotEmpty && accepted == requiredVersion;
  }
}

class TermsAcceptanceService {
  TermsAcceptanceService({FirebaseFirestore? firestore})
    : _injectedFirestore = firestore;

  /// Resolved on use, like the other services in this codebase: constructing
  /// one must not require a live Firebase app, or nothing that depends on it
  /// can be built in a test.
  final FirebaseFirestore? _injectedFirestore;

  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  static const Duration _cacheTtl = Duration(minutes: 15);

  TermsConfig _cached = TermsConfig.bundled;
  DateTime _lastFetch = DateTime.fromMillisecondsSinceEpoch(0);

  TermsConfig get cached => _cached;

  /// The current config, refreshed at most once per [_cacheTtl].
  ///
  /// Never throws and never returns null: a gate that cannot resolve its own
  /// requirement must fall back to letting the user in with the version the
  /// build shipped, not to locking the app.
  Future<TermsConfig> fetchConfig({bool force = false}) async {
    final now = DateTime.now();
    if (!force && now.difference(_lastFetch) < _cacheTtl) {
      return _cached;
    }

    try {
      final doc = await _firestore.collection('config').doc('legal').get();
      _cached = TermsConfig.fromData(doc.data() ?? const <String, dynamic>{});
      _lastFetch = now;
    } catch (error, stackTrace) {
      // `config/*` is world-readable, so a failure here is a network problem,
      // not a permission one. Logged rather than swallowed because a config
      // this gate depends on silently never loading is exactly the kind of
      // thing that only shows up as "some users were asked twice".
      AppLogger.warning(
        'legal config unavailable; falling back to the bundled terms version',
        source: 'legal/config',
        error: error,
        stackTrace: stackTrace,
      );
    }

    return _cached;
  }

  @visibleForTesting
  void resetForTests() {
    _cached = TermsConfig.bundled;
    _lastFetch = DateTime.fromMillisecondsSinceEpoch(0);
  }
}
