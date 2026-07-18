import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../design_tokens.dart';
import '../../../facility_status.dart';
import '../application/station_detail_controller.dart';
import '../domain/station_models.dart';
import 'station_detail_info_row.dart';
import 'station_info_basis_disclosure.dart';

const _stationFacilityDetailPagePadding = EdgeInsets.fromLTRB(20, 20, 20, 32);
const _stationFacilityDetailCardRadius = BorderRadius.all(
  Radius.circular(EasySubwayRadius.sheet),
);

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
    final statusIconColor = _facilityStatusNoticeIconColor(
      facility.statusPresentation.severity,
    );
    final statusIcon = _facilityStatusNoticeIcon(
      facility.statusPresentation.severity,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('시설 상세')),
      body: SafeArea(
        child: ListView(
          padding: _stationFacilityDetailPagePadding,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    facility.layoutSummaryIcon,
                    color: EasySubwayAccessibleColors.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${station.nameKo}역',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: EasySubwayAccessibleColors.mutedText,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          facility.name,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: EasySubwayAccessibleColors.text,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              key: Key('facilityDetailStatusNotice-${facility.id}'),
              decoration: BoxDecoration(
                color: EasySubwayAccessibleColors.surface,
                borderRadius: _stationFacilityDetailCardRadius,
                border: Border.all(color: EasySubwayAccessibleColors.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 4, color: statusIconColor),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(statusIcon, color: statusIconColor, size: 28),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _facilityStatusTitle(facility),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: statusIconColor,
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
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: EasySubwayAccessibleColors
                                              .mutedText,
                                          fontWeight: FontWeight.w700,
                                          height: 1.3,
                                        ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _facilityDetailStatusDescription(facility),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: EasySubwayAccessibleColors
                                              .mutedText,
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            const _StationDetailSectionTitle(title: '위치'),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              color: Colors.white,
              elevation: 0,
              shape: const RoundedRectangleBorder(
                borderRadius: _stationFacilityDetailCardRadius,
                side: BorderSide(color: EasySubwayAccessibleColors.line),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
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
                  ],
                ),
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
            const SizedBox(height: 16),
            FilledButton.icon(
              key: Key('facilityDetailReportButton-${facility.id}'),
              onPressed: () {
                Navigator.of(context).pop();
                onReportTap();
              },
              icon: const Icon(Icons.report_outlined),
              label: const Text('시설 알려주기'),
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
    return '현장 안내와 다르면 시설 알려주기로 알려 주세요.';
  }
  return '시설 안내가 다르면 시설 알려주기로 알려 주세요.';
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

IconData _facilityStatusNoticeIcon(FacilityStatusSeverity severity) {
  return switch (severity) {
    FacilityStatusSeverity.blocked => Icons.warning_amber,
    FacilityStatusSeverity.caution => Icons.report_problem_outlined,
    FacilityStatusSeverity.needsInfo => Icons.info_outline,
    FacilityStatusSeverity.normal => Icons.check_circle,
  };
}

class _StationDetailSectionTitle extends StatelessWidget {
  const _StationDetailSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: EasySubwayAccessibleColors.text,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
      ),
    );
  }
}
