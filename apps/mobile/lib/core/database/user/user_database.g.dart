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
  static const VerificationMeta _lineIdMeta = const VerificationMeta('lineId');
  @override
  late final GeneratedColumn<String> lineId = GeneratedColumn<String>(
    'line_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
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
  List<GeneratedColumn> get $columns => [stationId, lineId, addedAt];
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
    if (data.containsKey('line_id')) {
      context.handle(
        _lineIdMeta,
        lineId.isAcceptableOrUnknown(data['line_id']!, _lineIdMeta),
      );
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
  Set<GeneratedColumn> get $primaryKey => {stationId, lineId};
  @override
  FavoriteStation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FavoriteStation(
      stationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}station_id'],
      )!,
      lineId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}line_id'],
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

  /// 호선 단위 즐겨찾기. 빈 문자열은 레거시(역 전체) 즐겨찾기다.
  final String lineId;
  final DateTime addedAt;
  const FavoriteStation({
    required this.stationId,
    required this.lineId,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['station_id'] = Variable<String>(stationId);
    map['line_id'] = Variable<String>(lineId);
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  FavoriteStationsCompanion toCompanion(bool nullToAbsent) {
    return FavoriteStationsCompanion(
      stationId: Value(stationId),
      lineId: Value(lineId),
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
      lineId: serializer.fromJson<String>(json['lineId']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'stationId': serializer.toJson<String>(stationId),
      'lineId': serializer.toJson<String>(lineId),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  FavoriteStation copyWith({
    String? stationId,
    String? lineId,
    DateTime? addedAt,
  }) => FavoriteStation(
    stationId: stationId ?? this.stationId,
    lineId: lineId ?? this.lineId,
    addedAt: addedAt ?? this.addedAt,
  );
  FavoriteStation copyWithCompanion(FavoriteStationsCompanion data) {
    return FavoriteStation(
      stationId: data.stationId.present ? data.stationId.value : this.stationId,
      lineId: data.lineId.present ? data.lineId.value : this.lineId,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteStation(')
          ..write('stationId: $stationId, ')
          ..write('lineId: $lineId, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(stationId, lineId, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FavoriteStation &&
          other.stationId == this.stationId &&
          other.lineId == this.lineId &&
          other.addedAt == this.addedAt);
}

class FavoriteStationsCompanion extends UpdateCompanion<FavoriteStation> {
  final Value<String> stationId;
  final Value<String> lineId;
  final Value<DateTime> addedAt;
  final Value<int> rowid;
  const FavoriteStationsCompanion({
    this.stationId = const Value.absent(),
    this.lineId = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FavoriteStationsCompanion.insert({
    required String stationId,
    this.lineId = const Value.absent(),
    required DateTime addedAt,
    this.rowid = const Value.absent(),
  }) : stationId = Value(stationId),
       addedAt = Value(addedAt);
  static Insertable<FavoriteStation> custom({
    Expression<String>? stationId,
    Expression<String>? lineId,
    Expression<DateTime>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (stationId != null) 'station_id': stationId,
      if (lineId != null) 'line_id': lineId,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FavoriteStationsCompanion copyWith({
    Value<String>? stationId,
    Value<String>? lineId,
    Value<DateTime>? addedAt,
    Value<int>? rowid,
  }) {
    return FavoriteStationsCompanion(
      stationId: stationId ?? this.stationId,
      lineId: lineId ?? this.lineId,
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
    if (lineId.present) {
      map['line_id'] = Variable<String>(lineId.value);
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
          ..write('lineId: $lineId, ')
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
  static const VerificationMeta _regionMeta = const VerificationMeta('region');
  @override
  late final GeneratedColumn<String> region = GeneratedColumn<String>(
    'region',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  static const VerificationMeta _lineIdMeta = const VerificationMeta('lineId');
  @override
  late final GeneratedColumn<String> lineId = GeneratedColumn<String>(
    'line_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lineNameMeta = const VerificationMeta(
    'lineName',
  );
  @override
  late final GeneratedColumn<String> lineName = GeneratedColumn<String>(
    'line_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lineColorMeta = const VerificationMeta(
    'lineColor',
  );
  @override
  late final GeneratedColumn<String> lineColor = GeneratedColumn<String>(
    'line_color',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stationCodeMeta = const VerificationMeta(
    'stationCode',
  );
  @override
  late final GeneratedColumn<String> stationCode = GeneratedColumn<String>(
    'station_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  List<GeneratedColumn> get $columns => [
    id,
    query,
    region,
    stationId,
    lineId,
    lineName,
    lineColor,
    stationCode,
    searchedAt,
  ];
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
    if (data.containsKey('region')) {
      context.handle(
        _regionMeta,
        region.isAcceptableOrUnknown(data['region']!, _regionMeta),
      );
    }
    if (data.containsKey('station_id')) {
      context.handle(
        _stationIdMeta,
        stationId.isAcceptableOrUnknown(data['station_id']!, _stationIdMeta),
      );
    }
    if (data.containsKey('line_id')) {
      context.handle(
        _lineIdMeta,
        lineId.isAcceptableOrUnknown(data['line_id']!, _lineIdMeta),
      );
    }
    if (data.containsKey('line_name')) {
      context.handle(
        _lineNameMeta,
        lineName.isAcceptableOrUnknown(data['line_name']!, _lineNameMeta),
      );
    }
    if (data.containsKey('line_color')) {
      context.handle(
        _lineColorMeta,
        lineColor.isAcceptableOrUnknown(data['line_color']!, _lineColorMeta),
      );
    }
    if (data.containsKey('station_code')) {
      context.handle(
        _stationCodeMeta,
        stationCode.isAcceptableOrUnknown(
          data['station_code']!,
          _stationCodeMeta,
        ),
      );
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
      region: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}region'],
      ),
      stationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}station_id'],
      ),
      lineId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}line_id'],
      ),
      lineName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}line_name'],
      ),
      lineColor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}line_color'],
      ),
      stationCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}station_code'],
      ),
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

  /// 검색 당시 선택 지역(예: `수도권`, `부산`). 지역별 최근 목록 필터에 쓴다.
  /// 지역 정보 없이 저장된 레거시 행은 null이며, 지역 필터 목록에서 제외한다.
  final String? region;

  /// 결과에서 고른 역·호선. 검색어만 있는 레거시/타이핑 기록은 null.
  final String? stationId;
  final String? lineId;
  final String? lineName;
  final String? lineColor;
  final String? stationCode;
  final DateTime searchedAt;
  const SearchHistoryData({
    required this.id,
    required this.query,
    this.region,
    this.stationId,
    this.lineId,
    this.lineName,
    this.lineColor,
    this.stationCode,
    required this.searchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['query'] = Variable<String>(query);
    if (!nullToAbsent || region != null) {
      map['region'] = Variable<String>(region);
    }
    if (!nullToAbsent || stationId != null) {
      map['station_id'] = Variable<String>(stationId);
    }
    if (!nullToAbsent || lineId != null) {
      map['line_id'] = Variable<String>(lineId);
    }
    if (!nullToAbsent || lineName != null) {
      map['line_name'] = Variable<String>(lineName);
    }
    if (!nullToAbsent || lineColor != null) {
      map['line_color'] = Variable<String>(lineColor);
    }
    if (!nullToAbsent || stationCode != null) {
      map['station_code'] = Variable<String>(stationCode);
    }
    map['searched_at'] = Variable<DateTime>(searchedAt);
    return map;
  }

  SearchHistoryCompanion toCompanion(bool nullToAbsent) {
    return SearchHistoryCompanion(
      id: Value(id),
      query: Value(query),
      region: region == null && nullToAbsent
          ? const Value.absent()
          : Value(region),
      stationId: stationId == null && nullToAbsent
          ? const Value.absent()
          : Value(stationId),
      lineId: lineId == null && nullToAbsent
          ? const Value.absent()
          : Value(lineId),
      lineName: lineName == null && nullToAbsent
          ? const Value.absent()
          : Value(lineName),
      lineColor: lineColor == null && nullToAbsent
          ? const Value.absent()
          : Value(lineColor),
      stationCode: stationCode == null && nullToAbsent
          ? const Value.absent()
          : Value(stationCode),
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
      region: serializer.fromJson<String?>(json['region']),
      stationId: serializer.fromJson<String?>(json['stationId']),
      lineId: serializer.fromJson<String?>(json['lineId']),
      lineName: serializer.fromJson<String?>(json['lineName']),
      lineColor: serializer.fromJson<String?>(json['lineColor']),
      stationCode: serializer.fromJson<String?>(json['stationCode']),
      searchedAt: serializer.fromJson<DateTime>(json['searchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'query': serializer.toJson<String>(query),
      'region': serializer.toJson<String?>(region),
      'stationId': serializer.toJson<String?>(stationId),
      'lineId': serializer.toJson<String?>(lineId),
      'lineName': serializer.toJson<String?>(lineName),
      'lineColor': serializer.toJson<String?>(lineColor),
      'stationCode': serializer.toJson<String?>(stationCode),
      'searchedAt': serializer.toJson<DateTime>(searchedAt),
    };
  }

  SearchHistoryData copyWith({
    int? id,
    String? query,
    Value<String?> region = const Value.absent(),
    Value<String?> stationId = const Value.absent(),
    Value<String?> lineId = const Value.absent(),
    Value<String?> lineName = const Value.absent(),
    Value<String?> lineColor = const Value.absent(),
    Value<String?> stationCode = const Value.absent(),
    DateTime? searchedAt,
  }) => SearchHistoryData(
    id: id ?? this.id,
    query: query ?? this.query,
    region: region.present ? region.value : this.region,
    stationId: stationId.present ? stationId.value : this.stationId,
    lineId: lineId.present ? lineId.value : this.lineId,
    lineName: lineName.present ? lineName.value : this.lineName,
    lineColor: lineColor.present ? lineColor.value : this.lineColor,
    stationCode: stationCode.present ? stationCode.value : this.stationCode,
    searchedAt: searchedAt ?? this.searchedAt,
  );
  SearchHistoryData copyWithCompanion(SearchHistoryCompanion data) {
    return SearchHistoryData(
      id: data.id.present ? data.id.value : this.id,
      query: data.query.present ? data.query.value : this.query,
      region: data.region.present ? data.region.value : this.region,
      stationId: data.stationId.present ? data.stationId.value : this.stationId,
      lineId: data.lineId.present ? data.lineId.value : this.lineId,
      lineName: data.lineName.present ? data.lineName.value : this.lineName,
      lineColor: data.lineColor.present ? data.lineColor.value : this.lineColor,
      stationCode: data.stationCode.present
          ? data.stationCode.value
          : this.stationCode,
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
          ..write('region: $region, ')
          ..write('stationId: $stationId, ')
          ..write('lineId: $lineId, ')
          ..write('lineName: $lineName, ')
          ..write('lineColor: $lineColor, ')
          ..write('stationCode: $stationCode, ')
          ..write('searchedAt: $searchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    query,
    region,
    stationId,
    lineId,
    lineName,
    lineColor,
    stationCode,
    searchedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SearchHistoryData &&
          other.id == this.id &&
          other.query == this.query &&
          other.region == this.region &&
          other.stationId == this.stationId &&
          other.lineId == this.lineId &&
          other.lineName == this.lineName &&
          other.lineColor == this.lineColor &&
          other.stationCode == this.stationCode &&
          other.searchedAt == this.searchedAt);
}

class SearchHistoryCompanion extends UpdateCompanion<SearchHistoryData> {
  final Value<int> id;
  final Value<String> query;
  final Value<String?> region;
  final Value<String?> stationId;
  final Value<String?> lineId;
  final Value<String?> lineName;
  final Value<String?> lineColor;
  final Value<String?> stationCode;
  final Value<DateTime> searchedAt;
  const SearchHistoryCompanion({
    this.id = const Value.absent(),
    this.query = const Value.absent(),
    this.region = const Value.absent(),
    this.stationId = const Value.absent(),
    this.lineId = const Value.absent(),
    this.lineName = const Value.absent(),
    this.lineColor = const Value.absent(),
    this.stationCode = const Value.absent(),
    this.searchedAt = const Value.absent(),
  });
  SearchHistoryCompanion.insert({
    this.id = const Value.absent(),
    required String query,
    this.region = const Value.absent(),
    this.stationId = const Value.absent(),
    this.lineId = const Value.absent(),
    this.lineName = const Value.absent(),
    this.lineColor = const Value.absent(),
    this.stationCode = const Value.absent(),
    required DateTime searchedAt,
  }) : query = Value(query),
       searchedAt = Value(searchedAt);
  static Insertable<SearchHistoryData> custom({
    Expression<int>? id,
    Expression<String>? query,
    Expression<String>? region,
    Expression<String>? stationId,
    Expression<String>? lineId,
    Expression<String>? lineName,
    Expression<String>? lineColor,
    Expression<String>? stationCode,
    Expression<DateTime>? searchedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (query != null) 'query': query,
      if (region != null) 'region': region,
      if (stationId != null) 'station_id': stationId,
      if (lineId != null) 'line_id': lineId,
      if (lineName != null) 'line_name': lineName,
      if (lineColor != null) 'line_color': lineColor,
      if (stationCode != null) 'station_code': stationCode,
      if (searchedAt != null) 'searched_at': searchedAt,
    });
  }

  SearchHistoryCompanion copyWith({
    Value<int>? id,
    Value<String>? query,
    Value<String?>? region,
    Value<String?>? stationId,
    Value<String?>? lineId,
    Value<String?>? lineName,
    Value<String?>? lineColor,
    Value<String?>? stationCode,
    Value<DateTime>? searchedAt,
  }) {
    return SearchHistoryCompanion(
      id: id ?? this.id,
      query: query ?? this.query,
      region: region ?? this.region,
      stationId: stationId ?? this.stationId,
      lineId: lineId ?? this.lineId,
      lineName: lineName ?? this.lineName,
      lineColor: lineColor ?? this.lineColor,
      stationCode: stationCode ?? this.stationCode,
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
    if (region.present) {
      map['region'] = Variable<String>(region.value);
    }
    if (stationId.present) {
      map['station_id'] = Variable<String>(stationId.value);
    }
    if (lineId.present) {
      map['line_id'] = Variable<String>(lineId.value);
    }
    if (lineName.present) {
      map['line_name'] = Variable<String>(lineName.value);
    }
    if (lineColor.present) {
      map['line_color'] = Variable<String>(lineColor.value);
    }
    if (stationCode.present) {
      map['station_code'] = Variable<String>(stationCode.value);
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
          ..write('region: $region, ')
          ..write('stationId: $stationId, ')
          ..write('lineId: $lineId, ')
          ..write('lineName: $lineName, ')
          ..write('lineColor: $lineColor, ')
          ..write('stationCode: $stationCode, ')
          ..write('searchedAt: $searchedAt')
          ..write(')'))
        .toString();
  }
}

class $RouteSearchHistoryTable extends RouteSearchHistory
    with TableInfo<$RouteSearchHistoryTable, RouteSearchHistoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RouteSearchHistoryTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _originStationNameMeta = const VerificationMeta(
    'originStationName',
  );
  @override
  late final GeneratedColumn<String> originStationName =
      GeneratedColumn<String>(
        'origin_station_name',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _originLineIdMeta = const VerificationMeta(
    'originLineId',
  );
  @override
  late final GeneratedColumn<String> originLineId = GeneratedColumn<String>(
    'origin_line_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _originLineNameMeta = const VerificationMeta(
    'originLineName',
  );
  @override
  late final GeneratedColumn<String> originLineName = GeneratedColumn<String>(
    'origin_line_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _originLineColorMeta = const VerificationMeta(
    'originLineColor',
  );
  @override
  late final GeneratedColumn<String> originLineColor = GeneratedColumn<String>(
    'origin_line_color',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _originStationCodeMeta = const VerificationMeta(
    'originStationCode',
  );
  @override
  late final GeneratedColumn<String> originStationCode =
      GeneratedColumn<String>(
        'origin_station_code',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _waypointStationIdMeta = const VerificationMeta(
    'waypointStationId',
  );
  @override
  late final GeneratedColumn<String> waypointStationId =
      GeneratedColumn<String>(
        'waypoint_station_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _waypointStationNameMeta =
      const VerificationMeta('waypointStationName');
  @override
  late final GeneratedColumn<String> waypointStationName =
      GeneratedColumn<String>(
        'waypoint_station_name',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _waypointLineIdMeta = const VerificationMeta(
    'waypointLineId',
  );
  @override
  late final GeneratedColumn<String> waypointLineId = GeneratedColumn<String>(
    'waypoint_line_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _waypointLineNameMeta = const VerificationMeta(
    'waypointLineName',
  );
  @override
  late final GeneratedColumn<String> waypointLineName = GeneratedColumn<String>(
    'waypoint_line_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _waypointLineColorMeta = const VerificationMeta(
    'waypointLineColor',
  );
  @override
  late final GeneratedColumn<String> waypointLineColor =
      GeneratedColumn<String>(
        'waypoint_line_color',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _waypointStationCodeMeta =
      const VerificationMeta('waypointStationCode');
  @override
  late final GeneratedColumn<String> waypointStationCode =
      GeneratedColumn<String>(
        'waypoint_station_code',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
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
  static const VerificationMeta _destinationStationNameMeta =
      const VerificationMeta('destinationStationName');
  @override
  late final GeneratedColumn<String> destinationStationName =
      GeneratedColumn<String>(
        'destination_station_name',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _destinationLineIdMeta = const VerificationMeta(
    'destinationLineId',
  );
  @override
  late final GeneratedColumn<String> destinationLineId =
      GeneratedColumn<String>(
        'destination_line_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _destinationLineNameMeta =
      const VerificationMeta('destinationLineName');
  @override
  late final GeneratedColumn<String> destinationLineName =
      GeneratedColumn<String>(
        'destination_line_name',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _destinationLineColorMeta =
      const VerificationMeta('destinationLineColor');
  @override
  late final GeneratedColumn<String> destinationLineColor =
      GeneratedColumn<String>(
        'destination_line_color',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _destinationStationCodeMeta =
      const VerificationMeta('destinationStationCode');
  @override
  late final GeneratedColumn<String> destinationStationCode =
      GeneratedColumn<String>(
        'destination_station_code',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _regionMeta = const VerificationMeta('region');
  @override
  late final GeneratedColumn<String> region = GeneratedColumn<String>(
    'region',
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
  List<GeneratedColumn> get $columns => [
    id,
    originStationId,
    originStationName,
    originLineId,
    originLineName,
    originLineColor,
    originStationCode,
    waypointStationId,
    waypointStationName,
    waypointLineId,
    waypointLineName,
    waypointLineColor,
    waypointStationCode,
    destinationStationId,
    destinationStationName,
    destinationLineId,
    destinationLineName,
    destinationLineColor,
    destinationStationCode,
    region,
    searchedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'route_search_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<RouteSearchHistoryData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
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
    if (data.containsKey('origin_station_name')) {
      context.handle(
        _originStationNameMeta,
        originStationName.isAcceptableOrUnknown(
          data['origin_station_name']!,
          _originStationNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originStationNameMeta);
    }
    if (data.containsKey('origin_line_id')) {
      context.handle(
        _originLineIdMeta,
        originLineId.isAcceptableOrUnknown(
          data['origin_line_id']!,
          _originLineIdMeta,
        ),
      );
    }
    if (data.containsKey('origin_line_name')) {
      context.handle(
        _originLineNameMeta,
        originLineName.isAcceptableOrUnknown(
          data['origin_line_name']!,
          _originLineNameMeta,
        ),
      );
    }
    if (data.containsKey('origin_line_color')) {
      context.handle(
        _originLineColorMeta,
        originLineColor.isAcceptableOrUnknown(
          data['origin_line_color']!,
          _originLineColorMeta,
        ),
      );
    }
    if (data.containsKey('origin_station_code')) {
      context.handle(
        _originStationCodeMeta,
        originStationCode.isAcceptableOrUnknown(
          data['origin_station_code']!,
          _originStationCodeMeta,
        ),
      );
    }
    if (data.containsKey('waypoint_station_id')) {
      context.handle(
        _waypointStationIdMeta,
        waypointStationId.isAcceptableOrUnknown(
          data['waypoint_station_id']!,
          _waypointStationIdMeta,
        ),
      );
    }
    if (data.containsKey('waypoint_station_name')) {
      context.handle(
        _waypointStationNameMeta,
        waypointStationName.isAcceptableOrUnknown(
          data['waypoint_station_name']!,
          _waypointStationNameMeta,
        ),
      );
    }
    if (data.containsKey('waypoint_line_id')) {
      context.handle(
        _waypointLineIdMeta,
        waypointLineId.isAcceptableOrUnknown(
          data['waypoint_line_id']!,
          _waypointLineIdMeta,
        ),
      );
    }
    if (data.containsKey('waypoint_line_name')) {
      context.handle(
        _waypointLineNameMeta,
        waypointLineName.isAcceptableOrUnknown(
          data['waypoint_line_name']!,
          _waypointLineNameMeta,
        ),
      );
    }
    if (data.containsKey('waypoint_line_color')) {
      context.handle(
        _waypointLineColorMeta,
        waypointLineColor.isAcceptableOrUnknown(
          data['waypoint_line_color']!,
          _waypointLineColorMeta,
        ),
      );
    }
    if (data.containsKey('waypoint_station_code')) {
      context.handle(
        _waypointStationCodeMeta,
        waypointStationCode.isAcceptableOrUnknown(
          data['waypoint_station_code']!,
          _waypointStationCodeMeta,
        ),
      );
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
    if (data.containsKey('destination_station_name')) {
      context.handle(
        _destinationStationNameMeta,
        destinationStationName.isAcceptableOrUnknown(
          data['destination_station_name']!,
          _destinationStationNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_destinationStationNameMeta);
    }
    if (data.containsKey('destination_line_id')) {
      context.handle(
        _destinationLineIdMeta,
        destinationLineId.isAcceptableOrUnknown(
          data['destination_line_id']!,
          _destinationLineIdMeta,
        ),
      );
    }
    if (data.containsKey('destination_line_name')) {
      context.handle(
        _destinationLineNameMeta,
        destinationLineName.isAcceptableOrUnknown(
          data['destination_line_name']!,
          _destinationLineNameMeta,
        ),
      );
    }
    if (data.containsKey('destination_line_color')) {
      context.handle(
        _destinationLineColorMeta,
        destinationLineColor.isAcceptableOrUnknown(
          data['destination_line_color']!,
          _destinationLineColorMeta,
        ),
      );
    }
    if (data.containsKey('destination_station_code')) {
      context.handle(
        _destinationStationCodeMeta,
        destinationStationCode.isAcceptableOrUnknown(
          data['destination_station_code']!,
          _destinationStationCodeMeta,
        ),
      );
    }
    if (data.containsKey('region')) {
      context.handle(
        _regionMeta,
        region.isAcceptableOrUnknown(data['region']!, _regionMeta),
      );
    } else if (isInserting) {
      context.missing(_regionMeta);
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
  RouteSearchHistoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RouteSearchHistoryData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      originStationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_station_id'],
      )!,
      originStationName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_station_name'],
      )!,
      originLineId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_line_id'],
      ),
      originLineName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_line_name'],
      ),
      originLineColor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_line_color'],
      ),
      originStationCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_station_code'],
      ),
      waypointStationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}waypoint_station_id'],
      ),
      waypointStationName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}waypoint_station_name'],
      ),
      waypointLineId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}waypoint_line_id'],
      ),
      waypointLineName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}waypoint_line_name'],
      ),
      waypointLineColor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}waypoint_line_color'],
      ),
      waypointStationCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}waypoint_station_code'],
      ),
      destinationStationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}destination_station_id'],
      )!,
      destinationStationName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}destination_station_name'],
      )!,
      destinationLineId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}destination_line_id'],
      ),
      destinationLineName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}destination_line_name'],
      ),
      destinationLineColor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}destination_line_color'],
      ),
      destinationStationCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}destination_station_code'],
      ),
      region: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}region'],
      )!,
      searchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}searched_at'],
      )!,
    );
  }

  @override
  $RouteSearchHistoryTable createAlias(String alias) {
    return $RouteSearchHistoryTable(attachedDatabase, alias);
  }
}

class RouteSearchHistoryData extends DataClass
    implements Insertable<RouteSearchHistoryData> {
  final int id;
  final String originStationId;
  final String originStationName;
  final String? originLineId;
  final String? originLineName;
  final String? originLineColor;
  final String? originStationCode;
  final String? waypointStationId;
  final String? waypointStationName;
  final String? waypointLineId;
  final String? waypointLineName;
  final String? waypointLineColor;
  final String? waypointStationCode;
  final String destinationStationId;
  final String destinationStationName;
  final String? destinationLineId;
  final String? destinationLineName;
  final String? destinationLineColor;
  final String? destinationStationCode;
  final String region;
  final DateTime searchedAt;
  const RouteSearchHistoryData({
    required this.id,
    required this.originStationId,
    required this.originStationName,
    this.originLineId,
    this.originLineName,
    this.originLineColor,
    this.originStationCode,
    this.waypointStationId,
    this.waypointStationName,
    this.waypointLineId,
    this.waypointLineName,
    this.waypointLineColor,
    this.waypointStationCode,
    required this.destinationStationId,
    required this.destinationStationName,
    this.destinationLineId,
    this.destinationLineName,
    this.destinationLineColor,
    this.destinationStationCode,
    required this.region,
    required this.searchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['origin_station_id'] = Variable<String>(originStationId);
    map['origin_station_name'] = Variable<String>(originStationName);
    if (!nullToAbsent || originLineId != null) {
      map['origin_line_id'] = Variable<String>(originLineId);
    }
    if (!nullToAbsent || originLineName != null) {
      map['origin_line_name'] = Variable<String>(originLineName);
    }
    if (!nullToAbsent || originLineColor != null) {
      map['origin_line_color'] = Variable<String>(originLineColor);
    }
    if (!nullToAbsent || originStationCode != null) {
      map['origin_station_code'] = Variable<String>(originStationCode);
    }
    if (!nullToAbsent || waypointStationId != null) {
      map['waypoint_station_id'] = Variable<String>(waypointStationId);
    }
    if (!nullToAbsent || waypointStationName != null) {
      map['waypoint_station_name'] = Variable<String>(waypointStationName);
    }
    if (!nullToAbsent || waypointLineId != null) {
      map['waypoint_line_id'] = Variable<String>(waypointLineId);
    }
    if (!nullToAbsent || waypointLineName != null) {
      map['waypoint_line_name'] = Variable<String>(waypointLineName);
    }
    if (!nullToAbsent || waypointLineColor != null) {
      map['waypoint_line_color'] = Variable<String>(waypointLineColor);
    }
    if (!nullToAbsent || waypointStationCode != null) {
      map['waypoint_station_code'] = Variable<String>(waypointStationCode);
    }
    map['destination_station_id'] = Variable<String>(destinationStationId);
    map['destination_station_name'] = Variable<String>(destinationStationName);
    if (!nullToAbsent || destinationLineId != null) {
      map['destination_line_id'] = Variable<String>(destinationLineId);
    }
    if (!nullToAbsent || destinationLineName != null) {
      map['destination_line_name'] = Variable<String>(destinationLineName);
    }
    if (!nullToAbsent || destinationLineColor != null) {
      map['destination_line_color'] = Variable<String>(destinationLineColor);
    }
    if (!nullToAbsent || destinationStationCode != null) {
      map['destination_station_code'] = Variable<String>(
        destinationStationCode,
      );
    }
    map['region'] = Variable<String>(region);
    map['searched_at'] = Variable<DateTime>(searchedAt);
    return map;
  }

  RouteSearchHistoryCompanion toCompanion(bool nullToAbsent) {
    return RouteSearchHistoryCompanion(
      id: Value(id),
      originStationId: Value(originStationId),
      originStationName: Value(originStationName),
      originLineId: originLineId == null && nullToAbsent
          ? const Value.absent()
          : Value(originLineId),
      originLineName: originLineName == null && nullToAbsent
          ? const Value.absent()
          : Value(originLineName),
      originLineColor: originLineColor == null && nullToAbsent
          ? const Value.absent()
          : Value(originLineColor),
      originStationCode: originStationCode == null && nullToAbsent
          ? const Value.absent()
          : Value(originStationCode),
      waypointStationId: waypointStationId == null && nullToAbsent
          ? const Value.absent()
          : Value(waypointStationId),
      waypointStationName: waypointStationName == null && nullToAbsent
          ? const Value.absent()
          : Value(waypointStationName),
      waypointLineId: waypointLineId == null && nullToAbsent
          ? const Value.absent()
          : Value(waypointLineId),
      waypointLineName: waypointLineName == null && nullToAbsent
          ? const Value.absent()
          : Value(waypointLineName),
      waypointLineColor: waypointLineColor == null && nullToAbsent
          ? const Value.absent()
          : Value(waypointLineColor),
      waypointStationCode: waypointStationCode == null && nullToAbsent
          ? const Value.absent()
          : Value(waypointStationCode),
      destinationStationId: Value(destinationStationId),
      destinationStationName: Value(destinationStationName),
      destinationLineId: destinationLineId == null && nullToAbsent
          ? const Value.absent()
          : Value(destinationLineId),
      destinationLineName: destinationLineName == null && nullToAbsent
          ? const Value.absent()
          : Value(destinationLineName),
      destinationLineColor: destinationLineColor == null && nullToAbsent
          ? const Value.absent()
          : Value(destinationLineColor),
      destinationStationCode: destinationStationCode == null && nullToAbsent
          ? const Value.absent()
          : Value(destinationStationCode),
      region: Value(region),
      searchedAt: Value(searchedAt),
    );
  }

  factory RouteSearchHistoryData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RouteSearchHistoryData(
      id: serializer.fromJson<int>(json['id']),
      originStationId: serializer.fromJson<String>(json['originStationId']),
      originStationName: serializer.fromJson<String>(json['originStationName']),
      originLineId: serializer.fromJson<String?>(json['originLineId']),
      originLineName: serializer.fromJson<String?>(json['originLineName']),
      originLineColor: serializer.fromJson<String?>(json['originLineColor']),
      originStationCode: serializer.fromJson<String?>(
        json['originStationCode'],
      ),
      waypointStationId: serializer.fromJson<String?>(
        json['waypointStationId'],
      ),
      waypointStationName: serializer.fromJson<String?>(
        json['waypointStationName'],
      ),
      waypointLineId: serializer.fromJson<String?>(json['waypointLineId']),
      waypointLineName: serializer.fromJson<String?>(json['waypointLineName']),
      waypointLineColor: serializer.fromJson<String?>(
        json['waypointLineColor'],
      ),
      waypointStationCode: serializer.fromJson<String?>(
        json['waypointStationCode'],
      ),
      destinationStationId: serializer.fromJson<String>(
        json['destinationStationId'],
      ),
      destinationStationName: serializer.fromJson<String>(
        json['destinationStationName'],
      ),
      destinationLineId: serializer.fromJson<String?>(
        json['destinationLineId'],
      ),
      destinationLineName: serializer.fromJson<String?>(
        json['destinationLineName'],
      ),
      destinationLineColor: serializer.fromJson<String?>(
        json['destinationLineColor'],
      ),
      destinationStationCode: serializer.fromJson<String?>(
        json['destinationStationCode'],
      ),
      region: serializer.fromJson<String>(json['region']),
      searchedAt: serializer.fromJson<DateTime>(json['searchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'originStationId': serializer.toJson<String>(originStationId),
      'originStationName': serializer.toJson<String>(originStationName),
      'originLineId': serializer.toJson<String?>(originLineId),
      'originLineName': serializer.toJson<String?>(originLineName),
      'originLineColor': serializer.toJson<String?>(originLineColor),
      'originStationCode': serializer.toJson<String?>(originStationCode),
      'waypointStationId': serializer.toJson<String?>(waypointStationId),
      'waypointStationName': serializer.toJson<String?>(waypointStationName),
      'waypointLineId': serializer.toJson<String?>(waypointLineId),
      'waypointLineName': serializer.toJson<String?>(waypointLineName),
      'waypointLineColor': serializer.toJson<String?>(waypointLineColor),
      'waypointStationCode': serializer.toJson<String?>(waypointStationCode),
      'destinationStationId': serializer.toJson<String>(destinationStationId),
      'destinationStationName': serializer.toJson<String>(
        destinationStationName,
      ),
      'destinationLineId': serializer.toJson<String?>(destinationLineId),
      'destinationLineName': serializer.toJson<String?>(destinationLineName),
      'destinationLineColor': serializer.toJson<String?>(destinationLineColor),
      'destinationStationCode': serializer.toJson<String?>(
        destinationStationCode,
      ),
      'region': serializer.toJson<String>(region),
      'searchedAt': serializer.toJson<DateTime>(searchedAt),
    };
  }

  RouteSearchHistoryData copyWith({
    int? id,
    String? originStationId,
    String? originStationName,
    Value<String?> originLineId = const Value.absent(),
    Value<String?> originLineName = const Value.absent(),
    Value<String?> originLineColor = const Value.absent(),
    Value<String?> originStationCode = const Value.absent(),
    Value<String?> waypointStationId = const Value.absent(),
    Value<String?> waypointStationName = const Value.absent(),
    Value<String?> waypointLineId = const Value.absent(),
    Value<String?> waypointLineName = const Value.absent(),
    Value<String?> waypointLineColor = const Value.absent(),
    Value<String?> waypointStationCode = const Value.absent(),
    String? destinationStationId,
    String? destinationStationName,
    Value<String?> destinationLineId = const Value.absent(),
    Value<String?> destinationLineName = const Value.absent(),
    Value<String?> destinationLineColor = const Value.absent(),
    Value<String?> destinationStationCode = const Value.absent(),
    String? region,
    DateTime? searchedAt,
  }) => RouteSearchHistoryData(
    id: id ?? this.id,
    originStationId: originStationId ?? this.originStationId,
    originStationName: originStationName ?? this.originStationName,
    originLineId: originLineId.present ? originLineId.value : this.originLineId,
    originLineName: originLineName.present
        ? originLineName.value
        : this.originLineName,
    originLineColor: originLineColor.present
        ? originLineColor.value
        : this.originLineColor,
    originStationCode: originStationCode.present
        ? originStationCode.value
        : this.originStationCode,
    waypointStationId: waypointStationId.present
        ? waypointStationId.value
        : this.waypointStationId,
    waypointStationName: waypointStationName.present
        ? waypointStationName.value
        : this.waypointStationName,
    waypointLineId: waypointLineId.present
        ? waypointLineId.value
        : this.waypointLineId,
    waypointLineName: waypointLineName.present
        ? waypointLineName.value
        : this.waypointLineName,
    waypointLineColor: waypointLineColor.present
        ? waypointLineColor.value
        : this.waypointLineColor,
    waypointStationCode: waypointStationCode.present
        ? waypointStationCode.value
        : this.waypointStationCode,
    destinationStationId: destinationStationId ?? this.destinationStationId,
    destinationStationName:
        destinationStationName ?? this.destinationStationName,
    destinationLineId: destinationLineId.present
        ? destinationLineId.value
        : this.destinationLineId,
    destinationLineName: destinationLineName.present
        ? destinationLineName.value
        : this.destinationLineName,
    destinationLineColor: destinationLineColor.present
        ? destinationLineColor.value
        : this.destinationLineColor,
    destinationStationCode: destinationStationCode.present
        ? destinationStationCode.value
        : this.destinationStationCode,
    region: region ?? this.region,
    searchedAt: searchedAt ?? this.searchedAt,
  );
  RouteSearchHistoryData copyWithCompanion(RouteSearchHistoryCompanion data) {
    return RouteSearchHistoryData(
      id: data.id.present ? data.id.value : this.id,
      originStationId: data.originStationId.present
          ? data.originStationId.value
          : this.originStationId,
      originStationName: data.originStationName.present
          ? data.originStationName.value
          : this.originStationName,
      originLineId: data.originLineId.present
          ? data.originLineId.value
          : this.originLineId,
      originLineName: data.originLineName.present
          ? data.originLineName.value
          : this.originLineName,
      originLineColor: data.originLineColor.present
          ? data.originLineColor.value
          : this.originLineColor,
      originStationCode: data.originStationCode.present
          ? data.originStationCode.value
          : this.originStationCode,
      waypointStationId: data.waypointStationId.present
          ? data.waypointStationId.value
          : this.waypointStationId,
      waypointStationName: data.waypointStationName.present
          ? data.waypointStationName.value
          : this.waypointStationName,
      waypointLineId: data.waypointLineId.present
          ? data.waypointLineId.value
          : this.waypointLineId,
      waypointLineName: data.waypointLineName.present
          ? data.waypointLineName.value
          : this.waypointLineName,
      waypointLineColor: data.waypointLineColor.present
          ? data.waypointLineColor.value
          : this.waypointLineColor,
      waypointStationCode: data.waypointStationCode.present
          ? data.waypointStationCode.value
          : this.waypointStationCode,
      destinationStationId: data.destinationStationId.present
          ? data.destinationStationId.value
          : this.destinationStationId,
      destinationStationName: data.destinationStationName.present
          ? data.destinationStationName.value
          : this.destinationStationName,
      destinationLineId: data.destinationLineId.present
          ? data.destinationLineId.value
          : this.destinationLineId,
      destinationLineName: data.destinationLineName.present
          ? data.destinationLineName.value
          : this.destinationLineName,
      destinationLineColor: data.destinationLineColor.present
          ? data.destinationLineColor.value
          : this.destinationLineColor,
      destinationStationCode: data.destinationStationCode.present
          ? data.destinationStationCode.value
          : this.destinationStationCode,
      region: data.region.present ? data.region.value : this.region,
      searchedAt: data.searchedAt.present
          ? data.searchedAt.value
          : this.searchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RouteSearchHistoryData(')
          ..write('id: $id, ')
          ..write('originStationId: $originStationId, ')
          ..write('originStationName: $originStationName, ')
          ..write('originLineId: $originLineId, ')
          ..write('originLineName: $originLineName, ')
          ..write('originLineColor: $originLineColor, ')
          ..write('originStationCode: $originStationCode, ')
          ..write('waypointStationId: $waypointStationId, ')
          ..write('waypointStationName: $waypointStationName, ')
          ..write('waypointLineId: $waypointLineId, ')
          ..write('waypointLineName: $waypointLineName, ')
          ..write('waypointLineColor: $waypointLineColor, ')
          ..write('waypointStationCode: $waypointStationCode, ')
          ..write('destinationStationId: $destinationStationId, ')
          ..write('destinationStationName: $destinationStationName, ')
          ..write('destinationLineId: $destinationLineId, ')
          ..write('destinationLineName: $destinationLineName, ')
          ..write('destinationLineColor: $destinationLineColor, ')
          ..write('destinationStationCode: $destinationStationCode, ')
          ..write('region: $region, ')
          ..write('searchedAt: $searchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    originStationId,
    originStationName,
    originLineId,
    originLineName,
    originLineColor,
    originStationCode,
    waypointStationId,
    waypointStationName,
    waypointLineId,
    waypointLineName,
    waypointLineColor,
    waypointStationCode,
    destinationStationId,
    destinationStationName,
    destinationLineId,
    destinationLineName,
    destinationLineColor,
    destinationStationCode,
    region,
    searchedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RouteSearchHistoryData &&
          other.id == this.id &&
          other.originStationId == this.originStationId &&
          other.originStationName == this.originStationName &&
          other.originLineId == this.originLineId &&
          other.originLineName == this.originLineName &&
          other.originLineColor == this.originLineColor &&
          other.originStationCode == this.originStationCode &&
          other.waypointStationId == this.waypointStationId &&
          other.waypointStationName == this.waypointStationName &&
          other.waypointLineId == this.waypointLineId &&
          other.waypointLineName == this.waypointLineName &&
          other.waypointLineColor == this.waypointLineColor &&
          other.waypointStationCode == this.waypointStationCode &&
          other.destinationStationId == this.destinationStationId &&
          other.destinationStationName == this.destinationStationName &&
          other.destinationLineId == this.destinationLineId &&
          other.destinationLineName == this.destinationLineName &&
          other.destinationLineColor == this.destinationLineColor &&
          other.destinationStationCode == this.destinationStationCode &&
          other.region == this.region &&
          other.searchedAt == this.searchedAt);
}

class RouteSearchHistoryCompanion
    extends UpdateCompanion<RouteSearchHistoryData> {
  final Value<int> id;
  final Value<String> originStationId;
  final Value<String> originStationName;
  final Value<String?> originLineId;
  final Value<String?> originLineName;
  final Value<String?> originLineColor;
  final Value<String?> originStationCode;
  final Value<String?> waypointStationId;
  final Value<String?> waypointStationName;
  final Value<String?> waypointLineId;
  final Value<String?> waypointLineName;
  final Value<String?> waypointLineColor;
  final Value<String?> waypointStationCode;
  final Value<String> destinationStationId;
  final Value<String> destinationStationName;
  final Value<String?> destinationLineId;
  final Value<String?> destinationLineName;
  final Value<String?> destinationLineColor;
  final Value<String?> destinationStationCode;
  final Value<String> region;
  final Value<DateTime> searchedAt;
  const RouteSearchHistoryCompanion({
    this.id = const Value.absent(),
    this.originStationId = const Value.absent(),
    this.originStationName = const Value.absent(),
    this.originLineId = const Value.absent(),
    this.originLineName = const Value.absent(),
    this.originLineColor = const Value.absent(),
    this.originStationCode = const Value.absent(),
    this.waypointStationId = const Value.absent(),
    this.waypointStationName = const Value.absent(),
    this.waypointLineId = const Value.absent(),
    this.waypointLineName = const Value.absent(),
    this.waypointLineColor = const Value.absent(),
    this.waypointStationCode = const Value.absent(),
    this.destinationStationId = const Value.absent(),
    this.destinationStationName = const Value.absent(),
    this.destinationLineId = const Value.absent(),
    this.destinationLineName = const Value.absent(),
    this.destinationLineColor = const Value.absent(),
    this.destinationStationCode = const Value.absent(),
    this.region = const Value.absent(),
    this.searchedAt = const Value.absent(),
  });
  RouteSearchHistoryCompanion.insert({
    this.id = const Value.absent(),
    required String originStationId,
    required String originStationName,
    this.originLineId = const Value.absent(),
    this.originLineName = const Value.absent(),
    this.originLineColor = const Value.absent(),
    this.originStationCode = const Value.absent(),
    this.waypointStationId = const Value.absent(),
    this.waypointStationName = const Value.absent(),
    this.waypointLineId = const Value.absent(),
    this.waypointLineName = const Value.absent(),
    this.waypointLineColor = const Value.absent(),
    this.waypointStationCode = const Value.absent(),
    required String destinationStationId,
    required String destinationStationName,
    this.destinationLineId = const Value.absent(),
    this.destinationLineName = const Value.absent(),
    this.destinationLineColor = const Value.absent(),
    this.destinationStationCode = const Value.absent(),
    required String region,
    required DateTime searchedAt,
  }) : originStationId = Value(originStationId),
       originStationName = Value(originStationName),
       destinationStationId = Value(destinationStationId),
       destinationStationName = Value(destinationStationName),
       region = Value(region),
       searchedAt = Value(searchedAt);
  static Insertable<RouteSearchHistoryData> custom({
    Expression<int>? id,
    Expression<String>? originStationId,
    Expression<String>? originStationName,
    Expression<String>? originLineId,
    Expression<String>? originLineName,
    Expression<String>? originLineColor,
    Expression<String>? originStationCode,
    Expression<String>? waypointStationId,
    Expression<String>? waypointStationName,
    Expression<String>? waypointLineId,
    Expression<String>? waypointLineName,
    Expression<String>? waypointLineColor,
    Expression<String>? waypointStationCode,
    Expression<String>? destinationStationId,
    Expression<String>? destinationStationName,
    Expression<String>? destinationLineId,
    Expression<String>? destinationLineName,
    Expression<String>? destinationLineColor,
    Expression<String>? destinationStationCode,
    Expression<String>? region,
    Expression<DateTime>? searchedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (originStationId != null) 'origin_station_id': originStationId,
      if (originStationName != null) 'origin_station_name': originStationName,
      if (originLineId != null) 'origin_line_id': originLineId,
      if (originLineName != null) 'origin_line_name': originLineName,
      if (originLineColor != null) 'origin_line_color': originLineColor,
      if (originStationCode != null) 'origin_station_code': originStationCode,
      if (waypointStationId != null) 'waypoint_station_id': waypointStationId,
      if (waypointStationName != null)
        'waypoint_station_name': waypointStationName,
      if (waypointLineId != null) 'waypoint_line_id': waypointLineId,
      if (waypointLineName != null) 'waypoint_line_name': waypointLineName,
      if (waypointLineColor != null) 'waypoint_line_color': waypointLineColor,
      if (waypointStationCode != null)
        'waypoint_station_code': waypointStationCode,
      if (destinationStationId != null)
        'destination_station_id': destinationStationId,
      if (destinationStationName != null)
        'destination_station_name': destinationStationName,
      if (destinationLineId != null) 'destination_line_id': destinationLineId,
      if (destinationLineName != null)
        'destination_line_name': destinationLineName,
      if (destinationLineColor != null)
        'destination_line_color': destinationLineColor,
      if (destinationStationCode != null)
        'destination_station_code': destinationStationCode,
      if (region != null) 'region': region,
      if (searchedAt != null) 'searched_at': searchedAt,
    });
  }

  RouteSearchHistoryCompanion copyWith({
    Value<int>? id,
    Value<String>? originStationId,
    Value<String>? originStationName,
    Value<String?>? originLineId,
    Value<String?>? originLineName,
    Value<String?>? originLineColor,
    Value<String?>? originStationCode,
    Value<String?>? waypointStationId,
    Value<String?>? waypointStationName,
    Value<String?>? waypointLineId,
    Value<String?>? waypointLineName,
    Value<String?>? waypointLineColor,
    Value<String?>? waypointStationCode,
    Value<String>? destinationStationId,
    Value<String>? destinationStationName,
    Value<String?>? destinationLineId,
    Value<String?>? destinationLineName,
    Value<String?>? destinationLineColor,
    Value<String?>? destinationStationCode,
    Value<String>? region,
    Value<DateTime>? searchedAt,
  }) {
    return RouteSearchHistoryCompanion(
      id: id ?? this.id,
      originStationId: originStationId ?? this.originStationId,
      originStationName: originStationName ?? this.originStationName,
      originLineId: originLineId ?? this.originLineId,
      originLineName: originLineName ?? this.originLineName,
      originLineColor: originLineColor ?? this.originLineColor,
      originStationCode: originStationCode ?? this.originStationCode,
      waypointStationId: waypointStationId ?? this.waypointStationId,
      waypointStationName: waypointStationName ?? this.waypointStationName,
      waypointLineId: waypointLineId ?? this.waypointLineId,
      waypointLineName: waypointLineName ?? this.waypointLineName,
      waypointLineColor: waypointLineColor ?? this.waypointLineColor,
      waypointStationCode: waypointStationCode ?? this.waypointStationCode,
      destinationStationId: destinationStationId ?? this.destinationStationId,
      destinationStationName:
          destinationStationName ?? this.destinationStationName,
      destinationLineId: destinationLineId ?? this.destinationLineId,
      destinationLineName: destinationLineName ?? this.destinationLineName,
      destinationLineColor: destinationLineColor ?? this.destinationLineColor,
      destinationStationCode:
          destinationStationCode ?? this.destinationStationCode,
      region: region ?? this.region,
      searchedAt: searchedAt ?? this.searchedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (originStationId.present) {
      map['origin_station_id'] = Variable<String>(originStationId.value);
    }
    if (originStationName.present) {
      map['origin_station_name'] = Variable<String>(originStationName.value);
    }
    if (originLineId.present) {
      map['origin_line_id'] = Variable<String>(originLineId.value);
    }
    if (originLineName.present) {
      map['origin_line_name'] = Variable<String>(originLineName.value);
    }
    if (originLineColor.present) {
      map['origin_line_color'] = Variable<String>(originLineColor.value);
    }
    if (originStationCode.present) {
      map['origin_station_code'] = Variable<String>(originStationCode.value);
    }
    if (waypointStationId.present) {
      map['waypoint_station_id'] = Variable<String>(waypointStationId.value);
    }
    if (waypointStationName.present) {
      map['waypoint_station_name'] = Variable<String>(
        waypointStationName.value,
      );
    }
    if (waypointLineId.present) {
      map['waypoint_line_id'] = Variable<String>(waypointLineId.value);
    }
    if (waypointLineName.present) {
      map['waypoint_line_name'] = Variable<String>(waypointLineName.value);
    }
    if (waypointLineColor.present) {
      map['waypoint_line_color'] = Variable<String>(waypointLineColor.value);
    }
    if (waypointStationCode.present) {
      map['waypoint_station_code'] = Variable<String>(
        waypointStationCode.value,
      );
    }
    if (destinationStationId.present) {
      map['destination_station_id'] = Variable<String>(
        destinationStationId.value,
      );
    }
    if (destinationStationName.present) {
      map['destination_station_name'] = Variable<String>(
        destinationStationName.value,
      );
    }
    if (destinationLineId.present) {
      map['destination_line_id'] = Variable<String>(destinationLineId.value);
    }
    if (destinationLineName.present) {
      map['destination_line_name'] = Variable<String>(
        destinationLineName.value,
      );
    }
    if (destinationLineColor.present) {
      map['destination_line_color'] = Variable<String>(
        destinationLineColor.value,
      );
    }
    if (destinationStationCode.present) {
      map['destination_station_code'] = Variable<String>(
        destinationStationCode.value,
      );
    }
    if (region.present) {
      map['region'] = Variable<String>(region.value);
    }
    if (searchedAt.present) {
      map['searched_at'] = Variable<DateTime>(searchedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RouteSearchHistoryCompanion(')
          ..write('id: $id, ')
          ..write('originStationId: $originStationId, ')
          ..write('originStationName: $originStationName, ')
          ..write('originLineId: $originLineId, ')
          ..write('originLineName: $originLineName, ')
          ..write('originLineColor: $originLineColor, ')
          ..write('originStationCode: $originStationCode, ')
          ..write('waypointStationId: $waypointStationId, ')
          ..write('waypointStationName: $waypointStationName, ')
          ..write('waypointLineId: $waypointLineId, ')
          ..write('waypointLineName: $waypointLineName, ')
          ..write('waypointLineColor: $waypointLineColor, ')
          ..write('waypointStationCode: $waypointStationCode, ')
          ..write('destinationStationId: $destinationStationId, ')
          ..write('destinationStationName: $destinationStationName, ')
          ..write('destinationLineId: $destinationLineId, ')
          ..write('destinationLineName: $destinationLineName, ')
          ..write('destinationLineColor: $destinationLineColor, ')
          ..write('destinationStationCode: $destinationStationCode, ')
          ..write('region: $region, ')
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
  static const VerificationMeta _publicReceiptCodeMeta = const VerificationMeta(
    'publicReceiptCode',
  );
  @override
  late final GeneratedColumn<String> publicReceiptCode =
      GeneratedColumn<String>(
        'public_receipt_code',
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
    publicReceiptCode,
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
    if (data.containsKey('public_receipt_code')) {
      context.handle(
        _publicReceiptCodeMeta,
        publicReceiptCode.isAcceptableOrUnknown(
          data['public_receipt_code']!,
          _publicReceiptCodeMeta,
        ),
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
      publicReceiptCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}public_receipt_code'],
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
  final String? publicReceiptCode;
  final String status;
  final DateTime createdAt;
  const ReportReceipt({
    required this.receiptId,
    this.reportId,
    this.publicReceiptCode,
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
    if (!nullToAbsent || publicReceiptCode != null) {
      map['public_receipt_code'] = Variable<String>(publicReceiptCode);
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
      publicReceiptCode: publicReceiptCode == null && nullToAbsent
          ? const Value.absent()
          : Value(publicReceiptCode),
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
      publicReceiptCode: serializer.fromJson<String?>(
        json['publicReceiptCode'],
      ),
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
      'publicReceiptCode': serializer.toJson<String?>(publicReceiptCode),
      'status': serializer.toJson<String>(status),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ReportReceipt copyWith({
    String? receiptId,
    Value<String?> reportId = const Value.absent(),
    Value<String?> publicReceiptCode = const Value.absent(),
    String? status,
    DateTime? createdAt,
  }) => ReportReceipt(
    receiptId: receiptId ?? this.receiptId,
    reportId: reportId.present ? reportId.value : this.reportId,
    publicReceiptCode: publicReceiptCode.present
        ? publicReceiptCode.value
        : this.publicReceiptCode,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
  );
  ReportReceipt copyWithCompanion(ReportReceiptsCompanion data) {
    return ReportReceipt(
      receiptId: data.receiptId.present ? data.receiptId.value : this.receiptId,
      reportId: data.reportId.present ? data.reportId.value : this.reportId,
      publicReceiptCode: data.publicReceiptCode.present
          ? data.publicReceiptCode.value
          : this.publicReceiptCode,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReportReceipt(')
          ..write('receiptId: $receiptId, ')
          ..write('reportId: $reportId, ')
          ..write('publicReceiptCode: $publicReceiptCode, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(receiptId, reportId, publicReceiptCode, status, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReportReceipt &&
          other.receiptId == this.receiptId &&
          other.reportId == this.reportId &&
          other.publicReceiptCode == this.publicReceiptCode &&
          other.status == this.status &&
          other.createdAt == this.createdAt);
}

class ReportReceiptsCompanion extends UpdateCompanion<ReportReceipt> {
  final Value<String> receiptId;
  final Value<String?> reportId;
  final Value<String?> publicReceiptCode;
  final Value<String> status;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ReportReceiptsCompanion({
    this.receiptId = const Value.absent(),
    this.reportId = const Value.absent(),
    this.publicReceiptCode = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReportReceiptsCompanion.insert({
    required String receiptId,
    this.reportId = const Value.absent(),
    this.publicReceiptCode = const Value.absent(),
    required String status,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : receiptId = Value(receiptId),
       status = Value(status),
       createdAt = Value(createdAt);
  static Insertable<ReportReceipt> custom({
    Expression<String>? receiptId,
    Expression<String>? reportId,
    Expression<String>? publicReceiptCode,
    Expression<String>? status,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (receiptId != null) 'receipt_id': receiptId,
      if (reportId != null) 'report_id': reportId,
      if (publicReceiptCode != null) 'public_receipt_code': publicReceiptCode,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReportReceiptsCompanion copyWith({
    Value<String>? receiptId,
    Value<String?>? reportId,
    Value<String?>? publicReceiptCode,
    Value<String>? status,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return ReportReceiptsCompanion(
      receiptId: receiptId ?? this.receiptId,
      reportId: reportId ?? this.reportId,
      publicReceiptCode: publicReceiptCode ?? this.publicReceiptCode,
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
    if (publicReceiptCode.present) {
      map['public_receipt_code'] = Variable<String>(publicReceiptCode.value);
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
          ..write('publicReceiptCode: $publicReceiptCode, ')
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
  late final $RouteSearchHistoryTable routeSearchHistory =
      $RouteSearchHistoryTable(this);
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
    routeSearchHistory,
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
      Value<String> lineId,
      required DateTime addedAt,
      Value<int> rowid,
    });
typedef $$FavoriteStationsTableUpdateCompanionBuilder =
    FavoriteStationsCompanion Function({
      Value<String> stationId,
      Value<String> lineId,
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

  ColumnFilters<String> get lineId => $composableBuilder(
    column: $table.lineId,
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

  ColumnOrderings<String> get lineId => $composableBuilder(
    column: $table.lineId,
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

  GeneratedColumn<String> get lineId =>
      $composableBuilder(column: $table.lineId, builder: (column) => column);

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
                Value<String> lineId = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FavoriteStationsCompanion(
                stationId: stationId,
                lineId: lineId,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String stationId,
                Value<String> lineId = const Value.absent(),
                required DateTime addedAt,
                Value<int> rowid = const Value.absent(),
              }) => FavoriteStationsCompanion.insert(
                stationId: stationId,
                lineId: lineId,
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
      Value<String?> region,
      Value<String?> stationId,
      Value<String?> lineId,
      Value<String?> lineName,
      Value<String?> lineColor,
      Value<String?> stationCode,
      required DateTime searchedAt,
    });
typedef $$SearchHistoryTableUpdateCompanionBuilder =
    SearchHistoryCompanion Function({
      Value<int> id,
      Value<String> query,
      Value<String?> region,
      Value<String?> stationId,
      Value<String?> lineId,
      Value<String?> lineName,
      Value<String?> lineColor,
      Value<String?> stationCode,
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

  ColumnFilters<String> get region => $composableBuilder(
    column: $table.region,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stationId => $composableBuilder(
    column: $table.stationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lineId => $composableBuilder(
    column: $table.lineId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lineName => $composableBuilder(
    column: $table.lineName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lineColor => $composableBuilder(
    column: $table.lineColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stationCode => $composableBuilder(
    column: $table.stationCode,
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

  ColumnOrderings<String> get region => $composableBuilder(
    column: $table.region,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stationId => $composableBuilder(
    column: $table.stationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lineId => $composableBuilder(
    column: $table.lineId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lineName => $composableBuilder(
    column: $table.lineName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lineColor => $composableBuilder(
    column: $table.lineColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stationCode => $composableBuilder(
    column: $table.stationCode,
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

  GeneratedColumn<String> get region =>
      $composableBuilder(column: $table.region, builder: (column) => column);

  GeneratedColumn<String> get stationId =>
      $composableBuilder(column: $table.stationId, builder: (column) => column);

  GeneratedColumn<String> get lineId =>
      $composableBuilder(column: $table.lineId, builder: (column) => column);

  GeneratedColumn<String> get lineName =>
      $composableBuilder(column: $table.lineName, builder: (column) => column);

  GeneratedColumn<String> get lineColor =>
      $composableBuilder(column: $table.lineColor, builder: (column) => column);

  GeneratedColumn<String> get stationCode => $composableBuilder(
    column: $table.stationCode,
    builder: (column) => column,
  );

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
                Value<String?> region = const Value.absent(),
                Value<String?> stationId = const Value.absent(),
                Value<String?> lineId = const Value.absent(),
                Value<String?> lineName = const Value.absent(),
                Value<String?> lineColor = const Value.absent(),
                Value<String?> stationCode = const Value.absent(),
                Value<DateTime> searchedAt = const Value.absent(),
              }) => SearchHistoryCompanion(
                id: id,
                query: query,
                region: region,
                stationId: stationId,
                lineId: lineId,
                lineName: lineName,
                lineColor: lineColor,
                stationCode: stationCode,
                searchedAt: searchedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String query,
                Value<String?> region = const Value.absent(),
                Value<String?> stationId = const Value.absent(),
                Value<String?> lineId = const Value.absent(),
                Value<String?> lineName = const Value.absent(),
                Value<String?> lineColor = const Value.absent(),
                Value<String?> stationCode = const Value.absent(),
                required DateTime searchedAt,
              }) => SearchHistoryCompanion.insert(
                id: id,
                query: query,
                region: region,
                stationId: stationId,
                lineId: lineId,
                lineName: lineName,
                lineColor: lineColor,
                stationCode: stationCode,
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
typedef $$RouteSearchHistoryTableCreateCompanionBuilder =
    RouteSearchHistoryCompanion Function({
      Value<int> id,
      required String originStationId,
      required String originStationName,
      Value<String?> originLineId,
      Value<String?> originLineName,
      Value<String?> originLineColor,
      Value<String?> originStationCode,
      Value<String?> waypointStationId,
      Value<String?> waypointStationName,
      Value<String?> waypointLineId,
      Value<String?> waypointLineName,
      Value<String?> waypointLineColor,
      Value<String?> waypointStationCode,
      required String destinationStationId,
      required String destinationStationName,
      Value<String?> destinationLineId,
      Value<String?> destinationLineName,
      Value<String?> destinationLineColor,
      Value<String?> destinationStationCode,
      required String region,
      required DateTime searchedAt,
    });
typedef $$RouteSearchHistoryTableUpdateCompanionBuilder =
    RouteSearchHistoryCompanion Function({
      Value<int> id,
      Value<String> originStationId,
      Value<String> originStationName,
      Value<String?> originLineId,
      Value<String?> originLineName,
      Value<String?> originLineColor,
      Value<String?> originStationCode,
      Value<String?> waypointStationId,
      Value<String?> waypointStationName,
      Value<String?> waypointLineId,
      Value<String?> waypointLineName,
      Value<String?> waypointLineColor,
      Value<String?> waypointStationCode,
      Value<String> destinationStationId,
      Value<String> destinationStationName,
      Value<String?> destinationLineId,
      Value<String?> destinationLineName,
      Value<String?> destinationLineColor,
      Value<String?> destinationStationCode,
      Value<String> region,
      Value<DateTime> searchedAt,
    });

class $$RouteSearchHistoryTableFilterComposer
    extends Composer<_$UserDatabase, $RouteSearchHistoryTable> {
  $$RouteSearchHistoryTableFilterComposer({
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

  ColumnFilters<String> get originStationId => $composableBuilder(
    column: $table.originStationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originStationName => $composableBuilder(
    column: $table.originStationName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originLineId => $composableBuilder(
    column: $table.originLineId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originLineName => $composableBuilder(
    column: $table.originLineName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originLineColor => $composableBuilder(
    column: $table.originLineColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originStationCode => $composableBuilder(
    column: $table.originStationCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get waypointStationId => $composableBuilder(
    column: $table.waypointStationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get waypointStationName => $composableBuilder(
    column: $table.waypointStationName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get waypointLineId => $composableBuilder(
    column: $table.waypointLineId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get waypointLineName => $composableBuilder(
    column: $table.waypointLineName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get waypointLineColor => $composableBuilder(
    column: $table.waypointLineColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get waypointStationCode => $composableBuilder(
    column: $table.waypointStationCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get destinationStationId => $composableBuilder(
    column: $table.destinationStationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get destinationStationName => $composableBuilder(
    column: $table.destinationStationName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get destinationLineId => $composableBuilder(
    column: $table.destinationLineId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get destinationLineName => $composableBuilder(
    column: $table.destinationLineName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get destinationLineColor => $composableBuilder(
    column: $table.destinationLineColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get destinationStationCode => $composableBuilder(
    column: $table.destinationStationCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get region => $composableBuilder(
    column: $table.region,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get searchedAt => $composableBuilder(
    column: $table.searchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RouteSearchHistoryTableOrderingComposer
    extends Composer<_$UserDatabase, $RouteSearchHistoryTable> {
  $$RouteSearchHistoryTableOrderingComposer({
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

  ColumnOrderings<String> get originStationId => $composableBuilder(
    column: $table.originStationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originStationName => $composableBuilder(
    column: $table.originStationName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originLineId => $composableBuilder(
    column: $table.originLineId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originLineName => $composableBuilder(
    column: $table.originLineName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originLineColor => $composableBuilder(
    column: $table.originLineColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originStationCode => $composableBuilder(
    column: $table.originStationCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get waypointStationId => $composableBuilder(
    column: $table.waypointStationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get waypointStationName => $composableBuilder(
    column: $table.waypointStationName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get waypointLineId => $composableBuilder(
    column: $table.waypointLineId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get waypointLineName => $composableBuilder(
    column: $table.waypointLineName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get waypointLineColor => $composableBuilder(
    column: $table.waypointLineColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get waypointStationCode => $composableBuilder(
    column: $table.waypointStationCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get destinationStationId => $composableBuilder(
    column: $table.destinationStationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get destinationStationName => $composableBuilder(
    column: $table.destinationStationName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get destinationLineId => $composableBuilder(
    column: $table.destinationLineId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get destinationLineName => $composableBuilder(
    column: $table.destinationLineName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get destinationLineColor => $composableBuilder(
    column: $table.destinationLineColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get destinationStationCode => $composableBuilder(
    column: $table.destinationStationCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get region => $composableBuilder(
    column: $table.region,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get searchedAt => $composableBuilder(
    column: $table.searchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RouteSearchHistoryTableAnnotationComposer
    extends Composer<_$UserDatabase, $RouteSearchHistoryTable> {
  $$RouteSearchHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get originStationId => $composableBuilder(
    column: $table.originStationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get originStationName => $composableBuilder(
    column: $table.originStationName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get originLineId => $composableBuilder(
    column: $table.originLineId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get originLineName => $composableBuilder(
    column: $table.originLineName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get originLineColor => $composableBuilder(
    column: $table.originLineColor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get originStationCode => $composableBuilder(
    column: $table.originStationCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get waypointStationId => $composableBuilder(
    column: $table.waypointStationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get waypointStationName => $composableBuilder(
    column: $table.waypointStationName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get waypointLineId => $composableBuilder(
    column: $table.waypointLineId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get waypointLineName => $composableBuilder(
    column: $table.waypointLineName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get waypointLineColor => $composableBuilder(
    column: $table.waypointLineColor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get waypointStationCode => $composableBuilder(
    column: $table.waypointStationCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get destinationStationId => $composableBuilder(
    column: $table.destinationStationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get destinationStationName => $composableBuilder(
    column: $table.destinationStationName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get destinationLineId => $composableBuilder(
    column: $table.destinationLineId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get destinationLineName => $composableBuilder(
    column: $table.destinationLineName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get destinationLineColor => $composableBuilder(
    column: $table.destinationLineColor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get destinationStationCode => $composableBuilder(
    column: $table.destinationStationCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get region =>
      $composableBuilder(column: $table.region, builder: (column) => column);

  GeneratedColumn<DateTime> get searchedAt => $composableBuilder(
    column: $table.searchedAt,
    builder: (column) => column,
  );
}

class $$RouteSearchHistoryTableTableManager
    extends
        RootTableManager<
          _$UserDatabase,
          $RouteSearchHistoryTable,
          RouteSearchHistoryData,
          $$RouteSearchHistoryTableFilterComposer,
          $$RouteSearchHistoryTableOrderingComposer,
          $$RouteSearchHistoryTableAnnotationComposer,
          $$RouteSearchHistoryTableCreateCompanionBuilder,
          $$RouteSearchHistoryTableUpdateCompanionBuilder,
          (
            RouteSearchHistoryData,
            BaseReferences<
              _$UserDatabase,
              $RouteSearchHistoryTable,
              RouteSearchHistoryData
            >,
          ),
          RouteSearchHistoryData,
          PrefetchHooks Function()
        > {
  $$RouteSearchHistoryTableTableManager(
    _$UserDatabase db,
    $RouteSearchHistoryTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RouteSearchHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RouteSearchHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RouteSearchHistoryTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> originStationId = const Value.absent(),
                Value<String> originStationName = const Value.absent(),
                Value<String?> originLineId = const Value.absent(),
                Value<String?> originLineName = const Value.absent(),
                Value<String?> originLineColor = const Value.absent(),
                Value<String?> originStationCode = const Value.absent(),
                Value<String?> waypointStationId = const Value.absent(),
                Value<String?> waypointStationName = const Value.absent(),
                Value<String?> waypointLineId = const Value.absent(),
                Value<String?> waypointLineName = const Value.absent(),
                Value<String?> waypointLineColor = const Value.absent(),
                Value<String?> waypointStationCode = const Value.absent(),
                Value<String> destinationStationId = const Value.absent(),
                Value<String> destinationStationName = const Value.absent(),
                Value<String?> destinationLineId = const Value.absent(),
                Value<String?> destinationLineName = const Value.absent(),
                Value<String?> destinationLineColor = const Value.absent(),
                Value<String?> destinationStationCode = const Value.absent(),
                Value<String> region = const Value.absent(),
                Value<DateTime> searchedAt = const Value.absent(),
              }) => RouteSearchHistoryCompanion(
                id: id,
                originStationId: originStationId,
                originStationName: originStationName,
                originLineId: originLineId,
                originLineName: originLineName,
                originLineColor: originLineColor,
                originStationCode: originStationCode,
                waypointStationId: waypointStationId,
                waypointStationName: waypointStationName,
                waypointLineId: waypointLineId,
                waypointLineName: waypointLineName,
                waypointLineColor: waypointLineColor,
                waypointStationCode: waypointStationCode,
                destinationStationId: destinationStationId,
                destinationStationName: destinationStationName,
                destinationLineId: destinationLineId,
                destinationLineName: destinationLineName,
                destinationLineColor: destinationLineColor,
                destinationStationCode: destinationStationCode,
                region: region,
                searchedAt: searchedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String originStationId,
                required String originStationName,
                Value<String?> originLineId = const Value.absent(),
                Value<String?> originLineName = const Value.absent(),
                Value<String?> originLineColor = const Value.absent(),
                Value<String?> originStationCode = const Value.absent(),
                Value<String?> waypointStationId = const Value.absent(),
                Value<String?> waypointStationName = const Value.absent(),
                Value<String?> waypointLineId = const Value.absent(),
                Value<String?> waypointLineName = const Value.absent(),
                Value<String?> waypointLineColor = const Value.absent(),
                Value<String?> waypointStationCode = const Value.absent(),
                required String destinationStationId,
                required String destinationStationName,
                Value<String?> destinationLineId = const Value.absent(),
                Value<String?> destinationLineName = const Value.absent(),
                Value<String?> destinationLineColor = const Value.absent(),
                Value<String?> destinationStationCode = const Value.absent(),
                required String region,
                required DateTime searchedAt,
              }) => RouteSearchHistoryCompanion.insert(
                id: id,
                originStationId: originStationId,
                originStationName: originStationName,
                originLineId: originLineId,
                originLineName: originLineName,
                originLineColor: originLineColor,
                originStationCode: originStationCode,
                waypointStationId: waypointStationId,
                waypointStationName: waypointStationName,
                waypointLineId: waypointLineId,
                waypointLineName: waypointLineName,
                waypointLineColor: waypointLineColor,
                waypointStationCode: waypointStationCode,
                destinationStationId: destinationStationId,
                destinationStationName: destinationStationName,
                destinationLineId: destinationLineId,
                destinationLineName: destinationLineName,
                destinationLineColor: destinationLineColor,
                destinationStationCode: destinationStationCode,
                region: region,
                searchedAt: searchedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RouteSearchHistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$UserDatabase,
      $RouteSearchHistoryTable,
      RouteSearchHistoryData,
      $$RouteSearchHistoryTableFilterComposer,
      $$RouteSearchHistoryTableOrderingComposer,
      $$RouteSearchHistoryTableAnnotationComposer,
      $$RouteSearchHistoryTableCreateCompanionBuilder,
      $$RouteSearchHistoryTableUpdateCompanionBuilder,
      (
        RouteSearchHistoryData,
        BaseReferences<
          _$UserDatabase,
          $RouteSearchHistoryTable,
          RouteSearchHistoryData
        >,
      ),
      RouteSearchHistoryData,
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
      Value<String?> publicReceiptCode,
      required String status,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$ReportReceiptsTableUpdateCompanionBuilder =
    ReportReceiptsCompanion Function({
      Value<String> receiptId,
      Value<String?> reportId,
      Value<String?> publicReceiptCode,
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

  ColumnFilters<String> get publicReceiptCode => $composableBuilder(
    column: $table.publicReceiptCode,
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

  ColumnOrderings<String> get publicReceiptCode => $composableBuilder(
    column: $table.publicReceiptCode,
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

  GeneratedColumn<String> get publicReceiptCode => $composableBuilder(
    column: $table.publicReceiptCode,
    builder: (column) => column,
  );

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
                Value<String?> publicReceiptCode = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReportReceiptsCompanion(
                receiptId: receiptId,
                reportId: reportId,
                publicReceiptCode: publicReceiptCode,
                status: status,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String receiptId,
                Value<String?> reportId = const Value.absent(),
                Value<String?> publicReceiptCode = const Value.absent(),
                required String status,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => ReportReceiptsCompanion.insert(
                receiptId: receiptId,
                reportId: reportId,
                publicReceiptCode: publicReceiptCode,
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
  $$RouteSearchHistoryTableTableManager get routeSearchHistory =>
      $$RouteSearchHistoryTableTableManager(_db, _db.routeSearchHistory);
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
