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

  void clear() {
    if (_draft.isEmpty) {
      return;
    }
    _draft = const RouteDraft.empty();
    notifyListeners();
  }
}
