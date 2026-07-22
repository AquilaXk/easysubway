import 'package:drift/drift.dart';

class FavoriteStations extends Table {
  @override
  String get tableName => 'favorite_stations';

  TextColumn get stationId => text().named('station_id')();

  /// 호선 단위 즐겨찾기. 빈 문자열은 레거시(역 전체) 즐겨찾기다.
  TextColumn get lineId =>
      text().named('line_id').withDefault(const Constant(''))();
  DateTimeColumn get addedAt => dateTime().named('added_at')();

  @override
  Set<Column> get primaryKey => {stationId, lineId};
}

class FavoriteFacilities extends Table {
  @override
  String get tableName => 'favorite_facilities';

  TextColumn get facilityId => text().named('facility_id')();
  TextColumn get stationId => text().named('station_id')();
  DateTimeColumn get addedAt => dateTime().named('added_at')();

  @override
  Set<Column> get primaryKey => {facilityId};
}

class FavoriteRoutes extends Table {
  @override
  String get tableName => 'favorite_routes';

  TextColumn get routeId => text().named('route_id')();
  TextColumn get originStationId => text().named('origin_station_id')();
  TextColumn get destinationStationId =>
      text().named('destination_station_id')();
  TextColumn get mobilityProfile => text().named('mobility_profile')();
  DateTimeColumn get addedAt => dateTime().named('added_at')();

  @override
  Set<Column> get primaryKey => {routeId};
}

class SearchHistory extends Table {
  @override
  String get tableName => 'search_history';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get query => text()();

  /// 검색 당시 선택 지역(예: `수도권`, `부산`). 지역별 최근 목록 필터에 쓴다.
  /// 지역 정보 없이 저장된 레거시 행은 null이며, 지역 필터 목록에서 제외한다.
  TextColumn get region => text().nullable()();
  DateTimeColumn get searchedAt => dateTime().named('searched_at')();
}

class RouteSearchHistory extends Table {
  @override
  String get tableName => 'route_search_history';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get originStationId => text().named('origin_station_id')();
  TextColumn get originStationName => text().named('origin_station_name')();
  TextColumn get waypointStationId =>
      text().named('waypoint_station_id').nullable()();
  TextColumn get waypointStationName =>
      text().named('waypoint_station_name').nullable()();
  TextColumn get destinationStationId =>
      text().named('destination_station_id')();
  TextColumn get destinationStationName =>
      text().named('destination_station_name')();
  TextColumn get region => text()();
  DateTimeColumn get searchedAt => dateTime().named('searched_at')();
}

class AppPreferences extends Table {
  @override
  String get tableName => 'app_preferences';

  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime().named('updated_at')();

  @override
  Set<Column> get primaryKey => {key};
}

class InstalledDataPacks extends Table {
  @override
  String get tableName => 'installed_data_packs';

  TextColumn get packId => text().named('pack_id')();
  TextColumn get version => text()();
  TextColumn get sha256 => text()();
  DateTimeColumn get installedAt => dateTime().named('installed_at')();

  @override
  Set<Column> get primaryKey => {packId};
}

class DataPackUpdateState extends Table {
  @override
  String get tableName => 'data_pack_update_state';

  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime().named('updated_at')();

  @override
  Set<Column> get primaryKey => {key};
}

class ReportReceipts extends Table {
  @override
  String get tableName => 'report_receipts';

  TextColumn get receiptId => text().named('receipt_id')();
  TextColumn get reportId => text().named('report_id').nullable()();
  TextColumn get publicReceiptCode =>
      text().named('public_receipt_code').nullable()();
  TextColumn get status => text()();
  DateTimeColumn get createdAt => dateTime().named('created_at')();

  @override
  Set<Column> get primaryKey => {receiptId};
}

class ReportDrafts extends Table {
  @override
  String get tableName => 'report_drafts';

  TextColumn get draftId => text().named('draft_id')();
  TextColumn get stationId => text().named('station_id').nullable()();
  TextColumn get facilityId => text().named('facility_id').nullable()();
  TextColumn get payloadJson => text().named('payload_json')();
  DateTimeColumn get updatedAt => dateTime().named('updated_at')();

  @override
  Set<Column> get primaryKey => {draftId};
}
