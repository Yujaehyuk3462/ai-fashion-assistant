class UserProfile {
  final int? heightCm;
  final double? weightKg;
  final String? personalColor; // 봄웜/여름쿨/가을웜/겨울쿨
  final String? bodyType; // 마른 체형/보통 체형/통통한 체형/근육질 체형
  final int? waistCm;
  final int? chestCm;
  final List<String> preferredStyles; // 캐주얼/포멀/스트릿/미니멀/스포티 중 다중 선택

  const UserProfile({
    this.heightCm,
    this.weightKg,
    this.personalColor,
    this.bodyType,
    this.waistCm,
    this.chestCm,
    this.preferredStyles = const [],
  });

  // 코디 분석 프롬프트에서 "이 사용자가 뭐라도 입력했는지" 판단하는 기준.
  // 하나라도 채워져 있으면 프로필 텍스트를 쓰고, 전부 비어 있으면
  // 기존처럼 전신 사진 폴백으로 넘어간다.
  bool get hasAnyData =>
      heightCm != null ||
      weightKg != null ||
      personalColor != null ||
      bodyType != null ||
      waistCm != null ||
      chestCm != null ||
      preferredStyles.isNotEmpty;

  factory UserProfile.fromFirestore(Map<String, dynamic> data) {
    return UserProfile(
      heightCm: data['heightCm'] as int?,
      weightKg: (data['weightKg'] as num?)?.toDouble(),
      personalColor: data['personalColor'] as String?,
      bodyType: data['bodyType'] as String?,
      waistCm: data['waistCm'] as int?,
      chestCm: data['chestCm'] as int?,
      preferredStyles:
          (data['preferredStyles'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }

  Map<String, dynamic> toFirestore() => {
        if (heightCm != null) 'heightCm': heightCm,
        if (weightKg != null) 'weightKg': weightKg,
        if (personalColor != null) 'personalColor': personalColor,
        if (bodyType != null) 'bodyType': bodyType,
        if (waistCm != null) 'waistCm': waistCm,
        if (chestCm != null) 'chestCm': chestCm,
        if (preferredStyles.isNotEmpty) 'preferredStyles': preferredStyles,
      };

  // 코디 분석 프롬프트에 그대로 삽입할 한 줄 요약. 입력된 필드만 포함한다.
  String toPromptLine() {
    final parts = <String>[];
    if (heightCm != null) parts.add('키 ${heightCm}cm');
    if (weightKg != null) parts.add('몸무게 ${weightKg}kg');
    if (personalColor != null) parts.add('퍼스널 컬러 $personalColor');
    if (bodyType != null) parts.add('체형 $bodyType');
    if (waistCm != null) parts.add('허리둘레 ${waistCm}cm');
    if (chestCm != null) parts.add('가슴둘레 ${chestCm}cm');
    if (preferredStyles.isNotEmpty) parts.add('선호 스타일 ${preferredStyles.join(', ')}');
    return parts.join(', ');
  }
}
