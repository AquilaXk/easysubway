import 'package:connectivity_plus/connectivity_plus.dart';

enum NetworkCondition { unmetered, metered, offline }

abstract class NetworkConditionSource {
  const NetworkConditionSource();

  Future<NetworkCondition> current();
}

class FixedNetworkConditionSource extends NetworkConditionSource {
  const FixedNetworkConditionSource(this.condition);

  final NetworkCondition condition;

  @override
  Future<NetworkCondition> current() async => condition;
}

class ConnectivityNetworkConditionSource extends NetworkConditionSource {
  ConnectivityNetworkConditionSource({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<NetworkCondition> current() async {
    final results = await _connectivity.checkConnectivity();
    if (results.contains(ConnectivityResult.none)) {
      return NetworkCondition.offline;
    }
    if (results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet)) {
      return NetworkCondition.unmetered;
    }
    return NetworkCondition.metered;
  }
}
