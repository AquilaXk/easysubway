import 'dart:math' as math;

import 'package:flutter/widgets.dart';

@immutable
class MapCameraState {
  const MapCameraState({
    required this.sourceBounds,
    required this.viewportSize,
    required this.center,
    required this.scale,
    required this.minScale,
    required this.maxScale,
    required this.revision,
  }) : assert(scale > 0),
       assert(minScale > 0),
       assert(maxScale >= minScale),
       assert(revision >= 0);

  final Rect sourceBounds;
  final Size viewportSize;
  final Offset center;
  final double scale;
  final double minScale;
  final double maxScale;
  final int revision;

  Rect get visibleSourceRect {
    final sourceWidth = viewportSize.width / scale;
    final sourceHeight = viewportSize.height / scale;
    return Rect.fromCenter(
      center: center,
      width: sourceWidth,
      height: sourceHeight,
    );
  }

  Matrix4 get sourceToViewport {
    final viewportCenter = viewportSize.center(Offset.zero);
    return Matrix4.identity()
      ..translateByDouble(viewportCenter.dx, viewportCenter.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);
  }

  Matrix4 get viewportToSource => Matrix4.inverted(sourceToViewport);

  Offset sourceToViewportPoint(Offset sourcePoint) {
    final viewportCenter = viewportSize.center(Offset.zero);
    return viewportCenter + (sourcePoint - center) * scale;
  }

  Offset viewportToSourcePoint(Offset viewportPoint) {
    final viewportCenter = viewportSize.center(Offset.zero);
    return center + (viewportPoint - viewportCenter) / scale;
  }

  MapCameraState zoomBy(double factor, {required Offset focalPoint}) {
    final sourceBefore = viewportToSourcePoint(focalPoint);
    final newScale = (scale * factor).clamp(minScale, maxScale).toDouble();
    final viewportCenter = viewportSize.center(Offset.zero);
    final newCenter = sourceBefore - (focalPoint - viewportCenter) / newScale;
    return copyWith(
      center: newCenter,
      scale: newScale,
      revision: revision + 1,
    ).clamped();
  }

  MapCameraState clamped({double viewportMargin = 0}) {
    final visibleWidth = viewportSize.width / scale;
    final visibleHeight = viewportSize.height / scale;
    final sourceMargin = viewportMargin / scale;
    final minCenterX = sourceBounds.left + visibleWidth / 2 - sourceMargin;
    final maxCenterX = sourceBounds.right - visibleWidth / 2 + sourceMargin;
    final minCenterY = sourceBounds.top + visibleHeight / 2 - sourceMargin;
    final maxCenterY = sourceBounds.bottom - visibleHeight / 2 + sourceMargin;

    final clampedCenter = Offset(
      _clampAxis(center.dx, minCenterX, maxCenterX, sourceBounds.center.dx),
      _clampAxis(center.dy, minCenterY, maxCenterY, sourceBounds.center.dy),
    );
    return center == clampedCenter ? this : copyWith(center: clampedCenter);
  }

  MapCameraState copyWith({
    Rect? sourceBounds,
    Size? viewportSize,
    Offset? center,
    double? scale,
    double? minScale,
    double? maxScale,
    int? revision,
  }) {
    return MapCameraState(
      sourceBounds: sourceBounds ?? this.sourceBounds,
      viewportSize: viewportSize ?? this.viewportSize,
      center: center ?? this.center,
      scale: scale ?? this.scale,
      minScale: minScale ?? this.minScale,
      maxScale: maxScale ?? this.maxScale,
      revision: revision ?? this.revision,
    );
  }
}

double _clampAxis(
  double value,
  double minValue,
  double maxValue,
  double fallback,
) {
  if (minValue > maxValue) {
    return fallback;
  }
  return math.min(math.max(value, minValue), maxValue);
}
