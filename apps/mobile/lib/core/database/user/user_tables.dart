import 'package:drift/drift.dart';

class FavoriteStations extends Table {
  @override
  String get tableName => 'favorite_stations';

  TextColumn get stationId => text().named('station_id')();
  DateTimeColumn get addedAt => dateTime().named('added_at')();

  @override
  Set<Column> get primaryKey => {stationId};
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
