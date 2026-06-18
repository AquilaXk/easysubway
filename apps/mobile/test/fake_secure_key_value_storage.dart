import 'package:easysubway_mobile/secure_key_value_storage.dart';

class FakeSecureKeyValueStorage implements SecureKeyValueStorage {
  FakeSecureKeyValueStorage({this.readError, this.deleteError});

  final Object? readError;
  final Object? deleteError;
  final values = <String, String>{};
  final deletedKeys = <String>[];

  @override
  Future<String?> read({required String key}) async {
    final error = readError;
    if (error != null) {
      throw error;
    }
    return values[key];
  }

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    final error = deleteError;
    if (error != null) {
      throw error;
    }
    deletedKeys.add(key);
    values.remove(key);
  }
}
