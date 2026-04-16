import 'package:adfoot/config/app_environment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults remain production-safe', () {
    expect(AppEnvironmentConfig.environment, AppEnvironment.production);
    expect(AppEnvironmentConfig.useFirebaseEmulators, isFalse);
    expect(
      AppEnvironmentConfig.emailLinkHost,
      '${AppEnvironmentConfig.firebaseProjectId}.firebaseapp.com',
    );
    expect(
      AppEnvironmentConfig.emailLinkAllowedHosts,
      contains('${AppEnvironmentConfig.firebaseProjectId}.firebaseapp.com'),
    );
    expect(
      AppEnvironmentConfig.emailLinkAllowedHosts,
      contains('${AppEnvironmentConfig.firebaseProjectId}.web.app'),
    );
  });
}
