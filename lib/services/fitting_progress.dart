import 'package:flutter/foundation.dart';

// 피팅룸 결과 카드가 접혀서(플로팅 아이콘으로 대체 표시) 있는지 — AppShell
// 레벨의 플로팅 아이콘과 fitting_room_screen.dart가 공유하는 전역 상태다.
// AgentActivity와 동일한 static ValueNotifier 패턴. 앱 재시작 시 초기화되므로
// "접힌 채로 남는" 상태가 새 세션까지 이어지는 일은 없다.
class FittingProgress {
  static final ValueNotifier<bool> collapsed = ValueNotifier<bool>(false);
}
