import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kDebugMode;


class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;

  final Connectivity _connectivity = Connectivity();

  /// Diffuse `true` si au moins une interface est connectée (≠ none).
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _disposed = false;

  ConnectivityService._internal() {
    // Ecoute temps réel
    _subscription =
        _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final hasConnection = _hasConnection(results);
      _safeAdd(hasConnection);
    }, onError: (e, st) {
      _debugLog('onConnectivityChanged error', e, st);
      // En cas d'erreur de plugin, on ne spam pas le stream.
    });

    // Etat initial
    _connectivity.checkConnectivity().then((List<ConnectivityResult> results) {
      _safeAdd(_hasConnection(results));
    }).catchError((e, st) {
      _debugLog('checkConnectivity error', e, st);
      // On n’émet rien en cas d’erreur ponctuelle.
    });
  }

  /// Stream en temps réel de l'état de la connexion Internet (distinct pour éviter les doublons).
  Stream<bool> get connectionStream => _controller.stream.distinct();

  /// Vérifie l'état initial de connexion (snapshot instantané).
  Future<bool> checkInitialConnection() async {
    final results = await _connectivity.checkConnectivity(); // v6 -> List<ConnectivityResult>
    return _hasConnection(results);
  }

  /// Nettoyage (à appeler si tu veux libérer explicitement le service).
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _subscription?.cancel();
    _subscription = null;
    _controller.close();
  }

  // ---------- Helpers privés ----------

  bool _hasConnection(List<ConnectivityResult> results) {
    // Toute interface ≠ none => connecté (wifi, mobile, ethernet, vpn, bluetooth, other...)
    return results.any((r) => r != ConnectivityResult.none);
  }

  void _safeAdd(bool value) {
    if (_disposed) return;
    // .add peut throw si le controller est fermé => on protège
    try {
      _controller.add(value);
    } catch (_) {
      // ignore silencieusement en prod
      _debugLog('StreamController already closed while adding value');
    }
  }

  void _debugLog(String msg, [Object? error, StackTrace? st]) {
    if (!kDebugMode) return;
    // ignore: avoid_print
    print('[ConnectivityService] $msg'
        '${error != null ? ' | error: $error' : ''}'
        '${st != null ? '\n$st' : ''}');
  }
}
