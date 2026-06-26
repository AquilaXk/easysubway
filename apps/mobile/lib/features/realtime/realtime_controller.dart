import 'package:flutter/foundation.dart';

import 'realtime_repository.dart';

class RealtimeStationController extends ChangeNotifier {
  RealtimeStationController({required this.repository});

  final RealtimeRepository repository;

  RealtimeSnapshot _state = const RealtimeSnapshot.loading();
  bool _isDisposed = false;

  RealtimeSnapshot get state => _state;

  Future<void> load(RealtimeStationQuery query) async {
    _emit(const RealtimeSnapshot.loading());
    try {
      _emit(await repository.arrivals(query));
    } on RealtimeException {
      _emit(const RealtimeSnapshot.unavailable());
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'easysubway realtime',
          context: ErrorDescription('실시간 열차 조회 중 예외가 발생했습니다.'),
        ),
      );
      _emit(const RealtimeSnapshot.unavailable());
    }
  }

  void _emit(RealtimeSnapshot nextState) {
    if (_isDisposed) {
      return;
    }
    _state = nextState;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
