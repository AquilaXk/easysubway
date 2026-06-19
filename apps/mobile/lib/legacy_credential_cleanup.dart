import 'secure_key_value_storage.dart';

abstract interface class LegacyCredentialCleaner {
  Future<void> clear();
}

class NoLegacyCredentialCleaner implements LegacyCredentialCleaner {
  const NoLegacyCredentialCleaner();

  @override
  Future<void> clear() async {}
}

class SecureLegacyCredentialCleaner implements LegacyCredentialCleaner {
  const SecureLegacyCredentialCleaner({
    this.storage = const FlutterSecureKeyValueStorage(),
  });

  static const legacyAuthCredentialsKey =
      'easysubway.anonymousAuth.credentials';

  final SecureKeyValueStorage storage;

  @override
  Future<void> clear() {
    return storage.delete(key: legacyAuthCredentialsKey);
  }
}
