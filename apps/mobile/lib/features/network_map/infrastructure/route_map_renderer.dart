import 'dart:async';

import '../domain/map_camera.dart';

const routeMapViewportLabelCollisionScript = r'''
window.easysubwayApplyRouteMapLabelPolicy = function () {
  const svg = document.querySelector('svg');
  if (!svg || !svg.viewBox || !svg.viewBox.baseVal) {
    return false;
  }
  const minIntervalMs = 120;
  const now = Date.now();
  const lastRun = Number(svg.dataset.easysubwayLabelPolicyAt || 0);
  const remainingMs = minIntervalMs - (now - lastRun);
  if (remainingMs > 0) {
    if (!svg.dataset.easysubwayLabelPolicyPending) {
      svg.dataset.easysubwayLabelPolicyPending = 'true';
      setTimeout(() => {
        delete svg.dataset.easysubwayLabelPolicyPending;
        window.easysubwayApplyRouteMapLabelPolicy();
      }, remainingMs);
    }
    return true;
  }
  svg.dataset.easysubwayLabelPolicyAt = String(now);
  const viewBox = svg.viewBox.baseVal;
  const viewport = {
    left: viewBox.x,
    top: viewBox.y,
    right: viewBox.x + viewBox.width,
    bottom: viewBox.y + viewBox.height
  };
  const readBounds = (label) => {
    try {
      return label.getBBox();
    } catch {
      return null;
    }
  };
  const invertMatrix = (matrix) => {
    try {
      return matrix.inverse();
    } catch {
      return null;
    }
  };
  const isFiniteBox = (box) =>
    box &&
    Number.isFinite(box.left) &&
    Number.isFinite(box.top) &&
    Number.isFinite(box.right) &&
    Number.isFinite(box.bottom);
  const accepted = [];
  // svg 좌표 변환은 한 패스 내내 불변이므로 루프 밖에서 한 번만 계산한다.
  const svgMatrix = svg.getScreenCTM();
  const toSvg = svgMatrix ? invertMatrix(svgMatrix) : null;
  const point = svg.createSVGPoint ? svg.createSVGPoint() : null;
  const labels = Array.from(svg.querySelectorAll('text'));
  for (const label of labels) {
    const hiddenByUs = label.hasAttribute('data-easysubway-hidden-label');
    if (!hiddenByUs && label.style.display === 'none') {
      // 원본 SVG가 숨긴 라벨: 그대로 숨겨 두고 라벨 공간도 차지하지 않게 한다.
      continue;
    }
    if (hiddenByUs) {
      label.style.display = '';
      label.removeAttribute('data-easysubway-hidden-label');
    }
    let box;
    if (
      label.dataset.easysubwayLabelLeft &&
      label.dataset.easysubwayLabelTop &&
      label.dataset.easysubwayLabelRight &&
      label.dataset.easysubwayLabelBottom
    ) {
      box = {
        left: Number(label.dataset.easysubwayLabelLeft),
        top: Number(label.dataset.easysubwayLabelTop),
        right: Number(label.dataset.easysubwayLabelRight),
        bottom: Number(label.dataset.easysubwayLabelBottom)
      };
    }
    if (!isFiniteBox(box)) {
      if (!toSvg || !point) {
        continue;
      }
      const bounds = readBounds(label);
      if (!bounds) {
        continue;
      }
      const labelMatrix = label.getScreenCTM();
      if (!labelMatrix) {
        continue;
      }
      const transformPoint = (x, y) => {
        point.x = x;
        point.y = y;
        return point.matrixTransform(labelMatrix).matrixTransform(toSvg);
      };
      const topLeft = transformPoint(bounds.x, bounds.y);
      const topRight = transformPoint(bounds.x + bounds.width, bounds.y);
      const bottomLeft = transformPoint(bounds.x, bounds.y + bounds.height);
      const bottomRight = transformPoint(
        bounds.x + bounds.width,
        bounds.y + bounds.height
      );
      box = {
        left: Math.min(topLeft.x, topRight.x, bottomLeft.x, bottomRight.x),
        top: Math.min(topLeft.y, topRight.y, bottomLeft.y, bottomRight.y),
        right: Math.max(topLeft.x, topRight.x, bottomLeft.x, bottomRight.x),
        bottom: Math.max(topLeft.y, topRight.y, bottomLeft.y, bottomRight.y)
      };
      if (!isFiniteBox(box)) {
        // 비정상 측정값(뷰가 아직 레이아웃되지 않은 상태): 잘못된 박스를 영구
        // 캐시하지 않도록 캐시를 건너뛰어 다음 실행에서 다시 측정하게 한다.
        continue;
      }
      label.dataset.easysubwayLabelLeft = String(box.left);
      label.dataset.easysubwayLabelTop = String(box.top);
      label.dataset.easysubwayLabelRight = String(box.right);
      label.dataset.easysubwayLabelBottom = String(box.bottom);
    }
    if (
      box.right < viewport.left ||
      box.left > viewport.right ||
      box.bottom < viewport.top ||
      box.top > viewport.bottom
    ) {
      label.style.display = 'none';
      label.setAttribute('data-easysubway-hidden-label', 'offscreen');
      continue;
    }
    const overlaps = accepted.some((other) =>
      box.left < other.right &&
      box.right > other.left &&
      box.top < other.bottom &&
      box.bottom > other.top
    );
    if (overlaps) {
      label.style.display = 'none';
      label.setAttribute('data-easysubway-hidden-label', 'collision');
    } else {
      accepted.push(box);
    }
  }
  return true;
};
''';

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
