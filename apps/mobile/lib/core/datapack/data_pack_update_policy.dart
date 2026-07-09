class DataPackUpdatePolicyDefaults {
  const DataPackUpdatePolicyDefaults._();

  static const int manifestCheckOnResumeMinIntervalSeconds = 21600;
  static const List<int> retryBackoffSeconds = [60, 480, 3600];
  static const int retryMaxAttemptsPerSession = 3;
  static const int expiryUrgentWindowDays = 7;

  static const DataPackUpdatePolicy policy = DataPackUpdatePolicy(
    manifestCheckOnResumeMinInterval: Duration(
      seconds: manifestCheckOnResumeMinIntervalSeconds,
    ),
    retryBackoffSeconds: retryBackoffSeconds,
    retryMaxAttemptsPerSession: retryMaxAttemptsPerSession,
    expiryUrgentWindow: Duration(days: expiryUrgentWindowDays),
    expiryUrgentIgnoresMinInterval: true,
  );
}

class DataPackUpdatePolicy {
  const DataPackUpdatePolicy({
    required this.manifestCheckOnResumeMinInterval,
    required this.retryBackoffSeconds,
    required this.retryMaxAttemptsPerSession,
    required this.expiryUrgentWindow,
    required this.expiryUrgentIgnoresMinInterval,
  });

  final Duration manifestCheckOnResumeMinInterval;
  final List<int> retryBackoffSeconds;
  final int retryMaxAttemptsPerSession;
  final Duration expiryUrgentWindow;
  final bool expiryUrgentIgnoresMinInterval;

  Duration backoffForAttempt(int attempt) {
    final index = attempt.clamp(1, retryBackoffSeconds.length) - 1;
    return Duration(seconds: retryBackoffSeconds[index]);
  }
}
