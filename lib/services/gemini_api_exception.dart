class GeminiApiException implements Exception {
  final int statusCode;
  final String message;

  GeminiApiException(this.statusCode, this.message);

  // 503(모델 과부하)·429(요청 급증)는 잠시 후 재시도하면 성공할 가능성이
  // 높은 일시적 오류. 그 외(400/403 등)는 재시도해도 같은 결과라 바로 실패 처리.
  bool get isRetryable => statusCode == 503 || statusCode == 429;

  @override
  String toString() => 'Gemini API 오류: $message';
}
