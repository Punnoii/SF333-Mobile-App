import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisabai_app/config/app_config.dart';

void _loadEnv(Map<String, String> entries) {
  final buffer = StringBuffer();
  entries.forEach((key, value) => buffer.writeln('$key=$value'));
  dotenv.testLoad(fileInput: buffer.toString());
}

void main() {
  setUp(() {
    _loadEnv({});
  });

  test('reads all configuration keys from .env', () {
    _loadEnv({
      'FIREBASE_API_KEY_WEB': 'web-key',
      'FIREBASE_API_KEY_ANDROID': 'android-key',
      'FIREBASE_API_KEY_IOS': 'ios-key',
      'FIREBASE_APP_ID_WEB': 'app-web',
      'FIREBASE_APP_ID_ANDROID': 'app-android',
      'FIREBASE_APP_ID_IOS': 'app-ios',
      'FIREBASE_MESSAGING_SENDER_ID': 'sender',
      'FIREBASE_PROJECT_ID': 'project-id',
      'FIREBASE_STORAGE_BUCKET': 'bucket',
      'FIREBASE_BUNDLE_IOS_ID': 'bundle-ios',
      'CLOUDINARY_CLOUD_NAME': 'demo',
      'CLOUDINARY_UPLOAD_PRESET': 'upload-preset',
      'FCM_SERVER_KEY': 'server-key',
    });

    expect(AppConfig.firebaseApiKeyWeb, 'web-key');
    expect(AppConfig.firebaseApiKeyAndroid, 'android-key');
    expect(AppConfig.firebaseApiKeyIos, 'ios-key');
    expect(AppConfig.firebaseAppIdWeb, 'app-web');
    expect(AppConfig.firebaseAppIdAndroid, 'app-android');
    expect(AppConfig.firebaseAppIdIos, 'app-ios');
    expect(AppConfig.firebaseMessagingSenderId, 'sender');
    expect(AppConfig.firebaseProjectId, 'project-id');
    expect(AppConfig.firebaseStorageBucket, 'bucket');
    expect(AppConfig.firebasebundleiosId, 'bundle-ios');
    expect(AppConfig.cloudinaryCloudName, 'demo');
    expect(AppConfig.cloudinaryUploadPreset, 'upload-preset');
    expect(AppConfig.fcmServerKey, 'server-key');
  });

  test('falls back to empty strings when variables are missing', () {
    expect(AppConfig.firebaseApiKeyWeb, isEmpty);
    expect(AppConfig.firebaseApiKeyAndroid, isEmpty);
    expect(AppConfig.firebaseApiKeyIos, isEmpty);
    expect(AppConfig.firebaseAppIdWeb, isEmpty);
    expect(AppConfig.firebaseAppIdAndroid, isEmpty);
    expect(AppConfig.firebaseAppIdIos, isEmpty);
    expect(AppConfig.firebaseMessagingSenderId, isEmpty);
    expect(AppConfig.firebaseProjectId, isEmpty);
    expect(AppConfig.firebaseStorageBucket, isEmpty);
    expect(AppConfig.firebasebundleiosId, isEmpty);
    expect(AppConfig.cloudinaryCloudName, isEmpty);
    expect(AppConfig.cloudinaryUploadPreset, isEmpty);
    expect(AppConfig.fcmServerKey, isEmpty);
  });
}
