import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();

  factory ConnectivityService() => _instance;

  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _subscription;

  ConnectivityService._internal() {
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final hasConnection = results.any((result) => result != ConnectivityResult.none);
      _controller.add(hasConnection);
    });

    // Émission initiale de l'état
    _connectivity.checkConnectivity().then((result) {
      final hasConnection = result != ConnectivityResult.none;
      _controller.add(hasConnection);
    });
  }

  /// Stream en temps réel de l'état de la connexion Internet
  Stream<bool> get connectionStream => _controller.stream;

  /// Vérifie l'état initial de connexion
  Future<bool> checkInitialConnection() async {
    final result = await _connectivity.checkConnectivity();
    return result != ConnectivityResult.none;
  }

  /// Nettoyage
  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }
}
