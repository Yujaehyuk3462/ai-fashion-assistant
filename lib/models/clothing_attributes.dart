class ClothingAttributes {
  final String color;
  final String style;
  final String pattern;
  final String formality;
  final String fit;
  final List<String> tags;

  const ClothingAttributes({
    required this.color,
    required this.style,
    required this.pattern,
    required this.formality,
    required this.fit,
    required this.tags,
  });

  factory ClothingAttributes.fromJson(Map<String, dynamic> json) {
    return ClothingAttributes(
      color: (json['color'] as String?)?.trim() ?? '',
      style: (json['style'] as String?)?.trim() ?? '',
      pattern: (json['pattern'] as String?)?.trim() ?? '',
      formality: (json['formality'] as String?)?.trim() ?? '',
      fit: (json['fit'] as String?)?.trim() ?? '',
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }

  Map<String, dynamic> toFirestore() => {
        'color': color,
        'style': style,
        'pattern': pattern,
        'formality': formality,
        'fit': fit,
        'tags': tags,
      };

  // 텍스트 기반 코디 매칭 프롬프트에 그대로 삽입할 한 줄 요약.
  String toPromptLine() {
    final tagsText = tags.isEmpty ? '' : ', 태그: ${tags.join(', ')}';
    return '색상 $color, 스타일 $style, 패턴 $pattern, 격식 $formality, 핏 $fit$tagsText';
  }
}
