import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

final _sha256Pattern = RegExp(r'^[a-f0-9]{64}$');

class DataPackManifest {
  const DataPackManifest({
    required this.ttl,
    required this.packs,
    this.activePack,
    this.emergencyOverride,
  });

  factory DataPackManifest.fromJson(
    Map<String, Object?> json, {
    DataPackSigningPublicKey? productionSigningPublicKey,
  }) {
    final ttlSeconds = json['ttlSeconds'];
    final rawPacks = json['packs'];
    if (ttlSeconds is! int || ttlSeconds <= 0 || rawPacks is! List<Object?>) {
      throw const FormatException('Invalid data pack manifest.');
    }

    return DataPackManifest(
      ttl: Duration(seconds: ttlSeconds),
      packs: rawPacks
          .map((rawPack) {
            if (rawPack is! Map<String, Object?>) {
              throw const FormatException('Invalid data pack entry.');
            }
            return DataPackManifestEntry.fromJson(
              rawPack,
              productionSigningPublicKey: productionSigningPublicKey,
            );
          })
          .toList(growable: false),
      activePack: _parseActivePack(json['activePack']),
      emergencyOverride: _parseOverride(json['emergencyOverride']),
    );
  }

  final Duration ttl;
  final List<DataPackManifestEntry> packs;
  final ActiveDataPackManifest? activePack;
  final EmergencyOverrideManifest? emergencyOverride;
}

/// Production manifests sign the source inventory, regional quality metrics,
/// and representative route regressions.
///
/// Contract marker: production signatures bind the pack URL.
class DataPackManifestEntry {
  const DataPackManifestEntry({
    required this.id,
    required this.version,
    required this.url,
    required this.compressedSha256,
    required this.sqliteSha256,
    required this.sizeBytes,
    required this.artifactKind,
    required this.signature,
    required this.sourceInventory,
    required this.regionalQualityMetrics,
    required this.representativeRouteRegressions,
    required this.representativeRouteRegressionSignature,
    required this.schemaVersion,
    required this.requiredTables,
    this.minimumTableRows = const {},
  });

  factory DataPackManifestEntry.fromJson(
    Map<String, Object?> json, {
    DataPackSigningPublicKey? productionSigningPublicKey,
  }) {
    final id = _readPackId(json['id']);
    final version = _readPackVersion(json['version']);
    final url = _parsePackUrl(_requiredString(json, 'url'));
    final artifactKind = _parseArtifactKind(json['artifactKind'], url);
    final requiredTables = json['requiredTables'];
    final minimumTableRows = json['minimumTableRows'];
    if (requiredTables is! List<Object?> || requiredTables.isEmpty) {
      throw const FormatException('Invalid required data pack tables.');
    }

    return DataPackManifestEntry(
      id: id,
      version: version,
      url: url,
      compressedSha256: _requiredString(json, 'sha256'),
      sqliteSha256: _requiredString(json, 'sqliteSha256'),
      sizeBytes: _optionalPositiveInt(json, 'sizeBytes', artifactKind),
      artifactKind: artifactKind,
      signature: _parseSignature(json['signature'], artifactKind),
      sourceInventory: _parseSourceInventory(
        json['sourceInventory'],
        artifactKind,
      ),
      regionalQualityMetrics: _parseRegionalQualityMetrics(
        json['regionalQualityMetrics'],
        artifactKind,
      ),
      representativeRouteRegressions: _parseRepresentativeRouteRegressions(
        json['representativeRouteRegressions'],
        artifactKind,
      ),
      representativeRouteRegressionSignature:
          _parseRepresentativeRouteRegressionSignature(
            json['representativeRouteRegressionSignature'],
            artifactKind,
          ),
      schemaVersion: _requiredString(json, 'schemaVersion'),
      requiredTables: requiredTables
          .map((table) {
            return _readTableName(table);
          })
          .toList(growable: false),
      minimumTableRows: _parseMinimumTableRows(minimumTableRows),
    ).._validateManifestContract(productionSigningPublicKey);
  }

  final String id;
  final String version;
  final Uri url;
  final String compressedSha256;
  final String sqliteSha256;
  final int? sizeBytes;
  final DataPackArtifactKind artifactKind;
  final DataPackSignature signature;
  final List<DataPackSourceInventoryEntry> sourceInventory;
  final RegionalQualityMetrics regionalQualityMetrics;
  final List<DataPackRepresentativeRouteRegression>
  representativeRouteRegressions;
  final DataPackSignature representativeRouteRegressionSignature;
  final String schemaVersion;
  final List<String> requiredTables;
  final Map<String, int> minimumTableRows;

  void _validateManifestContract(
    DataPackSigningPublicKey? productionSigningPublicKey,
  ) {
    final expectedSizeBytes = sizeBytes;
    if (productionSigningPublicKey != null &&
        artifactKind != DataPackArtifactKind.production) {
      throw const FormatException('Invalid data pack artifact kind.');
    }
    _validateSignature(expectedSizeBytes, productionSigningPublicKey);
    if (artifactKind != DataPackArtifactKind.production) {
      return;
    }
    if (!_isAbsoluteHttpsWithHost(url)) {
      throw const FormatException('Invalid production data pack URL.');
    }
    if (sourceInventory.isEmpty ||
        sourceInventory.any(
          (source) =>
              source.licenseStatus != 'redistributable' ||
              !source.redistributionAllowed ||
              !_isAbsoluteHttpsWithHost(source.url),
        )) {
      throw const FormatException('Invalid production data pack source.');
    }
  }

  void _validateSignature(
    int? expectedSizeBytes,
    DataPackSigningPublicKey? productionSigningPublicKey,
  ) {
    if (expectedSizeBytes == null) {
      return;
    }
    final canonical = _signaturePayload(expectedSizeBytes);
    if (artifactKind == DataPackArtifactKind.production) {
      final publicKey = productionSigningPublicKey;
      if (publicKey == null) {
        throw const FormatException('Invalid data pack signature.');
      }
      if (signature.algorithm != 'rsa-sha256-pack-manifest-v1' ||
          !publicKey.verify(canonical, signature.value)) {
        throw const FormatException('Invalid data pack signature.');
      }
      _validateRepresentativeRouteRegressionSignature(
        expectedSizeBytes,
        productionSigningPublicKey,
      );
      return;
    }
    if (signature.algorithm != 'sha256-pack-manifest-v1') {
      throw const FormatException('Invalid data pack signature.');
    }
    if (signature.value != sha256.convert(utf8.encode(canonical)).toString()) {
      throw const FormatException('Invalid data pack signature.');
    }
    _validateRepresentativeRouteRegressionSignature(
      expectedSizeBytes,
      productionSigningPublicKey,
    );
  }

  String _signaturePayload(int expectedSizeBytes) {
    final fixturePayload = _fixtureSignaturePayload(expectedSizeBytes);
    if (artifactKind == DataPackArtifactKind.production) {
      return '$fixturePayload:${url.toString()}';
    }
    return fixturePayload;
  }

  void _validateRepresentativeRouteRegressionSignature(
    int expectedSizeBytes,
    DataPackSigningPublicKey? productionSigningPublicKey,
  ) {
    if (artifactKind == DataPackArtifactKind.fixture &&
        representativeRouteRegressions.isEmpty &&
        representativeRouteRegressionSignature.algorithm ==
            'sha256-route-regression-v1' &&
        representativeRouteRegressionSignature.value == '0' * 64) {
      return;
    }
    final canonical = _representativeRouteRegressionSignaturePayload(
      expectedSizeBytes,
    );
    if (artifactKind == DataPackArtifactKind.production) {
      final publicKey = productionSigningPublicKey;
      if (publicKey == null) {
        throw const FormatException('Invalid data pack signature.');
      }
      if (representativeRouteRegressionSignature.algorithm !=
              'rsa-sha256-route-regression-v1' ||
          !publicKey.verify(
            canonical,
            representativeRouteRegressionSignature.value,
          )) {
        throw const FormatException('Invalid data pack signature.');
      }
      return;
    }
    if (representativeRouteRegressionSignature.algorithm !=
        'sha256-route-regression-v1') {
      throw const FormatException('Invalid data pack signature.');
    }
    if (representativeRouteRegressionSignature.value !=
        sha256.convert(utf8.encode(canonical)).toString()) {
      throw const FormatException('Invalid data pack signature.');
    }
  }

  String _representativeRouteRegressionSignaturePayload(int expectedSizeBytes) {
    final fixturePayload =
        '${_fixtureSignaturePayload(expectedSizeBytes)}:${_representativeRouteRegressionPayload()}';
    if (artifactKind == DataPackArtifactKind.production) {
      return '$fixturePayload:${url.toString()}';
    }
    return fixturePayload;
  }

  String _fixtureSignaturePayload(int expectedSizeBytes) {
    return '$id:$version:$compressedSha256:$sqliteSha256:$expectedSizeBytes';
  }

  String _representativeRouteRegressionPayload() {
    return jsonEncode(
      representativeRouteRegressions
          .map((route) => route.toSignatureJson())
          .toList(growable: false),
    );
  }
}

class DataPackSigningPublicKey {
  const DataPackSigningPublicKey({
    required this.modulusBase64Url,
    required this.exponentBase64Url,
  });

  final String modulusBase64Url;
  final String exponentBase64Url;

  bool verify(String message, String signatureBase64Url) {
    try {
      final modulusBytes = _base64UrlBytes(modulusBase64Url);
      final exponentBytes = _base64UrlBytes(exponentBase64Url);
      final signatureBytes = _base64UrlBytes(signatureBase64Url);
      if (modulusBytes.isEmpty ||
          exponentBytes.isEmpty ||
          signatureBytes.length != modulusBytes.length) {
        return false;
      }
      final modulus = _bigIntFromBytes(modulusBytes);
      final exponent = _bigIntFromBytes(exponentBytes);
      final signature = _bigIntFromBytes(signatureBytes);
      if (modulus <= BigInt.zero ||
          exponent <= BigInt.one ||
          signature >= modulus) {
        return false;
      }
      final encoded = _bigIntToFixedLengthBytes(
        signature.modPow(exponent, modulus),
        modulusBytes.length,
      );
      final digestInfo = <int>[
        0x30,
        0x31,
        0x30,
        0x0d,
        0x06,
        0x09,
        0x60,
        0x86,
        0x48,
        0x01,
        0x65,
        0x03,
        0x04,
        0x02,
        0x01,
        0x05,
        0x00,
        0x04,
        0x20,
        ...sha256.convert(utf8.encode(message)).bytes,
      ];
      final paddingLength = modulusBytes.length - digestInfo.length - 3;
      if (paddingLength < 8) {
        return false;
      }
      final expected = <int>[
        0x00,
        0x01,
        ...List<int>.filled(paddingLength, 0xff),
        0x00,
        ...digestInfo,
      ];
      return _constantTimeBytesEquals(encoded, expected);
    } on FormatException {
      return false;
    } on RangeError {
      return false;
    }
  }
}

enum DataPackArtifactKind { fixture, production }

class DataPackSignature {
  const DataPackSignature({required this.algorithm, required this.value});

  factory DataPackSignature.fromJson(Map<String, Object?> json) {
    final algorithm = _requiredString(json, 'algorithm');
    if (algorithm != 'sha256-pack-manifest-v1' &&
        algorithm != 'rsa-sha256-pack-manifest-v1' &&
        algorithm != 'sha256-route-regression-v1' &&
        algorithm != 'rsa-sha256-route-regression-v1') {
      throw const FormatException('Invalid data pack signature.');
    }
    final value = _requiredString(json, 'value');
    if (!_sha256Pattern.hasMatch(value) &&
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      throw const FormatException('Invalid data pack signature.');
    }
    return DataPackSignature(algorithm: algorithm, value: value);
  }

  final String algorithm;
  final String value;
}

bool _isAbsoluteHttpsWithHost(Uri uri) {
  return uri.isAbsolute &&
      uri.scheme == 'https' &&
      uri.hasAuthority &&
      uri.host.isNotEmpty;
}

Uint8List _base64UrlBytes(String value) {
  return base64Url.decode(base64Url.normalize(value));
}

BigInt _bigIntFromBytes(List<int> bytes) {
  var result = BigInt.zero;
  for (final byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}

Uint8List _bigIntToFixedLengthBytes(BigInt value, int length) {
  final bytes = List<int>.filled(length, 0);
  var remaining = value;
  for (var index = length - 1; index >= 0; index--) {
    bytes[index] = (remaining & BigInt.from(0xff)).toInt();
    remaining = remaining >> 8;
  }
  if (remaining != BigInt.zero) {
    throw RangeError('RSA value exceeds modulus length.');
  }
  return Uint8List.fromList(bytes);
}

bool _constantTimeBytesEquals(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  var diff = 0;
  for (var index = 0; index < left.length; index++) {
    diff |= left[index] ^ right[index];
  }
  return diff == 0;
}

class DataPackSourceInventoryEntry {
  const DataPackSourceInventoryEntry({
    required this.id,
    required this.owner,
    required this.url,
    required this.license,
    required this.licenseStatus,
    required this.redistributionAllowed,
    required this.updateFrequency,
    required this.updatedAt,
    required this.fields,
  });

  factory DataPackSourceInventoryEntry.fromJson(Map<String, Object?> json) {
    final fields = json['fields'];
    if (fields is! List<Object?> || fields.isEmpty) {
      throw const FormatException('Invalid data pack source fields.');
    }
    return DataPackSourceInventoryEntry(
      id: _requiredString(json, 'id'),
      owner: _requiredString(json, 'owner'),
      url: Uri.parse(_requiredString(json, 'url')),
      license: _requiredString(json, 'license'),
      licenseStatus: _requiredString(json, 'licenseStatus'),
      redistributionAllowed: _requiredBool(json, 'redistributionAllowed'),
      updateFrequency: _requiredString(json, 'updateFrequency'),
      updatedAt: _requiredString(json, 'updatedAt'),
      fields: fields
          .map((field) {
            if (field is! String || field.trim().isEmpty) {
              throw const FormatException('Invalid data pack source fields.');
            }
            return field.trim();
          })
          .toList(growable: false),
    );
  }

  final String id;
  final String owner;
  final Uri url;
  final String license;
  final String licenseStatus;
  final bool redistributionAllowed;
  final String updateFrequency;
  final String updatedAt;
  final List<String> fields;
}

class RegionalQualityMetrics {
  const RegionalQualityMetrics({
    required this.stationCount,
    required this.facilityCoverageRatio,
    required this.edgeCount,
    required this.unknownAccessibilityRatio,
  });

  factory RegionalQualityMetrics.fromJson(Map<String, Object?> json) {
    return RegionalQualityMetrics(
      stationCount: _requiredNonNegativeInt(json, 'stationCount'),
      facilityCoverageRatio: _requiredRatio(json, 'facilityCoverageRatio'),
      edgeCount: _requiredNonNegativeInt(json, 'edgeCount'),
      unknownAccessibilityRatio: _requiredRatio(
        json,
        'unknownAccessibilityRatio',
      ),
    );
  }

  final int stationCount;
  final double facilityCoverageRatio;
  final int edgeCount;
  final double unknownAccessibilityRatio;
}

class DataPackRepresentativeRouteRegression {
  const DataPackRepresentativeRouteRegression({
    required this.id,
    required this.pattern,
    required this.fromNodeId,
    required this.toNodeId,
    required this.requiredEdgeIds,
  });

  factory DataPackRepresentativeRouteRegression.fromJson(
    Map<String, Object?> json,
  ) {
    final rawRequiredEdgeIds = json['requiredEdgeIds'];
    if (rawRequiredEdgeIds is! List<Object?> || rawRequiredEdgeIds.isEmpty) {
      throw const FormatException('Invalid representative route regression.');
    }
    final pattern = _requiredString(json, 'pattern');
    if (!_representativeRoutePatterns.contains(pattern)) {
      throw const FormatException('Invalid representative route regression.');
    }
    return DataPackRepresentativeRouteRegression(
      id: _requiredString(json, 'id'),
      pattern: pattern,
      fromNodeId: _requiredString(json, 'fromNodeId'),
      toNodeId: _requiredString(json, 'toNodeId'),
      requiredEdgeIds: rawRequiredEdgeIds
          .map((edgeId) => _readRequiredString(edgeId))
          .toList(growable: false),
    );
  }

  final String id;
  final String pattern;
  final String fromNodeId;
  final String toNodeId;
  final List<String> requiredEdgeIds;

  Map<String, Object?> toSignatureJson() {
    return {
      'id': id,
      'pattern': pattern,
      'fromNodeId': fromNodeId,
      'toNodeId': toNodeId,
      'requiredEdgeIds': requiredEdgeIds,
    };
  }
}

const _representativeRoutePatterns = {
  'DIRECT',
  'TRANSFER',
  'MULTI_TRANSFER',
  'LOOP_BRANCH',
  'EXPRESS_LOCAL',
};

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

class ActiveDataPackManifest {
  const ActiveDataPackManifest({required this.id, required this.version});

  final String id;
  final String version;
}

ActiveDataPackManifest? _parseActivePack(Object? rawActivePack) {
  if (rawActivePack == null) {
    return null;
  }
  if (rawActivePack is! Map<String, Object?>) {
    throw const FormatException('Invalid active data pack.');
  }
  return ActiveDataPackManifest(
    id: _readPackId(rawActivePack['id']),
    version: _readPackVersion(rawActivePack['version']),
  );
}

EmergencyOverrideManifest? _parseOverride(Object? rawOverride) {
  if (rawOverride == null) {
    return null;
  }
  if (rawOverride is! Map<String, Object?>) {
    throw const FormatException('Invalid emergency override.');
  }
  return EmergencyOverrideManifest(
    id: _readPackId(rawOverride['id']),
    version: _readPackVersion(rawOverride['version']),
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

DataPackSignature _parseSignature(
  Object? rawSignature,
  DataPackArtifactKind artifactKind,
) {
  if (rawSignature == null && artifactKind == DataPackArtifactKind.fixture) {
    return DataPackSignature(
      algorithm: 'sha256-pack-manifest-v1',
      value: '0' * 64,
    );
  }
  if (rawSignature is! Map<String, Object?>) {
    throw const FormatException('Invalid data pack signature.');
  }
  return DataPackSignature.fromJson(rawSignature);
}

DataPackSignature _parseRepresentativeRouteRegressionSignature(
  Object? rawSignature,
  DataPackArtifactKind artifactKind,
) {
  if (rawSignature == null && artifactKind == DataPackArtifactKind.fixture) {
    return DataPackSignature(
      algorithm: 'sha256-route-regression-v1',
      value: '0' * 64,
    );
  }
  if (rawSignature is! Map<String, Object?>) {
    throw const FormatException('Invalid data pack signature.');
  }
  return DataPackSignature.fromJson(rawSignature);
}

List<DataPackSourceInventoryEntry> _parseSourceInventory(
  Object? rawSources,
  DataPackArtifactKind artifactKind,
) {
  if (rawSources == null && artifactKind == DataPackArtifactKind.fixture) {
    return [
      DataPackSourceInventoryEntry(
        id: 'legacy-fixture-manifest',
        owner: 'legacy-fixture',
        url: Uri.parse('https://example.invalid/legacy-fixture'),
        license: 'fixture-only',
        licenseStatus: 'fixture-only',
        redistributionAllowed: false,
        updateFrequency: 'manual',
        updatedAt: '1970-01-01T00:00:00.000Z',
        fields: const ['legacy'],
      ),
    ];
  }
  if (rawSources is! List<Object?> || rawSources.isEmpty) {
    throw const FormatException('Invalid data pack source inventory.');
  }
  return rawSources
      .map((source) {
        if (source is! Map<String, Object?>) {
          throw const FormatException('Invalid data pack source inventory.');
        }
        return DataPackSourceInventoryEntry.fromJson(source);
      })
      .toList(growable: false);
}

DataPackArtifactKind _parseArtifactKind(Object? rawKind, Uri url) {
  if (rawKind == null) {
    return url.isAbsolute
        ? DataPackArtifactKind.production
        : DataPackArtifactKind.fixture;
  }
  return switch (_readRequiredString(rawKind)) {
    'fixture' => DataPackArtifactKind.fixture,
    'production' => DataPackArtifactKind.production,
    _ => throw const FormatException('Invalid data pack artifact kind.'),
  };
}

RegionalQualityMetrics _parseRegionalQualityMetrics(
  Object? rawMetrics,
  DataPackArtifactKind artifactKind,
) {
  if (rawMetrics == null && artifactKind == DataPackArtifactKind.fixture) {
    return const RegionalQualityMetrics(
      stationCount: 0,
      facilityCoverageRatio: 0,
      edgeCount: 0,
      unknownAccessibilityRatio: 0,
    );
  }
  if (rawMetrics is! Map<String, Object?>) {
    throw const FormatException('Invalid regional quality metrics.');
  }
  return RegionalQualityMetrics.fromJson(rawMetrics);
}

List<DataPackRepresentativeRouteRegression>
_parseRepresentativeRouteRegressions(
  Object? rawRoutes,
  DataPackArtifactKind artifactKind,
) {
  if (rawRoutes == null && artifactKind == DataPackArtifactKind.fixture) {
    return const [];
  }
  if (rawRoutes is! List<Object?> || rawRoutes.isEmpty) {
    throw const FormatException('Invalid representative route regressions.');
  }
  final routes = rawRoutes
      .map((route) {
        if (route is! Map<String, Object?>) {
          throw const FormatException(
            'Invalid representative route regression.',
          );
        }
        return DataPackRepresentativeRouteRegression.fromJson(route);
      })
      .toList(growable: false);
  final seenPatterns = routes.map((route) => route.pattern).toSet();
  if (!_representativeRoutePatterns.every(seenPatterns.contains)) {
    throw const FormatException('Invalid representative route regressions.');
  }
  return routes;
}

String _requiredString(Map<String, Object?> json, String key) {
  return _readRequiredString(json[key]);
}

Uri _parsePackUrl(String rawUrl) {
  if (_containsRawDotSegment(rawUrl) || _containsEncodedPathBoundary(rawUrl)) {
    throw const FormatException('Invalid data pack URL.');
  }
  final uri = Uri.parse(rawUrl);
  if (uri.isAbsolute) {
    if (uri.scheme != 'https') {
      throw const FormatException('Invalid data pack URL.');
    }
    return uri;
  }
  if (uri.hasAuthority ||
      rawUrl.startsWith('/') ||
      rawUrl.startsWith('//') ||
      rawUrl.contains(r'\')) {
    throw const FormatException('Invalid data pack URL.');
  }
  return uri;
}

bool _containsRawDotSegment(String rawUrl) {
  return rawUrl.split('/').any((segment) => segment == '..');
}

bool _containsEncodedPathBoundary(String rawUrl) {
  return RegExp(r'%(?:2e|2f|5c)', caseSensitive: false).hasMatch(rawUrl);
}

String _readRequiredString(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Invalid data pack manifest value.');
  }
  return value.trim();
}

int? _optionalPositiveInt(
  Map<String, Object?> json,
  String key,
  DataPackArtifactKind artifactKind,
) {
  final value = json[key];
  if (value == null && artifactKind == DataPackArtifactKind.fixture) {
    return null;
  }
  if (value is! int || value <= 0) {
    throw const FormatException('Invalid data pack manifest value.');
  }
  return value;
}

int _requiredNonNegativeInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int || value < 0) {
    throw const FormatException('Invalid data pack manifest value.');
  }
  return value;
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) {
    throw const FormatException('Invalid data pack manifest value.');
  }
  return value;
}

double _requiredRatio(Map<String, Object?> json, String key) {
  final value = json[key];
  final ratio = value is int ? value.toDouble() : value;
  if (ratio is! double || ratio < 0 || ratio > 1) {
    throw const FormatException('Invalid data pack manifest value.');
  }
  return ratio;
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

String _readPackId(Object? value) {
  if (value is! String) {
    throw const FormatException('Invalid data pack identity.');
  }
  final packId = value.trim();
  final identifier = RegExp(r'^[A-Za-z][A-Za-z0-9_-]*$');
  if (!identifier.hasMatch(packId)) {
    throw const FormatException('Invalid data pack identity.');
  }
  return packId;
}

String _readPackVersion(Object? value) {
  if (value is! String) {
    throw const FormatException('Invalid data pack version.');
  }
  final version = value.trim();
  final numericVersion = RegExp(r'^[0-9]+$');
  if (!numericVersion.hasMatch(version)) {
    throw const FormatException('Invalid data pack version.');
  }
  return version;
}
