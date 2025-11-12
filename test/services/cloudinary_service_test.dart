import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:paisabai_app/services/cloudinary_service.dart';

void _loadEnv(Map<String, String> entries) {
  final buffer = StringBuffer();
  entries.forEach((key, value) => buffer.writeln('$key=$value'));
  dotenv.testLoad(fileInput: buffer.toString());
}

Future<File> _createTempImage() async {
  final file = File(
    '${Directory.systemTemp.path}/cloudinary_test_${DateTime.now().microsecondsSinceEpoch}.jpg',
  );
  await file.writeAsBytes(List<int>.generate(10, (index) => index));
  return file;
}

void main() {
  setUp(() {
    _loadEnv({});
    CloudinaryService.resetDependencies();
  });

  group('CloudinaryService URL helpers', () {
    test('return empty strings when Cloudinary config is missing', () {
      expect(CloudinaryService.getProfileImageUrl('user1'), isEmpty);
      expect(CloudinaryService.getOptimizedImageUrl('public_id'), isEmpty);
      expect(CloudinaryService.getAvatarUrl('Avatar'), isEmpty);
    });

    test('builds profile image URLs with defaults', () {
      _loadEnv({
        'CLOUDINARY_CLOUD_NAME': 'demo',
        'CLOUDINARY_BASE_IMAGE_PATH': 'paisabai',
      });

      final url = CloudinaryService.getProfileImageUrl('user123');

      expect(
        url,
        'https://res.cloudinary.com/demo/image/upload/paisabai/w_200,h_200,c_fill,g_face/profiles/profile_user123.jpg',
      );
    });

    test('builds profile image URLs with custom dimensions', () {
      _loadEnv({
        'CLOUDINARY_CLOUD_NAME': 'demo',
        'CLOUDINARY_BASE_IMAGE_PATH': 'paisabai',
      });

      final url = CloudinaryService.getProfileImageUrl('user123', width: 400, height: 300);

      expect(
        url,
        'https://res.cloudinary.com/demo/image/upload/paisabai/w_400,h_300,c_fill,g_face/profiles/profile_user123.jpg',
      );
    });

    test('builds optimized URLs for arbitrary public IDs', () {
      _loadEnv({
        'CLOUDINARY_CLOUD_NAME': 'demo',
        'CLOUDINARY_BASE_IMAGE_PATH': 'paisabai',
      });

      final url = CloudinaryService.getOptimizedImageUrl('my/public/id', width: 500, height: 500);

      expect(url,
          'https://res.cloudinary.com/demo/image/upload/paisabai/w_500,h_500,c_fill/my/public/id');
    });

    test('returns all supported avatar options', () {
      expect(
        CloudinaryService.getAvatarOptions(),
        equals([
          'Avatar',
          'Avatar-2',
          'Avatar-3',
          'Avatar-4',
          'Avatar-5',
          'Avatar-6',
          'Avatar-7',
          'Avatar-8',
          'Avatar-9',
        ]),
      );
    });

    test('builds avatar URLs when Cloudinary config exists', () {
      _loadEnv({
        'CLOUDINARY_CLOUD_NAME': 'demo',
        'CLOUDINARY_BASE_IMAGE_PATH': 'paisabai',
      });

      final url = CloudinaryService.getAvatarUrl('Avatar-3', width: 256, height: 256);
      expect(url,
          'https://res.cloudinary.com/demo/image/upload/paisabai/w_256,h_256,c_fill/avatars/Avatar-3.png');
    });
  });

  group('CloudinaryService uploadProfileImage', () {
    late File tempImage;

    setUp(() async {
      tempImage = await _createTempImage();
    });

    tearDown(() async {
      if (await tempImage.exists()) {
        await tempImage.delete();
      }
    });

    test('returns null when configuration is missing', () async {
      final result = await CloudinaryService.uploadProfileImage(tempImage, 'user123');
      expect(result, isNull);
    });

    test('returns secure_url when upload succeeds', () async {
      _loadEnv({
        'CLOUDINARY_CLOUD_NAME': 'demo',
        'CLOUDINARY_UPLOAD_PRESET': 'preset',
      });

      CloudinaryService.configure(
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.toString(), contains('/demo/image/upload'));
          expect(request.body, contains('preset'));
          return http.Response(
            '{"secure_url":"https://res.cloudinary.com/demo/image/upload/sample.jpg"}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await CloudinaryService.uploadProfileImage(tempImage, 'user123');

      expect(result, 'https://res.cloudinary.com/demo/image/upload/sample.jpg');
    });

    test('returns null when Cloudinary responds with non-200 status', () async {
      _loadEnv({
        'CLOUDINARY_CLOUD_NAME': 'demo',
        'CLOUDINARY_UPLOAD_PRESET': 'preset',
      });

      CloudinaryService.configure(
        httpClient: MockClient((request) async => http.Response('error', 500)),
      );

      final result = await CloudinaryService.uploadProfileImage(tempImage, 'user123');

      expect(result, isNull);
    });

    test('returns null when the HTTP client throws', () async {
      _loadEnv({
        'CLOUDINARY_CLOUD_NAME': 'demo',
        'CLOUDINARY_UPLOAD_PRESET': 'preset',
      });

      CloudinaryService.configure(
        httpClient: MockClient((request) async => throw Exception('network failure')),
      );

      final result = await CloudinaryService.uploadProfileImage(tempImage, 'user123');

      expect(result, isNull);
    });
  });
}
