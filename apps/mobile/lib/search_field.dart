import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'accessible_design.dart';

/// #2083 홈 노선도 편집 모드와 역 검색 화면의 입력 필드가 픽셀 단위로 동일한
/// 시각 규격을 공유하도록 추출한 공용 검색 입력 위젯. 두 화면이 같은 시각
/// 껍데기(40px 박스·아이콘 배치·단일 줄 TextField·지우기 버튼)를 소비해 규격이
/// 어긋나지 않게 한다. 홈 idle 검색 버튼도 아래 공유 상수를 참조해 탭 전환 시
/// 박스가 점프하지 않는다(#1933).

/// idle/active 시각 박스 radius(8).
const easySubwaySearchFieldRadius = BorderRadius.all(Radius.circular(8));

/// idle/active가 공유하는 시각 박스 높이(40). 바깥 터치타겟(56)과 분리된다.
/// 17sp 입력 글자 대비 내부 상하 여백을 줄여 검색창이 덜 헐렁하게 보이게 한다(#2436).
const easySubwaySearchFieldVisualHeight = 40.0;

/// 시각 박스 좌우 내부 패딩(12).
const easySubwaySearchFieldHorizontalPadding = 12.0;

/// 시각 박스 테두리 두께(1.0). 선 색은 전역 [EasySubwayAccessibleColors.line]보다
/// 진하게 두어 얇아도 윤곽이 읽히게 한다(#2436).
const easySubwaySearchFieldBorderWidth = 1.0;

/// 검색·출발/도착/경유 박스 외곽선.
/// 표면 `#F6F8F9` 대비 약 3:1 이상인 전용 색(구분선 `#C5CDD4`와 분리).
const easySubwaySearchFieldBorderColor =
    EasySubwayAccessibleColors.interactionSecondaryBorder;

/// 검색/지우기 아이콘 시각 크기(22).
const easySubwaySearchFieldIconSize = 22.0;

/// 아이콘과 텍스트 사이 간격(8).
const easySubwaySearchFieldIconGap = 8.0;

/// hint(placeholder) 텍스트 스타일. mutedText·17·w600·height 미지정.
const easySubwaySearchFieldHintStyle = TextStyle(
  color: EasySubwayAccessibleColors.mutedText,
  fontSize: 17,
  fontWeight: FontWeight.w600,
);

/// 입력(편집) 텍스트 스타일. hint와 glyph 메트릭(fontSize·fontWeight·height
/// 미지정)을 동일하게 두고 색만 본문색으로 바꾼다. #2082: 입력 style에만
/// height를 지정하면 hint와 glyph 중심이 어긋나 편집 텍스트가 시각 박스 중앙
/// 보다 위로 뜨는 회귀가 있었다. hint와 동일 메트릭을 공유해 중앙 정합을
/// 보장한다.
const easySubwaySearchFieldInputStyle = TextStyle(
  color: EasySubwayAccessibleColors.text,
  fontSize: 17,
  fontWeight: FontWeight.w600,
);

/// 홈 편집 모드와 역 검색 화면이 공유하는 편집 가능한 검색 입력 필드. 바깥
/// 터치타겟(56)은 확보하되, 안쪽 시각 박스는 40px 고정 높이·패딩(12)·테두리·
/// 아이콘 배치를 공유 상수로 재사용한다. TextField 자체는 border/배경 없이 텍스트
/// 편집만 담당하고, 시각적 테두리·배경·아이콘은 시각 껍데기 Container가 그린다.
///
/// 시각(40px 박스)과 히트 영역(≥48px)은 Stack으로 분리한다: 배경 레이어가
/// 40px 시각 껍데기를 그리고, 그 위 Positioned.fill 레이어에서 TextField가
/// 바깥 터치타겟 높이(56)를 그대로 채우며 지우기 IconButton도 독립적인
/// 48x48 탭 타깃을 갖는다. TextField와 지우기 버튼을 하나의 semantics로
/// 병합하지 않아야 스크린리더 사용자가 '검색어 지우기' 액션에 별도로 접근할
/// 수 있다.
class EasySubwaySearchField extends StatelessWidget {
  const EasySubwaySearchField({
    required this.hintText,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.onSubmitted,
    this.onClear,
    this.semanticsLabel,
    super.key,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;

  /// placeholder이자 TalkBack 라벨. 호출부가 화면 맥락(출발/도착/경유 등)에
  /// 맞는 문구를 지정한다.
  final String hintText;

  /// 입력 후에도 스크린리더에 유지돼야 하는 슬롯 맥락 라벨. hint는 입력이 있으면
  /// InputDecorator가 지우므로 "출발역/경유역/도착역 이름을 입력해 주세요" 같은
  /// 맥락이 입력 후 소실된다(#2090). 이 값이 주어지면 필드 서브트리를
  /// [Semantics](label)로 감싸 입력 유무와 무관하게 맥락이 낭독되게 한다. 홈
  /// 노선도 검색은 hint 자체가 라벨 역할을 해 이 파라미터를 쓰지 않는다(라벨
  /// 이중 낭독 방지).
  final String? semanticsLabel;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final editController = controller;
    // #2090: 시스템 글자 배율을 키우면 고정 높이(시각 박스 40·입력 필드 48/56)가
    // 확대된 입력 줄을 세로로 잘라 WCAG 1.4.4를 위반한다. 배율에 비례해 시각 박스와
    // 터치타겟이 함께 자라도록 배율을 곱해 높이를 재도출한다. clamp(min: 1.0)로
    // 축소는 하지 않아 기본 배율(1.0)에서는 40/48/56 픽셀이 그대로 보존된다.
    final scaler = MediaQuery.textScalerOf(context);
    // 바깥 터치타겟: 기본 56, 배율에 비례해 확대(입력 줄이 자라도 필드가
    // 터치타겟보다 작아지지 않게). 배율 1.0에서 정확히 56.
    final touchTargetHeight = math.max(
      EasySubwayTouchTarget.general,
      scaler.scale(EasySubwayTouchTarget.general),
    );
    // #2082 재작업: 편집 텍스트를 홈 idle 검색 필드와 동일한 폰트 메트릭 독립
    // 방식으로 중앙 정렬한다. idle 필드는 Container(height 40) 안 Row가 고유 높이
    // Text를 crossAxis 중앙에 놓아 실기기 Noto Sans KR에서도 오프셋 0으로
    // 정합한다. 편집 필드도 TextField를 고유 높이(글자 줄)로 두고 Center로 시각
    // 박스 중앙에 놓아, 절대값 비대칭 패딩(구 21/9) 없이 동일 정합을 얻는다.
    // 비대칭 패딩은 FlutterTest 테스트 폰트 기준으로 맞춰 실기기 폰트에서는
    // 편향됐다(#2082 실기기 QA). 시각 박스 높이: 기본 40, 배율에 비례해 확대.
    final visualBoxHeight = math.max(
      easySubwaySearchFieldVisualHeight,
      scaler.scale(easySubwaySearchFieldVisualHeight),
    );
    final field = ConstrainedBox(
      // 터치 타겟(≥48, 실제로는 56)을 만족시키기 위해 필드 자체가 전체 높이를
      // 차지한다. 시각적 박스(40px)는 배경 레이어 Container가 idle 필드와
      // 동일하게 그리고, 입력/버튼 히트 영역은 그 위 레이어에서 시각 박스와
      // 독립적으로 ≥48px를 확보한다. 고정 높이 대신 minHeight를 써서 배율 확대
      // 시 안쪽 입력 줄이 세로로 자라도 잘리지 않게 한다(#2090).
      constraints: BoxConstraints(minHeight: touchTargetHeight),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 시각 껍데기: idle 필드와 픽셀 단위로 동일(높이 40, radius 8,
          // border 1.0·진한 외곽, surface 배경). 히트 영역과 분리된 순수 배경이다.
          // heroStationSearchInputBox 키는 홈/역 검색 두 화면 위젯 테스트가
          // 시각 박스 높이·중앙 정합을 검증하는 데 쓴다(두 화면은 동시에
          // 렌더되지 않아 키 충돌 없음). 배율 1.0에서는 40 고정, 확대 시 배율에
          // 비례해 커져 확대된 입력 줄을 담는다.
          Container(
            key: const Key('heroStationSearchInputBox'),
            height: visualBoxHeight,
            decoration: BoxDecoration(
              color: EasySubwayAccessibleColors.searchFieldSurface,
              border: Border.all(
                color: easySubwaySearchFieldBorderColor,
                width: easySubwaySearchFieldBorderWidth,
              ),
              borderRadius: easySubwaySearchFieldRadius,
            ),
          ),
          Positioned.fill(
            child: Padding(
              // idle의 콘텐츠 시작 위치와 동일: 테두리(1.0) + 패딩(12).
              padding: const EdgeInsets.symmetric(
                horizontal:
                    easySubwaySearchFieldBorderWidth +
                    easySubwaySearchFieldHorizontalPadding,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.search,
                    size: easySubwaySearchFieldIconSize,
                    color: EasySubwayAccessibleColors.iconMuted,
                  ),
                  const SizedBox(width: easySubwaySearchFieldIconGap),
                  Expanded(
                    // 바깥(56·배율확대)이 터치타겟 높이를 차지하고, 그 안 Center가
                    // 고유 높이 단일 줄 TextField를 세로 중앙에 놓는다(구현은 아래
                    // 194~196행 SizedBox(touchTargetHeight) + Center 참고). 이
                    // SizedBox 높이가 히트/semantics 영역을 48px 게이트 이상으로
                    // 키운다. #2090: SizedBox 높이를 배율에 비례해 키워(배율 1.0에서
                    // 정확히 48/56) 확대 시 입력 줄이 세로로 자라도 잘리지 않게 한다.
                    // 여러 줄(expands) 트릭을 쓰면 실기기에서 입력 텍스트와 IME 조합
                    // 밑줄이 첫 줄로 렌더돼 박스 상단에 붙는 회귀가 있어 단일 줄
                    // 필드를 유지한다.
                    //
                    // #2090 Finding 3: semanticsLabel이 주어지면 입력 필드
                    // 서브트리(지우기 버튼 제외)를 MergeSemantics + Semantics(label)
                    // 로 감싼다. hint는 입력이 있으면 사라지지만 라벨은 유지돼
                    // "출발/도착/경유역 이름을 입력해 주세요" 슬롯 맥락이 입력 후에도
                    // 낭독된다. MergeSemantics로 hint 노드를 라벨 노드에 병합해 입력
                    // 전 라벨 이중 낭독을 막는다. 지우기 버튼은 형제라 별도 탭
                    // 타깃/semantics를 유지한다.
                    child: MergeSemantics(
                      child: _maybeWrapSemantics(
                        // 터치타겟(56·배율확대) 안에서 단일 줄 필드를 세로 중앙에
                        // 놓는다. TextField는 고유 높이(글자 줄 높이 + isDense 최소
                        // 여백)로 두고 Center가 그 줄을 40px 시각 박스 중앙(=터치타겟
                        // 중앙)에 정렬한다. idle 필드가 Container(40) 안 Row로 고유
                        // 높이 Text를 중앙에 놓는 것과 같은 폰트 메트릭 독립 원리라,
                        // 실기기 Noto Sans KR에서 hint·캐럿·입력 글자가 시각 박스
                        // 중앙에 오프셋 0으로 정합함을 픽셀 판독으로 확인했다(정본 —
                        // docs/2082-qa). 절대값 비대칭 패딩(구 21/9)·고정 높이 박스 +
                        // textAlignVertical 조합은 실기기에서 입력 줄을 위/아래로
                        // 편향시켜 버렸다.
                        //
                        // 입력 필드 자체(고유 높이)의 semantics 노드는 40 미만이지만,
                        // 바깥 SizedBox(56)와 함께 MergeSemantics로 병합해 탭 타깃
                        // semantics 노드가 터치타겟 높이(≥48)를 갖게 한다(접근성 최소
                        // 탭 타깃). 지우기 버튼은 이 병합 밖 형제라 자체 탭 타깃·
                        // semantics를 유지한다.
                        SizedBox(
                          height: touchTargetHeight,
                          child: Center(
                            child: TextField(
                              key: const Key('stationSearchInput'),
                              controller: editController,
                              focusNode: focusNode,
                              autofocus: autofocus,
                              maxLines: 1,
                              textInputAction: TextInputAction.search,
                              // #2082: 입력 텍스트 style을 hint style과 동일 glyph
                              // 메트릭(fontSize 17·w600·height 미지정)으로 두고 색만
                              // 본문색으로 바꾼다. 두 style이 다른 height를 가지면
                              // hint와 편집 텍스트의 glyph 중심이 어긋난다.
                              style: easySubwaySearchFieldInputStyle,
                              // isDense + contentPadding 0 으로 필드 고유 높이를 글자
                              // 줄 높이로 만들고 Center로 중앙 정렬한다. isCollapsed·
                              // floatingLabelBehavior는 각각 탭 타깃·부유 라벨 회귀
                              // (#1933)를 유발해 쓰지 않는다.
                              decoration: InputDecoration(
                                hintText: hintText,
                                hintStyle: easySubwaySearchFieldHintStyle,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                              ),
                              onSubmitted: onSubmitted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 지우기 버튼은 입력 유무에 따라 나타난다. 컨트롤러를 직접
                  // 구독해(ListenableBuilder) 키 입력 시 이 작은 서브트리만
                  // 재빌드되게 한다 — 상위 화면/지도 chrome은 재빌드되지 않아
                  // 입력 지연을 막는다(#1915).
                  if (editController != null)
                    ListenableBuilder(
                      listenable: editController,
                      builder: (context, _) {
                        final hasQuery = editController.text.trim().isNotEmpty;
                        if (!hasQuery) {
                          return const SizedBox.shrink();
                        }
                        // 시각 아이콘은 22px이지만 탭 타깃은 독립적으로 48x48을
                        // 확보한다(top bar IconButton 패턴과 동일). 히트 영역은
                        // 40px 시각 박스 밖으로 넘치되 바깥 56px 터치타겟 안에
                        // 머물러 시각 박스 높이를 밀어 올리지 않는다.
                        return IconButton(
                          tooltip: '검색어 지우기',
                          onPressed: onClear ?? editController.clear,
                          style: IconButton.styleFrom(
                            minimumSize: const Size.square(48),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: EdgeInsets.zero,
                          ),
                          icon: const Icon(
                            Icons.close,
                            size: easySubwaySearchFieldIconSize,
                            color: EasySubwayAccessibleColors.iconMuted,
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return field;
  }

  /// [semanticsLabel]이 주어지면 입력 필드 서브트리를 슬롯 맥락 라벨로 감싼다.
  /// hint는 입력이 있으면 InputDecorator가 지워 "출발역/경유역/도착역 이름을
  /// 입력해 주세요" 맥락이 입력 후 소실되지만(#2090 Finding 3), 이 라벨은 입력
  /// 유무와 무관하게 유지된다. [MergeSemantics]로 hint 노드를 라벨 노드에 병합해
  /// 입력 전 라벨 이중 낭독을 막는다. 지우기 버튼은 이 서브트리 밖 형제라 자체
  /// 탭 타깃·semantics를 유지한다. 라벨이 없으면(홈 검색) 원본을 그대로 둔다.
  Widget _maybeWrapSemantics(Widget child) {
    final label = semanticsLabel;
    if (label == null) {
      return child;
    }
    return MergeSemantics(
      child: Semantics(label: label, textField: true, child: child),
    );
  }
}
