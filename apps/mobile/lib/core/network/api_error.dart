class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.path});

  final String message;
  final int? statusCode;
  final String? path;

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
