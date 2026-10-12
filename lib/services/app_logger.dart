import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, kReleaseMode;

import '../config/app_environment.dart';
import 'client_logger.dart';

enum AppLogLevel { debug, info, warning, error }

class AppLogger {
  AppLogger._();

  static final Random _random = Random();

  static const double productionInfoSampleRate = 0.02;

  /// Part des avertissements reellement transmis a `client_logs`, en pourcent.
  ///
  /// Un reglage, pas une constante, parce que la bonne valeur depend du
  /// nombre d'appareils et change donc deux fois dans la vie du produit.
  ///
  /// 15 % est juste pour une application installee des milliers de fois : le
  /// taux d'un defaut se lit tres bien sur un echantillon, et tout envoyer
  /// coute des ecritures Firestore pour rien. Avec trois testeurs, c'est
  /// l'inverse d'un reglage : un defaut qui survient une fois par session est
  /// vu environ une session sur sept, et l'absence de trace se lit comme une
  /// absence de probleme. Ce raisonnement exact figure deux fois dans le
  /// registre des notifications iOS -- « il n'a rien journalise, mais les
  /// avertissements sont echantillonnes, donc ce silence n'etait pas une
  /// preuve » -- et il a coute des tours de build.
  ///
  /// A 100 pendant la phase d'appareils et le lancement, ou le dépôt compte
  /// 117 appels `AppLogger.warning` contre 17 `AppLogger.error`. Le cout est
  /// borne de trois cotes : 20 appels/minute/utilisateur
  /// (`enforceCallRateLimit`), 50 entrees par appel, et une expiration
  /// automatique (90 jours pour les erreurs, 30 pour la telemetrie).
  ///
  /// **A redescendre quand le volume d'installations le justifiera**, sans
  /// toucher au code :
  /// `flutter build ... --dart-define=CLIENT_LOG_WARNING_SAMPLE_PERCENT=15`.
  /// C'est une entree de la liste de controle avant deploiement public, pas
  /// une decision a reprendre ici.
  static const int warningSamplePercent = int.fromEnvironment(
    'CLIENT_LOG_WARNING_SAMPLE_PERCENT',
    defaultValue: 100,
  );

  static const double productionWarningSampleRate = warningSamplePercent / 100;

  static void debug(
    Object? message, {
    String source = 'app',
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    _log(
      AppLogLevel.debug,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
      metadata: metadata,
    );
  }

  static void info(
    Object? message, {
    String source = 'app',
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    _log(
      AppLogLevel.info,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
      metadata: metadata,
    );
  }

  static void warning(
    Object? message, {
    String source = 'app',
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    _log(
      AppLogLevel.warning,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
      metadata: metadata,
    );
  }

  /// For anything the user has already been told went wrong.
  ///
  /// The choice between this and [warning] is not about severity, it is about
  /// whether we will ever see it. [warning] is sampled at
  /// [productionWarningSampleRate] and [debug] is never sent at all, so a
  /// failure reported at either of those levels and *shown to the user* puts
  /// them in a position to describe a problem we have no record of.
  ///
  /// The rule this codebase settled on: if a screen says "impossible", if a
  /// capability is lost, or if the user lands somewhere other than where they
  /// asked to go, it is an `error` — regardless of how ordinary the cause is.
  /// Sampling is for telemetry about things that worked.
  static void error(
    Object? message, {
    String source = 'app',
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    _log(
      AppLogLevel.error,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
      metadata: metadata,
    );
  }

  static void _log(
    AppLogLevel level,
    Object? message, {
    required String source,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    final text = message?.toString() ?? '';

    if (kDebugMode) {
      debugPrint(text);
    }

    developer.log(
      text,
      name: source,
      level: _developerLevel(level),
      error: error,
      stackTrace: stackTrace,
    );

    if (!_shouldSendToRemote(level)) {
      return;
    }

    final sanitizedMetadata = _safeMetadata({
      'level': level.name,
      'error': error?.toString(),
      'stackTrace': stackTrace?.toString(),
      ...?metadata,
    });

    if (level == AppLogLevel.error || level == AppLogLevel.warning) {
      unawaited(
        ClientLogger.instance.logError(
          source,
          text,
          metadata: sanitizedMetadata,
        ),
      );
      return;
    }

    unawaited(
      ClientLogger.instance.logInfo(
        source,
        text,
        metadata: sanitizedMetadata,
      ),
    );
  }

  static bool _shouldSendToRemote(AppLogLevel level) {
    if (!kReleaseMode || !AppEnvironmentConfig.isProduction) {
      return false;
    }

    switch (level) {
      case AppLogLevel.error:
        return true;
      case AppLogLevel.warning:
        return _random.nextDouble() < productionWarningSampleRate;
      case AppLogLevel.info:
        return _random.nextDouble() < productionInfoSampleRate;
      case AppLogLevel.debug:
        return false;
    }
  }

  static int _developerLevel(AppLogLevel level) {
    switch (level) {
      case AppLogLevel.debug:
        return 500;
      case AppLogLevel.info:
        return 800;
      case AppLogLevel.warning:
        return 900;
      case AppLogLevel.error:
        return 1000;
    }
  }

  /// Plafond par valeur de métadonnée, en caractères.
  ///
  /// `logClientEvents` tronque déjà le *message* à 2000 caractères ; les
  /// métadonnées, elles, étaient recopiées telles quelles dans Firestore. Or
  /// c'est là que vivent `error.toString()` et surtout `stackTrace.toString()`,
  /// qui fait couramment plusieurs kilo-octets en release.
  ///
  /// Tant que les avertissements étaient échantillonnés à 15 %, le volume
  /// était borné par accident. Il ne l'est plus : [warningSamplePercent] est à
  /// 100 pour la phase d'appareils, et une pile non tronquée par entrée, sur
  /// un flux qui se redéclenche à chaque snapshot, est une facture Firestore
  /// avant d'être un diagnostic. Les premières lignes d'une pile disent où ;
  /// les suivantes disent par où, et ça ne vaut pas ce que ça coûte.
  ///
  /// Même plafond que le message, pour que les deux se lisent pareil.
  static const int maxMetadataValueLength = 2000;

  static Map<String, dynamic> _safeMetadata(Map<String, dynamic> raw) {
    return raw.map((key, value) {
      if (value == null || value is bool || value is num) {
        return MapEntry(key, value);
      }
      return MapEntry(key, _truncate(value is String ? value : value.toString()));
    })..removeWhere((_, value) => value == null);
  }

  /// Dit qu'elle a été coupée, plutôt que de laisser croire à une pile courte.
  static String _truncate(String value) {
    if (value.length <= maxMetadataValueLength) {
      return value;
    }
    return '${value.substring(0, maxMetadataValueLength)}… '
        '[tronqué, ${value.length} caractères]';
  }
}
