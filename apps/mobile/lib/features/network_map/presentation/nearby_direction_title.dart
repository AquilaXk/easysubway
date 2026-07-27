import 'package:flutter/material.dart';

import '../../../accessible_design.dart';

/// 주변역 패널의 "○○ 방면" 제목 (오너 스펙 2026-07-16, #2200).
///
/// 역명 부분은 선택 노선색, " 방면" 부분은 #2F2F2F로 스타일만 분리한다. 라벨
/// 문자열(데이터 포맷)은 조작하지 않는다 — "방면"으로 끝나지 않으면 전체를
/// 노선색으로 그린다. 실시간·시간표 열이 공유하는 단일 스타일이다.
class NearbyDirectionTitle extends StatelessWidget {
  const NearbyDirectionTitle({
    required this.label,
    required this.lineColor,
    super.key,
  });

  static const _suffix = '방면';
  static const _suffixColor = EasySubwayAccessibleColors.contentPrimary;
  static const _style = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w900,
    height: 20 / 14,
  );

  final String label;
  final Color lineColor;

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    if (label.endsWith(_suffix)) {
      final head = label.substring(0, label.length - _suffix.length);
      final name = head.trimRight();
      final gap = head.substring(name.length);
      if (name.isNotEmpty) {
        spans.add(
          TextSpan(
            text: name,
            style: TextStyle(color: lineColor),
          ),
        );
      }
      spans.add(
        TextSpan(
          text: '$gap$_suffix',
          style: const TextStyle(color: _suffixColor),
        ),
      );
    } else {
      spans.add(
        TextSpan(
          text: label,
          style: TextStyle(color: lineColor),
        ),
      );
    }
    return Text.rich(
      TextSpan(style: _style, children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
    );
  }
}

/// 실시간 도착 정보 한 행("○○행" + 도착 안내). 오너 스펙(#2200)의 방면 제목
/// 개편에서도 이 행의 위젯·폰트·색·간격은 무변경으로 유지한다(회귀 고정).
class NearbyArrivalRow extends StatelessWidget {
  const NearbyArrivalRow({
    required this.destination,
    required this.eta,
    super.key,
  });

  final String destination;
  final String eta;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        children: [
          if (destination.isNotEmpty)
            Text(
              '$destination행',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: EasySubwayAccessibleColors.contentPrimary,
                fontSize: 13,
                height: 1.3,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (eta.isNotEmpty)
            Text(
              eta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: EasySubwayAccessibleColors.secondaryText,
                fontSize: 12,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}
