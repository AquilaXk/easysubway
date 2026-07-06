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
    required this.badgeLabelByLineId,
  });

  final StructuredRouteMap map;
  final Map<String, String> labelTextByStationId;
  final Map<String, String> badgeLabelByLineId;
}

CapitalRouteMapFixture loadCapitalRouteMapFixture({String region = '수도권'}) {
  final gzBytes = File('assets/datapacks/capital.sqlite.gz').readAsBytesSync();
  final dir = Directory.systemTemp.createTempSync('capital-pack-');
  try {
    final sqliteFile = File('${dir.path}/pack.sqlite')
      ..writeAsBytesSync(gzip.decode(gzBytes));
    final db = sqlite3.open(sqliteFile.path);
    try {
      final stationRows = db.select('''
        SELECT p.station_id, p.line_id, p.x, p.y, sl.line_sequence, s.name_ko
        FROM route_map_positions p
        JOIN station_lines sl
          ON sl.station_id = p.station_id AND sl.line_id = p.line_id
        JOIN stations s ON s.id = p.station_id
        WHERE p.region = ?
        ORDER BY p.line_id, sl.line_sequence, p.station_id
      ''', [region]);
      final trackRows = db.select(
        'SELECT line_id, path FROM route_map_line_tracks '
        'WHERE region = ? ORDER BY line_id, track_index',
        [region],
      );
      final lineRows = db.select('SELECT id, name_ko FROM lines');

      final labelText = <String, String>{};
      final inputs = <StructuredRouteMapStationInput>[];
      for (final row in stationRows) {
        final stationId = row['station_id'] as String;
        labelText[stationId] = routeMapStationLabel(row['name_ko'] as String);
        inputs.add(
          StructuredRouteMapStationInput(
            stationId: stationId,
            lineId: row['line_id'] as String,
            sequence: row['line_sequence'] as int,
            position: Offset(
              (row['x'] as num).toDouble(),
              (row['y'] as num).toDouble(),
            ),
            labelPolygon: const [],
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
      return CapitalRouteMapFixture(
        map: map,
        labelTextByStationId: labelText,
        badgeLabelByLineId: badgeLabel,
      );
    } finally {
      db.close();
    }
  } finally {
    dir.deleteSync(recursive: true);
  }
}
