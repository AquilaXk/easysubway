class DataPackIndex {
  const DataPackIndex({
    required this.schemaVersion,
    required this.builtAt,
    required this.qualityAsOf,
    required this.freshnessExpiresAt,
    required this.sourceSnapshotSetHash,
    required this.schemaIdentity,
    required this.packs,
  });

  factory DataPackIndex.fromJson(Map<String, Object?> json) {
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion is! int) {
      throw UnsupportedDatapackSchemaException(schemaVersion);
    }
    if (schemaVersion != 1) {
      throw UnsupportedDatapackSchemaException(schemaVersion);
    }
    final packs = json['packs'];
    if (packs is! List<Object?> || packs.isEmpty) {
      throw const FormatException('Invalid data pack index packs.');
    }
    final qualityAsOf = _requiredUtcDateTime(json, 'qualityAsOf');
    final freshnessExpiresAt = _requiredUtcDateTime(json, 'freshnessExpiresAt');
    if (!freshnessExpiresAt.isAfter(qualityAsOf)) {
      throw const FormatException(
        'Data pack index freshnessExpiresAt must be after qualityAsOf.',
      );
    }
    final schemaIdentity = _requiredString(json, 'schemaIdentity');
    if (schemaIdentity != 'catalog-schema-v1') {
      throw const FormatException('Unsupported data pack schema identity.');
    }
    return DataPackIndex(
      schemaVersion: schemaVersion,
      builtAt: _requiredUtcDateTime(json, 'builtAt'),
      qualityAsOf: qualityAsOf,
      freshnessExpiresAt: freshnessExpiresAt,
      sourceSnapshotSetHash: _requiredSha256(json, 'sourceSnapshotSetHash'),
      schemaIdentity: schemaIdentity,
      packs: packs
          .map((pack) {
            if (pack is! Map<String, Object?>) {
              throw const FormatException('Invalid data pack index entry.');
            }
            return DataPackIndexEntry.fromJson(pack);
          })
          .toList(growable: false),
    );
  }

  final int schemaVersion;
  final DateTime builtAt;
  final DateTime qualityAsOf;
  final DateTime freshnessExpiresAt;
  final String sourceSnapshotSetHash;
  final String schemaIdentity;
  final List<DataPackIndexEntry> packs;
}

class DataPackIndexEntry {
  const DataPackIndexEntry({
    required this.id,
    required this.asset,
    required this.sha256,
    required this.sqliteSha256,
    required this.byteSize,
  });

  factory DataPackIndexEntry.fromJson(Map<String, Object?> json) {
    return DataPackIndexEntry(
      id: _requiredString(json, 'id'),
      asset: _requiredString(json, 'asset'),
      sha256: _requiredString(json, 'sha256'),
      sqliteSha256: _requiredString(json, 'sqliteSha256'),
      byteSize: _requiredPositiveInt(json, 'byteSize'),
    );
  }

  final String id;
  final String asset;
  final String sha256;
  final String sqliteSha256;
  final int byteSize;
}

class UnsupportedDatapackSchemaException implements Exception {
  const UnsupportedDatapackSchemaException(this.schemaVersion);

  final Object? schemaVersion;
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw FormatException('Invalid data pack index field: $key.');
}

int _requiredPositiveInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int && value > 0) {
    return value;
  }
  throw FormatException('Invalid data pack index field: $key.');
}

String _requiredSha256(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw FormatException('Invalid data pack index field: $key.');
  }
  return value;
}

DateTime _requiredUtcDateTime(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  final parsed = DateTime.tryParse(value);
  if (parsed == null ||
      !value.endsWith('Z') ||
      parsed.toUtc().toIso8601String() != value) {
    throw FormatException('Invalid data pack index field: $key.');
  }
  return parsed.toUtc();
}
