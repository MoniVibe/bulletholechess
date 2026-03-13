import 'package:flutter/foundation.dart';

/// Runtime configuration sourced from compile-time `--dart-define` values.
class AppRuntimeConfig {
  static const String _appEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'dev',
  );
  static const String _defaultBackendUrlOverride = String.fromEnvironment(
    'DEFAULT_BACKEND_URL',
    defaultValue:
        'https://matchmaker.agreeableground-86a00183.eastus2.azurecontainerapps.io',
  );
  static const String _devBackendUrl = String.fromEnvironment(
    'DEFAULT_BACKEND_URL_DEV',
    defaultValue: 'http://localhost:8080',
  );
  static const String _stagingBackendUrl = String.fromEnvironment(
    'DEFAULT_BACKEND_URL_STAGING',
    defaultValue: '',
  );
  static const String _productionBackendUrl = String.fromEnvironment(
    'DEFAULT_BACKEND_URL_PROD',
    defaultValue: '',
  );
  static const String _releaseFallbackBackendUrl = String.fromEnvironment(
    'DEFAULT_BACKEND_URL_RELEASE_FALLBACK',
    defaultValue:
        'https://matchmaker.agreeableground-86a00183.eastus2.azurecontainerapps.io',
  );

  static String get appEnv => _normalizedAppEnv(_appEnv);

  static String get defaultBackendUrl {
    final explicit = _normalizeUrl(_defaultBackendUrlOverride);
    if (explicit != null) {
      return explicit;
    }
    final envDefault = _defaultForEnv(appEnv);
    if (envDefault != null) {
      return envDefault;
    }
    return kReleaseMode ? _releaseFallbackBackendUrl : _devBackendUrl;
  }

  static String _normalizedAppEnv(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized == 'prod') {
      return 'production';
    }
    if (normalized == 'stage') {
      return 'staging';
    }
    if (normalized.isEmpty) {
      return 'dev';
    }
    return normalized;
  }

  static String? _defaultForEnv(String env) {
    switch (env) {
      case 'production':
        return _normalizeUrl(_productionBackendUrl);
      case 'staging':
        return _normalizeUrl(_stagingBackendUrl);
      default:
        return _normalizeUrl(_devBackendUrl);
    }
  }

  static String? _normalizeUrl(String candidate) {
    final trimmed = candidate.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
