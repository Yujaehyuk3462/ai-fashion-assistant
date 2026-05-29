import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../config/env.dart';

class GeminiService {
  static const _baseUrl = 'https://generativelanguage.googleapis.com/v1beta';

  // 가상 피팅: 사용자 사진 + 옷 이미지들 → 합성 이미지 반환
  static Future<Uint8List> generateFittingImage({
    required XFile userPhoto,
    required List<String> clothingImageUrls,
    required List<String> clothingNames,
  }) async {
    final userPhotoBytes = await userPhoto.readAsBytes();

    // 옷 이미지들 다운로드
    final clothingImageBytes = <Uint8List>[];
    for (final url in clothingImageUrls) {
      final bytes = await _downloadImage(url);
      clothingImageBytes.add(bytes);
    }

    // 요청 본문 구성
    final parts = <Map<String, dynamic>>[
      {'text': _buildPrompt(clothingNames)},
      {
        'inlineData': {
          'mimeType': 'image/jpeg',
          'data': base64Encode(userPhotoBytes),
        }
      },
      ...clothingImageBytes.map((bytes) => {
            'inlineData': {
              'mimeType': 'image/jpeg',
              'data': base64Encode(bytes),
            }
          }),
    ];

    final requestBody = jsonEncode({
      'contents': [
        {'parts': parts}
      ],
      'generationConfig': {
        'responseModalities': ['IMAGE', 'TEXT'],
      },
    });

    final response = await http
        .post(
          Uri.parse(
              '$_baseUrl/models/gemini-2.0-flash-preview-image-generation:generateContent?key=${Env.geminiApiKey}'),
          headers: {'Content-Type': 'application/json'},
          body: requestBody,
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      final errorBody = jsonDecode(response.body);
      final message = (errorBody['error']?['message'] as String?) ?? '알 수 없는 오류';
      throw Exception('Gemini API 오류: $message');
    }

    return _extractImageFromResponse(response.body);
  }

  static Future<Uint8List> _downloadImage(String url) async {
    final response =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('옷 이미지 다운로드 실패 (${response.statusCode})');
    }
    return response.bodyBytes;
  }

  static Uint8List _extractImageFromResponse(String responseBody) {
    final data = jsonDecode(responseBody) as Map<String, dynamic>;
    final candidates = data['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('Gemini에서 응답이 없습니다. 다시 시도해주세요.');
    }

    final content = (candidates[0] as Map)['content'] as Map?;
    final parts = content?['parts'] as List?;
    if (parts == null || parts.isEmpty) {
      throw Exception('Gemini 응답에 이미지가 포함되지 않았습니다.');
    }

    for (final part in parts) {
      final inlineData = (part as Map)['inlineData'] as Map?;
      if (inlineData != null) {
        final imageData = inlineData['data'] as String?;
        if (imageData != null && imageData.isNotEmpty) {
          return base64Decode(imageData);
        }
      }
    }

    throw Exception('합성 이미지를 생성하지 못했습니다. 다른 옷이나 사진으로 다시 시도해주세요.');
  }

  static String _buildPrompt(List<String> clothingNames) {
    final clothingList = clothingNames.map((n) => '- $n').join('\n');
    return '''
첫 번째 사진의 사람에게 이후 사진에 있는 옷을 입혀서 자연스러운 합성 이미지를 만들어주세요.

착용할 옷:
$clothingList

생성 규칙:
- 첫 번째 사진 속 사람의 얼굴, 체형, 피부톤, 헤어스타일을 그대로 유지해주세요
- 제공된 옷 이미지의 옷을 그 사람에게 자연스럽게 입혀주세요
- 전신이 보이도록 해주세요
- 자연스러운 포즈와 배경을 유지해주세요
- 실제로 그 옷을 입은 것처럼 사실적으로 표현해주세요
''';
  }
}