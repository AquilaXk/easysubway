import 'dart:async';

import '../domain/map_camera.dart';

abstract interface class RouteMapRendererController {
  Stream<RouteMapRendererEvent> get events;

  Future<void> setCamera(MapCameraState camera);
  Future<void> retry();
  Future<void> trimMemory();
  Future<void> dispose();
}

sealed class RouteMapRendererEvent {
  const RouteMapRendererEvent();
}

final class RouteMapRendererCreated extends RouteMapRendererEvent {
  const RouteMapRendererCreated();
}

final class RouteMapRendererAssetLoading extends RouteMapRendererEvent {
  const RouteMapRendererAssetLoading();
}

final class RouteMapRendererAssetReady extends RouteMapRendererEvent {
  const RouteMapRendererAssetReady();
}

final class RouteMapRendererFramePresented extends RouteMapRendererEvent {
  const RouteMapRendererFramePresented(this.revision);

  final int revision;
}

final class RouteMapRendererProcessGone extends RouteMapRendererEvent {
  const RouteMapRendererProcessGone({required this.didCrash});

  final bool didCrash;
}

final class RouteMapRendererFrameTimeout extends RouteMapRendererEvent {
  const RouteMapRendererFrameTimeout(this.revision);

  final int revision;
}

final class RouteMapRendererRecovering extends RouteMapRendererEvent {
  const RouteMapRendererRecovering(this.attempt);

  final int attempt;
}

final class RouteMapRendererFailed extends RouteMapRendererEvent {
  const RouteMapRendererFailed(this.reason);

  final String reason;
}

final class RouteMapRendererDisposed extends RouteMapRendererEvent {
  const RouteMapRendererDisposed();
}
