import 'package:flutter/foundation.dart';

import '../domain/route_draft.dart';

class RouteDraftController extends ChangeNotifier {
  RouteDraft _draft = const RouteDraft.empty();

  /// 경유 칸이 비어 있어도 출발·도착 사이에 행을 보여줄지.
  /// [openWaypointSlot]으로 열고, 역을 채우거나 [clearWaypoint]로 닫는다.
  bool _waypointSlotOpen = false;

  RouteDraft get draft => _draft;

  /// 경유 행 표시 여부(빈 칸 포함).
  bool get isWaypointRowVisible => _waypointSlotOpen || _draft.waypoint != null;

  /// 출발·도착 사이에 빈 경유 칸을 연다. 이미 열려 있거나 경유가 있으면 no-op.
  void openWaypointSlot() {
    if (_waypointSlotOpen || _draft.waypoint != null) {
      return;
    }
    _waypointSlotOpen = true;
    notifyListeners();
  }

  void setOrigin(RouteDraftStation station) {
    // 같은 역이 다른 슬롯(도착·경유)에 이미 있으면 지정을 거부한다. 같은 슬롯
    // 재지정(덮어쓰기)은 허용한다.
    if (station.id == _draft.destination?.id ||
        station.id == _draft.waypoint?.id) {
      return;
    }
    _draft = RouteDraft(
      origin: station,
      destination: _draft.destination,
      waypoint: _draft.waypoint,
      lastModifiedAt: DateTime.now(),
    );
    notifyListeners();
  }

  void setDestination(RouteDraftStation station) {
    if (station.id == _draft.origin?.id || station.id == _draft.waypoint?.id) {
      return;
    }
    _draft = RouteDraft(
      origin: _draft.origin,
      destination: station,
      waypoint: _draft.waypoint,
      lastModifiedAt: DateTime.now(),
    );
    notifyListeners();
  }

  void setWaypoint(RouteDraftStation station) {
    if (station.id == _draft.origin?.id ||
        station.id == _draft.destination?.id) {
      return;
    }
    _waypointSlotOpen = true;
    _draft = RouteDraft(
      origin: _draft.origin,
      destination: _draft.destination,
      waypoint: station,
      lastModifiedAt: DateTime.now(),
    );
    notifyListeners();
  }

  void clearOrigin() {
    if (_draft.origin == null) {
      return;
    }
    _draft = RouteDraft(
      origin: null,
      destination: _draft.destination,
      waypoint: _draft.waypoint,
      lastModifiedAt: DateTime.now(),
    );
    notifyListeners();
  }

  void clearDestination() {
    if (_draft.destination == null) {
      return;
    }
    _draft = RouteDraft(
      origin: _draft.origin,
      destination: null,
      waypoint: _draft.waypoint,
      lastModifiedAt: DateTime.now(),
    );
    notifyListeners();
  }

  void clearWaypoint() {
    final hadStation = _draft.waypoint != null;
    final hadSlot = _waypointSlotOpen;
    if (!hadStation && !hadSlot) {
      return;
    }
    _waypointSlotOpen = false;
    if (hadStation) {
      _draft = RouteDraft(
        origin: _draft.origin,
        destination: _draft.destination,
        waypoint: null,
        lastModifiedAt: DateTime.now(),
      );
    }
    notifyListeners();
  }

  /// 출발/도착을 맞바꾼다. 둘 다 비어 있으면 아무 것도 하지 않는다.
  /// 지도 탭·검색 어느 경로로 채웠든 같은 draft 상태를 뒤집기만 한다.
  void swapOriginDestination() {
    if (_draft.origin == null && _draft.destination == null) {
      return;
    }
    _draft = RouteDraft(
      origin: _draft.destination,
      destination: _draft.origin,
      waypoint: _draft.waypoint,
      lastModifiedAt: DateTime.now(),
    );
    notifyListeners();
  }

  /// #1985: 두 슬롯 [a], [b]의 값을 맞바꾼다. a==b거나 두 슬롯 모두 비어 있으면
  /// 아무 것도 하지 않는다(notify 안 함). 나머지 슬롯 값은 보존한다.
  void swapSlots(RouteDraftSlot a, RouteDraftSlot b) {
    if (a == b) {
      return;
    }
    final aStation = _stationFor(a);
    final bStation = _stationFor(b);
    if (aStation == null && bStation == null) {
      return;
    }
    // a자리에 b값, b자리에 a값. 나머지 슬롯은 원래 값 유지.
    _draft = RouteDraft(
      origin: _slotValue(RouteDraftSlot.origin, a, b, aStation, bStation),
      destination: _slotValue(
        RouteDraftSlot.destination,
        a,
        b,
        aStation,
        bStation,
      ),
      waypoint: _slotValue(RouteDraftSlot.waypoint, a, b, aStation, bStation),
      lastModifiedAt: DateTime.now(),
    );
    notifyListeners();
  }

  /// #1985: [from] 슬롯 값을 [to] 슬롯으로 옮기고 from을 비운다. from이 비어
  /// 있으면 아무 것도 하지 않는다. to가 이미 채워져 있으면 값 소실을 막기 위해
  /// swap 시맨틱으로 폴백한다.
  void moveSlot(RouteDraftSlot from, RouteDraftSlot to) {
    if (from == to) {
      return;
    }
    final fromStation = _stationFor(from);
    if (fromStation == null) {
      return;
    }
    if (_stationFor(to) != null) {
      swapSlots(from, to);
      return;
    }
    // to가 비어 있으므로 from값을 to로 옮기고 from을 비운다.
    _draft = RouteDraft(
      origin: _movedValue(RouteDraftSlot.origin, from, to, fromStation),
      destination: _movedValue(
        RouteDraftSlot.destination,
        from,
        to,
        fromStation,
      ),
      waypoint: _movedValue(RouteDraftSlot.waypoint, from, to, fromStation),
      lastModifiedAt: DateTime.now(),
    );
    notifyListeners();
  }

  RouteDraftStation? _stationFor(RouteDraftSlot slot) {
    return switch (slot) {
      RouteDraftSlot.origin => _draft.origin,
      RouteDraftSlot.destination => _draft.destination,
      RouteDraftSlot.waypoint => _draft.waypoint,
    };
  }

  /// swapSlots용: [slot]의 최종값을 계산한다. slot이 a면 b값, b면 a값, 그 외는 원래값.
  RouteDraftStation? _slotValue(
    RouteDraftSlot slot,
    RouteDraftSlot a,
    RouteDraftSlot b,
    RouteDraftStation? aStation,
    RouteDraftStation? bStation,
  ) {
    if (slot == a) {
      return bStation;
    }
    if (slot == b) {
      return aStation;
    }
    return _stationFor(slot);
  }

  /// moveSlot용: [slot]의 최종값을 계산한다. slot이 to면 from값, from이면 null, 그 외는 원래값.
  RouteDraftStation? _movedValue(
    RouteDraftSlot slot,
    RouteDraftSlot from,
    RouteDraftSlot to,
    RouteDraftStation? fromStation,
  ) {
    if (slot == to) {
      return fromStation;
    }
    if (slot == from) {
      return null;
    }
    return _stationFor(slot);
  }

  void clear() {
    if (_draft.isEmpty && !_waypointSlotOpen) {
      return;
    }
    _waypointSlotOpen = false;
    _draft = const RouteDraft.empty();
    notifyListeners();
  }
}
