class DataPackManifest {
  const DataPackManifest({
    required this.ttl,
    required this.packs,
    this.emergencyOverride,
  });

  factory DataPackManifest.fromJson(Map<String, Object?> json) {
    final ttlSeconds = json['ttlSeconds'];
    final rawPacks = json['packs'];
    if (ttlSeconds is! int || ttlSeconds <= 0 || rawPacks is! List) {
      throw const FormatException('Invalid data pack manifest.');
    }

    return DataPackManifest(
      ttl: Duration(seconds: ttlSeconds),
      packs: rawPacks
          .map((rawPack) {
            if (rawPack is! Map<String, Object?>) {
              throw const FormatException('Invalid data pack entry.');
            }
            return DataPackManifestEntry.fromJson(rawPack);
          })
          .toList(growable: false),
      emergencyOverride: _parseOverride(json['emergencyOverride']),
    );
  }

  final Duration ttl;
  final List<DataPackManifestEntry> packs;
  final EmergencyOverrideManifest? emergencyOverride;
}

class DataPackManifestEntry {
  const DataPackManifestEntry({
    required this.id,
    required this.version,
    required this.url,
    required this.compressedSha256,
    required this.sqliteSha256,
    required this.schemaVersion,
    required this.requiredTables,
    this.minimumTableRows = const {},
  });

  factory DataPackManifestEntry.fromJson(Map<String, Object?> json) {
    final id = _requiredString(json, 'id');
    final version = _requiredString(json, 'version');
    final url = _requiredString(json, 'url');
    final requiredTables = json['requiredTables'];
    final minimumTableRows = json['minimumTableRows'];
    if (requiredTables is! List || requiredTables.isEmpty) {
      throw const FormatException('Invalid required data pack tables.');
    }

    return DataPackManifestEntry(
      id: id,
      version: version,
      url: Uri.parse(url),
      compressedSha256: _requiredString(json, 'sha256'),
      sqliteSha256: _requiredString(json, 'sqliteSha256'),
      schemaVersion: _requiredString(json, 'schemaVersion'),
      requiredTables: requiredTables
          .map((table) {
            return _readTableName(table);
          })
          .toList(growable: false),
      minimumTableRows: _parseMinimumTableRows(minimumTableRows),
    );
  }

  final String id;
  final String version;
  final Uri url;
  final String compressedSha256;
  final String sqliteSha256;
  final String schemaVersion;
  final List<String> requiredTables;
  final Map<String, int> minimumTableRows;
}

class EmergencyOverrideManifest {
  const EmergencyOverrideManifest({
    required this.id,
    required this.version,
    required this.reason,
  });

  final String id;
  final String version;
  final String reason;
}

EmergencyOverrideManifest? _parseOverride(Object? rawOverride) {
  if (rawOverride == null) {
    return null;
  }
  if (rawOverride is! Map<String, Object?>) {
    throw const FormatException('Invalid emergency override.');
  }
  return EmergencyOverrideManifest(
    id: _requiredString(rawOverride, 'id'),
    version: _requiredString(rawOverride, 'version'),
    reason: _requiredString(rawOverride, 'reason'),
  );
}

Map<String, int> _parseMinimumTableRows(Object? rawRows) {
  if (rawRows == null) {
    return const {};
  }
  if (rawRows is! Map<String, Object?>) {
    throw const FormatException('Invalid minimum table rows.');
  }
  return rawRows.map((key, value) {
    final tableName = _readTableName(key);
    if (value is! int || value < 0) {
      throw const FormatException('Invalid minimum table row entry.');
    }
    return MapEntry(tableName, value);
  });
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Invalid data pack manifest value.');
  }
  return value.trim();
}

String _readTableName(Object? value) {
  if (value is! String) {
    throw const FormatException('Invalid data pack table name.');
  }
  final tableName = value.trim();
  final identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
  if (!identifier.hasMatch(tableName)) {
    throw const FormatException('Invalid data pack table name.');
  }
  return tableName;
}
