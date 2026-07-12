import 'package:flutter/foundation.dart';

// 백그라운드 능동 추천 파이프라인이 지금 무엇을 하고 있는지 한 줄 문구.
// null이면 유휴 — 홈 화면이 이 값을 구독해 "에이전트 작업 중" 미니
// 인디케이터를 그린다. 파이프라인이 끝나면(성공/실패 무관) 반드시 null로
// 되돌려야 인디케이터가 유령처럼 남지 않는다. 앱 프로세스가 재시작되면
// 이 static 필드도 초기화되므로 재시작 후 "작업 중" 상태가 남는 일은 없다.
class AgentActivity {
  static final ValueNotifier<String?> current = ValueNotifier<String?>(null);
}
