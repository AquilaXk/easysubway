import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../app/easy_subway_family_app_bar.dart';
import '../../../design_tokens.dart';
import '../../../facility_status.dart';
import '../domain/station_models.dart';
import 'station_detail_info_row.dart';
import 'station_info_basis_disclosure.dart';

const _stationFacilityDetailPagePadding = EdgeInsets.fromLTRB(20, 12, 20, 32);

class FacilityDetailScreen extends StatelessWidget {
  const FacilityDetailScreen({
    required this.station,
    required this.facility,
    required this.onReportTap,
    super.key,
  });

  final StationDetail station;
  final StationFacilityInfo facility;
  final VoidCallback onReportTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = _facilityStatusNoticeIconColor(
      facility.statusPresentation.severity,
    );
    return Scaffold(
      backgroundColor: EasySubwayAccessibleColors.surface,
      appBar: EasySubwayFamilyAppBar(
        key: const Key('facilityDetailAppBar'),
        title: Text(
          facility.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backButtonKey: const Key('facilityDetailBackButton'),
        dividerKey: const Key('facilityDetailHeaderDivider'),
      ),
      body: SafeArea(
        child: ListView(
          padding: _stationFacilityDetailPagePadding,
          children: [
            _FacilityDetailSectionTitle(title: '상태'),
            const SizedBox(height: 12),
            Semantics(
              label:
                  '${_facilityStatusTitle(facility)}, '
                  '${facilityStatusDisplayLabel(statusLabel: facility.statusLabel, severityLabel: facility.severityLabel)}, '
                  '${_facilityDetailStatusDescription(facility)}',
              child: ExcludeSemantics(
                child: Padding(
                  key: Key('facilityDetailStatusNotice-${facility.id}'),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _facilityStatusTitle(facility),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: statusColor,
                                    fontWeight: FontWeight.w700,
                                    height: 1.25,
                                  ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              facilityStatusDisplayLabel(
                                statusLabel: facility.statusLabel,
                                severityLabel: facility.severityLabel,
                              ),
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: EasySubwayAccessibleColors.mutedText,
                                    fontWeight: FontWeight.w700,
                                    height: 1.3,
                                  ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _facilityDetailStatusDescription(facility),
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: EasySubwayAccessibleColors.mutedText,
                                    fontWeight: FontWeight.w700,
                                    height: 1.3,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const _FacilityDetailSectionTitle(title: '위치'),
            const SizedBox(height: 8),
            StationDetailInfoRow(
              icon: Icons.train_outlined,
              text: '${station.nameKo}역',
            ),
            const SizedBox(height: 10),
            StationDetailInfoRow(
              icon: Icons.stairs_outlined,
              text: _facilityFloorLabel(facility),
            ),
            const SizedBox(height: 10),
            StationDetailInfoRow(
              icon: Icons.place_outlined,
              text: facility.locationLabel,
            ),
            const SizedBox(height: 10),
            StationDetailInfoRow(
              icon: Icons.event_available,
              text: facility.updatedLabel,
            ),
            const SizedBox(height: 20),
            const _FacilityDetailSectionTitle(title: '이용 안내'),
            const SizedBox(height: 8),
            Text(
              facility.nextActionDescription,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: EasySubwayAccessibleColors.secondaryText,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: EasySubwayTouchTarget.primary,
              width: double.infinity,
              child: FilledButton.icon(
                key: Key('facilityDetailReportButton-${facility.id}'),
                onPressed: () {
                  Navigator.of(context).pop();
                  onReportTap();
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(
                    EasySubwayTouchTarget.primary,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(EasySubwayRadius.card),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                icon: const Icon(Icons.report_outlined),
                label: const Text('시설 제보'),
              ),
            ),
            const SizedBox(height: 16),
            StationInfoBasisDisclosure(
              labels: [
                facility.fieldValidationLabel,
                facility.confidenceLabel,
                facility.dataSourceLabel,
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _facilityFloorLabel(StationFacilityInfo facility) {
  final from = facility.floorFrom.trim();
  final to = facility.floorTo.trim();
  if (from.isEmpty && to.isEmpty) {
    return '연결 위치 미확인';
  }
  if (from.isEmpty || to.isEmpty) {
    return '연결 위치 ${from.isEmpty ? to : from}';
  }
  return '연결 위치 $from ↔ $to';
}

String _facilityDetailStatusDescription(StationFacilityInfo facility) {
  if (facility.needsAttention) {
    return '현장 안내와 다르면 시설 제보로 알려 주세요.';
  }
  return '시설 안내가 다르면 시설 제보로 알려 주세요.';
}

String _facilityStatusTitle(StationFacilityInfo facility) {
  return facility.statusTitle;
}

Color _facilityStatusNoticeIconColor(FacilityStatusSeverity severity) {
  return switch (severity) {
    FacilityStatusSeverity.blocked => EasySubwayAccessibleColors.red,
    FacilityStatusSeverity.caution => EasySubwayAccessibleColors.amber,
    FacilityStatusSeverity.needsInfo => EasySubwayAccessibleColors.brand,
    FacilityStatusSeverity.normal => EasySubwayAccessibleColors.mint,
  };
}

class _FacilityDetailSectionTitle extends StatelessWidget {
  const _FacilityDetailSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: EasySubwayAccessibleColors.scaffoldSurface,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: EasySubwayAccessibleColors.secondaryText,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
