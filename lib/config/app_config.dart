import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  // Firebase Configuration
  static String get firebaseApiKeyWeb => dotenv.env['FIREBASE_API_KEY_WEB'] ?? '';
  static String get firebaseApiKeyAndroid => dotenv.env['FIREBASE_API_KEY_ANDROID'] ?? '';
  static String get firebaseApiKeyIos => dotenv.env['FIREBASE_API_KEY_IOS'] ?? '';
  static String get firebaseAppIdWeb => dotenv.env['FIREBASE_APP_ID_WEB'] ?? '';
  static String get firebaseAppIdAndroid => dotenv.env['FIREBASE_APP_ID_ANDROID'] ?? '';
  static String get firebaseAppIdIos => dotenv.env['FIREBASE_APP_ID_IOS'] ?? '';
  static String get firebaseMessagingSenderId => dotenv.env['FIREBASE_MESSAGING_SENDER_ID'] ?? '';
  static String get firebaseProjectId => dotenv.env['FIREBASE_PROJECT_ID'] ?? '';
  static String get firebaseStorageBucket => dotenv.env['FIREBASE_STORAGE_BUCKET'] ?? '';
  static String get firebasebundleiosId => dotenv.env['FIREBASE_BUNDLE_IOS_ID'] ?? '';
  // Cloudinary Configuration
  static String get cloudinaryCloudName => dotenv.env['CLOUDINARY_CLOUD_NAME'] ?? '';
  static String get cloudinaryUploadPreset => dotenv.env['CLOUDINARY_UPLOAD_PRESET'] ?? '';
  static String get cloudinaryBaseImagePath =>
      dotenv.env['CLOUDINARY_BASE_IMAGE_PATH'] ?? 'paisabai';
  
  static bool get enablePerformanceOverlay =>
      (dotenv.env['SHOW_PERFORMANCE_OVERLAY'] ?? 'false').toLowerCase() == 'true';
  
  static bool get logSlowFrames =>
      (dotenv.env['LOG_SLOW_FRAMES'] ?? 'false').toLowerCase() == 'true';
  
  static Duration get slowFrameThreshold {
    final raw = int.tryParse(dotenv.env['SLOW_FRAME_THRESHOLD_MS'] ?? '');
    if (raw == null || raw <= 0) {
      return const Duration(milliseconds: 16);
    }
    return Duration(milliseconds: raw);
  }
}
