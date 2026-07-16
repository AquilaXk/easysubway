import 'dart:convert' show jsonDecode;
import 'dart:io';
import 'dart:ui' show Offset;

import 'package:easysubway_mobile/features/network_map/domain/structured_route_map.dart';
import 'package:easysubway_mobile/features/network_map/presentation/structured_route_map_painter.dart'
    show routeMapLineBadgeLabel, routeMapStationLabel;
import 'package:sqlite3/sqlite3.dart';

/// capital 팩(assets/datapacks/capital.sqlite.gz)을 직접 열어 프로덕션과 같은
/// buildStructuredRouteMap 입력으로 실데이터 노선도를 만든다 — 실데이터 계약
/// 테스트(#1789 스펙 R3) 전용. flutter test의 CWD는 apps/mobile이다.
class CapitalRouteMapFixture {
  const CapitalRouteMapFixture({
    required this.map,
    required this.labelTextByStationId,
    required this.stationNameByStationId,
    required this.badgeLabelByLineId,
    required this.lineColorHexById,
  });

  final StructuredRouteMap map;
  final Map<String, String> labelTextByStationId;

  /// stationId → 축약 전 원본 nameKo(#2068 6차 오너 라벨 sidecar 매칭 키).
  final Map<String, String> stationNameByStationId;
  final Map<String, String> badgeLabelByLineId;

  /// line_id → hex 색(`lines.color`). 렌더링(golden) 테스트가 프로덕션과 같은
  /// 노선색으로 그리도록 노출한다.
  final Map<String, String> lineColorHexById;
}

/// [packAssetPath]는 flutter test CWD(apps/mobile) 기준 상대 경로다. 기본값은
/// 커밋된 capital 팩이고, S0 스파이크 golden은 route-map-defs의 스파이크 팩을
/// 리포 루트 상대(`../../tools/...`)로 넘겨 재사용한다.
CapitalRouteMapFixture loadCapitalRouteMapFixture({
  String region = '수도권',
  String packAssetPath = 'assets/datapacks/capital.sqlite.gz',
}) {
  final gzBytes = File(packAssetPath).readAsBytesSync();
  final dir = Directory.systemTemp.createTempSync('capital-pack-');
  try {
    final sqliteFile = File('${dir.path}/pack.sqlite')
      ..writeAsBytesSync(gzip.decode(gzBytes));
    final db = sqlite3.open(sqliteFile.path);
    try {
      final stationRows = db.select(
        '''
        SELECT p.station_id, p.line_id, p.x, p.y, p.label_polygon,
               sl.line_sequence, s.name_ko
        FROM route_map_positions p
        JOIN station_lines sl
          ON sl.station_id = p.station_id AND sl.line_id = p.line_id
        JOIN stations s ON s.id = p.station_id
        WHERE p.region = ?
        ORDER BY p.line_id, sl.line_sequence, p.station_id
      ''',
        [region],
      );
      final trackRows = db.select(
        'SELECT line_id, path FROM route_map_line_tracks '
        'WHERE region = ? ORDER BY line_id, track_index',
        [region],
      );
      final lineRows = db.select('SELECT id, name_ko, color FROM lines');

      final labelText = <String, String>{};
      final stationName = <String, String>{};
      final inputs = <StructuredRouteMapStationInput>[];
      for (final row in stationRows) {
        final stationId = row['station_id'] as String;
        final nameKo = row['name_ko'] as String;
        labelText[stationId] = routeMapStationLabel(nameKo);
        stationName[stationId] = nameKo;
        inputs.add(
          StructuredRouteMapStationInput(
            stationId: stationId,
            lineId: row['line_id'] as String,
            sequence: row['line_sequence'] as int,
            position: Offset(
              (row['x'] as num).toDouble(),
              (row['y'] as num).toDouble(),
            ),
            labelPolygon:
                _parseLabelPolygon(row['label_polygon'] as String? ?? '') ??
                const [],
          ),
        );
      }
      final pathsByLine = <String, List<String>>{};
      for (final row in trackRows) {
        pathsByLine
            .putIfAbsent(row['line_id'] as String, () => [])
            .add(row['path'] as String);
      }
      final map = buildStructuredRouteMap(
        inputs,
        lineTracks: [
          for (final entry in pathsByLine.entries)
            RouteMapLineTrackInput(lineId: entry.key, paths: entry.value),
        ],
      );
      final lineIdsInMap = {for (final line in map.lines) line.lineId};
      final badgeLabel = <String, String>{
        for (final row in lineRows)
          if (lineIdsInMap.contains(row['id'] as String))
            row['id'] as String: routeMapLineBadgeLabel(
              row['name_ko'] as String,
            ),
      };
      final lineColorHex = <String, String>{
        for (final row in lineRows)
          if (lineIdsInMap.contains(row['id'] as String) &&
              row['color'] != null)
            row['id'] as String: row['color'] as String,
      };
      return CapitalRouteMapFixture(
        map: map,
        labelTextByStationId: labelText,
        stationNameByStationId: stationName,
        badgeLabelByLineId: badgeLabel,
        lineColorHexById: lineColorHex,
      );
    } finally {
      db.close();
    }
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// network_map.dart의 프로덕션 `_parseLabelPolygon`과 동일한 파싱 규칙(#2068
/// 5차) — 픽스처가 프로덕션과 같은 오너 라벨 폴리곤을 얻도록 미러링한다. 그
/// 함수는 private이라 여기서 재사용할 수 없어 로직만 복제한다.
List<Offset>? _parseLabelPolygon(String value) {
  if (value.trim().isEmpty) {
    return null;
  }
  try {
    final decoded = jsonDecode(value);
    if (decoded is! List || decoded.length < 3) {
      return null;
    }
    final points = <Offset>[];
    for (final rawPoint in decoded) {
      if (rawPoint is! Map) {
        return null;
      }
      final x = rawPoint['x'];
      final y = rawPoint['y'];
      if (x is! num || y is! num) {
        return null;
      }
      final dx = x.toDouble();
      final dy = y.toDouble();
      if (!dx.isFinite || !dy.isFinite || dx < 0 || dy < 0) {
        return null;
      }
      points.add(Offset(dx, dy));
    }
    return points;
  } on FormatException {
    return null;
  }
}
