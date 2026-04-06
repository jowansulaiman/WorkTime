import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig._();

  static const bool disableAuthentication = bool.fromEnvironment(
    'APP_DISABLE_AUTH',
    defaultValue: false,
  );

  static const String defaultOrganizationId = String.fromEnvironment(
    'APP_DEFAULT_ORG_ID',
    defaultValue: 'main-org',
  );

  static const String defaultOrganizationName = String.fromEnvironment(
    'APP_DEFAULT_ORG_NAME',
    defaultValue: 'Worktime',
  );

  static const String bootstrapAdminEmails = String.fromEnvironment(
    'APP_BOOTSTRAP_ADMIN_EMAILS',
    defaultValue: '',
  );

  static const String firebaseFunctionsRegion = String.fromEnvironment(
    'FIREBASE_FUNCTIONS_REGION',
    defaultValue: 'europe-west3',
  );

  static List<String> get bootstrapAdminEmailList => bootstrapAdminEmails
      .split(',')
      .map((value) => value.trim().toLowerCase())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);

  static void validateEnvironment() {
    if (kReleaseMode && disableAuthentication) {
      throw StateError(
        'APP_DISABLE_AUTH darf in Release-Builds nicht aktiviert sein.',
      );
    }
  }
}
