import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../config/app_environment.dart';

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

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
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
      await callable.call({
        'entries': payload.map((e) => e.toJson()).toList(),
        'context': _deviceContext(),
      });
    } catch (_) {
      // Remettre en file pour une prochaine tentative
      _buffer.insertAll(0, payload);
      _flushTimer ??= Timer(const Duration(seconds: 8), () {
        unawaited(_flush());
      });
    } finally {
      _flushing = false;
    }
  }

  Map<String, dynamic> _deviceContext() {
    if (kIsWeb) {
      return {'platform': 'web'};
    }
    return {
      'platform': Platform.operatingSystem,
      'version': Platform.operatingSystemVersion,
    };
  }
}
