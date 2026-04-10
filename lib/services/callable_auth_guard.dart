import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CallableAuthGuard {
  CallableAuthGuard._();

  static Future<void> prepareCall({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    await user.getIdToken(forceRefresh);
  }

  static Future<HttpsCallableResult<T>> call<T>(
    HttpsCallable callable, [
    dynamic parameters,
  ]) async {
    await prepareCall();

    try {
      return await callable.call<T>(parameters);
    } on FirebaseFunctionsException catch (error) {
      if (!_shouldRetry(error)) {
        rethrow;
      }

      await prepareCall(forceRefresh: true);
      return callable.call<T>(parameters);
    }
  }

  static bool _shouldRetry(FirebaseFunctionsException error) {
    return error.code == 'unauthenticated' || error.code == 'permission-denied';
  }
}
