import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../design_tokens.dart';
import '../domain/station_models.dart';
import 'station_detail_info_row.dart';
import 'station_facility_detail_screen.dart';

const _stationFacilityCardRadius = BorderRadius.all(
  Radius.circular(EasySubwayRadius.sheet),
);

class StationFacilityCard extends StatelessWidget {
  const StationFacilityCard({
    required this.facility,
    required this.station,
    required this.onReportTap,
    super.key,
  });

  final StationFacilityInfo facility;
  final StationDetail station;
  final VoidCallback onReportTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: facility.semanticLabel,
      button: true,
      onTap: () => _openFacilityDetail(context),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        color: Colors.white,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: _stationFacilityCardRadius,
          side: BorderSide(color: EasySubwayAccessibleColors.line),
        ),
        child: InkWell(
          key: Key('stationFacilityCard-${facility.id}'),
          borderRadius: _stationFacilityCardRadius,
          onTap: () => _openFacilityDetail(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  facility.name,
                  style: textTheme.titleMedium?.copyWith(
                    color: EasySubwayAccessibleColors.text,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                // 정상 시설은 필 없이 조용히 표시하고, 문제(고장·공사)일 때만
                // 상태 필 하나만 노출한다. 시설 종류는 이름에 이미 포함되고,
                // '이용 가능'='정상' 중복과 종류 필은 제거한다.
                if (facility.needsAttention) ...[
                  const SizedBox(height: 10),
                  _StationDetailTextPill(text: facility.statusTitle),
                ],
                const SizedBox(height: 12),
                StationDetailInfoRow(
                  icon: Icons.place_outlined,
                  text: facility.locationLabel,
                ),
                const SizedBox(height: 6),
                StationDetailInfoRow(
                  icon: Icons.event_available,
                  text: facility.updatedLabel,
                ),
                const SizedBox(height: 8),
                // 상용 리스트 항목처럼 카드 전체 탭으로 상세에 들어가고(우측 ›로
                // 암시), 보조 액션 '시설 알려주기'는 텍스트 버튼 수준으로 낮춘다.
                // 카드 탭과 중복되던 '상세 보기' 텍스트는 제거한다.
                Row(
                  children: [
                    Semantics(
                      container: true,
                      label: '${facility.name} 시설 알려주기',
                      button: true,
                      onTap: onReportTap,
                      child: ExcludeSemantics(
                        child: TextButton.icon(
                          key: Key('facilityReportButton-${facility.id}'),
                          onPressed: onReportTap,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                          ),
                          icon: const Icon(Icons.report_outlined, size: 20),
                          label: const Text('시설 알려주기'),
                        ),
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.chevron_right,
                      color: EasySubwayAccessibleColors.mutedText,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openFacilityDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FacilityDetailScreen(
          station: station,
          facility: facility,
          onReportTap: onReportTap,
        ),
      ),
    );
  }
}

class _StationDetailTextPill extends StatelessWidget {
  const _StationDetailTextPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    // 유형·품질 라벨은 상태 의미가 없으므로 틴트 필 대신 중립 아웃라인으로.
    return Container(
      decoration: BoxDecoration(
        color: EasySubwayAccessibleColors.surface,
        borderRadius: _stationFacilityCardRadius,
        border: Border.all(color: EasySubwayAccessibleColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: EasySubwayAccessibleColors.secondaryText,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}
