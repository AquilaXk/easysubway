import 'package:flutter/foundation.dart';

import '../domain/route_draft.dart';

class RouteDraftController extends ChangeNotifier {
  RouteDraft _draft = const RouteDraft.empty();

  RouteDraft get draft => _draft;

  void setOrigin(RouteDraftStation station) {
    _draft = RouteDraft(
      origin: station,
      destination: _draft.destination,
      lastModifiedAt: DateTime.now(),
    );
    notifyListeners();
  }

  void setDestination(RouteDraftStation station) {
    _draft = RouteDraft(
      origin: _draft.origin,
      destination: station,
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
      lastModifiedAt: DateTime.now(),
    );
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
      lastModifiedAt: DateTime.now(),
    );
    notifyListeners();
  }

  void clear() {
    if (_draft.isEmpty) {
      return;
    }
    _draft = const RouteDraft.empty();
    notifyListeners();
  }
}
