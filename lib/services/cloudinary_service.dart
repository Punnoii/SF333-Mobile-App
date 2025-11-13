import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import '../config/app_config.dart';
import 'logging_service.dart';
import 'monitoring_service.dart';

class CloudinaryService {
  static const String _logCategory = 'CloudinaryService';
  static String get _cloudName => AppConfig.cloudinaryCloudName;
  static String get _uploadPreset => AppConfig.cloudinaryUploadPreset;
  static http.Client _httpClient = NetworkTrackedClient();

  static String get _baseUploadUrl =>
      _cloudName.isEmpty ? '' : 'https://api.cloudinary.com/v1_1/$_cloudName/image/upload';

  static String get _baseImageUrl {
    final basePath = AppConfig.cloudinaryBaseImagePath;
    if (_cloudName.isEmpty || basePath.isEmpty) return '';
    return 'https://res.cloudinary.com/$_cloudName/image/upload/$basePath';
  }

  /// Allow injecting a custom HTTP client (useful for tests).
  @visibleForTesting
  static void configure({http.Client? httpClient}) {
    if (httpClient != null) {
      _httpClient = httpClient;
    }
  }

  @visibleForTesting
  static void resetDependencies() {
    _httpClient = NetworkTrackedClient();
  }

  static Future<String?> uploadProfileImage(File imageFile, String userId) async {
    return ServiceJobScope.run('CloudinaryService.uploadProfileImage', () async {
      if (_cloudName.isEmpty || _uploadPreset.isEmpty) {
        LoggingService.warning(
          'Missing Cloudinary configuration. Check CLOUDINARY_* entries in .env',
          category: _logCategory,
        );
        return null;
      }

      try {
        final url = Uri.parse(_baseUploadUrl);
        
        final request = http.MultipartRequest('POST', url);
        request.fields['upload_preset'] = _uploadPreset;
        
        final file = await http.MultipartFile.fromPath('file', imageFile.path);
        request.files.add(file);
        
        // Add timeout to prevent hanging uploads
        final response = await _httpClient.send(request).timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw Exception('Upload request timed out');
          },
        );
        
        if (response.statusCode == 200) {
          final responseData = await response.stream.bytesToString().timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception('Response reading timed out');
            },
          );
          final jsonData = json.decode(responseData);
          return jsonData['secure_url'];
        } else {
          final responseData = await response.stream.bytesToString().timeout(
            const Duration(seconds: 5),
            onTimeout: () => 'Response timeout',
          );
          LoggingService.warning(
            'Cloudinary upload failed (${response.statusCode}): $responseData, fields: ${request.fields}',
            category: _logCategory,
          );
          return null;
        }
      } catch (e, stack) {
        LoggingService.error(
          'Cloudinary upload error',
          error: e,
          stackTrace: stack,
          category: _logCategory,
        );
        return null;
      }
    });
  }

  static String getProfileImageUrl(String userId, {int width = 200, int height = 200}) {
    if (_baseImageUrl.isEmpty) return '';
    return '$_baseImageUrl/w_$width,h_$height,c_fill,g_face/profiles/profile_$userId.jpg';
  }

  static String getOptimizedImageUrl(String publicId, {int width = 200, int height = 200}) {
    if (_baseImageUrl.isEmpty) return '';
    return '$_baseImageUrl/w_$width,h_$height,c_fill/$publicId';
  }

  // Get list of available avatar options
  static List<String> getAvatarOptions() {
    return [
      'Avatar',
      'Avatar-2',
      'Avatar-3',
      'Avatar-4',
      'Avatar-5',
      'Avatar-6',
      'Avatar-7',
      'Avatar-8',
      'Avatar-9',
    ];
  }

  // Get avatar URL by name
  static String getAvatarUrl(String avatarName, {int width = 200, int height = 200}) {
    if (_baseImageUrl.isEmpty) return '';
    return '$_baseImageUrl/w_$width,h_$height,c_fill/avatars/$avatarName.png';
  }
}
