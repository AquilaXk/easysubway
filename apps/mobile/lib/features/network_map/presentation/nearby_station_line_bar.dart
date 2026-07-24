import 'package:flutter/material.dart';

/// 주변역 패널의 이전-현재-다음역 노선 표시 바 (오너 스펙 2026-07-16, #2200).
///
/// 좌우 바는 선택 노선색 단일 소스([lineColor])를 동일하게 쓰고(2호선이면 양쪽
/// 모두 #00A84D), 바깥 끝만 반원이다. 노선 바를 하나의 연속 바로 먼저 그린 뒤
/// 흰 캡슐을 Stack으로 겹쳐, 캡슐 뒤에서 노선이 끊겨 보이지 않게 한다. 크기는
/// LayoutBuilder로 패널 너비 비율에 맞춘다.
class NearbyStationLineBar extends StatelessWidget {
  const NearbyStationLineBar({
    required this.leftName,
    required this.rightName,
    required this.stationName,
    required this.badgeText,
    required this.lineColor,
    this.onStationNameTap,
    super.key,
  });

  final String? leftName;
  final String? rightName;
  final String stationName;
  final String badgeText;
  final Color lineColor;

  /// 현재 역 이름 탭 → 역 상세. null이면 이름만 표시한다.
  final VoidCallback? onStationNameTap;

  @override
  Widget build(BuildContext context) {
    final openDetail = onStationNameTap;
    return Semantics(
      container: true,
      label: openDetail == null
          ? _semanticsLabel()
          : '${_semanticsLabel()}, 상세 보기',
      button: openDetail != null,
      onTap: openDetail,
      child: ExcludeSemantics(child: _buildBar()),
    );
  }

  String _semanticsLabel() {
    final parts = <String>[];
    final left = leftName;
    if (left != null && left.isNotEmpty) {
      parts.add('이전역 $left');
    }
    parts.add(
      badgeText.isEmpty ? '현재역 $stationName' : '현재역 $badgeText $stationName',
    );
    final right = rightName;
    if (right != null && right.isNotEmpty) {
      parts.add('다음역 $right');
    }
    return parts.join(', ');
  }

  Widget _buildBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fullWidth = constraints.maxWidth;
        final margin = fullWidth * 0.03476;
        final barWidth = fullWidth - margin * 2;
        final barHeight = barWidth * 28 / 348;
        final centerWidth = barWidth * 0.37069;
        final endRadius = barHeight / 2;
        final capsuleWidth = centerWidth;
        final capsuleHeight = capsuleWidth * 41 / 129;
        final badgeDiameter = capsuleWidth * 0.18;
        final stationNameSize = (capsuleHeight * 0.42).clamp(16.0, 20.0);
        return Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Center(
            child: SizedBox(
              width: barWidth,
              height: capsuleHeight,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    key: const Key('nearbyStationLineBarTrack'),
                    width: barWidth,
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: lineColor,
                      borderRadius: BorderRadius.all(
                        Radius.circular(endRadius),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(child: _SideName(name: leftName)),
                        SizedBox(width: centerWidth),
                        Expanded(child: _SideName(name: rightName)),
                      ],
                    ),
                  ),
                  Container(
                    key: const Key('nearbyStationLineBarCapsule'),
                    width: capsuleWidth,
                    height: capsuleHeight,
                    alignment: Alignment.center,
                    padding: EdgeInsets.symmetric(
                      horizontal: capsuleWidth * 0.08,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: lineColor, width: 3),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (badgeText.isNotEmpty) ...[
                          _LineBadge(
                            diameter: badgeDiameter,
                            color: lineColor,
                            text: badgeText,
                          ),
                          const SizedBox(width: 7),
                        ],
                        Flexible(
                          child: _StationNameLabel(
                            stationName: stationName,
                            fontSize: stationNameSize,
                            onTap: onStationNameTap,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StationNameLabel extends StatelessWidget {
  const _StationNameLabel({
    required this.stationName,
    required this.fontSize,
    this.onTap,
  });

  final String stationName;
  final double fontSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      stationName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: const Color(0xFF102A2C),
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        height: 1.1,
      ),
    );
    final tap = onTap;
    if (tap == null) {
      return KeyedSubtree(
        key: const Key('nearbyStationLineBarStationName'),
        child: text,
      );
    }
    // TalkBack 라벨·동작은 상위 NearbyStationLineBar Semantics가 담당한다.
    return InkWell(
      key: const Key('nearbyStationLineBarStationName'),
      onTap: tap,
      borderRadius: BorderRadius.circular(8),
      child: text,
    );
  }
}

class _SideName extends StatelessWidget {
  const _SideName({required this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    final value = name;
    if (value == null || value.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _LineBadge extends StatelessWidget {
  const _LineBadge({
    required this.diameter,
    required this.color,
    required this.text,
  });

  final double diameter;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Padding(
        padding: EdgeInsets.all(diameter * 0.12),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            maxLines: 1,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}
