import 'package:drift/drift.dart';

class CatalogMetadata extends Table {
  @override
  String get tableName => 'catalog_metadata';

  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}

class Operators extends Table {
  @override
  String get tableName => 'operators';

  TextColumn get id => text()();
  TextColumn get nameKo => text().named('name_ko')();
  TextColumn get nameEn =>
      text().named('name_en').withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class Lines extends Table {
  @override
  String get tableName => 'lines';

  TextColumn get id => text()();
  TextColumn get operatorId => text().named('operator_id')();
  TextColumn get nameKo => text().named('name_ko')();
  TextColumn get nameEn =>
      text().named('name_en').withDefault(const Constant(''))();
  TextColumn get color => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class Stations extends Table {
  @override
  String get tableName => 'stations';

  TextColumn get id => text()();
  TextColumn get nameKo => text().named('name_ko')();
  TextColumn get nameEn =>
      text().named('name_en').withDefault(const Constant(''))();
  TextColumn get normalizedName => text().named('normalized_name')();
  TextColumn get region => text().withDefault(const Constant(''))();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  TextColumn get dataQualityLevel => text()
      .named('data_quality_level')
      .withDefault(const Constant('LEVEL_1'))();
  TextColumn get dataSourceType => text()
      .named('data_source_type')
      .withDefault(const Constant('OFFICIAL_FILE'))();
  DateTimeColumn get lastVerifiedAt =>
      dateTime().named('last_verified_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class StationAliases extends Table {
  @override
  String get tableName => 'station_aliases';

  TextColumn get stationId => text().named('station_id')();
  TextColumn get alias => text()();
  TextColumn get normalizedAlias => text().named('normalized_alias')();
}

class StationLines extends Table {
  @override
  String get tableName => 'station_lines';

  TextColumn get stationId => text().named('station_id')();
  TextColumn get lineId => text().named('line_id')();
  TextColumn get stationCode =>
      text().named('station_code').withDefault(const Constant(''))();
  IntColumn get lineSequence => integer().named('line_sequence')();
  TextColumn get platformInfo =>
      text().named('platform_info').withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {stationId, lineId};
}

class NetworkEdges extends Table {
  @override
  String get tableName => 'network_edges';

  TextColumn get id => text()();
  TextColumn get fromNodeId => text().named('from_node_id')();
  TextColumn get toNodeId => text().named('to_node_id')();
  IntColumn get durationSeconds =>
      integer().named('duration_seconds').withDefault(const Constant(0))();
  IntColumn get distanceMeters =>
      integer().named('distance_meters').withDefault(const Constant(0))();
  TextColumn get edgeType =>
      text().named('edge_type').withDefault(const Constant('WALK'))();
  TextColumn get servicePattern =>
      text().named('service_pattern').withDefault(const Constant(''))();
  BoolColumn get includesStairs =>
      boolean().named('includes_stairs').withDefault(const Constant(false))();
  TextColumn get stairAccessState => text()
      .named('stair_access_state')
      .withDefault(const Constant('UNKNOWN'))();
  TextColumn get accessibilityStatus => text()
      .named('accessibility_status')
      .withDefault(const Constant('UNKNOWN'))();
  IntColumn get reliabilityScore =>
      integer().named('reliability_score').withDefault(const Constant(100))();
  TextColumn get facilityId => text().named('facility_id').nullable()();
  DateTimeColumn get lastVerifiedAt =>
      dateTime().named('last_verified_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class StationExits extends Table {
  @override
  String get tableName => 'station_exits';

  TextColumn get id => text()();
  TextColumn get stationId => text().named('station_id')();
  TextColumn get exitNumber => text().named('exit_number')();
  TextColumn get description => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class Facilities extends Table {
  @override
  String get tableName => 'facilities';

  TextColumn get id => text()();
  TextColumn get stationId => text().named('station_id')();
  TextColumn get exitId => text().named('exit_id').nullable()();
  TextColumn get type => text()();
  TextColumn get name => text()();
  TextColumn get status => text().withDefault(const Constant('NORMAL'))();
  TextColumn get floorFrom =>
      text().named('floor_from').withDefault(const Constant(''))();
  TextColumn get floorTo =>
      text().named('floor_to').withDefault(const Constant(''))();
  TextColumn get description => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class StationAccessibilitySummaries extends Table {
  @override
  String get tableName => 'station_accessibility_summaries';

  TextColumn get stationId => text().named('station_id')();
  TextColumn get summary => text()();
  TextColumn get warning => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {stationId};
}

class InternalRouteNodes extends Table {
  @override
  String get tableName => 'internal_route_nodes';

  TextColumn get id => text()();
  TextColumn get stationId => text().named('station_id')();
  TextColumn get label => text()();
  TextColumn get nodeType => text().named('node_type')();

  @override
  Set<Column> get primaryKey => {id};
}

class InternalRouteEdges extends Table {
  @override
  String get tableName => 'internal_route_edges';

  TextColumn get id => text()();
  TextColumn get fromNodeId => text().named('from_node_id')();
  TextColumn get toNodeId => text().named('to_node_id')();
  TextColumn get edgeType =>
      text().named('edge_type').withDefault(const Constant('WALK'))();
  IntColumn get distanceMeters =>
      integer().named('distance_meters').withDefault(const Constant(0))();
  IntColumn get durationSeconds =>
      integer().named('duration_seconds').withDefault(const Constant(0))();
  BoolColumn get includesStairs =>
      boolean().named('includes_stairs').withDefault(const Constant(false))();
  BoolColumn get requiresElevator =>
      boolean().named('requires_elevator').withDefault(const Constant(false))();
  BoolColumn get requiresEscalator => boolean()
      .named('requires_escalator')
      .withDefault(const Constant(false))();
  IntColumn get slopeLevel =>
      integer().named('slope_level').withDefault(const Constant(1))();
  IntColumn get widthLevel =>
      integer().named('width_level').withDefault(const Constant(2))();
  IntColumn get reliabilityScore =>
      integer().named('reliability_score').withDefault(const Constant(100))();
  TextColumn get accessibilityStatus => text()
      .named('accessibility_status')
      .withDefault(const Constant('UNKNOWN'))();
  TextColumn get instruction => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class DataQualityRecords extends Table {
  @override
  String get tableName => 'data_quality_records';

  TextColumn get id => text()();
  TextColumn get targetType => text().named('target_type')();
  TextColumn get targetId => text().named('target_id')();
  TextColumn get qualityLevel => text().named('quality_level')();
  DateTimeColumn get checkedAt => dateTime().named('checked_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
