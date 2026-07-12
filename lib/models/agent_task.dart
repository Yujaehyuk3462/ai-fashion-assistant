import 'package:cloud_firestore/cloud_firestore.dart';

// users/{uid}/agent_tasks/{id} 컬렉션 문서 — 실패한 백그라운드 작업의
// "재개 지점"을 남긴다. 파이프라인이 조용히 실패하고 끝나는 대신, 여기에
// 태스크로 남겨두면 AgentSweeper가 다음 앱 실행 때 스스로 발견해 재시도한다.
class AgentTask {
  static const typeExtractAttributes = 'extract_attributes';
  static const typeGenerateRecommendation = 'generate_recommendation';

  static const statusPending = 'pending';
  static const statusDone = 'done';
  static const statusGaveUp = 'gave_up';

  // 이 횟수를 넘겨 실패하면 더 재시도하지 않고 gave_up으로 전환한다.
  static const maxRetries = 5;

  final String id;
  final String type;
  final Map<String, dynamic> payload; // 재개에 필요한 최소 정보(예: {itemId: ...})
  final String status;
  final int retryCount;
  final DateTime nextRetryAt;
  final String? lastError; // 마지막 실패 사유(로그/디버깅용)
  final DateTime createdAt;

  const AgentTask({
    required this.id,
    required this.type,
    required this.payload,
    this.status = statusPending,
    this.retryCount = 0,
    required this.nextRetryAt,
    this.lastError,
    required this.createdAt,
  });

  String? get itemId => payload['itemId'] as String?;

  // 새 태스크를 만들 때 쓰는 생성자 — 즉시 재시도 가능하도록 nextRetryAt은
  // now, id/createdAt은 Firestore가 add() 시점에 채운다.
  factory AgentTask.create({
    required String type,
    required Map<String, dynamic> payload,
    String? lastError,
  }) {
    final now = DateTime.now();
    return AgentTask(
      id: '',
      type: type,
      payload: payload,
      nextRetryAt: now,
      lastError: lastError,
      createdAt: now,
    );
  }

  factory AgentTask.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AgentTask(
      id: doc.id,
      type: data['type'] as String? ?? '',
      payload: Map<String, dynamic>.from(data['payload'] as Map? ?? const {}),
      status: data['status'] as String? ?? statusPending,
      retryCount: data['retryCount'] as int? ?? 0,
      nextRetryAt: (data['nextRetryAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastError: data['lastError'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'type': type,
        'payload': payload,
        'status': status,
        'retryCount': retryCount,
        'nextRetryAt': Timestamp.fromDate(nextRetryAt),
        if (lastError != null) 'lastError': lastError,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
