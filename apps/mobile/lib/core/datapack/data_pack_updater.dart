import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

import 'data_pack_client.dart';
import 'data_pack_installer.dart';
import 'data_pack_manifest.dart';
import 'data_pack_update_policy.dart';
import 'data_pack_update_state.dart';
import 'emergency_override_repository.dart';
import 'network_condition_source.dart';

const _dataPackDownloadTimeout = Duration(seconds: 20);
const _maxDataPackDownloadBytes = 250 * 1024 * 1024;

class DataPackUpdater {
  DataPackUpdater({
    required this.client,
    required this.installer,
    this.emergencyOverrideRepository,
    this.activePackId = 'capital',
    this.networkConditionSource = const FixedNetworkConditionSource(
      NetworkCondition.unmetered,
    ),
    this.policy = DataPackUpdatePolicyDefaults.policy,
    HttpClient? httpClient,
    DateTime Function()? now,
  }) : _httpClient = httpClient ?? HttpClient(),
       _now = now ?? DateTime.now;

  final DataPackClient client;
  final DataPackInstaller installer;
  final EmergencyOverrideRepository? emergencyOverrideRepository;
  final String activePackId;
  final NetworkConditionSource networkConditionSource;
  final DataPackUpdatePolicy policy;
  final HttpClient _httpClient;
  final DateTime Function() _now;
  Future<List<DataPackInstallResult>>? _inFlight;

  Future<List<DataPackInstallResult>> checkForUpdates({
    UpdateTrigger trigger = UpdateTrigger.appStart,
  }) {
    final inFlight = _inFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final next = _checkForUpdates(trigger: trigger);
    _inFlight = next.whenComplete(() {
      _inFlight = null;
    });
    return _inFlight!;
  }

  Future<List<DataPackInstallResult>> _checkForUpdates({
    required UpdateTrigger trigger,
  }) async {
    await installer.recoverInstallJournal();
    var policyState = await client.stateRepository.readPolicyState();
    final now = _now().toUtc();
    if (await _shouldSkipCheck(
      trigger: trigger,
      policyState: policyState,
      now: now,
    )) {
      return const [];
    }
    // 사용자가 명시적으로 수락한 다운로드(userConsent)는 실패 backoff 창과
    // 무관하게 즉시 시도한다 — 동의 액션의 무음 실패 금지 (#1910).
    final backoffUntil = policyState.backoffUntil;
    if (trigger != UpdateTrigger.userConsent &&
        backoffUntil != null &&
        now.isBefore(backoffUntil)) {
      return const [];
    }
    final networkCondition = await networkConditionSource.current();
    if (networkCondition == NetworkCondition.offline) {
      return const [];
    }
    policyState = policyState.copyWith(lastCheckAt: now);
    await client.stateRepository.savePolicyState(policyState);

    final DataPackManifestFetchResult manifestResult;
    try {
      manifestResult = await client.fetchManifestIfNeeded();
    } on Object catch (error) {
      await _saveFailure(policyState, now, error);
      rethrow;
    }
    final manifest = manifestResult.manifest;
    if (manifest == null) {
      return const [];
    }

    // rollout 버킷 판정 — salt + seed → sha256 → bucket % 100
    final rollout = manifest.rollout;
    bool isRolloutApplied = true; // rollout 부재 = 100%(항상 채택)
    if (rollout != null) {
      final salt = await client.stateRepository.readOrCreateRolloutSalt();
      isRolloutApplied = rolloutApplies(salt, rollout);
    }
    final rolloutDecision = rollout == null
        ? 'noRollout'
        : isRolloutApplied
        ? 'applied'
        : 'heldOut';
    developer.log('rolloutDecision=$rolloutDecision', name: 'DataPackUpdater');

    final preUpdateCurrentPointer = await _readCurrentPointerSafely();
    final override = manifest.emergencyOverride;
    final protectedVersionsByPackId = <String, Set<String>>{};
    if (preUpdateCurrentPointer != null) {
      _protectVersion(
        protectedVersionsByPackId,
        id: preUpdateCurrentPointer.id,
        version: preUpdateCurrentPointer.version,
      );
    }
    if (override != null) {
      _protectVersion(
        protectedVersionsByPackId,
        id: override.id,
        version: override.version,
      );
    }

    final packBaseUri = _packBaseUriForManifest(client.manifestUri);
    final packs = _packsToInstall(manifest, rolloutApplies: isRolloutApplied);
    if (packs.isNotEmpty &&
        networkCondition == NetworkCondition.metered &&
        trigger != UpdateTrigger.userConsent) {
      await client.stateRepository.savePolicyState(
        policyState.copyWith(pendingConsentBytes: _totalSizeBytes(packs)),
      );
      return const [];
    }
    final results = <DataPackInstallResult>[];
    try {
      for (final pack in packs) {
        final uri = packBaseUri.resolve(pack.url.toString());
        final compressedFile = await _downloadToTemporaryFile(uri, pack);
        results.add(
          await installer.installFromCompressedFile(
            pack: pack,
            compressedFile: compressedFile,
            protectedVersions:
                protectedVersionsByPackId[pack.id] ?? const <String>{},
            activateCurrent: false,
          ),
        );
      }
    } on Object catch (error) {
      await _saveFailure(policyState, now, error);
      rethrow;
    }
    if (results.any(
      (result) => result.status != DataPackInstallStatus.installed,
    )) {
      await _saveFailure(policyState, now, 'install');
    }
    if (results.every(
      (result) => result.status == DataPackInstallStatus.installed,
    )) {
      final currentPointer = await _currentPointerForManifest(
        manifest: manifest,
        results: results,
        rolloutApplies: isRolloutApplied,
      );
      if (currentPointer != null) {
        await installer.activateCurrentPointer(currentPointer);
        _protectVersion(
          protectedVersionsByPackId,
          id: currentPointer.id,
          version: currentPointer.version,
        );
      }
      for (final result in results) {
        final pointer = result.pointer;
        if (pointer != null) {
          _protectVersion(
            protectedVersionsByPackId,
            id: pointer.id,
            version: pointer.version,
          );
        }
      }
      for (final packId in packs.map((pack) => pack.id).toSet()) {
        await installer.pruneObsoletePacks(
          packId,
          keepVersionCount: 2,
          protectedVersions:
              protectedVersionsByPackId[packId] ?? const <String>{},
        );
      }
      if (override != null) {
        final installedOverride = await installer.readInstalledPointer(
          id: override.id,
          version: override.version,
        );
        if (installedOverride != null) {
          await emergencyOverrideRepository?.saveOverride(
            EmergencyDataPackOverride(
              id: override.id,
              version: override.version,
              reason: override.reason,
            ),
          );
        } else {
          await emergencyOverrideRepository?.clearOverride();
        }
      } else {
        await emergencyOverrideRepository?.clearOverride();
      }
      await client.saveManifestCache(manifestResult);
      await client.stateRepository.savePolicyState(
        policyState.copyWith(
          clearBackoff: true,
          clearPendingConsent: true,
          clearLastFailure: true,
        ),
      );
    }
    return results;
  }

  Future<bool> _shouldSkipCheck({
    required UpdateTrigger trigger,
    required DataPackUpdatePolicyState policyState,
    required DateTime now,
  }) async {
    if (trigger != UpdateTrigger.foregroundResume) {
      return false;
    }
    if (policyState.pendingConsentBytes != null) {
      return false;
    }
    if (policy.expiryUrgentIgnoresMinInterval) {
      final cache = await client.stateRepository.readManifestCache();
      final expiresAt = cache?.expiresAt;
      if (expiresAt != null &&
          !expiresAt.isAfter(now.add(policy.expiryUrgentWindow))) {
        return false;
      }
    }
    final lastCheckAt = policyState.lastCheckAt;
    if (lastCheckAt == null) {
      return false;
    }
    return now.isBefore(
      lastCheckAt.add(policy.manifestCheckOnResumeMinInterval),
    );
  }

  Future<void> _saveFailure(
    DataPackUpdatePolicyState state,
    DateTime now,
    Object error,
  ) async {
    final attempts = (state.backoffAttempts + 1).clamp(
      1,
      policy.retryMaxAttemptsPerSession,
    );
    await client.stateRepository.savePolicyState(
      state.copyWith(
        lastCheckAt: now,
        backoffAttempts: attempts,
        backoffUntil: now.add(policy.backoffForAttempt(attempts)),
        lastFailureReason: _failureReason(error),
      ),
    );
  }

  int _totalSizeBytes(List<DataPackManifestEntry> packs) {
    return packs.fold<int>(0, (total, pack) => total + (pack.sizeBytes ?? 0));
  }

  String _failureReason(Object error) {
    if (error is DataPackClientException) {
      return error.message;
    }
    return error.toString();
  }

  Future<InstalledDataPackPointer?> _readCurrentPointerSafely() async {
    try {
      return await installer.readCurrentPointer();
    } on Object {
      return null;
    }
  }

  List<DataPackManifestEntry> _packsToInstall(
    DataPackManifest manifest, {
    bool rolloutApplies = true,
  }) {
    final activePack = manifest.activePack;
    final override = manifest.emergencyOverride;
    final selectedPacks = manifest.packs
        .where((pack) {
          // emergencyOverride 대상 팩은 rollout과 무관하게 항상 포함
          if (_matchesOverride(pack, override)) return true;
          // rollout 비대상이면 일반 팩 제외
          if (!rolloutApplies) return false;
          final selectedActiveId = activePack?.id ?? activePackId;
          return pack.id == selectedActiveId;
        })
        .toList(growable: false);
    final selectedDependencies = selectedPacks
        .expand((pack) => pack.dependencies)
        .toList(growable: false);
    return manifest.packs
        .where((pack) {
          if (selectedPacks.contains(pack)) {
            return true;
          }
          return selectedDependencies.any(
            (dependency) =>
                dependency.id == pack.id &&
                _versionNumber(dependency.version) ==
                    _versionNumber(pack.version),
          );
        })
        .toList(growable: false);
  }

  Future<InstalledDataPackPointer?> _currentPointerForManifest({
    required DataPackManifest manifest,
    required List<DataPackInstallResult> results,
    bool rolloutApplies = true,
  }) async {
    final activePack = manifest.activePack;
    if (activePack != null) {
      for (final result in results) {
        final pointer = result.pointer;
        if (pointer?.id == activePack.id &&
            _versionNumber(pointer?.version ?? '') ==
                _versionNumber(activePack.version)) {
          return pointer;
        }
      }
      final installedPointer = await installer.readInstalledPointer(
        id: activePack.id,
        version: activePack.version,
      );
      if (installedPointer != null) {
        return installedPointer;
      }
      // heldOut 단말 + activePack 미설치: 예외 대신 null 반환(기존 포인터 유지).
      // rolloutApplied 단말이거나 activePack이 설치된 경우는 이미 위에서 반환.
      if (!rolloutApplies) {
        return null;
      }
      throw const DataPackClientException('사용할 이동 정보를 선택하지 못했어요.');
    }

    if (results.isEmpty) {
      return null;
    }

    InstalledDataPackPointer? selected;
    for (final result in results) {
      final pointer = result.pointer;
      if (pointer == null || pointer.id != activePackId) {
        continue;
      }
      if (selected == null ||
          _versionNumber(pointer.version) > _versionNumber(selected.version)) {
        selected = pointer;
      }
    }
    if (selected == null) {
      throw const DataPackClientException('사용할 이동 정보를 선택하지 못했어요.');
    }
    return selected;
  }

  Uri _packBaseUriForManifest(Uri manifestUri) {
    final manifestDirectory = manifestUri.resolve('./');
    final pathSegments = manifestUri.pathSegments;
    if (pathSegments.length >= 2 &&
        pathSegments[pathSegments.length - 2] == 'catalog' &&
        pathSegments.last == 'current.json') {
      return manifestDirectory.resolve('../');
    }
    return manifestDirectory;
  }

  Future<File> _downloadToTemporaryFile(
    Uri uri,
    DataPackManifestEntry pack,
  ) async {
    final request = await _httpClient
        .getUrl(uri)
        .timeout(_dataPackDownloadTimeout);
    final response = await request.close().timeout(_dataPackDownloadTimeout);
    if (response.statusCode != HttpStatus.ok) {
      throw const DataPackClientException('이동 정보를 내려받지 못했어요.');
    }
    final expectedSizeBytes = pack.sizeBytes;
    final contentLength = response.contentLength;
    final maxBytes = expectedSizeBytes ?? _maxDataPackDownloadBytes;
    if (contentLength > maxBytes || contentLength > _maxDataPackDownloadBytes) {
      throw const DataPackClientException('이동 정보 파일이 너무 큽니다.');
    }
    final directory = await installer.catalogDirectory.create(recursive: true);
    final temporary = File(
      '${directory.path}/${pack.id}-v${pack.version}.sqlite.gz.downloading',
    );
    final sink = temporary.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.timeout(_dataPackDownloadTimeout)) {
        received += chunk.length;
        if (received > maxBytes || received > _maxDataPackDownloadBytes) {
          throw const DataPackClientException('이동 정보 파일이 너무 큽니다.');
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      return temporary;
    } on Object {
      await sink.close();
      await _deleteIfExists(temporary);
      rethrow;
    }
  }
}

enum UpdateTrigger { appStart, foregroundResume, userConsent }

Future<void> _deleteIfExists(File file) async {
  if (await file.exists()) {
    await file.delete();
  }
}

int _versionNumber(String version) {
  return int.tryParse(version) ?? 0;
}

bool _matchesOverride(
  DataPackManifestEntry pack,
  EmergencyOverrideManifest? override,
) {
  return override != null &&
      pack.id == override.id &&
      _versionNumber(pack.version) == _versionNumber(override.version);
}

void _protectVersion(
  Map<String, Set<String>> protectedVersionsByPackId, {
  required String id,
  required String version,
}) {
  protectedVersionsByPackId
      .putIfAbsent(id, () => <String>{})
      .add(_normalizedVersion(version));
}

String _normalizedVersion(String version) {
  return _versionNumber(version).toString();
}

/// salt + seed → sha256 → 첫 8 hex 자리를 정수로 파싱 → % 100 → 0~99 버킷.
///
/// 버킷은 seed에만 의존하므로 percentage와 독립적이다. percentage를 올려도
/// 기존 버킷이 변하지 않아 단조 편입(monotonic enrollment)이 자동 성립한다.
@visibleForTesting
int rolloutBucket(String salt, String seed) {
  final digest = sha256.convert(utf8.encode('$salt:$seed')).toString();
  return int.parse(digest.substring(0, 8), radix: 16) % 100;
}

/// [rolloutBucket] 결과가 [r.percentage] 미만이면 채택(true), 그렇지 않으면 보류(false).
///
/// percentage == 0 이면 항상 false(전면 heldOut = kill switch).
/// percentage == 100 이면 항상 true(전면 채택).
@visibleForTesting
bool rolloutApplies(String salt, RolloutManifest r) {
  return rolloutBucket(salt, r.seed) < r.percentage;
}
