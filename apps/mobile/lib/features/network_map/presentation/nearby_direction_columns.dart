import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import 'nearby_direction_title.dart';

/// 주변역 패널의 열 하나. [rows]가 비면 열차 정보가 없는 열이라 대시('-')를 그린다.
/// 제목은 항상 "○○ 방면"(비어 있으면 생략)으로 노출한다(오너 스펙 #2200 QA).
class NearbyPanelColumn {
  const NearbyPanelColumn({required this.title, this.rows = const <Widget>[]});

  final String title;
  final List<Widget> rows;

  bool get hasData => rows.isNotEmpty;
}

/// 주변역 패널 열 배치 계획. [dataIndex]가 null이면 인접역에서 유도한 대시 열이다.
class NearbyColumnSlot {
  const NearbyColumnSlot({required this.title, required this.dataIndex});

  final String title;
  final int? dataIndex;
}

/// 열차 정보가 있는 방면 라벨 [dataTitles]과 인접역 이름으로 주변역 패널의 열
/// 구성을 결정한다(오너 스펙 #2200 QA). 열차 정보가 없어도 인접역에서 "○○ 방면"을
/// 유도해 두 열 스켈레톤을 유지하고, 유도할 방면이 하나도 없으면 빈 리스트를
/// 반환한다(호출부가 기존 대시 폴백으로 수렴).
///
/// - 데이터 방면이 2개 이상: 인접역과 무관하게 기존 두 데이터 열을 유지한다.
/// - 데이터 방면이 1개: 데이터 열 + 인접역 유도 대시 열. 대시 열의 인접역은
///   데이터 라벨에 포함되지 않은 쪽을 고르고(판단 불가면 rightName 우선), 노선
///   바와 같은 쪽(왼쪽=이전역)에 배치한다.
/// - 데이터 방면이 0개: 좌(이전역)-우(다음역) 순서의 대시 열만 만든다.
List<NearbyColumnSlot> resolveNearbyColumnSlots({
  required List<String> dataTitles,
  String? leftName,
  String? rightName,
}) {
  final left = _trimToNull(leftName);
  final right = _trimToNull(rightName);

  if (dataTitles.length >= 2) {
    return [
      NearbyColumnSlot(title: dataTitles[0], dataIndex: 0),
      NearbyColumnSlot(title: dataTitles[1], dataIndex: 1),
    ];
  }

  if (dataTitles.length == 1) {
    final label = dataTitles.first;
    final dataSlot = NearbyColumnSlot(title: label, dataIndex: 0);
    final other = _pickOtherAdjacent(label: label, left: left, right: right);
    if (other == null) {
      return [dataSlot];
    }
    final dashSlot = NearbyColumnSlot(
      title: _directionTitle(other.name),
      dataIndex: null,
    );
    return other.isLeft ? [dashSlot, dataSlot] : [dataSlot, dashSlot];
  }

  return [
    if (left != null)
      NearbyColumnSlot(title: _directionTitle(left), dataIndex: null),
    if (right != null)
      NearbyColumnSlot(title: _directionTitle(right), dataIndex: null),
  ];
}

String _directionTitle(String name) => '$name 방면';

String? _trimToNull(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

class _AdjacentPick {
  const _AdjacentPick(this.name, {required this.isLeft});

  final String name;
  final bool isLeft;
}

_AdjacentPick? _pickOtherAdjacent({
  required String label,
  required String? left,
  required String? right,
}) {
  // rightName 우선 순서로 후보를 만들고, 라벨에 포함되지 않은 쪽을 먼저 고른다.
  final candidates = <_AdjacentPick>[
    if (right != null) _AdjacentPick(right, isLeft: false),
    if (left != null) _AdjacentPick(left, isLeft: true),
  ];
  if (candidates.isEmpty) {
    return null;
  }
  for (final candidate in candidates) {
    if (!label.contains(candidate.name)) {
      return candidate;
    }
  }
  // 판단 불가(모두 라벨에 포함) → rightName 우선(후보 목록의 첫 항목).
  return candidates.first;
}

/// 주변역 패널의 열 본문. 각 열은 "○○ 방면" 제목과 본문을 그리고, 데이터가 없는
/// 열은 대시('-')로 표시한다. 열 사이에는 기존과 동일한 1×46 세로 구분선을 둔다.
class NearbyPanelColumns extends StatelessWidget {
  const NearbyPanelColumns({
    required this.columns,
    required this.lineColor,
    super.key,
  });

  /// 기존 `_SubwayDataUnavailable`의 대시 스타일(16sp w700 #2F2F2F)을 재사용한다.
  static const dashStyle = TextStyle(
    color: Color(0xFF2F2F2F),
    fontSize: 16,
    fontWeight: FontWeight.w700,
  );

  final List<NearbyPanelColumn> columns;
  final Color lineColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < columns.length; index++) ...[
          if (index > 0)
            const SizedBox(
              height: 46,
              child: VerticalDivider(
                color: EasySubwayAccessibleColors.arrivalColumnDivider,
                width: 30,
              ),
            ),
          Expanded(child: _buildColumn(columns[index])),
        ],
      ],
    );
  }

  Widget _buildColumn(NearbyPanelColumn column) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (column.title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: NearbyDirectionTitle(
              label: column.title,
              lineColor: lineColor,
            ),
          ),
        if (column.hasData)
          ...column.rows
        else
          const SizedBox(
            height: 46,
            child: Center(child: Text('-', style: dashStyle)),
          ),
      ],
    );
  }
}
