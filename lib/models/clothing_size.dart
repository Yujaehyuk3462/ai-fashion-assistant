class ClothingSize {
  // 상의/아우터
  final double? totalLength; // 총장
  final double? shoulderWidth; // 어깨너비
  final double? chestWidth; // 가슴단면 (겨드랑이~겨드랑이, 둘레의 절반)
  final double? sleeveLength; // 소매길이
  // 하의
  final double? waistWidth; // 허리단면 (둘레의 절반)
  final double? hipWidth; // 엉덩이단면
  final double? thighWidth; // 허벅지단면
  final double? pantsLength; // 총장(밑위 포함 기장)

  const ClothingSize({
    this.totalLength,
    this.shoulderWidth,
    this.chestWidth,
    this.sleeveLength,
    this.waistWidth,
    this.hipWidth,
    this.thighWidth,
    this.pantsLength,
  });

  bool get hasAnyData =>
      totalLength != null ||
      shoulderWidth != null ||
      chestWidth != null ||
      sleeveLength != null ||
      waistWidth != null ||
      hipWidth != null ||
      thighWidth != null ||
      pantsLength != null;

  factory ClothingSize.fromJson(Map<String, dynamic> json) {
    double? parse(dynamic v) => (v as num?)?.toDouble();
    return ClothingSize(
      totalLength: parse(json['totalLength']),
      shoulderWidth: parse(json['shoulderWidth']),
      chestWidth: parse(json['chestWidth']),
      sleeveLength: parse(json['sleeveLength']),
      waistWidth: parse(json['waistWidth']),
      hipWidth: parse(json['hipWidth']),
      thighWidth: parse(json['thighWidth']),
      pantsLength: parse(json['pantsLength']),
    );
  }

  Map<String, dynamic> toFirestore() => {
        if (totalLength != null) 'totalLength': totalLength,
        if (shoulderWidth != null) 'shoulderWidth': shoulderWidth,
        if (chestWidth != null) 'chestWidth': chestWidth,
        if (sleeveLength != null) 'sleeveLength': sleeveLength,
        if (waistWidth != null) 'waistWidth': waistWidth,
        if (hipWidth != null) 'hipWidth': hipWidth,
        if (thighWidth != null) 'thighWidth': thighWidth,
        if (pantsLength != null) 'pantsLength': pantsLength,
      };
}
