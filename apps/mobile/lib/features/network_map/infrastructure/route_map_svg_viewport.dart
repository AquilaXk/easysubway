import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../domain/map_camera.dart';

const _viewType = 'com.easysubway.easysubway_mobile/route_map_viewport_webview';
const _channelPrefix =
    'com.easysubway.easysubway_mobile/route_map_viewport_webview/';

const Map<String, String> kRouteMapSvgRegionToId = {
  '수도권': 'seoul',
  '부산': 'busan',
  '광주': 'gwangju',
  '대구': 'daegu',
  '대전': 'daejeon',
};

String? routeMapSvgAssetForRegion(String region) {
  final id = kRouteMapSvgRegionToId[region];
  return id == null ? null : 'assets/datapacks/metro_map_pack/basemap/$id.svg';
}

Map<String, Object> routeMapSvgViewportCameraPayload({
  required MapCameraState camera,
  required Offset sourceOrigin,
}) {
  final rect = camera.visibleSourceRect.shift(sourceOrigin);
  return <String, Object>{
    'viewBox': <double>[rect.left, rect.top, rect.width, rect.height],
    'revision': camera.revision,
  };
}

bool _hasValidViewBox(MapCameraState camera, Offset sourceOrigin) {
  final rect = camera.visibleSourceRect.shift(sourceOrigin);
  return rect.left.isFinite &&
      rect.top.isFinite &&
      rect.width.isFinite &&
      rect.height.isFinite &&
      rect.width > 0 &&
      rect.height > 0;
}

class RouteMapSvgViewportController {
  RouteMapSvgViewportController({
    required this.onUnavailable,
    this.onFramePresented,
  });

  final VoidCallback onUnavailable;
  final ValueChanged<int>? onFramePresented;
  MethodChannel? _channel;
  Map<String, Object>? _pendingCameraPayload;
  bool _unavailable = false;

  Future<void> attach({required int viewId}) async {
    _channel = MethodChannel('$_channelPrefix$viewId')
      ..setMethodCallHandler(_handleMethodCall);
    final pending = _pendingCameraPayload;
    _pendingCameraPayload = null;
    if (pending != null && !_unavailable) {
      await _invokeSetCamera(pending);
    }
  }

  Future<void> update(
    MapCameraState camera, {
    required Offset sourceOrigin,
  }) async {
    if (!_hasValidViewBox(camera, sourceOrigin)) {
      _fail();
      return;
    }
    final payload = routeMapSvgViewportCameraPayload(
      camera: camera,
      sourceOrigin: sourceOrigin,
    );
    final channel = _channel;
    if (channel == null) {
      _pendingCameraPayload = payload;
      return;
    }
    if (_unavailable) return;
    await _invokeSetCamera(payload);
  }

  Future<void> _invokeSetCamera(Map<String, Object> payload) async {
    final channel = _channel;
    if (channel == null || _unavailable) return;
    try {
      await channel.invokeMethod<void>('setCamera', payload);
    } on PlatformException {
      _fail();
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'framePresented':
        final revision = (call.arguments as Map?)?['revision'];
        if (revision is int) onFramePresented?.call(revision);
        return;
      case 'assetLoadFailed':
      case 'cameraApplyFailed':
      case 'processGone':
        _fail();
    }
  }

  void _fail() {
    if (_unavailable) return;
    _unavailable = true;
    onUnavailable();
  }

  void dispose() {
    final channel = _channel;
    _channel = null;
    if (channel == null) return;
    channel.setMethodCallHandler(null);
    unawaited(channel.invokeMethod<void>('dispose').catchError((_) {}));
  }
}

class RouteMapSvgViewport extends StatefulWidget {
  const RouteMapSvgViewport({
    required this.region,
    required this.camera,
    required this.sourceOrigin,
    required this.onUnavailable,
    super.key,
  });

  final String region;
  final MapCameraState camera;
  final Offset sourceOrigin;
  final VoidCallback onUnavailable;

  @override
  State<RouteMapSvgViewport> createState() => _RouteMapSvgViewportState();
}

class _RouteMapSvgViewportState extends State<RouteMapSvgViewport> {
  late final RouteMapSvgViewportController _controller;
  bool _framePresented = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = RouteMapSvgViewportController(
      onUnavailable: _fail,
      onFramePresented: (revision) {
        if (mounted && revision == widget.camera.revision) {
          setState(() => _framePresented = true);
        }
      },
    );
    if (!_isSupported ||
        routeMapSvgAssetForRegion(widget.region) == null ||
        !_hasValidViewBox(widget.camera, widget.sourceOrigin)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fail());
    }
  }

  bool get _isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void didUpdateWidget(RouteMapSvgViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.camera != widget.camera ||
        oldWidget.sourceOrigin != widget.sourceOrigin) {
      unawaited(
        _controller.update(widget.camera, sourceOrigin: widget.sourceOrigin),
      );
    }
  }

  void _fail() {
    if (!mounted || _failed) return;
    setState(() => _failed = true);
    widget.onUnavailable();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asset = routeMapSvgAssetForRegion(widget.region);
    if (_failed ||
        !_isSupported ||
        asset == null ||
        !_hasValidViewBox(widget.camera, widget.sourceOrigin)) {
      return const SizedBox.expand();
    }
    final cameraPayload = routeMapSvgViewportCameraPayload(
      camera: widget.camera,
      sourceOrigin: widget.sourceOrigin,
    );
    final params = <String, Object>{
      'assetPath': asset,
      'mimeType': 'image/svg+xml',
      'sourceWidth': widget.camera.sourceBounds.width,
      'sourceHeight': widget.camera.sourceBounds.height,
      ...cameraPayload,
    };
    final Widget platformView = switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidView(
        viewType: _viewType,
        layoutDirection: TextDirection.ltr,
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (id) =>
            unawaited(_controller.attach(viewId: id)),
      ),
      TargetPlatform.iOS => UiKitView(
        viewType: _viewType,
        layoutDirection: TextDirection.ltr,
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (id) =>
            unawaited(_controller.attach(viewId: id)),
      ),
      _ => const SizedBox.expand(),
    };
    return Visibility(
      visible: _framePresented,
      maintainState: true,
      maintainAnimation: true,
      maintainSize: true,
      child: ExcludeSemantics(child: IgnorePointer(child: platformView)),
    );
  }
}
