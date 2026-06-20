// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'catalog_database.dart';

// ignore_for_file: type=lint
class $CatalogMetadataTable extends CatalogMetadata
    with TableInfo<$CatalogMetadataTable, CatalogMetadataData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CatalogMetadataTable(this.attachedDatabase, [this._alias]);
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
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'catalog_metadata';
  @override
  VerificationContext validateIntegrity(
    Insertable<CatalogMetadataData> instance, {
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
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  CatalogMetadataData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CatalogMetadataData(
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
      ),
    );
  }

  @override
  $CatalogMetadataTable createAlias(String alias) {
    return $CatalogMetadataTable(attachedDatabase, alias);
  }
}

class CatalogMetadataData extends DataClass
    implements Insertable<CatalogMetadataData> {
  final String key;
  final String value;
  final DateTime? updatedAt;
  const CatalogMetadataData({
    required this.key,
    required this.value,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  CatalogMetadataCompanion toCompanion(bool nullToAbsent) {
    return CatalogMetadataCompanion(
      key: Value(key),
      value: Value(value),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory CatalogMetadataData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CatalogMetadataData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  CatalogMetadataData copyWith({
    String? key,
    String? value,
    Value<DateTime?> updatedAt = const Value.absent(),
  }) => CatalogMetadataData(
    key: key ?? this.key,
    value: value ?? this.value,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  CatalogMetadataData copyWithCompanion(CatalogMetadataCompanion data) {
    return CatalogMetadataData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CatalogMetadataData(')
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
      (other is CatalogMetadataData &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class CatalogMetadataCompanion extends UpdateCompanion<CatalogMetadataData> {
  final Value<String> key;
  final Value<String> value;
  final Value<DateTime?> updatedAt;
  final Value<int> rowid;
  const CatalogMetadataCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CatalogMetadataCompanion.insert({
    required String key,
    required String value,
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<CatalogMetadataData> custom({
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

  CatalogMetadataCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<DateTime?>? updatedAt,
    Value<int>? rowid,
  }) {
    return CatalogMetadataCompanion(
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
    return (StringBuffer('CatalogMetadataCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OperatorsTable extends Operators
    with TableInfo<$OperatorsTable, Operator> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OperatorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameKoMeta = const VerificationMeta('nameKo');
  @override
  late final GeneratedColumn<String> nameKo = GeneratedColumn<String>(
    'name_ko',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameEnMeta = const VerificationMeta('nameEn');
  @override
  late final GeneratedColumn<String> nameEn = GeneratedColumn<String>(
    'name_en',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [id, nameKo, nameEn];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'operators';
  @override
  VerificationContext validateIntegrity(
    Insertable<Operator> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name_ko')) {
      context.handle(
        _nameKoMeta,
        nameKo.isAcceptableOrUnknown(data['name_ko']!, _nameKoMeta),
      );
    } else if (isInserting) {
      context.missing(_nameKoMeta);
    }
    if (data.containsKey('name_en')) {
      context.handle(
        _nameEnMeta,
        nameEn.isAcceptableOrUnknown(data['name_en']!, _nameEnMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Operator map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Operator(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      nameKo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_ko'],
      )!,
      nameEn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_en'],
      )!,
    );
  }

  @override
  $OperatorsTable createAlias(String alias) {
    return $OperatorsTable(attachedDatabase, alias);
  }
}

class Operator extends DataClass implements Insertable<Operator> {
  final String id;
  final String nameKo;
  final String nameEn;
  const Operator({
    required this.id,
    required this.nameKo,
    required this.nameEn,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name_ko'] = Variable<String>(nameKo);
    map['name_en'] = Variable<String>(nameEn);
    return map;
  }

  OperatorsCompanion toCompanion(bool nullToAbsent) {
    return OperatorsCompanion(
      id: Value(id),
      nameKo: Value(nameKo),
      nameEn: Value(nameEn),
    );
  }

  factory Operator.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Operator(
      id: serializer.fromJson<String>(json['id']),
      nameKo: serializer.fromJson<String>(json['nameKo']),
      nameEn: serializer.fromJson<String>(json['nameEn']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'nameKo': serializer.toJson<String>(nameKo),
      'nameEn': serializer.toJson<String>(nameEn),
    };
  }

  Operator copyWith({String? id, String? nameKo, String? nameEn}) => Operator(
    id: id ?? this.id,
    nameKo: nameKo ?? this.nameKo,
    nameEn: nameEn ?? this.nameEn,
  );
  Operator copyWithCompanion(OperatorsCompanion data) {
    return Operator(
      id: data.id.present ? data.id.value : this.id,
      nameKo: data.nameKo.present ? data.nameKo.value : this.nameKo,
      nameEn: data.nameEn.present ? data.nameEn.value : this.nameEn,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Operator(')
          ..write('id: $id, ')
          ..write('nameKo: $nameKo, ')
          ..write('nameEn: $nameEn')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, nameKo, nameEn);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Operator &&
          other.id == this.id &&
          other.nameKo == this.nameKo &&
          other.nameEn == this.nameEn);
}

class OperatorsCompanion extends UpdateCompanion<Operator> {
  final Value<String> id;
  final Value<String> nameKo;
  final Value<String> nameEn;
  final Value<int> rowid;
  const OperatorsCompanion({
    this.id = const Value.absent(),
    this.nameKo = const Value.absent(),
    this.nameEn = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OperatorsCompanion.insert({
    required String id,
    required String nameKo,
    this.nameEn = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       nameKo = Value(nameKo);
  static Insertable<Operator> custom({
    Expression<String>? id,
    Expression<String>? nameKo,
    Expression<String>? nameEn,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (nameKo != null) 'name_ko': nameKo,
      if (nameEn != null) 'name_en': nameEn,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OperatorsCompanion copyWith({
    Value<String>? id,
    Value<String>? nameKo,
    Value<String>? nameEn,
    Value<int>? rowid,
  }) {
    return OperatorsCompanion(
      id: id ?? this.id,
      nameKo: nameKo ?? this.nameKo,
      nameEn: nameEn ?? this.nameEn,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (nameKo.present) {
      map['name_ko'] = Variable<String>(nameKo.value);
    }
    if (nameEn.present) {
      map['name_en'] = Variable<String>(nameEn.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OperatorsCompanion(')
          ..write('id: $id, ')
          ..write('nameKo: $nameKo, ')
          ..write('nameEn: $nameEn, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LinesTable extends Lines with TableInfo<$LinesTable, Line> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LinesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operatorIdMeta = const VerificationMeta(
    'operatorId',
  );
  @override
  late final GeneratedColumn<String> operatorId = GeneratedColumn<String>(
    'operator_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameKoMeta = const VerificationMeta('nameKo');
  @override
  late final GeneratedColumn<String> nameKo = GeneratedColumn<String>(
    'name_ko',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameEnMeta = const VerificationMeta('nameEn');
  @override
  late final GeneratedColumn<String> nameEn = GeneratedColumn<String>(
    'name_en',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [id, operatorId, nameKo, nameEn, color];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'lines';
  @override
  VerificationContext validateIntegrity(
    Insertable<Line> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('operator_id')) {
      context.handle(
        _operatorIdMeta,
        operatorId.isAcceptableOrUnknown(data['operator_id']!, _operatorIdMeta),
      );
    } else if (isInserting) {
      context.missing(_operatorIdMeta);
    }
    if (data.containsKey('name_ko')) {
      context.handle(
        _nameKoMeta,
        nameKo.isAcceptableOrUnknown(data['name_ko']!, _nameKoMeta),
      );
    } else if (isInserting) {
      context.missing(_nameKoMeta);
    }
    if (data.containsKey('name_en')) {
      context.handle(
        _nameEnMeta,
        nameEn.isAcceptableOrUnknown(data['name_en']!, _nameEnMeta),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Line map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Line(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      operatorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operator_id'],
      )!,
      nameKo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_ko'],
      )!,
      nameEn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_en'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      )!,
    );
  }

  @override
  $LinesTable createAlias(String alias) {
    return $LinesTable(attachedDatabase, alias);
  }
}

class Line extends DataClass implements Insertable<Line> {
  final String id;
  final String operatorId;
  final String nameKo;
  final String nameEn;
  final String color;
  const Line({
    required this.id,
    required this.operatorId,
    required this.nameKo,
    required this.nameEn,
    required this.color,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['operator_id'] = Variable<String>(operatorId);
    map['name_ko'] = Variable<String>(nameKo);
    map['name_en'] = Variable<String>(nameEn);
    map['color'] = Variable<String>(color);
    return map;
  }

  LinesCompanion toCompanion(bool nullToAbsent) {
    return LinesCompanion(
      id: Value(id),
      operatorId: Value(operatorId),
      nameKo: Value(nameKo),
      nameEn: Value(nameEn),
      color: Value(color),
    );
  }

  factory Line.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Line(
      id: serializer.fromJson<String>(json['id']),
      operatorId: serializer.fromJson<String>(json['operatorId']),
      nameKo: serializer.fromJson<String>(json['nameKo']),
      nameEn: serializer.fromJson<String>(json['nameEn']),
      color: serializer.fromJson<String>(json['color']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'operatorId': serializer.toJson<String>(operatorId),
      'nameKo': serializer.toJson<String>(nameKo),
      'nameEn': serializer.toJson<String>(nameEn),
      'color': serializer.toJson<String>(color),
    };
  }

  Line copyWith({
    String? id,
    String? operatorId,
    String? nameKo,
    String? nameEn,
    String? color,
  }) => Line(
    id: id ?? this.id,
    operatorId: operatorId ?? this.operatorId,
    nameKo: nameKo ?? this.nameKo,
    nameEn: nameEn ?? this.nameEn,
    color: color ?? this.color,
  );
  Line copyWithCompanion(LinesCompanion data) {
    return Line(
      id: data.id.present ? data.id.value : this.id,
      operatorId: data.operatorId.present
          ? data.operatorId.value
          : this.operatorId,
      nameKo: data.nameKo.present ? data.nameKo.value : this.nameKo,
      nameEn: data.nameEn.present ? data.nameEn.value : this.nameEn,
      color: data.color.present ? data.color.value : this.color,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Line(')
          ..write('id: $id, ')
          ..write('operatorId: $operatorId, ')
          ..write('nameKo: $nameKo, ')
          ..write('nameEn: $nameEn, ')
          ..write('color: $color')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, operatorId, nameKo, nameEn, color);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Line &&
          other.id == this.id &&
          other.operatorId == this.operatorId &&
          other.nameKo == this.nameKo &&
          other.nameEn == this.nameEn &&
          other.color == this.color);
}

class LinesCompanion extends UpdateCompanion<Line> {
  final Value<String> id;
  final Value<String> operatorId;
  final Value<String> nameKo;
  final Value<String> nameEn;
  final Value<String> color;
  final Value<int> rowid;
  const LinesCompanion({
    this.id = const Value.absent(),
    this.operatorId = const Value.absent(),
    this.nameKo = const Value.absent(),
    this.nameEn = const Value.absent(),
    this.color = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LinesCompanion.insert({
    required String id,
    required String operatorId,
    required String nameKo,
    this.nameEn = const Value.absent(),
    this.color = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       operatorId = Value(operatorId),
       nameKo = Value(nameKo);
  static Insertable<Line> custom({
    Expression<String>? id,
    Expression<String>? operatorId,
    Expression<String>? nameKo,
    Expression<String>? nameEn,
    Expression<String>? color,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (operatorId != null) 'operator_id': operatorId,
      if (nameKo != null) 'name_ko': nameKo,
      if (nameEn != null) 'name_en': nameEn,
      if (color != null) 'color': color,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LinesCompanion copyWith({
    Value<String>? id,
    Value<String>? operatorId,
    Value<String>? nameKo,
    Value<String>? nameEn,
    Value<String>? color,
    Value<int>? rowid,
  }) {
    return LinesCompanion(
      id: id ?? this.id,
      operatorId: operatorId ?? this.operatorId,
      nameKo: nameKo ?? this.nameKo,
      nameEn: nameEn ?? this.nameEn,
      color: color ?? this.color,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (operatorId.present) {
      map['operator_id'] = Variable<String>(operatorId.value);
    }
    if (nameKo.present) {
      map['name_ko'] = Variable<String>(nameKo.value);
    }
    if (nameEn.present) {
      map['name_en'] = Variable<String>(nameEn.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LinesCompanion(')
          ..write('id: $id, ')
          ..write('operatorId: $operatorId, ')
          ..write('nameKo: $nameKo, ')
          ..write('nameEn: $nameEn, ')
          ..write('color: $color, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StationsTable extends Stations with TableInfo<$StationsTable, Station> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameKoMeta = const VerificationMeta('nameKo');
  @override
  late final GeneratedColumn<String> nameKo = GeneratedColumn<String>(
    'name_ko',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameEnMeta = const VerificationMeta('nameEn');
  @override
  late final GeneratedColumn<String> nameEn = GeneratedColumn<String>(
    'name_en',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _normalizedNameMeta = const VerificationMeta(
    'normalizedName',
  );
  @override
  late final GeneratedColumn<String> normalizedName = GeneratedColumn<String>(
    'normalized_name',
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
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dataQualityLevelMeta = const VerificationMeta(
    'dataQualityLevel',
  );
  @override
  late final GeneratedColumn<String> dataQualityLevel = GeneratedColumn<String>(
    'data_quality_level',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('LEVEL_1'),
  );
  static const VerificationMeta _dataSourceTypeMeta = const VerificationMeta(
    'dataSourceType',
  );
  @override
  late final GeneratedColumn<String> dataSourceType = GeneratedColumn<String>(
    'data_source_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('OFFICIAL_FILE'),
  );
  static const VerificationMeta _lastVerifiedAtMeta = const VerificationMeta(
    'lastVerifiedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastVerifiedAt =
      GeneratedColumn<DateTime>(
        'last_verified_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    nameKo,
    nameEn,
    normalizedName,
    region,
    latitude,
    longitude,
    dataQualityLevel,
    dataSourceType,
    lastVerifiedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stations';
  @override
  VerificationContext validateIntegrity(
    Insertable<Station> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name_ko')) {
      context.handle(
        _nameKoMeta,
        nameKo.isAcceptableOrUnknown(data['name_ko']!, _nameKoMeta),
      );
    } else if (isInserting) {
      context.missing(_nameKoMeta);
    }
    if (data.containsKey('name_en')) {
      context.handle(
        _nameEnMeta,
        nameEn.isAcceptableOrUnknown(data['name_en']!, _nameEnMeta),
      );
    }
    if (data.containsKey('normalized_name')) {
      context.handle(
        _normalizedNameMeta,
        normalizedName.isAcceptableOrUnknown(
          data['normalized_name']!,
          _normalizedNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_normalizedNameMeta);
    }
    if (data.containsKey('region')) {
      context.handle(
        _regionMeta,
        region.isAcceptableOrUnknown(data['region']!, _regionMeta),
      );
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    }
    if (data.containsKey('data_quality_level')) {
      context.handle(
        _dataQualityLevelMeta,
        dataQualityLevel.isAcceptableOrUnknown(
          data['data_quality_level']!,
          _dataQualityLevelMeta,
        ),
      );
    }
    if (data.containsKey('data_source_type')) {
      context.handle(
        _dataSourceTypeMeta,
        dataSourceType.isAcceptableOrUnknown(
          data['data_source_type']!,
          _dataSourceTypeMeta,
        ),
      );
    }
    if (data.containsKey('last_verified_at')) {
      context.handle(
        _lastVerifiedAtMeta,
        lastVerifiedAt.isAcceptableOrUnknown(
          data['last_verified_at']!,
          _lastVerifiedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Station map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Station(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      nameKo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_ko'],
      )!,
      nameEn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_en'],
      )!,
      normalizedName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}normalized_name'],
      )!,
      region: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}region'],
      )!,
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      ),
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      ),
      dataQualityLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data_quality_level'],
      )!,
      dataSourceType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data_source_type'],
      )!,
      lastVerifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_verified_at'],
      ),
    );
  }

  @override
  $StationsTable createAlias(String alias) {
    return $StationsTable(attachedDatabase, alias);
  }
}

class Station extends DataClass implements Insertable<Station> {
  final String id;
  final String nameKo;
  final String nameEn;
  final String normalizedName;
  final String region;
  final double? latitude;
  final double? longitude;
  final String dataQualityLevel;
  final String dataSourceType;
  final DateTime? lastVerifiedAt;
  const Station({
    required this.id,
    required this.nameKo,
    required this.nameEn,
    required this.normalizedName,
    required this.region,
    this.latitude,
    this.longitude,
    required this.dataQualityLevel,
    required this.dataSourceType,
    this.lastVerifiedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name_ko'] = Variable<String>(nameKo);
    map['name_en'] = Variable<String>(nameEn);
    map['normalized_name'] = Variable<String>(normalizedName);
    map['region'] = Variable<String>(region);
    if (!nullToAbsent || latitude != null) {
      map['latitude'] = Variable<double>(latitude);
    }
    if (!nullToAbsent || longitude != null) {
      map['longitude'] = Variable<double>(longitude);
    }
    map['data_quality_level'] = Variable<String>(dataQualityLevel);
    map['data_source_type'] = Variable<String>(dataSourceType);
    if (!nullToAbsent || lastVerifiedAt != null) {
      map['last_verified_at'] = Variable<DateTime>(lastVerifiedAt);
    }
    return map;
  }

  StationsCompanion toCompanion(bool nullToAbsent) {
    return StationsCompanion(
      id: Value(id),
      nameKo: Value(nameKo),
      nameEn: Value(nameEn),
      normalizedName: Value(normalizedName),
      region: Value(region),
      latitude: latitude == null && nullToAbsent
          ? const Value.absent()
          : Value(latitude),
      longitude: longitude == null && nullToAbsent
          ? const Value.absent()
          : Value(longitude),
      dataQualityLevel: Value(dataQualityLevel),
      dataSourceType: Value(dataSourceType),
      lastVerifiedAt: lastVerifiedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastVerifiedAt),
    );
  }

  factory Station.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Station(
      id: serializer.fromJson<String>(json['id']),
      nameKo: serializer.fromJson<String>(json['nameKo']),
      nameEn: serializer.fromJson<String>(json['nameEn']),
      normalizedName: serializer.fromJson<String>(json['normalizedName']),
      region: serializer.fromJson<String>(json['region']),
      latitude: serializer.fromJson<double?>(json['latitude']),
      longitude: serializer.fromJson<double?>(json['longitude']),
      dataQualityLevel: serializer.fromJson<String>(json['dataQualityLevel']),
      dataSourceType: serializer.fromJson<String>(json['dataSourceType']),
      lastVerifiedAt: serializer.fromJson<DateTime?>(json['lastVerifiedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'nameKo': serializer.toJson<String>(nameKo),
      'nameEn': serializer.toJson<String>(nameEn),
      'normalizedName': serializer.toJson<String>(normalizedName),
      'region': serializer.toJson<String>(region),
      'latitude': serializer.toJson<double?>(latitude),
      'longitude': serializer.toJson<double?>(longitude),
      'dataQualityLevel': serializer.toJson<String>(dataQualityLevel),
      'dataSourceType': serializer.toJson<String>(dataSourceType),
      'lastVerifiedAt': serializer.toJson<DateTime?>(lastVerifiedAt),
    };
  }

  Station copyWith({
    String? id,
    String? nameKo,
    String? nameEn,
    String? normalizedName,
    String? region,
    Value<double?> latitude = const Value.absent(),
    Value<double?> longitude = const Value.absent(),
    String? dataQualityLevel,
    String? dataSourceType,
    Value<DateTime?> lastVerifiedAt = const Value.absent(),
  }) => Station(
    id: id ?? this.id,
    nameKo: nameKo ?? this.nameKo,
    nameEn: nameEn ?? this.nameEn,
    normalizedName: normalizedName ?? this.normalizedName,
    region: region ?? this.region,
    latitude: latitude.present ? latitude.value : this.latitude,
    longitude: longitude.present ? longitude.value : this.longitude,
    dataQualityLevel: dataQualityLevel ?? this.dataQualityLevel,
    dataSourceType: dataSourceType ?? this.dataSourceType,
    lastVerifiedAt: lastVerifiedAt.present
        ? lastVerifiedAt.value
        : this.lastVerifiedAt,
  );
  Station copyWithCompanion(StationsCompanion data) {
    return Station(
      id: data.id.present ? data.id.value : this.id,
      nameKo: data.nameKo.present ? data.nameKo.value : this.nameKo,
      nameEn: data.nameEn.present ? data.nameEn.value : this.nameEn,
      normalizedName: data.normalizedName.present
          ? data.normalizedName.value
          : this.normalizedName,
      region: data.region.present ? data.region.value : this.region,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      dataQualityLevel: data.dataQualityLevel.present
          ? data.dataQualityLevel.value
          : this.dataQualityLevel,
      dataSourceType: data.dataSourceType.present
          ? data.dataSourceType.value
          : this.dataSourceType,
      lastVerifiedAt: data.lastVerifiedAt.present
          ? data.lastVerifiedAt.value
          : this.lastVerifiedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Station(')
          ..write('id: $id, ')
          ..write('nameKo: $nameKo, ')
          ..write('nameEn: $nameEn, ')
          ..write('normalizedName: $normalizedName, ')
          ..write('region: $region, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('dataQualityLevel: $dataQualityLevel, ')
          ..write('dataSourceType: $dataSourceType, ')
          ..write('lastVerifiedAt: $lastVerifiedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    nameKo,
    nameEn,
    normalizedName,
    region,
    latitude,
    longitude,
    dataQualityLevel,
    dataSourceType,
    lastVerifiedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Station &&
          other.id == this.id &&
          other.nameKo == this.nameKo &&
          other.nameEn == this.nameEn &&
          other.normalizedName == this.normalizedName &&
          other.region == this.region &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.dataQualityLevel == this.dataQualityLevel &&
          other.dataSourceType == this.dataSourceType &&
          other.lastVerifiedAt == this.lastVerifiedAt);
}

class StationsCompanion extends UpdateCompanion<Station> {
  final Value<String> id;
  final Value<String> nameKo;
  final Value<String> nameEn;
  final Value<String> normalizedName;
  final Value<String> region;
  final Value<double?> latitude;
  final Value<double?> longitude;
  final Value<String> dataQualityLevel;
  final Value<String> dataSourceType;
  final Value<DateTime?> lastVerifiedAt;
  final Value<int> rowid;
  const StationsCompanion({
    this.id = const Value.absent(),
    this.nameKo = const Value.absent(),
    this.nameEn = const Value.absent(),
    this.normalizedName = const Value.absent(),
    this.region = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.dataQualityLevel = const Value.absent(),
    this.dataSourceType = const Value.absent(),
    this.lastVerifiedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StationsCompanion.insert({
    required String id,
    required String nameKo,
    this.nameEn = const Value.absent(),
    required String normalizedName,
    this.region = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.dataQualityLevel = const Value.absent(),
    this.dataSourceType = const Value.absent(),
    this.lastVerifiedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       nameKo = Value(nameKo),
       normalizedName = Value(normalizedName);
  static Insertable<Station> custom({
    Expression<String>? id,
    Expression<String>? nameKo,
    Expression<String>? nameEn,
    Expression<String>? normalizedName,
    Expression<String>? region,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<String>? dataQualityLevel,
    Expression<String>? dataSourceType,
    Expression<DateTime>? lastVerifiedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (nameKo != null) 'name_ko': nameKo,
      if (nameEn != null) 'name_en': nameEn,
      if (normalizedName != null) 'normalized_name': normalizedName,
      if (region != null) 'region': region,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (dataQualityLevel != null) 'data_quality_level': dataQualityLevel,
      if (dataSourceType != null) 'data_source_type': dataSourceType,
      if (lastVerifiedAt != null) 'last_verified_at': lastVerifiedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StationsCompanion copyWith({
    Value<String>? id,
    Value<String>? nameKo,
    Value<String>? nameEn,
    Value<String>? normalizedName,
    Value<String>? region,
    Value<double?>? latitude,
    Value<double?>? longitude,
    Value<String>? dataQualityLevel,
    Value<String>? dataSourceType,
    Value<DateTime?>? lastVerifiedAt,
    Value<int>? rowid,
  }) {
    return StationsCompanion(
      id: id ?? this.id,
      nameKo: nameKo ?? this.nameKo,
      nameEn: nameEn ?? this.nameEn,
      normalizedName: normalizedName ?? this.normalizedName,
      region: region ?? this.region,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      dataQualityLevel: dataQualityLevel ?? this.dataQualityLevel,
      dataSourceType: dataSourceType ?? this.dataSourceType,
      lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (nameKo.present) {
      map['name_ko'] = Variable<String>(nameKo.value);
    }
    if (nameEn.present) {
      map['name_en'] = Variable<String>(nameEn.value);
    }
    if (normalizedName.present) {
      map['normalized_name'] = Variable<String>(normalizedName.value);
    }
    if (region.present) {
      map['region'] = Variable<String>(region.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (dataQualityLevel.present) {
      map['data_quality_level'] = Variable<String>(dataQualityLevel.value);
    }
    if (dataSourceType.present) {
      map['data_source_type'] = Variable<String>(dataSourceType.value);
    }
    if (lastVerifiedAt.present) {
      map['last_verified_at'] = Variable<DateTime>(lastVerifiedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StationsCompanion(')
          ..write('id: $id, ')
          ..write('nameKo: $nameKo, ')
          ..write('nameEn: $nameEn, ')
          ..write('normalizedName: $normalizedName, ')
          ..write('region: $region, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('dataQualityLevel: $dataQualityLevel, ')
          ..write('dataSourceType: $dataSourceType, ')
          ..write('lastVerifiedAt: $lastVerifiedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StationAliasesTable extends StationAliases
    with TableInfo<$StationAliasesTable, StationAliase> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StationAliasesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _aliasMeta = const VerificationMeta('alias');
  @override
  late final GeneratedColumn<String> alias = GeneratedColumn<String>(
    'alias',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _normalizedAliasMeta = const VerificationMeta(
    'normalizedAlias',
  );
  @override
  late final GeneratedColumn<String> normalizedAlias = GeneratedColumn<String>(
    'normalized_alias',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [stationId, alias, normalizedAlias];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'station_aliases';
  @override
  VerificationContext validateIntegrity(
    Insertable<StationAliase> instance, {
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
    if (data.containsKey('alias')) {
      context.handle(
        _aliasMeta,
        alias.isAcceptableOrUnknown(data['alias']!, _aliasMeta),
      );
    } else if (isInserting) {
      context.missing(_aliasMeta);
    }
    if (data.containsKey('normalized_alias')) {
      context.handle(
        _normalizedAliasMeta,
        normalizedAlias.isAcceptableOrUnknown(
          data['normalized_alias']!,
          _normalizedAliasMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_normalizedAliasMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => const {};
  @override
  StationAliase map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StationAliase(
      stationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}station_id'],
      )!,
      alias: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}alias'],
      )!,
      normalizedAlias: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}normalized_alias'],
      )!,
    );
  }

  @override
  $StationAliasesTable createAlias(String alias) {
    return $StationAliasesTable(attachedDatabase, alias);
  }
}

class StationAliase extends DataClass implements Insertable<StationAliase> {
  final String stationId;
  final String alias;
  final String normalizedAlias;
  const StationAliase({
    required this.stationId,
    required this.alias,
    required this.normalizedAlias,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['station_id'] = Variable<String>(stationId);
    map['alias'] = Variable<String>(alias);
    map['normalized_alias'] = Variable<String>(normalizedAlias);
    return map;
  }

  StationAliasesCompanion toCompanion(bool nullToAbsent) {
    return StationAliasesCompanion(
      stationId: Value(stationId),
      alias: Value(alias),
      normalizedAlias: Value(normalizedAlias),
    );
  }

  factory StationAliase.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StationAliase(
      stationId: serializer.fromJson<String>(json['stationId']),
      alias: serializer.fromJson<String>(json['alias']),
      normalizedAlias: serializer.fromJson<String>(json['normalizedAlias']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'stationId': serializer.toJson<String>(stationId),
      'alias': serializer.toJson<String>(alias),
      'normalizedAlias': serializer.toJson<String>(normalizedAlias),
    };
  }

  StationAliase copyWith({
    String? stationId,
    String? alias,
    String? normalizedAlias,
  }) => StationAliase(
    stationId: stationId ?? this.stationId,
    alias: alias ?? this.alias,
    normalizedAlias: normalizedAlias ?? this.normalizedAlias,
  );
  StationAliase copyWithCompanion(StationAliasesCompanion data) {
    return StationAliase(
      stationId: data.stationId.present ? data.stationId.value : this.stationId,
      alias: data.alias.present ? data.alias.value : this.alias,
      normalizedAlias: data.normalizedAlias.present
          ? data.normalizedAlias.value
          : this.normalizedAlias,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StationAliase(')
          ..write('stationId: $stationId, ')
          ..write('alias: $alias, ')
          ..write('normalizedAlias: $normalizedAlias')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(stationId, alias, normalizedAlias);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StationAliase &&
          other.stationId == this.stationId &&
          other.alias == this.alias &&
          other.normalizedAlias == this.normalizedAlias);
}

class StationAliasesCompanion extends UpdateCompanion<StationAliase> {
  final Value<String> stationId;
  final Value<String> alias;
  final Value<String> normalizedAlias;
  final Value<int> rowid;
  const StationAliasesCompanion({
    this.stationId = const Value.absent(),
    this.alias = const Value.absent(),
    this.normalizedAlias = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StationAliasesCompanion.insert({
    required String stationId,
    required String alias,
    required String normalizedAlias,
    this.rowid = const Value.absent(),
  }) : stationId = Value(stationId),
       alias = Value(alias),
       normalizedAlias = Value(normalizedAlias);
  static Insertable<StationAliase> custom({
    Expression<String>? stationId,
    Expression<String>? alias,
    Expression<String>? normalizedAlias,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (stationId != null) 'station_id': stationId,
      if (alias != null) 'alias': alias,
      if (normalizedAlias != null) 'normalized_alias': normalizedAlias,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StationAliasesCompanion copyWith({
    Value<String>? stationId,
    Value<String>? alias,
    Value<String>? normalizedAlias,
    Value<int>? rowid,
  }) {
    return StationAliasesCompanion(
      stationId: stationId ?? this.stationId,
      alias: alias ?? this.alias,
      normalizedAlias: normalizedAlias ?? this.normalizedAlias,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (stationId.present) {
      map['station_id'] = Variable<String>(stationId.value);
    }
    if (alias.present) {
      map['alias'] = Variable<String>(alias.value);
    }
    if (normalizedAlias.present) {
      map['normalized_alias'] = Variable<String>(normalizedAlias.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StationAliasesCompanion(')
          ..write('stationId: $stationId, ')
          ..write('alias: $alias, ')
          ..write('normalizedAlias: $normalizedAlias, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StationLinesTable extends StationLines
    with TableInfo<$StationLinesTable, StationLine> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StationLinesTable(this.attachedDatabase, [this._alias]);
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
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stationCodeMeta = const VerificationMeta(
    'stationCode',
  );
  @override
  late final GeneratedColumn<String> stationCode = GeneratedColumn<String>(
    'station_code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _lineSequenceMeta = const VerificationMeta(
    'lineSequence',
  );
  @override
  late final GeneratedColumn<int> lineSequence = GeneratedColumn<int>(
    'line_sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _platformInfoMeta = const VerificationMeta(
    'platformInfo',
  );
  @override
  late final GeneratedColumn<String> platformInfo = GeneratedColumn<String>(
    'platform_info',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    stationId,
    lineId,
    stationCode,
    lineSequence,
    platformInfo,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'station_lines';
  @override
  VerificationContext validateIntegrity(
    Insertable<StationLine> instance, {
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
    } else if (isInserting) {
      context.missing(_lineIdMeta);
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
    if (data.containsKey('line_sequence')) {
      context.handle(
        _lineSequenceMeta,
        lineSequence.isAcceptableOrUnknown(
          data['line_sequence']!,
          _lineSequenceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lineSequenceMeta);
    }
    if (data.containsKey('platform_info')) {
      context.handle(
        _platformInfoMeta,
        platformInfo.isAcceptableOrUnknown(
          data['platform_info']!,
          _platformInfoMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {stationId, lineId};
  @override
  StationLine map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StationLine(
      stationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}station_id'],
      )!,
      lineId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}line_id'],
      )!,
      stationCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}station_code'],
      )!,
      lineSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}line_sequence'],
      )!,
      platformInfo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}platform_info'],
      )!,
    );
  }

  @override
  $StationLinesTable createAlias(String alias) {
    return $StationLinesTable(attachedDatabase, alias);
  }
}

class StationLine extends DataClass implements Insertable<StationLine> {
  final String stationId;
  final String lineId;
  final String stationCode;
  final int lineSequence;
  final String platformInfo;
  const StationLine({
    required this.stationId,
    required this.lineId,
    required this.stationCode,
    required this.lineSequence,
    required this.platformInfo,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['station_id'] = Variable<String>(stationId);
    map['line_id'] = Variable<String>(lineId);
    map['station_code'] = Variable<String>(stationCode);
    map['line_sequence'] = Variable<int>(lineSequence);
    map['platform_info'] = Variable<String>(platformInfo);
    return map;
  }

  StationLinesCompanion toCompanion(bool nullToAbsent) {
    return StationLinesCompanion(
      stationId: Value(stationId),
      lineId: Value(lineId),
      stationCode: Value(stationCode),
      lineSequence: Value(lineSequence),
      platformInfo: Value(platformInfo),
    );
  }

  factory StationLine.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StationLine(
      stationId: serializer.fromJson<String>(json['stationId']),
      lineId: serializer.fromJson<String>(json['lineId']),
      stationCode: serializer.fromJson<String>(json['stationCode']),
      lineSequence: serializer.fromJson<int>(json['lineSequence']),
      platformInfo: serializer.fromJson<String>(json['platformInfo']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'stationId': serializer.toJson<String>(stationId),
      'lineId': serializer.toJson<String>(lineId),
      'stationCode': serializer.toJson<String>(stationCode),
      'lineSequence': serializer.toJson<int>(lineSequence),
      'platformInfo': serializer.toJson<String>(platformInfo),
    };
  }

  StationLine copyWith({
    String? stationId,
    String? lineId,
    String? stationCode,
    int? lineSequence,
    String? platformInfo,
  }) => StationLine(
    stationId: stationId ?? this.stationId,
    lineId: lineId ?? this.lineId,
    stationCode: stationCode ?? this.stationCode,
    lineSequence: lineSequence ?? this.lineSequence,
    platformInfo: platformInfo ?? this.platformInfo,
  );
  StationLine copyWithCompanion(StationLinesCompanion data) {
    return StationLine(
      stationId: data.stationId.present ? data.stationId.value : this.stationId,
      lineId: data.lineId.present ? data.lineId.value : this.lineId,
      stationCode: data.stationCode.present
          ? data.stationCode.value
          : this.stationCode,
      lineSequence: data.lineSequence.present
          ? data.lineSequence.value
          : this.lineSequence,
      platformInfo: data.platformInfo.present
          ? data.platformInfo.value
          : this.platformInfo,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StationLine(')
          ..write('stationId: $stationId, ')
          ..write('lineId: $lineId, ')
          ..write('stationCode: $stationCode, ')
          ..write('lineSequence: $lineSequence, ')
          ..write('platformInfo: $platformInfo')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(stationId, lineId, stationCode, lineSequence, platformInfo);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StationLine &&
          other.stationId == this.stationId &&
          other.lineId == this.lineId &&
          other.stationCode == this.stationCode &&
          other.lineSequence == this.lineSequence &&
          other.platformInfo == this.platformInfo);
}

class StationLinesCompanion extends UpdateCompanion<StationLine> {
  final Value<String> stationId;
  final Value<String> lineId;
  final Value<String> stationCode;
  final Value<int> lineSequence;
  final Value<String> platformInfo;
  final Value<int> rowid;
  const StationLinesCompanion({
    this.stationId = const Value.absent(),
    this.lineId = const Value.absent(),
    this.stationCode = const Value.absent(),
    this.lineSequence = const Value.absent(),
    this.platformInfo = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StationLinesCompanion.insert({
    required String stationId,
    required String lineId,
    this.stationCode = const Value.absent(),
    required int lineSequence,
    this.platformInfo = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : stationId = Value(stationId),
       lineId = Value(lineId),
       lineSequence = Value(lineSequence);
  static Insertable<StationLine> custom({
    Expression<String>? stationId,
    Expression<String>? lineId,
    Expression<String>? stationCode,
    Expression<int>? lineSequence,
    Expression<String>? platformInfo,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (stationId != null) 'station_id': stationId,
      if (lineId != null) 'line_id': lineId,
      if (stationCode != null) 'station_code': stationCode,
      if (lineSequence != null) 'line_sequence': lineSequence,
      if (platformInfo != null) 'platform_info': platformInfo,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StationLinesCompanion copyWith({
    Value<String>? stationId,
    Value<String>? lineId,
    Value<String>? stationCode,
    Value<int>? lineSequence,
    Value<String>? platformInfo,
    Value<int>? rowid,
  }) {
    return StationLinesCompanion(
      stationId: stationId ?? this.stationId,
      lineId: lineId ?? this.lineId,
      stationCode: stationCode ?? this.stationCode,
      lineSequence: lineSequence ?? this.lineSequence,
      platformInfo: platformInfo ?? this.platformInfo,
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
    if (stationCode.present) {
      map['station_code'] = Variable<String>(stationCode.value);
    }
    if (lineSequence.present) {
      map['line_sequence'] = Variable<int>(lineSequence.value);
    }
    if (platformInfo.present) {
      map['platform_info'] = Variable<String>(platformInfo.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StationLinesCompanion(')
          ..write('stationId: $stationId, ')
          ..write('lineId: $lineId, ')
          ..write('stationCode: $stationCode, ')
          ..write('lineSequence: $lineSequence, ')
          ..write('platformInfo: $platformInfo, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NetworkEdgesTable extends NetworkEdges
    with TableInfo<$NetworkEdgesTable, NetworkEdge> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NetworkEdgesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fromNodeIdMeta = const VerificationMeta(
    'fromNodeId',
  );
  @override
  late final GeneratedColumn<String> fromNodeId = GeneratedColumn<String>(
    'from_node_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _toNodeIdMeta = const VerificationMeta(
    'toNodeId',
  );
  @override
  late final GeneratedColumn<String> toNodeId = GeneratedColumn<String>(
    'to_node_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationSecondsMeta = const VerificationMeta(
    'durationSeconds',
  );
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
    'duration_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _edgeTypeMeta = const VerificationMeta(
    'edgeType',
  );
  @override
  late final GeneratedColumn<String> edgeType = GeneratedColumn<String>(
    'edge_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('WALK'),
  );
  static const VerificationMeta _servicePatternMeta = const VerificationMeta(
    'servicePattern',
  );
  @override
  late final GeneratedColumn<String> servicePattern = GeneratedColumn<String>(
    'service_pattern',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _includesStairsMeta = const VerificationMeta(
    'includesStairs',
  );
  @override
  late final GeneratedColumn<bool> includesStairs = GeneratedColumn<bool>(
    'includes_stairs',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("includes_stairs" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _accessibilityStatusMeta =
      const VerificationMeta('accessibilityStatus');
  @override
  late final GeneratedColumn<String> accessibilityStatus =
      GeneratedColumn<String>(
        'accessibility_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('UNKNOWN'),
      );
  static const VerificationMeta _reliabilityScoreMeta = const VerificationMeta(
    'reliabilityScore',
  );
  @override
  late final GeneratedColumn<int> reliabilityScore = GeneratedColumn<int>(
    'reliability_score',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(100),
  );
  static const VerificationMeta _lastVerifiedAtMeta = const VerificationMeta(
    'lastVerifiedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastVerifiedAt =
      GeneratedColumn<DateTime>(
        'last_verified_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    fromNodeId,
    toNodeId,
    durationSeconds,
    edgeType,
    servicePattern,
    includesStairs,
    accessibilityStatus,
    reliabilityScore,
    lastVerifiedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'network_edges';
  @override
  VerificationContext validateIntegrity(
    Insertable<NetworkEdge> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('from_node_id')) {
      context.handle(
        _fromNodeIdMeta,
        fromNodeId.isAcceptableOrUnknown(
          data['from_node_id']!,
          _fromNodeIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fromNodeIdMeta);
    }
    if (data.containsKey('to_node_id')) {
      context.handle(
        _toNodeIdMeta,
        toNodeId.isAcceptableOrUnknown(data['to_node_id']!, _toNodeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_toNodeIdMeta);
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
        _durationSecondsMeta,
        durationSeconds.isAcceptableOrUnknown(
          data['duration_seconds']!,
          _durationSecondsMeta,
        ),
      );
    }
    if (data.containsKey('edge_type')) {
      context.handle(
        _edgeTypeMeta,
        edgeType.isAcceptableOrUnknown(data['edge_type']!, _edgeTypeMeta),
      );
    }
    if (data.containsKey('service_pattern')) {
      context.handle(
        _servicePatternMeta,
        servicePattern.isAcceptableOrUnknown(
          data['service_pattern']!,
          _servicePatternMeta,
        ),
      );
    }
    if (data.containsKey('includes_stairs')) {
      context.handle(
        _includesStairsMeta,
        includesStairs.isAcceptableOrUnknown(
          data['includes_stairs']!,
          _includesStairsMeta,
        ),
      );
    }
    if (data.containsKey('accessibility_status')) {
      context.handle(
        _accessibilityStatusMeta,
        accessibilityStatus.isAcceptableOrUnknown(
          data['accessibility_status']!,
          _accessibilityStatusMeta,
        ),
      );
    }
    if (data.containsKey('reliability_score')) {
      context.handle(
        _reliabilityScoreMeta,
        reliabilityScore.isAcceptableOrUnknown(
          data['reliability_score']!,
          _reliabilityScoreMeta,
        ),
      );
    }
    if (data.containsKey('last_verified_at')) {
      context.handle(
        _lastVerifiedAtMeta,
        lastVerifiedAt.isAcceptableOrUnknown(
          data['last_verified_at']!,
          _lastVerifiedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NetworkEdge map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NetworkEdge(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      fromNodeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_node_id'],
      )!,
      toNodeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}to_node_id'],
      )!,
      durationSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_seconds'],
      )!,
      edgeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}edge_type'],
      )!,
      servicePattern: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}service_pattern'],
      )!,
      includesStairs: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}includes_stairs'],
      )!,
      accessibilityStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}accessibility_status'],
      )!,
      reliabilityScore: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reliability_score'],
      )!,
      lastVerifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_verified_at'],
      ),
    );
  }

  @override
  $NetworkEdgesTable createAlias(String alias) {
    return $NetworkEdgesTable(attachedDatabase, alias);
  }
}

class NetworkEdge extends DataClass implements Insertable<NetworkEdge> {
  final String id;
  final String fromNodeId;
  final String toNodeId;
  final int durationSeconds;
  final String edgeType;
  final String servicePattern;
  final bool includesStairs;
  final String accessibilityStatus;
  final int reliabilityScore;
  final DateTime? lastVerifiedAt;
  const NetworkEdge({
    required this.id,
    required this.fromNodeId,
    required this.toNodeId,
    required this.durationSeconds,
    required this.edgeType,
    required this.servicePattern,
    required this.includesStairs,
    required this.accessibilityStatus,
    required this.reliabilityScore,
    this.lastVerifiedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['from_node_id'] = Variable<String>(fromNodeId);
    map['to_node_id'] = Variable<String>(toNodeId);
    map['duration_seconds'] = Variable<int>(durationSeconds);
    map['edge_type'] = Variable<String>(edgeType);
    map['service_pattern'] = Variable<String>(servicePattern);
    map['includes_stairs'] = Variable<bool>(includesStairs);
    map['accessibility_status'] = Variable<String>(accessibilityStatus);
    map['reliability_score'] = Variable<int>(reliabilityScore);
    if (!nullToAbsent || lastVerifiedAt != null) {
      map['last_verified_at'] = Variable<DateTime>(lastVerifiedAt);
    }
    return map;
  }

  NetworkEdgesCompanion toCompanion(bool nullToAbsent) {
    return NetworkEdgesCompanion(
      id: Value(id),
      fromNodeId: Value(fromNodeId),
      toNodeId: Value(toNodeId),
      durationSeconds: Value(durationSeconds),
      edgeType: Value(edgeType),
      servicePattern: Value(servicePattern),
      includesStairs: Value(includesStairs),
      accessibilityStatus: Value(accessibilityStatus),
      reliabilityScore: Value(reliabilityScore),
      lastVerifiedAt: lastVerifiedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastVerifiedAt),
    );
  }

  factory NetworkEdge.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NetworkEdge(
      id: serializer.fromJson<String>(json['id']),
      fromNodeId: serializer.fromJson<String>(json['fromNodeId']),
      toNodeId: serializer.fromJson<String>(json['toNodeId']),
      durationSeconds: serializer.fromJson<int>(json['durationSeconds']),
      edgeType: serializer.fromJson<String>(json['edgeType']),
      servicePattern: serializer.fromJson<String>(json['servicePattern']),
      includesStairs: serializer.fromJson<bool>(json['includesStairs']),
      accessibilityStatus: serializer.fromJson<String>(
        json['accessibilityStatus'],
      ),
      reliabilityScore: serializer.fromJson<int>(json['reliabilityScore']),
      lastVerifiedAt: serializer.fromJson<DateTime?>(json['lastVerifiedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'fromNodeId': serializer.toJson<String>(fromNodeId),
      'toNodeId': serializer.toJson<String>(toNodeId),
      'durationSeconds': serializer.toJson<int>(durationSeconds),
      'edgeType': serializer.toJson<String>(edgeType),
      'servicePattern': serializer.toJson<String>(servicePattern),
      'includesStairs': serializer.toJson<bool>(includesStairs),
      'accessibilityStatus': serializer.toJson<String>(accessibilityStatus),
      'reliabilityScore': serializer.toJson<int>(reliabilityScore),
      'lastVerifiedAt': serializer.toJson<DateTime?>(lastVerifiedAt),
    };
  }

  NetworkEdge copyWith({
    String? id,
    String? fromNodeId,
    String? toNodeId,
    int? durationSeconds,
    String? edgeType,
    String? servicePattern,
    bool? includesStairs,
    String? accessibilityStatus,
    int? reliabilityScore,
    Value<DateTime?> lastVerifiedAt = const Value.absent(),
  }) => NetworkEdge(
    id: id ?? this.id,
    fromNodeId: fromNodeId ?? this.fromNodeId,
    toNodeId: toNodeId ?? this.toNodeId,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    edgeType: edgeType ?? this.edgeType,
    servicePattern: servicePattern ?? this.servicePattern,
    includesStairs: includesStairs ?? this.includesStairs,
    accessibilityStatus: accessibilityStatus ?? this.accessibilityStatus,
    reliabilityScore: reliabilityScore ?? this.reliabilityScore,
    lastVerifiedAt: lastVerifiedAt.present
        ? lastVerifiedAt.value
        : this.lastVerifiedAt,
  );
  NetworkEdge copyWithCompanion(NetworkEdgesCompanion data) {
    return NetworkEdge(
      id: data.id.present ? data.id.value : this.id,
      fromNodeId: data.fromNodeId.present
          ? data.fromNodeId.value
          : this.fromNodeId,
      toNodeId: data.toNodeId.present ? data.toNodeId.value : this.toNodeId,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
      edgeType: data.edgeType.present ? data.edgeType.value : this.edgeType,
      servicePattern: data.servicePattern.present
          ? data.servicePattern.value
          : this.servicePattern,
      includesStairs: data.includesStairs.present
          ? data.includesStairs.value
          : this.includesStairs,
      accessibilityStatus: data.accessibilityStatus.present
          ? data.accessibilityStatus.value
          : this.accessibilityStatus,
      reliabilityScore: data.reliabilityScore.present
          ? data.reliabilityScore.value
          : this.reliabilityScore,
      lastVerifiedAt: data.lastVerifiedAt.present
          ? data.lastVerifiedAt.value
          : this.lastVerifiedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NetworkEdge(')
          ..write('id: $id, ')
          ..write('fromNodeId: $fromNodeId, ')
          ..write('toNodeId: $toNodeId, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('edgeType: $edgeType, ')
          ..write('servicePattern: $servicePattern, ')
          ..write('includesStairs: $includesStairs, ')
          ..write('accessibilityStatus: $accessibilityStatus, ')
          ..write('reliabilityScore: $reliabilityScore, ')
          ..write('lastVerifiedAt: $lastVerifiedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    fromNodeId,
    toNodeId,
    durationSeconds,
    edgeType,
    servicePattern,
    includesStairs,
    accessibilityStatus,
    reliabilityScore,
    lastVerifiedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NetworkEdge &&
          other.id == this.id &&
          other.fromNodeId == this.fromNodeId &&
          other.toNodeId == this.toNodeId &&
          other.durationSeconds == this.durationSeconds &&
          other.edgeType == this.edgeType &&
          other.servicePattern == this.servicePattern &&
          other.includesStairs == this.includesStairs &&
          other.accessibilityStatus == this.accessibilityStatus &&
          other.reliabilityScore == this.reliabilityScore &&
          other.lastVerifiedAt == this.lastVerifiedAt);
}

class NetworkEdgesCompanion extends UpdateCompanion<NetworkEdge> {
  final Value<String> id;
  final Value<String> fromNodeId;
  final Value<String> toNodeId;
  final Value<int> durationSeconds;
  final Value<String> edgeType;
  final Value<String> servicePattern;
  final Value<bool> includesStairs;
  final Value<String> accessibilityStatus;
  final Value<int> reliabilityScore;
  final Value<DateTime?> lastVerifiedAt;
  final Value<int> rowid;
  const NetworkEdgesCompanion({
    this.id = const Value.absent(),
    this.fromNodeId = const Value.absent(),
    this.toNodeId = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.edgeType = const Value.absent(),
    this.servicePattern = const Value.absent(),
    this.includesStairs = const Value.absent(),
    this.accessibilityStatus = const Value.absent(),
    this.reliabilityScore = const Value.absent(),
    this.lastVerifiedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NetworkEdgesCompanion.insert({
    required String id,
    required String fromNodeId,
    required String toNodeId,
    this.durationSeconds = const Value.absent(),
    this.edgeType = const Value.absent(),
    this.servicePattern = const Value.absent(),
    this.includesStairs = const Value.absent(),
    this.accessibilityStatus = const Value.absent(),
    this.reliabilityScore = const Value.absent(),
    this.lastVerifiedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       fromNodeId = Value(fromNodeId),
       toNodeId = Value(toNodeId);
  static Insertable<NetworkEdge> custom({
    Expression<String>? id,
    Expression<String>? fromNodeId,
    Expression<String>? toNodeId,
    Expression<int>? durationSeconds,
    Expression<String>? edgeType,
    Expression<String>? servicePattern,
    Expression<bool>? includesStairs,
    Expression<String>? accessibilityStatus,
    Expression<int>? reliabilityScore,
    Expression<DateTime>? lastVerifiedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (fromNodeId != null) 'from_node_id': fromNodeId,
      if (toNodeId != null) 'to_node_id': toNodeId,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (edgeType != null) 'edge_type': edgeType,
      if (servicePattern != null) 'service_pattern': servicePattern,
      if (includesStairs != null) 'includes_stairs': includesStairs,
      if (accessibilityStatus != null)
        'accessibility_status': accessibilityStatus,
      if (reliabilityScore != null) 'reliability_score': reliabilityScore,
      if (lastVerifiedAt != null) 'last_verified_at': lastVerifiedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NetworkEdgesCompanion copyWith({
    Value<String>? id,
    Value<String>? fromNodeId,
    Value<String>? toNodeId,
    Value<int>? durationSeconds,
    Value<String>? edgeType,
    Value<String>? servicePattern,
    Value<bool>? includesStairs,
    Value<String>? accessibilityStatus,
    Value<int>? reliabilityScore,
    Value<DateTime?>? lastVerifiedAt,
    Value<int>? rowid,
  }) {
    return NetworkEdgesCompanion(
      id: id ?? this.id,
      fromNodeId: fromNodeId ?? this.fromNodeId,
      toNodeId: toNodeId ?? this.toNodeId,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      edgeType: edgeType ?? this.edgeType,
      servicePattern: servicePattern ?? this.servicePattern,
      includesStairs: includesStairs ?? this.includesStairs,
      accessibilityStatus: accessibilityStatus ?? this.accessibilityStatus,
      reliabilityScore: reliabilityScore ?? this.reliabilityScore,
      lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (fromNodeId.present) {
      map['from_node_id'] = Variable<String>(fromNodeId.value);
    }
    if (toNodeId.present) {
      map['to_node_id'] = Variable<String>(toNodeId.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (edgeType.present) {
      map['edge_type'] = Variable<String>(edgeType.value);
    }
    if (servicePattern.present) {
      map['service_pattern'] = Variable<String>(servicePattern.value);
    }
    if (includesStairs.present) {
      map['includes_stairs'] = Variable<bool>(includesStairs.value);
    }
    if (accessibilityStatus.present) {
      map['accessibility_status'] = Variable<String>(accessibilityStatus.value);
    }
    if (reliabilityScore.present) {
      map['reliability_score'] = Variable<int>(reliabilityScore.value);
    }
    if (lastVerifiedAt.present) {
      map['last_verified_at'] = Variable<DateTime>(lastVerifiedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NetworkEdgesCompanion(')
          ..write('id: $id, ')
          ..write('fromNodeId: $fromNodeId, ')
          ..write('toNodeId: $toNodeId, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('edgeType: $edgeType, ')
          ..write('servicePattern: $servicePattern, ')
          ..write('includesStairs: $includesStairs, ')
          ..write('accessibilityStatus: $accessibilityStatus, ')
          ..write('reliabilityScore: $reliabilityScore, ')
          ..write('lastVerifiedAt: $lastVerifiedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StationExitsTable extends StationExits
    with TableInfo<$StationExitsTable, StationExit> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StationExitsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _exitNumberMeta = const VerificationMeta(
    'exitNumber',
  );
  @override
  late final GeneratedColumn<String> exitNumber = GeneratedColumn<String>(
    'exit_number',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    stationId,
    exitNumber,
    description,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'station_exits';
  @override
  VerificationContext validateIntegrity(
    Insertable<StationExit> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('station_id')) {
      context.handle(
        _stationIdMeta,
        stationId.isAcceptableOrUnknown(data['station_id']!, _stationIdMeta),
      );
    } else if (isInserting) {
      context.missing(_stationIdMeta);
    }
    if (data.containsKey('exit_number')) {
      context.handle(
        _exitNumberMeta,
        exitNumber.isAcceptableOrUnknown(data['exit_number']!, _exitNumberMeta),
      );
    } else if (isInserting) {
      context.missing(_exitNumberMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StationExit map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StationExit(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      stationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}station_id'],
      )!,
      exitNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exit_number'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
    );
  }

  @override
  $StationExitsTable createAlias(String alias) {
    return $StationExitsTable(attachedDatabase, alias);
  }
}

class StationExit extends DataClass implements Insertable<StationExit> {
  final String id;
  final String stationId;
  final String exitNumber;
  final String description;
  const StationExit({
    required this.id,
    required this.stationId,
    required this.exitNumber,
    required this.description,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['station_id'] = Variable<String>(stationId);
    map['exit_number'] = Variable<String>(exitNumber);
    map['description'] = Variable<String>(description);
    return map;
  }

  StationExitsCompanion toCompanion(bool nullToAbsent) {
    return StationExitsCompanion(
      id: Value(id),
      stationId: Value(stationId),
      exitNumber: Value(exitNumber),
      description: Value(description),
    );
  }

  factory StationExit.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StationExit(
      id: serializer.fromJson<String>(json['id']),
      stationId: serializer.fromJson<String>(json['stationId']),
      exitNumber: serializer.fromJson<String>(json['exitNumber']),
      description: serializer.fromJson<String>(json['description']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'stationId': serializer.toJson<String>(stationId),
      'exitNumber': serializer.toJson<String>(exitNumber),
      'description': serializer.toJson<String>(description),
    };
  }

  StationExit copyWith({
    String? id,
    String? stationId,
    String? exitNumber,
    String? description,
  }) => StationExit(
    id: id ?? this.id,
    stationId: stationId ?? this.stationId,
    exitNumber: exitNumber ?? this.exitNumber,
    description: description ?? this.description,
  );
  StationExit copyWithCompanion(StationExitsCompanion data) {
    return StationExit(
      id: data.id.present ? data.id.value : this.id,
      stationId: data.stationId.present ? data.stationId.value : this.stationId,
      exitNumber: data.exitNumber.present
          ? data.exitNumber.value
          : this.exitNumber,
      description: data.description.present
          ? data.description.value
          : this.description,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StationExit(')
          ..write('id: $id, ')
          ..write('stationId: $stationId, ')
          ..write('exitNumber: $exitNumber, ')
          ..write('description: $description')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, stationId, exitNumber, description);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StationExit &&
          other.id == this.id &&
          other.stationId == this.stationId &&
          other.exitNumber == this.exitNumber &&
          other.description == this.description);
}

class StationExitsCompanion extends UpdateCompanion<StationExit> {
  final Value<String> id;
  final Value<String> stationId;
  final Value<String> exitNumber;
  final Value<String> description;
  final Value<int> rowid;
  const StationExitsCompanion({
    this.id = const Value.absent(),
    this.stationId = const Value.absent(),
    this.exitNumber = const Value.absent(),
    this.description = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StationExitsCompanion.insert({
    required String id,
    required String stationId,
    required String exitNumber,
    this.description = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       stationId = Value(stationId),
       exitNumber = Value(exitNumber);
  static Insertable<StationExit> custom({
    Expression<String>? id,
    Expression<String>? stationId,
    Expression<String>? exitNumber,
    Expression<String>? description,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (stationId != null) 'station_id': stationId,
      if (exitNumber != null) 'exit_number': exitNumber,
      if (description != null) 'description': description,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StationExitsCompanion copyWith({
    Value<String>? id,
    Value<String>? stationId,
    Value<String>? exitNumber,
    Value<String>? description,
    Value<int>? rowid,
  }) {
    return StationExitsCompanion(
      id: id ?? this.id,
      stationId: stationId ?? this.stationId,
      exitNumber: exitNumber ?? this.exitNumber,
      description: description ?? this.description,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (stationId.present) {
      map['station_id'] = Variable<String>(stationId.value);
    }
    if (exitNumber.present) {
      map['exit_number'] = Variable<String>(exitNumber.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StationExitsCompanion(')
          ..write('id: $id, ')
          ..write('stationId: $stationId, ')
          ..write('exitNumber: $exitNumber, ')
          ..write('description: $description, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FacilitiesTable extends Facilities
    with TableInfo<$FacilitiesTable, Facility> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FacilitiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _exitIdMeta = const VerificationMeta('exitId');
  @override
  late final GeneratedColumn<String> exitId = GeneratedColumn<String>(
    'exit_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('NORMAL'),
  );
  static const VerificationMeta _floorFromMeta = const VerificationMeta(
    'floorFrom',
  );
  @override
  late final GeneratedColumn<String> floorFrom = GeneratedColumn<String>(
    'floor_from',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _floorToMeta = const VerificationMeta(
    'floorTo',
  );
  @override
  late final GeneratedColumn<String> floorTo = GeneratedColumn<String>(
    'floor_to',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    stationId,
    exitId,
    type,
    name,
    status,
    floorFrom,
    floorTo,
    description,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'facilities';
  @override
  VerificationContext validateIntegrity(
    Insertable<Facility> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('station_id')) {
      context.handle(
        _stationIdMeta,
        stationId.isAcceptableOrUnknown(data['station_id']!, _stationIdMeta),
      );
    } else if (isInserting) {
      context.missing(_stationIdMeta);
    }
    if (data.containsKey('exit_id')) {
      context.handle(
        _exitIdMeta,
        exitId.isAcceptableOrUnknown(data['exit_id']!, _exitIdMeta),
      );
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('floor_from')) {
      context.handle(
        _floorFromMeta,
        floorFrom.isAcceptableOrUnknown(data['floor_from']!, _floorFromMeta),
      );
    }
    if (data.containsKey('floor_to')) {
      context.handle(
        _floorToMeta,
        floorTo.isAcceptableOrUnknown(data['floor_to']!, _floorToMeta),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Facility map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Facility(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      stationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}station_id'],
      )!,
      exitId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exit_id'],
      ),
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      floorFrom: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}floor_from'],
      )!,
      floorTo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}floor_to'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
    );
  }

  @override
  $FacilitiesTable createAlias(String alias) {
    return $FacilitiesTable(attachedDatabase, alias);
  }
}

class Facility extends DataClass implements Insertable<Facility> {
  final String id;
  final String stationId;
  final String? exitId;
  final String type;
  final String name;
  final String status;
  final String floorFrom;
  final String floorTo;
  final String description;
  const Facility({
    required this.id,
    required this.stationId,
    this.exitId,
    required this.type,
    required this.name,
    required this.status,
    required this.floorFrom,
    required this.floorTo,
    required this.description,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['station_id'] = Variable<String>(stationId);
    if (!nullToAbsent || exitId != null) {
      map['exit_id'] = Variable<String>(exitId);
    }
    map['type'] = Variable<String>(type);
    map['name'] = Variable<String>(name);
    map['status'] = Variable<String>(status);
    map['floor_from'] = Variable<String>(floorFrom);
    map['floor_to'] = Variable<String>(floorTo);
    map['description'] = Variable<String>(description);
    return map;
  }

  FacilitiesCompanion toCompanion(bool nullToAbsent) {
    return FacilitiesCompanion(
      id: Value(id),
      stationId: Value(stationId),
      exitId: exitId == null && nullToAbsent
          ? const Value.absent()
          : Value(exitId),
      type: Value(type),
      name: Value(name),
      status: Value(status),
      floorFrom: Value(floorFrom),
      floorTo: Value(floorTo),
      description: Value(description),
    );
  }

  factory Facility.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Facility(
      id: serializer.fromJson<String>(json['id']),
      stationId: serializer.fromJson<String>(json['stationId']),
      exitId: serializer.fromJson<String?>(json['exitId']),
      type: serializer.fromJson<String>(json['type']),
      name: serializer.fromJson<String>(json['name']),
      status: serializer.fromJson<String>(json['status']),
      floorFrom: serializer.fromJson<String>(json['floorFrom']),
      floorTo: serializer.fromJson<String>(json['floorTo']),
      description: serializer.fromJson<String>(json['description']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'stationId': serializer.toJson<String>(stationId),
      'exitId': serializer.toJson<String?>(exitId),
      'type': serializer.toJson<String>(type),
      'name': serializer.toJson<String>(name),
      'status': serializer.toJson<String>(status),
      'floorFrom': serializer.toJson<String>(floorFrom),
      'floorTo': serializer.toJson<String>(floorTo),
      'description': serializer.toJson<String>(description),
    };
  }

  Facility copyWith({
    String? id,
    String? stationId,
    Value<String?> exitId = const Value.absent(),
    String? type,
    String? name,
    String? status,
    String? floorFrom,
    String? floorTo,
    String? description,
  }) => Facility(
    id: id ?? this.id,
    stationId: stationId ?? this.stationId,
    exitId: exitId.present ? exitId.value : this.exitId,
    type: type ?? this.type,
    name: name ?? this.name,
    status: status ?? this.status,
    floorFrom: floorFrom ?? this.floorFrom,
    floorTo: floorTo ?? this.floorTo,
    description: description ?? this.description,
  );
  Facility copyWithCompanion(FacilitiesCompanion data) {
    return Facility(
      id: data.id.present ? data.id.value : this.id,
      stationId: data.stationId.present ? data.stationId.value : this.stationId,
      exitId: data.exitId.present ? data.exitId.value : this.exitId,
      type: data.type.present ? data.type.value : this.type,
      name: data.name.present ? data.name.value : this.name,
      status: data.status.present ? data.status.value : this.status,
      floorFrom: data.floorFrom.present ? data.floorFrom.value : this.floorFrom,
      floorTo: data.floorTo.present ? data.floorTo.value : this.floorTo,
      description: data.description.present
          ? data.description.value
          : this.description,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Facility(')
          ..write('id: $id, ')
          ..write('stationId: $stationId, ')
          ..write('exitId: $exitId, ')
          ..write('type: $type, ')
          ..write('name: $name, ')
          ..write('status: $status, ')
          ..write('floorFrom: $floorFrom, ')
          ..write('floorTo: $floorTo, ')
          ..write('description: $description')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    stationId,
    exitId,
    type,
    name,
    status,
    floorFrom,
    floorTo,
    description,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Facility &&
          other.id == this.id &&
          other.stationId == this.stationId &&
          other.exitId == this.exitId &&
          other.type == this.type &&
          other.name == this.name &&
          other.status == this.status &&
          other.floorFrom == this.floorFrom &&
          other.floorTo == this.floorTo &&
          other.description == this.description);
}

class FacilitiesCompanion extends UpdateCompanion<Facility> {
  final Value<String> id;
  final Value<String> stationId;
  final Value<String?> exitId;
  final Value<String> type;
  final Value<String> name;
  final Value<String> status;
  final Value<String> floorFrom;
  final Value<String> floorTo;
  final Value<String> description;
  final Value<int> rowid;
  const FacilitiesCompanion({
    this.id = const Value.absent(),
    this.stationId = const Value.absent(),
    this.exitId = const Value.absent(),
    this.type = const Value.absent(),
    this.name = const Value.absent(),
    this.status = const Value.absent(),
    this.floorFrom = const Value.absent(),
    this.floorTo = const Value.absent(),
    this.description = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FacilitiesCompanion.insert({
    required String id,
    required String stationId,
    this.exitId = const Value.absent(),
    required String type,
    required String name,
    this.status = const Value.absent(),
    this.floorFrom = const Value.absent(),
    this.floorTo = const Value.absent(),
    this.description = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       stationId = Value(stationId),
       type = Value(type),
       name = Value(name);
  static Insertable<Facility> custom({
    Expression<String>? id,
    Expression<String>? stationId,
    Expression<String>? exitId,
    Expression<String>? type,
    Expression<String>? name,
    Expression<String>? status,
    Expression<String>? floorFrom,
    Expression<String>? floorTo,
    Expression<String>? description,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (stationId != null) 'station_id': stationId,
      if (exitId != null) 'exit_id': exitId,
      if (type != null) 'type': type,
      if (name != null) 'name': name,
      if (status != null) 'status': status,
      if (floorFrom != null) 'floor_from': floorFrom,
      if (floorTo != null) 'floor_to': floorTo,
      if (description != null) 'description': description,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FacilitiesCompanion copyWith({
    Value<String>? id,
    Value<String>? stationId,
    Value<String?>? exitId,
    Value<String>? type,
    Value<String>? name,
    Value<String>? status,
    Value<String>? floorFrom,
    Value<String>? floorTo,
    Value<String>? description,
    Value<int>? rowid,
  }) {
    return FacilitiesCompanion(
      id: id ?? this.id,
      stationId: stationId ?? this.stationId,
      exitId: exitId ?? this.exitId,
      type: type ?? this.type,
      name: name ?? this.name,
      status: status ?? this.status,
      floorFrom: floorFrom ?? this.floorFrom,
      floorTo: floorTo ?? this.floorTo,
      description: description ?? this.description,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (stationId.present) {
      map['station_id'] = Variable<String>(stationId.value);
    }
    if (exitId.present) {
      map['exit_id'] = Variable<String>(exitId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (floorFrom.present) {
      map['floor_from'] = Variable<String>(floorFrom.value);
    }
    if (floorTo.present) {
      map['floor_to'] = Variable<String>(floorTo.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FacilitiesCompanion(')
          ..write('id: $id, ')
          ..write('stationId: $stationId, ')
          ..write('exitId: $exitId, ')
          ..write('type: $type, ')
          ..write('name: $name, ')
          ..write('status: $status, ')
          ..write('floorFrom: $floorFrom, ')
          ..write('floorTo: $floorTo, ')
          ..write('description: $description, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StationAccessibilitySummariesTable extends StationAccessibilitySummaries
    with
        TableInfo<
          $StationAccessibilitySummariesTable,
          StationAccessibilitySummary
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StationAccessibilitySummariesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _summaryMeta = const VerificationMeta(
    'summary',
  );
  @override
  late final GeneratedColumn<String> summary = GeneratedColumn<String>(
    'summary',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _warningMeta = const VerificationMeta(
    'warning',
  );
  @override
  late final GeneratedColumn<String> warning = GeneratedColumn<String>(
    'warning',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [stationId, summary, warning];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'station_accessibility_summaries';
  @override
  VerificationContext validateIntegrity(
    Insertable<StationAccessibilitySummary> instance, {
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
    if (data.containsKey('summary')) {
      context.handle(
        _summaryMeta,
        summary.isAcceptableOrUnknown(data['summary']!, _summaryMeta),
      );
    } else if (isInserting) {
      context.missing(_summaryMeta);
    }
    if (data.containsKey('warning')) {
      context.handle(
        _warningMeta,
        warning.isAcceptableOrUnknown(data['warning']!, _warningMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {stationId};
  @override
  StationAccessibilitySummary map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StationAccessibilitySummary(
      stationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}station_id'],
      )!,
      summary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary'],
      )!,
      warning: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}warning'],
      )!,
    );
  }

  @override
  $StationAccessibilitySummariesTable createAlias(String alias) {
    return $StationAccessibilitySummariesTable(attachedDatabase, alias);
  }
}

class StationAccessibilitySummary extends DataClass
    implements Insertable<StationAccessibilitySummary> {
  final String stationId;
  final String summary;
  final String warning;
  const StationAccessibilitySummary({
    required this.stationId,
    required this.summary,
    required this.warning,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['station_id'] = Variable<String>(stationId);
    map['summary'] = Variable<String>(summary);
    map['warning'] = Variable<String>(warning);
    return map;
  }

  StationAccessibilitySummariesCompanion toCompanion(bool nullToAbsent) {
    return StationAccessibilitySummariesCompanion(
      stationId: Value(stationId),
      summary: Value(summary),
      warning: Value(warning),
    );
  }

  factory StationAccessibilitySummary.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StationAccessibilitySummary(
      stationId: serializer.fromJson<String>(json['stationId']),
      summary: serializer.fromJson<String>(json['summary']),
      warning: serializer.fromJson<String>(json['warning']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'stationId': serializer.toJson<String>(stationId),
      'summary': serializer.toJson<String>(summary),
      'warning': serializer.toJson<String>(warning),
    };
  }

  StationAccessibilitySummary copyWith({
    String? stationId,
    String? summary,
    String? warning,
  }) => StationAccessibilitySummary(
    stationId: stationId ?? this.stationId,
    summary: summary ?? this.summary,
    warning: warning ?? this.warning,
  );
  StationAccessibilitySummary copyWithCompanion(
    StationAccessibilitySummariesCompanion data,
  ) {
    return StationAccessibilitySummary(
      stationId: data.stationId.present ? data.stationId.value : this.stationId,
      summary: data.summary.present ? data.summary.value : this.summary,
      warning: data.warning.present ? data.warning.value : this.warning,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StationAccessibilitySummary(')
          ..write('stationId: $stationId, ')
          ..write('summary: $summary, ')
          ..write('warning: $warning')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(stationId, summary, warning);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StationAccessibilitySummary &&
          other.stationId == this.stationId &&
          other.summary == this.summary &&
          other.warning == this.warning);
}

class StationAccessibilitySummariesCompanion
    extends UpdateCompanion<StationAccessibilitySummary> {
  final Value<String> stationId;
  final Value<String> summary;
  final Value<String> warning;
  final Value<int> rowid;
  const StationAccessibilitySummariesCompanion({
    this.stationId = const Value.absent(),
    this.summary = const Value.absent(),
    this.warning = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StationAccessibilitySummariesCompanion.insert({
    required String stationId,
    required String summary,
    this.warning = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : stationId = Value(stationId),
       summary = Value(summary);
  static Insertable<StationAccessibilitySummary> custom({
    Expression<String>? stationId,
    Expression<String>? summary,
    Expression<String>? warning,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (stationId != null) 'station_id': stationId,
      if (summary != null) 'summary': summary,
      if (warning != null) 'warning': warning,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StationAccessibilitySummariesCompanion copyWith({
    Value<String>? stationId,
    Value<String>? summary,
    Value<String>? warning,
    Value<int>? rowid,
  }) {
    return StationAccessibilitySummariesCompanion(
      stationId: stationId ?? this.stationId,
      summary: summary ?? this.summary,
      warning: warning ?? this.warning,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (stationId.present) {
      map['station_id'] = Variable<String>(stationId.value);
    }
    if (summary.present) {
      map['summary'] = Variable<String>(summary.value);
    }
    if (warning.present) {
      map['warning'] = Variable<String>(warning.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StationAccessibilitySummariesCompanion(')
          ..write('stationId: $stationId, ')
          ..write('summary: $summary, ')
          ..write('warning: $warning, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $InternalRouteNodesTable extends InternalRouteNodes
    with TableInfo<$InternalRouteNodesTable, InternalRouteNode> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InternalRouteNodesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nodeTypeMeta = const VerificationMeta(
    'nodeType',
  );
  @override
  late final GeneratedColumn<String> nodeType = GeneratedColumn<String>(
    'node_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, stationId, label, nodeType];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'internal_route_nodes';
  @override
  VerificationContext validateIntegrity(
    Insertable<InternalRouteNode> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('station_id')) {
      context.handle(
        _stationIdMeta,
        stationId.isAcceptableOrUnknown(data['station_id']!, _stationIdMeta),
      );
    } else if (isInserting) {
      context.missing(_stationIdMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('node_type')) {
      context.handle(
        _nodeTypeMeta,
        nodeType.isAcceptableOrUnknown(data['node_type']!, _nodeTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_nodeTypeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  InternalRouteNode map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InternalRouteNode(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      stationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}station_id'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      nodeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}node_type'],
      )!,
    );
  }

  @override
  $InternalRouteNodesTable createAlias(String alias) {
    return $InternalRouteNodesTable(attachedDatabase, alias);
  }
}

class InternalRouteNode extends DataClass
    implements Insertable<InternalRouteNode> {
  final String id;
  final String stationId;
  final String label;
  final String nodeType;
  const InternalRouteNode({
    required this.id,
    required this.stationId,
    required this.label,
    required this.nodeType,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['station_id'] = Variable<String>(stationId);
    map['label'] = Variable<String>(label);
    map['node_type'] = Variable<String>(nodeType);
    return map;
  }

  InternalRouteNodesCompanion toCompanion(bool nullToAbsent) {
    return InternalRouteNodesCompanion(
      id: Value(id),
      stationId: Value(stationId),
      label: Value(label),
      nodeType: Value(nodeType),
    );
  }

  factory InternalRouteNode.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InternalRouteNode(
      id: serializer.fromJson<String>(json['id']),
      stationId: serializer.fromJson<String>(json['stationId']),
      label: serializer.fromJson<String>(json['label']),
      nodeType: serializer.fromJson<String>(json['nodeType']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'stationId': serializer.toJson<String>(stationId),
      'label': serializer.toJson<String>(label),
      'nodeType': serializer.toJson<String>(nodeType),
    };
  }

  InternalRouteNode copyWith({
    String? id,
    String? stationId,
    String? label,
    String? nodeType,
  }) => InternalRouteNode(
    id: id ?? this.id,
    stationId: stationId ?? this.stationId,
    label: label ?? this.label,
    nodeType: nodeType ?? this.nodeType,
  );
  InternalRouteNode copyWithCompanion(InternalRouteNodesCompanion data) {
    return InternalRouteNode(
      id: data.id.present ? data.id.value : this.id,
      stationId: data.stationId.present ? data.stationId.value : this.stationId,
      label: data.label.present ? data.label.value : this.label,
      nodeType: data.nodeType.present ? data.nodeType.value : this.nodeType,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InternalRouteNode(')
          ..write('id: $id, ')
          ..write('stationId: $stationId, ')
          ..write('label: $label, ')
          ..write('nodeType: $nodeType')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, stationId, label, nodeType);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InternalRouteNode &&
          other.id == this.id &&
          other.stationId == this.stationId &&
          other.label == this.label &&
          other.nodeType == this.nodeType);
}

class InternalRouteNodesCompanion extends UpdateCompanion<InternalRouteNode> {
  final Value<String> id;
  final Value<String> stationId;
  final Value<String> label;
  final Value<String> nodeType;
  final Value<int> rowid;
  const InternalRouteNodesCompanion({
    this.id = const Value.absent(),
    this.stationId = const Value.absent(),
    this.label = const Value.absent(),
    this.nodeType = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InternalRouteNodesCompanion.insert({
    required String id,
    required String stationId,
    required String label,
    required String nodeType,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       stationId = Value(stationId),
       label = Value(label),
       nodeType = Value(nodeType);
  static Insertable<InternalRouteNode> custom({
    Expression<String>? id,
    Expression<String>? stationId,
    Expression<String>? label,
    Expression<String>? nodeType,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (stationId != null) 'station_id': stationId,
      if (label != null) 'label': label,
      if (nodeType != null) 'node_type': nodeType,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InternalRouteNodesCompanion copyWith({
    Value<String>? id,
    Value<String>? stationId,
    Value<String>? label,
    Value<String>? nodeType,
    Value<int>? rowid,
  }) {
    return InternalRouteNodesCompanion(
      id: id ?? this.id,
      stationId: stationId ?? this.stationId,
      label: label ?? this.label,
      nodeType: nodeType ?? this.nodeType,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (stationId.present) {
      map['station_id'] = Variable<String>(stationId.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (nodeType.present) {
      map['node_type'] = Variable<String>(nodeType.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InternalRouteNodesCompanion(')
          ..write('id: $id, ')
          ..write('stationId: $stationId, ')
          ..write('label: $label, ')
          ..write('nodeType: $nodeType, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $InternalRouteEdgesTable extends InternalRouteEdges
    with TableInfo<$InternalRouteEdgesTable, InternalRouteEdge> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InternalRouteEdgesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fromNodeIdMeta = const VerificationMeta(
    'fromNodeId',
  );
  @override
  late final GeneratedColumn<String> fromNodeId = GeneratedColumn<String>(
    'from_node_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _toNodeIdMeta = const VerificationMeta(
    'toNodeId',
  );
  @override
  late final GeneratedColumn<String> toNodeId = GeneratedColumn<String>(
    'to_node_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationSecondsMeta = const VerificationMeta(
    'durationSeconds',
  );
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
    'duration_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _instructionMeta = const VerificationMeta(
    'instruction',
  );
  @override
  late final GeneratedColumn<String> instruction = GeneratedColumn<String>(
    'instruction',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    fromNodeId,
    toNodeId,
    durationSeconds,
    instruction,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'internal_route_edges';
  @override
  VerificationContext validateIntegrity(
    Insertable<InternalRouteEdge> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('from_node_id')) {
      context.handle(
        _fromNodeIdMeta,
        fromNodeId.isAcceptableOrUnknown(
          data['from_node_id']!,
          _fromNodeIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fromNodeIdMeta);
    }
    if (data.containsKey('to_node_id')) {
      context.handle(
        _toNodeIdMeta,
        toNodeId.isAcceptableOrUnknown(data['to_node_id']!, _toNodeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_toNodeIdMeta);
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
        _durationSecondsMeta,
        durationSeconds.isAcceptableOrUnknown(
          data['duration_seconds']!,
          _durationSecondsMeta,
        ),
      );
    }
    if (data.containsKey('instruction')) {
      context.handle(
        _instructionMeta,
        instruction.isAcceptableOrUnknown(
          data['instruction']!,
          _instructionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  InternalRouteEdge map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InternalRouteEdge(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      fromNodeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_node_id'],
      )!,
      toNodeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}to_node_id'],
      )!,
      durationSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_seconds'],
      )!,
      instruction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}instruction'],
      )!,
    );
  }

  @override
  $InternalRouteEdgesTable createAlias(String alias) {
    return $InternalRouteEdgesTable(attachedDatabase, alias);
  }
}

class InternalRouteEdge extends DataClass
    implements Insertable<InternalRouteEdge> {
  final String id;
  final String fromNodeId;
  final String toNodeId;
  final int durationSeconds;
  final String instruction;
  const InternalRouteEdge({
    required this.id,
    required this.fromNodeId,
    required this.toNodeId,
    required this.durationSeconds,
    required this.instruction,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['from_node_id'] = Variable<String>(fromNodeId);
    map['to_node_id'] = Variable<String>(toNodeId);
    map['duration_seconds'] = Variable<int>(durationSeconds);
    map['instruction'] = Variable<String>(instruction);
    return map;
  }

  InternalRouteEdgesCompanion toCompanion(bool nullToAbsent) {
    return InternalRouteEdgesCompanion(
      id: Value(id),
      fromNodeId: Value(fromNodeId),
      toNodeId: Value(toNodeId),
      durationSeconds: Value(durationSeconds),
      instruction: Value(instruction),
    );
  }

  factory InternalRouteEdge.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InternalRouteEdge(
      id: serializer.fromJson<String>(json['id']),
      fromNodeId: serializer.fromJson<String>(json['fromNodeId']),
      toNodeId: serializer.fromJson<String>(json['toNodeId']),
      durationSeconds: serializer.fromJson<int>(json['durationSeconds']),
      instruction: serializer.fromJson<String>(json['instruction']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'fromNodeId': serializer.toJson<String>(fromNodeId),
      'toNodeId': serializer.toJson<String>(toNodeId),
      'durationSeconds': serializer.toJson<int>(durationSeconds),
      'instruction': serializer.toJson<String>(instruction),
    };
  }

  InternalRouteEdge copyWith({
    String? id,
    String? fromNodeId,
    String? toNodeId,
    int? durationSeconds,
    String? instruction,
  }) => InternalRouteEdge(
    id: id ?? this.id,
    fromNodeId: fromNodeId ?? this.fromNodeId,
    toNodeId: toNodeId ?? this.toNodeId,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    instruction: instruction ?? this.instruction,
  );
  InternalRouteEdge copyWithCompanion(InternalRouteEdgesCompanion data) {
    return InternalRouteEdge(
      id: data.id.present ? data.id.value : this.id,
      fromNodeId: data.fromNodeId.present
          ? data.fromNodeId.value
          : this.fromNodeId,
      toNodeId: data.toNodeId.present ? data.toNodeId.value : this.toNodeId,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
      instruction: data.instruction.present
          ? data.instruction.value
          : this.instruction,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InternalRouteEdge(')
          ..write('id: $id, ')
          ..write('fromNodeId: $fromNodeId, ')
          ..write('toNodeId: $toNodeId, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('instruction: $instruction')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, fromNodeId, toNodeId, durationSeconds, instruction);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InternalRouteEdge &&
          other.id == this.id &&
          other.fromNodeId == this.fromNodeId &&
          other.toNodeId == this.toNodeId &&
          other.durationSeconds == this.durationSeconds &&
          other.instruction == this.instruction);
}

class InternalRouteEdgesCompanion extends UpdateCompanion<InternalRouteEdge> {
  final Value<String> id;
  final Value<String> fromNodeId;
  final Value<String> toNodeId;
  final Value<int> durationSeconds;
  final Value<String> instruction;
  final Value<int> rowid;
  const InternalRouteEdgesCompanion({
    this.id = const Value.absent(),
    this.fromNodeId = const Value.absent(),
    this.toNodeId = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.instruction = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InternalRouteEdgesCompanion.insert({
    required String id,
    required String fromNodeId,
    required String toNodeId,
    this.durationSeconds = const Value.absent(),
    this.instruction = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       fromNodeId = Value(fromNodeId),
       toNodeId = Value(toNodeId);
  static Insertable<InternalRouteEdge> custom({
    Expression<String>? id,
    Expression<String>? fromNodeId,
    Expression<String>? toNodeId,
    Expression<int>? durationSeconds,
    Expression<String>? instruction,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (fromNodeId != null) 'from_node_id': fromNodeId,
      if (toNodeId != null) 'to_node_id': toNodeId,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (instruction != null) 'instruction': instruction,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InternalRouteEdgesCompanion copyWith({
    Value<String>? id,
    Value<String>? fromNodeId,
    Value<String>? toNodeId,
    Value<int>? durationSeconds,
    Value<String>? instruction,
    Value<int>? rowid,
  }) {
    return InternalRouteEdgesCompanion(
      id: id ?? this.id,
      fromNodeId: fromNodeId ?? this.fromNodeId,
      toNodeId: toNodeId ?? this.toNodeId,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      instruction: instruction ?? this.instruction,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (fromNodeId.present) {
      map['from_node_id'] = Variable<String>(fromNodeId.value);
    }
    if (toNodeId.present) {
      map['to_node_id'] = Variable<String>(toNodeId.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (instruction.present) {
      map['instruction'] = Variable<String>(instruction.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InternalRouteEdgesCompanion(')
          ..write('id: $id, ')
          ..write('fromNodeId: $fromNodeId, ')
          ..write('toNodeId: $toNodeId, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('instruction: $instruction, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DataQualityRecordsTable extends DataQualityRecords
    with TableInfo<$DataQualityRecordsTable, DataQualityRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DataQualityRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetTypeMeta = const VerificationMeta(
    'targetType',
  );
  @override
  late final GeneratedColumn<String> targetType = GeneratedColumn<String>(
    'target_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetIdMeta = const VerificationMeta(
    'targetId',
  );
  @override
  late final GeneratedColumn<String> targetId = GeneratedColumn<String>(
    'target_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _qualityLevelMeta = const VerificationMeta(
    'qualityLevel',
  );
  @override
  late final GeneratedColumn<String> qualityLevel = GeneratedColumn<String>(
    'quality_level',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _checkedAtMeta = const VerificationMeta(
    'checkedAt',
  );
  @override
  late final GeneratedColumn<DateTime> checkedAt = GeneratedColumn<DateTime>(
    'checked_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    targetType,
    targetId,
    qualityLevel,
    checkedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'data_quality_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<DataQualityRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('target_type')) {
      context.handle(
        _targetTypeMeta,
        targetType.isAcceptableOrUnknown(data['target_type']!, _targetTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_targetTypeMeta);
    }
    if (data.containsKey('target_id')) {
      context.handle(
        _targetIdMeta,
        targetId.isAcceptableOrUnknown(data['target_id']!, _targetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_targetIdMeta);
    }
    if (data.containsKey('quality_level')) {
      context.handle(
        _qualityLevelMeta,
        qualityLevel.isAcceptableOrUnknown(
          data['quality_level']!,
          _qualityLevelMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_qualityLevelMeta);
    }
    if (data.containsKey('checked_at')) {
      context.handle(
        _checkedAtMeta,
        checkedAt.isAcceptableOrUnknown(data['checked_at']!, _checkedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DataQualityRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DataQualityRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      targetType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_type'],
      )!,
      targetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_id'],
      )!,
      qualityLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}quality_level'],
      )!,
      checkedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}checked_at'],
      ),
    );
  }

  @override
  $DataQualityRecordsTable createAlias(String alias) {
    return $DataQualityRecordsTable(attachedDatabase, alias);
  }
}

class DataQualityRecord extends DataClass
    implements Insertable<DataQualityRecord> {
  final String id;
  final String targetType;
  final String targetId;
  final String qualityLevel;
  final DateTime? checkedAt;
  const DataQualityRecord({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.qualityLevel,
    this.checkedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['target_type'] = Variable<String>(targetType);
    map['target_id'] = Variable<String>(targetId);
    map['quality_level'] = Variable<String>(qualityLevel);
    if (!nullToAbsent || checkedAt != null) {
      map['checked_at'] = Variable<DateTime>(checkedAt);
    }
    return map;
  }

  DataQualityRecordsCompanion toCompanion(bool nullToAbsent) {
    return DataQualityRecordsCompanion(
      id: Value(id),
      targetType: Value(targetType),
      targetId: Value(targetId),
      qualityLevel: Value(qualityLevel),
      checkedAt: checkedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(checkedAt),
    );
  }

  factory DataQualityRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DataQualityRecord(
      id: serializer.fromJson<String>(json['id']),
      targetType: serializer.fromJson<String>(json['targetType']),
      targetId: serializer.fromJson<String>(json['targetId']),
      qualityLevel: serializer.fromJson<String>(json['qualityLevel']),
      checkedAt: serializer.fromJson<DateTime?>(json['checkedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'targetType': serializer.toJson<String>(targetType),
      'targetId': serializer.toJson<String>(targetId),
      'qualityLevel': serializer.toJson<String>(qualityLevel),
      'checkedAt': serializer.toJson<DateTime?>(checkedAt),
    };
  }

  DataQualityRecord copyWith({
    String? id,
    String? targetType,
    String? targetId,
    String? qualityLevel,
    Value<DateTime?> checkedAt = const Value.absent(),
  }) => DataQualityRecord(
    id: id ?? this.id,
    targetType: targetType ?? this.targetType,
    targetId: targetId ?? this.targetId,
    qualityLevel: qualityLevel ?? this.qualityLevel,
    checkedAt: checkedAt.present ? checkedAt.value : this.checkedAt,
  );
  DataQualityRecord copyWithCompanion(DataQualityRecordsCompanion data) {
    return DataQualityRecord(
      id: data.id.present ? data.id.value : this.id,
      targetType: data.targetType.present
          ? data.targetType.value
          : this.targetType,
      targetId: data.targetId.present ? data.targetId.value : this.targetId,
      qualityLevel: data.qualityLevel.present
          ? data.qualityLevel.value
          : this.qualityLevel,
      checkedAt: data.checkedAt.present ? data.checkedAt.value : this.checkedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DataQualityRecord(')
          ..write('id: $id, ')
          ..write('targetType: $targetType, ')
          ..write('targetId: $targetId, ')
          ..write('qualityLevel: $qualityLevel, ')
          ..write('checkedAt: $checkedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, targetType, targetId, qualityLevel, checkedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DataQualityRecord &&
          other.id == this.id &&
          other.targetType == this.targetType &&
          other.targetId == this.targetId &&
          other.qualityLevel == this.qualityLevel &&
          other.checkedAt == this.checkedAt);
}

class DataQualityRecordsCompanion extends UpdateCompanion<DataQualityRecord> {
  final Value<String> id;
  final Value<String> targetType;
  final Value<String> targetId;
  final Value<String> qualityLevel;
  final Value<DateTime?> checkedAt;
  final Value<int> rowid;
  const DataQualityRecordsCompanion({
    this.id = const Value.absent(),
    this.targetType = const Value.absent(),
    this.targetId = const Value.absent(),
    this.qualityLevel = const Value.absent(),
    this.checkedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DataQualityRecordsCompanion.insert({
    required String id,
    required String targetType,
    required String targetId,
    required String qualityLevel,
    this.checkedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       targetType = Value(targetType),
       targetId = Value(targetId),
       qualityLevel = Value(qualityLevel);
  static Insertable<DataQualityRecord> custom({
    Expression<String>? id,
    Expression<String>? targetType,
    Expression<String>? targetId,
    Expression<String>? qualityLevel,
    Expression<DateTime>? checkedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (targetType != null) 'target_type': targetType,
      if (targetId != null) 'target_id': targetId,
      if (qualityLevel != null) 'quality_level': qualityLevel,
      if (checkedAt != null) 'checked_at': checkedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DataQualityRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? targetType,
    Value<String>? targetId,
    Value<String>? qualityLevel,
    Value<DateTime?>? checkedAt,
    Value<int>? rowid,
  }) {
    return DataQualityRecordsCompanion(
      id: id ?? this.id,
      targetType: targetType ?? this.targetType,
      targetId: targetId ?? this.targetId,
      qualityLevel: qualityLevel ?? this.qualityLevel,
      checkedAt: checkedAt ?? this.checkedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (targetType.present) {
      map['target_type'] = Variable<String>(targetType.value);
    }
    if (targetId.present) {
      map['target_id'] = Variable<String>(targetId.value);
    }
    if (qualityLevel.present) {
      map['quality_level'] = Variable<String>(qualityLevel.value);
    }
    if (checkedAt.present) {
      map['checked_at'] = Variable<DateTime>(checkedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DataQualityRecordsCompanion(')
          ..write('id: $id, ')
          ..write('targetType: $targetType, ')
          ..write('targetId: $targetId, ')
          ..write('qualityLevel: $qualityLevel, ')
          ..write('checkedAt: $checkedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$CatalogDatabase extends GeneratedDatabase {
  _$CatalogDatabase(QueryExecutor e) : super(e);
  $CatalogDatabaseManager get managers => $CatalogDatabaseManager(this);
  late final $CatalogMetadataTable catalogMetadata = $CatalogMetadataTable(
    this,
  );
  late final $OperatorsTable operators = $OperatorsTable(this);
  late final $LinesTable lines = $LinesTable(this);
  late final $StationsTable stations = $StationsTable(this);
  late final $StationAliasesTable stationAliases = $StationAliasesTable(this);
  late final $StationLinesTable stationLines = $StationLinesTable(this);
  late final $NetworkEdgesTable networkEdges = $NetworkEdgesTable(this);
  late final $StationExitsTable stationExits = $StationExitsTable(this);
  late final $FacilitiesTable facilities = $FacilitiesTable(this);
  late final $StationAccessibilitySummariesTable stationAccessibilitySummaries =
      $StationAccessibilitySummariesTable(this);
  late final $InternalRouteNodesTable internalRouteNodes =
      $InternalRouteNodesTable(this);
  late final $InternalRouteEdgesTable internalRouteEdges =
      $InternalRouteEdgesTable(this);
  late final $DataQualityRecordsTable dataQualityRecords =
      $DataQualityRecordsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    catalogMetadata,
    operators,
    lines,
    stations,
    stationAliases,
    stationLines,
    networkEdges,
    stationExits,
    facilities,
    stationAccessibilitySummaries,
    internalRouteNodes,
    internalRouteEdges,
    dataQualityRecords,
  ];
}

typedef $$CatalogMetadataTableCreateCompanionBuilder =
    CatalogMetadataCompanion Function({
      required String key,
      required String value,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });
typedef $$CatalogMetadataTableUpdateCompanionBuilder =
    CatalogMetadataCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });

class $$CatalogMetadataTableFilterComposer
    extends Composer<_$CatalogDatabase, $CatalogMetadataTable> {
  $$CatalogMetadataTableFilterComposer({
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

class $$CatalogMetadataTableOrderingComposer
    extends Composer<_$CatalogDatabase, $CatalogMetadataTable> {
  $$CatalogMetadataTableOrderingComposer({
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

class $$CatalogMetadataTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $CatalogMetadataTable> {
  $$CatalogMetadataTableAnnotationComposer({
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

class $$CatalogMetadataTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $CatalogMetadataTable,
          CatalogMetadataData,
          $$CatalogMetadataTableFilterComposer,
          $$CatalogMetadataTableOrderingComposer,
          $$CatalogMetadataTableAnnotationComposer,
          $$CatalogMetadataTableCreateCompanionBuilder,
          $$CatalogMetadataTableUpdateCompanionBuilder,
          (
            CatalogMetadataData,
            BaseReferences<
              _$CatalogDatabase,
              $CatalogMetadataTable,
              CatalogMetadataData
            >,
          ),
          CatalogMetadataData,
          PrefetchHooks Function()
        > {
  $$CatalogMetadataTableTableManager(
    _$CatalogDatabase db,
    $CatalogMetadataTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CatalogMetadataTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CatalogMetadataTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CatalogMetadataTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CatalogMetadataCompanion(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CatalogMetadataCompanion.insert(
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

typedef $$CatalogMetadataTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $CatalogMetadataTable,
      CatalogMetadataData,
      $$CatalogMetadataTableFilterComposer,
      $$CatalogMetadataTableOrderingComposer,
      $$CatalogMetadataTableAnnotationComposer,
      $$CatalogMetadataTableCreateCompanionBuilder,
      $$CatalogMetadataTableUpdateCompanionBuilder,
      (
        CatalogMetadataData,
        BaseReferences<
          _$CatalogDatabase,
          $CatalogMetadataTable,
          CatalogMetadataData
        >,
      ),
      CatalogMetadataData,
      PrefetchHooks Function()
    >;
typedef $$OperatorsTableCreateCompanionBuilder =
    OperatorsCompanion Function({
      required String id,
      required String nameKo,
      Value<String> nameEn,
      Value<int> rowid,
    });
typedef $$OperatorsTableUpdateCompanionBuilder =
    OperatorsCompanion Function({
      Value<String> id,
      Value<String> nameKo,
      Value<String> nameEn,
      Value<int> rowid,
    });

class $$OperatorsTableFilterComposer
    extends Composer<_$CatalogDatabase, $OperatorsTable> {
  $$OperatorsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameKo => $composableBuilder(
    column: $table.nameKo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameEn => $composableBuilder(
    column: $table.nameEn,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OperatorsTableOrderingComposer
    extends Composer<_$CatalogDatabase, $OperatorsTable> {
  $$OperatorsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameKo => $composableBuilder(
    column: $table.nameKo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameEn => $composableBuilder(
    column: $table.nameEn,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OperatorsTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $OperatorsTable> {
  $$OperatorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get nameKo =>
      $composableBuilder(column: $table.nameKo, builder: (column) => column);

  GeneratedColumn<String> get nameEn =>
      $composableBuilder(column: $table.nameEn, builder: (column) => column);
}

class $$OperatorsTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $OperatorsTable,
          Operator,
          $$OperatorsTableFilterComposer,
          $$OperatorsTableOrderingComposer,
          $$OperatorsTableAnnotationComposer,
          $$OperatorsTableCreateCompanionBuilder,
          $$OperatorsTableUpdateCompanionBuilder,
          (
            Operator,
            BaseReferences<_$CatalogDatabase, $OperatorsTable, Operator>,
          ),
          Operator,
          PrefetchHooks Function()
        > {
  $$OperatorsTableTableManager(_$CatalogDatabase db, $OperatorsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OperatorsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OperatorsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OperatorsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> nameKo = const Value.absent(),
                Value<String> nameEn = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OperatorsCompanion(
                id: id,
                nameKo: nameKo,
                nameEn: nameEn,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String nameKo,
                Value<String> nameEn = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OperatorsCompanion.insert(
                id: id,
                nameKo: nameKo,
                nameEn: nameEn,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OperatorsTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $OperatorsTable,
      Operator,
      $$OperatorsTableFilterComposer,
      $$OperatorsTableOrderingComposer,
      $$OperatorsTableAnnotationComposer,
      $$OperatorsTableCreateCompanionBuilder,
      $$OperatorsTableUpdateCompanionBuilder,
      (Operator, BaseReferences<_$CatalogDatabase, $OperatorsTable, Operator>),
      Operator,
      PrefetchHooks Function()
    >;
typedef $$LinesTableCreateCompanionBuilder =
    LinesCompanion Function({
      required String id,
      required String operatorId,
      required String nameKo,
      Value<String> nameEn,
      Value<String> color,
      Value<int> rowid,
    });
typedef $$LinesTableUpdateCompanionBuilder =
    LinesCompanion Function({
      Value<String> id,
      Value<String> operatorId,
      Value<String> nameKo,
      Value<String> nameEn,
      Value<String> color,
      Value<int> rowid,
    });

class $$LinesTableFilterComposer
    extends Composer<_$CatalogDatabase, $LinesTable> {
  $$LinesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operatorId => $composableBuilder(
    column: $table.operatorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameKo => $composableBuilder(
    column: $table.nameKo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameEn => $composableBuilder(
    column: $table.nameEn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LinesTableOrderingComposer
    extends Composer<_$CatalogDatabase, $LinesTable> {
  $$LinesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operatorId => $composableBuilder(
    column: $table.operatorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameKo => $composableBuilder(
    column: $table.nameKo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameEn => $composableBuilder(
    column: $table.nameEn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LinesTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $LinesTable> {
  $$LinesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get operatorId => $composableBuilder(
    column: $table.operatorId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nameKo =>
      $composableBuilder(column: $table.nameKo, builder: (column) => column);

  GeneratedColumn<String> get nameEn =>
      $composableBuilder(column: $table.nameEn, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);
}

class $$LinesTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $LinesTable,
          Line,
          $$LinesTableFilterComposer,
          $$LinesTableOrderingComposer,
          $$LinesTableAnnotationComposer,
          $$LinesTableCreateCompanionBuilder,
          $$LinesTableUpdateCompanionBuilder,
          (Line, BaseReferences<_$CatalogDatabase, $LinesTable, Line>),
          Line,
          PrefetchHooks Function()
        > {
  $$LinesTableTableManager(_$CatalogDatabase db, $LinesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LinesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LinesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LinesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> operatorId = const Value.absent(),
                Value<String> nameKo = const Value.absent(),
                Value<String> nameEn = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LinesCompanion(
                id: id,
                operatorId: operatorId,
                nameKo: nameKo,
                nameEn: nameEn,
                color: color,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String operatorId,
                required String nameKo,
                Value<String> nameEn = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LinesCompanion.insert(
                id: id,
                operatorId: operatorId,
                nameKo: nameKo,
                nameEn: nameEn,
                color: color,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LinesTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $LinesTable,
      Line,
      $$LinesTableFilterComposer,
      $$LinesTableOrderingComposer,
      $$LinesTableAnnotationComposer,
      $$LinesTableCreateCompanionBuilder,
      $$LinesTableUpdateCompanionBuilder,
      (Line, BaseReferences<_$CatalogDatabase, $LinesTable, Line>),
      Line,
      PrefetchHooks Function()
    >;
typedef $$StationsTableCreateCompanionBuilder =
    StationsCompanion Function({
      required String id,
      required String nameKo,
      Value<String> nameEn,
      required String normalizedName,
      Value<String> region,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<String> dataQualityLevel,
      Value<String> dataSourceType,
      Value<DateTime?> lastVerifiedAt,
      Value<int> rowid,
    });
typedef $$StationsTableUpdateCompanionBuilder =
    StationsCompanion Function({
      Value<String> id,
      Value<String> nameKo,
      Value<String> nameEn,
      Value<String> normalizedName,
      Value<String> region,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<String> dataQualityLevel,
      Value<String> dataSourceType,
      Value<DateTime?> lastVerifiedAt,
      Value<int> rowid,
    });

class $$StationsTableFilterComposer
    extends Composer<_$CatalogDatabase, $StationsTable> {
  $$StationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameKo => $composableBuilder(
    column: $table.nameKo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameEn => $composableBuilder(
    column: $table.nameEn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get normalizedName => $composableBuilder(
    column: $table.normalizedName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get region => $composableBuilder(
    column: $table.region,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dataQualityLevel => $composableBuilder(
    column: $table.dataQualityLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dataSourceType => $composableBuilder(
    column: $table.dataSourceType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastVerifiedAt => $composableBuilder(
    column: $table.lastVerifiedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StationsTableOrderingComposer
    extends Composer<_$CatalogDatabase, $StationsTable> {
  $$StationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameKo => $composableBuilder(
    column: $table.nameKo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameEn => $composableBuilder(
    column: $table.nameEn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get normalizedName => $composableBuilder(
    column: $table.normalizedName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get region => $composableBuilder(
    column: $table.region,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dataQualityLevel => $composableBuilder(
    column: $table.dataQualityLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dataSourceType => $composableBuilder(
    column: $table.dataSourceType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastVerifiedAt => $composableBuilder(
    column: $table.lastVerifiedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StationsTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $StationsTable> {
  $$StationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get nameKo =>
      $composableBuilder(column: $table.nameKo, builder: (column) => column);

  GeneratedColumn<String> get nameEn =>
      $composableBuilder(column: $table.nameEn, builder: (column) => column);

  GeneratedColumn<String> get normalizedName => $composableBuilder(
    column: $table.normalizedName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get region =>
      $composableBuilder(column: $table.region, builder: (column) => column);

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<String> get dataQualityLevel => $composableBuilder(
    column: $table.dataQualityLevel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get dataSourceType => $composableBuilder(
    column: $table.dataSourceType,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastVerifiedAt => $composableBuilder(
    column: $table.lastVerifiedAt,
    builder: (column) => column,
  );
}

class $$StationsTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $StationsTable,
          Station,
          $$StationsTableFilterComposer,
          $$StationsTableOrderingComposer,
          $$StationsTableAnnotationComposer,
          $$StationsTableCreateCompanionBuilder,
          $$StationsTableUpdateCompanionBuilder,
          (Station, BaseReferences<_$CatalogDatabase, $StationsTable, Station>),
          Station,
          PrefetchHooks Function()
        > {
  $$StationsTableTableManager(_$CatalogDatabase db, $StationsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> nameKo = const Value.absent(),
                Value<String> nameEn = const Value.absent(),
                Value<String> normalizedName = const Value.absent(),
                Value<String> region = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<String> dataQualityLevel = const Value.absent(),
                Value<String> dataSourceType = const Value.absent(),
                Value<DateTime?> lastVerifiedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StationsCompanion(
                id: id,
                nameKo: nameKo,
                nameEn: nameEn,
                normalizedName: normalizedName,
                region: region,
                latitude: latitude,
                longitude: longitude,
                dataQualityLevel: dataQualityLevel,
                dataSourceType: dataSourceType,
                lastVerifiedAt: lastVerifiedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String nameKo,
                Value<String> nameEn = const Value.absent(),
                required String normalizedName,
                Value<String> region = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<String> dataQualityLevel = const Value.absent(),
                Value<String> dataSourceType = const Value.absent(),
                Value<DateTime?> lastVerifiedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StationsCompanion.insert(
                id: id,
                nameKo: nameKo,
                nameEn: nameEn,
                normalizedName: normalizedName,
                region: region,
                latitude: latitude,
                longitude: longitude,
                dataQualityLevel: dataQualityLevel,
                dataSourceType: dataSourceType,
                lastVerifiedAt: lastVerifiedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StationsTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $StationsTable,
      Station,
      $$StationsTableFilterComposer,
      $$StationsTableOrderingComposer,
      $$StationsTableAnnotationComposer,
      $$StationsTableCreateCompanionBuilder,
      $$StationsTableUpdateCompanionBuilder,
      (Station, BaseReferences<_$CatalogDatabase, $StationsTable, Station>),
      Station,
      PrefetchHooks Function()
    >;
typedef $$StationAliasesTableCreateCompanionBuilder =
    StationAliasesCompanion Function({
      required String stationId,
      required String alias,
      required String normalizedAlias,
      Value<int> rowid,
    });
typedef $$StationAliasesTableUpdateCompanionBuilder =
    StationAliasesCompanion Function({
      Value<String> stationId,
      Value<String> alias,
      Value<String> normalizedAlias,
      Value<int> rowid,
    });

class $$StationAliasesTableFilterComposer
    extends Composer<_$CatalogDatabase, $StationAliasesTable> {
  $$StationAliasesTableFilterComposer({
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

  ColumnFilters<String> get alias => $composableBuilder(
    column: $table.alias,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get normalizedAlias => $composableBuilder(
    column: $table.normalizedAlias,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StationAliasesTableOrderingComposer
    extends Composer<_$CatalogDatabase, $StationAliasesTable> {
  $$StationAliasesTableOrderingComposer({
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

  ColumnOrderings<String> get alias => $composableBuilder(
    column: $table.alias,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get normalizedAlias => $composableBuilder(
    column: $table.normalizedAlias,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StationAliasesTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $StationAliasesTable> {
  $$StationAliasesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get stationId =>
      $composableBuilder(column: $table.stationId, builder: (column) => column);

  GeneratedColumn<String> get alias =>
      $composableBuilder(column: $table.alias, builder: (column) => column);

  GeneratedColumn<String> get normalizedAlias => $composableBuilder(
    column: $table.normalizedAlias,
    builder: (column) => column,
  );
}

class $$StationAliasesTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $StationAliasesTable,
          StationAliase,
          $$StationAliasesTableFilterComposer,
          $$StationAliasesTableOrderingComposer,
          $$StationAliasesTableAnnotationComposer,
          $$StationAliasesTableCreateCompanionBuilder,
          $$StationAliasesTableUpdateCompanionBuilder,
          (
            StationAliase,
            BaseReferences<
              _$CatalogDatabase,
              $StationAliasesTable,
              StationAliase
            >,
          ),
          StationAliase,
          PrefetchHooks Function()
        > {
  $$StationAliasesTableTableManager(
    _$CatalogDatabase db,
    $StationAliasesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StationAliasesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StationAliasesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StationAliasesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> stationId = const Value.absent(),
                Value<String> alias = const Value.absent(),
                Value<String> normalizedAlias = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StationAliasesCompanion(
                stationId: stationId,
                alias: alias,
                normalizedAlias: normalizedAlias,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String stationId,
                required String alias,
                required String normalizedAlias,
                Value<int> rowid = const Value.absent(),
              }) => StationAliasesCompanion.insert(
                stationId: stationId,
                alias: alias,
                normalizedAlias: normalizedAlias,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StationAliasesTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $StationAliasesTable,
      StationAliase,
      $$StationAliasesTableFilterComposer,
      $$StationAliasesTableOrderingComposer,
      $$StationAliasesTableAnnotationComposer,
      $$StationAliasesTableCreateCompanionBuilder,
      $$StationAliasesTableUpdateCompanionBuilder,
      (
        StationAliase,
        BaseReferences<_$CatalogDatabase, $StationAliasesTable, StationAliase>,
      ),
      StationAliase,
      PrefetchHooks Function()
    >;
typedef $$StationLinesTableCreateCompanionBuilder =
    StationLinesCompanion Function({
      required String stationId,
      required String lineId,
      Value<String> stationCode,
      required int lineSequence,
      Value<String> platformInfo,
      Value<int> rowid,
    });
typedef $$StationLinesTableUpdateCompanionBuilder =
    StationLinesCompanion Function({
      Value<String> stationId,
      Value<String> lineId,
      Value<String> stationCode,
      Value<int> lineSequence,
      Value<String> platformInfo,
      Value<int> rowid,
    });

class $$StationLinesTableFilterComposer
    extends Composer<_$CatalogDatabase, $StationLinesTable> {
  $$StationLinesTableFilterComposer({
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

  ColumnFilters<String> get stationCode => $composableBuilder(
    column: $table.stationCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lineSequence => $composableBuilder(
    column: $table.lineSequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get platformInfo => $composableBuilder(
    column: $table.platformInfo,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StationLinesTableOrderingComposer
    extends Composer<_$CatalogDatabase, $StationLinesTable> {
  $$StationLinesTableOrderingComposer({
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

  ColumnOrderings<String> get stationCode => $composableBuilder(
    column: $table.stationCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lineSequence => $composableBuilder(
    column: $table.lineSequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get platformInfo => $composableBuilder(
    column: $table.platformInfo,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StationLinesTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $StationLinesTable> {
  $$StationLinesTableAnnotationComposer({
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

  GeneratedColumn<String> get stationCode => $composableBuilder(
    column: $table.stationCode,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lineSequence => $composableBuilder(
    column: $table.lineSequence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get platformInfo => $composableBuilder(
    column: $table.platformInfo,
    builder: (column) => column,
  );
}

class $$StationLinesTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $StationLinesTable,
          StationLine,
          $$StationLinesTableFilterComposer,
          $$StationLinesTableOrderingComposer,
          $$StationLinesTableAnnotationComposer,
          $$StationLinesTableCreateCompanionBuilder,
          $$StationLinesTableUpdateCompanionBuilder,
          (
            StationLine,
            BaseReferences<_$CatalogDatabase, $StationLinesTable, StationLine>,
          ),
          StationLine,
          PrefetchHooks Function()
        > {
  $$StationLinesTableTableManager(
    _$CatalogDatabase db,
    $StationLinesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StationLinesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StationLinesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StationLinesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> stationId = const Value.absent(),
                Value<String> lineId = const Value.absent(),
                Value<String> stationCode = const Value.absent(),
                Value<int> lineSequence = const Value.absent(),
                Value<String> platformInfo = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StationLinesCompanion(
                stationId: stationId,
                lineId: lineId,
                stationCode: stationCode,
                lineSequence: lineSequence,
                platformInfo: platformInfo,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String stationId,
                required String lineId,
                Value<String> stationCode = const Value.absent(),
                required int lineSequence,
                Value<String> platformInfo = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StationLinesCompanion.insert(
                stationId: stationId,
                lineId: lineId,
                stationCode: stationCode,
                lineSequence: lineSequence,
                platformInfo: platformInfo,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StationLinesTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $StationLinesTable,
      StationLine,
      $$StationLinesTableFilterComposer,
      $$StationLinesTableOrderingComposer,
      $$StationLinesTableAnnotationComposer,
      $$StationLinesTableCreateCompanionBuilder,
      $$StationLinesTableUpdateCompanionBuilder,
      (
        StationLine,
        BaseReferences<_$CatalogDatabase, $StationLinesTable, StationLine>,
      ),
      StationLine,
      PrefetchHooks Function()
    >;
typedef $$NetworkEdgesTableCreateCompanionBuilder =
    NetworkEdgesCompanion Function({
      required String id,
      required String fromNodeId,
      required String toNodeId,
      Value<int> durationSeconds,
      Value<String> edgeType,
      Value<String> servicePattern,
      Value<bool> includesStairs,
      Value<String> accessibilityStatus,
      Value<int> reliabilityScore,
      Value<DateTime?> lastVerifiedAt,
      Value<int> rowid,
    });
typedef $$NetworkEdgesTableUpdateCompanionBuilder =
    NetworkEdgesCompanion Function({
      Value<String> id,
      Value<String> fromNodeId,
      Value<String> toNodeId,
      Value<int> durationSeconds,
      Value<String> edgeType,
      Value<String> servicePattern,
      Value<bool> includesStairs,
      Value<String> accessibilityStatus,
      Value<int> reliabilityScore,
      Value<DateTime?> lastVerifiedAt,
      Value<int> rowid,
    });

class $$NetworkEdgesTableFilterComposer
    extends Composer<_$CatalogDatabase, $NetworkEdgesTable> {
  $$NetworkEdgesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fromNodeId => $composableBuilder(
    column: $table.fromNodeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toNodeId => $composableBuilder(
    column: $table.toNodeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get edgeType => $composableBuilder(
    column: $table.edgeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get servicePattern => $composableBuilder(
    column: $table.servicePattern,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get includesStairs => $composableBuilder(
    column: $table.includesStairs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accessibilityStatus => $composableBuilder(
    column: $table.accessibilityStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reliabilityScore => $composableBuilder(
    column: $table.reliabilityScore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastVerifiedAt => $composableBuilder(
    column: $table.lastVerifiedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NetworkEdgesTableOrderingComposer
    extends Composer<_$CatalogDatabase, $NetworkEdgesTable> {
  $$NetworkEdgesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fromNodeId => $composableBuilder(
    column: $table.fromNodeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toNodeId => $composableBuilder(
    column: $table.toNodeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get edgeType => $composableBuilder(
    column: $table.edgeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get servicePattern => $composableBuilder(
    column: $table.servicePattern,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get includesStairs => $composableBuilder(
    column: $table.includesStairs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accessibilityStatus => $composableBuilder(
    column: $table.accessibilityStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reliabilityScore => $composableBuilder(
    column: $table.reliabilityScore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastVerifiedAt => $composableBuilder(
    column: $table.lastVerifiedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NetworkEdgesTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $NetworkEdgesTable> {
  $$NetworkEdgesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get fromNodeId => $composableBuilder(
    column: $table.fromNodeId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get toNodeId =>
      $composableBuilder(column: $table.toNodeId, builder: (column) => column);

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<String> get edgeType =>
      $composableBuilder(column: $table.edgeType, builder: (column) => column);

  GeneratedColumn<String> get servicePattern => $composableBuilder(
    column: $table.servicePattern,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get includesStairs => $composableBuilder(
    column: $table.includesStairs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get accessibilityStatus => $composableBuilder(
    column: $table.accessibilityStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get reliabilityScore => $composableBuilder(
    column: $table.reliabilityScore,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastVerifiedAt => $composableBuilder(
    column: $table.lastVerifiedAt,
    builder: (column) => column,
  );
}

class $$NetworkEdgesTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $NetworkEdgesTable,
          NetworkEdge,
          $$NetworkEdgesTableFilterComposer,
          $$NetworkEdgesTableOrderingComposer,
          $$NetworkEdgesTableAnnotationComposer,
          $$NetworkEdgesTableCreateCompanionBuilder,
          $$NetworkEdgesTableUpdateCompanionBuilder,
          (
            NetworkEdge,
            BaseReferences<_$CatalogDatabase, $NetworkEdgesTable, NetworkEdge>,
          ),
          NetworkEdge,
          PrefetchHooks Function()
        > {
  $$NetworkEdgesTableTableManager(
    _$CatalogDatabase db,
    $NetworkEdgesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NetworkEdgesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NetworkEdgesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NetworkEdgesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> fromNodeId = const Value.absent(),
                Value<String> toNodeId = const Value.absent(),
                Value<int> durationSeconds = const Value.absent(),
                Value<String> edgeType = const Value.absent(),
                Value<String> servicePattern = const Value.absent(),
                Value<bool> includesStairs = const Value.absent(),
                Value<String> accessibilityStatus = const Value.absent(),
                Value<int> reliabilityScore = const Value.absent(),
                Value<DateTime?> lastVerifiedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NetworkEdgesCompanion(
                id: id,
                fromNodeId: fromNodeId,
                toNodeId: toNodeId,
                durationSeconds: durationSeconds,
                edgeType: edgeType,
                servicePattern: servicePattern,
                includesStairs: includesStairs,
                accessibilityStatus: accessibilityStatus,
                reliabilityScore: reliabilityScore,
                lastVerifiedAt: lastVerifiedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String fromNodeId,
                required String toNodeId,
                Value<int> durationSeconds = const Value.absent(),
                Value<String> edgeType = const Value.absent(),
                Value<String> servicePattern = const Value.absent(),
                Value<bool> includesStairs = const Value.absent(),
                Value<String> accessibilityStatus = const Value.absent(),
                Value<int> reliabilityScore = const Value.absent(),
                Value<DateTime?> lastVerifiedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NetworkEdgesCompanion.insert(
                id: id,
                fromNodeId: fromNodeId,
                toNodeId: toNodeId,
                durationSeconds: durationSeconds,
                edgeType: edgeType,
                servicePattern: servicePattern,
                includesStairs: includesStairs,
                accessibilityStatus: accessibilityStatus,
                reliabilityScore: reliabilityScore,
                lastVerifiedAt: lastVerifiedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NetworkEdgesTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $NetworkEdgesTable,
      NetworkEdge,
      $$NetworkEdgesTableFilterComposer,
      $$NetworkEdgesTableOrderingComposer,
      $$NetworkEdgesTableAnnotationComposer,
      $$NetworkEdgesTableCreateCompanionBuilder,
      $$NetworkEdgesTableUpdateCompanionBuilder,
      (
        NetworkEdge,
        BaseReferences<_$CatalogDatabase, $NetworkEdgesTable, NetworkEdge>,
      ),
      NetworkEdge,
      PrefetchHooks Function()
    >;
typedef $$StationExitsTableCreateCompanionBuilder =
    StationExitsCompanion Function({
      required String id,
      required String stationId,
      required String exitNumber,
      Value<String> description,
      Value<int> rowid,
    });
typedef $$StationExitsTableUpdateCompanionBuilder =
    StationExitsCompanion Function({
      Value<String> id,
      Value<String> stationId,
      Value<String> exitNumber,
      Value<String> description,
      Value<int> rowid,
    });

class $$StationExitsTableFilterComposer
    extends Composer<_$CatalogDatabase, $StationExitsTable> {
  $$StationExitsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stationId => $composableBuilder(
    column: $table.stationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exitNumber => $composableBuilder(
    column: $table.exitNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StationExitsTableOrderingComposer
    extends Composer<_$CatalogDatabase, $StationExitsTable> {
  $$StationExitsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stationId => $composableBuilder(
    column: $table.stationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exitNumber => $composableBuilder(
    column: $table.exitNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StationExitsTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $StationExitsTable> {
  $$StationExitsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get stationId =>
      $composableBuilder(column: $table.stationId, builder: (column) => column);

  GeneratedColumn<String> get exitNumber => $composableBuilder(
    column: $table.exitNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );
}

class $$StationExitsTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $StationExitsTable,
          StationExit,
          $$StationExitsTableFilterComposer,
          $$StationExitsTableOrderingComposer,
          $$StationExitsTableAnnotationComposer,
          $$StationExitsTableCreateCompanionBuilder,
          $$StationExitsTableUpdateCompanionBuilder,
          (
            StationExit,
            BaseReferences<_$CatalogDatabase, $StationExitsTable, StationExit>,
          ),
          StationExit,
          PrefetchHooks Function()
        > {
  $$StationExitsTableTableManager(
    _$CatalogDatabase db,
    $StationExitsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StationExitsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StationExitsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StationExitsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> stationId = const Value.absent(),
                Value<String> exitNumber = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StationExitsCompanion(
                id: id,
                stationId: stationId,
                exitNumber: exitNumber,
                description: description,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String stationId,
                required String exitNumber,
                Value<String> description = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StationExitsCompanion.insert(
                id: id,
                stationId: stationId,
                exitNumber: exitNumber,
                description: description,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StationExitsTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $StationExitsTable,
      StationExit,
      $$StationExitsTableFilterComposer,
      $$StationExitsTableOrderingComposer,
      $$StationExitsTableAnnotationComposer,
      $$StationExitsTableCreateCompanionBuilder,
      $$StationExitsTableUpdateCompanionBuilder,
      (
        StationExit,
        BaseReferences<_$CatalogDatabase, $StationExitsTable, StationExit>,
      ),
      StationExit,
      PrefetchHooks Function()
    >;
typedef $$FacilitiesTableCreateCompanionBuilder =
    FacilitiesCompanion Function({
      required String id,
      required String stationId,
      Value<String?> exitId,
      required String type,
      required String name,
      Value<String> status,
      Value<String> floorFrom,
      Value<String> floorTo,
      Value<String> description,
      Value<int> rowid,
    });
typedef $$FacilitiesTableUpdateCompanionBuilder =
    FacilitiesCompanion Function({
      Value<String> id,
      Value<String> stationId,
      Value<String?> exitId,
      Value<String> type,
      Value<String> name,
      Value<String> status,
      Value<String> floorFrom,
      Value<String> floorTo,
      Value<String> description,
      Value<int> rowid,
    });

class $$FacilitiesTableFilterComposer
    extends Composer<_$CatalogDatabase, $FacilitiesTable> {
  $$FacilitiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stationId => $composableBuilder(
    column: $table.stationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exitId => $composableBuilder(
    column: $table.exitId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get floorFrom => $composableBuilder(
    column: $table.floorFrom,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get floorTo => $composableBuilder(
    column: $table.floorTo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FacilitiesTableOrderingComposer
    extends Composer<_$CatalogDatabase, $FacilitiesTable> {
  $$FacilitiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stationId => $composableBuilder(
    column: $table.stationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exitId => $composableBuilder(
    column: $table.exitId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get floorFrom => $composableBuilder(
    column: $table.floorFrom,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get floorTo => $composableBuilder(
    column: $table.floorTo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FacilitiesTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $FacilitiesTable> {
  $$FacilitiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get stationId =>
      $composableBuilder(column: $table.stationId, builder: (column) => column);

  GeneratedColumn<String> get exitId =>
      $composableBuilder(column: $table.exitId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get floorFrom =>
      $composableBuilder(column: $table.floorFrom, builder: (column) => column);

  GeneratedColumn<String> get floorTo =>
      $composableBuilder(column: $table.floorTo, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );
}

class $$FacilitiesTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $FacilitiesTable,
          Facility,
          $$FacilitiesTableFilterComposer,
          $$FacilitiesTableOrderingComposer,
          $$FacilitiesTableAnnotationComposer,
          $$FacilitiesTableCreateCompanionBuilder,
          $$FacilitiesTableUpdateCompanionBuilder,
          (
            Facility,
            BaseReferences<_$CatalogDatabase, $FacilitiesTable, Facility>,
          ),
          Facility,
          PrefetchHooks Function()
        > {
  $$FacilitiesTableTableManager(_$CatalogDatabase db, $FacilitiesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FacilitiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FacilitiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FacilitiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> stationId = const Value.absent(),
                Value<String?> exitId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> floorFrom = const Value.absent(),
                Value<String> floorTo = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FacilitiesCompanion(
                id: id,
                stationId: stationId,
                exitId: exitId,
                type: type,
                name: name,
                status: status,
                floorFrom: floorFrom,
                floorTo: floorTo,
                description: description,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String stationId,
                Value<String?> exitId = const Value.absent(),
                required String type,
                required String name,
                Value<String> status = const Value.absent(),
                Value<String> floorFrom = const Value.absent(),
                Value<String> floorTo = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FacilitiesCompanion.insert(
                id: id,
                stationId: stationId,
                exitId: exitId,
                type: type,
                name: name,
                status: status,
                floorFrom: floorFrom,
                floorTo: floorTo,
                description: description,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FacilitiesTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $FacilitiesTable,
      Facility,
      $$FacilitiesTableFilterComposer,
      $$FacilitiesTableOrderingComposer,
      $$FacilitiesTableAnnotationComposer,
      $$FacilitiesTableCreateCompanionBuilder,
      $$FacilitiesTableUpdateCompanionBuilder,
      (Facility, BaseReferences<_$CatalogDatabase, $FacilitiesTable, Facility>),
      Facility,
      PrefetchHooks Function()
    >;
typedef $$StationAccessibilitySummariesTableCreateCompanionBuilder =
    StationAccessibilitySummariesCompanion Function({
      required String stationId,
      required String summary,
      Value<String> warning,
      Value<int> rowid,
    });
typedef $$StationAccessibilitySummariesTableUpdateCompanionBuilder =
    StationAccessibilitySummariesCompanion Function({
      Value<String> stationId,
      Value<String> summary,
      Value<String> warning,
      Value<int> rowid,
    });

class $$StationAccessibilitySummariesTableFilterComposer
    extends Composer<_$CatalogDatabase, $StationAccessibilitySummariesTable> {
  $$StationAccessibilitySummariesTableFilterComposer({
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

  ColumnFilters<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get warning => $composableBuilder(
    column: $table.warning,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StationAccessibilitySummariesTableOrderingComposer
    extends Composer<_$CatalogDatabase, $StationAccessibilitySummariesTable> {
  $$StationAccessibilitySummariesTableOrderingComposer({
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

  ColumnOrderings<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get warning => $composableBuilder(
    column: $table.warning,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StationAccessibilitySummariesTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $StationAccessibilitySummariesTable> {
  $$StationAccessibilitySummariesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get stationId =>
      $composableBuilder(column: $table.stationId, builder: (column) => column);

  GeneratedColumn<String> get summary =>
      $composableBuilder(column: $table.summary, builder: (column) => column);

  GeneratedColumn<String> get warning =>
      $composableBuilder(column: $table.warning, builder: (column) => column);
}

class $$StationAccessibilitySummariesTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $StationAccessibilitySummariesTable,
          StationAccessibilitySummary,
          $$StationAccessibilitySummariesTableFilterComposer,
          $$StationAccessibilitySummariesTableOrderingComposer,
          $$StationAccessibilitySummariesTableAnnotationComposer,
          $$StationAccessibilitySummariesTableCreateCompanionBuilder,
          $$StationAccessibilitySummariesTableUpdateCompanionBuilder,
          (
            StationAccessibilitySummary,
            BaseReferences<
              _$CatalogDatabase,
              $StationAccessibilitySummariesTable,
              StationAccessibilitySummary
            >,
          ),
          StationAccessibilitySummary,
          PrefetchHooks Function()
        > {
  $$StationAccessibilitySummariesTableTableManager(
    _$CatalogDatabase db,
    $StationAccessibilitySummariesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StationAccessibilitySummariesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$StationAccessibilitySummariesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$StationAccessibilitySummariesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> stationId = const Value.absent(),
                Value<String> summary = const Value.absent(),
                Value<String> warning = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StationAccessibilitySummariesCompanion(
                stationId: stationId,
                summary: summary,
                warning: warning,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String stationId,
                required String summary,
                Value<String> warning = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StationAccessibilitySummariesCompanion.insert(
                stationId: stationId,
                summary: summary,
                warning: warning,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StationAccessibilitySummariesTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $StationAccessibilitySummariesTable,
      StationAccessibilitySummary,
      $$StationAccessibilitySummariesTableFilterComposer,
      $$StationAccessibilitySummariesTableOrderingComposer,
      $$StationAccessibilitySummariesTableAnnotationComposer,
      $$StationAccessibilitySummariesTableCreateCompanionBuilder,
      $$StationAccessibilitySummariesTableUpdateCompanionBuilder,
      (
        StationAccessibilitySummary,
        BaseReferences<
          _$CatalogDatabase,
          $StationAccessibilitySummariesTable,
          StationAccessibilitySummary
        >,
      ),
      StationAccessibilitySummary,
      PrefetchHooks Function()
    >;
typedef $$InternalRouteNodesTableCreateCompanionBuilder =
    InternalRouteNodesCompanion Function({
      required String id,
      required String stationId,
      required String label,
      required String nodeType,
      Value<int> rowid,
    });
typedef $$InternalRouteNodesTableUpdateCompanionBuilder =
    InternalRouteNodesCompanion Function({
      Value<String> id,
      Value<String> stationId,
      Value<String> label,
      Value<String> nodeType,
      Value<int> rowid,
    });

class $$InternalRouteNodesTableFilterComposer
    extends Composer<_$CatalogDatabase, $InternalRouteNodesTable> {
  $$InternalRouteNodesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stationId => $composableBuilder(
    column: $table.stationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nodeType => $composableBuilder(
    column: $table.nodeType,
    builder: (column) => ColumnFilters(column),
  );
}

class $$InternalRouteNodesTableOrderingComposer
    extends Composer<_$CatalogDatabase, $InternalRouteNodesTable> {
  $$InternalRouteNodesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stationId => $composableBuilder(
    column: $table.stationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nodeType => $composableBuilder(
    column: $table.nodeType,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$InternalRouteNodesTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $InternalRouteNodesTable> {
  $$InternalRouteNodesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get stationId =>
      $composableBuilder(column: $table.stationId, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get nodeType =>
      $composableBuilder(column: $table.nodeType, builder: (column) => column);
}

class $$InternalRouteNodesTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $InternalRouteNodesTable,
          InternalRouteNode,
          $$InternalRouteNodesTableFilterComposer,
          $$InternalRouteNodesTableOrderingComposer,
          $$InternalRouteNodesTableAnnotationComposer,
          $$InternalRouteNodesTableCreateCompanionBuilder,
          $$InternalRouteNodesTableUpdateCompanionBuilder,
          (
            InternalRouteNode,
            BaseReferences<
              _$CatalogDatabase,
              $InternalRouteNodesTable,
              InternalRouteNode
            >,
          ),
          InternalRouteNode,
          PrefetchHooks Function()
        > {
  $$InternalRouteNodesTableTableManager(
    _$CatalogDatabase db,
    $InternalRouteNodesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InternalRouteNodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InternalRouteNodesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InternalRouteNodesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> stationId = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<String> nodeType = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InternalRouteNodesCompanion(
                id: id,
                stationId: stationId,
                label: label,
                nodeType: nodeType,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String stationId,
                required String label,
                required String nodeType,
                Value<int> rowid = const Value.absent(),
              }) => InternalRouteNodesCompanion.insert(
                id: id,
                stationId: stationId,
                label: label,
                nodeType: nodeType,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$InternalRouteNodesTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $InternalRouteNodesTable,
      InternalRouteNode,
      $$InternalRouteNodesTableFilterComposer,
      $$InternalRouteNodesTableOrderingComposer,
      $$InternalRouteNodesTableAnnotationComposer,
      $$InternalRouteNodesTableCreateCompanionBuilder,
      $$InternalRouteNodesTableUpdateCompanionBuilder,
      (
        InternalRouteNode,
        BaseReferences<
          _$CatalogDatabase,
          $InternalRouteNodesTable,
          InternalRouteNode
        >,
      ),
      InternalRouteNode,
      PrefetchHooks Function()
    >;
typedef $$InternalRouteEdgesTableCreateCompanionBuilder =
    InternalRouteEdgesCompanion Function({
      required String id,
      required String fromNodeId,
      required String toNodeId,
      Value<int> durationSeconds,
      Value<String> instruction,
      Value<int> rowid,
    });
typedef $$InternalRouteEdgesTableUpdateCompanionBuilder =
    InternalRouteEdgesCompanion Function({
      Value<String> id,
      Value<String> fromNodeId,
      Value<String> toNodeId,
      Value<int> durationSeconds,
      Value<String> instruction,
      Value<int> rowid,
    });

class $$InternalRouteEdgesTableFilterComposer
    extends Composer<_$CatalogDatabase, $InternalRouteEdgesTable> {
  $$InternalRouteEdgesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fromNodeId => $composableBuilder(
    column: $table.fromNodeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toNodeId => $composableBuilder(
    column: $table.toNodeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get instruction => $composableBuilder(
    column: $table.instruction,
    builder: (column) => ColumnFilters(column),
  );
}

class $$InternalRouteEdgesTableOrderingComposer
    extends Composer<_$CatalogDatabase, $InternalRouteEdgesTable> {
  $$InternalRouteEdgesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fromNodeId => $composableBuilder(
    column: $table.fromNodeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toNodeId => $composableBuilder(
    column: $table.toNodeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get instruction => $composableBuilder(
    column: $table.instruction,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$InternalRouteEdgesTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $InternalRouteEdgesTable> {
  $$InternalRouteEdgesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get fromNodeId => $composableBuilder(
    column: $table.fromNodeId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get toNodeId =>
      $composableBuilder(column: $table.toNodeId, builder: (column) => column);

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<String> get instruction => $composableBuilder(
    column: $table.instruction,
    builder: (column) => column,
  );
}

class $$InternalRouteEdgesTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $InternalRouteEdgesTable,
          InternalRouteEdge,
          $$InternalRouteEdgesTableFilterComposer,
          $$InternalRouteEdgesTableOrderingComposer,
          $$InternalRouteEdgesTableAnnotationComposer,
          $$InternalRouteEdgesTableCreateCompanionBuilder,
          $$InternalRouteEdgesTableUpdateCompanionBuilder,
          (
            InternalRouteEdge,
            BaseReferences<
              _$CatalogDatabase,
              $InternalRouteEdgesTable,
              InternalRouteEdge
            >,
          ),
          InternalRouteEdge,
          PrefetchHooks Function()
        > {
  $$InternalRouteEdgesTableTableManager(
    _$CatalogDatabase db,
    $InternalRouteEdgesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InternalRouteEdgesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InternalRouteEdgesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InternalRouteEdgesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> fromNodeId = const Value.absent(),
                Value<String> toNodeId = const Value.absent(),
                Value<int> durationSeconds = const Value.absent(),
                Value<String> instruction = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InternalRouteEdgesCompanion(
                id: id,
                fromNodeId: fromNodeId,
                toNodeId: toNodeId,
                durationSeconds: durationSeconds,
                instruction: instruction,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String fromNodeId,
                required String toNodeId,
                Value<int> durationSeconds = const Value.absent(),
                Value<String> instruction = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InternalRouteEdgesCompanion.insert(
                id: id,
                fromNodeId: fromNodeId,
                toNodeId: toNodeId,
                durationSeconds: durationSeconds,
                instruction: instruction,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$InternalRouteEdgesTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $InternalRouteEdgesTable,
      InternalRouteEdge,
      $$InternalRouteEdgesTableFilterComposer,
      $$InternalRouteEdgesTableOrderingComposer,
      $$InternalRouteEdgesTableAnnotationComposer,
      $$InternalRouteEdgesTableCreateCompanionBuilder,
      $$InternalRouteEdgesTableUpdateCompanionBuilder,
      (
        InternalRouteEdge,
        BaseReferences<
          _$CatalogDatabase,
          $InternalRouteEdgesTable,
          InternalRouteEdge
        >,
      ),
      InternalRouteEdge,
      PrefetchHooks Function()
    >;
typedef $$DataQualityRecordsTableCreateCompanionBuilder =
    DataQualityRecordsCompanion Function({
      required String id,
      required String targetType,
      required String targetId,
      required String qualityLevel,
      Value<DateTime?> checkedAt,
      Value<int> rowid,
    });
typedef $$DataQualityRecordsTableUpdateCompanionBuilder =
    DataQualityRecordsCompanion Function({
      Value<String> id,
      Value<String> targetType,
      Value<String> targetId,
      Value<String> qualityLevel,
      Value<DateTime?> checkedAt,
      Value<int> rowid,
    });

class $$DataQualityRecordsTableFilterComposer
    extends Composer<_$CatalogDatabase, $DataQualityRecordsTable> {
  $$DataQualityRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetType => $composableBuilder(
    column: $table.targetType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get qualityLevel => $composableBuilder(
    column: $table.qualityLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get checkedAt => $composableBuilder(
    column: $table.checkedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DataQualityRecordsTableOrderingComposer
    extends Composer<_$CatalogDatabase, $DataQualityRecordsTable> {
  $$DataQualityRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetType => $composableBuilder(
    column: $table.targetType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get qualityLevel => $composableBuilder(
    column: $table.qualityLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get checkedAt => $composableBuilder(
    column: $table.checkedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DataQualityRecordsTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $DataQualityRecordsTable> {
  $$DataQualityRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get targetType => $composableBuilder(
    column: $table.targetType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetId =>
      $composableBuilder(column: $table.targetId, builder: (column) => column);

  GeneratedColumn<String> get qualityLevel => $composableBuilder(
    column: $table.qualityLevel,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get checkedAt =>
      $composableBuilder(column: $table.checkedAt, builder: (column) => column);
}

class $$DataQualityRecordsTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $DataQualityRecordsTable,
          DataQualityRecord,
          $$DataQualityRecordsTableFilterComposer,
          $$DataQualityRecordsTableOrderingComposer,
          $$DataQualityRecordsTableAnnotationComposer,
          $$DataQualityRecordsTableCreateCompanionBuilder,
          $$DataQualityRecordsTableUpdateCompanionBuilder,
          (
            DataQualityRecord,
            BaseReferences<
              _$CatalogDatabase,
              $DataQualityRecordsTable,
              DataQualityRecord
            >,
          ),
          DataQualityRecord,
          PrefetchHooks Function()
        > {
  $$DataQualityRecordsTableTableManager(
    _$CatalogDatabase db,
    $DataQualityRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DataQualityRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DataQualityRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DataQualityRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> targetType = const Value.absent(),
                Value<String> targetId = const Value.absent(),
                Value<String> qualityLevel = const Value.absent(),
                Value<DateTime?> checkedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DataQualityRecordsCompanion(
                id: id,
                targetType: targetType,
                targetId: targetId,
                qualityLevel: qualityLevel,
                checkedAt: checkedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String targetType,
                required String targetId,
                required String qualityLevel,
                Value<DateTime?> checkedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DataQualityRecordsCompanion.insert(
                id: id,
                targetType: targetType,
                targetId: targetId,
                qualityLevel: qualityLevel,
                checkedAt: checkedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DataQualityRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $DataQualityRecordsTable,
      DataQualityRecord,
      $$DataQualityRecordsTableFilterComposer,
      $$DataQualityRecordsTableOrderingComposer,
      $$DataQualityRecordsTableAnnotationComposer,
      $$DataQualityRecordsTableCreateCompanionBuilder,
      $$DataQualityRecordsTableUpdateCompanionBuilder,
      (
        DataQualityRecord,
        BaseReferences<
          _$CatalogDatabase,
          $DataQualityRecordsTable,
          DataQualityRecord
        >,
      ),
      DataQualityRecord,
      PrefetchHooks Function()
    >;

class $CatalogDatabaseManager {
  final _$CatalogDatabase _db;
  $CatalogDatabaseManager(this._db);
  $$CatalogMetadataTableTableManager get catalogMetadata =>
      $$CatalogMetadataTableTableManager(_db, _db.catalogMetadata);
  $$OperatorsTableTableManager get operators =>
      $$OperatorsTableTableManager(_db, _db.operators);
  $$LinesTableTableManager get lines =>
      $$LinesTableTableManager(_db, _db.lines);
  $$StationsTableTableManager get stations =>
      $$StationsTableTableManager(_db, _db.stations);
  $$StationAliasesTableTableManager get stationAliases =>
      $$StationAliasesTableTableManager(_db, _db.stationAliases);
  $$StationLinesTableTableManager get stationLines =>
      $$StationLinesTableTableManager(_db, _db.stationLines);
  $$NetworkEdgesTableTableManager get networkEdges =>
      $$NetworkEdgesTableTableManager(_db, _db.networkEdges);
  $$StationExitsTableTableManager get stationExits =>
      $$StationExitsTableTableManager(_db, _db.stationExits);
  $$FacilitiesTableTableManager get facilities =>
      $$FacilitiesTableTableManager(_db, _db.facilities);
  $$StationAccessibilitySummariesTableTableManager
  get stationAccessibilitySummaries =>
      $$StationAccessibilitySummariesTableTableManager(
        _db,
        _db.stationAccessibilitySummaries,
      );
  $$InternalRouteNodesTableTableManager get internalRouteNodes =>
      $$InternalRouteNodesTableTableManager(_db, _db.internalRouteNodes);
  $$InternalRouteEdgesTableTableManager get internalRouteEdges =>
      $$InternalRouteEdgesTableTableManager(_db, _db.internalRouteEdges);
  $$DataQualityRecordsTableTableManager get dataQualityRecords =>
      $$DataQualityRecordsTableTableManager(_db, _db.dataQualityRecords);
}
