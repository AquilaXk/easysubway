import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('station_car_door_hints runtime schema가 범위와 참조 무결성을 강제한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);

    final row = await database
        .customSelect(
          "SELECT sql FROM sqlite_schema WHERE type = 'table' AND name = 'station_car_door_hints'",
        )
        .getSingle();
    final sql = row.read<String>('sql');

    expect(sql, contains('CHECK (car_number >= 1 AND car_number <= 10)'));
    expect(sql, contains('CHECK (door_number >= 1 AND door_number <= 4)'));
    expect(
      sql,
      contains(
        "CHECK (target_facility_type IN ('STAIR', 'ELEVATOR', 'ESCALATOR', 'TRANSFER'))",
      ),
    );
    expect(
      sql,
      contains(
        'FOREIGN KEY (station_id, line_id) REFERENCES station_lines(station_id, line_id)',
      ),
    );
  });
}
