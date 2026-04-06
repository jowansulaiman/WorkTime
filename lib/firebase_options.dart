import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static const String _androidApiKey = String.fromEnvironment(
    'FIREBASE_ANDROID_API_KEY',
  );
  static const String _androidAppId = String.fromEnvironment(
    'FIREBASE_ANDROID_APP_ID',
  );
  static const String _androidMessagingSenderId = String.fromEnvironment(
    'FIREBASE_ANDROID_MESSAGING_SENDER_ID',
  );
  static const String _androidProjectId = String.fromEnvironment(
    'FIREBASE_ANDROID_PROJECT_ID',
  );
  static const String _androidStorageBucket = String.fromEnvironment(
    'FIREBASE_ANDROID_STORAGE_BUCKET',
  );

  static const String _iosApiKey = String.fromEnvironment(
    'FIREBASE_IOS_API_KEY',
  );
  static const String _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const String _iosMessagingSenderId = String.fromEnvironment(
    'FIREBASE_IOS_MESSAGING_SENDER_ID',
  );
  static const String _iosProjectId = String.fromEnvironment(
    'FIREBASE_IOS_PROJECT_ID',
  );
  static const String _iosStorageBucket = String.fromEnvironment(
    'FIREBASE_IOS_STORAGE_BUCKET',
  );
  static const String _iosBundleId = String.fromEnvironment(
    'FIREBASE_IOS_BUNDLE_ID',
  );

  static const String _webApiKey =
      String.fromEnvironment('FIREBASE_WEB_API_KEY');
  static const String _webAppId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
  static const String _webMessagingSenderId = String.fromEnvironment(
    'FIREBASE_WEB_MESSAGING_SENDER_ID',
  );
  static const String _webProjectId = String.fromEnvironment(
    'FIREBASE_WEB_PROJECT_ID',
  );
  static const String _webAuthDomain = String.fromEnvironment(
    'FIREBASE_WEB_AUTH_DOMAIN',
  );
  static const String _webStorageBucket = String.fromEnvironment(
    'FIREBASE_WEB_STORAGE_BUCKET',
  );
  static const String _webMeasurementId = String.fromEnvironment(
    'FIREBASE_WEB_MEASUREMENT_ID',
  );

  static bool get isConfigured {
    if (kIsWeb) {
      return _areSet([
        _webApiKey,
        _webAppId,
        _webMessagingSenderId,
        _webProjectId,
        _webAuthDomain,
      ]);
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _areSet([
          _androidApiKey,
          _androidAppId,
          _androidMessagingSenderId,
          _androidProjectId,
        ]);
      case TargetPlatform.iOS:
        return _areSet([
          _iosApiKey,
          _iosAppId,
          _iosMessagingSenderId,
          _iosProjectId,
          _iosBundleId,
        ]);
      default:
        return false;
    }
  }

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return FirebaseOptions(
        apiKey: _webApiKey,
        appId: _webAppId,
        messagingSenderId: _webMessagingSenderId,
        projectId: _webProjectId,
        authDomain: _webAuthDomain,
        storageBucket: _emptyToNull(_webStorageBucket),
        measurementId: _emptyToNull(_webMeasurementId),
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return FirebaseOptions(
          apiKey: _androidApiKey,
          appId: _androidAppId,
          messagingSenderId: _androidMessagingSenderId,
          projectId: _androidProjectId,
          storageBucket: _emptyToNull(_androidStorageBucket),
        );
      case TargetPlatform.iOS:
        return FirebaseOptions(
          apiKey: _iosApiKey,
          appId: _iosAppId,
          messagingSenderId: _iosMessagingSenderId,
          projectId: _iosProjectId,
          storageBucket: _emptyToNull(_iosStorageBucket),
          iosBundleId: _iosBundleId,
        );
      default:
        throw UnsupportedError(
          'Firebase ist auf dieser Plattform in diesem Projekt nicht konfiguriert.',
        );
    }
  }

  static bool _areSet(List<String> values) => values.every((value) {
        final normalized = value.trim();
        return normalized.isNotEmpty &&
            normalized.toUpperCase() != 'REPLACE_ME' &&
            normalized.toUpperCase() != 'YOUR_VALUE_HERE';
      });

  static String? _emptyToNull(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty ||
        trimmed.toUpperCase() == 'REPLACE_ME' ||
        trimmed.toUpperCase() == 'YOUR_VALUE_HERE') {
      return null;
    }
    return trimmed;
  }
}
