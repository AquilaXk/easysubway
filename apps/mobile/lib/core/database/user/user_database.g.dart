// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_database.dart';

// ignore_for_file: type=lint
class $FavoriteStationsTable extends FavoriteStations
    with TableInfo<$FavoriteStationsTable, FavoriteStation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FavoriteStationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _stationIdMeta = const VerificationMeta(
    'stationId',
  );
  @override
  late final GeneratedColumn<String> stationId = GeneratedColumn<String>(
    'station_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [stationId, addedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'favorite_stations';
  @override
  VerificationContext validateIntegrity(
    Insertable<FavoriteStation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('station_id')) {
      context.handle(
        _stationIdMeta,
        stationId.isAcceptableOrUnknown(data['station_id']!, _stationIdMeta),
      );
    } else if (isInserting) {
      context.missing(_stationIdMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {stationId};
  @override
  FavoriteStation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FavoriteStation(
      stationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}station_id'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $FavoriteStationsTable createAlias(String alias) {
    return $FavoriteStationsTable(attachedDatabase, alias);
  }
}

class FavoriteStation extends DataClass implements Insertable<FavoriteStation> {
  final String stationId;
  final DateTime addedAt;
  const FavoriteStation({required this.stationId, required this.addedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['station_id'] = Variable<String>(stationId);
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  FavoriteStationsCompanion toCompanion(bool nullToAbsent) {
    return FavoriteStationsCompanion(
      stationId: Value(stationId),
      addedAt: Value(addedAt),
    );
  }

  factory FavoriteStation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FavoriteStation(
      stationId: serializer.fromJson<String>(json['stationId']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'stationId': serializer.toJson<String>(stationId),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  FavoriteStation copyWith({String? stationId, DateTime? addedAt}) =>
      FavoriteStation(
        stationId: stationId ?? this.stationId,
        addedAt: addedAt ?? this.addedAt,
      );
  FavoriteStation copyWithCompanion(FavoriteStationsCompanion data) {
    return FavoriteStation(
      stationId: data.stationId.present ? data.stationId.value : this.stationId,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteStation(')
          ..write('stationId: $stationId, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(stationId, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FavoriteStation &&
          other.stationId == this.stationId &&
          other.addedAt == this.addedAt);
}

class FavoriteStationsCompanion extends UpdateCompanion<FavoriteStation> {
  final Value<String> stationId;
  final Value<DateTime> addedAt;
  final Value<int> rowid;
  const FavoriteStationsCompanion({
    this.stationId = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FavoriteStationsCompanion.insert({
    required String stationId,
    required DateTime addedAt,
    this.rowid = const Value.absent(),
  }) : stationId = Value(stationId),
       addedAt = Value(addedAt);
  static Insertable<FavoriteStation> custom({
    Expression<String>? stationId,
    Expression<DateTime>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (stationId != null) 'station_id': stationId,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FavoriteStationsCompanion copyWith({
    Value<String>? stationId,
    Value<DateTime>? addedAt,
    Value<int>? rowid,
  }) {
    return FavoriteStationsCompanion(
      stationId: stationId ?? this.stationId,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (stationId.present) {
      map['station_id'] = Variable<String>(stationId.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteStationsCompanion(')
          ..write('stationId: $stationId, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FavoriteFacilitiesTable extends FavoriteFacilities
    with TableInfo<$FavoriteFacilitiesTable, FavoriteFacility> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FavoriteFacilitiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _facilityIdMeta = const VerificationMeta(
    'facilityId',
  );
  @override
  late final GeneratedColumn<String> facilityId = GeneratedColumn<String>(
    'facility_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stationIdMeta = const VerificationMeta(
    'stationId',
  );
  @override
  late final GeneratedColumn<String> stationId = GeneratedColumn<String>(
    'station_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [facilityId, stationId, addedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'favorite_facilities';
  @override
  VerificationContext validateIntegrity(
    Insertable<FavoriteFacility> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('facility_id')) {
      context.handle(
        _facilityIdMeta,
        facilityId.isAcceptableOrUnknown(data['facility_id']!, _facilityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_facilityIdMeta);
    }
    if (data.containsKey('station_id')) {
      context.handle(
        _stationIdMeta,
        stationId.isAcceptableOrUnknown(data['station_id']!, _stationIdMeta),
      );
    } else if (isInserting) {
      context.missing(_stationIdMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {facilityId};
  @override
  FavoriteFacility map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FavoriteFacility(
      facilityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}facility_id'],
      )!,
      stationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}station_id'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $FavoriteFacilitiesTable createAlias(String alias) {
    return $FavoriteFacilitiesTable(attachedDatabase, alias);
  }
}

class FavoriteFacility extends DataClass
    implements Insertable<FavoriteFacility> {
  final String facilityId;
  final String stationId;
  final DateTime addedAt;
  const FavoriteFacility({
    required this.facilityId,
    required this.stationId,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['facility_id'] = Variable<String>(facilityId);
    map['station_id'] = Variable<String>(stationId);
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  FavoriteFacilitiesCompanion toCompanion(bool nullToAbsent) {
    return FavoriteFacilitiesCompanion(
      facilityId: Value(facilityId),
      stationId: Value(stationId),
      addedAt: Value(addedAt),
    );
  }

  factory FavoriteFacility.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FavoriteFacility(
      facilityId: serializer.fromJson<String>(json['facilityId']),
      stationId: serializer.fromJson<String>(json['stationId']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'facilityId': serializer.toJson<String>(facilityId),
      'stationId': serializer.toJson<String>(stationId),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  FavoriteFacility copyWith({
    String? facilityId,
    String? stationId,
    DateTime? addedAt,
  }) => FavoriteFacility(
    facilityId: facilityId ?? this.facilityId,
    stationId: stationId ?? this.stationId,
    addedAt: addedAt ?? this.addedAt,
  );
  FavoriteFacility copyWithCompanion(FavoriteFacilitiesCompanion data) {
    return FavoriteFacility(
      facilityId: data.facilityId.present
          ? data.facilityId.value
          : this.facilityId,
      stationId: data.stationId.present ? data.stationId.value : this.stationId,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteFacility(')
          ..write('facilityId: $facilityId, ')
          ..write('stationId: $stationId, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(facilityId, stationId, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FavoriteFacility &&
          other.facilityId == this.facilityId &&
          other.stationId == this.stationId &&
          other.addedAt == this.addedAt);
}

class FavoriteFacilitiesCompanion extends UpdateCompanion<FavoriteFacility> {
  final Value<String> facilityId;
  final Value<String> stationId;
  final Value<DateTime> addedAt;
  final Value<int> rowid;
  const FavoriteFacilitiesCompanion({
    this.facilityId = const Value.absent(),
    this.stationId = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FavoriteFacilitiesCompanion.insert({
    required String facilityId,
    required String stationId,
    required DateTime addedAt,
    this.rowid = const Value.absent(),
  }) : facilityId = Value(facilityId),
       stationId = Value(stationId),
       addedAt = Value(addedAt);
  static Insertable<FavoriteFacility> custom({
    Expression<String>? facilityId,
    Expression<String>? stationId,
    Expression<DateTime>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (facilityId != null) 'facility_id': facilityId,
      if (stationId != null) 'station_id': stationId,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FavoriteFacilitiesCompanion copyWith({
    Value<String>? facilityId,
    Value<String>? stationId,
    Value<DateTime>? addedAt,
    Value<int>? rowid,
  }) {
    return FavoriteFacilitiesCompanion(
      facilityId: facilityId ?? this.facilityId,
      stationId: stationId ?? this.stationId,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (facilityId.present) {
      map['facility_id'] = Variable<String>(facilityId.value);
    }
    if (stationId.present) {
      map['station_id'] = Variable<String>(stationId.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteFacilitiesCompanion(')
          ..write('facilityId: $facilityId, ')
          ..write('stationId: $stationId, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FavoriteRoutesTable extends FavoriteRoutes
    with TableInfo<$FavoriteRoutesTable, FavoriteRoute> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FavoriteRoutesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _routeIdMeta = const VerificationMeta(
    'routeId',
  );
  @override
  late final GeneratedColumn<String> routeId = GeneratedColumn<String>(
    'route_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originStationIdMeta = const VerificationMeta(
    'originStationId',
  );
  @override
  late final GeneratedColumn<String> originStationId = GeneratedColumn<String>(
    'origin_station_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _destinationStationIdMeta =
      const VerificationMeta('destinationStationId');
  @override
  late final GeneratedColumn<String> destinationStationId =
      GeneratedColumn<String>(
        'destination_station_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _mobilityProfileMeta = const VerificationMeta(
    'mobilityProfile',
  );
  @override
  late final GeneratedColumn<String> mobilityProfile = GeneratedColumn<String>(
    'mobility_profile',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    routeId,
    originStationId,
    destinationStationId,
    mobilityProfile,
    addedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'favorite_routes';
  @override
  VerificationContext validateIntegrity(
    Insertable<FavoriteRoute> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('route_id')) {
      context.handle(
        _routeIdMeta,
        routeId.isAcceptableOrUnknown(data['route_id']!, _routeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_routeIdMeta);
    }
    if (data.containsKey('origin_station_id')) {
      context.handle(
        _originStationIdMeta,
        originStationId.isAcceptableOrUnknown(
          data['origin_station_id']!,
          _originStationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originStationIdMeta);
    }
    if (data.containsKey('destination_station_id')) {
      context.handle(
        _destinationStationIdMeta,
        destinationStationId.isAcceptableOrUnknown(
          data['destination_station_id']!,
          _destinationStationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_destinationStationIdMeta);
    }
    if (data.containsKey('mobility_profile')) {
      context.handle(
        _mobilityProfileMeta,
        mobilityProfile.isAcceptableOrUnknown(
          data['mobility_profile']!,
          _mobilityProfileMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_mobilityProfileMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {routeId};
  @override
  FavoriteRoute map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FavoriteRoute(
      routeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}route_id'],
      )!,
      originStationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_station_id'],
      )!,
      destinationStationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}destination_station_id'],
      )!,
      mobilityProfile: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mobility_profile'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $FavoriteRoutesTable createAlias(String alias) {
    return $FavoriteRoutesTable(attachedDatabase, alias);
  }
}

class FavoriteRoute extends DataClass implements Insertable<FavoriteRoute> {
  final String routeId;
  final String originStationId;
  final String destinationStationId;
  final String mobilityProfile;
  final DateTime addedAt;
  const FavoriteRoute({
    required this.routeId,
    required this.originStationId,
    required this.destinationStationId,
    required this.mobilityProfile,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['route_id'] = Variable<String>(routeId);
    map['origin_station_id'] = Variable<String>(originStationId);
    map['destination_station_id'] = Variable<String>(destinationStationId);
    map['mobility_profile'] = Variable<String>(mobilityProfile);
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  FavoriteRoutesCompanion toCompanion(bool nullToAbsent) {
    return FavoriteRoutesCompanion(
      routeId: Value(routeId),
      originStationId: Value(originStationId),
      destinationStationId: Value(destinationStationId),
      mobilityProfile: Value(mobilityProfile),
      addedAt: Value(addedAt),
    );
  }

  factory FavoriteRoute.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FavoriteRoute(
      routeId: serializer.fromJson<String>(json['routeId']),
      originStationId: serializer.fromJson<String>(json['originStationId']),
      destinationStationId: serializer.fromJson<String>(
        json['destinationStationId'],
      ),
      mobilityProfile: serializer.fromJson<String>(json['mobilityProfile']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'routeId': serializer.toJson<String>(routeId),
      'originStationId': serializer.toJson<String>(originStationId),
      'destinationStationId': serializer.toJson<String>(destinationStationId),
      'mobilityProfile': serializer.toJson<String>(mobilityProfile),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  FavoriteRoute copyWith({
    String? routeId,
    String? originStationId,
    String? destinationStationId,
    String? mobilityProfile,
    DateTime? addedAt,
  }) => FavoriteRoute(
    routeId: routeId ?? this.routeId,
    originStationId: originStationId ?? this.originStationId,
    destinationStationId: destinationStationId ?? this.destinationStationId,
    mobilityProfile: mobilityProfile ?? this.mobilityProfile,
    addedAt: addedAt ?? this.addedAt,
  );
  FavoriteRoute copyWithCompanion(FavoriteRoutesCompanion data) {
    return FavoriteRoute(
      routeId: data.routeId.present ? data.routeId.value : this.routeId,
      originStationId: data.originStationId.present
          ? data.originStationId.value
          : this.originStationId,
      destinationStationId: data.destinationStationId.present
          ? data.destinationStationId.value
          : this.destinationStationId,
      mobilityProfile: data.mobilityProfile.present
          ? data.mobilityProfile.value
          : this.mobilityProfile,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteRoute(')
          ..write('routeId: $routeId, ')
          ..write('originStationId: $originStationId, ')
          ..write('destinationStationId: $destinationStationId, ')
          ..write('mobilityProfile: $mobilityProfile, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    routeId,
    originStationId,
    destinationStationId,
    mobilityProfile,
    addedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FavoriteRoute &&
          other.routeId == this.routeId &&
          other.originStationId == this.originStationId &&
          other.destinationStationId == this.destinationStationId &&
          other.mobilityProfile == this.mobilityProfile &&
          other.addedAt == this.addedAt);
}

class FavoriteRoutesCompanion extends UpdateCompanion<FavoriteRoute> {
  final Value<String> routeId;
  final Value<String> originStationId;
  final Value<String> destinationStationId;
  final Value<String> mobilityProfile;
  final Value<DateTime> addedAt;
  final Value<int> rowid;
  const FavoriteRoutesCompanion({
    this.routeId = const Value.absent(),
    this.originStationId = const Value.absent(),
    this.destinationStationId = const Value.absent(),
    this.mobilityProfile = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FavoriteRoutesCompanion.insert({
    required String routeId,
    required String originStationId,
    required String destinationStationId,
    required String mobilityProfile,
    required DateTime addedAt,
    this.rowid = const Value.absent(),
  }) : routeId = Value(routeId),
       originStationId = Value(originStationId),
       destinationStationId = Value(destinationStationId),
       mobilityProfile = Value(mobilityProfile),
       addedAt = Value(addedAt);
  static Insertable<FavoriteRoute> custom({
    Expression<String>? routeId,
    Expression<String>? originStationId,
    Expression<String>? destinationStationId,
    Expression<String>? mobilityProfile,
    Expression<DateTime>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (routeId != null) 'route_id': routeId,
      if (originStationId != null) 'origin_station_id': originStationId,
      if (destinationStationId != null)
        'destination_station_id': destinationStationId,
      if (mobilityProfile != null) 'mobility_profile': mobilityProfile,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FavoriteRoutesCompanion copyWith({
    Value<String>? routeId,
    Value<String>? originStationId,
    Value<String>? destinationStationId,
    Value<String>? mobilityProfile,
    Value<DateTime>? addedAt,
    Value<int>? rowid,
  }) {
    return FavoriteRoutesCompanion(
      routeId: routeId ?? this.routeId,
      originStationId: originStationId ?? this.originStationId,
      destinationStationId: destinationStationId ?? this.destinationStationId,
      mobilityProfile: mobilityProfile ?? this.mobilityProfile,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (routeId.present) {
      map['route_id'] = Variable<String>(routeId.value);
    }
    if (originStationId.present) {
      map['origin_station_id'] = Variable<String>(originStationId.value);
    }
    if (destinationStationId.present) {
      map['destination_station_id'] = Variable<String>(
        destinationStationId.value,
      );
    }
    if (mobilityProfile.present) {
      map['mobility_profile'] = Variable<String>(mobilityProfile.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteRoutesCompanion(')
          ..write('routeId: $routeId, ')
          ..write('originStationId: $originStationId, ')
          ..write('destinationStationId: $destinationStationId, ')
          ..write('mobilityProfile: $mobilityProfile, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SearchHistoryTable extends SearchHistory
    with TableInfo<$SearchHistoryTable, SearchHistoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SearchHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _queryMeta = const VerificationMeta('query');
  @override
  late final GeneratedColumn<String> query = GeneratedColumn<String>(
    'query',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _searchedAtMeta = const VerificationMeta(
    'searchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> searchedAt = GeneratedColumn<DateTime>(
    'searched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, query, searchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'search_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<SearchHistoryData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('query')) {
      context.handle(
        _queryMeta,
        query.isAcceptableOrUnknown(data['query']!, _queryMeta),
      );
    } else if (isInserting) {
      context.missing(_queryMeta);
    }
    if (data.containsKey('searched_at')) {
      context.handle(
        _searchedAtMeta,
        searchedAt.isAcceptableOrUnknown(data['searched_at']!, _searchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_searchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SearchHistoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SearchHistoryData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      query: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}query'],
      )!,
      searchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}searched_at'],
      )!,
    );
  }

  @override
  $SearchHistoryTable createAlias(String alias) {
    return $SearchHistoryTable(attachedDatabase, alias);
  }
}

class SearchHistoryData extends DataClass
    implements Insertable<SearchHistoryData> {
  final int id;
  final String query;
  final DateTime searchedAt;
  const SearchHistoryData({
    required this.id,
    required this.query,
    required this.searchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['query'] = Variable<String>(query);
    map['searched_at'] = Variable<DateTime>(searchedAt);
    return map;
  }

  SearchHistoryCompanion toCompanion(bool nullToAbsent) {
    return SearchHistoryCompanion(
      id: Value(id),
      query: Value(query),
      searchedAt: Value(searchedAt),
    );
  }

  factory SearchHistoryData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SearchHistoryData(
      id: serializer.fromJson<int>(json['id']),
      query: serializer.fromJson<String>(json['query']),
      searchedAt: serializer.fromJson<DateTime>(json['searchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'query': serializer.toJson<String>(query),
      'searchedAt': serializer.toJson<DateTime>(searchedAt),
    };
  }

  SearchHistoryData copyWith({int? id, String? query, DateTime? searchedAt}) =>
      SearchHistoryData(
        id: id ?? this.id,
        query: query ?? this.query,
        searchedAt: searchedAt ?? this.searchedAt,
      );
  SearchHistoryData copyWithCompanion(SearchHistoryCompanion data) {
    return SearchHistoryData(
      id: data.id.present ? data.id.value : this.id,
      query: data.query.present ? data.query.value : this.query,
      searchedAt: data.searchedAt.present
          ? data.searchedAt.value
          : this.searchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SearchHistoryData(')
          ..write('id: $id, ')
          ..write('query: $query, ')
          ..write('searchedAt: $searchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, query, searchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SearchHistoryData &&
          other.id == this.id &&
          other.query == this.query &&
          other.searchedAt == this.searchedAt);
}

class SearchHistoryCompanion extends UpdateCompanion<SearchHistoryData> {
  final Value<int> id;
  final Value<String> query;
  final Value<DateTime> searchedAt;
  const SearchHistoryCompanion({
    this.id = const Value.absent(),
    this.query = const Value.absent(),
    this.searchedAt = const Value.absent(),
  });
  SearchHistoryCompanion.insert({
    this.id = const Value.absent(),
    required String query,
    required DateTime searchedAt,
  }) : query = Value(query),
       searchedAt = Value(searchedAt);
  static Insertable<SearchHistoryData> custom({
    Expression<int>? id,
    Expression<String>? query,
    Expression<DateTime>? searchedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (query != null) 'query': query,
      if (searchedAt != null) 'searched_at': searchedAt,
    });
  }

  SearchHistoryCompanion copyWith({
    Value<int>? id,
    Value<String>? query,
    Value<DateTime>? searchedAt,
  }) {
    return SearchHistoryCompanion(
      id: id ?? this.id,
      query: query ?? this.query,
      searchedAt: searchedAt ?? this.searchedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (query.present) {
      map['query'] = Variable<String>(query.value);
    }
    if (searchedAt.present) {
      map['searched_at'] = Variable<DateTime>(searchedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SearchHistoryCompanion(')
          ..write('id: $id, ')
          ..write('query: $query, ')
          ..write('searchedAt: $searchedAt')
          ..write(')'))
        .toString();
  }
}

class $AppPreferencesTable extends AppPreferences
    with TableInfo<$AppPreferencesTable, AppPreference> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppPreferencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_preferences';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppPreference> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppPreference map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppPreference(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AppPreferencesTable createAlias(String alias) {
    return $AppPreferencesTable(attachedDatabase, alias);
  }
}

class AppPreference extends DataClass implements Insertable<AppPreference> {
  final String key;
  final String value;
  final DateTime updatedAt;
  const AppPreference({
    required this.key,
    required this.value,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AppPreferencesCompanion toCompanion(bool nullToAbsent) {
    return AppPreferencesCompanion(
      key: Value(key),
      value: Value(value),
      updatedAt: Value(updatedAt),
    );
  }

  factory AppPreference.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppPreference(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  AppPreference copyWith({String? key, String? value, DateTime? updatedAt}) =>
      AppPreference(
        key: key ?? this.key,
        value: value ?? this.value,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  AppPreference copyWithCompanion(AppPreferencesCompanion data) {
    return AppPreference(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppPreference(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppPreference &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class AppPreferencesCompanion extends UpdateCompanion<AppPreference> {
  final Value<String> key;
  final Value<String> value;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const AppPreferencesCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppPreferencesCompanion.insert({
    required String key,
    required String value,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value),
       updatedAt = Value(updatedAt);
  static Insertable<AppPreference> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppPreferencesCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return AppPreferencesCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppPreferencesCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $InstalledDataPacksTable extends InstalledDataPacks
    with TableInfo<$InstalledDataPacksTable, InstalledDataPack> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InstalledDataPacksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _packIdMeta = const VerificationMeta('packId');
  @override
  late final GeneratedColumn<String> packId = GeneratedColumn<String>(
    'pack_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<String> version = GeneratedColumn<String>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _installedAtMeta = const VerificationMeta(
    'installedAt',
  );
  @override
  late final GeneratedColumn<DateTime> installedAt = GeneratedColumn<DateTime>(
    'installed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [packId, version, sha256, installedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'installed_data_packs';
  @override
  VerificationContext validateIntegrity(
    Insertable<InstalledDataPack> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('pack_id')) {
      context.handle(
        _packIdMeta,
        packId.isAcceptableOrUnknown(data['pack_id']!, _packIdMeta),
      );
    } else if (isInserting) {
      context.missing(_packIdMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    } else if (isInserting) {
      context.missing(_sha256Meta);
    }
    if (data.containsKey('installed_at')) {
      context.handle(
        _installedAtMeta,
        installedAt.isAcceptableOrUnknown(
          data['installed_at']!,
          _installedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_installedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {packId};
  @override
  InstalledDataPack map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InstalledDataPack(
      packId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pack_id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      )!,
      installedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}installed_at'],
      )!,
    );
  }

  @override
  $InstalledDataPacksTable createAlias(String alias) {
    return $InstalledDataPacksTable(attachedDatabase, alias);
  }
}

class InstalledDataPack extends DataClass
    implements Insertable<InstalledDataPack> {
  final String packId;
  final String version;
  final String sha256;
  final DateTime installedAt;
  const InstalledDataPack({
    required this.packId,
    required this.version,
    required this.sha256,
    required this.installedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['pack_id'] = Variable<String>(packId);
    map['version'] = Variable<String>(version);
    map['sha256'] = Variable<String>(sha256);
    map['installed_at'] = Variable<DateTime>(installedAt);
    return map;
  }

  InstalledDataPacksCompanion toCompanion(bool nullToAbsent) {
    return InstalledDataPacksCompanion(
      packId: Value(packId),
      version: Value(version),
      sha256: Value(sha256),
      installedAt: Value(installedAt),
    );
  }

  factory InstalledDataPack.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InstalledDataPack(
      packId: serializer.fromJson<String>(json['packId']),
      version: serializer.fromJson<String>(json['version']),
      sha256: serializer.fromJson<String>(json['sha256']),
      installedAt: serializer.fromJson<DateTime>(json['installedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'packId': serializer.toJson<String>(packId),
      'version': serializer.toJson<String>(version),
      'sha256': serializer.toJson<String>(sha256),
      'installedAt': serializer.toJson<DateTime>(installedAt),
    };
  }

  InstalledDataPack copyWith({
    String? packId,
    String? version,
    String? sha256,
    DateTime? installedAt,
  }) => InstalledDataPack(
    packId: packId ?? this.packId,
    version: version ?? this.version,
    sha256: sha256 ?? this.sha256,
    installedAt: installedAt ?? this.installedAt,
  );
  InstalledDataPack copyWithCompanion(InstalledDataPacksCompanion data) {
    return InstalledDataPack(
      packId: data.packId.present ? data.packId.value : this.packId,
      version: data.version.present ? data.version.value : this.version,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      installedAt: data.installedAt.present
          ? data.installedAt.value
          : this.installedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InstalledDataPack(')
          ..write('packId: $packId, ')
          ..write('version: $version, ')
          ..write('sha256: $sha256, ')
          ..write('installedAt: $installedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(packId, version, sha256, installedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InstalledDataPack &&
          other.packId == this.packId &&
          other.version == this.version &&
          other.sha256 == this.sha256 &&
          other.installedAt == this.installedAt);
}

class InstalledDataPacksCompanion extends UpdateCompanion<InstalledDataPack> {
  final Value<String> packId;
  final Value<String> version;
  final Value<String> sha256;
  final Value<DateTime> installedAt;
  final Value<int> rowid;
  const InstalledDataPacksCompanion({
    this.packId = const Value.absent(),
    this.version = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.installedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InstalledDataPacksCompanion.insert({
    required String packId,
    required String version,
    required String sha256,
    required DateTime installedAt,
    this.rowid = const Value.absent(),
  }) : packId = Value(packId),
       version = Value(version),
       sha256 = Value(sha256),
       installedAt = Value(installedAt);
  static Insertable<InstalledDataPack> custom({
    Expression<String>? packId,
    Expression<String>? version,
    Expression<String>? sha256,
    Expression<DateTime>? installedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (packId != null) 'pack_id': packId,
      if (version != null) 'version': version,
      if (sha256 != null) 'sha256': sha256,
      if (installedAt != null) 'installed_at': installedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InstalledDataPacksCompanion copyWith({
    Value<String>? packId,
    Value<String>? version,
    Value<String>? sha256,
    Value<DateTime>? installedAt,
    Value<int>? rowid,
  }) {
    return InstalledDataPacksCompanion(
      packId: packId ?? this.packId,
      version: version ?? this.version,
      sha256: sha256 ?? this.sha256,
      installedAt: installedAt ?? this.installedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (packId.present) {
      map['pack_id'] = Variable<String>(packId.value);
    }
    if (version.present) {
      map['version'] = Variable<String>(version.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (installedAt.present) {
      map['installed_at'] = Variable<DateTime>(installedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InstalledDataPacksCompanion(')
          ..write('packId: $packId, ')
          ..write('version: $version, ')
          ..write('sha256: $sha256, ')
          ..write('installedAt: $installedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DataPackUpdateStateTable extends DataPackUpdateState
    with TableInfo<$DataPackUpdateStateTable, DataPackUpdateStateData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DataPackUpdateStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'data_pack_update_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<DataPackUpdateStateData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  DataPackUpdateStateData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DataPackUpdateStateData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $DataPackUpdateStateTable createAlias(String alias) {
    return $DataPackUpdateStateTable(attachedDatabase, alias);
  }
}

class DataPackUpdateStateData extends DataClass
    implements Insertable<DataPackUpdateStateData> {
  final String key;
  final String value;
  final DateTime updatedAt;
  const DataPackUpdateStateData({
    required this.key,
    required this.value,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  DataPackUpdateStateCompanion toCompanion(bool nullToAbsent) {
    return DataPackUpdateStateCompanion(
      key: Value(key),
      value: Value(value),
      updatedAt: Value(updatedAt),
    );
  }

  factory DataPackUpdateStateData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DataPackUpdateStateData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  DataPackUpdateStateData copyWith({
    String? key,
    String? value,
    DateTime? updatedAt,
  }) => DataPackUpdateStateData(
    key: key ?? this.key,
    value: value ?? this.value,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  DataPackUpdateStateData copyWithCompanion(DataPackUpdateStateCompanion data) {
    return DataPackUpdateStateData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DataPackUpdateStateData(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DataPackUpdateStateData &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class DataPackUpdateStateCompanion
    extends UpdateCompanion<DataPackUpdateStateData> {
  final Value<String> key;
  final Value<String> value;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const DataPackUpdateStateCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DataPackUpdateStateCompanion.insert({
    required String key,
    required String value,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value),
       updatedAt = Value(updatedAt);
  static Insertable<DataPackUpdateStateData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DataPackUpdateStateCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return DataPackUpdateStateCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DataPackUpdateStateCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReportReceiptsTable extends ReportReceipts
    with TableInfo<$ReportReceiptsTable, ReportReceipt> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReportReceiptsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _receiptIdMeta = const VerificationMeta(
    'receiptId',
  );
  @override
  late final GeneratedColumn<String> receiptId = GeneratedColumn<String>(
    'receipt_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reportIdMeta = const VerificationMeta(
    'reportId',
  );
  @override
  late final GeneratedColumn<String> reportId = GeneratedColumn<String>(
    'report_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    receiptId,
    reportId,
    status,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'report_receipts';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReportReceipt> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('receipt_id')) {
      context.handle(
        _receiptIdMeta,
        receiptId.isAcceptableOrUnknown(data['receipt_id']!, _receiptIdMeta),
      );
    } else if (isInserting) {
      context.missing(_receiptIdMeta);
    }
    if (data.containsKey('report_id')) {
      context.handle(
        _reportIdMeta,
        reportId.isAcceptableOrUnknown(data['report_id']!, _reportIdMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {receiptId};
  @override
  ReportReceipt map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReportReceipt(
      receiptId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}receipt_id'],
      )!,
      reportId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}report_id'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ReportReceiptsTable createAlias(String alias) {
    return $ReportReceiptsTable(attachedDatabase, alias);
  }
}

class ReportReceipt extends DataClass implements Insertable<ReportReceipt> {
  final String receiptId;
  final String? reportId;
  final String status;
  final DateTime createdAt;
  const ReportReceipt({
    required this.receiptId,
    this.reportId,
    required this.status,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['receipt_id'] = Variable<String>(receiptId);
    if (!nullToAbsent || reportId != null) {
      map['report_id'] = Variable<String>(reportId);
    }
    map['status'] = Variable<String>(status);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ReportReceiptsCompanion toCompanion(bool nullToAbsent) {
    return ReportReceiptsCompanion(
      receiptId: Value(receiptId),
      reportId: reportId == null && nullToAbsent
          ? const Value.absent()
          : Value(reportId),
      status: Value(status),
      createdAt: Value(createdAt),
    );
  }

  factory ReportReceipt.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReportReceipt(
      receiptId: serializer.fromJson<String>(json['receiptId']),
      reportId: serializer.fromJson<String?>(json['reportId']),
      status: serializer.fromJson<String>(json['status']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'receiptId': serializer.toJson<String>(receiptId),
      'reportId': serializer.toJson<String?>(reportId),
      'status': serializer.toJson<String>(status),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ReportReceipt copyWith({
    String? receiptId,
    Value<String?> reportId = const Value.absent(),
    String? status,
    DateTime? createdAt,
  }) => ReportReceipt(
    receiptId: receiptId ?? this.receiptId,
    reportId: reportId.present ? reportId.value : this.reportId,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
  );
  ReportReceipt copyWithCompanion(ReportReceiptsCompanion data) {
    return ReportReceipt(
      receiptId: data.receiptId.present ? data.receiptId.value : this.receiptId,
      reportId: data.reportId.present ? data.reportId.value : this.reportId,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReportReceipt(')
          ..write('receiptId: $receiptId, ')
          ..write('reportId: $reportId, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(receiptId, reportId, status, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReportReceipt &&
          other.receiptId == this.receiptId &&
          other.reportId == this.reportId &&
          other.status == this.status &&
          other.createdAt == this.createdAt);
}

class ReportReceiptsCompanion extends UpdateCompanion<ReportReceipt> {
  final Value<String> receiptId;
  final Value<String?> reportId;
  final Value<String> status;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ReportReceiptsCompanion({
    this.receiptId = const Value.absent(),
    this.reportId = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReportReceiptsCompanion.insert({
    required String receiptId,
    this.reportId = const Value.absent(),
    required String status,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : receiptId = Value(receiptId),
       status = Value(status),
       createdAt = Value(createdAt);
  static Insertable<ReportReceipt> custom({
    Expression<String>? receiptId,
    Expression<String>? reportId,
    Expression<String>? status,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (receiptId != null) 'receipt_id': receiptId,
      if (reportId != null) 'report_id': reportId,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReportReceiptsCompanion copyWith({
    Value<String>? receiptId,
    Value<String?>? reportId,
    Value<String>? status,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return ReportReceiptsCompanion(
      receiptId: receiptId ?? this.receiptId,
      reportId: reportId ?? this.reportId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (receiptId.present) {
      map['receipt_id'] = Variable<String>(receiptId.value);
    }
    if (reportId.present) {
      map['report_id'] = Variable<String>(reportId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReportReceiptsCompanion(')
          ..write('receiptId: $receiptId, ')
          ..write('reportId: $reportId, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReportDraftsTable extends ReportDrafts
    with TableInfo<$ReportDraftsTable, ReportDraft> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReportDraftsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _draftIdMeta = const VerificationMeta(
    'draftId',
  );
  @override
  late final GeneratedColumn<String> draftId = GeneratedColumn<String>(
    'draft_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stationIdMeta = const VerificationMeta(
    'stationId',
  );
  @override
  late final GeneratedColumn<String> stationId = GeneratedColumn<String>(
    'station_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _facilityIdMeta = const VerificationMeta(
    'facilityId',
  );
  @override
  late final GeneratedColumn<String> facilityId = GeneratedColumn<String>(
    'facility_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    draftId,
    stationId,
    facilityId,
    payloadJson,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'report_drafts';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReportDraft> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('draft_id')) {
      context.handle(
        _draftIdMeta,
        draftId.isAcceptableOrUnknown(data['draft_id']!, _draftIdMeta),
      );
    } else if (isInserting) {
      context.missing(_draftIdMeta);
    }
    if (data.containsKey('station_id')) {
      context.handle(
        _stationIdMeta,
        stationId.isAcceptableOrUnknown(data['station_id']!, _stationIdMeta),
      );
    }
    if (data.containsKey('facility_id')) {
      context.handle(
        _facilityIdMeta,
        facilityId.isAcceptableOrUnknown(data['facility_id']!, _facilityIdMeta),
      );
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {draftId};
  @override
  ReportDraft map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReportDraft(
      draftId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}draft_id'],
      )!,
      stationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}station_id'],
      ),
      facilityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}facility_id'],
      ),
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ReportDraftsTable createAlias(String alias) {
    return $ReportDraftsTable(attachedDatabase, alias);
  }
}

class ReportDraft extends DataClass implements Insertable<ReportDraft> {
  final String draftId;
  final String? stationId;
  final String? facilityId;
  final String payloadJson;
  final DateTime updatedAt;
  const ReportDraft({
    required this.draftId,
    this.stationId,
    this.facilityId,
    required this.payloadJson,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['draft_id'] = Variable<String>(draftId);
    if (!nullToAbsent || stationId != null) {
      map['station_id'] = Variable<String>(stationId);
    }
    if (!nullToAbsent || facilityId != null) {
      map['facility_id'] = Variable<String>(facilityId);
    }
    map['payload_json'] = Variable<String>(payloadJson);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ReportDraftsCompanion toCompanion(bool nullToAbsent) {
    return ReportDraftsCompanion(
      draftId: Value(draftId),
      stationId: stationId == null && nullToAbsent
          ? const Value.absent()
          : Value(stationId),
      facilityId: facilityId == null && nullToAbsent
          ? const Value.absent()
          : Value(facilityId),
      payloadJson: Value(payloadJson),
      updatedAt: Value(updatedAt),
    );
  }

  factory ReportDraft.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReportDraft(
      draftId: serializer.fromJson<String>(json['draftId']),
      stationId: serializer.fromJson<String?>(json['stationId']),
      facilityId: serializer.fromJson<String?>(json['facilityId']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'draftId': serializer.toJson<String>(draftId),
      'stationId': serializer.toJson<String?>(stationId),
      'facilityId': serializer.toJson<String?>(facilityId),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ReportDraft copyWith({
    String? draftId,
    Value<String?> stationId = const Value.absent(),
    Value<String?> facilityId = const Value.absent(),
    String? payloadJson,
    DateTime? updatedAt,
  }) => ReportDraft(
    draftId: draftId ?? this.draftId,
    stationId: stationId.present ? stationId.value : this.stationId,
    facilityId: facilityId.present ? facilityId.value : this.facilityId,
    payloadJson: payloadJson ?? this.payloadJson,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ReportDraft copyWithCompanion(ReportDraftsCompanion data) {
    return ReportDraft(
      draftId: data.draftId.present ? data.draftId.value : this.draftId,
      stationId: data.stationId.present ? data.stationId.value : this.stationId,
      facilityId: data.facilityId.present
          ? data.facilityId.value
          : this.facilityId,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReportDraft(')
          ..write('draftId: $draftId, ')
          ..write('stationId: $stationId, ')
          ..write('facilityId: $facilityId, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(draftId, stationId, facilityId, payloadJson, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReportDraft &&
          other.draftId == this.draftId &&
          other.stationId == this.stationId &&
          other.facilityId == this.facilityId &&
          other.payloadJson == this.payloadJson &&
          other.updatedAt == this.updatedAt);
}

class ReportDraftsCompanion extends UpdateCompanion<ReportDraft> {
  final Value<String> draftId;
  final Value<String?> stationId;
  final Value<String?> facilityId;
  final Value<String> payloadJson;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ReportDraftsCompanion({
    this.draftId = const Value.absent(),
    this.stationId = const Value.absent(),
    this.facilityId = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReportDraftsCompanion.insert({
    required String draftId,
    this.stationId = const Value.absent(),
    this.facilityId = const Value.absent(),
    required String payloadJson,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : draftId = Value(draftId),
       payloadJson = Value(payloadJson),
       updatedAt = Value(updatedAt);
  static Insertable<ReportDraft> custom({
    Expression<String>? draftId,
    Expression<String>? stationId,
    Expression<String>? facilityId,
    Expression<String>? payloadJson,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (draftId != null) 'draft_id': draftId,
      if (stationId != null) 'station_id': stationId,
      if (facilityId != null) 'facility_id': facilityId,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReportDraftsCompanion copyWith({
    Value<String>? draftId,
    Value<String?>? stationId,
    Value<String?>? facilityId,
    Value<String>? payloadJson,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ReportDraftsCompanion(
      draftId: draftId ?? this.draftId,
      stationId: stationId ?? this.stationId,
      facilityId: facilityId ?? this.facilityId,
      payloadJson: payloadJson ?? this.payloadJson,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (draftId.present) {
      map['draft_id'] = Variable<String>(draftId.value);
    }
    if (stationId.present) {
      map['station_id'] = Variable<String>(stationId.value);
    }
    if (facilityId.present) {
      map['facility_id'] = Variable<String>(facilityId.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReportDraftsCompanion(')
          ..write('draftId: $draftId, ')
          ..write('stationId: $stationId, ')
          ..write('facilityId: $facilityId, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$UserDatabase extends GeneratedDatabase {
  _$UserDatabase(QueryExecutor e) : super(e);
  $UserDatabaseManager get managers => $UserDatabaseManager(this);
  late final $FavoriteStationsTable favoriteStations = $FavoriteStationsTable(
    this,
  );
  late final $FavoriteFacilitiesTable favoriteFacilities =
      $FavoriteFacilitiesTable(this);
  late final $FavoriteRoutesTable favoriteRoutes = $FavoriteRoutesTable(this);
  late final $SearchHistoryTable searchHistory = $SearchHistoryTable(this);
  late final $AppPreferencesTable appPreferences = $AppPreferencesTable(this);
  late final $InstalledDataPacksTable installedDataPacks =
      $InstalledDataPacksTable(this);
  late final $DataPackUpdateStateTable dataPackUpdateState =
      $DataPackUpdateStateTable(this);
  late final $ReportReceiptsTable reportReceipts = $ReportReceiptsTable(this);
  late final $ReportDraftsTable reportDrafts = $ReportDraftsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    favoriteStations,
    favoriteFacilities,
    favoriteRoutes,
    searchHistory,
    appPreferences,
    installedDataPacks,
    dataPackUpdateState,
    reportReceipts,
    reportDrafts,
  ];
}

typedef $$FavoriteStationsTableCreateCompanionBuilder =
    FavoriteStationsCompanion Function({
      required String stationId,
      required DateTime addedAt,
      Value<int> rowid,
    });
typedef $$FavoriteStationsTableUpdateCompanionBuilder =
    FavoriteStationsCompanion Function({
      Value<String> stationId,
      Value<DateTime> addedAt,
      Value<int> rowid,
    });

class $$FavoriteStationsTableFilterComposer
    extends Composer<_$UserDatabase, $FavoriteStationsTable> {
  $$FavoriteStationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get stationId => $composableBuilder(
    column: $table.stationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FavoriteStationsTableOrderingComposer
    extends Composer<_$UserDatabase, $FavoriteStationsTable> {
  $$FavoriteStationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get stationId => $composableBuilder(
    column: $table.stationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FavoriteStationsTableAnnotationComposer
    extends Composer<_$UserDatabase, $FavoriteStationsTable> {
  $$FavoriteStationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get stationId =>
      $composableBuilder(column: $table.stationId, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$FavoriteStationsTableTableManager
    extends
        RootTableManager<
          _$UserDatabase,
          $FavoriteStationsTable,
          FavoriteStation,
          $$FavoriteStationsTableFilterComposer,
          $$FavoriteStationsTableOrderingComposer,
          $$FavoriteStationsTableAnnotationComposer,
          $$FavoriteStationsTableCreateCompanionBuilder,
          $$FavoriteStationsTableUpdateCompanionBuilder,
          (
            FavoriteStation,
            BaseReferences<
              _$UserDatabase,
              $FavoriteStationsTable,
              FavoriteStation
            >,
          ),
          FavoriteStation,
          PrefetchHooks Function()
        > {
  $$FavoriteStationsTableTableManager(
    _$UserDatabase db,
    $FavoriteStationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FavoriteStationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FavoriteStationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FavoriteStationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> stationId = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FavoriteStationsCompanion(
                stationId: stationId,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String stationId,
                required DateTime addedAt,
                Value<int> rowid = const Value.absent(),
              }) => FavoriteStationsCompanion.insert(
                stationId: stationId,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FavoriteStationsTableProcessedTableManager =
    ProcessedTableManager<
      _$UserDatabase,
      $FavoriteStationsTable,
      FavoriteStation,
      $$FavoriteStationsTableFilterComposer,
      $$FavoriteStationsTableOrderingComposer,
      $$FavoriteStationsTableAnnotationComposer,
      $$FavoriteStationsTableCreateCompanionBuilder,
      $$FavoriteStationsTableUpdateCompanionBuilder,
      (
        FavoriteStation,
        BaseReferences<_$UserDatabase, $FavoriteStationsTable, FavoriteStation>,
      ),
      FavoriteStation,
      PrefetchHooks Function()
    >;
typedef $$FavoriteFacilitiesTableCreateCompanionBuilder =
    FavoriteFacilitiesCompanion Function({
      required String facilityId,
      required String stationId,
      required DateTime addedAt,
      Value<int> rowid,
    });
typedef $$FavoriteFacilitiesTableUpdateCompanionBuilder =
    FavoriteFacilitiesCompanion Function({
      Value<String> facilityId,
      Value<String> stationId,
      Value<DateTime> addedAt,
      Value<int> rowid,
    });

class $$FavoriteFacilitiesTableFilterComposer
    extends Composer<_$UserDatabase, $FavoriteFacilitiesTable> {
  $$FavoriteFacilitiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get facilityId => $composableBuilder(
    column: $table.facilityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stationId => $composableBuilder(
    column: $table.stationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FavoriteFacilitiesTableOrderingComposer
    extends Composer<_$UserDatabase, $FavoriteFacilitiesTable> {
  $$FavoriteFacilitiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get facilityId => $composableBuilder(
    column: $table.facilityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stationId => $composableBuilder(
    column: $table.stationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FavoriteFacilitiesTableAnnotationComposer
    extends Composer<_$UserDatabase, $FavoriteFacilitiesTable> {
  $$FavoriteFacilitiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get facilityId => $composableBuilder(
    column: $table.facilityId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get stationId =>
      $composableBuilder(column: $table.stationId, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$FavoriteFacilitiesTableTableManager
    extends
        RootTableManager<
          _$UserDatabase,
          $FavoriteFacilitiesTable,
          FavoriteFacility,
          $$FavoriteFacilitiesTableFilterComposer,
          $$FavoriteFacilitiesTableOrderingComposer,
          $$FavoriteFacilitiesTableAnnotationComposer,
          $$FavoriteFacilitiesTableCreateCompanionBuilder,
          $$FavoriteFacilitiesTableUpdateCompanionBuilder,
          (
            FavoriteFacility,
            BaseReferences<
              _$UserDatabase,
              $FavoriteFacilitiesTable,
              FavoriteFacility
            >,
          ),
          FavoriteFacility,
          PrefetchHooks Function()
        > {
  $$FavoriteFacilitiesTableTableManager(
    _$UserDatabase db,
    $FavoriteFacilitiesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FavoriteFacilitiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FavoriteFacilitiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FavoriteFacilitiesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> facilityId = const Value.absent(),
                Value<String> stationId = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FavoriteFacilitiesCompanion(
                facilityId: facilityId,
                stationId: stationId,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String facilityId,
                required String stationId,
                required DateTime addedAt,
                Value<int> rowid = const Value.absent(),
              }) => FavoriteFacilitiesCompanion.insert(
                facilityId: facilityId,
                stationId: stationId,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FavoriteFacilitiesTableProcessedTableManager =
    ProcessedTableManager<
      _$UserDatabase,
      $FavoriteFacilitiesTable,
      FavoriteFacility,
      $$FavoriteFacilitiesTableFilterComposer,
      $$FavoriteFacilitiesTableOrderingComposer,
      $$FavoriteFacilitiesTableAnnotationComposer,
      $$FavoriteFacilitiesTableCreateCompanionBuilder,
      $$FavoriteFacilitiesTableUpdateCompanionBuilder,
      (
        FavoriteFacility,
        BaseReferences<
          _$UserDatabase,
          $FavoriteFacilitiesTable,
          FavoriteFacility
        >,
      ),
      FavoriteFacility,
      PrefetchHooks Function()
    >;
typedef $$FavoriteRoutesTableCreateCompanionBuilder =
    FavoriteRoutesCompanion Function({
      required String routeId,
      required String originStationId,
      required String destinationStationId,
      required String mobilityProfile,
      required DateTime addedAt,
      Value<int> rowid,
    });
typedef $$FavoriteRoutesTableUpdateCompanionBuilder =
    FavoriteRoutesCompanion Function({
      Value<String> routeId,
      Value<String> originStationId,
      Value<String> destinationStationId,
      Value<String> mobilityProfile,
      Value<DateTime> addedAt,
      Value<int> rowid,
    });

class $$FavoriteRoutesTableFilterComposer
    extends Composer<_$UserDatabase, $FavoriteRoutesTable> {
  $$FavoriteRoutesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get routeId => $composableBuilder(
    column: $table.routeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originStationId => $composableBuilder(
    column: $table.originStationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get destinationStationId => $composableBuilder(
    column: $table.destinationStationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mobilityProfile => $composableBuilder(
    column: $table.mobilityProfile,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FavoriteRoutesTableOrderingComposer
    extends Composer<_$UserDatabase, $FavoriteRoutesTable> {
  $$FavoriteRoutesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get routeId => $composableBuilder(
    column: $table.routeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originStationId => $composableBuilder(
    column: $table.originStationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get destinationStationId => $composableBuilder(
    column: $table.destinationStationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mobilityProfile => $composableBuilder(
    column: $table.mobilityProfile,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FavoriteRoutesTableAnnotationComposer
    extends Composer<_$UserDatabase, $FavoriteRoutesTable> {
  $$FavoriteRoutesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get routeId =>
      $composableBuilder(column: $table.routeId, builder: (column) => column);

  GeneratedColumn<String> get originStationId => $composableBuilder(
    column: $table.originStationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get destinationStationId => $composableBuilder(
    column: $table.destinationStationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mobilityProfile => $composableBuilder(
    column: $table.mobilityProfile,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$FavoriteRoutesTableTableManager
    extends
        RootTableManager<
          _$UserDatabase,
          $FavoriteRoutesTable,
          FavoriteRoute,
          $$FavoriteRoutesTableFilterComposer,
          $$FavoriteRoutesTableOrderingComposer,
          $$FavoriteRoutesTableAnnotationComposer,
          $$FavoriteRoutesTableCreateCompanionBuilder,
          $$FavoriteRoutesTableUpdateCompanionBuilder,
          (
            FavoriteRoute,
            BaseReferences<_$UserDatabase, $FavoriteRoutesTable, FavoriteRoute>,
          ),
          FavoriteRoute,
          PrefetchHooks Function()
        > {
  $$FavoriteRoutesTableTableManager(
    _$UserDatabase db,
    $FavoriteRoutesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FavoriteRoutesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FavoriteRoutesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FavoriteRoutesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> routeId = const Value.absent(),
                Value<String> originStationId = const Value.absent(),
                Value<String> destinationStationId = const Value.absent(),
                Value<String> mobilityProfile = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FavoriteRoutesCompanion(
                routeId: routeId,
                originStationId: originStationId,
                destinationStationId: destinationStationId,
                mobilityProfile: mobilityProfile,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String routeId,
                required String originStationId,
                required String destinationStationId,
                required String mobilityProfile,
                required DateTime addedAt,
                Value<int> rowid = const Value.absent(),
              }) => FavoriteRoutesCompanion.insert(
                routeId: routeId,
                originStationId: originStationId,
                destinationStationId: destinationStationId,
                mobilityProfile: mobilityProfile,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FavoriteRoutesTableProcessedTableManager =
    ProcessedTableManager<
      _$UserDatabase,
      $FavoriteRoutesTable,
      FavoriteRoute,
      $$FavoriteRoutesTableFilterComposer,
      $$FavoriteRoutesTableOrderingComposer,
      $$FavoriteRoutesTableAnnotationComposer,
      $$FavoriteRoutesTableCreateCompanionBuilder,
      $$FavoriteRoutesTableUpdateCompanionBuilder,
      (
        FavoriteRoute,
        BaseReferences<_$UserDatabase, $FavoriteRoutesTable, FavoriteRoute>,
      ),
      FavoriteRoute,
      PrefetchHooks Function()
    >;
typedef $$SearchHistoryTableCreateCompanionBuilder =
    SearchHistoryCompanion Function({
      Value<int> id,
      required String query,
      required DateTime searchedAt,
    });
typedef $$SearchHistoryTableUpdateCompanionBuilder =
    SearchHistoryCompanion Function({
      Value<int> id,
      Value<String> query,
      Value<DateTime> searchedAt,
    });

class $$SearchHistoryTableFilterComposer
    extends Composer<_$UserDatabase, $SearchHistoryTable> {
  $$SearchHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get query => $composableBuilder(
    column: $table.query,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get searchedAt => $composableBuilder(
    column: $table.searchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SearchHistoryTableOrderingComposer
    extends Composer<_$UserDatabase, $SearchHistoryTable> {
  $$SearchHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get query => $composableBuilder(
    column: $table.query,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get searchedAt => $composableBuilder(
    column: $table.searchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SearchHistoryTableAnnotationComposer
    extends Composer<_$UserDatabase, $SearchHistoryTable> {
  $$SearchHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get query =>
      $composableBuilder(column: $table.query, builder: (column) => column);

  GeneratedColumn<DateTime> get searchedAt => $composableBuilder(
    column: $table.searchedAt,
    builder: (column) => column,
  );
}

class $$SearchHistoryTableTableManager
    extends
        RootTableManager<
          _$UserDatabase,
          $SearchHistoryTable,
          SearchHistoryData,
          $$SearchHistoryTableFilterComposer,
          $$SearchHistoryTableOrderingComposer,
          $$SearchHistoryTableAnnotationComposer,
          $$SearchHistoryTableCreateCompanionBuilder,
          $$SearchHistoryTableUpdateCompanionBuilder,
          (
            SearchHistoryData,
            BaseReferences<
              _$UserDatabase,
              $SearchHistoryTable,
              SearchHistoryData
            >,
          ),
          SearchHistoryData,
          PrefetchHooks Function()
        > {
  $$SearchHistoryTableTableManager(_$UserDatabase db, $SearchHistoryTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SearchHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SearchHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SearchHistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> query = const Value.absent(),
                Value<DateTime> searchedAt = const Value.absent(),
              }) => SearchHistoryCompanion(
                id: id,
                query: query,
                searchedAt: searchedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String query,
                required DateTime searchedAt,
              }) => SearchHistoryCompanion.insert(
                id: id,
                query: query,
                searchedAt: searchedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SearchHistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$UserDatabase,
      $SearchHistoryTable,
      SearchHistoryData,
      $$SearchHistoryTableFilterComposer,
      $$SearchHistoryTableOrderingComposer,
      $$SearchHistoryTableAnnotationComposer,
      $$SearchHistoryTableCreateCompanionBuilder,
      $$SearchHistoryTableUpdateCompanionBuilder,
      (
        SearchHistoryData,
        BaseReferences<_$UserDatabase, $SearchHistoryTable, SearchHistoryData>,
      ),
      SearchHistoryData,
      PrefetchHooks Function()
    >;
typedef $$AppPreferencesTableCreateCompanionBuilder =
    AppPreferencesCompanion Function({
      required String key,
      required String value,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$AppPreferencesTableUpdateCompanionBuilder =
    AppPreferencesCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$AppPreferencesTableFilterComposer
    extends Composer<_$UserDatabase, $AppPreferencesTable> {
  $$AppPreferencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppPreferencesTableOrderingComposer
    extends Composer<_$UserDatabase, $AppPreferencesTable> {
  $$AppPreferencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppPreferencesTableAnnotationComposer
    extends Composer<_$UserDatabase, $AppPreferencesTable> {
  $$AppPreferencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AppPreferencesTableTableManager
    extends
        RootTableManager<
          _$UserDatabase,
          $AppPreferencesTable,
          AppPreference,
          $$AppPreferencesTableFilterComposer,
          $$AppPreferencesTableOrderingComposer,
          $$AppPreferencesTableAnnotationComposer,
          $$AppPreferencesTableCreateCompanionBuilder,
          $$AppPreferencesTableUpdateCompanionBuilder,
          (
            AppPreference,
            BaseReferences<_$UserDatabase, $AppPreferencesTable, AppPreference>,
          ),
          AppPreference,
          PrefetchHooks Function()
        > {
  $$AppPreferencesTableTableManager(
    _$UserDatabase db,
    $AppPreferencesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppPreferencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppPreferencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppPreferencesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppPreferencesCompanion(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => AppPreferencesCompanion.insert(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppPreferencesTableProcessedTableManager =
    ProcessedTableManager<
      _$UserDatabase,
      $AppPreferencesTable,
      AppPreference,
      $$AppPreferencesTableFilterComposer,
      $$AppPreferencesTableOrderingComposer,
      $$AppPreferencesTableAnnotationComposer,
      $$AppPreferencesTableCreateCompanionBuilder,
      $$AppPreferencesTableUpdateCompanionBuilder,
      (
        AppPreference,
        BaseReferences<_$UserDatabase, $AppPreferencesTable, AppPreference>,
      ),
      AppPreference,
      PrefetchHooks Function()
    >;
typedef $$InstalledDataPacksTableCreateCompanionBuilder =
    InstalledDataPacksCompanion Function({
      required String packId,
      required String version,
      required String sha256,
      required DateTime installedAt,
      Value<int> rowid,
    });
typedef $$InstalledDataPacksTableUpdateCompanionBuilder =
    InstalledDataPacksCompanion Function({
      Value<String> packId,
      Value<String> version,
      Value<String> sha256,
      Value<DateTime> installedAt,
      Value<int> rowid,
    });

class $$InstalledDataPacksTableFilterComposer
    extends Composer<_$UserDatabase, $InstalledDataPacksTable> {
  $$InstalledDataPacksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get packId => $composableBuilder(
    column: $table.packId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$InstalledDataPacksTableOrderingComposer
    extends Composer<_$UserDatabase, $InstalledDataPacksTable> {
  $$InstalledDataPacksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get packId => $composableBuilder(
    column: $table.packId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$InstalledDataPacksTableAnnotationComposer
    extends Composer<_$UserDatabase, $InstalledDataPacksTable> {
  $$InstalledDataPacksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get packId =>
      $composableBuilder(column: $table.packId, builder: (column) => column);

  GeneratedColumn<String> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<DateTime> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => column,
  );
}

class $$InstalledDataPacksTableTableManager
    extends
        RootTableManager<
          _$UserDatabase,
          $InstalledDataPacksTable,
          InstalledDataPack,
          $$InstalledDataPacksTableFilterComposer,
          $$InstalledDataPacksTableOrderingComposer,
          $$InstalledDataPacksTableAnnotationComposer,
          $$InstalledDataPacksTableCreateCompanionBuilder,
          $$InstalledDataPacksTableUpdateCompanionBuilder,
          (
            InstalledDataPack,
            BaseReferences<
              _$UserDatabase,
              $InstalledDataPacksTable,
              InstalledDataPack
            >,
          ),
          InstalledDataPack,
          PrefetchHooks Function()
        > {
  $$InstalledDataPacksTableTableManager(
    _$UserDatabase db,
    $InstalledDataPacksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InstalledDataPacksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InstalledDataPacksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InstalledDataPacksTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> packId = const Value.absent(),
                Value<String> version = const Value.absent(),
                Value<String> sha256 = const Value.absent(),
                Value<DateTime> installedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InstalledDataPacksCompanion(
                packId: packId,
                version: version,
                sha256: sha256,
                installedAt: installedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String packId,
                required String version,
                required String sha256,
                required DateTime installedAt,
                Value<int> rowid = const Value.absent(),
              }) => InstalledDataPacksCompanion.insert(
                packId: packId,
                version: version,
                sha256: sha256,
                installedAt: installedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$InstalledDataPacksTableProcessedTableManager =
    ProcessedTableManager<
      _$UserDatabase,
      $InstalledDataPacksTable,
      InstalledDataPack,
      $$InstalledDataPacksTableFilterComposer,
      $$InstalledDataPacksTableOrderingComposer,
      $$InstalledDataPacksTableAnnotationComposer,
      $$InstalledDataPacksTableCreateCompanionBuilder,
      $$InstalledDataPacksTableUpdateCompanionBuilder,
      (
        InstalledDataPack,
        BaseReferences<
          _$UserDatabase,
          $InstalledDataPacksTable,
          InstalledDataPack
        >,
      ),
      InstalledDataPack,
      PrefetchHooks Function()
    >;
typedef $$DataPackUpdateStateTableCreateCompanionBuilder =
    DataPackUpdateStateCompanion Function({
      required String key,
      required String value,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$DataPackUpdateStateTableUpdateCompanionBuilder =
    DataPackUpdateStateCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$DataPackUpdateStateTableFilterComposer
    extends Composer<_$UserDatabase, $DataPackUpdateStateTable> {
  $$DataPackUpdateStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DataPackUpdateStateTableOrderingComposer
    extends Composer<_$UserDatabase, $DataPackUpdateStateTable> {
  $$DataPackUpdateStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DataPackUpdateStateTableAnnotationComposer
    extends Composer<_$UserDatabase, $DataPackUpdateStateTable> {
  $$DataPackUpdateStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$DataPackUpdateStateTableTableManager
    extends
        RootTableManager<
          _$UserDatabase,
          $DataPackUpdateStateTable,
          DataPackUpdateStateData,
          $$DataPackUpdateStateTableFilterComposer,
          $$DataPackUpdateStateTableOrderingComposer,
          $$DataPackUpdateStateTableAnnotationComposer,
          $$DataPackUpdateStateTableCreateCompanionBuilder,
          $$DataPackUpdateStateTableUpdateCompanionBuilder,
          (
            DataPackUpdateStateData,
            BaseReferences<
              _$UserDatabase,
              $DataPackUpdateStateTable,
              DataPackUpdateStateData
            >,
          ),
          DataPackUpdateStateData,
          PrefetchHooks Function()
        > {
  $$DataPackUpdateStateTableTableManager(
    _$UserDatabase db,
    $DataPackUpdateStateTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DataPackUpdateStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DataPackUpdateStateTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$DataPackUpdateStateTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DataPackUpdateStateCompanion(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => DataPackUpdateStateCompanion.insert(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DataPackUpdateStateTableProcessedTableManager =
    ProcessedTableManager<
      _$UserDatabase,
      $DataPackUpdateStateTable,
      DataPackUpdateStateData,
      $$DataPackUpdateStateTableFilterComposer,
      $$DataPackUpdateStateTableOrderingComposer,
      $$DataPackUpdateStateTableAnnotationComposer,
      $$DataPackUpdateStateTableCreateCompanionBuilder,
      $$DataPackUpdateStateTableUpdateCompanionBuilder,
      (
        DataPackUpdateStateData,
        BaseReferences<
          _$UserDatabase,
          $DataPackUpdateStateTable,
          DataPackUpdateStateData
        >,
      ),
      DataPackUpdateStateData,
      PrefetchHooks Function()
    >;
typedef $$ReportReceiptsTableCreateCompanionBuilder =
    ReportReceiptsCompanion Function({
      required String receiptId,
      Value<String?> reportId,
      required String status,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$ReportReceiptsTableUpdateCompanionBuilder =
    ReportReceiptsCompanion Function({
      Value<String> receiptId,
      Value<String?> reportId,
      Value<String> status,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$ReportReceiptsTableFilterComposer
    extends Composer<_$UserDatabase, $ReportReceiptsTable> {
  $$ReportReceiptsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get receiptId => $composableBuilder(
    column: $table.receiptId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reportId => $composableBuilder(
    column: $table.reportId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReportReceiptsTableOrderingComposer
    extends Composer<_$UserDatabase, $ReportReceiptsTable> {
  $$ReportReceiptsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get receiptId => $composableBuilder(
    column: $table.receiptId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reportId => $composableBuilder(
    column: $table.reportId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReportReceiptsTableAnnotationComposer
    extends Composer<_$UserDatabase, $ReportReceiptsTable> {
  $$ReportReceiptsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get receiptId =>
      $composableBuilder(column: $table.receiptId, builder: (column) => column);

  GeneratedColumn<String> get reportId =>
      $composableBuilder(column: $table.reportId, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ReportReceiptsTableTableManager
    extends
        RootTableManager<
          _$UserDatabase,
          $ReportReceiptsTable,
          ReportReceipt,
          $$ReportReceiptsTableFilterComposer,
          $$ReportReceiptsTableOrderingComposer,
          $$ReportReceiptsTableAnnotationComposer,
          $$ReportReceiptsTableCreateCompanionBuilder,
          $$ReportReceiptsTableUpdateCompanionBuilder,
          (
            ReportReceipt,
            BaseReferences<_$UserDatabase, $ReportReceiptsTable, ReportReceipt>,
          ),
          ReportReceipt,
          PrefetchHooks Function()
        > {
  $$ReportReceiptsTableTableManager(
    _$UserDatabase db,
    $ReportReceiptsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReportReceiptsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReportReceiptsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReportReceiptsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> receiptId = const Value.absent(),
                Value<String?> reportId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReportReceiptsCompanion(
                receiptId: receiptId,
                reportId: reportId,
                status: status,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String receiptId,
                Value<String?> reportId = const Value.absent(),
                required String status,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => ReportReceiptsCompanion.insert(
                receiptId: receiptId,
                reportId: reportId,
                status: status,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReportReceiptsTableProcessedTableManager =
    ProcessedTableManager<
      _$UserDatabase,
      $ReportReceiptsTable,
      ReportReceipt,
      $$ReportReceiptsTableFilterComposer,
      $$ReportReceiptsTableOrderingComposer,
      $$ReportReceiptsTableAnnotationComposer,
      $$ReportReceiptsTableCreateCompanionBuilder,
      $$ReportReceiptsTableUpdateCompanionBuilder,
      (
        ReportReceipt,
        BaseReferences<_$UserDatabase, $ReportReceiptsTable, ReportReceipt>,
      ),
      ReportReceipt,
      PrefetchHooks Function()
    >;
typedef $$ReportDraftsTableCreateCompanionBuilder =
    ReportDraftsCompanion Function({
      required String draftId,
      Value<String?> stationId,
      Value<String?> facilityId,
      required String payloadJson,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ReportDraftsTableUpdateCompanionBuilder =
    ReportDraftsCompanion Function({
      Value<String> draftId,
      Value<String?> stationId,
      Value<String?> facilityId,
      Value<String> payloadJson,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$ReportDraftsTableFilterComposer
    extends Composer<_$UserDatabase, $ReportDraftsTable> {
  $$ReportDraftsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get draftId => $composableBuilder(
    column: $table.draftId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stationId => $composableBuilder(
    column: $table.stationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get facilityId => $composableBuilder(
    column: $table.facilityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReportDraftsTableOrderingComposer
    extends Composer<_$UserDatabase, $ReportDraftsTable> {
  $$ReportDraftsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get draftId => $composableBuilder(
    column: $table.draftId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stationId => $composableBuilder(
    column: $table.stationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get facilityId => $composableBuilder(
    column: $table.facilityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReportDraftsTableAnnotationComposer
    extends Composer<_$UserDatabase, $ReportDraftsTable> {
  $$ReportDraftsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get draftId =>
      $composableBuilder(column: $table.draftId, builder: (column) => column);

  GeneratedColumn<String> get stationId =>
      $composableBuilder(column: $table.stationId, builder: (column) => column);

  GeneratedColumn<String> get facilityId => $composableBuilder(
    column: $table.facilityId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ReportDraftsTableTableManager
    extends
        RootTableManager<
          _$UserDatabase,
          $ReportDraftsTable,
          ReportDraft,
          $$ReportDraftsTableFilterComposer,
          $$ReportDraftsTableOrderingComposer,
          $$ReportDraftsTableAnnotationComposer,
          $$ReportDraftsTableCreateCompanionBuilder,
          $$ReportDraftsTableUpdateCompanionBuilder,
          (
            ReportDraft,
            BaseReferences<_$UserDatabase, $ReportDraftsTable, ReportDraft>,
          ),
          ReportDraft,
          PrefetchHooks Function()
        > {
  $$ReportDraftsTableTableManager(_$UserDatabase db, $ReportDraftsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReportDraftsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReportDraftsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReportDraftsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> draftId = const Value.absent(),
                Value<String?> stationId = const Value.absent(),
                Value<String?> facilityId = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReportDraftsCompanion(
                draftId: draftId,
                stationId: stationId,
                facilityId: facilityId,
                payloadJson: payloadJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String draftId,
                Value<String?> stationId = const Value.absent(),
                Value<String?> facilityId = const Value.absent(),
                required String payloadJson,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ReportDraftsCompanion.insert(
                draftId: draftId,
                stationId: stationId,
                facilityId: facilityId,
                payloadJson: payloadJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReportDraftsTableProcessedTableManager =
    ProcessedTableManager<
      _$UserDatabase,
      $ReportDraftsTable,
      ReportDraft,
      $$ReportDraftsTableFilterComposer,
      $$ReportDraftsTableOrderingComposer,
      $$ReportDraftsTableAnnotationComposer,
      $$ReportDraftsTableCreateCompanionBuilder,
      $$ReportDraftsTableUpdateCompanionBuilder,
      (
        ReportDraft,
        BaseReferences<_$UserDatabase, $ReportDraftsTable, ReportDraft>,
      ),
      ReportDraft,
      PrefetchHooks Function()
    >;

class $UserDatabaseManager {
  final _$UserDatabase _db;
  $UserDatabaseManager(this._db);
  $$FavoriteStationsTableTableManager get favoriteStations =>
      $$FavoriteStationsTableTableManager(_db, _db.favoriteStations);
  $$FavoriteFacilitiesTableTableManager get favoriteFacilities =>
      $$FavoriteFacilitiesTableTableManager(_db, _db.favoriteFacilities);
  $$FavoriteRoutesTableTableManager get favoriteRoutes =>
      $$FavoriteRoutesTableTableManager(_db, _db.favoriteRoutes);
  $$SearchHistoryTableTableManager get searchHistory =>
      $$SearchHistoryTableTableManager(_db, _db.searchHistory);
  $$AppPreferencesTableTableManager get appPreferences =>
      $$AppPreferencesTableTableManager(_db, _db.appPreferences);
  $$InstalledDataPacksTableTableManager get installedDataPacks =>
      $$InstalledDataPacksTableTableManager(_db, _db.installedDataPacks);
  $$DataPackUpdateStateTableTableManager get dataPackUpdateState =>
      $$DataPackUpdateStateTableTableManager(_db, _db.dataPackUpdateState);
  $$ReportReceiptsTableTableManager get reportReceipts =>
      $$ReportReceiptsTableTableManager(_db, _db.reportReceipts);
  $$ReportDraftsTableTableManager get reportDrafts =>
      $$ReportDraftsTableTableManager(_db, _db.reportDrafts);
}
