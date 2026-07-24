import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app_intents.dart';

/// Windows/macOS/Linux/Web에서만 앱 단축키를 설치한다 — Android/iOS는 같은
/// 키 이벤트를 소비하지 않고 그대로 흘려보내, 외장 키보드가 있어도 기본
/// 플랫폼 동작(Tab/Enter/Space 등)이 무해하게 유지된다.
bool get isDesktopShortcutPlatform =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.linux;

/// Windows/macOS/Linux 네이티브 빌드에서만 켜는, [isDesktopShortcutPlatform]의
/// 부분집합. Ctrl+Tab처럼 모든 주요 브라우저가 페이지 JS에 넘기지 않고
/// 브라우저 자체 탭 전환으로 가로채는 키는 Web에서 아예 등록해도 동작하지
/// 않으므로 — 대신 Web은 이 조합에서 제외해 혼선을 주지 않는다.
bool get isNativeDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

/// macOS(그리고 macOS Safari 등에서 실행되는 Web)에서는 Cmd(meta), 그 외
/// Windows/Linux/Web에서는 Ctrl(control)을 주 modifier로 쓴다.
bool get _useMetaModifier =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

SingleActivator _modifierKey(LogicalKeyboardKey key) =>
    SingleActivator(key, control: !_useMetaModifier, meta: _useMetaModifier);

/// `HomeShell` 전역에서 켜는 탭 전환 단축키(Ctrl/Cmd+1..5). 모바일에서는
/// 빈 맵을 돌려줘 `Shortcuts`가 사실상 아무 키도 가로채지 않는다.
Map<ShortcutActivator, Intent> homeShellShortcuts() {
  if (!isDesktopShortcutPlatform) return const {};
  const digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
  ];
  return {
    for (var i = 0; i < digits.length; i++)
      _modifierKey(digits[i]): SelectHomeTabIntent(i),
  };
}

/// 퀘스트 화면 전용 단축키: 검색 열기(Ctrl/Cmd+F), 새 퀘스트(Ctrl/Cmd+N),
/// 검색 닫기(Escape — 검색이 열려 있을 때만 의미가 있고, `Actions.
/// isEnabled`로 그 조건을 건다), 탭 순환(Ctrl/Cmd+Tab, +Shift로 역방향 —
/// 네이티브 데스크톱에서만. Web은 Ctrl+Tab을 브라우저가 자체 탭 전환으로
/// 가로채 페이지까지 이벤트가 오지 않는다).
Map<ShortcutActivator, Intent> questsScreenShortcuts() {
  if (!isDesktopShortcutPlatform) return const {};
  return {
    _modifierKey(LogicalKeyboardKey.keyF): const SearchQuestsIntent(),
    _modifierKey(LogicalKeyboardKey.keyN): const CreateQuestIntent(),
    const SingleActivator(LogicalKeyboardKey.escape):
        const DismissLocalUiIntent(),
    if (isNativeDesktopPlatform) ...{
      SingleActivator(
        LogicalKeyboardKey.tab,
        control: !_useMetaModifier,
        meta: _useMetaModifier,
      ): const CycleQuestTabIntent(
        1,
      ),
      SingleActivator(
        LogicalKeyboardKey.tab,
        control: !_useMetaModifier,
        meta: _useMetaModifier,
        shift: true,
      ): const CycleQuestTabIntent(
        -1,
      ),
    },
  };
}
