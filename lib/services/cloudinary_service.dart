import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class CloudinaryService {
  static const _cloudName = String.fromEnvironment(
    'CLOUDINARY_CLOUD_NAME',
    defaultValue: 'diraz3twf',
  );
  static const _uploadPreset = String.fromEnvironment(
    'CLOUDINARY_UPLOAD_PRESET',
    defaultValue: 'chat_app_unsigned',
  );

  static Future<String> uploadImage(
    File imageFile, {
    required String publicId,
    String folder = 'user_images',
  }) async {
    if (_cloudName.isEmpty || _uploadPreset.isEmpty) {
      throw Exception(
        'Missing Cloudinary config. Run the app with '
        '--dart-define=CLOUDINARY_CLOUD_NAME=... '
        '--dart-define=CLOUDINARY_UPLOAD_PRESET=...',
      );
    }

    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse(
              'https://api.cloudinary.com/v1_1/$_cloudName/image/upload',
            ),
          )
          ..fields['upload_preset'] = _uploadPreset
          ..fields['folder'] = folder
          ..fields['public_id'] = publicId
          ..files.add(
            await http.MultipartFile.fromPath('file', imageFile.path),
          );

    final response = await request.send();
    final body = await response.stream.bytesToString();
    final data = jsonDecode(body) as Map<String, dynamic>;

    if (response.statusCode >= 400) {
      final error = data['error'];
      final message = error is Map<String, dynamic>
          ? error['message']?.toString()
          : null;
      throw Exception(message ?? 'Cloudinary upload failed.');
    }

    final secureUrl = data['secure_url']?.toString();
    if (secureUrl == null || secureUrl.isEmpty) {
      throw Exception('Cloudinary did not return a secure_url.');
    }

    return secureUrl;
  }
}
