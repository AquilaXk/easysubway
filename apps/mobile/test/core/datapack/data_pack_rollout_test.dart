import 'dart:math';

import 'package:easysubway_mobile/core/datapack/data_pack_manifest.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_updater.dart';
import 'package:flutter_test/flutter_test.dart';

final _rng = Random(42); // 결정론적

String _randomHex32() => List.generate(
  16,
  (_) => _rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

void main() {
  group('rollout 버킷 함수', () {
    test('분포: 1만 salt 샘플에서 percentage 근사(±2%p)', () {
      const seed = 'abcdef0123456789abcdef0123456789';
      for (final pct in [10, 50, 90]) {
        var applied = 0;
        for (var i = 0; i < 10000; i++) {
          final salt = _randomHex32();
          if (rolloutApplies(
            salt,
            RolloutManifest(percentage: pct, seed: seed),
          )) {
            applied++;
          }
        }
        expect(
          (applied / 100.0 - pct).abs(),
          lessThan(2.0),
          reason: 'pct=$pct applied=$applied',
        );
      }
    });

    test('판정 안정성: 같은 salt+seed는 불변', () {
      const seed = 'abcdef0123456789abcdef0123456789';
      const salt = 'deadbeef01234567deadbeef01234567';
      final bucket1 = rolloutBucket(salt, seed);
      final bucket2 = rolloutBucket(salt, seed);
      final bucket3 = rolloutBucket(salt, seed);
      expect(bucket1, equals(bucket2));
      expect(bucket2, equals(bucket3));
      expect(bucket1, inInclusiveRange(0, 99));
    });

    test('단조 편입: 10→50%로 올려도 기존 대상은 유지', () {
      const seed = 'abcdef0123456789abcdef0123456789';
      final salts = List.generate(2000, (_) => _randomHex32());
      final at10 = salts
          .where(
            (s) =>
                rolloutApplies(s, RolloutManifest(percentage: 10, seed: seed)),
          )
          .toSet();
      final at50 = salts
          .where(
            (s) =>
                rolloutApplies(s, RolloutManifest(percentage: 50, seed: seed)),
          )
          .toSet();
      // 10% 대상 ⊆ 50% 대상
      expect(at10.difference(at50), isEmpty);
    });

    test('percentage 0 = 전면 heldOut', () {
      const seed = 'abcdef0123456789abcdef0123456789';
      for (var i = 0; i < 500; i++) {
        final salt = _randomHex32();
        expect(
          rolloutApplies(salt, RolloutManifest(percentage: 0, seed: seed)),
          isFalse,
          reason: 'salt=$salt should be heldOut at percentage=0',
        );
      }
    });

    test('rolloutBucket 반환값은 0~99 범위', () {
      const seed = 'abcdef0123456789abcdef0123456789';
      for (var i = 0; i < 200; i++) {
        final salt = _randomHex32();
        final bucket = rolloutBucket(salt, seed);
        expect(bucket, inInclusiveRange(0, 99));
      }
    });

    test('rolloutApplies: percentage 100 = 전면 채택', () {
      const seed = 'abcdef0123456789abcdef0123456789';
      for (var i = 0; i < 500; i++) {
        final salt = _randomHex32();
        expect(
          rolloutApplies(salt, RolloutManifest(percentage: 100, seed: seed)),
          isTrue,
          reason: 'salt=$salt should be applied at percentage=100',
        );
      }
    });
  });
}
