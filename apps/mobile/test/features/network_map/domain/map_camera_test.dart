import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourceBounds = Rect.fromLTWH(100, 200, 1000, 500);
  const viewportSize = Size(400, 200);

  test('source와 viewport 좌표를 왕복 변환한다', () {
    const camera = MapCameraState(
      sourceBounds: sourceBounds,
      viewportSize: viewportSize,
      center: Offset(600, 450),
      scale: 0.4,
      minScale: 0.2,
      maxScale: 3,
      revision: 7,
    );

    const sourcePoint = Offset(700, 500);
    final viewportPoint = camera.sourceToViewportPoint(sourcePoint);

    expect(viewportPoint, const Offset(240, 120));
    expect(
      camera.viewportToSourcePoint(viewportPoint),
      closeToOffset(sourcePoint),
    );
    expect(camera.visibleSourceRect, sourceBounds);
  });

  test('focal point 아래 source 좌표를 유지하며 확대한다', () {
    const camera = MapCameraState(
      sourceBounds: sourceBounds,
      viewportSize: viewportSize,
      center: Offset(600, 450),
      scale: 0.4,
      minScale: 0.2,
      maxScale: 3,
      revision: 2,
    );
    const focalPoint = Offset(320, 140);
    final before = camera.viewportToSourcePoint(focalPoint);

    final zoomed = camera.zoomBy(2, focalPoint: focalPoint);

    expect(zoomed.scale, 0.8);
    expect(zoomed.revision, 3);
    expect(zoomed.viewportToSourcePoint(focalPoint), closeToOffset(before));
  });

  test('camera center를 source bounds 안으로 clamp한다', () {
    const camera = MapCameraState(
      sourceBounds: sourceBounds,
      viewportSize: viewportSize,
      center: Offset(600, 450),
      scale: 1,
      minScale: 0.2,
      maxScale: 3,
      revision: 1,
    );

    final panned = camera.copyWith(center: const Offset(0, 0)).clamped();

    expect(panned.visibleSourceRect.left, sourceBounds.left);
    expect(panned.visibleSourceRect.top, sourceBounds.top);
    expect(
      panned.visibleSourceRect.right,
      lessThanOrEqualTo(sourceBounds.right),
    );
    expect(
      panned.visibleSourceRect.bottom,
      lessThanOrEqualTo(sourceBounds.bottom),
    );
  });

  test('bounds가 viewport보다 작으면 해당 축 center를 source 중앙에 고정한다', () {
    const camera = MapCameraState(
      sourceBounds: Rect.fromLTWH(0, 0, 100, 80),
      viewportSize: Size(400, 200),
      center: Offset(-100, 500),
      scale: 1,
      minScale: 0.2,
      maxScale: 3,
      revision: 1,
    );

    final clamped = camera.clamped();

    expect(clamped.center, const Offset(50, 40));
  });
}

Matcher closeToOffset(Offset expected) {
  return isA<Offset>()
      .having((offset) => offset.dx, 'dx', closeTo(expected.dx, 0.0001))
      .having((offset) => offset.dy, 'dy', closeTo(expected.dy, 0.0001));
}
