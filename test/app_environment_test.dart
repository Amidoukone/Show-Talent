import 'package:adfoot/config/app_environment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults remain production-safe', () {
    expect(AppEnvironmentConfig.environment, AppEnvironment.production);
    expect(AppEnvironmentConfig.useFirebaseEmulators, isFalse);
    expect(
      AppEnvironmentConfig.emailVerificationActionUrl,
      'https://adfoot.org/verify',
    );
    expect(
      AppEnvironmentConfig.passwordResetActionUrl,
      'https://adfoot.org/reset',
    );
    expect(
      AppEnvironmentConfig.emailLinkAllowedHosts,
      contains('${AppEnvironmentConfig.firebaseProjectId}.firebaseapp.com'),
    );
    expect(
      AppEnvironmentConfig.emailLinkAllowedHosts,
      contains('${AppEnvironmentConfig.firebaseProjectId}.web.app'),
    );
    expect(AppEnvironmentConfig.emailLinkAllowedHosts, contains('adfoot.org'));
  });
}
