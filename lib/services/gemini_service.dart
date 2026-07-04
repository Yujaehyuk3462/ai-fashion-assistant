import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../config/env.dart';
import '../models/clothing_attributes.dart';
import '../models/clothing_size.dart';
import '../models/user_profile.dart';
import 'gemini_api_exception.dart';

class GeminiService {
  static const _baseUrl = 'https://generativelanguage.googleapis.com/v1beta';

  // 모델명을 한 곳에 모아서 나중에 교체하기 쉽게 관리한다.
  // gemini-3-flash-preview로 시도해봤으나 응답이 중간에 잘리는 등
  // preview 특유의 불안정함이 반복 확인돼 안정적인 gemini-3.5-flash로 되돌림.
  // 이미지 합성(Nano Banana Pro)은 그대로 gemini-3-pro-image를 유지한다.
  static const _textModel = 'gemini-3.5-flash';
  static const _imageModel = 'gemini-3-pro-image';

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
          Uri.parse('$_baseUrl/models/$_imageModel:generateContent?key=${Env.geminiApiKey}'),
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
        'maxOutputTokens': 500,
        'responseMimeType': 'application/json',
        // 실측 결과 thinking(추론) 단계가 maxOutputTokens 예산을 거의 다
        // 먹어버려서(예: 478/500) 실제 JSON은 "{" 한두 글자만 쓰고 잘리는
        // 경우가 반복 확인됐다. 색상/스타일 분류는 추론이 필요 없는 단순
        // 작업이라 thinking budget을 0으로 꺼서 근본적으로 방지한다.
        'thinkingConfig': {'thinkingBudget': 0},
      },
    });

    final response = await _client
        .post(
          Uri.parse('$_baseUrl/models/$_textModel:generateContent?key=${Env.geminiApiKey}'),
          headers: {'Content-Type': 'application/json'},
          body: requestBody,
        )
        // preview 모델이라 3.5-flash보다 응답 지연이 더 클 수 있어 여유를 둔다.
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      final errorBody = jsonDecode(response.body);
      final message = (errorBody['error']?['message'] as String?) ?? '알 수 없는 오류';
      throw GeminiApiException(response.statusCode, message);
    }

    final text = _extractTextFromResponse(response.body);
    return ClothingAttributes.fromJson(_parseJsonObject(text));
  }

  // ── 사이즈표 사진 한 장 → 특정 사이즈 행의 치수 추출 ──
  // Storage에 업로드된 옷 사진이 아니라 사용자가 그 자리에서 찍은/고른
  // 사이즈표 사진의 바이트를 바로 받는다 — 저장할 필요 없는 1회성 OCR
  // 입력이라 URL 다운로드 경로(_downloadImageBytesCached)를 타지 않는다.
  static Future<ClothingSize> extractSizeFromChart({
    required Uint8List imageBytes,
    required String category,
    required String sizeLabel,
  }) async {
    final parts = <Map<String, dynamic>>[
      {'text': _buildSizeChartExtractionPrompt(category: category, sizeLabel: sizeLabel)},
      {'inlineData': {'mimeType': 'image/jpeg', 'data': base64Encode(imageBytes)}},
    ];

    final requestBody = jsonEncode({
      'contents': [{'parts': parts}],
      'generationConfig': {
        'temperature': 0.1,
        'maxOutputTokens': 500,
        'responseMimeType': 'application/json',
        // extractAttributes와 동일한 이유로 thinking을 꺼서 예산이
        // JSON 출력 전에 잘려나가는 것을 방지한다.
        'thinkingConfig': {'thinkingBudget': 0},
      },
    });

    final response = await _client
        .post(
          Uri.parse('$_baseUrl/models/$_textModel:generateContent?key=${Env.geminiApiKey}'),
          headers: {'Content-Type': 'application/json'},
          body: requestBody,
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      final errorBody = jsonDecode(response.body);
      final message = (errorBody['error']?['message'] as String?) ?? '알 수 없는 오류';
      throw GeminiApiException(response.statusCode, message);
    }

    final text = _extractTextFromResponse(response.body);
    return ClothingSize.fromJson(_parseJsonObject(text));
  }

  static String _buildSizeChartExtractionPrompt({
    required String category,
    required String sizeLabel,
  }) {
    final fields = category == '하의'
        ? '"waistWidth": 허리단면(cm), "hipWidth": 엉덩이단면(cm), "thighWidth": 허벅지단면(cm), "pantsLength": 총장(cm)'
        : '"totalLength": 총장(cm), "shoulderWidth": 어깨너비(cm), "chestWidth": 가슴단면(cm), "sleeveLength": 소매길이(cm)';
    return '''
아래는 의류 사이즈표 이미지입니다. 이 표에서 사이즈가 정확히 "$sizeLabel"인 행 하나만 찾아
그 행의 치수 숫자만 JSON으로 추출하세요. 다른 사이즈 행의 값을 섞어 쓰지 마세요.
숫자를 읽는 것 외에 어떤 판단이나 설명, 핏 평가도 하지 마세요.
표에 "$sizeLabel" 사이즈가 없거나 특정 항목을 읽을 수 없으면 해당 값은 null로 두세요.
단위가 cm가 아니라 인치 등으로 표기되어 있다면 cm로 환산해서 반환하세요.

응답은 반드시 '{' 문자로 즉시 시작해야 합니다. "Here is the JSON" 같은 설명 문구,
마크다운, 코드블록을 절대 앞에 붙이지 마세요. 순수 JSON 객체만 출력하세요.

형식: {$fields}
''';
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
    UserProfile? userProfile,
  }) async {
    // 옷 이미지는 더 이상 보내지 않는다 — 등록 시점에 뽑아둔 색상/스타일/
    // 패턴/격식/핏/태그 텍스트만으로 매칭을 평가하므로 입력이 훨씬 가볍다.
    // 사용자 체형 프로필이 입력되어 있으면 그 텍스트가 사진보다 정확하고
    // 훨씬 빠르므로 우선하고, 이 경우 전신 사진은 아예 보내지 않는다.
    final hasProfile = userProfile != null && userProfile.hasAnyData;

    final imageParts = <Map<String, dynamic>>[];
    if (!hasProfile && userPhotoUrl != null) {
      final bytes = await _downloadImageBytesCached(userPhotoUrl);
      imageParts.add({
        'inlineData': {'mimeType': 'image/jpeg', 'data': base64Encode(bytes)}
      });
    }

    final prompt = hasProfile
        ? _buildAttributeAnalysisPromptWithProfile(items, userProfile)
        : (userPhotoUrl != null
            ? _buildAttributeAnalysisPromptWithPhoto(items)
            : _buildAttributeAnalysisPrompt(items));

    final parts = <Map<String, dynamic>>[
      {'text': prompt},
      ...imageParts,
    ];

    // maxOutputTokens는 thinking(추론) 토큰과 같은 예산을 공유한다.
    // 스타일링 조언은 어느 정도 추론이 품질에 도움이 되므로 thinking은
    // 끄지 않되, 실제 답변이 잘리지 않도록 예산을 넉넉히 둔다.
    final requestBody = jsonEncode({
      'contents': [{'parts': parts}],
      'generationConfig': {'temperature': 0.7, 'maxOutputTokens': 3000},
    });

    final response = await _client
        .post(
          Uri.parse('$_baseUrl/models/$_textModel:generateContent?key=${Env.geminiApiKey}'),
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

  // ── 코디 텍스트 분석 (스트리밍) ──────────────────────────
  // analyzeOutfitFromAttributes와 프롬프트/설정은 동일하되, SSE로 델타
  // 텍스트를 그때그때 yield해 화면에 점진적으로 표시할 수 있게 한다.
  static Stream<String> analyzeOutfitFromAttributesStream({
    required List<({String category, ClothingAttributes attributes})> items,
    String? userPhotoUrl,
    UserProfile? userProfile,
  }) async* {
    final hasProfile = userProfile != null && userProfile.hasAnyData;

    final imageParts = <Map<String, dynamic>>[];
    if (!hasProfile && userPhotoUrl != null) {
      final bytes = await _downloadImageBytesCached(userPhotoUrl);
      imageParts.add({
        'inlineData': {'mimeType': 'image/jpeg', 'data': base64Encode(bytes)}
      });
    }

    final prompt = hasProfile
        ? _buildAttributeAnalysisPromptWithProfile(items, userProfile)
        : (userPhotoUrl != null
            ? _buildAttributeAnalysisPromptWithPhoto(items)
            : _buildAttributeAnalysisPrompt(items));

    final parts = <Map<String, dynamic>>[
      {'text': prompt},
      ...imageParts,
    ];

    final requestBody = jsonEncode({
      'contents': [{'parts': parts}],
      'generationConfig': {'temperature': 0.7, 'maxOutputTokens': 3000},
    });

    final request = http.Request(
      'POST',
      Uri.parse('$_baseUrl/models/$_textModel:streamGenerateContent?alt=sse&key=${Env.geminiApiKey}'),
    )
      ..headers['Content-Type'] = 'application/json'
      // gzip 응답은 dart:io가 자동 압축 해제하면서 전체 바디를 다 받을 때까지
      // 스트림을 버퍼링해버려 SSE 청크가 한꺼번에 도착한 것처럼 보이게 만든다.
      // 압축을 아예 받지 않도록 요청해 진짜 점진적 스트리밍이 되게 한다.
      ..headers['Accept-Encoding'] = 'identity'
      ..body = requestBody;

    final streamedResponse = await _client.send(request).timeout(const Duration(seconds: 60));

    if (streamedResponse.statusCode != 200) {
      final errorBody = await streamedResponse.stream.bytesToString();
      final decoded = jsonDecode(errorBody);
      final message = (decoded['error']?['message'] as String?) ?? '알 수 없는 오류';
      throw GeminiApiException(streamedResponse.statusCode, message);
    }

    // 이벤트 사이 간격이 60초를 넘으면(응답이 멈춘 것으로 간주) 타임아웃시킨다.
    // Stream.timeout은 이벤트가 올 때마다 타이머를 리셋하므로 전체 응답
    // 길이와 무관하게 "멈춘 상태"만 감지한다.
    final lines = streamedResponse.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(const Duration(seconds: 60));

    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final jsonStr = line.substring(5).trim();
      if (jsonStr.isEmpty) continue;

      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final candidates = data['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) continue;
      final content = (candidates[0] as Map)['content'] as Map?;
      final parts0 = content?['parts'] as List?;
      if (parts0 == null || parts0.isEmpty) continue;
      final text = (parts0[0] as Map)['text'] as String?;
      if (text != null && text.isNotEmpty) yield text;
    }
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
아래 옷 사진 한 장을 분석해서 JSON 객체 하나만 출력하세요.
응답은 반드시 '{' 문자로 즉시 시작해야 합니다. "Here is the JSON" 같은 설명 문구,
마크다운, 코드블록을 절대 앞에 붙이지 마세요. 순수 JSON 객체만 출력하세요.
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

  static String _buildAttributeAnalysisPromptWithProfile(
    List<({String category, ClothingAttributes attributes})> items,
    UserProfile profile,
  ) {
    final itemLines = _itemsToPromptLines(items);
    return '''
당신은 세련된 중년 남성을 위한 전문 패션 스타일리스트입니다.

착용자 정보(사용자가 직접 입력): ${profile.toPromptLine()}

분석 대상은 아래 텍스트로 설명된 의류들입니다.

$itemLines

위 착용자 정보를 참고해서, 이 의류들이 착용자에게 얼마나 잘 어울릴지 평가해 주세요.

아래 형식으로 정확히 답변해 주세요.

[점수] (현재 코디의 컬러 조합을 1~100점으로 평가한 숫자만 입력)

1. 코디 분위기: 위 의류 조합이 착용자 정보와 얼마나 잘 어울리는지, 연출되는 스타일을 2~3문장으로 설명해 주세요.
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
