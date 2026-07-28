import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../core/external/kakao_map_launcher.dart';
import '../../../mobile_error_reporter.dart';
import '../domain/station_models.dart';
import '../domain/station_repositories.dart';
import 'station_detail_info_row.dart';
import 'station_exit_map_target.dart';

const _currentLocationDisabledMessage =
    '휴대전화의 위치 기능을 켜 주세요. 가까운 역을 찾는 데 필요합니다.';

class StationExitCard extends StatefulWidget {
  const StationExitCard({
    required this.station,
    required this.exit,
    required this.mapLauncher,
    required this.locationProvider,
    super.key,
  });

  final StationDetail station;
  final StationExitInfo exit;
  final KakaoMapLauncher mapLauncher;
  final CurrentLocationProvider? locationProvider;

  @override
  State<StationExitCard> createState() => _StationExitCardState();
}

class _StationExitCardState extends State<StationExitCard> {
  CurrentLocation? _walkingRouteStart;
  String _locationMessage = '';
  bool _isLoadingLocation = false;
  bool _isOpeningWalkingRoute = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final station = widget.station;
    final exit = widget.exit;
    final mapTarget = stationExitMapTarget(station: station, exit: exit);
    final walkingRouteStart = _walkingRouteStart;
    final distanceMeters = walkingRouteStart == null || mapTarget == null
        ? null
        : _coordinateDistanceMeters(
            fromLatitude: walkingRouteStart.latitude,
            fromLongitude: walkingRouteStart.longitude,
            toLatitude: mapTarget.target.latitude,
            toLongitude: mapTarget.target.longitude,
          );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                container: true,
                label: exit.semanticLabel,
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exit.name,
                        style: textTheme.titleMedium?.copyWith(
                          color: EasySubwayAccessibleColors.text,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _StationDetailStatusPill(
                        icon: Icons.elevator,
                        text: exit.elevatorConnectionLabel,
                        positive: exit.hasElevatorConnection,
                      ),
                      const SizedBox(height: 8),
                      _StationDetailStatusPill(
                        icon: Icons.stairs_outlined,
                        text: exit.stairPathLabel,
                        positive: !exit.hasStairOnlyPath,
                      ),
                      if (exit.lastVerifiedAt.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        StationDetailInfoRow(
                          icon: Icons.verified_outlined,
                          text:
                              '최근 확인 ${stationVerifiedRelativeLabel(exit.lastVerifiedAt)}',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (mapTarget?.usesStationFallback ?? false) ...[
                const SizedBox(height: 8),
                const StationDetailInfoRow(
                  icon: Icons.info_outline,
                  text: '출구 좌표가 없어 역 위치 기준으로 안내합니다.',
                ),
              ],
              if (distanceMeters != null) ...[
                const SizedBox(height: 8),
                StationDetailInfoRow(
                  icon: Icons.straighten,
                  text: _exitDistanceLabel(
                    distanceMeters,
                    usesStationFallback: mapTarget!.usesStationFallback,
                  ),
                ),
              ],
              if (_locationMessage.isNotEmpty) ...[
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: StationDetailInfoRow(
                    icon: Icons.info_outline,
                    text: _locationMessage,
                  ),
                ),
              ],
              if (mapTarget != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  container: true,
                  button: true,
                  label: mapTarget.usesStationFallback
                      ? '${exit.name} 카카오맵에서 보기, 출구 좌표가 없어 역 위치 기준으로 새 앱이 열립니다'
                      : '${exit.name} 카카오맵에서 보기, 새 앱이 열립니다',
                  onTap: () => _openExitMap(context),
                  child: SizedBox(
                    width: double.infinity,
                    child: ExcludeSemantics(
                      child: OutlinedButton.icon(
                        key: Key('stationExitMapButton-${exit.id}'),
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('카카오맵에서 보기'),
                        onPressed: () => _openExitMap(context),
                      ),
                    ),
                  ),
                ),
              ],
              if (mapTarget != null && widget.locationProvider != null) ...[
                const SizedBox(height: 8),
                Semantics(
                  container: true,
                  button: true,
                  enabled: !_isLoadingLocation,
                  label: mapTarget.usesStationFallback
                      ? '${exit.name} 역 위치 기준 직선거리 보기'
                      : '${exit.name}까지 직선거리 보기',
                  onTap: _isLoadingLocation
                      ? null
                      : _loadCurrentLocationForExit,
                  child: SizedBox(
                    width: double.infinity,
                    child: ExcludeSemantics(
                      child: OutlinedButton.icon(
                        key: Key('stationExitDistanceButton-${exit.id}'),
                        icon: _isLoadingLocation
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.near_me_outlined),
                        label: Text(
                          _isLoadingLocation
                              ? '현재 위치 확인 중'
                              : mapTarget.usesStationFallback
                              ? '역까지 거리 보기'
                              : '출구까지 거리 보기',
                        ),
                        onPressed: _isLoadingLocation
                            ? null
                            : _loadCurrentLocationForExit,
                      ),
                    ),
                  ),
                ),
              ],
              if (mapTarget != null && walkingRouteStart != null) ...[
                const SizedBox(height: 8),
                StationDetailInfoRow(
                  icon: Icons.privacy_tip_outlined,
                  text: mapTarget.usesStationFallback
                      ? '카카오맵 앱에서는 현재 위치와 역 좌표를, 웹에서는 역 좌표만 카카오에 전달합니다.'
                      : '카카오맵 앱에서는 현재 위치와 출구 좌표를, 웹에서는 출구 좌표만 카카오에 전달합니다.',
                ),
                const SizedBox(height: 8),
                Semantics(
                  container: true,
                  button: true,
                  enabled: !_isOpeningWalkingRoute,
                  label: mapTarget.usesStationFallback
                      ? '${exit.name} 역 위치 기준 카카오맵 도보 길안내'
                      : '${exit.name}까지 카카오맵 도보 길안내',
                  onTap: _isOpeningWalkingRoute
                      ? null
                      : () => _openWalkingRoute(context),
                  child: SizedBox(
                    width: double.infinity,
                    child: ExcludeSemantics(
                      child: FilledButton.icon(
                        key: Key('stationExitWalkingRouteButton-${exit.id}'),
                        icon: _isOpeningWalkingRoute
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: EasySubwayAccessibleColors
                                      .interactionOnPrimary,
                                ),
                              )
                            : const Icon(Icons.directions_walk),
                        label: Text(
                          _isOpeningWalkingRoute ? '길안내 여는 중' : '도보 길안내',
                        ),
                        onPressed: _isOpeningWalkingRoute
                            ? null
                            : () => _openWalkingRoute(context),
                      ),
                    ),
                  ),
                ),
              ],
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

  Future<void> _loadCurrentLocationForExit() async {
    if (_isLoadingLocation) {
      return;
    }
    final provider = widget.locationProvider;
    if (provider == null) {
      return;
    }
    setState(() {
      _isLoadingLocation = true;
      _locationMessage = '';
    });
    try {
      await _loadUsableCurrentLocationForExit();
    } finally {
      if (mounted) {
        setState(() => _isLoadingLocation = false);
      }
    }
  }

  Future<CurrentLocation?> _loadUsableCurrentLocationForExit() async {
    final provider = widget.locationProvider;
    if (provider == null) {
      return null;
    }
    try {
      final location = await provider.currentLocation();
      final blockedMessage = _exitWalkingLocationBlockedMessage(location);
      if (!mounted) {
        return null;
      }
      if (blockedMessage != null) {
        setState(() {
          _walkingRouteStart = null;
          _locationMessage = blockedMessage;
        });
        return null;
      }
      setState(() {
        _walkingRouteStart = location;
        _locationMessage = '';
      });
      return location;
    } on CurrentLocationException catch (error) {
      if (!mounted) {
        return null;
      }
      setState(() {
        _walkingRouteStart = null;
        _locationMessage = _exitWalkingLocationExceptionMessage(error);
      });
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '출구 도보 길안내 현재 위치 확인 중 예외가 발생했습니다.',
      );
      if (!mounted) {
        return null;
      }
      setState(() {
        _walkingRouteStart = null;
        _locationMessage = '현재 위치를 확인하지 못했어요.';
      });
    }
    return null;
  }

  Future<void> _openExitMap(BuildContext context) async {
    final mapTarget = stationExitMapTarget(
      station: widget.station,
      exit: widget.exit,
    );
    if (mapTarget == null) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final result = await widget.mapLauncher.openLook(mapTarget.target);
    if (!context.mounted) {
      return;
    }
    final message = switch (result) {
      KakaoMapLaunchResult.app || KakaoMapLaunchResult.web => '카카오맵을 열었습니다.',
      KakaoMapLaunchResult.copied => '좌표를 복사했습니다. 지도 앱에서 붙여넣어 주세요.',
      KakaoMapLaunchResult.failed => '지도 앱을 열지 못했어요. 잠시 후 다시 시도해 주세요.',
    };
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openWalkingRoute(BuildContext context) async {
    if (_isOpeningWalkingRoute || _isLoadingLocation) {
      return;
    }
    final mapTarget = stationExitMapTarget(
      station: widget.station,
      exit: widget.exit,
    );
    if (mapTarget == null) {
      return;
    }
    setState(() {
      _isOpeningWalkingRoute = true;
      _locationMessage = '';
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final start = await _loadUsableCurrentLocationForExit();
      if (!mounted || start == null) {
        return;
      }
      final result = await widget.mapLauncher.openWalkingRoute(
        KakaoWalkingRouteTarget(
          start: KakaoMapPoint(
            latitude: start.latitude,
            longitude: start.longitude,
          ),
          end: mapTarget.target,
        ),
      );
      if (!mounted) {
        return;
      }
      final message = switch (result) {
        KakaoMapLaunchResult.app ||
        KakaoMapLaunchResult.web => '카카오맵 도보 길안내를 열었습니다.',
        KakaoMapLaunchResult.copied =>
          mapTarget.usesStationFallback
              ? '역 좌표를 복사했습니다. 지도 앱에서 붙여넣어 주세요.'
              : '출구 좌표를 복사했습니다. 지도 앱에서 붙여넣어 주세요.',
        KakaoMapLaunchResult.failed => '도보 길안내를 열지 못했어요. 잠시 후 다시 시도해 주세요.',
      };
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _isOpeningWalkingRoute = false);
      }
    }
  }
}

String? _exitWalkingLocationBlockedMessage(CurrentLocation location) {
  return switch (location.qualityStatus()) {
    CurrentLocationQualityStatus.freshPrecise => null,
    CurrentLocationQualityStatus.unavailable =>
      '현재 위치 정확도 정보를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.',
    CurrentLocationQualityStatus.stale =>
      '현재 위치가 오래되어 출구까지 안내하기 어려워요. 다시 확인해 주세요.',
    CurrentLocationQualityStatus.coarse =>
      '현재 위치 정확도가 낮아 출구까지 안내하기 어려워요. 정확한 위치 권한을 허용해 주세요.',
    CurrentLocationQualityStatus.mocked => '모의 위치는 출구 도보 길안내에 사용할 수 없어요.',
  };
}

String _exitWalkingLocationExceptionMessage(CurrentLocationException error) {
  if (error.message == _currentLocationDisabledMessage) {
    return '휴대전화의 위치 기능을 켜 주세요. 출구까지 안내하는 데 필요합니다.';
  }
  return error.message;
}

String _exitDistanceLabel(
  int distanceMeters, {
  required bool usesStationFallback,
}) {
  final target = usesStationFallback ? '역까지 ' : '';
  if (distanceMeters < 1000) {
    return '현재 위치에서 $target직선 ${distanceMeters}m';
  }
  return '현재 위치에서 $target직선 ${(distanceMeters / 1000).toStringAsFixed(1)}km';
}

int _coordinateDistanceMeters({
  required double fromLatitude,
  required double fromLongitude,
  required double toLatitude,
  required double toLongitude,
}) {
  const earthRadiusMeters = 6371000.0;
  final fromLatRadians = _degreesToRadians(fromLatitude);
  final toLatRadians = _degreesToRadians(toLatitude);
  final deltaLat = _degreesToRadians(toLatitude - fromLatitude);
  final deltaLon = _degreesToRadians(toLongitude - fromLongitude);
  final haversine =
      math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
      math.cos(fromLatRadians) *
          math.cos(toLatRadians) *
          math.sin(deltaLon / 2) *
          math.sin(deltaLon / 2);
  return (earthRadiusMeters *
          2 *
          math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine)))
      .round();
}

double _degreesToRadians(double degrees) => degrees * math.pi / 180;

class _StationDetailStatusPill extends StatelessWidget {
  const _StationDetailStatusPill({
    required this.icon,
    required this.text,
    required this.positive,
  });

  final IconData icon;
  final String text;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final color = positive
        ? EasySubwayAccessibleColors.primary
        : EasySubwayAccessibleColors.amber;

    return Row(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: EasySubwayAccessibleColors.text,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}
