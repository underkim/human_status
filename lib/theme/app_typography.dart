import 'package:flutter/material.dart';

/// 숫자(레벨·XP·금액·날짜) 전용 스타일. 자릿수가 흔들리지 않도록
/// tabularFigures를 켠다 — 별도 모노스페이스 폰트를 번들하지 않고도
/// 시스템 폰트에서 계기판처럼 정렬된 숫자를 얻는 표준 방법이다.
class AppTypography {
  static const _tabular = [FontFeature.tabularFigures()];

  static TextStyle dataLarge({Color? color, FontWeight weight = FontWeight.w700}) => TextStyle(
        fontSize: 26,
        fontWeight: weight,
        fontFeatures: _tabular,
        color: color,
      );

  static TextStyle dataMedium({Color? color, FontWeight weight = FontWeight.w600}) => TextStyle(
        fontSize: 15,
        fontWeight: weight,
        fontFeatures: _tabular,
        color: color,
      );

  static TextStyle dataSmall({Color? color, FontWeight weight = FontWeight.w500}) => TextStyle(
        fontSize: 12,
        fontWeight: weight,
        fontFeatures: _tabular,
        color: color,
      );

  /// 섹션 라벨용 소문자 대문자 변환은 문자열 쪽에서 `.toUpperCase()`로
  /// 처리한다(Flutter TextStyle에는 CSS의 text-transform이 없음).
  static TextStyle labelCaps({Color? color}) => TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: color,
      );
}
