class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.path,
    this.cause,
    this.causeStackTrace,
  });

  final String message;
  final int? statusCode;
  final String? path;
  final Object? cause;
  final StackTrace? causeStackTrace;

  @override
  String toString() {
    final parts = <String>[message];
    if (statusCode != null) {
      parts.add('status=$statusCode');
    }
    if (path != null && path!.isNotEmpty) {
      parts.add('path=$path');
    }
    return parts.join(' ');
  }
}
