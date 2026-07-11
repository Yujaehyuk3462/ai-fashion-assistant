import 'package:cloud_firestore/cloud_firestore.dart';

// users/{uid}/agent_logs/{id} 컬렉션 문서 — 에이전트가 백그라운드에서 밟은
// "행동 단위" 한 건. history가 결과물(코디/착장)을 남긴다면 agent_logs는
// 그 결과에 이르기까지의 서사(감지 → 후보 생성 → 평가 → 등록)를 남긴다.
// 심사/시연에서 "뒤에서 스스로 일하는 비서"임을 타임라인으로 보여주는 용도.
class AgentLogEntry {
  // 알려진 eventType 상수. 화면이 아이콘/그룹을 결정할 때 참조하고,
  // 이 목록에 없는 값이 와도(모델 진화 대비) 화면은 기본 아이콘으로 처리한다.
  static const typeNewItemDetected = 'new_item_detected';
  static const typeCandidatesGenerated = 'candidates_generated';
  static const typeCandidateEvaluated = 'candidate_evaluated';
  static const typeRecommendationRegistered = 'recommendation_registered';
  static const typeAnalysisCompleted = 'analysis_completed';
  static const typeFittingGenerated = 'fitting_generated';
  static const typeCalendarLogged = 'calendar_logged';
  static const typeScheduleDetected = 'schedule_detected'; // 다가오는 일정 감지(선제 추천)
  static const typeWeeklyPlanned = 'weekly_planned'; // 주간 코디 플랜 수립

  final String id;
  final DateTime? createdAt; // 읽을 때만 채워짐(쓸 때는 서버 타임스탬프 사용)
  final String eventType;
  final String message; // 사용자에게 그대로 보여줄 한국어 문장
  // 같은 파이프라인에 속한 연속 이벤트를 화면에서 묶기 위한 상관 id.
  // 추천 파이프라인은 트리거된 옷 id를 공유 id로 쓴다(등록 문서 id는 마지막에야
  // 생기므로). 단발 이벤트(분석/피팅 완료)는 null.
  final String? relatedDocId;

  const AgentLogEntry({
    required this.id,
    this.createdAt,
    required this.eventType,
    required this.message,
    this.relatedDocId,
  });

  factory AgentLogEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AgentLogEntry(
      id: doc.id,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      eventType: data['eventType'] as String? ?? '',
      message: data['message'] as String? ?? '',
      relatedDocId: data['relatedDocId'] as String?,
    );
  }

  // id는 Firestore가 add() 시점에 자동 부여하므로 쓰기에는 포함하지 않는다.
  Map<String, dynamic> toFirestore() => {
        'eventType': eventType,
        'message': message,
        if (relatedDocId != null) 'relatedDocId': relatedDocId,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
