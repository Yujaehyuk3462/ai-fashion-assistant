import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../config/env.dart';

class GeminiService {
  static const _baseUrl = 'https://generativelanguage.googleapis.com/v1beta';

  // ── 가상 피팅 이미지 생성 ────────────────────────────────
  static Future<Uint8List> generateFittingImage({
    required String userPhotoUrl,
    required List<String> clothingImageUrls,
    required List<String> clothingNames,
  }) async {
    final userPhotoBytes = await _downloadImageBytes(userPhotoUrl);

    final clothingImageBytes = <Uint8List>[];
    for (final url in clothingImageUrls) {
      clothingImageBytes.add(await _downloadImageBytes(url));
    }

    final parts = <Map<String, dynamic>>[
      {'text': _buildFittingPrompt(clothingNames)},
      {'inlineData': {'mimeType': 'image/jpeg', 'data': base64Encode(userPhotoBytes)}},
      ...clothingImageBytes.map((bytes) => {
        'inlineData': {'mimeType': 'image/jpeg', 'data': base64Encode(bytes)}
      }),
    ];

    final requestBody = jsonEncode({
      'contents': [{'parts': parts}],
      'generationConfig': {'responseModalities': ['IMAGE', 'TEXT']},
    });

    final response = await http
        .post(
          Uri.parse('$_baseUrl/models/gemini-3-pro-image:generateContent?key=${Env.geminiApiKey}'),
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

  // ── 코디 텍스트 분석 ──────────────────────────────────────
  static Future<String> analyzeOutfit({
    required List<String> clothingImageUrls,
    required List<String> clothingCategories,
    String? userPhotoUrl,
  }) async {
    final imageParts = <Map<String, dynamic>>[];

    if (userPhotoUrl != null) {
      final bytes = await _downloadImageBytes(userPhotoUrl);
      imageParts.add({
        'inlineData': {'mimeType': 'image/jpeg', 'data': base64Encode(bytes)}
      });
    }

    for (final url in clothingImageUrls) {
      final bytes = await _downloadImageBytes(url);
      imageParts.add({
        'inlineData': {'mimeType': 'image/jpeg', 'data': base64Encode(bytes)}
      });
    }

    final prompt = userPhotoUrl != null
        ? _buildAnalysisPromptWithPhoto(clothingCategories)
        : _buildAnalysisPrompt(clothingCategories);

    final parts = <Map<String, dynamic>>[
      {'text': prompt},
      ...imageParts,
    ];

    final requestBody = jsonEncode({
      'contents': [{'parts': parts}],
      'generationConfig': {'temperature': 0.7, 'maxOutputTokens': 1024},
    });

    final response = await http
        .post(
          Uri.parse('$_baseUrl/models/gemini-3.5-flash:generateContent?key=${Env.geminiApiKey}'),
          headers: {'Content-Type': 'application/json'},
          body: requestBody,
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode != 200) {
      final errorBody = jsonDecode(response.body);
      final message = (errorBody['error']?['message'] as String?) ?? '알 수 없는 오류';
      throw Exception('Gemini API 오류: $message');
    }

    return _extractTextFromResponse(response.body);
  }

  // ── 내부 공통 유틸 ─────────────────────────────────────────
  static Future<Uint8List> _downloadImageBytes(String url) async {
    final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('이미지 다운로드 실패 (${response.statusCode})');
    }
    return response.bodyBytes;
  }

  static String _extractTextFromResponse(String body) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('Gemini 응답이 비어 있습니다. 다시 시도해 주세요.');
    }
    final content = (candidates[0] as Map)['content'] as Map?;
    final parts = content?['parts'] as List?;
    if (parts == null || parts.isEmpty) {
      throw Exception('응답에서 텍스트를 찾을 수 없습니다.');
    }
    final text = (parts[0] as Map)['text'] as String?;
    if (text == null || text.trim().isEmpty) {
      throw Exception('분석 결과를 가져오지 못했습니다.');
    }
    return text.trim();
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

  static String _buildFittingPrompt(List<String> clothingNames) {
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

  static String _buildAnalysisPromptWithPhoto(List<String> categories) {
    final items = categories.join(', ');
    return '''
당신은 세련된 중년 남성을 위한 전문 패션 스타일리스트입니다.

[핵심 지침 - 반드시 준수하세요]
첫 번째 이미지는 착용자의 체형, 피부톤, 얼굴형, 전체적인 분위기를 파악하기 위한 참고 사진입니다.
절대로 첫 번째 사진 속 인물이 현재 입고 있는 옷에 대해 분석하거나 언급하지 마세요.
분석 대상은 오직 두 번째 이미지부터 첨부된 의류($items)입니다.
첨부된 의류들을 첫 번째 사진 착용자가 입었을 때 얼마나 잘 어울릴지, 가상 피팅 관점에서 평가해 주세요.

아래 3가지 항목으로 구분해서 한국어로 답변해 주세요.

1. 코디 분위기: 첨부된 의류 조합이 이 착용자의 체형과 분위기에 얼마나 잘 어울리는지, 연출되는 스타일을 2~3문장으로 설명해 주세요.
2. 신발 추천: 이 코디에 가장 잘 어울리는 신발을 종류와 색상을 포함해 2가지 추천해 주세요.
3. 스타일링 팁: 전체 코디를 더욱 완성도 있게 만들 액세서리나 추가 아이템을 1~2가지 제안해 주세요.

[출력 형식 규칙 - 반드시 준수하세요]
별표(*), 샵(#), 대시(-) 등 어떠한 마크다운 기호도 절대 사용하지 마세요.
이모지나 특수문자도 사용하지 마세요.
1. 2. 3. 숫자 번호와 일반 텍스트로만 깔끔하게 답변해 주세요.
''';
  }

  static String _buildAnalysisPrompt(List<String> categories) {
    final items = categories.join(', ');
    return '''
당신은 세련된 중년 남성을 위한 전문 패션 스타일리스트입니다.
첨부된 의류 이미지($items)를 보고, 이 옷차림의 분위기와 어울리는 코디 및 신발을 추천해 주세요.

아래 3가지 항목으로 구분해서, 간결하고 실용적으로 한국어로 답변해 주세요.

1. 코디 분위기: 이 의류 조합이 연출하는 전반적인 스타일과 분위기를 2~3문장으로 설명해 주세요.
2. 신발 추천: 이 코디에 가장 잘 어울리는 신발을 종류와 색상을 포함해 2가지 추천해 주세요.
3. 스타일링 팁: 전체 코디를 더욱 완성도 있게 만들 액세서리나 추가 아이템을 1~2가지 제안해 주세요.

[출력 형식 규칙 - 반드시 준수하세요]
별표(*), 샵(#), 대시(-) 등 어떠한 마크다운 기호도 절대 사용하지 마세요.
이모지나 특수문자도 사용하지 마세요.
1. 2. 3. 숫자 번호와 일반 텍스트로만 깔끔하게 답변해 주세요.
''';
  }
}
