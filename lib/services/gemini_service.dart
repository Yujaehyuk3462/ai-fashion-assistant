import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../config/env.dart';
import '../models/clothing_attributes.dart';
import 'gemini_api_exception.dart';

class GeminiService {
  static const _baseUrl = 'https://generativelanguage.googleapis.com/v1beta';

  // 커넥션을 재사용해 매 요청마다의 TLS 핸드셰이크 비용을 줄인다.
  static final http.Client _client = http.Client();

  // 같은 세션에서 분석 → 가상 피팅을 연달아 실행하면 동일한 이미지 URL을
  // 반복 다운로드하게 되므로, 바이트를 캐시해 재다운로드를 피한다.
  static final Map<String, Uint8List> _imageCache = {};

  // ── 가상 피팅 이미지 생성 ────────────────────────────────
  static Future<Uint8List> generateFittingImage({
    required String userPhotoUrl,
    required List<String> clothingImageUrls,
    required List<String> clothingNames,
  }) async {
    // 이미지들을 순차 다운로드하면 N개 x 다운로드시간만큼 대기하게 되므로
    // Future.wait로 병렬 실행해 가장 느린 한 건의 시간만큼만 기다리게 한다.
    final downloaded = await Future.wait([
      _downloadImageBytesCached(userPhotoUrl),
      ...clothingImageUrls.map(_downloadImageBytesCached),
    ]);
    final userPhotoBytes = downloaded.first;
    final clothingImageBytes = downloaded.skip(1).toList();

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

    final response = await _client
        .post(
          Uri.parse('$_baseUrl/models/gemini-3-pro-image:generateContent?key=${Env.geminiApiKey}'),
          headers: {'Content-Type': 'application/json'},
          body: requestBody,
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      final errorBody = jsonDecode(response.body);
      final message = (errorBody['error']?['message'] as String?) ?? '알 수 없는 오류';
      throw GeminiApiException(response.statusCode, message);
    }

    return _extractImageFromResponse(response.body);
  }

  // ── 옷 사진 1장 → 속성 추출 (등록 시점 백그라운드 / 분석 시점 폴백) ──
  static Future<ClothingAttributes> extractAttributes({
    required String imageUrl,
    required String category,
  }) async {
    final bytes = await _downloadImageBytesCached(imageUrl);
    final parts = <Map<String, dynamic>>[
      {'text': _buildAttributeExtractionPrompt(category)},
      {'inlineData': {'mimeType': 'image/jpeg', 'data': base64Encode(bytes)}},
    ];

    final requestBody = jsonEncode({
      'contents': [{'parts': parts}],
      'generationConfig': {
        'temperature': 0.2,
        'maxOutputTokens': 250,
        'responseMimeType': 'application/json',
      },
    });

    final response = await _client
        .post(
          Uri.parse('$_baseUrl/models/gemini-3.5-flash:generateContent?key=${Env.geminiApiKey}'),
          headers: {'Content-Type': 'application/json'},
          body: requestBody,
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      final errorBody = jsonDecode(response.body);
      final message = (errorBody['error']?['message'] as String?) ?? '알 수 없는 오류';
      throw GeminiApiException(response.statusCode, message);
    }

    final text = _extractTextFromResponse(response.body);
    return ClothingAttributes.fromJson(_parseJsonObject(text));
  }

  // responseMimeType: application/json을 지정해도 모델이 종종
  // "Here is the JSON requested: {...}" 처럼 설명을 앞에 붙이거나
  // 마크다운 코드블록으로 감싸는 경우가 있어, 첫 '{'~마지막 '}' 구간만
  // 추출해 안전하게 파싱한다.
  static Map<String, dynamic> _parseJsonObject(String text) {
    var cleaned = text.trim();
    cleaned = cleaned
        .replaceAll(RegExp(r'```json\s*'), '')
        .replaceAll(RegExp(r'```\s*'), '');
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start == -1 || end == -1 || end < start) {
      throw FormatException('응답에서 JSON 객체를 찾을 수 없습니다: $text');
    }
    return jsonDecode(cleaned.substring(start, end + 1)) as Map<String, dynamic>;
  }

  // ── 코디 텍스트 분석 (옷 이미지 대신 캐싱된 속성 텍스트로 매칭 평가) ──
  static Future<String> analyzeOutfitFromAttributes({
    required List<({String category, ClothingAttributes attributes})> items,
    String? userPhotoUrl,
  }) async {
    // 옷 이미지는 더 이상 보내지 않는다 — 등록 시점에 뽑아둔 색상/스타일/
    // 패턴/격식/핏/태그 텍스트만으로 매칭을 평가하므로 입력이 훨씬 가볍다.
    final imageParts = <Map<String, dynamic>>[];
    if (userPhotoUrl != null) {
      final bytes = await _downloadImageBytesCached(userPhotoUrl);
      imageParts.add({
        'inlineData': {'mimeType': 'image/jpeg', 'data': base64Encode(bytes)}
      });
    }

    final prompt = userPhotoUrl != null
        ? _buildAttributeAnalysisPromptWithPhoto(items)
        : _buildAttributeAnalysisPrompt(items);

    final parts = <Map<String, dynamic>>[
      {'text': prompt},
      ...imageParts,
    ];

    final requestBody = jsonEncode({
      'contents': [{'parts': parts}],
      'generationConfig': {'temperature': 0.7, 'maxOutputTokens': 1200},
    });

    final response = await _client
        .post(
          Uri.parse('$_baseUrl/models/gemini-3.5-flash:generateContent?key=${Env.geminiApiKey}'),
          headers: {'Content-Type': 'application/json'},
          body: requestBody,
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      final errorBody = jsonDecode(response.body);
      final message = (errorBody['error']?['message'] as String?) ?? '알 수 없는 오류';
      throw GeminiApiException(response.statusCode, message);
    }

    return _extractTextFromResponse(response.body);
  }

  // ── 내부 공통 유틸 ─────────────────────────────────────────
  static Future<Uint8List> _downloadImageBytes(String url) async {
    final response = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('이미지 다운로드 실패 (${response.statusCode})');
    }
    return response.bodyBytes;
  }

  static Future<Uint8List> _downloadImageBytesCached(String url) async {
    final cached = _imageCache[url];
    if (cached != null) return cached;
    final bytes = await _downloadImageBytes(url);
    _imageCache[url] = bytes;
    return bytes;
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

  static String _buildAttributeExtractionPrompt(String category) {
    return '''
아래 옷 사진 한 장을 분석해서 JSON 객체 하나만 출력하세요. 설명, 마크다운, 코드블록 없이 순수 JSON만 답하세요.
이 옷의 카테고리는 "$category"입니다.

형식:
{"color": "주요 색상 (한 단어, 예: 네이비)", "style": "스타일 (한 단어, 예: 캐주얼/포멀/스트릿/미니멀/스포티)", "pattern": "패턴 (한 단어, 예: 무지/스트라이프/체크/도트/그래픽)", "formality": "격식 정도 (한 단어, 예: 캐주얼/세미포멀/포멀)", "fit": "핏 (한 단어, 예: 슬림/레귤러/오버사이즈)", "tags": ["소재나 계절 등 추가 특징 키워드 2~4개"]}
''';
  }

  static String _itemsToPromptLines(
    List<({String category, ClothingAttributes attributes})> items,
  ) {
    return items
        .asMap()
        .entries
        .map((e) => '${e.key + 1}. ${e.value.category}: ${e.value.attributes.toPromptLine()}')
        .join('\n');
  }

  static String _buildAttributeAnalysisPromptWithPhoto(
    List<({String category, ClothingAttributes attributes})> items,
  ) {
    final itemLines = _itemsToPromptLines(items);
    return '''
당신은 세련된 중년 남성을 위한 전문 패션 스타일리스트입니다.

[핵심 지침 - 반드시 준수하세요]
첫 번째 이미지는 착용자의 체형, 피부톤, 얼굴형, 전체적인 분위기를 파악하기 위한 참고 사진입니다.
절대로 첫 번째 사진 속 인물이 현재 입고 있는 옷에 대해 분석하거나 언급하지 마세요.
분석 대상은 아래 텍스트로 설명된 의류들입니다. 실제 이미지는 첨부되지 않았으니 아래 설명만으로 판단해 주세요.

$itemLines

이 의류들을 첫 번째 사진 착용자가 입었을 때 얼마나 잘 어울릴지, 가상 피팅 관점에서 평가해 주세요.

아래 형식으로 정확히 답변해 주세요.

[점수] (현재 코디의 컬러 조합을 1~100점으로 평가한 숫자만 입력)

1. 코디 분위기: 위 의류 조합이 이 착용자의 체형과 분위기에 얼마나 잘 어울리는지, 연출되는 스타일을 2~3문장으로 설명해 주세요.
2. 신발 추천: 이 코디에 가장 잘 어울리는 신발을 종류와 색상을 포함해 2가지 추천해 주세요.
3. 스타일링 팁: 전체 코디를 더욱 완성도 있게 만들 액세서리나 추가 아이템을 1~2가지 제안해 주세요.
4. 다른 색상 추천: 현재 선택한 의류와 동일한 스타일이지만 더 높은 컬러 조합 점수를 받을 수 있는 색상 조합 2가지를 구체적으로 추천해 주세요. 각 추천마다 어떤 색상으로 바꾸면 좋은지, 왜 더 잘 어울리는지 설명해 주세요.

[출력 형식 규칙 - 반드시 준수하세요]
응답의 첫 번째 줄은 반드시 "[점수] 숫자" 형식으로만 시작해 주세요. 예시: [점수] 78
별표(*), 샵(#), 대시(-) 등 어떠한 마크다운 기호도 절대 사용하지 마세요.
이모지나 특수문자도 사용하지 마세요.
1. 2. 3. 4. 숫자 번호와 일반 텍스트로만 깔끔하게 답변해 주세요.
전체 답변은 각 항목당 지정된 문장 수를 넘기지 말고 간결하게 작성해 주세요.
''';
  }

  static String _buildAttributeAnalysisPrompt(
    List<({String category, ClothingAttributes attributes})> items,
  ) {
    final itemLines = _itemsToPromptLines(items);
    return '''
당신은 세련된 중년 남성을 위한 전문 패션 스타일리스트입니다.
아래에 텍스트로 설명된 의류 조합을 보고, 컬러 조합을 점수로 평가하고 코디 분석 및 다른 색상 추천을 해 주세요. 실제 이미지는 첨부되지 않았으니 아래 설명만으로 판단해 주세요.

$itemLines

아래 형식으로 정확히 답변해 주세요.

[점수] (현재 코디의 컬러 조합을 1~100점으로 평가한 숫자만 입력)

1. 코디 분위기: 이 의류 조합이 연출하는 전반적인 스타일과 분위기를 2~3문장으로 설명해 주세요.
2. 신발 추천: 이 코디에 가장 잘 어울리는 신발을 종류와 색상을 포함해 2가지 추천해 주세요.
3. 스타일링 팁: 전체 코디를 더욱 완성도 있게 만들 액세서리나 추가 아이템을 1~2가지 제안해 주세요.
4. 다른 색상 추천: 현재 선택한 의류와 동일한 스타일이지만 더 높은 컬러 조합 점수를 받을 수 있는 색상 조합 2가지를 구체적으로 추천해 주세요. 각 추천마다 어떤 색상으로 바꾸면 좋은지, 왜 더 잘 어울리는지 설명해 주세요.

[출력 형식 규칙 - 반드시 준수하세요]
응답의 첫 번째 줄은 반드시 "[점수] 숫자" 형식으로만 시작해 주세요. 예시: [점수] 78
별표(*), 샵(#), 대시(-) 등 어떠한 마크다운 기호도 절대 사용하지 마세요.
이모지나 특수문자도 사용하지 마세요.
1. 2. 3. 4. 숫자 번호와 일반 텍스트로만 깔끔하게 답변해 주세요.
전체 답변은 각 항목당 지정된 문장 수를 넘기지 말고 간결하게 작성해 주세요.
''';
  }
}
