import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('android release builds stay optimized for staging and production', () {
    final gradle = File('android/app/build.gradle').readAsStringSync();
    final settingsGradle = File('android/settings.gradle').readAsStringSync();
    final wrapper = File('android/gradle/wrapper/gradle-wrapper.properties')
        .readAsStringSync();

    expect(settingsGradle, contains('com.android.application" version "8.6.'));
    expect(wrapper, contains('gradle-8.9-bin.zip'));
    expect(gradle, contains('compileSdk = 35'));
    expect(gradle, contains('targetSdk = 35'));
    expect(gradle, contains('buildToolsVersion = "35.0.0"'));
    expect(gradle, contains('ndkVersion = "29.0.13599879"'));
    expect(gradle, contains('minifyEnabled true'));
    expect(gradle, contains('shrinkResources true'));
    expect(gradle, contains('useLegacyPackaging true'));
    expect(
        gradle, contains('rootProject.file(keystoreProperties["storeFile"])'));
    expect(gradle, isNot(contains('enableReleaseOptimization')));
    expect(gradle, isNot(contains('isStagingReleaseTask')));
  });

  test('android readiness gate enforces release optimization', () {
    final script =
        File('scripts/check-android-release-readiness.ps1').readAsStringSync();

    expect(script, contains('minifyEnabled=true'));
    expect(script, contains('shrinkResources=true'));
    expect(script, contains('JDK 17'));
    expect(script, contains('cmdline-tools/latest/bin/sdkmanager.bat'));
    expect(script, contains('AGP 8.6.x'));
    expect(script, contains(r'$expectedBuildToolsVersion = "35.0.0"'));
    expect(script, contains(r'$expectedNdkVersion = "29.0.13599879"'));
    expect(script, contains('16 KB page-size'));
    expect(script, contains('useLegacyPackaging=true'));
    expect(script, contains('release keystore SHA-256'));
    expect(script, contains('assetlinks.json fingerprint for org.adfoot.app'));
    expect(script, contains('storeFile relative to the android rootProject'));
    expect(script, contains('UTF-8 BOM'));
  });

  test('production release config keeps App Check enabled', () {
    final productionTemplate =
        File('config/mobile/production.example.json').readAsStringSync();
    final productionNextTemplate =
        File('config/mobile/production-next.example.json').readAsStringSync();
    final productionEnv = File('functions/.env.production').readAsStringSync();
    final mobileConfigCheck =
        File('scripts/check-mobile-firebase-config.ps1').readAsStringSync();
    final buildScript =
        File('scripts/build-android-release.ps1').readAsStringSync();
    final runScript =
        File('scripts/flutter-run-mobile-env.ps1').readAsStringSync();
    final appCheckService =
        File('lib/services/app_check_service.dart').readAsStringSync();
    final packageJson = File('package.json').readAsStringSync();
    final appCheckDebugScript =
        File('scripts/configure-mobile-appcheck-debug.mjs').readAsStringSync();
    final mobileConfigReadme =
        File('config/mobile/README.md').readAsStringSync();
    final gitignore = File('.gitignore').readAsStringSync();

    expect(productionTemplate, contains('"APP_CHECK_ENABLED": "true"'));
    expect(productionNextTemplate, contains('"APP_CHECK_ENABLED": "true"'));
    expect(productionEnv, contains('ENFORCE_APPCHECK=true'));
    expect(mobileConfigCheck, contains('APP_CHECK_ENABLED must be true'));
    expect(buildScript, contains('Missing required mobile config file'));
    expect(buildScript, contains('Mobile config APP_ENV'));
    expect(buildScript, contains('APP_CHECK_ENABLED must be true'));
    expect(buildScript, contains(r'$dartDefines["APP_ENV"] = $Environment'));
    expect(runScript, contains('function Mask-PreviewArg'));
    expect(runScript, contains('KEY|SECRET|TOKEN|PASSWORD'));
    expect(appCheckService, contains('APP_CHECK_ANDROID_PROVIDER'));
    expect(appCheckService, contains('TargetPlatform.android'));
    expect(appCheckService, contains('AndroidDebugProvider'));
    expect(appCheckService, contains('AndroidPlayIntegrityProvider'));
    expect(packageJson, contains('mobile:appcheck:debug:production'));
    expect(appCheckDebugScript, contains('firebaseappcheck.googleapis.com'));
    expect(appCheckDebugScript, contains('APP_CHECK_ANDROID_DEBUG_TOKEN'));
    expect(appCheckDebugScript, contains('--write-config'));
    expect(appCheckDebugScript,
        contains('Debug token: <written to ignored local config>'));
    expect(appCheckDebugScript, isNot(contains('Debug token: \${token}')));
    expect(mobileConfigReadme, contains('Pre-Play-Store App Check validation'));
    expect(gitignore, contains('/config/mobile/*.json'));
  });

  test('production app links include public domain auth actions', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(manifest, contains('android:host="adfoot.org"'));
    expect(manifest, contains('android:pathPrefix="/__/auth/action"'));
    expect(manifest, contains('android:pathPrefix="/v"'));
  });

  test('android signing setup command generates the upload keystore', () {
    final packageJson = File('package.json').readAsStringSync();
    final setupScript =
        File('scripts/setup-android-signing.ps1').readAsStringSync();

    expect(
        packageJson, contains('setup-android-signing.ps1 -GenerateKeystore'));
    expect(
        packageJson,
        contains(
            'build-android-release.ps1 -Environment production -ReleaseGate -Clean'));
    expect(
        packageJson,
        contains(
            'setup-android-signing.ps1 -GenerateKeystore -RegenerateKeystore -Force'));
    expect(setupScript, contains('New StorePassword'));
    expect(setupScript, contains('at least 12 characters'));
    expect(setupScript, contains('Get-RelativePathCompat'));
    expect(setupScript, contains('UTF8Encoding(\$false)'));
    expect(setupScript, contains('WriteAllLines'));
    expect(setupScript, contains('Keystore already exists, reusing it'));
    expect(setupScript,
        contains('android/key.properties already exists, refreshing it'));
    expect(setupScript, contains('L=Bamako, ST=Bamako, C=ML'));
    expect(setupScript,
        contains('-RegenerateKeystore requires -GenerateKeystore'));
    expect(setupScript, isNot(contains('[System.IO.Path]::GetRelativePath')));
  });

  test(
      'android release build accepts only validated Flutter debug-symbol false negatives',
      () {
    final buildScript =
        File('scripts/build-android-release.ps1').readAsStringSync();

    expect(buildScript, contains('Test-AabContainsFlutterDebugSymbols'));
    expect(buildScript, contains('Clear-AndroidAppBundleOutput'));
    expect(buildScript, contains('Clear-GeneratedBuildDirectory'));
    expect(buildScript, contains('ConvertTo-LongPath'));
    expect(buildScript, contains('New-AndroidReleaseBuildLock'));
    expect(buildScript, contains('Assert-NoConflictingAndroidBuildProcess'));
    expect(
        buildScript,
        contains(
            'BUNDLE-METADATA/com\\.android\\.tools\\.build\\.debugsymbols'));
    expect(buildScript, contains('Get-AndroidAppBundleVariantDirectory'));
    expect(buildScript, contains('wasProducedByThisBuild'));
    expect(
        buildScript,
        contains(
            'apkanalyzer/cmdline-tools debug-symbol check false negative'));
  });
}
