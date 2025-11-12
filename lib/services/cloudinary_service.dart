import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:io';
import '../config/app_config.dart';

class CloudinaryService {
  static String get _cloudName => AppConfig.cloudinaryCloudName;
  static String get _uploadPreset => AppConfig.cloudinaryUploadPreset;

  static Future<String?> uploadProfileImage(File imageFile, String userId) async {
    if (_cloudName.isEmpty || _uploadPreset.isEmpty) {
      debugPrint('Missing Cloudinary configuration. Check CLOUDINARY_* entries in .env');
      return null;
    }

    try {
      final url = Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/image/upload');
      
      final request = http.MultipartRequest('POST', url);
      request.fields['upload_preset'] = _uploadPreset;
      
      final file = await http.MultipartFile.fromPath('file', imageFile.path);
      request.files.add(file);
      
      // Add timeout to prevent hanging uploads
      final response = await request.send().timeout(
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
        debugPrint('Cloudinary upload failed with status: ${response.statusCode}');
        debugPrint('Response body: $responseData');
        debugPrint('Request fields: ${request.fields}');
        return null;
      }
    } catch (e) {
      debugPrint('Cloudinary upload error: $e');
      return null;
    }
  }

  static String getProfileImageUrl(String userId, {int width = 200, int height = 200}) {
    if (_cloudName.isEmpty) return '';
    return 'https://res.cloudinary.com/$_cloudName/image/upload/w_$width,h_$height,c_fill,g_face/paisabai/profiles/profile_$userId.jpg';
  }

  static String getOptimizedImageUrl(String publicId, {int width = 200, int height = 200}) {
    if (_cloudName.isEmpty) return '';
    return 'https://res.cloudinary.com/$_cloudName/image/upload/w_$width,h_$height,c_fill/$publicId';
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
    if (_cloudName.isEmpty) return '';
    return 'https://res.cloudinary.com/$_cloudName/image/upload/w_$width,h_$height,c_fill/$avatarName.png';
  }
}
