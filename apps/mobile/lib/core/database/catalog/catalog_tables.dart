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

class ServiceCalendars extends Table {
  @override
  String get tableName => 'service_calendars';

  TextColumn get serviceId => text().named('service_id')();
  BoolColumn get monday => boolean()();
  BoolColumn get tuesday => boolean()();
  BoolColumn get wednesday => boolean()();
  BoolColumn get thursday => boolean()();
  BoolColumn get friday => boolean()();
  BoolColumn get saturday => boolean()();
  BoolColumn get sunday => boolean()();
  TextColumn get startDate => text().named('start_date')();
  TextColumn get endDate => text().named('end_date')();
  TextColumn get timezone => text().withDefault(const Constant('Asia/Seoul'))();

  @override
  Set<Column> get primaryKey => {serviceId};
}

class ServiceCalendarDates extends Table {
  @override
  String get tableName => 'service_calendar_dates';

  TextColumn get serviceId => text().named('service_id')();
  TextColumn get date => text()();
  IntColumn get exceptionType => integer().named('exception_type')();

  @override
  Set<Column> get primaryKey => {serviceId, date};

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (service_id) REFERENCES service_calendars(service_id)',
  ];
}

class TransitRoutes extends Table {
  @override
  String get tableName => 'transit_routes';

  TextColumn get id => text()();
  TextColumn get lineId => text().named('line_id')();
  TextColumn get routeShortName =>
      text().named('route_short_name').withDefault(const Constant(''))();
  TextColumn get routeLongName =>
      text().named('route_long_name').withDefault(const Constant(''))();
  TextColumn get directionName =>
      text().named('direction_name').withDefault(const Constant(''))();
  TextColumn get timezone => text().withDefault(const Constant('Asia/Seoul'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (line_id) REFERENCES lines(id)',
  ];
}

class TransitTrips extends Table {
  @override
  String get tableName => 'transit_trips';

  TextColumn get id => text()();
  TextColumn get routeId => text().named('route_id')();
  TextColumn get serviceId => text().named('service_id')();
  TextColumn get tripHeadsign =>
      text().named('trip_headsign').withDefault(const Constant(''))();
  TextColumn get directionId =>
      text().named('direction_id').withDefault(const Constant(''))();
  TextColumn get servicePattern =>
      text().named('service_pattern').withDefault(const Constant('LOCAL'))();
  IntColumn get serviceDayStartSeconds => integer()
      .named('service_day_start_seconds')
      .withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (route_id) REFERENCES transit_routes(id)',
    'FOREIGN KEY (service_id) REFERENCES service_calendars(service_id)',
  ];
}

class TransitStopTimes extends Table {
  @override
  String get tableName => 'transit_stop_times';

  TextColumn get tripId => text().named('trip_id')();
  IntColumn get stopSequence => integer().named('stop_sequence')();
  TextColumn get stationId => text().named('station_id')();
  TextColumn get lineId => text().named('line_id')();
  IntColumn get arrivalSeconds => integer().named('arrival_seconds')();
  IntColumn get departureSeconds => integer().named('departure_seconds')();
  IntColumn get pickupType =>
      integer().named('pickup_type').withDefault(const Constant(0))();
  IntColumn get dropOffType =>
      integer().named('drop_off_type').withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {tripId, stopSequence};

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (trip_id) REFERENCES transit_trips(id)',
    'FOREIGN KEY (station_id, line_id) REFERENCES station_lines(station_id, line_id)',
  ];
}

class TransitFrequencies extends Table {
  @override
  String get tableName => 'transit_frequencies';

  TextColumn get tripId => text().named('trip_id')();
  IntColumn get startTimeSeconds => integer().named('start_time_seconds')();
  IntColumn get endTimeSeconds => integer().named('end_time_seconds')();
  IntColumn get headwaySeconds => integer().named('headway_seconds')();
  BoolColumn get exactTimes =>
      boolean().named('exact_times').withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {tripId, startTimeSeconds};

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (trip_id) REFERENCES transit_trips(id)',
  ];
}

class RealtimeProviderLineMappings extends Table {
  @override
  String get tableName => 'realtime_provider_line_mappings';

  TextColumn get providerId => text().named('provider_id')();
  TextColumn get providerLineId => text().named('provider_line_id')();
  TextColumn get lineId => text().named('line_id')();
  TextColumn get sourceId => text().named('source_id')();
  BoolColumn get supportsArrivals =>
      boolean().named('supports_arrivals').withDefault(const Constant(false))();
  BoolColumn get supportsTrainPositions => boolean()
      .named('supports_train_positions')
      .withDefault(const Constant(false))();
  TextColumn get mappingConfidence => text()
      .named('mapping_confidence')
      .withDefault(const Constant('UNKNOWN'))();
  DateTimeColumn get updatedAt => dateTime().named('updated_at').nullable()();

  @override
  Set<Column> get primaryKey => {providerId, providerLineId};

  @override
  List<Set<Column>> get uniqueKeys => [
    {providerId, lineId},
    {providerId, providerLineId, lineId},
  ];

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (line_id) REFERENCES lines(id)',
  ];
}

class RealtimeProviderStationMappings extends Table {
  @override
  String get tableName => 'realtime_provider_station_mappings';

  TextColumn get providerId => text().named('provider_id')();
  TextColumn get providerLineId => text().named('provider_line_id')();
  TextColumn get providerStationId => text().named('provider_station_id')();
  TextColumn get stationId => text().named('station_id')();
  TextColumn get lineId => text().named('line_id')();
  TextColumn get sourceId => text().named('source_id')();
  TextColumn get queryName =>
      text().named('query_name').withDefault(const Constant(''))();
  BoolColumn get supportsArrivals =>
      boolean().named('supports_arrivals').withDefault(const Constant(false))();
  BoolColumn get supportsTrainPositions => boolean()
      .named('supports_train_positions')
      .withDefault(const Constant(false))();
  TextColumn get mappingConfidence => text()
      .named('mapping_confidence')
      .withDefault(const Constant('UNKNOWN'))();
  DateTimeColumn get updatedAt => dateTime().named('updated_at').nullable()();

  @override
  Set<Column> get primaryKey => {providerId, providerLineId, providerStationId};

  @override
  List<Set<Column>> get uniqueKeys => [
    {providerId, lineId, stationId},
  ];

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (provider_id, provider_line_id, line_id) REFERENCES realtime_provider_line_mappings(provider_id, provider_line_id, line_id)',
    'FOREIGN KEY (station_id, line_id) REFERENCES station_lines(station_id, line_id)',
  ];
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
  TextColumn get sourceId =>
      text().named('source_id').withDefault(const Constant(''))();
  TextColumn get sourceSnapshotId =>
      text().named('source_snapshot_id').withDefault(const Constant(''))();
  TextColumn get providerRecordHash =>
      text().named('provider_record_hash').withDefault(const Constant(''))();
  TextColumn get provenanceKind =>
      text().named('provenance_kind').withDefault(const Constant('UNKNOWN'))();
  TextColumn get verificationStatus => text()
      .named('verification_status')
      .withDefault(const Constant('UNKNOWN'))();
  TextColumn get facilityId => text().named('facility_id').nullable()();
  DateTimeColumn get lastVerifiedAt =>
      dateTime().named('last_verified_at').nullable()();
  TextColumn get evidenceHash =>
      text().named('evidence_hash').withDefault(const Constant(''))();

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
  TextColumn get status => text().withDefault(const Constant('UNKNOWN'))();
  TextColumn get floorFrom =>
      text().named('floor_from').withDefault(const Constant(''))();
  TextColumn get floorTo =>
      text().named('floor_to').withDefault(const Constant(''))();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get sourceId =>
      text().named('source_id').withDefault(const Constant(''))();
  TextColumn get sourceSnapshotId =>
      text().named('source_snapshot_id').withDefault(const Constant(''))();
  TextColumn get providerFacilityRef =>
      text().named('provider_facility_ref').withDefault(const Constant(''))();
  TextColumn get providerRecordHash =>
      text().named('provider_record_hash').withDefault(const Constant(''))();
  TextColumn get provenanceKind =>
      text().named('provenance_kind').withDefault(const Constant('UNKNOWN'))();
  DateTimeColumn get verifiedAt => dateTime().named('verified_at').nullable()();
  DateTimeColumn get retrievedAt =>
      dateTime().named('retrieved_at').nullable()();
  TextColumn get evidenceHash =>
      text().named('evidence_hash').withDefault(const Constant(''))();
  TextColumn get statusMeaning =>
      text().named('status_meaning').withDefault(const Constant(''))();
  TextColumn get operationalStatus =>
      text().named('operational_status').withDefault(const Constant(''))();
  TextColumn get installationStatus =>
      text().named('installation_status').withDefault(const Constant(''))();
  IntColumn get confidence =>
      integer().named('confidence').withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class StationFacilityEvidence extends Table {
  @override
  String get tableName => 'station_facility_evidence';

  TextColumn get stationId => text().named('station_id')();
  TextColumn get lineId => text().named('line_id')();
  TextColumn get facilityType => text().named('facility_type')();
  TextColumn get evidenceKind => text().named('evidence_kind')();
  TextColumn get sourceId => text().named('source_id')();
  TextColumn get sourceSnapshotId => text().named('source_snapshot_id')();
  TextColumn get providerRecordHash => text().named('provider_record_hash')();
  TextColumn get evidenceHash => text().named('evidence_hash')();
  TextColumn get provenanceKind => text().named('provenance_kind')();
  TextColumn get installationStatus => text()
      .named('installation_status')
      .withDefault(const Constant('UNKNOWN'))();
  TextColumn get operationalStatus => text()
      .named('operational_status')
      .withDefault(const Constant('UNKNOWN'))();
  TextColumn get statusMeaning =>
      text().named('status_meaning').withDefault(const Constant(''))();
  IntColumn get confidence =>
      integer().named('confidence').withDefault(const Constant(0))();
  DateTimeColumn get verifiedAt => dateTime().named('verified_at').nullable()();
  DateTimeColumn get retrievedAt =>
      dateTime().named('retrieved_at').nullable()();
  BoolColumn get strictRouteEligible => boolean()
      .named('strict_route_eligible')
      .withDefault(const Constant(false))();
  TextColumn get strictRouteEligibleReason => text()
      .named('strict_route_eligible_reason')
      .withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {stationId, lineId, facilityType};
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
  TextColumn get sourceId =>
      text().named('source_id').withDefault(const Constant(''))();
  TextColumn get sourceSnapshotId =>
      text().named('source_snapshot_id').withDefault(const Constant(''))();
  TextColumn get providerRecordHash =>
      text().named('provider_record_hash').withDefault(const Constant(''))();
  TextColumn get provenanceKind =>
      text().named('provenance_kind').withDefault(const Constant('UNKNOWN'))();
  TextColumn get verificationStatus => text()
      .named('verification_status')
      .withDefault(const Constant('UNKNOWN'))();
  TextColumn get facilityId => text().named('facility_id').nullable()();
  DateTimeColumn get lastVerifiedAt =>
      dateTime().named('last_verified_at').nullable()();
  TextColumn get evidenceHash =>
      text().named('evidence_hash').withDefault(const Constant(''))();
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
