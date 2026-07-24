import 'package:flutter/widgets.dart';

/// HomeShell의 5개 탭(홈/퀘스트/목표/재무/더보기) 중 [index]로 전환한다.
class SelectHomeTabIntent extends Intent {
  final int index;

  const SelectHomeTabIntent(this.index);
}

/// 퀘스트 화면의 검색을 열고 검색 입력에 포커스를 준다.
class SearchQuestsIntent extends Intent {
  const SearchQuestsIntent();
}

/// 퀘스트 화면에서 새 퀘스트 작성 화면으로 이동한다(기존 FAB과 같은 경로).
class CreateQuestIntent extends Intent {
  const CreateQuestIntent();
}

/// 현재 화면에서 가장 안쪽에 열린 로컬 UI(검색 등)를 닫는다. 다이얼로그의
/// Escape 기본 동작(Navigator pop)은 이 Intent를 거치지 않고 프레임워크가
/// 그대로 처리한다.
class DismissLocalUiIntent extends Intent {
  const DismissLocalUiIntent();
}
