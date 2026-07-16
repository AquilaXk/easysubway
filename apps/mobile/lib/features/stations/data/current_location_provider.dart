import 'package:flutter/services.dart';

import '../../../mobile_error_reporter.dart';
import '../domain/station_models.dart';
import '../domain/station_repositories.dart';

const _currentLocationDisabledMessage =
    '휴대전화의 위치 기능을 켜 주세요. 가까운 역을 찾는 데 필요합니다.';
const _currentLocationPermissionMessage = '현재 위치를 사용할 수 없어요.';

class MethodChannelCurrentLocationProvider implements CurrentLocationProvider {
  MethodChannelCurrentLocationProvider({MethodChannel? channel})
    : _channel =
          channel ??
          const MethodChannel('com.easysubway.easysubway_mobile/location');

  final MethodChannel _channel;

  @override
  Future<bool> needsLocationPermissionRequest() async {
    try {
      return await _channel.invokeMethod<bool>(
            'needsLocationPermissionRequest',
          ) ??
          true;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '현재 위치 권한 상태 확인 중 예외가 발생했습니다.',
      );
      return true;
    }
  }

  @override
  Future<CurrentLocation> currentLocation() async {
    try {
      // 위치 권한과 센서 접근은 Android/iOS 네이티브 채널에 맡기고 화면은 같은 실패 문구를 사용한다.
      final response = await _channel.invokeMapMethod<String, Object?>(
        'currentLocation',
      );
      final latitude = _coordinateFrom(response, 'latitude');
      final longitude = _coordinateFrom(response, 'longitude');
      if (latitude == null || longitude == null) {
        throw const CurrentLocationException('현재 위치를 확인하지 못했어요.');
      }
      return CurrentLocation(
        latitude: latitude,
        longitude: longitude,
        accuracyMeters: _doubleFrom(response, 'accuracyMeters'),
        measuredAt: _dateTimeFromMillis(response, 'measuredAtMillis'),
        provider: _stringFrom(response, 'provider') ?? 'unknown',
        isMocked: _boolFrom(response, 'isMocked') ?? false,
        permissionPrecision: _permissionPrecisionFrom(
          _stringFrom(response, 'permissionPrecision'),
        ),
      );
    } on CurrentLocationException {
      rethrow;
    } on PlatformException catch (error) {
      throw CurrentLocationException(_locationErrorMessage(error.code));
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '현재 위치 조회 중 예외가 발생했습니다.');
      throw const CurrentLocationException('현재 위치를 확인하지 못했어요.');
    }
  }

  @override
  Future<bool> openLocationSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openLocationSettings') ?? false;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '위치 설정 화면 이동 중 예외가 발생했습니다.',
      );
      return false;
    }
  }

  double? _coordinateFrom(Map<String, Object?>? response, String key) {
    final value = response?[key];
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  double? _doubleFrom(Map<String, Object?>? response, String key) {
    final value = response?[key];
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  DateTime? _dateTimeFromMillis(Map<String, Object?>? response, String key) {
    final value = response?[key];
    final millis = switch (value) {
      int() => value,
      double() => value.round(),
      String() => int.tryParse(value),
      _ => null,
    };
    if (millis == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }

  String? _stringFrom(Map<String, Object?>? response, String key) {
    final value = response?[key];
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
    return null;
  }

  bool? _boolFrom(Map<String, Object?>? response, String key) {
    final value = response?[key];
    if (value is bool) {
      return value;
    }
    return null;
  }

  LocationPermissionPrecision _permissionPrecisionFrom(String? value) {
    return switch (value) {
      'precise' => LocationPermissionPrecision.precise,
      'approximate' => LocationPermissionPrecision.approximate,
      _ => LocationPermissionPrecision.unknown,
    };
  }

  String _locationErrorMessage(String code) {
    return switch (code) {
      'permissionDenied' => _currentLocationPermissionMessage,
      'locationDisabled' => _currentLocationDisabledMessage,
      'locationUnavailable' => '현재 위치를 확인하지 못했어요.',
      _ => '현재 위치를 확인하지 못했어요.',
    };
  }
}
