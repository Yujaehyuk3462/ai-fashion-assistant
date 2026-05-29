import 'dart:convert';

class OutfitAnalysis {
  final String title;
  final int score;
  final String top;
  final String bottom;
  final String description;

  const OutfitAnalysis({
    required this.title,
    required this.score,
    required this.top,
    required this.bottom,
    required this.description,
  });

  factory OutfitAnalysis.fromJson(Map<String, dynamic> json) {
    return OutfitAnalysis(
      title: (json['title'] as String?) ?? '스타일 추천',
      score: (json['score'] as num?)?.toInt() ?? 80,
      top: (json['top'] as String?) ?? '',
      bottom: (json['bottom'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
    );
  }

  static List<OutfitAnalysis> listFromJson(String text) {
    String cleaned = text.trim();
    // Gemini가 마크다운 코드 블록으로 감싸는 경우 제거
    cleaned = cleaned
        .replaceAll(RegExp(r'```json\s*'), '')
        .replaceAll(RegExp(r'```\s*'), '')
        .trim();

    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(OutfitAnalysis.fromJson)
            .toList();
      }
    } catch (_) {}
    return [];
  }
}