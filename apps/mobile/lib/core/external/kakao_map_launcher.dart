import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class KakaoMapPoint {
  const KakaoMapPoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

class KakaoMapTarget extends KakaoMapPoint {
  const KakaoMapTarget({
    required this.label,
    required super.latitude,
    required super.longitude,
  });

  final String label;
}

class KakaoWalkingRouteTarget {
  const KakaoWalkingRouteTarget({required this.start, required this.end});

  final KakaoMapPoint start;
  final KakaoMapTarget end;
}

enum KakaoMapLaunchResult { app, web, copied, failed }

abstract interface class KakaoMapLauncher {
  Future<KakaoMapLaunchResult> openLook(KakaoMapTarget target);

  Future<KakaoMapLaunchResult> openWalkingRoute(KakaoWalkingRouteTarget target);
}

typedef ExternalUriOpener = Future<bool> Function(Uri uri);
typedef TextCopier = Future<void> Function(String text);

class UrlLauncherKakaoMapLauncher implements KakaoMapLauncher {
  const UrlLauncherKakaoMapLauncher({
    this.openExternal = _launchExternalApplication,
    this.copyText = _copyTextToClipboard,
  });

  final ExternalUriOpener openExternal;
  final TextCopier copyText;

  @override
  Future<KakaoMapLaunchResult> openLook(KakaoMapTarget target) async {
    return _openWithFallback(
      appUri: kakaoMapLookAppUri(target),
      webUri: kakaoMapLookWebUri(target),
      copyFallbackText: _copyTextFor(target),
    );
  }

  @override
  Future<KakaoMapLaunchResult> openWalkingRoute(
    KakaoWalkingRouteTarget target,
  ) async {
    return _openWithFallback(
      appUri: kakaoMapWalkingRouteAppUri(target),
      webUri: kakaoMapWalkingRouteWebUri(target),
      copyFallbackText: _copyTextFor(target.end),
    );
  }

  Future<KakaoMapLaunchResult> _openWithFallback({
    required Uri appUri,
    required Uri webUri,
    required String copyFallbackText,
  }) async {
    if (await _tryOpenExternal(appUri)) {
      return KakaoMapLaunchResult.app;
    }
    if (await _tryOpenExternal(webUri)) {
      return KakaoMapLaunchResult.web;
    }
    try {
      await copyText(copyFallbackText);
      return KakaoMapLaunchResult.copied;
    } on Object {
      return KakaoMapLaunchResult.failed;
    }
  }

  Future<bool> _tryOpenExternal(Uri uri) async {
    try {
      return await openExternal(uri);
    } on Object {
      return false;
    }
  }
}

Uri kakaoMapLookAppUri(KakaoMapTarget target) {
  return Uri.parse(
    'kakaomap://look?p=${_coordinate(target.latitude)},${_coordinate(target.longitude)}',
  );
}

Uri kakaoMapLookWebUri(KakaoMapTarget target) {
  return Uri.parse(
    'https://map.kakao.com/link/map/${Uri.encodeComponent(target.label)},'
    '${_coordinate(target.latitude)},${_coordinate(target.longitude)}',
  );
}

Uri kakaoMapWalkingRouteAppUri(KakaoWalkingRouteTarget target) {
  return Uri.parse(
    'kakaomap://route?sp=${_coordinate(target.start.latitude)},'
    '${_coordinate(target.start.longitude)}&ep=${_coordinate(target.end.latitude)},'
    '${_coordinate(target.end.longitude)}&by=foot',
  );
}

Uri kakaoMapWalkingRouteWebUri(KakaoWalkingRouteTarget target) {
  return Uri.parse(
    'https://map.kakao.com/link/to/${Uri.encodeComponent(target.end.label)},'
    '${_coordinate(target.end.latitude)},${_coordinate(target.end.longitude)}',
  );
}

String _copyTextFor(KakaoMapTarget target) {
  return '${target.label} ${_coordinate(target.latitude)}, ${_coordinate(target.longitude)}';
}

String _coordinate(double value) {
  return value.toStringAsFixed(6).replaceFirst(RegExp(r'\.?0+$'), '');
}

Future<bool> _launchExternalApplication(Uri uri) {
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> _copyTextToClipboard(String text) {
  return Clipboard.setData(ClipboardData(text: text));
}
