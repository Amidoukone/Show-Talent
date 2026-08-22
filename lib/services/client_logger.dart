import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../config/app_environment.dart';
import 'callable_auth_guard.dart';

class ClientLogEntry {
  final String level;
  final String source;
  final String message;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  ClientLogEntry({
    required this.level,
    required this.source,
    required this.message,
    this.metadata,
  }) : createdAt = DateTime.now();

  Map<String, dynamic> toJson() => {
        'level': level,
        'source': source,
        'message': message,
        'metadata': metadata ?? {},
        'createdAt': createdAt.toIso8601String(),
      };
}

class ClientLogger {
  ClientLogger._internal();
  static final ClientLogger instance = ClientLogger._internal();

  final List<ClientLogEntry> _buffer = [];
  Timer? _flushTimer;
  bool _flushing = false;

  /// Hard cap on the retry buffer.
  ///
  /// A failed flush puts its whole batch back at the head of the queue, and
  /// the flush that fails is precisely the one running on a broken network —
  /// where new entries keep arriving because everything else is failing too.
  /// Unbounded, that queue grew for as long as the outage lasted, and each
  /// retry then tried to ship the entire accumulated history in one callable
  /// payload. Diagnostics must never be able to become the incident: past
  /// this many entries the oldest are dropped.
  static const int _maxBufferedEntries = 200;

  // Résolu à l'usage. En champ initialisé, il s'exécutait à la construction
  // du singleton — c'est-à-dire au tout premier `ClientLogger.instance`, y
  // compris sur un chemin d'erreur atteint avant que Firebase ne soit
  // démarré. Le service chargé de rapporter les pannes lançait alors sa
  // propre exception, et l'erreur d'origine disparaissait derrière.
  FirebaseFunctions get _functions => FirebaseFunctions.instanceFor(
    region: AppEnvironmentConfig.functionsRegion,
  );

  Future<void> logInfo(String source, String message,
      {Map<String, dynamic>? metadata}) async {
    _enqueue(ClientLogEntry(
        level: 'info', source: source, message: message, metadata: metadata));
  }

  Future<void> logError(String source, String message,
      {Map<String, dynamic>? metadata}) async {
    _enqueue(ClientLogEntry(
        level: 'error', source: source, message: message, metadata: metadata));
  }

  void _enqueue(ClientLogEntry entry) {
    _buffer.add(entry);
    _trimBuffer();

    if (_buffer.length >= 10) {
      unawaited(_flush());
      return;
    }

    _flushTimer ??= Timer(const Duration(seconds: 3), () {
      unawaited(_flush());
    });
  }

  Future<void> flushNow() async => _flush();

  Future<void> _flush() async {
    if (_flushing || _buffer.isEmpty) return;

    _flushTimer?.cancel();
    _flushTimer = null;
    _flushing = true;

    // Capture le batch courant pour éviter les pertes en cas d’échec
    final payload = _buffer.toList();
    _buffer.clear();

    try {
      final callable = _functions.httpsCallable(
        'logClientEvents',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 6)),
      );
      await CallableAuthGuard.call(callable, {
        'entries': payload.map((e) => e.toJson()).toList(),
        'context': _deviceContext(),
      });
    } catch (_) {
      // Remettre en file pour une prochaine tentative
      _buffer.insertAll(0, payload);
      _trimBuffer();
      _flushTimer ??= Timer(const Duration(seconds: 8), () {
        unawaited(_flush());
      });
    } finally {
      _flushing = false;
    }
  }

  /// Drops the oldest entries once the buffer exceeds its cap.
  void _trimBuffer() {
    final overflow = _buffer.length - _maxBufferedEntries;
    if (overflow > 0) {
      _buffer.removeRange(0, overflow);
    }
  }

  Map<String, dynamic> _deviceContext() {
    if (kIsWeb) {
      return {'platform': 'web'};
    }
    final platformName = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
    return {
      'platform': platformName,
    };
  }
}
