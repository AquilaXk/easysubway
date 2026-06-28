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

final class RouteMapRendererCameraRequested extends RouteMapRendererEvent {
  const RouteMapRendererCameraRequested(this.revision);

  final int revision;
}

final class RouteMapRendererCameraLatency extends RouteMapRendererEvent {
  const RouteMapRendererCameraLatency({
    required this.revision,
    required this.elapsed,
  });

  final int revision;
  final Duration elapsed;
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

final class RouteMapRendererMemoryTrimmed extends RouteMapRendererEvent {
  const RouteMapRendererMemoryTrimmed();
}

final class RouteMapRendererDisposed extends RouteMapRendererEvent {
  const RouteMapRendererDisposed();
}

final class RouteMapRendererHealthMonitor {
  RouteMapRendererHealthMonitor(
    this._controller, {
    this.blankTimeout = const Duration(milliseconds: 1500),
    this.maxRecoveryAttempts = 2,
    this.onEvent,
    Timer Function(Duration duration, void Function() callback)? timerFactory,
  }) : assert(maxRecoveryAttempts > 0),
       _timerFactory = timerFactory ?? Timer.new;

  final RouteMapRendererController _controller;
  final Duration blankTimeout;
  final int maxRecoveryAttempts;
  final void Function(RouteMapRendererEvent event)? onEvent;
  final Timer Function(Duration duration, void Function() callback)
  _timerFactory;

  StreamSubscription<RouteMapRendererEvent>? _subscription;
  Timer? _blankTimer;
  int? _pendingRevision;
  int? _retryWatchRevision;
  int _recoveryAttempt = 0;
  bool _closed = false;

  void start() {
    if (_subscription != null) {
      return;
    }
    _closed = false;
    _subscription = _controller.events.listen(_handleEvent);
  }

  Future<void> trimMemory() {
    if (_closed) {
      return Future<void>.value();
    }
    return _controller.trimMemory();
  }

  Future<void> disposeRenderer() {
    if (_closed) {
      return Future<void>.value();
    }
    return _controller.dispose();
  }

  Future<void> close({bool disposeRenderer = false}) async {
    if (_closed) {
      return;
    }
    _closed = true;
    try {
      if (disposeRenderer) {
        await _controller.dispose();
      }
    } finally {
      await stop();
    }
  }

  Future<void> stop() async {
    _closed = true;
    _blankTimer?.cancel();
    _blankTimer = null;
    _retryWatchRevision = null;
    await _subscription?.cancel();
    _subscription = null;
  }

  void _handleEvent(RouteMapRendererEvent event) {
    onEvent?.call(event);
    switch (event) {
      case RouteMapRendererCameraRequested(:final revision):
        _watchRevision(revision);
      case RouteMapRendererFramePresented(:final revision):
        if (_pendingRevision != null && revision == _pendingRevision!) {
          _clearPendingFrame();
          _recoveryAttempt = 0;
        }
      case RouteMapRendererProcessGone():
        _recover();
      case RouteMapRendererDisposed():
        unawaited(stop());
      case RouteMapRendererAssetReady():
        final retryRevision = _retryWatchRevision;
        if (retryRevision != null) {
          _retryWatchRevision = null;
          _watchRevision(retryRevision);
        }
      case RouteMapRendererCreated() ||
          RouteMapRendererAssetLoading() ||
          RouteMapRendererCameraLatency() ||
          RouteMapRendererFrameTimeout() ||
          RouteMapRendererRecovering() ||
          RouteMapRendererFailed() ||
          RouteMapRendererMemoryTrimmed():
        break;
    }
  }

  void _watchRevision(int revision) {
    _retryWatchRevision = null;
    _pendingRevision = revision;
    _blankTimer?.cancel();
    _blankTimer = _timerFactory(blankTimeout, () {
      if (_closed) {
        return;
      }
      final revision = _pendingRevision;
      if (revision == null) {
        return;
      }
      onEvent?.call(RouteMapRendererFrameTimeout(revision));
      _recover(rewatchRevision: revision);
    });
  }

  void _clearPendingFrame() {
    _pendingRevision = null;
    _blankTimer?.cancel();
    _blankTimer = null;
  }

  void _recover({int? rewatchRevision}) {
    _clearPendingFrame();
    _retryWatchRevision = rewatchRevision;
    if (_recoveryAttempt >= maxRecoveryAttempts) {
      onEvent?.call(
        RouteMapRendererFailed(
          'renderer did not present a frame after $maxRecoveryAttempts recovery attempts',
        ),
      );
      return;
    }
    _recoveryAttempt += 1;
    onEvent?.call(RouteMapRendererRecovering(_recoveryAttempt));
    unawaited(
      _controller.retry().catchError((Object error) {
        if (!_closed) {
          onEvent?.call(RouteMapRendererFailed(error.toString()));
        }
      }),
    );
  }
}
