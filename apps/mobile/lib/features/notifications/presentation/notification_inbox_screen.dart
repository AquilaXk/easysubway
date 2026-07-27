import 'dart:async';

import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../app/app_components.dart';
import '../../../facility_report.dart';
import '../../../facility_status.dart';
import '../../../favorite_facility.dart';
import '../../../mobile_error_reporter.dart';
import '../../../notification_settings.dart';

class NotificationInboxScreen extends StatefulWidget {
  const NotificationInboxScreen({
    required this.favoriteFacilityRepository,
    required this.reportRepository,
    required this.notificationRepository,
    required this.notificationPermissionProvider,
    super.key,
  });

  final FavoriteFacilityRepository? favoriteFacilityRepository;
  final FacilityReportRepository reportRepository;
  final NotificationSettingsRepository? notificationRepository;
  final NotificationPermissionProvider? notificationPermissionProvider;

  @override
  State<NotificationInboxScreen> createState() =>
      _NotificationInboxScreenState();
}

class _NotificationInboxScreenState extends State<NotificationInboxScreen> {
  late Future<List<_NotificationInboxItem>> _itemsFuture;

  @override
  void initState() {
    super.initState();
    _itemsFuture = _loadItemsForDisplay();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('알림'),
        actions: [
          if (widget.notificationRepository != null)
            IconButton(
              tooltip: '알림 설정',
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<_NotificationInboxItem>>(
          future: _itemsFuture,
          builder: (context, snapshot) {
            final items = snapshot.data ?? const <_NotificationInboxItem>[];
            return RefreshIndicator(
              onRefresh: () async {
                final next = _loadItemsForDisplay();
                setState(() {
                  _itemsFuture = next;
                });
                try {
                  await next;
                } catch (error, stackTrace) {
                  reportMobileError(
                    error,
                    stackTrace,
                    context: '알림함 새로고침 중 예외가 발생했습니다.',
                  );
                }
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: mainListPagePadding,
                children: [
                  if (snapshot.connectionState != ConnectionState.done)
                    const LinearProgressIndicator(minHeight: 3),
                  if (snapshot.hasError)
                    HomeStateCard(
                      key: const Key('notificationInboxErrorState'),
                      icon: Icons.error_outline,
                      title: '알림을 불러오지 못했어요',
                      subtitle: '잠시 후 다시 시도해 주세요.',
                      actionLabel: '다시 시도',
                      onAction: () {
                        setState(() {
                          _itemsFuture = _loadItemsForDisplay();
                        });
                      },
                    )
                  else if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.notifications_none,
                            size: 44,
                            color: EasySubwayAccessibleColors.mutedText,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '새 알림이 없습니다',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: EasySubwayAccessibleColors.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '즐겨찾기 시설과 제보 상태가 바뀌면 여기에서 볼 수 있어요.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: EasySubwayAccessibleColors.mutedText,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    _NotificationInboxChips(items: items),
                    for (final item in items) _NotificationInboxRow(item: item),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<List<_NotificationInboxItem>> _loadItemsForDisplay() {
    final next = _loadItems();
    unawaited(
      next.catchError((Object error, StackTrace stackTrace) {
        return const <_NotificationInboxItem>[];
      }),
    );
    return next;
  }

  Future<List<_NotificationInboxItem>> _loadItems() async {
    final items = <_NotificationInboxItem>[];
    var loadFailed = false;
    final favoriteFacilityRepository = widget.favoriteFacilityRepository;
    if (favoriteFacilityRepository != null) {
      try {
        final facilities = await favoriteFacilityRepository
            .listFavoriteFacilities();
        for (final facility in facilities.where(isFacilityAlert)) {
          items.add(_NotificationInboxItem.facility(facility));
        }
      } catch (error, stackTrace) {
        loadFailed = true;
        reportMobileError(
          error,
          stackTrace,
          context: '알림함 즐겨찾기 시설 상태를 불러오는 중 예외가 발생했습니다.',
        );
      }
    }

    try {
      final reports = await widget.reportRepository.listMyReports();
      for (final report in reports) {
        items.add(_NotificationInboxItem.report(report));
      }
    } catch (error, stackTrace) {
      loadFailed = true;
      reportMobileError(
        error,
        stackTrace,
        context: '알림함 제보 상태를 불러오는 중 예외가 발생했습니다.',
      );
    }
    if (items.isEmpty && loadFailed) {
      throw StateError('notification inbox load failed');
    }
    return items;
  }

  void _openSettings() {
    final repository = widget.notificationRepository;
    if (repository == null) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationSettingsScreen(
          repository: repository,
          notificationPermissionProvider: widget.notificationPermissionProvider,
        ),
      ),
    );
  }
}

class _NotificationInboxItem {
  const _NotificationInboxItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.semanticLabel,
    required this.kind,
    this.report,
    this.severity = FacilityStatusSeverity.normal,
    this.actionLabel = '',
  });

  factory _NotificationInboxItem.facility(FavoriteFacility facility) {
    final name = facility.name.trim().isEmpty
        ? facility.typeLabel
        : facility.name;
    // 출처 라벨이 비어 있을 수 있어(무표시) 빈 값은 걸러 Semantics에 ", ," 유령
    // 세그먼트를 남기지 않는다(#2078).
    final semanticParts = <String>[
      '${facility.stationLabel} $name',
      '${facility.typeLabel} ${facility.statusLabel}',
      facility.severityLabel,
      facility.updatedLabel,
      facility.dataSourceLabel,
      facility.nextActionLabel,
    ].where((part) => part.trim().isNotEmpty);
    return _NotificationInboxItem(
      icon: _facilityIcon(facility.type),
      title: '${facility.stationLabel} $name',
      subtitle:
          '${facility.severityLabel} · ${facility.typeLabel} ${facility.statusLabel}',
      semanticLabel: semanticParts.join(', '),
      kind: '시설',
      severity: facility.statusPresentation.severity,
      actionLabel: facility.nextActionLabel,
    );
  }

  factory _NotificationInboxItem.report(FacilityReportResult report) {
    return _NotificationInboxItem(
      icon: Icons.report_outlined,
      title: '제보 ${report.statusLabel}',
      subtitle: '제보 번호 ${report.displayReceiptCode}',
      semanticLabel:
          '제보 ${report.statusLabel}, 제보 번호 ${report.displayReceiptCode}',
      kind: '제보',
      report: report,
    );
  }

  final IconData icon;
  final String title;
  final String subtitle;
  final String semanticLabel;
  final String kind;
  final FacilityReportResult? report;
  final FacilityStatusSeverity severity;
  final String actionLabel;
}

class _NotificationInboxChips extends StatelessWidget {
  const _NotificationInboxChips({required this.items});

  final List<_NotificationInboxItem> items;

  @override
  Widget build(BuildContext context) {
    final facilityCount = items.where((item) => item.kind == '시설').length;
    final reportCount = items.length - facilityCount;
    final parts = <String>[
      '전체 ${items.length}',
      if (facilityCount > 0) '시설 $facilityCount',
      if (reportCount > 0) '제보 $reportCount',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 4),
      child: Text(
        parts.join('  ·  '),
        style: const TextStyle(
          color: EasySubwayAccessibleColors.mutedText,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _NotificationInboxRow extends StatelessWidget {
  const _NotificationInboxRow({required this.item});

  final _NotificationInboxItem item;

  @override
  Widget build(BuildContext context) {
    void open() {
      final report = item.report;
      if (report == null) {
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MyFacilityReportDetailScreen(report: report),
        ),
      );
    }

    final accent = _facilitySeverityAccent(item.severity);
    final row = Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: accent.backgroundColor,
        border: Border(
          bottom: BorderSide(color: accent.borderColor),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(item.icon, color: accent.iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: const TextStyle(
                          color: EasySubwayAccessibleColors.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item.kind,
                      style: const TextStyle(
                        color: EasySubwayAccessibleColors.mutedText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  item.subtitle,
                  style: TextStyle(
                    color: accent.iconColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
                if (item.actionLabel.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    item.actionLabel,
                    style: const TextStyle(
                      color: EasySubwayAccessibleColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    if (item.report == null) {
      return Semantics(
        label: item.semanticLabel,
        child: ExcludeSemantics(child: row),
      );
    }
    return Semantics(
      button: true,
      label: item.semanticLabel,
      onTap: open,
      child: ExcludeSemantics(
        child: InkWell(onTap: open, child: row),
      ),
    );
  }
}

class _FacilitySeverityAccent {
  const _FacilitySeverityAccent({
    required this.backgroundColor,
    required this.borderColor,
    required this.iconColor,
  });

  final Color backgroundColor;
  final Color borderColor;
  final Color iconColor;
}

_FacilitySeverityAccent _facilitySeverityAccent(
  FacilityStatusSeverity severity,
) {
  return switch (severity) {
    FacilityStatusSeverity.blocked => const _FacilitySeverityAccent(
      backgroundColor: EasySubwayAccessibleColors.redSoft,
      borderColor: EasySubwayAccessibleColors.red,
      iconColor: EasySubwayAccessibleColors.red,
    ),
    FacilityStatusSeverity.caution => const _FacilitySeverityAccent(
      backgroundColor: EasySubwayAccessibleColors.amberSoft,
      borderColor: EasySubwayAccessibleColors.amberBorder,
      iconColor: EasySubwayAccessibleColors.amber,
    ),
    FacilityStatusSeverity.needsInfo => const _FacilitySeverityAccent(
      backgroundColor: EasySubwayAccessibleColors.statusInfoSurface,
      borderColor: EasySubwayAccessibleColors.statusInfoContent,
      iconColor: EasySubwayAccessibleColors.statusInfoContent,
    ),
    FacilityStatusSeverity.normal => const _FacilitySeverityAccent(
      backgroundColor: EasySubwayAccessibleColors.surfaceDefault,
      borderColor: EasySubwayAccessibleColors.line,
      iconColor: EasySubwayAccessibleColors.mintDark,
    ),
  };
}

IconData _facilityIcon(String type) {
  return switch (type) {
    'ELEVATOR' => Icons.elevator_outlined,
    'ESCALATOR' => Icons.escalator_warning_outlined,
    'WHEELCHAIR_LIFT' => Icons.accessible_forward,
    'RAMP' => Icons.accessible,
    'ACCESSIBLE_TOILET' || 'TOILET' => Icons.wc_outlined,
    _ => Icons.warning_amber_outlined,
  };
}
