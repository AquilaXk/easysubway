import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../domain/station_models.dart';
import 'station_detail_info_row.dart';
import 'station_facility_detail_screen.dart';

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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                container: true,
                label: facility.semanticLabel,
                button: true,
                onTap: () => _openFacilityDetail(context),
                child: ExcludeSemantics(
                  child: InkWell(
                    key: Key('stationFacilityCard-${facility.id}'),
                    onTap: () => _openFacilityDetail(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                facility.name,
                                style: textTheme.titleMedium?.copyWith(
                                  color: EasySubwayAccessibleColors.text,
                                  fontWeight: FontWeight.w700,
                                  height: 1.25,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              color: EasySubwayAccessibleColors.mutedText,
                            ),
                          ],
                        ),
                        // 정상 시설은 필 없이 조용히 표시하고, 문제(고장·공사)일 때만
                        // 상태 문구를 노출한다.
                        if (facility.needsAttention) ...[
                          const SizedBox(height: 8),
                          Text(
                            facility.statusTitle,
                            style: textTheme.bodyMedium?.copyWith(
                              color: EasySubwayAccessibleColors.secondaryText,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        StationDetailInfoRow(
                          icon: Icons.place_outlined,
                          text: facility.locationLabel,
                        ),
                        const SizedBox(height: 6),
                        StationDetailInfoRow(
                          icon: Icons.event_available,
                          text: facility.updatedLabel,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Semantics(
                container: true,
                label: '${facility.name} 시설 제보',
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
                    label: const Text('시설 제보'),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(
          height: 1,
          thickness: 1,
          color: EasySubwayAccessibleColors.line,
        ),
      ],
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
