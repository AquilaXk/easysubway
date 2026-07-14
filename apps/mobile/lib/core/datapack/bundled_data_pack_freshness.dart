import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class BundledDataPackFreshness {
  const BundledDataPackFreshness({
    required this.status,
    required this.freshnessExpiresAt,
    required this.reasonCode,
    required this.labelKo,
  });

  static Future<BundledDataPackFreshness> read(
    Directory databaseDirectory,
  ) async {
    final file = File(
      p.join(databaseDirectory.path, 'datapacks', 'bundled-freshness.json'),
    );
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Invalid bundled data pack freshness.');
    }
    return BundledDataPackFreshness.fromJson(decoded);
  }

  factory BundledDataPackFreshness.fromJson(Map<String, Object?> json) {
    final status = _requiredString(json, 'status');
    final reasonCode = _requiredString(json, 'reasonCode');
    final labelKo = json['labelKo'];
    final expiresAt = DateTime.tryParse(
      _requiredString(json, 'freshnessExpiresAt'),
    );
    if (expiresAt == null || !expiresAt.isUtc) {
      throw const FormatException(
        'Invalid bundled data pack freshness expiry.',
      );
    }
    if (status == 'STALE') {
      if (reasonCode != 'BUNDLED_PACK_EXPIRED' ||
          labelKo is! String ||
          labelKo.trim().isEmpty) {
        throw const FormatException('Invalid stale bundled data pack state.');
      }
    } else if (status != 'FRESH' || reasonCode != 'NONE' || labelKo != '') {
      throw const FormatException('Invalid fresh bundled data pack state.');
    }
    return BundledDataPackFreshness(
      status: status,
      freshnessExpiresAt: expiresAt,
      reasonCode: reasonCode,
      labelKo: labelKo as String,
    );
  }

  final String status;
  final DateTime freshnessExpiresAt;
  final String reasonCode;
  final String labelKo;

  String? get staleLabel => status == 'STALE' ? labelKo : null;
}

String _requiredString(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! String || value.isEmpty) {
    throw FormatException('Invalid bundled data pack freshness $field.');
  }
  return value;
}
