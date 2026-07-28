import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../domain/map_camera.dart';

const _viewType = 'com.easysubway.easysubway_mobile/route_map_viewport_webview';
const _channelPrefix =
    'com.easysubway.easysubway_mobile/route_map_viewport_webview/';

@visibleForTesting
bool debugRouteMapSvgViewportPresentImmediately = false;

typedef RouteMapSvgFramePresentedCallback =
    void Function(int revision, int frameToken);

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
  int frameToken = 0,
}) {
  final rect = camera.visibleSourceRect.shift(sourceOrigin);
  return <String, Object>{
    'viewBox': <double>[rect.left, rect.top, rect.width, rect.height],
    'revision': camera.revision,
    'frameToken': frameToken,
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
  final RouteMapSvgFramePresentedCallback? onFramePresented;
  MethodChannel? _channel;
  Map<String, Object>? _pendingCameraPayload;
  bool _unavailable = false;

  Future<void> attach({required int viewId}) async {
    final channel = MethodChannel('$_channelPrefix$viewId')
      ..setMethodCallHandler(_handleMethodCall);
    _channel = channel;
    final pending = _pendingCameraPayload;
    _pendingCameraPayload = null;
    if (pending != null && !_unavailable) {
      await _invokeSetCamera(pending);
    }
    if (_channel != channel || _unavailable) return;
    try {
      await channel.invokeMethod<void>('start');
    } on PlatformException {
      _fail();
    } on MissingPluginException {
      _fail();
    }
  }

  Future<void> update(
    MapCameraState camera, {
    required Offset sourceOrigin,
    int frameToken = 0,
  }) async {
    if (!_hasValidViewBox(camera, sourceOrigin)) {
      _fail();
      return;
    }
    final payload = routeMapSvgViewportCameraPayload(
      camera: camera,
      sourceOrigin: sourceOrigin,
      frameToken: frameToken,
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
    } on MissingPluginException {
      _fail();
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'framePresented':
        final arguments = call.arguments as Map?;
        final revision = arguments?['revision'];
        final frameToken = arguments?['frameToken'];
        if (revision is int && frameToken is int) {
          onFramePresented?.call(revision, frameToken);
        }
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
    this.onFramePresented,
    this.overlay,
    super.key,
  });

  final String region;
  final MapCameraState camera;
  final Offset sourceOrigin;
  final VoidCallback onUnavailable;
  final ValueChanged<int>? onFramePresented;
  final Widget? overlay;

  @override
  State<RouteMapSvgViewport> createState() => _RouteMapSvgViewportState();
}

class _RouteMapSvgViewportState extends State<RouteMapSvgViewport> {
  late final RouteMapSvgViewportController _controller;
  bool _framePresented = false;
  bool _hasPresentedFrame = false;
  bool _failed = false;
  int _frameToken = 0;
  Widget? _presentedOverlay;
  int? _debugPresentedRevision;
  ({
    int revision,
    int token,
    double left,
    double top,
    double width,
    double height,
  })?
  _presentedFrame;

  ({
    int revision,
    int token,
    double left,
    double top,
    double width,
    double height,
  })
  get _frame {
    final rect = widget.camera.visibleSourceRect.shift(widget.sourceOrigin);
    return (
      revision: widget.camera.revision,
      token: _frameToken,
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
    );
  }

  @override
  void initState() {
    super.initState();
    _controller = RouteMapSvgViewportController(
      onUnavailable: _fail,
      onFramePresented: (revision, frameToken) {
        if (mounted &&
            revision == widget.camera.revision &&
            frameToken == _frameToken) {
          setState(() {
            _framePresented = true;
            _hasPresentedFrame = true;
            _presentedFrame = _frame;
            _presentedOverlay = widget.overlay;
          });
          widget.onFramePresented?.call(revision);
        }
      },
    );
    if (!debugRouteMapSvgViewportPresentImmediately &&
        (!_isSupported ||
            routeMapSvgAssetForRegion(widget.region) == null ||
            !_hasValidViewBox(widget.camera, widget.sourceOrigin))) {
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
      _frameToken += 1;
      _framePresented = false;
      unawaited(
        _controller.update(
          widget.camera,
          sourceOrigin: widget.sourceOrigin,
          frameToken: _frameToken,
        ),
      );
    } else if (_framePresented && _presentedFrame == _frame) {
      _presentedOverlay = widget.overlay;
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
    if (debugRouteMapSvgViewportPresentImmediately) {
      final revision = widget.camera.revision;
      if (_debugPresentedRevision != revision) {
        _debugPresentedRevision = revision;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              debugRouteMapSvgViewportPresentImmediately &&
              widget.camera.revision == revision) {
            widget.onFramePresented?.call(revision);
          }
        });
      }
      return widget.overlay ?? const SizedBox.expand();
    }
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
      frameToken: _frameToken,
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
    final nativeView = ExcludeSemantics(
      child: IgnorePointer(child: platformView),
    );
    final overlay = _framePresented ? _presentedOverlay : null;
    return Visibility(
      visible: _hasPresentedFrame,
      maintainState: true,
      maintainAnimation: true,
      maintainSize: true,
      child: overlay == null
          ? nativeView
          : Stack(fit: StackFit.expand, children: [nativeView, overlay]),
    );
  }
}
