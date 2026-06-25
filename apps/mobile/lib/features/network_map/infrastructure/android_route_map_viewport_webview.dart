import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../domain/map_camera.dart';
import 'route_map_renderer.dart';

const androidRouteMapViewportWebViewType =
    'com.easysubway.easysubway_mobile/route_map_viewport_webview';

@visibleForTesting
Map<String, Object?> androidRouteMapViewportCreationParams({
  required String assetPath,
  required String mimeType,
  required MapCameraState camera,
}) {
  return <String, Object?>{
    'assetPath': assetPath,
    'mimeType': mimeType,
    'sourceWidth': camera.sourceBounds.width,
    'sourceHeight': camera.sourceBounds.height,
    'viewBox': _viewBoxFor(camera),
    'revision': camera.revision,
  };
}

class AndroidRouteMapViewportWebView extends StatefulWidget {
  const AndroidRouteMapViewportWebView({
    super.key,
    required this.assetPath,
    required this.mimeType,
    required this.camera,
    this.onControllerCreated,
  });

  final String assetPath;
  final String mimeType;
  final MapCameraState camera;
  final ValueChanged<AndroidRouteMapViewportController>? onControllerCreated;

  @override
  State<AndroidRouteMapViewportWebView> createState() =>
      _AndroidRouteMapViewportWebViewState();
}

class _AndroidRouteMapViewportWebViewState
    extends State<AndroidRouteMapViewportWebView> {
  AndroidRouteMapViewportController? _controller;

  @override
  void didUpdateWidget(AndroidRouteMapViewportWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (androidRouteMapViewportNeedsCameraUpdate(
      previous: oldWidget.camera,
      next: widget.camera,
    )) {
      _controller?.setCamera(widget.camera);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const ColoredBox(color: Color(0xffffffff));
    }
    return AndroidView(
      key: ValueKey<String>(
        'routeMapViewportWebView:${widget.assetPath}:${widget.mimeType}',
      ),
      viewType: androidRouteMapViewportWebViewType,
      creationParams: androidRouteMapViewportCreationParams(
        assetPath: widget.assetPath,
        mimeType: widget.mimeType,
        camera: widget.camera,
      ),
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: (viewId) {
        final controller = AndroidRouteMapViewportController(viewId);
        _controller = controller;
        widget.onControllerCreated?.call(controller);
      },
    );
  }
}

class AndroidRouteMapViewportController implements RouteMapRendererController {
  AndroidRouteMapViewportController(
    int viewId, {
    BinaryMessenger? binaryMessenger,
  }) : _channel = MethodChannel(
         'com.easysubway.easysubway_mobile/route_map_viewport_webview/$viewId',
         const StandardMethodCodec(),
         binaryMessenger,
       ) {
    _channel.setMethodCallHandler(_handleNativeCall);
    _events.add(const RouteMapRendererCreated());
  }

  final MethodChannel _channel;
  final _events = StreamController<RouteMapRendererEvent>.broadcast();

  @override
  Stream<RouteMapRendererEvent> get events => _events.stream;

  @override
  Future<void> setCamera(MapCameraState camera) {
    return _channel.invokeMethod<void>('setCamera', <String, Object?>{
      'viewBox': _viewBoxFor(camera),
      'revision': camera.revision,
    });
  }

  @override
  Future<void> retry() => _channel.invokeMethod<void>('reload');

  @override
  Future<void> trimMemory() => _channel.invokeMethod<void>('trimMemory');

  @override
  Future<void> dispose() async {
    await _channel.invokeMethod<void>('dispose');
    _channel.setMethodCallHandler(null);
    await _events.close();
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    final arguments = (call.arguments as Map?)?.cast<String, Object?>();
    switch (call.method) {
      case 'assetReady':
        _events.add(const RouteMapRendererAssetReady());
      case 'framePresented':
        _events.add(
          RouteMapRendererFramePresented((arguments?['revision'] as int?) ?? 0),
        );
      case 'processGone':
        _events.add(
          RouteMapRendererProcessGone(
            didCrash: (arguments?['didCrash'] as bool?) ?? false,
          ),
        );
    }
  }
}

List<double> _viewBoxFor(MapCameraState camera) {
  final rect = camera.visibleSourceRect;
  return <double>[rect.left, rect.top, rect.width, rect.height];
}

@visibleForTesting
bool androidRouteMapViewportNeedsCameraUpdate({
  required MapCameraState previous,
  required MapCameraState next,
}) {
  if (previous.revision != next.revision) {
    return true;
  }
  final previousViewBox = _viewBoxFor(previous);
  final nextViewBox = _viewBoxFor(next);
  for (var index = 0; index < previousViewBox.length; index += 1) {
    if (previousViewBox[index] != nextViewBox[index]) {
      return true;
    }
  }
  return false;
}
