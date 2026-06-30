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

class $ServiceCalendarsTable extends ServiceCalendars
    with TableInfo<$ServiceCalendarsTable, ServiceCalendar> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ServiceCalendarsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _serviceIdMeta = const VerificationMeta(
    'serviceId',
  );
  @override
  late final GeneratedColumn<String> serviceId = GeneratedColumn<String>(
    'service_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mondayMeta = const VerificationMeta('monday');
  @override
  late final GeneratedColumn<bool> monday = GeneratedColumn<bool>(
    'monday',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("monday" IN (0, 1))',
    ),
  );
  static const VerificationMeta _tuesdayMeta = const VerificationMeta(
    'tuesday',
  );
  @override
  late final GeneratedColumn<bool> tuesday = GeneratedColumn<bool>(
    'tuesday',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("tuesday" IN (0, 1))',
    ),
  );
  static const VerificationMeta _wednesdayMeta = const VerificationMeta(
    'wednesday',
  );
  @override
  late final GeneratedColumn<bool> wednesday = GeneratedColumn<bool>(
    'wednesday',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("wednesday" IN (0, 1))',
    ),
  );
  static const VerificationMeta _thursdayMeta = const VerificationMeta(
    'thursday',
  );
  @override
  late final GeneratedColumn<bool> thursday = GeneratedColumn<bool>(
    'thursday',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("thursday" IN (0, 1))',
    ),
  );
  static const VerificationMeta _fridayMeta = const VerificationMeta('friday');
  @override
  late final GeneratedColumn<bool> friday = GeneratedColumn<bool>(
    'friday',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("friday" IN (0, 1))',
    ),
  );
  static const VerificationMeta _saturdayMeta = const VerificationMeta(
    'saturday',
  );
  @override
  late final GeneratedColumn<bool> saturday = GeneratedColumn<bool>(
    'saturday',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("saturday" IN (0, 1))',
    ),
  );
  static const VerificationMeta _sundayMeta = const VerificationMeta('sunday');
  @override
  late final GeneratedColumn<bool> sunday = GeneratedColumn<bool>(
    'sunday',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("sunday" IN (0, 1))',
    ),
  );
  static const VerificationMeta _startDateMeta = const VerificationMeta(
    'startDate',
  );
  @override
  late final GeneratedColumn<String> startDate = GeneratedColumn<String>(
    'start_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endDateMeta = const VerificationMeta(
    'endDate',
  );
  @override
  late final GeneratedColumn<String> endDate = GeneratedColumn<String>(
    'end_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timezoneMeta = const VerificationMeta(
    'timezone',
  );
  @override
  late final GeneratedColumn<String> timezone = GeneratedColumn<String>(
    'timezone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('Asia/Seoul'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    serviceId,
    monday,
    tuesday,
    wednesday,
    thursday,
    friday,
    saturday,
    sunday,
    startDate,
    endDate,
    timezone,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'service_calendars';
  @override
  VerificationContext validateIntegrity(
    Insertable<ServiceCalendar> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('service_id')) {
      context.handle(
        _serviceIdMeta,
        serviceId.isAcceptableOrUnknown(data['service_id']!, _serviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_serviceIdMeta);
    }
    if (data.containsKey('monday')) {
      context.handle(
        _mondayMeta,
        monday.isAcceptableOrUnknown(data['monday']!, _mondayMeta),
      );
    } else if (isInserting) {
      context.missing(_mondayMeta);
    }
    if (data.containsKey('tuesday')) {
      context.handle(
        _tuesdayMeta,
        tuesday.isAcceptableOrUnknown(data['tuesday']!, _tuesdayMeta),
      );
    } else if (isInserting) {
      context.missing(_tuesdayMeta);
    }
    if (data.containsKey('wednesday')) {
      context.handle(
        _wednesdayMeta,
        wednesday.isAcceptableOrUnknown(data['wednesday']!, _wednesdayMeta),
      );
    } else if (isInserting) {
      context.missing(_wednesdayMeta);
    }
    if (data.containsKey('thursday')) {
      context.handle(
        _thursdayMeta,
        thursday.isAcceptableOrUnknown(data['thursday']!, _thursdayMeta),
      );
    } else if (isInserting) {
      context.missing(_thursdayMeta);
    }
    if (data.containsKey('friday')) {
      context.handle(
        _fridayMeta,
        friday.isAcceptableOrUnknown(data['friday']!, _fridayMeta),
      );
    } else if (isInserting) {
      context.missing(_fridayMeta);
    }
    if (data.containsKey('saturday')) {
      context.handle(
        _saturdayMeta,
        saturday.isAcceptableOrUnknown(data['saturday']!, _saturdayMeta),
      );
    } else if (isInserting) {
      context.missing(_saturdayMeta);
    }
    if (data.containsKey('sunday')) {
      context.handle(
        _sundayMeta,
        sunday.isAcceptableOrUnknown(data['sunday']!, _sundayMeta),
      );
    } else if (isInserting) {
      context.missing(_sundayMeta);
    }
    if (data.containsKey('start_date')) {
      context.handle(
        _startDateMeta,
        startDate.isAcceptableOrUnknown(data['start_date']!, _startDateMeta),
      );
    } else if (isInserting) {
      context.missing(_startDateMeta);
    }
    if (data.containsKey('end_date')) {
      context.handle(
        _endDateMeta,
        endDate.isAcceptableOrUnknown(data['end_date']!, _endDateMeta),
      );
    } else if (isInserting) {
      context.missing(_endDateMeta);
    }
    if (data.containsKey('timezone')) {
      context.handle(
        _timezoneMeta,
        timezone.isAcceptableOrUnknown(data['timezone']!, _timezoneMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {serviceId};
  @override
  ServiceCalendar map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ServiceCalendar(
      serviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}service_id'],
      )!,
      monday: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}monday'],
      )!,
      tuesday: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}tuesday'],
      )!,
      wednesday: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}wednesday'],
      )!,
      thursday: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}thursday'],
      )!,
      friday: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}friday'],
      )!,
      saturday: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}saturday'],
      )!,
      sunday: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}sunday'],
      )!,
      startDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}start_date'],
      )!,
      endDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}end_date'],
      )!,
      timezone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}timezone'],
      )!,
    );
  }

  @override
  $ServiceCalendarsTable createAlias(String alias) {
    return $ServiceCalendarsTable(attachedDatabase, alias);
  }
}

class ServiceCalendar extends DataClass implements Insertable<ServiceCalendar> {
  final String serviceId;
  final bool monday;
  final bool tuesday;
  final bool wednesday;
  final bool thursday;
  final bool friday;
  final bool saturday;
  final bool sunday;
  final String startDate;
  final String endDate;
  final String timezone;
  const ServiceCalendar({
    required this.serviceId,
    required this.monday,
    required this.tuesday,
    required this.wednesday,
    required this.thursday,
    required this.friday,
    required this.saturday,
    required this.sunday,
    required this.startDate,
    required this.endDate,
    required this.timezone,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['service_id'] = Variable<String>(serviceId);
    map['monday'] = Variable<bool>(monday);
    map['tuesday'] = Variable<bool>(tuesday);
    map['wednesday'] = Variable<bool>(wednesday);
    map['thursday'] = Variable<bool>(thursday);
    map['friday'] = Variable<bool>(friday);
    map['saturday'] = Variable<bool>(saturday);
    map['sunday'] = Variable<bool>(sunday);
    map['start_date'] = Variable<String>(startDate);
    map['end_date'] = Variable<String>(endDate);
    map['timezone'] = Variable<String>(timezone);
    return map;
  }

  ServiceCalendarsCompanion toCompanion(bool nullToAbsent) {
    return ServiceCalendarsCompanion(
      serviceId: Value(serviceId),
      monday: Value(monday),
      tuesday: Value(tuesday),
      wednesday: Value(wednesday),
      thursday: Value(thursday),
      friday: Value(friday),
      saturday: Value(saturday),
      sunday: Value(sunday),
      startDate: Value(startDate),
      endDate: Value(endDate),
      timezone: Value(timezone),
    );
  }

  factory ServiceCalendar.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ServiceCalendar(
      serviceId: serializer.fromJson<String>(json['serviceId']),
      monday: serializer.fromJson<bool>(json['monday']),
      tuesday: serializer.fromJson<bool>(json['tuesday']),
      wednesday: serializer.fromJson<bool>(json['wednesday']),
      thursday: serializer.fromJson<bool>(json['thursday']),
      friday: serializer.fromJson<bool>(json['friday']),
      saturday: serializer.fromJson<bool>(json['saturday']),
      sunday: serializer.fromJson<bool>(json['sunday']),
      startDate: serializer.fromJson<String>(json['startDate']),
      endDate: serializer.fromJson<String>(json['endDate']),
      timezone: serializer.fromJson<String>(json['timezone']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'serviceId': serializer.toJson<String>(serviceId),
      'monday': serializer.toJson<bool>(monday),
      'tuesday': serializer.toJson<bool>(tuesday),
      'wednesday': serializer.toJson<bool>(wednesday),
      'thursday': serializer.toJson<bool>(thursday),
      'friday': serializer.toJson<bool>(friday),
      'saturday': serializer.toJson<bool>(saturday),
      'sunday': serializer.toJson<bool>(sunday),
      'startDate': serializer.toJson<String>(startDate),
      'endDate': serializer.toJson<String>(endDate),
      'timezone': serializer.toJson<String>(timezone),
    };
  }

  ServiceCalendar copyWith({
    String? serviceId,
    bool? monday,
    bool? tuesday,
    bool? wednesday,
    bool? thursday,
    bool? friday,
    bool? saturday,
    bool? sunday,
    String? startDate,
    String? endDate,
    String? timezone,
  }) => ServiceCalendar(
    serviceId: serviceId ?? this.serviceId,
    monday: monday ?? this.monday,
    tuesday: tuesday ?? this.tuesday,
    wednesday: wednesday ?? this.wednesday,
    thursday: thursday ?? this.thursday,
    friday: friday ?? this.friday,
    saturday: saturday ?? this.saturday,
    sunday: sunday ?? this.sunday,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    timezone: timezone ?? this.timezone,
  );
  ServiceCalendar copyWithCompanion(ServiceCalendarsCompanion data) {
    return ServiceCalendar(
      serviceId: data.serviceId.present ? data.serviceId.value : this.serviceId,
      monday: data.monday.present ? data.monday.value : this.monday,
      tuesday: data.tuesday.present ? data.tuesday.value : this.tuesday,
      wednesday: data.wednesday.present ? data.wednesday.value : this.wednesday,
      thursday: data.thursday.present ? data.thursday.value : this.thursday,
      friday: data.friday.present ? data.friday.value : this.friday,
      saturday: data.saturday.present ? data.saturday.value : this.saturday,
      sunday: data.sunday.present ? data.sunday.value : this.sunday,
      startDate: data.startDate.present ? data.startDate.value : this.startDate,
      endDate: data.endDate.present ? data.endDate.value : this.endDate,
      timezone: data.timezone.present ? data.timezone.value : this.timezone,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ServiceCalendar(')
          ..write('serviceId: $serviceId, ')
          ..write('monday: $monday, ')
          ..write('tuesday: $tuesday, ')
          ..write('wednesday: $wednesday, ')
          ..write('thursday: $thursday, ')
          ..write('friday: $friday, ')
          ..write('saturday: $saturday, ')
          ..write('sunday: $sunday, ')
          ..write('startDate: $startDate, ')
          ..write('endDate: $endDate, ')
          ..write('timezone: $timezone')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    serviceId,
    monday,
    tuesday,
    wednesday,
    thursday,
    friday,
    saturday,
    sunday,
    startDate,
    endDate,
    timezone,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ServiceCalendar &&
          other.serviceId == this.serviceId &&
          other.monday == this.monday &&
          other.tuesday == this.tuesday &&
          other.wednesday == this.wednesday &&
          other.thursday == this.thursday &&
          other.friday == this.friday &&
          other.saturday == this.saturday &&
          other.sunday == this.sunday &&
          other.startDate == this.startDate &&
          other.endDate == this.endDate &&
          other.timezone == this.timezone);
}

class ServiceCalendarsCompanion extends UpdateCompanion<ServiceCalendar> {
  final Value<String> serviceId;
  final Value<bool> monday;
  final Value<bool> tuesday;
  final Value<bool> wednesday;
  final Value<bool> thursday;
  final Value<bool> friday;
  final Value<bool> saturday;
  final Value<bool> sunday;
  final Value<String> startDate;
  final Value<String> endDate;
  final Value<String> timezone;
  final Value<int> rowid;
  const ServiceCalendarsCompanion({
    this.serviceId = const Value.absent(),
    this.monday = const Value.absent(),
    this.tuesday = const Value.absent(),
    this.wednesday = const Value.absent(),
    this.thursday = const Value.absent(),
    this.friday = const Value.absent(),
    this.saturday = const Value.absent(),
    this.sunday = const Value.absent(),
    this.startDate = const Value.absent(),
    this.endDate = const Value.absent(),
    this.timezone = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ServiceCalendarsCompanion.insert({
    required String serviceId,
    required bool monday,
    required bool tuesday,
    required bool wednesday,
    required bool thursday,
    required bool friday,
    required bool saturday,
    required bool sunday,
    required String startDate,
    required String endDate,
    this.timezone = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : serviceId = Value(serviceId),
       monday = Value(monday),
       tuesday = Value(tuesday),
       wednesday = Value(wednesday),
       thursday = Value(thursday),
       friday = Value(friday),
       saturday = Value(saturday),
       sunday = Value(sunday),
       startDate = Value(startDate),
       endDate = Value(endDate);
  static Insertable<ServiceCalendar> custom({
    Expression<String>? serviceId,
    Expression<bool>? monday,
    Expression<bool>? tuesday,
    Expression<bool>? wednesday,
    Expression<bool>? thursday,
    Expression<bool>? friday,
    Expression<bool>? saturday,
    Expression<bool>? sunday,
    Expression<String>? startDate,
    Expression<String>? endDate,
    Expression<String>? timezone,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (serviceId != null) 'service_id': serviceId,
      if (monday != null) 'monday': monday,
      if (tuesday != null) 'tuesday': tuesday,
      if (wednesday != null) 'wednesday': wednesday,
      if (thursday != null) 'thursday': thursday,
      if (friday != null) 'friday': friday,
      if (saturday != null) 'saturday': saturday,
      if (sunday != null) 'sunday': sunday,
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (timezone != null) 'timezone': timezone,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ServiceCalendarsCompanion copyWith({
    Value<String>? serviceId,
    Value<bool>? monday,
    Value<bool>? tuesday,
    Value<bool>? wednesday,
    Value<bool>? thursday,
    Value<bool>? friday,
    Value<bool>? saturday,
    Value<bool>? sunday,
    Value<String>? startDate,
    Value<String>? endDate,
    Value<String>? timezone,
    Value<int>? rowid,
  }) {
    return ServiceCalendarsCompanion(
      serviceId: serviceId ?? this.serviceId,
      monday: monday ?? this.monday,
      tuesday: tuesday ?? this.tuesday,
      wednesday: wednesday ?? this.wednesday,
      thursday: thursday ?? this.thursday,
      friday: friday ?? this.friday,
      saturday: saturday ?? this.saturday,
      sunday: sunday ?? this.sunday,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      timezone: timezone ?? this.timezone,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (serviceId.present) {
      map['service_id'] = Variable<String>(serviceId.value);
    }
    if (monday.present) {
      map['monday'] = Variable<bool>(monday.value);
    }
    if (tuesday.present) {
      map['tuesday'] = Variable<bool>(tuesday.value);
    }
    if (wednesday.present) {
      map['wednesday'] = Variable<bool>(wednesday.value);
    }
    if (thursday.present) {
      map['thursday'] = Variable<bool>(thursday.value);
    }
    if (friday.present) {
      map['friday'] = Variable<bool>(friday.value);
    }
    if (saturday.present) {
      map['saturday'] = Variable<bool>(saturday.value);
    }
    if (sunday.present) {
      map['sunday'] = Variable<bool>(sunday.value);
    }
    if (startDate.present) {
      map['start_date'] = Variable<String>(startDate.value);
    }
    if (endDate.present) {
      map['end_date'] = Variable<String>(endDate.value);
    }
    if (timezone.present) {
      map['timezone'] = Variable<String>(timezone.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ServiceCalendarsCompanion(')
          ..write('serviceId: $serviceId, ')
          ..write('monday: $monday, ')
          ..write('tuesday: $tuesday, ')
          ..write('wednesday: $wednesday, ')
          ..write('thursday: $thursday, ')
          ..write('friday: $friday, ')
          ..write('saturday: $saturday, ')
          ..write('sunday: $sunday, ')
          ..write('startDate: $startDate, ')
          ..write('endDate: $endDate, ')
          ..write('timezone: $timezone, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ServiceCalendarDatesTable extends ServiceCalendarDates
    with TableInfo<$ServiceCalendarDatesTable, ServiceCalendarDate> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ServiceCalendarDatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _serviceIdMeta = const VerificationMeta(
    'serviceId',
  );
  @override
  late final GeneratedColumn<String> serviceId = GeneratedColumn<String>(
    'service_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _exceptionTypeMeta = const VerificationMeta(
    'exceptionType',
  );
  @override
  late final GeneratedColumn<int> exceptionType = GeneratedColumn<int>(
    'exception_type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [serviceId, date, exceptionType];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'service_calendar_dates';
  @override
  VerificationContext validateIntegrity(
    Insertable<ServiceCalendarDate> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('service_id')) {
      context.handle(
        _serviceIdMeta,
        serviceId.isAcceptableOrUnknown(data['service_id']!, _serviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_serviceIdMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('exception_type')) {
      context.handle(
        _exceptionTypeMeta,
        exceptionType.isAcceptableOrUnknown(
          data['exception_type']!,
          _exceptionTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_exceptionTypeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {serviceId, date};
  @override
  ServiceCalendarDate map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ServiceCalendarDate(
      serviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}service_id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      exceptionType: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}exception_type'],
      )!,
    );
  }

  @override
  $ServiceCalendarDatesTable createAlias(String alias) {
    return $ServiceCalendarDatesTable(attachedDatabase, alias);
  }
}

class ServiceCalendarDate extends DataClass
    implements Insertable<ServiceCalendarDate> {
  final String serviceId;
  final String date;
  final int exceptionType;
  const ServiceCalendarDate({
    required this.serviceId,
    required this.date,
    required this.exceptionType,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['service_id'] = Variable<String>(serviceId);
    map['date'] = Variable<String>(date);
    map['exception_type'] = Variable<int>(exceptionType);
    return map;
  }

  ServiceCalendarDatesCompanion toCompanion(bool nullToAbsent) {
    return ServiceCalendarDatesCompanion(
      serviceId: Value(serviceId),
      date: Value(date),
      exceptionType: Value(exceptionType),
    );
  }

  factory ServiceCalendarDate.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ServiceCalendarDate(
      serviceId: serializer.fromJson<String>(json['serviceId']),
      date: serializer.fromJson<String>(json['date']),
      exceptionType: serializer.fromJson<int>(json['exceptionType']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'serviceId': serializer.toJson<String>(serviceId),
      'date': serializer.toJson<String>(date),
      'exceptionType': serializer.toJson<int>(exceptionType),
    };
  }

  ServiceCalendarDate copyWith({
    String? serviceId,
    String? date,
    int? exceptionType,
  }) => ServiceCalendarDate(
    serviceId: serviceId ?? this.serviceId,
    date: date ?? this.date,
    exceptionType: exceptionType ?? this.exceptionType,
  );
  ServiceCalendarDate copyWithCompanion(ServiceCalendarDatesCompanion data) {
    return ServiceCalendarDate(
      serviceId: data.serviceId.present ? data.serviceId.value : this.serviceId,
      date: data.date.present ? data.date.value : this.date,
      exceptionType: data.exceptionType.present
          ? data.exceptionType.value
          : this.exceptionType,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ServiceCalendarDate(')
          ..write('serviceId: $serviceId, ')
          ..write('date: $date, ')
          ..write('exceptionType: $exceptionType')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(serviceId, date, exceptionType);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ServiceCalendarDate &&
          other.serviceId == this.serviceId &&
          other.date == this.date &&
          other.exceptionType == this.exceptionType);
}

class ServiceCalendarDatesCompanion
    extends UpdateCompanion<ServiceCalendarDate> {
  final Value<String> serviceId;
  final Value<String> date;
  final Value<int> exceptionType;
  final Value<int> rowid;
  const ServiceCalendarDatesCompanion({
    this.serviceId = const Value.absent(),
    this.date = const Value.absent(),
    this.exceptionType = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ServiceCalendarDatesCompanion.insert({
    required String serviceId,
    required String date,
    required int exceptionType,
    this.rowid = const Value.absent(),
  }) : serviceId = Value(serviceId),
       date = Value(date),
       exceptionType = Value(exceptionType);
  static Insertable<ServiceCalendarDate> custom({
    Expression<String>? serviceId,
    Expression<String>? date,
    Expression<int>? exceptionType,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (serviceId != null) 'service_id': serviceId,
      if (date != null) 'date': date,
      if (exceptionType != null) 'exception_type': exceptionType,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ServiceCalendarDatesCompanion copyWith({
    Value<String>? serviceId,
    Value<String>? date,
    Value<int>? exceptionType,
    Value<int>? rowid,
  }) {
    return ServiceCalendarDatesCompanion(
      serviceId: serviceId ?? this.serviceId,
      date: date ?? this.date,
      exceptionType: exceptionType ?? this.exceptionType,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (serviceId.present) {
      map['service_id'] = Variable<String>(serviceId.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (exceptionType.present) {
      map['exception_type'] = Variable<int>(exceptionType.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ServiceCalendarDatesCompanion(')
          ..write('serviceId: $serviceId, ')
          ..write('date: $date, ')
          ..write('exceptionType: $exceptionType, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TransitRoutesTable extends TransitRoutes
    with TableInfo<$TransitRoutesTable, TransitRoute> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransitRoutesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _routeShortNameMeta = const VerificationMeta(
    'routeShortName',
  );
  @override
  late final GeneratedColumn<String> routeShortName = GeneratedColumn<String>(
    'route_short_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _routeLongNameMeta = const VerificationMeta(
    'routeLongName',
  );
  @override
  late final GeneratedColumn<String> routeLongName = GeneratedColumn<String>(
    'route_long_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _directionNameMeta = const VerificationMeta(
    'directionName',
  );
  @override
  late final GeneratedColumn<String> directionName = GeneratedColumn<String>(
    'direction_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _timezoneMeta = const VerificationMeta(
    'timezone',
  );
  @override
  late final GeneratedColumn<String> timezone = GeneratedColumn<String>(
    'timezone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('Asia/Seoul'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    lineId,
    routeShortName,
    routeLongName,
    directionName,
    timezone,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transit_routes';
  @override
  VerificationContext validateIntegrity(
    Insertable<TransitRoute> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('line_id')) {
      context.handle(
        _lineIdMeta,
        lineId.isAcceptableOrUnknown(data['line_id']!, _lineIdMeta),
      );
    } else if (isInserting) {
      context.missing(_lineIdMeta);
    }
    if (data.containsKey('route_short_name')) {
      context.handle(
        _routeShortNameMeta,
        routeShortName.isAcceptableOrUnknown(
          data['route_short_name']!,
          _routeShortNameMeta,
        ),
      );
    }
    if (data.containsKey('route_long_name')) {
      context.handle(
        _routeLongNameMeta,
        routeLongName.isAcceptableOrUnknown(
          data['route_long_name']!,
          _routeLongNameMeta,
        ),
      );
    }
    if (data.containsKey('direction_name')) {
      context.handle(
        _directionNameMeta,
        directionName.isAcceptableOrUnknown(
          data['direction_name']!,
          _directionNameMeta,
        ),
      );
    }
    if (data.containsKey('timezone')) {
      context.handle(
        _timezoneMeta,
        timezone.isAcceptableOrUnknown(data['timezone']!, _timezoneMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TransitRoute map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TransitRoute(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      lineId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}line_id'],
      )!,
      routeShortName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}route_short_name'],
      )!,
      routeLongName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}route_long_name'],
      )!,
      directionName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}direction_name'],
      )!,
      timezone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}timezone'],
      )!,
    );
  }

  @override
  $TransitRoutesTable createAlias(String alias) {
    return $TransitRoutesTable(attachedDatabase, alias);
  }
}

class TransitRoute extends DataClass implements Insertable<TransitRoute> {
  final String id;
  final String lineId;
  final String routeShortName;
  final String routeLongName;
  final String directionName;
  final String timezone;
  const TransitRoute({
    required this.id,
    required this.lineId,
    required this.routeShortName,
    required this.routeLongName,
    required this.directionName,
    required this.timezone,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['line_id'] = Variable<String>(lineId);
    map['route_short_name'] = Variable<String>(routeShortName);
    map['route_long_name'] = Variable<String>(routeLongName);
    map['direction_name'] = Variable<String>(directionName);
    map['timezone'] = Variable<String>(timezone);
    return map;
  }

  TransitRoutesCompanion toCompanion(bool nullToAbsent) {
    return TransitRoutesCompanion(
      id: Value(id),
      lineId: Value(lineId),
      routeShortName: Value(routeShortName),
      routeLongName: Value(routeLongName),
      directionName: Value(directionName),
      timezone: Value(timezone),
    );
  }

  factory TransitRoute.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TransitRoute(
      id: serializer.fromJson<String>(json['id']),
      lineId: serializer.fromJson<String>(json['lineId']),
      routeShortName: serializer.fromJson<String>(json['routeShortName']),
      routeLongName: serializer.fromJson<String>(json['routeLongName']),
      directionName: serializer.fromJson<String>(json['directionName']),
      timezone: serializer.fromJson<String>(json['timezone']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'lineId': serializer.toJson<String>(lineId),
      'routeShortName': serializer.toJson<String>(routeShortName),
      'routeLongName': serializer.toJson<String>(routeLongName),
      'directionName': serializer.toJson<String>(directionName),
      'timezone': serializer.toJson<String>(timezone),
    };
  }

  TransitRoute copyWith({
    String? id,
    String? lineId,
    String? routeShortName,
    String? routeLongName,
    String? directionName,
    String? timezone,
  }) => TransitRoute(
    id: id ?? this.id,
    lineId: lineId ?? this.lineId,
    routeShortName: routeShortName ?? this.routeShortName,
    routeLongName: routeLongName ?? this.routeLongName,
    directionName: directionName ?? this.directionName,
    timezone: timezone ?? this.timezone,
  );
  TransitRoute copyWithCompanion(TransitRoutesCompanion data) {
    return TransitRoute(
      id: data.id.present ? data.id.value : this.id,
      lineId: data.lineId.present ? data.lineId.value : this.lineId,
      routeShortName: data.routeShortName.present
          ? data.routeShortName.value
          : this.routeShortName,
      routeLongName: data.routeLongName.present
          ? data.routeLongName.value
          : this.routeLongName,
      directionName: data.directionName.present
          ? data.directionName.value
          : this.directionName,
      timezone: data.timezone.present ? data.timezone.value : this.timezone,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TransitRoute(')
          ..write('id: $id, ')
          ..write('lineId: $lineId, ')
          ..write('routeShortName: $routeShortName, ')
          ..write('routeLongName: $routeLongName, ')
          ..write('directionName: $directionName, ')
          ..write('timezone: $timezone')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    lineId,
    routeShortName,
    routeLongName,
    directionName,
    timezone,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TransitRoute &&
          other.id == this.id &&
          other.lineId == this.lineId &&
          other.routeShortName == this.routeShortName &&
          other.routeLongName == this.routeLongName &&
          other.directionName == this.directionName &&
          other.timezone == this.timezone);
}

class TransitRoutesCompanion extends UpdateCompanion<TransitRoute> {
  final Value<String> id;
  final Value<String> lineId;
  final Value<String> routeShortName;
  final Value<String> routeLongName;
  final Value<String> directionName;
  final Value<String> timezone;
  final Value<int> rowid;
  const TransitRoutesCompanion({
    this.id = const Value.absent(),
    this.lineId = const Value.absent(),
    this.routeShortName = const Value.absent(),
    this.routeLongName = const Value.absent(),
    this.directionName = const Value.absent(),
    this.timezone = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TransitRoutesCompanion.insert({
    required String id,
    required String lineId,
    this.routeShortName = const Value.absent(),
    this.routeLongName = const Value.absent(),
    this.directionName = const Value.absent(),
    this.timezone = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       lineId = Value(lineId);
  static Insertable<TransitRoute> custom({
    Expression<String>? id,
    Expression<String>? lineId,
    Expression<String>? routeShortName,
    Expression<String>? routeLongName,
    Expression<String>? directionName,
    Expression<String>? timezone,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (lineId != null) 'line_id': lineId,
      if (routeShortName != null) 'route_short_name': routeShortName,
      if (routeLongName != null) 'route_long_name': routeLongName,
      if (directionName != null) 'direction_name': directionName,
      if (timezone != null) 'timezone': timezone,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TransitRoutesCompanion copyWith({
    Value<String>? id,
    Value<String>? lineId,
    Value<String>? routeShortName,
    Value<String>? routeLongName,
    Value<String>? directionName,
    Value<String>? timezone,
    Value<int>? rowid,
  }) {
    return TransitRoutesCompanion(
      id: id ?? this.id,
      lineId: lineId ?? this.lineId,
      routeShortName: routeShortName ?? this.routeShortName,
      routeLongName: routeLongName ?? this.routeLongName,
      directionName: directionName ?? this.directionName,
      timezone: timezone ?? this.timezone,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (lineId.present) {
      map['line_id'] = Variable<String>(lineId.value);
    }
    if (routeShortName.present) {
      map['route_short_name'] = Variable<String>(routeShortName.value);
    }
    if (routeLongName.present) {
      map['route_long_name'] = Variable<String>(routeLongName.value);
    }
    if (directionName.present) {
      map['direction_name'] = Variable<String>(directionName.value);
    }
    if (timezone.present) {
      map['timezone'] = Variable<String>(timezone.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransitRoutesCompanion(')
          ..write('id: $id, ')
          ..write('lineId: $lineId, ')
          ..write('routeShortName: $routeShortName, ')
          ..write('routeLongName: $routeLongName, ')
          ..write('directionName: $directionName, ')
          ..write('timezone: $timezone, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TransitTripsTable extends TransitTrips
    with TableInfo<$TransitTripsTable, TransitTrip> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransitTripsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
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
  static const VerificationMeta _serviceIdMeta = const VerificationMeta(
    'serviceId',
  );
  @override
  late final GeneratedColumn<String> serviceId = GeneratedColumn<String>(
    'service_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tripHeadsignMeta = const VerificationMeta(
    'tripHeadsign',
  );
  @override
  late final GeneratedColumn<String> tripHeadsign = GeneratedColumn<String>(
    'trip_headsign',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _directionIdMeta = const VerificationMeta(
    'directionId',
  );
  @override
  late final GeneratedColumn<String> directionId = GeneratedColumn<String>(
    'direction_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
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
    defaultValue: const Constant('LOCAL'),
  );
  static const VerificationMeta _serviceDayStartSecondsMeta =
      const VerificationMeta('serviceDayStartSeconds');
  @override
  late final GeneratedColumn<int> serviceDayStartSeconds = GeneratedColumn<int>(
    'service_day_start_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    routeId,
    serviceId,
    tripHeadsign,
    directionId,
    servicePattern,
    serviceDayStartSeconds,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transit_trips';
  @override
  VerificationContext validateIntegrity(
    Insertable<TransitTrip> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('route_id')) {
      context.handle(
        _routeIdMeta,
        routeId.isAcceptableOrUnknown(data['route_id']!, _routeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_routeIdMeta);
    }
    if (data.containsKey('service_id')) {
      context.handle(
        _serviceIdMeta,
        serviceId.isAcceptableOrUnknown(data['service_id']!, _serviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_serviceIdMeta);
    }
    if (data.containsKey('trip_headsign')) {
      context.handle(
        _tripHeadsignMeta,
        tripHeadsign.isAcceptableOrUnknown(
          data['trip_headsign']!,
          _tripHeadsignMeta,
        ),
      );
    }
    if (data.containsKey('direction_id')) {
      context.handle(
        _directionIdMeta,
        directionId.isAcceptableOrUnknown(
          data['direction_id']!,
          _directionIdMeta,
        ),
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
    if (data.containsKey('service_day_start_seconds')) {
      context.handle(
        _serviceDayStartSecondsMeta,
        serviceDayStartSeconds.isAcceptableOrUnknown(
          data['service_day_start_seconds']!,
          _serviceDayStartSecondsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TransitTrip map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TransitTrip(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      routeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}route_id'],
      )!,
      serviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}service_id'],
      )!,
      tripHeadsign: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trip_headsign'],
      )!,
      directionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}direction_id'],
      )!,
      servicePattern: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}service_pattern'],
      )!,
      serviceDayStartSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}service_day_start_seconds'],
      )!,
    );
  }

  @override
  $TransitTripsTable createAlias(String alias) {
    return $TransitTripsTable(attachedDatabase, alias);
  }
}

class TransitTrip extends DataClass implements Insertable<TransitTrip> {
  final String id;
  final String routeId;
  final String serviceId;
  final String tripHeadsign;
  final String directionId;
  final String servicePattern;
  final int serviceDayStartSeconds;
  const TransitTrip({
    required this.id,
    required this.routeId,
    required this.serviceId,
    required this.tripHeadsign,
    required this.directionId,
    required this.servicePattern,
    required this.serviceDayStartSeconds,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['route_id'] = Variable<String>(routeId);
    map['service_id'] = Variable<String>(serviceId);
    map['trip_headsign'] = Variable<String>(tripHeadsign);
    map['direction_id'] = Variable<String>(directionId);
    map['service_pattern'] = Variable<String>(servicePattern);
    map['service_day_start_seconds'] = Variable<int>(serviceDayStartSeconds);
    return map;
  }

  TransitTripsCompanion toCompanion(bool nullToAbsent) {
    return TransitTripsCompanion(
      id: Value(id),
      routeId: Value(routeId),
      serviceId: Value(serviceId),
      tripHeadsign: Value(tripHeadsign),
      directionId: Value(directionId),
      servicePattern: Value(servicePattern),
      serviceDayStartSeconds: Value(serviceDayStartSeconds),
    );
  }

  factory TransitTrip.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TransitTrip(
      id: serializer.fromJson<String>(json['id']),
      routeId: serializer.fromJson<String>(json['routeId']),
      serviceId: serializer.fromJson<String>(json['serviceId']),
      tripHeadsign: serializer.fromJson<String>(json['tripHeadsign']),
      directionId: serializer.fromJson<String>(json['directionId']),
      servicePattern: serializer.fromJson<String>(json['servicePattern']),
      serviceDayStartSeconds: serializer.fromJson<int>(
        json['serviceDayStartSeconds'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'routeId': serializer.toJson<String>(routeId),
      'serviceId': serializer.toJson<String>(serviceId),
      'tripHeadsign': serializer.toJson<String>(tripHeadsign),
      'directionId': serializer.toJson<String>(directionId),
      'servicePattern': serializer.toJson<String>(servicePattern),
      'serviceDayStartSeconds': serializer.toJson<int>(serviceDayStartSeconds),
    };
  }

  TransitTrip copyWith({
    String? id,
    String? routeId,
    String? serviceId,
    String? tripHeadsign,
    String? directionId,
    String? servicePattern,
    int? serviceDayStartSeconds,
  }) => TransitTrip(
    id: id ?? this.id,
    routeId: routeId ?? this.routeId,
    serviceId: serviceId ?? this.serviceId,
    tripHeadsign: tripHeadsign ?? this.tripHeadsign,
    directionId: directionId ?? this.directionId,
    servicePattern: servicePattern ?? this.servicePattern,
    serviceDayStartSeconds:
        serviceDayStartSeconds ?? this.serviceDayStartSeconds,
  );
  TransitTrip copyWithCompanion(TransitTripsCompanion data) {
    return TransitTrip(
      id: data.id.present ? data.id.value : this.id,
      routeId: data.routeId.present ? data.routeId.value : this.routeId,
      serviceId: data.serviceId.present ? data.serviceId.value : this.serviceId,
      tripHeadsign: data.tripHeadsign.present
          ? data.tripHeadsign.value
          : this.tripHeadsign,
      directionId: data.directionId.present
          ? data.directionId.value
          : this.directionId,
      servicePattern: data.servicePattern.present
          ? data.servicePattern.value
          : this.servicePattern,
      serviceDayStartSeconds: data.serviceDayStartSeconds.present
          ? data.serviceDayStartSeconds.value
          : this.serviceDayStartSeconds,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TransitTrip(')
          ..write('id: $id, ')
          ..write('routeId: $routeId, ')
          ..write('serviceId: $serviceId, ')
          ..write('tripHeadsign: $tripHeadsign, ')
          ..write('directionId: $directionId, ')
          ..write('servicePattern: $servicePattern, ')
          ..write('serviceDayStartSeconds: $serviceDayStartSeconds')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    routeId,
    serviceId,
    tripHeadsign,
    directionId,
    servicePattern,
    serviceDayStartSeconds,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TransitTrip &&
          other.id == this.id &&
          other.routeId == this.routeId &&
          other.serviceId == this.serviceId &&
          other.tripHeadsign == this.tripHeadsign &&
          other.directionId == this.directionId &&
          other.servicePattern == this.servicePattern &&
          other.serviceDayStartSeconds == this.serviceDayStartSeconds);
}

class TransitTripsCompanion extends UpdateCompanion<TransitTrip> {
  final Value<String> id;
  final Value<String> routeId;
  final Value<String> serviceId;
  final Value<String> tripHeadsign;
  final Value<String> directionId;
  final Value<String> servicePattern;
  final Value<int> serviceDayStartSeconds;
  final Value<int> rowid;
  const TransitTripsCompanion({
    this.id = const Value.absent(),
    this.routeId = const Value.absent(),
    this.serviceId = const Value.absent(),
    this.tripHeadsign = const Value.absent(),
    this.directionId = const Value.absent(),
    this.servicePattern = const Value.absent(),
    this.serviceDayStartSeconds = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TransitTripsCompanion.insert({
    required String id,
    required String routeId,
    required String serviceId,
    this.tripHeadsign = const Value.absent(),
    this.directionId = const Value.absent(),
    this.servicePattern = const Value.absent(),
    this.serviceDayStartSeconds = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       routeId = Value(routeId),
       serviceId = Value(serviceId);
  static Insertable<TransitTrip> custom({
    Expression<String>? id,
    Expression<String>? routeId,
    Expression<String>? serviceId,
    Expression<String>? tripHeadsign,
    Expression<String>? directionId,
    Expression<String>? servicePattern,
    Expression<int>? serviceDayStartSeconds,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (routeId != null) 'route_id': routeId,
      if (serviceId != null) 'service_id': serviceId,
      if (tripHeadsign != null) 'trip_headsign': tripHeadsign,
      if (directionId != null) 'direction_id': directionId,
      if (servicePattern != null) 'service_pattern': servicePattern,
      if (serviceDayStartSeconds != null)
        'service_day_start_seconds': serviceDayStartSeconds,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TransitTripsCompanion copyWith({
    Value<String>? id,
    Value<String>? routeId,
    Value<String>? serviceId,
    Value<String>? tripHeadsign,
    Value<String>? directionId,
    Value<String>? servicePattern,
    Value<int>? serviceDayStartSeconds,
    Value<int>? rowid,
  }) {
    return TransitTripsCompanion(
      id: id ?? this.id,
      routeId: routeId ?? this.routeId,
      serviceId: serviceId ?? this.serviceId,
      tripHeadsign: tripHeadsign ?? this.tripHeadsign,
      directionId: directionId ?? this.directionId,
      servicePattern: servicePattern ?? this.servicePattern,
      serviceDayStartSeconds:
          serviceDayStartSeconds ?? this.serviceDayStartSeconds,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (routeId.present) {
      map['route_id'] = Variable<String>(routeId.value);
    }
    if (serviceId.present) {
      map['service_id'] = Variable<String>(serviceId.value);
    }
    if (tripHeadsign.present) {
      map['trip_headsign'] = Variable<String>(tripHeadsign.value);
    }
    if (directionId.present) {
      map['direction_id'] = Variable<String>(directionId.value);
    }
    if (servicePattern.present) {
      map['service_pattern'] = Variable<String>(servicePattern.value);
    }
    if (serviceDayStartSeconds.present) {
      map['service_day_start_seconds'] = Variable<int>(
        serviceDayStartSeconds.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransitTripsCompanion(')
          ..write('id: $id, ')
          ..write('routeId: $routeId, ')
          ..write('serviceId: $serviceId, ')
          ..write('tripHeadsign: $tripHeadsign, ')
          ..write('directionId: $directionId, ')
          ..write('servicePattern: $servicePattern, ')
          ..write('serviceDayStartSeconds: $serviceDayStartSeconds, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TransitStopTimesTable extends TransitStopTimes
    with TableInfo<$TransitStopTimesTable, TransitStopTime> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransitStopTimesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tripIdMeta = const VerificationMeta('tripId');
  @override
  late final GeneratedColumn<String> tripId = GeneratedColumn<String>(
    'trip_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stopSequenceMeta = const VerificationMeta(
    'stopSequence',
  );
  @override
  late final GeneratedColumn<int> stopSequence = GeneratedColumn<int>(
    'stop_sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
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
  static const VerificationMeta _lineIdMeta = const VerificationMeta('lineId');
  @override
  late final GeneratedColumn<String> lineId = GeneratedColumn<String>(
    'line_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _arrivalSecondsMeta = const VerificationMeta(
    'arrivalSeconds',
  );
  @override
  late final GeneratedColumn<int> arrivalSeconds = GeneratedColumn<int>(
    'arrival_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _departureSecondsMeta = const VerificationMeta(
    'departureSeconds',
  );
  @override
  late final GeneratedColumn<int> departureSeconds = GeneratedColumn<int>(
    'departure_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pickupTypeMeta = const VerificationMeta(
    'pickupType',
  );
  @override
  late final GeneratedColumn<int> pickupType = GeneratedColumn<int>(
    'pickup_type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _dropOffTypeMeta = const VerificationMeta(
    'dropOffType',
  );
  @override
  late final GeneratedColumn<int> dropOffType = GeneratedColumn<int>(
    'drop_off_type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    tripId,
    stopSequence,
    stationId,
    lineId,
    arrivalSeconds,
    departureSeconds,
    pickupType,
    dropOffType,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transit_stop_times';
  @override
  VerificationContext validateIntegrity(
    Insertable<TransitStopTime> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('trip_id')) {
      context.handle(
        _tripIdMeta,
        tripId.isAcceptableOrUnknown(data['trip_id']!, _tripIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tripIdMeta);
    }
    if (data.containsKey('stop_sequence')) {
      context.handle(
        _stopSequenceMeta,
        stopSequence.isAcceptableOrUnknown(
          data['stop_sequence']!,
          _stopSequenceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_stopSequenceMeta);
    }
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
    if (data.containsKey('arrival_seconds')) {
      context.handle(
        _arrivalSecondsMeta,
        arrivalSeconds.isAcceptableOrUnknown(
          data['arrival_seconds']!,
          _arrivalSecondsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_arrivalSecondsMeta);
    }
    if (data.containsKey('departure_seconds')) {
      context.handle(
        _departureSecondsMeta,
        departureSeconds.isAcceptableOrUnknown(
          data['departure_seconds']!,
          _departureSecondsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_departureSecondsMeta);
    }
    if (data.containsKey('pickup_type')) {
      context.handle(
        _pickupTypeMeta,
        pickupType.isAcceptableOrUnknown(data['pickup_type']!, _pickupTypeMeta),
      );
    }
    if (data.containsKey('drop_off_type')) {
      context.handle(
        _dropOffTypeMeta,
        dropOffType.isAcceptableOrUnknown(
          data['drop_off_type']!,
          _dropOffTypeMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tripId, stopSequence};
  @override
  TransitStopTime map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TransitStopTime(
      tripId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trip_id'],
      )!,
      stopSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}stop_sequence'],
      )!,
      stationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}station_id'],
      )!,
      lineId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}line_id'],
      )!,
      arrivalSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}arrival_seconds'],
      )!,
      departureSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}departure_seconds'],
      )!,
      pickupType: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pickup_type'],
      )!,
      dropOffType: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}drop_off_type'],
      )!,
    );
  }

  @override
  $TransitStopTimesTable createAlias(String alias) {
    return $TransitStopTimesTable(attachedDatabase, alias);
  }
}

class TransitStopTime extends DataClass implements Insertable<TransitStopTime> {
  final String tripId;
  final int stopSequence;
  final String stationId;
  final String lineId;
  final int arrivalSeconds;
  final int departureSeconds;
  final int pickupType;
  final int dropOffType;
  const TransitStopTime({
    required this.tripId,
    required this.stopSequence,
    required this.stationId,
    required this.lineId,
    required this.arrivalSeconds,
    required this.departureSeconds,
    required this.pickupType,
    required this.dropOffType,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['trip_id'] = Variable<String>(tripId);
    map['stop_sequence'] = Variable<int>(stopSequence);
    map['station_id'] = Variable<String>(stationId);
    map['line_id'] = Variable<String>(lineId);
    map['arrival_seconds'] = Variable<int>(arrivalSeconds);
    map['departure_seconds'] = Variable<int>(departureSeconds);
    map['pickup_type'] = Variable<int>(pickupType);
    map['drop_off_type'] = Variable<int>(dropOffType);
    return map;
  }

  TransitStopTimesCompanion toCompanion(bool nullToAbsent) {
    return TransitStopTimesCompanion(
      tripId: Value(tripId),
      stopSequence: Value(stopSequence),
      stationId: Value(stationId),
      lineId: Value(lineId),
      arrivalSeconds: Value(arrivalSeconds),
      departureSeconds: Value(departureSeconds),
      pickupType: Value(pickupType),
      dropOffType: Value(dropOffType),
    );
  }

  factory TransitStopTime.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TransitStopTime(
      tripId: serializer.fromJson<String>(json['tripId']),
      stopSequence: serializer.fromJson<int>(json['stopSequence']),
      stationId: serializer.fromJson<String>(json['stationId']),
      lineId: serializer.fromJson<String>(json['lineId']),
      arrivalSeconds: serializer.fromJson<int>(json['arrivalSeconds']),
      departureSeconds: serializer.fromJson<int>(json['departureSeconds']),
      pickupType: serializer.fromJson<int>(json['pickupType']),
      dropOffType: serializer.fromJson<int>(json['dropOffType']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tripId': serializer.toJson<String>(tripId),
      'stopSequence': serializer.toJson<int>(stopSequence),
      'stationId': serializer.toJson<String>(stationId),
      'lineId': serializer.toJson<String>(lineId),
      'arrivalSeconds': serializer.toJson<int>(arrivalSeconds),
      'departureSeconds': serializer.toJson<int>(departureSeconds),
      'pickupType': serializer.toJson<int>(pickupType),
      'dropOffType': serializer.toJson<int>(dropOffType),
    };
  }

  TransitStopTime copyWith({
    String? tripId,
    int? stopSequence,
    String? stationId,
    String? lineId,
    int? arrivalSeconds,
    int? departureSeconds,
    int? pickupType,
    int? dropOffType,
  }) => TransitStopTime(
    tripId: tripId ?? this.tripId,
    stopSequence: stopSequence ?? this.stopSequence,
    stationId: stationId ?? this.stationId,
    lineId: lineId ?? this.lineId,
    arrivalSeconds: arrivalSeconds ?? this.arrivalSeconds,
    departureSeconds: departureSeconds ?? this.departureSeconds,
    pickupType: pickupType ?? this.pickupType,
    dropOffType: dropOffType ?? this.dropOffType,
  );
  TransitStopTime copyWithCompanion(TransitStopTimesCompanion data) {
    return TransitStopTime(
      tripId: data.tripId.present ? data.tripId.value : this.tripId,
      stopSequence: data.stopSequence.present
          ? data.stopSequence.value
          : this.stopSequence,
      stationId: data.stationId.present ? data.stationId.value : this.stationId,
      lineId: data.lineId.present ? data.lineId.value : this.lineId,
      arrivalSeconds: data.arrivalSeconds.present
          ? data.arrivalSeconds.value
          : this.arrivalSeconds,
      departureSeconds: data.departureSeconds.present
          ? data.departureSeconds.value
          : this.departureSeconds,
      pickupType: data.pickupType.present
          ? data.pickupType.value
          : this.pickupType,
      dropOffType: data.dropOffType.present
          ? data.dropOffType.value
          : this.dropOffType,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TransitStopTime(')
          ..write('tripId: $tripId, ')
          ..write('stopSequence: $stopSequence, ')
          ..write('stationId: $stationId, ')
          ..write('lineId: $lineId, ')
          ..write('arrivalSeconds: $arrivalSeconds, ')
          ..write('departureSeconds: $departureSeconds, ')
          ..write('pickupType: $pickupType, ')
          ..write('dropOffType: $dropOffType')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    tripId,
    stopSequence,
    stationId,
    lineId,
    arrivalSeconds,
    departureSeconds,
    pickupType,
    dropOffType,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TransitStopTime &&
          other.tripId == this.tripId &&
          other.stopSequence == this.stopSequence &&
          other.stationId == this.stationId &&
          other.lineId == this.lineId &&
          other.arrivalSeconds == this.arrivalSeconds &&
          other.departureSeconds == this.departureSeconds &&
          other.pickupType == this.pickupType &&
          other.dropOffType == this.dropOffType);
}

class TransitStopTimesCompanion extends UpdateCompanion<TransitStopTime> {
  final Value<String> tripId;
  final Value<int> stopSequence;
  final Value<String> stationId;
  final Value<String> lineId;
  final Value<int> arrivalSeconds;
  final Value<int> departureSeconds;
  final Value<int> pickupType;
  final Value<int> dropOffType;
  final Value<int> rowid;
  const TransitStopTimesCompanion({
    this.tripId = const Value.absent(),
    this.stopSequence = const Value.absent(),
    this.stationId = const Value.absent(),
    this.lineId = const Value.absent(),
    this.arrivalSeconds = const Value.absent(),
    this.departureSeconds = const Value.absent(),
    this.pickupType = const Value.absent(),
    this.dropOffType = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TransitStopTimesCompanion.insert({
    required String tripId,
    required int stopSequence,
    required String stationId,
    required String lineId,
    required int arrivalSeconds,
    required int departureSeconds,
    this.pickupType = const Value.absent(),
    this.dropOffType = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : tripId = Value(tripId),
       stopSequence = Value(stopSequence),
       stationId = Value(stationId),
       lineId = Value(lineId),
       arrivalSeconds = Value(arrivalSeconds),
       departureSeconds = Value(departureSeconds);
  static Insertable<TransitStopTime> custom({
    Expression<String>? tripId,
    Expression<int>? stopSequence,
    Expression<String>? stationId,
    Expression<String>? lineId,
    Expression<int>? arrivalSeconds,
    Expression<int>? departureSeconds,
    Expression<int>? pickupType,
    Expression<int>? dropOffType,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tripId != null) 'trip_id': tripId,
      if (stopSequence != null) 'stop_sequence': stopSequence,
      if (stationId != null) 'station_id': stationId,
      if (lineId != null) 'line_id': lineId,
      if (arrivalSeconds != null) 'arrival_seconds': arrivalSeconds,
      if (departureSeconds != null) 'departure_seconds': departureSeconds,
      if (pickupType != null) 'pickup_type': pickupType,
      if (dropOffType != null) 'drop_off_type': dropOffType,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TransitStopTimesCompanion copyWith({
    Value<String>? tripId,
    Value<int>? stopSequence,
    Value<String>? stationId,
    Value<String>? lineId,
    Value<int>? arrivalSeconds,
    Value<int>? departureSeconds,
    Value<int>? pickupType,
    Value<int>? dropOffType,
    Value<int>? rowid,
  }) {
    return TransitStopTimesCompanion(
      tripId: tripId ?? this.tripId,
      stopSequence: stopSequence ?? this.stopSequence,
      stationId: stationId ?? this.stationId,
      lineId: lineId ?? this.lineId,
      arrivalSeconds: arrivalSeconds ?? this.arrivalSeconds,
      departureSeconds: departureSeconds ?? this.departureSeconds,
      pickupType: pickupType ?? this.pickupType,
      dropOffType: dropOffType ?? this.dropOffType,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tripId.present) {
      map['trip_id'] = Variable<String>(tripId.value);
    }
    if (stopSequence.present) {
      map['stop_sequence'] = Variable<int>(stopSequence.value);
    }
    if (stationId.present) {
      map['station_id'] = Variable<String>(stationId.value);
    }
    if (lineId.present) {
      map['line_id'] = Variable<String>(lineId.value);
    }
    if (arrivalSeconds.present) {
      map['arrival_seconds'] = Variable<int>(arrivalSeconds.value);
    }
    if (departureSeconds.present) {
      map['departure_seconds'] = Variable<int>(departureSeconds.value);
    }
    if (pickupType.present) {
      map['pickup_type'] = Variable<int>(pickupType.value);
    }
    if (dropOffType.present) {
      map['drop_off_type'] = Variable<int>(dropOffType.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransitStopTimesCompanion(')
          ..write('tripId: $tripId, ')
          ..write('stopSequence: $stopSequence, ')
          ..write('stationId: $stationId, ')
          ..write('lineId: $lineId, ')
          ..write('arrivalSeconds: $arrivalSeconds, ')
          ..write('departureSeconds: $departureSeconds, ')
          ..write('pickupType: $pickupType, ')
          ..write('dropOffType: $dropOffType, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TransitFrequenciesTable extends TransitFrequencies
    with TableInfo<$TransitFrequenciesTable, TransitFrequency> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransitFrequenciesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tripIdMeta = const VerificationMeta('tripId');
  @override
  late final GeneratedColumn<String> tripId = GeneratedColumn<String>(
    'trip_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startTimeSecondsMeta = const VerificationMeta(
    'startTimeSeconds',
  );
  @override
  late final GeneratedColumn<int> startTimeSeconds = GeneratedColumn<int>(
    'start_time_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endTimeSecondsMeta = const VerificationMeta(
    'endTimeSeconds',
  );
  @override
  late final GeneratedColumn<int> endTimeSeconds = GeneratedColumn<int>(
    'end_time_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _headwaySecondsMeta = const VerificationMeta(
    'headwaySeconds',
  );
  @override
  late final GeneratedColumn<int> headwaySeconds = GeneratedColumn<int>(
    'headway_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _exactTimesMeta = const VerificationMeta(
    'exactTimes',
  );
  @override
  late final GeneratedColumn<bool> exactTimes = GeneratedColumn<bool>(
    'exact_times',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("exact_times" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    tripId,
    startTimeSeconds,
    endTimeSeconds,
    headwaySeconds,
    exactTimes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transit_frequencies';
  @override
  VerificationContext validateIntegrity(
    Insertable<TransitFrequency> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('trip_id')) {
      context.handle(
        _tripIdMeta,
        tripId.isAcceptableOrUnknown(data['trip_id']!, _tripIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tripIdMeta);
    }
    if (data.containsKey('start_time_seconds')) {
      context.handle(
        _startTimeSecondsMeta,
        startTimeSeconds.isAcceptableOrUnknown(
          data['start_time_seconds']!,
          _startTimeSecondsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startTimeSecondsMeta);
    }
    if (data.containsKey('end_time_seconds')) {
      context.handle(
        _endTimeSecondsMeta,
        endTimeSeconds.isAcceptableOrUnknown(
          data['end_time_seconds']!,
          _endTimeSecondsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_endTimeSecondsMeta);
    }
    if (data.containsKey('headway_seconds')) {
      context.handle(
        _headwaySecondsMeta,
        headwaySeconds.isAcceptableOrUnknown(
          data['headway_seconds']!,
          _headwaySecondsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_headwaySecondsMeta);
    }
    if (data.containsKey('exact_times')) {
      context.handle(
        _exactTimesMeta,
        exactTimes.isAcceptableOrUnknown(data['exact_times']!, _exactTimesMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tripId, startTimeSeconds};
  @override
  TransitFrequency map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TransitFrequency(
      tripId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trip_id'],
      )!,
      startTimeSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_time_seconds'],
      )!,
      endTimeSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_time_seconds'],
      )!,
      headwaySeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}headway_seconds'],
      )!,
      exactTimes: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}exact_times'],
      )!,
    );
  }

  @override
  $TransitFrequenciesTable createAlias(String alias) {
    return $TransitFrequenciesTable(attachedDatabase, alias);
  }
}

class TransitFrequency extends DataClass
    implements Insertable<TransitFrequency> {
  final String tripId;
  final int startTimeSeconds;
  final int endTimeSeconds;
  final int headwaySeconds;
  final bool exactTimes;
  const TransitFrequency({
    required this.tripId,
    required this.startTimeSeconds,
    required this.endTimeSeconds,
    required this.headwaySeconds,
    required this.exactTimes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['trip_id'] = Variable<String>(tripId);
    map['start_time_seconds'] = Variable<int>(startTimeSeconds);
    map['end_time_seconds'] = Variable<int>(endTimeSeconds);
    map['headway_seconds'] = Variable<int>(headwaySeconds);
    map['exact_times'] = Variable<bool>(exactTimes);
    return map;
  }

  TransitFrequenciesCompanion toCompanion(bool nullToAbsent) {
    return TransitFrequenciesCompanion(
      tripId: Value(tripId),
      startTimeSeconds: Value(startTimeSeconds),
      endTimeSeconds: Value(endTimeSeconds),
      headwaySeconds: Value(headwaySeconds),
      exactTimes: Value(exactTimes),
    );
  }

  factory TransitFrequency.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TransitFrequency(
      tripId: serializer.fromJson<String>(json['tripId']),
      startTimeSeconds: serializer.fromJson<int>(json['startTimeSeconds']),
      endTimeSeconds: serializer.fromJson<int>(json['endTimeSeconds']),
      headwaySeconds: serializer.fromJson<int>(json['headwaySeconds']),
      exactTimes: serializer.fromJson<bool>(json['exactTimes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tripId': serializer.toJson<String>(tripId),
      'startTimeSeconds': serializer.toJson<int>(startTimeSeconds),
      'endTimeSeconds': serializer.toJson<int>(endTimeSeconds),
      'headwaySeconds': serializer.toJson<int>(headwaySeconds),
      'exactTimes': serializer.toJson<bool>(exactTimes),
    };
  }

  TransitFrequency copyWith({
    String? tripId,
    int? startTimeSeconds,
    int? endTimeSeconds,
    int? headwaySeconds,
    bool? exactTimes,
  }) => TransitFrequency(
    tripId: tripId ?? this.tripId,
    startTimeSeconds: startTimeSeconds ?? this.startTimeSeconds,
    endTimeSeconds: endTimeSeconds ?? this.endTimeSeconds,
    headwaySeconds: headwaySeconds ?? this.headwaySeconds,
    exactTimes: exactTimes ?? this.exactTimes,
  );
  TransitFrequency copyWithCompanion(TransitFrequenciesCompanion data) {
    return TransitFrequency(
      tripId: data.tripId.present ? data.tripId.value : this.tripId,
      startTimeSeconds: data.startTimeSeconds.present
          ? data.startTimeSeconds.value
          : this.startTimeSeconds,
      endTimeSeconds: data.endTimeSeconds.present
          ? data.endTimeSeconds.value
          : this.endTimeSeconds,
      headwaySeconds: data.headwaySeconds.present
          ? data.headwaySeconds.value
          : this.headwaySeconds,
      exactTimes: data.exactTimes.present
          ? data.exactTimes.value
          : this.exactTimes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TransitFrequency(')
          ..write('tripId: $tripId, ')
          ..write('startTimeSeconds: $startTimeSeconds, ')
          ..write('endTimeSeconds: $endTimeSeconds, ')
          ..write('headwaySeconds: $headwaySeconds, ')
          ..write('exactTimes: $exactTimes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    tripId,
    startTimeSeconds,
    endTimeSeconds,
    headwaySeconds,
    exactTimes,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TransitFrequency &&
          other.tripId == this.tripId &&
          other.startTimeSeconds == this.startTimeSeconds &&
          other.endTimeSeconds == this.endTimeSeconds &&
          other.headwaySeconds == this.headwaySeconds &&
          other.exactTimes == this.exactTimes);
}

class TransitFrequenciesCompanion extends UpdateCompanion<TransitFrequency> {
  final Value<String> tripId;
  final Value<int> startTimeSeconds;
  final Value<int> endTimeSeconds;
  final Value<int> headwaySeconds;
  final Value<bool> exactTimes;
  final Value<int> rowid;
  const TransitFrequenciesCompanion({
    this.tripId = const Value.absent(),
    this.startTimeSeconds = const Value.absent(),
    this.endTimeSeconds = const Value.absent(),
    this.headwaySeconds = const Value.absent(),
    this.exactTimes = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TransitFrequenciesCompanion.insert({
    required String tripId,
    required int startTimeSeconds,
    required int endTimeSeconds,
    required int headwaySeconds,
    this.exactTimes = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : tripId = Value(tripId),
       startTimeSeconds = Value(startTimeSeconds),
       endTimeSeconds = Value(endTimeSeconds),
       headwaySeconds = Value(headwaySeconds);
  static Insertable<TransitFrequency> custom({
    Expression<String>? tripId,
    Expression<int>? startTimeSeconds,
    Expression<int>? endTimeSeconds,
    Expression<int>? headwaySeconds,
    Expression<bool>? exactTimes,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tripId != null) 'trip_id': tripId,
      if (startTimeSeconds != null) 'start_time_seconds': startTimeSeconds,
      if (endTimeSeconds != null) 'end_time_seconds': endTimeSeconds,
      if (headwaySeconds != null) 'headway_seconds': headwaySeconds,
      if (exactTimes != null) 'exact_times': exactTimes,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TransitFrequenciesCompanion copyWith({
    Value<String>? tripId,
    Value<int>? startTimeSeconds,
    Value<int>? endTimeSeconds,
    Value<int>? headwaySeconds,
    Value<bool>? exactTimes,
    Value<int>? rowid,
  }) {
    return TransitFrequenciesCompanion(
      tripId: tripId ?? this.tripId,
      startTimeSeconds: startTimeSeconds ?? this.startTimeSeconds,
      endTimeSeconds: endTimeSeconds ?? this.endTimeSeconds,
      headwaySeconds: headwaySeconds ?? this.headwaySeconds,
      exactTimes: exactTimes ?? this.exactTimes,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tripId.present) {
      map['trip_id'] = Variable<String>(tripId.value);
    }
    if (startTimeSeconds.present) {
      map['start_time_seconds'] = Variable<int>(startTimeSeconds.value);
    }
    if (endTimeSeconds.present) {
      map['end_time_seconds'] = Variable<int>(endTimeSeconds.value);
    }
    if (headwaySeconds.present) {
      map['headway_seconds'] = Variable<int>(headwaySeconds.value);
    }
    if (exactTimes.present) {
      map['exact_times'] = Variable<bool>(exactTimes.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransitFrequenciesCompanion(')
          ..write('tripId: $tripId, ')
          ..write('startTimeSeconds: $startTimeSeconds, ')
          ..write('endTimeSeconds: $endTimeSeconds, ')
          ..write('headwaySeconds: $headwaySeconds, ')
          ..write('exactTimes: $exactTimes, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RealtimeProviderLineMappingsTable extends RealtimeProviderLineMappings
    with
        TableInfo<
          $RealtimeProviderLineMappingsTable,
          RealtimeProviderLineMapping
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RealtimeProviderLineMappingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _providerIdMeta = const VerificationMeta(
    'providerId',
  );
  @override
  late final GeneratedColumn<String> providerId = GeneratedColumn<String>(
    'provider_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _providerLineIdMeta = const VerificationMeta(
    'providerLineId',
  );
  @override
  late final GeneratedColumn<String> providerLineId = GeneratedColumn<String>(
    'provider_line_id',
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
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _supportsArrivalsMeta = const VerificationMeta(
    'supportsArrivals',
  );
  @override
  late final GeneratedColumn<bool> supportsArrivals = GeneratedColumn<bool>(
    'supports_arrivals',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("supports_arrivals" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _supportsTrainPositionsMeta =
      const VerificationMeta('supportsTrainPositions');
  @override
  late final GeneratedColumn<bool> supportsTrainPositions =
      GeneratedColumn<bool>(
        'supports_train_positions',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("supports_train_positions" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _mappingConfidenceMeta = const VerificationMeta(
    'mappingConfidence',
  );
  @override
  late final GeneratedColumn<String> mappingConfidence =
      GeneratedColumn<String>(
        'mapping_confidence',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('UNKNOWN'),
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
  List<GeneratedColumn> get $columns => [
    providerId,
    providerLineId,
    lineId,
    sourceId,
    supportsArrivals,
    supportsTrainPositions,
    mappingConfidence,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'realtime_provider_line_mappings';
  @override
  VerificationContext validateIntegrity(
    Insertable<RealtimeProviderLineMapping> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('provider_id')) {
      context.handle(
        _providerIdMeta,
        providerId.isAcceptableOrUnknown(data['provider_id']!, _providerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_providerIdMeta);
    }
    if (data.containsKey('provider_line_id')) {
      context.handle(
        _providerLineIdMeta,
        providerLineId.isAcceptableOrUnknown(
          data['provider_line_id']!,
          _providerLineIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_providerLineIdMeta);
    }
    if (data.containsKey('line_id')) {
      context.handle(
        _lineIdMeta,
        lineId.isAcceptableOrUnknown(data['line_id']!, _lineIdMeta),
      );
    } else if (isInserting) {
      context.missing(_lineIdMeta);
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('supports_arrivals')) {
      context.handle(
        _supportsArrivalsMeta,
        supportsArrivals.isAcceptableOrUnknown(
          data['supports_arrivals']!,
          _supportsArrivalsMeta,
        ),
      );
    }
    if (data.containsKey('supports_train_positions')) {
      context.handle(
        _supportsTrainPositionsMeta,
        supportsTrainPositions.isAcceptableOrUnknown(
          data['supports_train_positions']!,
          _supportsTrainPositionsMeta,
        ),
      );
    }
    if (data.containsKey('mapping_confidence')) {
      context.handle(
        _mappingConfidenceMeta,
        mappingConfidence.isAcceptableOrUnknown(
          data['mapping_confidence']!,
          _mappingConfidenceMeta,
        ),
      );
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
  Set<GeneratedColumn> get $primaryKey => {providerId, providerLineId};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {providerId, lineId},
    {providerId, providerLineId, lineId},
  ];
  @override
  RealtimeProviderLineMapping map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RealtimeProviderLineMapping(
      providerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider_id'],
      )!,
      providerLineId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider_line_id'],
      )!,
      lineId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}line_id'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      supportsArrivals: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}supports_arrivals'],
      )!,
      supportsTrainPositions: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}supports_train_positions'],
      )!,
      mappingConfidence: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mapping_confidence'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $RealtimeProviderLineMappingsTable createAlias(String alias) {
    return $RealtimeProviderLineMappingsTable(attachedDatabase, alias);
  }
}

class RealtimeProviderLineMapping extends DataClass
    implements Insertable<RealtimeProviderLineMapping> {
  final String providerId;
  final String providerLineId;
  final String lineId;
  final String sourceId;
  final bool supportsArrivals;
  final bool supportsTrainPositions;
  final String mappingConfidence;
  final DateTime? updatedAt;
  const RealtimeProviderLineMapping({
    required this.providerId,
    required this.providerLineId,
    required this.lineId,
    required this.sourceId,
    required this.supportsArrivals,
    required this.supportsTrainPositions,
    required this.mappingConfidence,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['provider_id'] = Variable<String>(providerId);
    map['provider_line_id'] = Variable<String>(providerLineId);
    map['line_id'] = Variable<String>(lineId);
    map['source_id'] = Variable<String>(sourceId);
    map['supports_arrivals'] = Variable<bool>(supportsArrivals);
    map['supports_train_positions'] = Variable<bool>(supportsTrainPositions);
    map['mapping_confidence'] = Variable<String>(mappingConfidence);
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  RealtimeProviderLineMappingsCompanion toCompanion(bool nullToAbsent) {
    return RealtimeProviderLineMappingsCompanion(
      providerId: Value(providerId),
      providerLineId: Value(providerLineId),
      lineId: Value(lineId),
      sourceId: Value(sourceId),
      supportsArrivals: Value(supportsArrivals),
      supportsTrainPositions: Value(supportsTrainPositions),
      mappingConfidence: Value(mappingConfidence),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory RealtimeProviderLineMapping.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RealtimeProviderLineMapping(
      providerId: serializer.fromJson<String>(json['providerId']),
      providerLineId: serializer.fromJson<String>(json['providerLineId']),
      lineId: serializer.fromJson<String>(json['lineId']),
      sourceId: serializer.fromJson<String>(json['sourceId']),
      supportsArrivals: serializer.fromJson<bool>(json['supportsArrivals']),
      supportsTrainPositions: serializer.fromJson<bool>(
        json['supportsTrainPositions'],
      ),
      mappingConfidence: serializer.fromJson<String>(json['mappingConfidence']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'providerId': serializer.toJson<String>(providerId),
      'providerLineId': serializer.toJson<String>(providerLineId),
      'lineId': serializer.toJson<String>(lineId),
      'sourceId': serializer.toJson<String>(sourceId),
      'supportsArrivals': serializer.toJson<bool>(supportsArrivals),
      'supportsTrainPositions': serializer.toJson<bool>(supportsTrainPositions),
      'mappingConfidence': serializer.toJson<String>(mappingConfidence),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  RealtimeProviderLineMapping copyWith({
    String? providerId,
    String? providerLineId,
    String? lineId,
    String? sourceId,
    bool? supportsArrivals,
    bool? supportsTrainPositions,
    String? mappingConfidence,
    Value<DateTime?> updatedAt = const Value.absent(),
  }) => RealtimeProviderLineMapping(
    providerId: providerId ?? this.providerId,
    providerLineId: providerLineId ?? this.providerLineId,
    lineId: lineId ?? this.lineId,
    sourceId: sourceId ?? this.sourceId,
    supportsArrivals: supportsArrivals ?? this.supportsArrivals,
    supportsTrainPositions:
        supportsTrainPositions ?? this.supportsTrainPositions,
    mappingConfidence: mappingConfidence ?? this.mappingConfidence,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  RealtimeProviderLineMapping copyWithCompanion(
    RealtimeProviderLineMappingsCompanion data,
  ) {
    return RealtimeProviderLineMapping(
      providerId: data.providerId.present
          ? data.providerId.value
          : this.providerId,
      providerLineId: data.providerLineId.present
          ? data.providerLineId.value
          : this.providerLineId,
      lineId: data.lineId.present ? data.lineId.value : this.lineId,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      supportsArrivals: data.supportsArrivals.present
          ? data.supportsArrivals.value
          : this.supportsArrivals,
      supportsTrainPositions: data.supportsTrainPositions.present
          ? data.supportsTrainPositions.value
          : this.supportsTrainPositions,
      mappingConfidence: data.mappingConfidence.present
          ? data.mappingConfidence.value
          : this.mappingConfidence,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RealtimeProviderLineMapping(')
          ..write('providerId: $providerId, ')
          ..write('providerLineId: $providerLineId, ')
          ..write('lineId: $lineId, ')
          ..write('sourceId: $sourceId, ')
          ..write('supportsArrivals: $supportsArrivals, ')
          ..write('supportsTrainPositions: $supportsTrainPositions, ')
          ..write('mappingConfidence: $mappingConfidence, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    providerId,
    providerLineId,
    lineId,
    sourceId,
    supportsArrivals,
    supportsTrainPositions,
    mappingConfidence,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RealtimeProviderLineMapping &&
          other.providerId == this.providerId &&
          other.providerLineId == this.providerLineId &&
          other.lineId == this.lineId &&
          other.sourceId == this.sourceId &&
          other.supportsArrivals == this.supportsArrivals &&
          other.supportsTrainPositions == this.supportsTrainPositions &&
          other.mappingConfidence == this.mappingConfidence &&
          other.updatedAt == this.updatedAt);
}

class RealtimeProviderLineMappingsCompanion
    extends UpdateCompanion<RealtimeProviderLineMapping> {
  final Value<String> providerId;
  final Value<String> providerLineId;
  final Value<String> lineId;
  final Value<String> sourceId;
  final Value<bool> supportsArrivals;
  final Value<bool> supportsTrainPositions;
  final Value<String> mappingConfidence;
  final Value<DateTime?> updatedAt;
  final Value<int> rowid;
  const RealtimeProviderLineMappingsCompanion({
    this.providerId = const Value.absent(),
    this.providerLineId = const Value.absent(),
    this.lineId = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.supportsArrivals = const Value.absent(),
    this.supportsTrainPositions = const Value.absent(),
    this.mappingConfidence = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RealtimeProviderLineMappingsCompanion.insert({
    required String providerId,
    required String providerLineId,
    required String lineId,
    required String sourceId,
    this.supportsArrivals = const Value.absent(),
    this.supportsTrainPositions = const Value.absent(),
    this.mappingConfidence = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : providerId = Value(providerId),
       providerLineId = Value(providerLineId),
       lineId = Value(lineId),
       sourceId = Value(sourceId);
  static Insertable<RealtimeProviderLineMapping> custom({
    Expression<String>? providerId,
    Expression<String>? providerLineId,
    Expression<String>? lineId,
    Expression<String>? sourceId,
    Expression<bool>? supportsArrivals,
    Expression<bool>? supportsTrainPositions,
    Expression<String>? mappingConfidence,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (providerId != null) 'provider_id': providerId,
      if (providerLineId != null) 'provider_line_id': providerLineId,
      if (lineId != null) 'line_id': lineId,
      if (sourceId != null) 'source_id': sourceId,
      if (supportsArrivals != null) 'supports_arrivals': supportsArrivals,
      if (supportsTrainPositions != null)
        'supports_train_positions': supportsTrainPositions,
      if (mappingConfidence != null) 'mapping_confidence': mappingConfidence,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RealtimeProviderLineMappingsCompanion copyWith({
    Value<String>? providerId,
    Value<String>? providerLineId,
    Value<String>? lineId,
    Value<String>? sourceId,
    Value<bool>? supportsArrivals,
    Value<bool>? supportsTrainPositions,
    Value<String>? mappingConfidence,
    Value<DateTime?>? updatedAt,
    Value<int>? rowid,
  }) {
    return RealtimeProviderLineMappingsCompanion(
      providerId: providerId ?? this.providerId,
      providerLineId: providerLineId ?? this.providerLineId,
      lineId: lineId ?? this.lineId,
      sourceId: sourceId ?? this.sourceId,
      supportsArrivals: supportsArrivals ?? this.supportsArrivals,
      supportsTrainPositions:
          supportsTrainPositions ?? this.supportsTrainPositions,
      mappingConfidence: mappingConfidence ?? this.mappingConfidence,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (providerId.present) {
      map['provider_id'] = Variable<String>(providerId.value);
    }
    if (providerLineId.present) {
      map['provider_line_id'] = Variable<String>(providerLineId.value);
    }
    if (lineId.present) {
      map['line_id'] = Variable<String>(lineId.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (supportsArrivals.present) {
      map['supports_arrivals'] = Variable<bool>(supportsArrivals.value);
    }
    if (supportsTrainPositions.present) {
      map['supports_train_positions'] = Variable<bool>(
        supportsTrainPositions.value,
      );
    }
    if (mappingConfidence.present) {
      map['mapping_confidence'] = Variable<String>(mappingConfidence.value);
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
    return (StringBuffer('RealtimeProviderLineMappingsCompanion(')
          ..write('providerId: $providerId, ')
          ..write('providerLineId: $providerLineId, ')
          ..write('lineId: $lineId, ')
          ..write('sourceId: $sourceId, ')
          ..write('supportsArrivals: $supportsArrivals, ')
          ..write('supportsTrainPositions: $supportsTrainPositions, ')
          ..write('mappingConfidence: $mappingConfidence, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RealtimeProviderStationMappingsTable
    extends RealtimeProviderStationMappings
    with
        TableInfo<
          $RealtimeProviderStationMappingsTable,
          RealtimeProviderStationMapping
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RealtimeProviderStationMappingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _providerIdMeta = const VerificationMeta(
    'providerId',
  );
  @override
  late final GeneratedColumn<String> providerId = GeneratedColumn<String>(
    'provider_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _providerLineIdMeta = const VerificationMeta(
    'providerLineId',
  );
  @override
  late final GeneratedColumn<String> providerLineId = GeneratedColumn<String>(
    'provider_line_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _providerStationIdMeta = const VerificationMeta(
    'providerStationId',
  );
  @override
  late final GeneratedColumn<String> providerStationId =
      GeneratedColumn<String>(
        'provider_station_id',
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
  static const VerificationMeta _lineIdMeta = const VerificationMeta('lineId');
  @override
  late final GeneratedColumn<String> lineId = GeneratedColumn<String>(
    'line_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _queryNameMeta = const VerificationMeta(
    'queryName',
  );
  @override
  late final GeneratedColumn<String> queryName = GeneratedColumn<String>(
    'query_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _supportsArrivalsMeta = const VerificationMeta(
    'supportsArrivals',
  );
  @override
  late final GeneratedColumn<bool> supportsArrivals = GeneratedColumn<bool>(
    'supports_arrivals',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("supports_arrivals" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _supportsTrainPositionsMeta =
      const VerificationMeta('supportsTrainPositions');
  @override
  late final GeneratedColumn<bool> supportsTrainPositions =
      GeneratedColumn<bool>(
        'supports_train_positions',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("supports_train_positions" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _mappingConfidenceMeta = const VerificationMeta(
    'mappingConfidence',
  );
  @override
  late final GeneratedColumn<String> mappingConfidence =
      GeneratedColumn<String>(
        'mapping_confidence',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('UNKNOWN'),
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
  List<GeneratedColumn> get $columns => [
    providerId,
    providerLineId,
    providerStationId,
    stationId,
    lineId,
    sourceId,
    queryName,
    supportsArrivals,
    supportsTrainPositions,
    mappingConfidence,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'realtime_provider_station_mappings';
  @override
  VerificationContext validateIntegrity(
    Insertable<RealtimeProviderStationMapping> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('provider_id')) {
      context.handle(
        _providerIdMeta,
        providerId.isAcceptableOrUnknown(data['provider_id']!, _providerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_providerIdMeta);
    }
    if (data.containsKey('provider_line_id')) {
      context.handle(
        _providerLineIdMeta,
        providerLineId.isAcceptableOrUnknown(
          data['provider_line_id']!,
          _providerLineIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_providerLineIdMeta);
    }
    if (data.containsKey('provider_station_id')) {
      context.handle(
        _providerStationIdMeta,
        providerStationId.isAcceptableOrUnknown(
          data['provider_station_id']!,
          _providerStationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_providerStationIdMeta);
    }
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
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('query_name')) {
      context.handle(
        _queryNameMeta,
        queryName.isAcceptableOrUnknown(data['query_name']!, _queryNameMeta),
      );
    }
    if (data.containsKey('supports_arrivals')) {
      context.handle(
        _supportsArrivalsMeta,
        supportsArrivals.isAcceptableOrUnknown(
          data['supports_arrivals']!,
          _supportsArrivalsMeta,
        ),
      );
    }
    if (data.containsKey('supports_train_positions')) {
      context.handle(
        _supportsTrainPositionsMeta,
        supportsTrainPositions.isAcceptableOrUnknown(
          data['supports_train_positions']!,
          _supportsTrainPositionsMeta,
        ),
      );
    }
    if (data.containsKey('mapping_confidence')) {
      context.handle(
        _mappingConfidenceMeta,
        mappingConfidence.isAcceptableOrUnknown(
          data['mapping_confidence']!,
          _mappingConfidenceMeta,
        ),
      );
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
  Set<GeneratedColumn> get $primaryKey => {
    providerId,
    providerLineId,
    providerStationId,
  };
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {providerId, lineId, stationId},
  ];
  @override
  RealtimeProviderStationMapping map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RealtimeProviderStationMapping(
      providerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider_id'],
      )!,
      providerLineId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider_line_id'],
      )!,
      providerStationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider_station_id'],
      )!,
      stationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}station_id'],
      )!,
      lineId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}line_id'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      queryName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}query_name'],
      )!,
      supportsArrivals: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}supports_arrivals'],
      )!,
      supportsTrainPositions: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}supports_train_positions'],
      )!,
      mappingConfidence: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mapping_confidence'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $RealtimeProviderStationMappingsTable createAlias(String alias) {
    return $RealtimeProviderStationMappingsTable(attachedDatabase, alias);
  }
}

class RealtimeProviderStationMapping extends DataClass
    implements Insertable<RealtimeProviderStationMapping> {
  final String providerId;
  final String providerLineId;
  final String providerStationId;
  final String stationId;
  final String lineId;
  final String sourceId;
  final String queryName;
  final bool supportsArrivals;
  final bool supportsTrainPositions;
  final String mappingConfidence;
  final DateTime? updatedAt;
  const RealtimeProviderStationMapping({
    required this.providerId,
    required this.providerLineId,
    required this.providerStationId,
    required this.stationId,
    required this.lineId,
    required this.sourceId,
    required this.queryName,
    required this.supportsArrivals,
    required this.supportsTrainPositions,
    required this.mappingConfidence,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['provider_id'] = Variable<String>(providerId);
    map['provider_line_id'] = Variable<String>(providerLineId);
    map['provider_station_id'] = Variable<String>(providerStationId);
    map['station_id'] = Variable<String>(stationId);
    map['line_id'] = Variable<String>(lineId);
    map['source_id'] = Variable<String>(sourceId);
    map['query_name'] = Variable<String>(queryName);
    map['supports_arrivals'] = Variable<bool>(supportsArrivals);
    map['supports_train_positions'] = Variable<bool>(supportsTrainPositions);
    map['mapping_confidence'] = Variable<String>(mappingConfidence);
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  RealtimeProviderStationMappingsCompanion toCompanion(bool nullToAbsent) {
    return RealtimeProviderStationMappingsCompanion(
      providerId: Value(providerId),
      providerLineId: Value(providerLineId),
      providerStationId: Value(providerStationId),
      stationId: Value(stationId),
      lineId: Value(lineId),
      sourceId: Value(sourceId),
      queryName: Value(queryName),
      supportsArrivals: Value(supportsArrivals),
      supportsTrainPositions: Value(supportsTrainPositions),
      mappingConfidence: Value(mappingConfidence),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory RealtimeProviderStationMapping.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RealtimeProviderStationMapping(
      providerId: serializer.fromJson<String>(json['providerId']),
      providerLineId: serializer.fromJson<String>(json['providerLineId']),
      providerStationId: serializer.fromJson<String>(json['providerStationId']),
      stationId: serializer.fromJson<String>(json['stationId']),
      lineId: serializer.fromJson<String>(json['lineId']),
      sourceId: serializer.fromJson<String>(json['sourceId']),
      queryName: serializer.fromJson<String>(json['queryName']),
      supportsArrivals: serializer.fromJson<bool>(json['supportsArrivals']),
      supportsTrainPositions: serializer.fromJson<bool>(
        json['supportsTrainPositions'],
      ),
      mappingConfidence: serializer.fromJson<String>(json['mappingConfidence']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'providerId': serializer.toJson<String>(providerId),
      'providerLineId': serializer.toJson<String>(providerLineId),
      'providerStationId': serializer.toJson<String>(providerStationId),
      'stationId': serializer.toJson<String>(stationId),
      'lineId': serializer.toJson<String>(lineId),
      'sourceId': serializer.toJson<String>(sourceId),
      'queryName': serializer.toJson<String>(queryName),
      'supportsArrivals': serializer.toJson<bool>(supportsArrivals),
      'supportsTrainPositions': serializer.toJson<bool>(supportsTrainPositions),
      'mappingConfidence': serializer.toJson<String>(mappingConfidence),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  RealtimeProviderStationMapping copyWith({
    String? providerId,
    String? providerLineId,
    String? providerStationId,
    String? stationId,
    String? lineId,
    String? sourceId,
    String? queryName,
    bool? supportsArrivals,
    bool? supportsTrainPositions,
    String? mappingConfidence,
    Value<DateTime?> updatedAt = const Value.absent(),
  }) => RealtimeProviderStationMapping(
    providerId: providerId ?? this.providerId,
    providerLineId: providerLineId ?? this.providerLineId,
    providerStationId: providerStationId ?? this.providerStationId,
    stationId: stationId ?? this.stationId,
    lineId: lineId ?? this.lineId,
    sourceId: sourceId ?? this.sourceId,
    queryName: queryName ?? this.queryName,
    supportsArrivals: supportsArrivals ?? this.supportsArrivals,
    supportsTrainPositions:
        supportsTrainPositions ?? this.supportsTrainPositions,
    mappingConfidence: mappingConfidence ?? this.mappingConfidence,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  RealtimeProviderStationMapping copyWithCompanion(
    RealtimeProviderStationMappingsCompanion data,
  ) {
    return RealtimeProviderStationMapping(
      providerId: data.providerId.present
          ? data.providerId.value
          : this.providerId,
      providerLineId: data.providerLineId.present
          ? data.providerLineId.value
          : this.providerLineId,
      providerStationId: data.providerStationId.present
          ? data.providerStationId.value
          : this.providerStationId,
      stationId: data.stationId.present ? data.stationId.value : this.stationId,
      lineId: data.lineId.present ? data.lineId.value : this.lineId,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      queryName: data.queryName.present ? data.queryName.value : this.queryName,
      supportsArrivals: data.supportsArrivals.present
          ? data.supportsArrivals.value
          : this.supportsArrivals,
      supportsTrainPositions: data.supportsTrainPositions.present
          ? data.supportsTrainPositions.value
          : this.supportsTrainPositions,
      mappingConfidence: data.mappingConfidence.present
          ? data.mappingConfidence.value
          : this.mappingConfidence,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RealtimeProviderStationMapping(')
          ..write('providerId: $providerId, ')
          ..write('providerLineId: $providerLineId, ')
          ..write('providerStationId: $providerStationId, ')
          ..write('stationId: $stationId, ')
          ..write('lineId: $lineId, ')
          ..write('sourceId: $sourceId, ')
          ..write('queryName: $queryName, ')
          ..write('supportsArrivals: $supportsArrivals, ')
          ..write('supportsTrainPositions: $supportsTrainPositions, ')
          ..write('mappingConfidence: $mappingConfidence, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    providerId,
    providerLineId,
    providerStationId,
    stationId,
    lineId,
    sourceId,
    queryName,
    supportsArrivals,
    supportsTrainPositions,
    mappingConfidence,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RealtimeProviderStationMapping &&
          other.providerId == this.providerId &&
          other.providerLineId == this.providerLineId &&
          other.providerStationId == this.providerStationId &&
          other.stationId == this.stationId &&
          other.lineId == this.lineId &&
          other.sourceId == this.sourceId &&
          other.queryName == this.queryName &&
          other.supportsArrivals == this.supportsArrivals &&
          other.supportsTrainPositions == this.supportsTrainPositions &&
          other.mappingConfidence == this.mappingConfidence &&
          other.updatedAt == this.updatedAt);
}

class RealtimeProviderStationMappingsCompanion
    extends UpdateCompanion<RealtimeProviderStationMapping> {
  final Value<String> providerId;
  final Value<String> providerLineId;
  final Value<String> providerStationId;
  final Value<String> stationId;
  final Value<String> lineId;
  final Value<String> sourceId;
  final Value<String> queryName;
  final Value<bool> supportsArrivals;
  final Value<bool> supportsTrainPositions;
  final Value<String> mappingConfidence;
  final Value<DateTime?> updatedAt;
  final Value<int> rowid;
  const RealtimeProviderStationMappingsCompanion({
    this.providerId = const Value.absent(),
    this.providerLineId = const Value.absent(),
    this.providerStationId = const Value.absent(),
    this.stationId = const Value.absent(),
    this.lineId = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.queryName = const Value.absent(),
    this.supportsArrivals = const Value.absent(),
    this.supportsTrainPositions = const Value.absent(),
    this.mappingConfidence = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RealtimeProviderStationMappingsCompanion.insert({
    required String providerId,
    required String providerLineId,
    required String providerStationId,
    required String stationId,
    required String lineId,
    required String sourceId,
    this.queryName = const Value.absent(),
    this.supportsArrivals = const Value.absent(),
    this.supportsTrainPositions = const Value.absent(),
    this.mappingConfidence = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : providerId = Value(providerId),
       providerLineId = Value(providerLineId),
       providerStationId = Value(providerStationId),
       stationId = Value(stationId),
       lineId = Value(lineId),
       sourceId = Value(sourceId);
  static Insertable<RealtimeProviderStationMapping> custom({
    Expression<String>? providerId,
    Expression<String>? providerLineId,
    Expression<String>? providerStationId,
    Expression<String>? stationId,
    Expression<String>? lineId,
    Expression<String>? sourceId,
    Expression<String>? queryName,
    Expression<bool>? supportsArrivals,
    Expression<bool>? supportsTrainPositions,
    Expression<String>? mappingConfidence,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (providerId != null) 'provider_id': providerId,
      if (providerLineId != null) 'provider_line_id': providerLineId,
      if (providerStationId != null) 'provider_station_id': providerStationId,
      if (stationId != null) 'station_id': stationId,
      if (lineId != null) 'line_id': lineId,
      if (sourceId != null) 'source_id': sourceId,
      if (queryName != null) 'query_name': queryName,
      if (supportsArrivals != null) 'supports_arrivals': supportsArrivals,
      if (supportsTrainPositions != null)
        'supports_train_positions': supportsTrainPositions,
      if (mappingConfidence != null) 'mapping_confidence': mappingConfidence,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RealtimeProviderStationMappingsCompanion copyWith({
    Value<String>? providerId,
    Value<String>? providerLineId,
    Value<String>? providerStationId,
    Value<String>? stationId,
    Value<String>? lineId,
    Value<String>? sourceId,
    Value<String>? queryName,
    Value<bool>? supportsArrivals,
    Value<bool>? supportsTrainPositions,
    Value<String>? mappingConfidence,
    Value<DateTime?>? updatedAt,
    Value<int>? rowid,
  }) {
    return RealtimeProviderStationMappingsCompanion(
      providerId: providerId ?? this.providerId,
      providerLineId: providerLineId ?? this.providerLineId,
      providerStationId: providerStationId ?? this.providerStationId,
      stationId: stationId ?? this.stationId,
      lineId: lineId ?? this.lineId,
      sourceId: sourceId ?? this.sourceId,
      queryName: queryName ?? this.queryName,
      supportsArrivals: supportsArrivals ?? this.supportsArrivals,
      supportsTrainPositions:
          supportsTrainPositions ?? this.supportsTrainPositions,
      mappingConfidence: mappingConfidence ?? this.mappingConfidence,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (providerId.present) {
      map['provider_id'] = Variable<String>(providerId.value);
    }
    if (providerLineId.present) {
      map['provider_line_id'] = Variable<String>(providerLineId.value);
    }
    if (providerStationId.present) {
      map['provider_station_id'] = Variable<String>(providerStationId.value);
    }
    if (stationId.present) {
      map['station_id'] = Variable<String>(stationId.value);
    }
    if (lineId.present) {
      map['line_id'] = Variable<String>(lineId.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (queryName.present) {
      map['query_name'] = Variable<String>(queryName.value);
    }
    if (supportsArrivals.present) {
      map['supports_arrivals'] = Variable<bool>(supportsArrivals.value);
    }
    if (supportsTrainPositions.present) {
      map['supports_train_positions'] = Variable<bool>(
        supportsTrainPositions.value,
      );
    }
    if (mappingConfidence.present) {
      map['mapping_confidence'] = Variable<String>(mappingConfidence.value);
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
    return (StringBuffer('RealtimeProviderStationMappingsCompanion(')
          ..write('providerId: $providerId, ')
          ..write('providerLineId: $providerLineId, ')
          ..write('providerStationId: $providerStationId, ')
          ..write('stationId: $stationId, ')
          ..write('lineId: $lineId, ')
          ..write('sourceId: $sourceId, ')
          ..write('queryName: $queryName, ')
          ..write('supportsArrivals: $supportsArrivals, ')
          ..write('supportsTrainPositions: $supportsTrainPositions, ')
          ..write('mappingConfidence: $mappingConfidence, ')
          ..write('updatedAt: $updatedAt, ')
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
  static const VerificationMeta _distanceMetersMeta = const VerificationMeta(
    'distanceMeters',
  );
  @override
  late final GeneratedColumn<int> distanceMeters = GeneratedColumn<int>(
    'distance_meters',
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
  static const VerificationMeta _stairAccessStateMeta = const VerificationMeta(
    'stairAccessState',
  );
  @override
  late final GeneratedColumn<String> stairAccessState = GeneratedColumn<String>(
    'stair_access_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('UNKNOWN'),
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
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sourceSnapshotIdMeta = const VerificationMeta(
    'sourceSnapshotId',
  );
  @override
  late final GeneratedColumn<String> sourceSnapshotId = GeneratedColumn<String>(
    'source_snapshot_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _providerRecordHashMeta =
      const VerificationMeta('providerRecordHash');
  @override
  late final GeneratedColumn<String> providerRecordHash =
      GeneratedColumn<String>(
        'provider_record_hash',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant(''),
      );
  static const VerificationMeta _provenanceKindMeta = const VerificationMeta(
    'provenanceKind',
  );
  @override
  late final GeneratedColumn<String> provenanceKind = GeneratedColumn<String>(
    'provenance_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('UNKNOWN'),
  );
  static const VerificationMeta _verificationStatusMeta =
      const VerificationMeta('verificationStatus');
  @override
  late final GeneratedColumn<String> verificationStatus =
      GeneratedColumn<String>(
        'verification_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('UNKNOWN'),
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
  static const VerificationMeta _evidenceHashMeta = const VerificationMeta(
    'evidenceHash',
  );
  @override
  late final GeneratedColumn<String> evidenceHash = GeneratedColumn<String>(
    'evidence_hash',
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
    distanceMeters,
    edgeType,
    servicePattern,
    includesStairs,
    stairAccessState,
    accessibilityStatus,
    reliabilityScore,
    sourceId,
    sourceSnapshotId,
    providerRecordHash,
    provenanceKind,
    verificationStatus,
    facilityId,
    lastVerifiedAt,
    evidenceHash,
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
    if (data.containsKey('distance_meters')) {
      context.handle(
        _distanceMetersMeta,
        distanceMeters.isAcceptableOrUnknown(
          data['distance_meters']!,
          _distanceMetersMeta,
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
    if (data.containsKey('stair_access_state')) {
      context.handle(
        _stairAccessStateMeta,
        stairAccessState.isAcceptableOrUnknown(
          data['stair_access_state']!,
          _stairAccessStateMeta,
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
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    }
    if (data.containsKey('source_snapshot_id')) {
      context.handle(
        _sourceSnapshotIdMeta,
        sourceSnapshotId.isAcceptableOrUnknown(
          data['source_snapshot_id']!,
          _sourceSnapshotIdMeta,
        ),
      );
    }
    if (data.containsKey('provider_record_hash')) {
      context.handle(
        _providerRecordHashMeta,
        providerRecordHash.isAcceptableOrUnknown(
          data['provider_record_hash']!,
          _providerRecordHashMeta,
        ),
      );
    }
    if (data.containsKey('provenance_kind')) {
      context.handle(
        _provenanceKindMeta,
        provenanceKind.isAcceptableOrUnknown(
          data['provenance_kind']!,
          _provenanceKindMeta,
        ),
      );
    }
    if (data.containsKey('verification_status')) {
      context.handle(
        _verificationStatusMeta,
        verificationStatus.isAcceptableOrUnknown(
          data['verification_status']!,
          _verificationStatusMeta,
        ),
      );
    }
    if (data.containsKey('facility_id')) {
      context.handle(
        _facilityIdMeta,
        facilityId.isAcceptableOrUnknown(data['facility_id']!, _facilityIdMeta),
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
    if (data.containsKey('evidence_hash')) {
      context.handle(
        _evidenceHashMeta,
        evidenceHash.isAcceptableOrUnknown(
          data['evidence_hash']!,
          _evidenceHashMeta,
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
      distanceMeters: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}distance_meters'],
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
      stairAccessState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stair_access_state'],
      )!,
      accessibilityStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}accessibility_status'],
      )!,
      reliabilityScore: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reliability_score'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      sourceSnapshotId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_snapshot_id'],
      )!,
      providerRecordHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider_record_hash'],
      )!,
      provenanceKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provenance_kind'],
      )!,
      verificationStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}verification_status'],
      )!,
      facilityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}facility_id'],
      ),
      lastVerifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_verified_at'],
      ),
      evidenceHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}evidence_hash'],
      )!,
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
  final int distanceMeters;
  final String edgeType;
  final String servicePattern;
  final bool includesStairs;
  final String stairAccessState;
  final String accessibilityStatus;
  final int reliabilityScore;
  final String sourceId;
  final String sourceSnapshotId;
  final String providerRecordHash;
  final String provenanceKind;
  final String verificationStatus;
  final String? facilityId;
  final DateTime? lastVerifiedAt;
  final String evidenceHash;
  const NetworkEdge({
    required this.id,
    required this.fromNodeId,
    required this.toNodeId,
    required this.durationSeconds,
    required this.distanceMeters,
    required this.edgeType,
    required this.servicePattern,
    required this.includesStairs,
    required this.stairAccessState,
    required this.accessibilityStatus,
    required this.reliabilityScore,
    required this.sourceId,
    required this.sourceSnapshotId,
    required this.providerRecordHash,
    required this.provenanceKind,
    required this.verificationStatus,
    this.facilityId,
    this.lastVerifiedAt,
    required this.evidenceHash,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['from_node_id'] = Variable<String>(fromNodeId);
    map['to_node_id'] = Variable<String>(toNodeId);
    map['duration_seconds'] = Variable<int>(durationSeconds);
    map['distance_meters'] = Variable<int>(distanceMeters);
    map['edge_type'] = Variable<String>(edgeType);
    map['service_pattern'] = Variable<String>(servicePattern);
    map['includes_stairs'] = Variable<bool>(includesStairs);
    map['stair_access_state'] = Variable<String>(stairAccessState);
    map['accessibility_status'] = Variable<String>(accessibilityStatus);
    map['reliability_score'] = Variable<int>(reliabilityScore);
    map['source_id'] = Variable<String>(sourceId);
    map['source_snapshot_id'] = Variable<String>(sourceSnapshotId);
    map['provider_record_hash'] = Variable<String>(providerRecordHash);
    map['provenance_kind'] = Variable<String>(provenanceKind);
    map['verification_status'] = Variable<String>(verificationStatus);
    if (!nullToAbsent || facilityId != null) {
      map['facility_id'] = Variable<String>(facilityId);
    }
    if (!nullToAbsent || lastVerifiedAt != null) {
      map['last_verified_at'] = Variable<DateTime>(lastVerifiedAt);
    }
    map['evidence_hash'] = Variable<String>(evidenceHash);
    return map;
  }

  NetworkEdgesCompanion toCompanion(bool nullToAbsent) {
    return NetworkEdgesCompanion(
      id: Value(id),
      fromNodeId: Value(fromNodeId),
      toNodeId: Value(toNodeId),
      durationSeconds: Value(durationSeconds),
      distanceMeters: Value(distanceMeters),
      edgeType: Value(edgeType),
      servicePattern: Value(servicePattern),
      includesStairs: Value(includesStairs),
      stairAccessState: Value(stairAccessState),
      accessibilityStatus: Value(accessibilityStatus),
      reliabilityScore: Value(reliabilityScore),
      sourceId: Value(sourceId),
      sourceSnapshotId: Value(sourceSnapshotId),
      providerRecordHash: Value(providerRecordHash),
      provenanceKind: Value(provenanceKind),
      verificationStatus: Value(verificationStatus),
      facilityId: facilityId == null && nullToAbsent
          ? const Value.absent()
          : Value(facilityId),
      lastVerifiedAt: lastVerifiedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastVerifiedAt),
      evidenceHash: Value(evidenceHash),
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
      distanceMeters: serializer.fromJson<int>(json['distanceMeters']),
      edgeType: serializer.fromJson<String>(json['edgeType']),
      servicePattern: serializer.fromJson<String>(json['servicePattern']),
      includesStairs: serializer.fromJson<bool>(json['includesStairs']),
      stairAccessState: serializer.fromJson<String>(json['stairAccessState']),
      accessibilityStatus: serializer.fromJson<String>(
        json['accessibilityStatus'],
      ),
      reliabilityScore: serializer.fromJson<int>(json['reliabilityScore']),
      sourceId: serializer.fromJson<String>(json['sourceId']),
      sourceSnapshotId: serializer.fromJson<String>(json['sourceSnapshotId']),
      providerRecordHash: serializer.fromJson<String>(
        json['providerRecordHash'],
      ),
      provenanceKind: serializer.fromJson<String>(json['provenanceKind']),
      verificationStatus: serializer.fromJson<String>(
        json['verificationStatus'],
      ),
      facilityId: serializer.fromJson<String?>(json['facilityId']),
      lastVerifiedAt: serializer.fromJson<DateTime?>(json['lastVerifiedAt']),
      evidenceHash: serializer.fromJson<String>(json['evidenceHash']),
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
      'distanceMeters': serializer.toJson<int>(distanceMeters),
      'edgeType': serializer.toJson<String>(edgeType),
      'servicePattern': serializer.toJson<String>(servicePattern),
      'includesStairs': serializer.toJson<bool>(includesStairs),
      'stairAccessState': serializer.toJson<String>(stairAccessState),
      'accessibilityStatus': serializer.toJson<String>(accessibilityStatus),
      'reliabilityScore': serializer.toJson<int>(reliabilityScore),
      'sourceId': serializer.toJson<String>(sourceId),
      'sourceSnapshotId': serializer.toJson<String>(sourceSnapshotId),
      'providerRecordHash': serializer.toJson<String>(providerRecordHash),
      'provenanceKind': serializer.toJson<String>(provenanceKind),
      'verificationStatus': serializer.toJson<String>(verificationStatus),
      'facilityId': serializer.toJson<String?>(facilityId),
      'lastVerifiedAt': serializer.toJson<DateTime?>(lastVerifiedAt),
      'evidenceHash': serializer.toJson<String>(evidenceHash),
    };
  }

  NetworkEdge copyWith({
    String? id,
    String? fromNodeId,
    String? toNodeId,
    int? durationSeconds,
    int? distanceMeters,
    String? edgeType,
    String? servicePattern,
    bool? includesStairs,
    String? stairAccessState,
    String? accessibilityStatus,
    int? reliabilityScore,
    String? sourceId,
    String? sourceSnapshotId,
    String? providerRecordHash,
    String? provenanceKind,
    String? verificationStatus,
    Value<String?> facilityId = const Value.absent(),
    Value<DateTime?> lastVerifiedAt = const Value.absent(),
    String? evidenceHash,
  }) => NetworkEdge(
    id: id ?? this.id,
    fromNodeId: fromNodeId ?? this.fromNodeId,
    toNodeId: toNodeId ?? this.toNodeId,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    distanceMeters: distanceMeters ?? this.distanceMeters,
    edgeType: edgeType ?? this.edgeType,
    servicePattern: servicePattern ?? this.servicePattern,
    includesStairs: includesStairs ?? this.includesStairs,
    stairAccessState: stairAccessState ?? this.stairAccessState,
    accessibilityStatus: accessibilityStatus ?? this.accessibilityStatus,
    reliabilityScore: reliabilityScore ?? this.reliabilityScore,
    sourceId: sourceId ?? this.sourceId,
    sourceSnapshotId: sourceSnapshotId ?? this.sourceSnapshotId,
    providerRecordHash: providerRecordHash ?? this.providerRecordHash,
    provenanceKind: provenanceKind ?? this.provenanceKind,
    verificationStatus: verificationStatus ?? this.verificationStatus,
    facilityId: facilityId.present ? facilityId.value : this.facilityId,
    lastVerifiedAt: lastVerifiedAt.present
        ? lastVerifiedAt.value
        : this.lastVerifiedAt,
    evidenceHash: evidenceHash ?? this.evidenceHash,
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
      distanceMeters: data.distanceMeters.present
          ? data.distanceMeters.value
          : this.distanceMeters,
      edgeType: data.edgeType.present ? data.edgeType.value : this.edgeType,
      servicePattern: data.servicePattern.present
          ? data.servicePattern.value
          : this.servicePattern,
      includesStairs: data.includesStairs.present
          ? data.includesStairs.value
          : this.includesStairs,
      stairAccessState: data.stairAccessState.present
          ? data.stairAccessState.value
          : this.stairAccessState,
      accessibilityStatus: data.accessibilityStatus.present
          ? data.accessibilityStatus.value
          : this.accessibilityStatus,
      reliabilityScore: data.reliabilityScore.present
          ? data.reliabilityScore.value
          : this.reliabilityScore,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      sourceSnapshotId: data.sourceSnapshotId.present
          ? data.sourceSnapshotId.value
          : this.sourceSnapshotId,
      providerRecordHash: data.providerRecordHash.present
          ? data.providerRecordHash.value
          : this.providerRecordHash,
      provenanceKind: data.provenanceKind.present
          ? data.provenanceKind.value
          : this.provenanceKind,
      verificationStatus: data.verificationStatus.present
          ? data.verificationStatus.value
          : this.verificationStatus,
      facilityId: data.facilityId.present
          ? data.facilityId.value
          : this.facilityId,
      lastVerifiedAt: data.lastVerifiedAt.present
          ? data.lastVerifiedAt.value
          : this.lastVerifiedAt,
      evidenceHash: data.evidenceHash.present
          ? data.evidenceHash.value
          : this.evidenceHash,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NetworkEdge(')
          ..write('id: $id, ')
          ..write('fromNodeId: $fromNodeId, ')
          ..write('toNodeId: $toNodeId, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('distanceMeters: $distanceMeters, ')
          ..write('edgeType: $edgeType, ')
          ..write('servicePattern: $servicePattern, ')
          ..write('includesStairs: $includesStairs, ')
          ..write('stairAccessState: $stairAccessState, ')
          ..write('accessibilityStatus: $accessibilityStatus, ')
          ..write('reliabilityScore: $reliabilityScore, ')
          ..write('sourceId: $sourceId, ')
          ..write('sourceSnapshotId: $sourceSnapshotId, ')
          ..write('providerRecordHash: $providerRecordHash, ')
          ..write('provenanceKind: $provenanceKind, ')
          ..write('verificationStatus: $verificationStatus, ')
          ..write('facilityId: $facilityId, ')
          ..write('lastVerifiedAt: $lastVerifiedAt, ')
          ..write('evidenceHash: $evidenceHash')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    fromNodeId,
    toNodeId,
    durationSeconds,
    distanceMeters,
    edgeType,
    servicePattern,
    includesStairs,
    stairAccessState,
    accessibilityStatus,
    reliabilityScore,
    sourceId,
    sourceSnapshotId,
    providerRecordHash,
    provenanceKind,
    verificationStatus,
    facilityId,
    lastVerifiedAt,
    evidenceHash,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NetworkEdge &&
          other.id == this.id &&
          other.fromNodeId == this.fromNodeId &&
          other.toNodeId == this.toNodeId &&
          other.durationSeconds == this.durationSeconds &&
          other.distanceMeters == this.distanceMeters &&
          other.edgeType == this.edgeType &&
          other.servicePattern == this.servicePattern &&
          other.includesStairs == this.includesStairs &&
          other.stairAccessState == this.stairAccessState &&
          other.accessibilityStatus == this.accessibilityStatus &&
          other.reliabilityScore == this.reliabilityScore &&
          other.sourceId == this.sourceId &&
          other.sourceSnapshotId == this.sourceSnapshotId &&
          other.providerRecordHash == this.providerRecordHash &&
          other.provenanceKind == this.provenanceKind &&
          other.verificationStatus == this.verificationStatus &&
          other.facilityId == this.facilityId &&
          other.lastVerifiedAt == this.lastVerifiedAt &&
          other.evidenceHash == this.evidenceHash);
}

class NetworkEdgesCompanion extends UpdateCompanion<NetworkEdge> {
  final Value<String> id;
  final Value<String> fromNodeId;
  final Value<String> toNodeId;
  final Value<int> durationSeconds;
  final Value<int> distanceMeters;
  final Value<String> edgeType;
  final Value<String> servicePattern;
  final Value<bool> includesStairs;
  final Value<String> stairAccessState;
  final Value<String> accessibilityStatus;
  final Value<int> reliabilityScore;
  final Value<String> sourceId;
  final Value<String> sourceSnapshotId;
  final Value<String> providerRecordHash;
  final Value<String> provenanceKind;
  final Value<String> verificationStatus;
  final Value<String?> facilityId;
  final Value<DateTime?> lastVerifiedAt;
  final Value<String> evidenceHash;
  final Value<int> rowid;
  const NetworkEdgesCompanion({
    this.id = const Value.absent(),
    this.fromNodeId = const Value.absent(),
    this.toNodeId = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.distanceMeters = const Value.absent(),
    this.edgeType = const Value.absent(),
    this.servicePattern = const Value.absent(),
    this.includesStairs = const Value.absent(),
    this.stairAccessState = const Value.absent(),
    this.accessibilityStatus = const Value.absent(),
    this.reliabilityScore = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.sourceSnapshotId = const Value.absent(),
    this.providerRecordHash = const Value.absent(),
    this.provenanceKind = const Value.absent(),
    this.verificationStatus = const Value.absent(),
    this.facilityId = const Value.absent(),
    this.lastVerifiedAt = const Value.absent(),
    this.evidenceHash = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NetworkEdgesCompanion.insert({
    required String id,
    required String fromNodeId,
    required String toNodeId,
    this.durationSeconds = const Value.absent(),
    this.distanceMeters = const Value.absent(),
    this.edgeType = const Value.absent(),
    this.servicePattern = const Value.absent(),
    this.includesStairs = const Value.absent(),
    this.stairAccessState = const Value.absent(),
    this.accessibilityStatus = const Value.absent(),
    this.reliabilityScore = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.sourceSnapshotId = const Value.absent(),
    this.providerRecordHash = const Value.absent(),
    this.provenanceKind = const Value.absent(),
    this.verificationStatus = const Value.absent(),
    this.facilityId = const Value.absent(),
    this.lastVerifiedAt = const Value.absent(),
    this.evidenceHash = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       fromNodeId = Value(fromNodeId),
       toNodeId = Value(toNodeId);
  static Insertable<NetworkEdge> custom({
    Expression<String>? id,
    Expression<String>? fromNodeId,
    Expression<String>? toNodeId,
    Expression<int>? durationSeconds,
    Expression<int>? distanceMeters,
    Expression<String>? edgeType,
    Expression<String>? servicePattern,
    Expression<bool>? includesStairs,
    Expression<String>? stairAccessState,
    Expression<String>? accessibilityStatus,
    Expression<int>? reliabilityScore,
    Expression<String>? sourceId,
    Expression<String>? sourceSnapshotId,
    Expression<String>? providerRecordHash,
    Expression<String>? provenanceKind,
    Expression<String>? verificationStatus,
    Expression<String>? facilityId,
    Expression<DateTime>? lastVerifiedAt,
    Expression<String>? evidenceHash,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (fromNodeId != null) 'from_node_id': fromNodeId,
      if (toNodeId != null) 'to_node_id': toNodeId,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (distanceMeters != null) 'distance_meters': distanceMeters,
      if (edgeType != null) 'edge_type': edgeType,
      if (servicePattern != null) 'service_pattern': servicePattern,
      if (includesStairs != null) 'includes_stairs': includesStairs,
      if (stairAccessState != null) 'stair_access_state': stairAccessState,
      if (accessibilityStatus != null)
        'accessibility_status': accessibilityStatus,
      if (reliabilityScore != null) 'reliability_score': reliabilityScore,
      if (sourceId != null) 'source_id': sourceId,
      if (sourceSnapshotId != null) 'source_snapshot_id': sourceSnapshotId,
      if (providerRecordHash != null)
        'provider_record_hash': providerRecordHash,
      if (provenanceKind != null) 'provenance_kind': provenanceKind,
      if (verificationStatus != null) 'verification_status': verificationStatus,
      if (facilityId != null) 'facility_id': facilityId,
      if (lastVerifiedAt != null) 'last_verified_at': lastVerifiedAt,
      if (evidenceHash != null) 'evidence_hash': evidenceHash,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NetworkEdgesCompanion copyWith({
    Value<String>? id,
    Value<String>? fromNodeId,
    Value<String>? toNodeId,
    Value<int>? durationSeconds,
    Value<int>? distanceMeters,
    Value<String>? edgeType,
    Value<String>? servicePattern,
    Value<bool>? includesStairs,
    Value<String>? stairAccessState,
    Value<String>? accessibilityStatus,
    Value<int>? reliabilityScore,
    Value<String>? sourceId,
    Value<String>? sourceSnapshotId,
    Value<String>? providerRecordHash,
    Value<String>? provenanceKind,
    Value<String>? verificationStatus,
    Value<String?>? facilityId,
    Value<DateTime?>? lastVerifiedAt,
    Value<String>? evidenceHash,
    Value<int>? rowid,
  }) {
    return NetworkEdgesCompanion(
      id: id ?? this.id,
      fromNodeId: fromNodeId ?? this.fromNodeId,
      toNodeId: toNodeId ?? this.toNodeId,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      edgeType: edgeType ?? this.edgeType,
      servicePattern: servicePattern ?? this.servicePattern,
      includesStairs: includesStairs ?? this.includesStairs,
      stairAccessState: stairAccessState ?? this.stairAccessState,
      accessibilityStatus: accessibilityStatus ?? this.accessibilityStatus,
      reliabilityScore: reliabilityScore ?? this.reliabilityScore,
      sourceId: sourceId ?? this.sourceId,
      sourceSnapshotId: sourceSnapshotId ?? this.sourceSnapshotId,
      providerRecordHash: providerRecordHash ?? this.providerRecordHash,
      provenanceKind: provenanceKind ?? this.provenanceKind,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      facilityId: facilityId ?? this.facilityId,
      lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
      evidenceHash: evidenceHash ?? this.evidenceHash,
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
    if (distanceMeters.present) {
      map['distance_meters'] = Variable<int>(distanceMeters.value);
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
    if (stairAccessState.present) {
      map['stair_access_state'] = Variable<String>(stairAccessState.value);
    }
    if (accessibilityStatus.present) {
      map['accessibility_status'] = Variable<String>(accessibilityStatus.value);
    }
    if (reliabilityScore.present) {
      map['reliability_score'] = Variable<int>(reliabilityScore.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (sourceSnapshotId.present) {
      map['source_snapshot_id'] = Variable<String>(sourceSnapshotId.value);
    }
    if (providerRecordHash.present) {
      map['provider_record_hash'] = Variable<String>(providerRecordHash.value);
    }
    if (provenanceKind.present) {
      map['provenance_kind'] = Variable<String>(provenanceKind.value);
    }
    if (verificationStatus.present) {
      map['verification_status'] = Variable<String>(verificationStatus.value);
    }
    if (facilityId.present) {
      map['facility_id'] = Variable<String>(facilityId.value);
    }
    if (lastVerifiedAt.present) {
      map['last_verified_at'] = Variable<DateTime>(lastVerifiedAt.value);
    }
    if (evidenceHash.present) {
      map['evidence_hash'] = Variable<String>(evidenceHash.value);
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
          ..write('distanceMeters: $distanceMeters, ')
          ..write('edgeType: $edgeType, ')
          ..write('servicePattern: $servicePattern, ')
          ..write('includesStairs: $includesStairs, ')
          ..write('stairAccessState: $stairAccessState, ')
          ..write('accessibilityStatus: $accessibilityStatus, ')
          ..write('reliabilityScore: $reliabilityScore, ')
          ..write('sourceId: $sourceId, ')
          ..write('sourceSnapshotId: $sourceSnapshotId, ')
          ..write('providerRecordHash: $providerRecordHash, ')
          ..write('provenanceKind: $provenanceKind, ')
          ..write('verificationStatus: $verificationStatus, ')
          ..write('facilityId: $facilityId, ')
          ..write('lastVerifiedAt: $lastVerifiedAt, ')
          ..write('evidenceHash: $evidenceHash, ')
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
    defaultValue: const Constant('UNKNOWN'),
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
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sourceSnapshotIdMeta = const VerificationMeta(
    'sourceSnapshotId',
  );
  @override
  late final GeneratedColumn<String> sourceSnapshotId = GeneratedColumn<String>(
    'source_snapshot_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _providerFacilityRefMeta =
      const VerificationMeta('providerFacilityRef');
  @override
  late final GeneratedColumn<String> providerFacilityRef =
      GeneratedColumn<String>(
        'provider_facility_ref',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant(''),
      );
  static const VerificationMeta _providerRecordHashMeta =
      const VerificationMeta('providerRecordHash');
  @override
  late final GeneratedColumn<String> providerRecordHash =
      GeneratedColumn<String>(
        'provider_record_hash',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant(''),
      );
  static const VerificationMeta _provenanceKindMeta = const VerificationMeta(
    'provenanceKind',
  );
  @override
  late final GeneratedColumn<String> provenanceKind = GeneratedColumn<String>(
    'provenance_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('UNKNOWN'),
  );
  static const VerificationMeta _verifiedAtMeta = const VerificationMeta(
    'verifiedAt',
  );
  @override
  late final GeneratedColumn<DateTime> verifiedAt = GeneratedColumn<DateTime>(
    'verified_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _retrievedAtMeta = const VerificationMeta(
    'retrievedAt',
  );
  @override
  late final GeneratedColumn<DateTime> retrievedAt = GeneratedColumn<DateTime>(
    'retrieved_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _evidenceHashMeta = const VerificationMeta(
    'evidenceHash',
  );
  @override
  late final GeneratedColumn<String> evidenceHash = GeneratedColumn<String>(
    'evidence_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _statusMeaningMeta = const VerificationMeta(
    'statusMeaning',
  );
  @override
  late final GeneratedColumn<String> statusMeaning = GeneratedColumn<String>(
    'status_meaning',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _operationalStatusMeta = const VerificationMeta(
    'operationalStatus',
  );
  @override
  late final GeneratedColumn<String> operationalStatus =
      GeneratedColumn<String>(
        'operational_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant(''),
      );
  static const VerificationMeta _installationStatusMeta =
      const VerificationMeta('installationStatus');
  @override
  late final GeneratedColumn<String> installationStatus =
      GeneratedColumn<String>(
        'installation_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant(''),
      );
  static const VerificationMeta _confidenceMeta = const VerificationMeta(
    'confidence',
  );
  @override
  late final GeneratedColumn<int> confidence = GeneratedColumn<int>(
    'confidence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
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
    sourceId,
    sourceSnapshotId,
    providerFacilityRef,
    providerRecordHash,
    provenanceKind,
    verifiedAt,
    retrievedAt,
    evidenceHash,
    statusMeaning,
    operationalStatus,
    installationStatus,
    confidence,
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
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    }
    if (data.containsKey('source_snapshot_id')) {
      context.handle(
        _sourceSnapshotIdMeta,
        sourceSnapshotId.isAcceptableOrUnknown(
          data['source_snapshot_id']!,
          _sourceSnapshotIdMeta,
        ),
      );
    }
    if (data.containsKey('provider_facility_ref')) {
      context.handle(
        _providerFacilityRefMeta,
        providerFacilityRef.isAcceptableOrUnknown(
          data['provider_facility_ref']!,
          _providerFacilityRefMeta,
        ),
      );
    }
    if (data.containsKey('provider_record_hash')) {
      context.handle(
        _providerRecordHashMeta,
        providerRecordHash.isAcceptableOrUnknown(
          data['provider_record_hash']!,
          _providerRecordHashMeta,
        ),
      );
    }
    if (data.containsKey('provenance_kind')) {
      context.handle(
        _provenanceKindMeta,
        provenanceKind.isAcceptableOrUnknown(
          data['provenance_kind']!,
          _provenanceKindMeta,
        ),
      );
    }
    if (data.containsKey('verified_at')) {
      context.handle(
        _verifiedAtMeta,
        verifiedAt.isAcceptableOrUnknown(data['verified_at']!, _verifiedAtMeta),
      );
    }
    if (data.containsKey('retrieved_at')) {
      context.handle(
        _retrievedAtMeta,
        retrievedAt.isAcceptableOrUnknown(
          data['retrieved_at']!,
          _retrievedAtMeta,
        ),
      );
    }
    if (data.containsKey('evidence_hash')) {
      context.handle(
        _evidenceHashMeta,
        evidenceHash.isAcceptableOrUnknown(
          data['evidence_hash']!,
          _evidenceHashMeta,
        ),
      );
    }
    if (data.containsKey('status_meaning')) {
      context.handle(
        _statusMeaningMeta,
        statusMeaning.isAcceptableOrUnknown(
          data['status_meaning']!,
          _statusMeaningMeta,
        ),
      );
    }
    if (data.containsKey('operational_status')) {
      context.handle(
        _operationalStatusMeta,
        operationalStatus.isAcceptableOrUnknown(
          data['operational_status']!,
          _operationalStatusMeta,
        ),
      );
    }
    if (data.containsKey('installation_status')) {
      context.handle(
        _installationStatusMeta,
        installationStatus.isAcceptableOrUnknown(
          data['installation_status']!,
          _installationStatusMeta,
        ),
      );
    }
    if (data.containsKey('confidence')) {
      context.handle(
        _confidenceMeta,
        confidence.isAcceptableOrUnknown(data['confidence']!, _confidenceMeta),
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
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      sourceSnapshotId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_snapshot_id'],
      )!,
      providerFacilityRef: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider_facility_ref'],
      )!,
      providerRecordHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider_record_hash'],
      )!,
      provenanceKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provenance_kind'],
      )!,
      verifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}verified_at'],
      ),
      retrievedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}retrieved_at'],
      ),
      evidenceHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}evidence_hash'],
      )!,
      statusMeaning: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status_meaning'],
      )!,
      operationalStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operational_status'],
      )!,
      installationStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}installation_status'],
      )!,
      confidence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}confidence'],
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
  final String sourceId;
  final String sourceSnapshotId;
  final String providerFacilityRef;
  final String providerRecordHash;
  final String provenanceKind;
  final DateTime? verifiedAt;
  final DateTime? retrievedAt;
  final String evidenceHash;
  final String statusMeaning;
  final String operationalStatus;
  final String installationStatus;
  final int confidence;
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
    required this.sourceId,
    required this.sourceSnapshotId,
    required this.providerFacilityRef,
    required this.providerRecordHash,
    required this.provenanceKind,
    this.verifiedAt,
    this.retrievedAt,
    required this.evidenceHash,
    required this.statusMeaning,
    required this.operationalStatus,
    required this.installationStatus,
    required this.confidence,
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
    map['source_id'] = Variable<String>(sourceId);
    map['source_snapshot_id'] = Variable<String>(sourceSnapshotId);
    map['provider_facility_ref'] = Variable<String>(providerFacilityRef);
    map['provider_record_hash'] = Variable<String>(providerRecordHash);
    map['provenance_kind'] = Variable<String>(provenanceKind);
    if (!nullToAbsent || verifiedAt != null) {
      map['verified_at'] = Variable<DateTime>(verifiedAt);
    }
    if (!nullToAbsent || retrievedAt != null) {
      map['retrieved_at'] = Variable<DateTime>(retrievedAt);
    }
    map['evidence_hash'] = Variable<String>(evidenceHash);
    map['status_meaning'] = Variable<String>(statusMeaning);
    map['operational_status'] = Variable<String>(operationalStatus);
    map['installation_status'] = Variable<String>(installationStatus);
    map['confidence'] = Variable<int>(confidence);
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
      sourceId: Value(sourceId),
      sourceSnapshotId: Value(sourceSnapshotId),
      providerFacilityRef: Value(providerFacilityRef),
      providerRecordHash: Value(providerRecordHash),
      provenanceKind: Value(provenanceKind),
      verifiedAt: verifiedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(verifiedAt),
      retrievedAt: retrievedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(retrievedAt),
      evidenceHash: Value(evidenceHash),
      statusMeaning: Value(statusMeaning),
      operationalStatus: Value(operationalStatus),
      installationStatus: Value(installationStatus),
      confidence: Value(confidence),
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
      sourceId: serializer.fromJson<String>(json['sourceId']),
      sourceSnapshotId: serializer.fromJson<String>(json['sourceSnapshotId']),
      providerFacilityRef: serializer.fromJson<String>(
        json['providerFacilityRef'],
      ),
      providerRecordHash: serializer.fromJson<String>(
        json['providerRecordHash'],
      ),
      provenanceKind: serializer.fromJson<String>(json['provenanceKind']),
      verifiedAt: serializer.fromJson<DateTime?>(json['verifiedAt']),
      retrievedAt: serializer.fromJson<DateTime?>(json['retrievedAt']),
      evidenceHash: serializer.fromJson<String>(json['evidenceHash']),
      statusMeaning: serializer.fromJson<String>(json['statusMeaning']),
      operationalStatus: serializer.fromJson<String>(json['operationalStatus']),
      installationStatus: serializer.fromJson<String>(
        json['installationStatus'],
      ),
      confidence: serializer.fromJson<int>(json['confidence']),
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
      'sourceId': serializer.toJson<String>(sourceId),
      'sourceSnapshotId': serializer.toJson<String>(sourceSnapshotId),
      'providerFacilityRef': serializer.toJson<String>(providerFacilityRef),
      'providerRecordHash': serializer.toJson<String>(providerRecordHash),
      'provenanceKind': serializer.toJson<String>(provenanceKind),
      'verifiedAt': serializer.toJson<DateTime?>(verifiedAt),
      'retrievedAt': serializer.toJson<DateTime?>(retrievedAt),
      'evidenceHash': serializer.toJson<String>(evidenceHash),
      'statusMeaning': serializer.toJson<String>(statusMeaning),
      'operationalStatus': serializer.toJson<String>(operationalStatus),
      'installationStatus': serializer.toJson<String>(installationStatus),
      'confidence': serializer.toJson<int>(confidence),
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
    String? sourceId,
    String? sourceSnapshotId,
    String? providerFacilityRef,
    String? providerRecordHash,
    String? provenanceKind,
    Value<DateTime?> verifiedAt = const Value.absent(),
    Value<DateTime?> retrievedAt = const Value.absent(),
    String? evidenceHash,
    String? statusMeaning,
    String? operationalStatus,
    String? installationStatus,
    int? confidence,
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
    sourceId: sourceId ?? this.sourceId,
    sourceSnapshotId: sourceSnapshotId ?? this.sourceSnapshotId,
    providerFacilityRef: providerFacilityRef ?? this.providerFacilityRef,
    providerRecordHash: providerRecordHash ?? this.providerRecordHash,
    provenanceKind: provenanceKind ?? this.provenanceKind,
    verifiedAt: verifiedAt.present ? verifiedAt.value : this.verifiedAt,
    retrievedAt: retrievedAt.present ? retrievedAt.value : this.retrievedAt,
    evidenceHash: evidenceHash ?? this.evidenceHash,
    statusMeaning: statusMeaning ?? this.statusMeaning,
    operationalStatus: operationalStatus ?? this.operationalStatus,
    installationStatus: installationStatus ?? this.installationStatus,
    confidence: confidence ?? this.confidence,
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
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      sourceSnapshotId: data.sourceSnapshotId.present
          ? data.sourceSnapshotId.value
          : this.sourceSnapshotId,
      providerFacilityRef: data.providerFacilityRef.present
          ? data.providerFacilityRef.value
          : this.providerFacilityRef,
      providerRecordHash: data.providerRecordHash.present
          ? data.providerRecordHash.value
          : this.providerRecordHash,
      provenanceKind: data.provenanceKind.present
          ? data.provenanceKind.value
          : this.provenanceKind,
      verifiedAt: data.verifiedAt.present
          ? data.verifiedAt.value
          : this.verifiedAt,
      retrievedAt: data.retrievedAt.present
          ? data.retrievedAt.value
          : this.retrievedAt,
      evidenceHash: data.evidenceHash.present
          ? data.evidenceHash.value
          : this.evidenceHash,
      statusMeaning: data.statusMeaning.present
          ? data.statusMeaning.value
          : this.statusMeaning,
      operationalStatus: data.operationalStatus.present
          ? data.operationalStatus.value
          : this.operationalStatus,
      installationStatus: data.installationStatus.present
          ? data.installationStatus.value
          : this.installationStatus,
      confidence: data.confidence.present
          ? data.confidence.value
          : this.confidence,
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
          ..write('description: $description, ')
          ..write('sourceId: $sourceId, ')
          ..write('sourceSnapshotId: $sourceSnapshotId, ')
          ..write('providerFacilityRef: $providerFacilityRef, ')
          ..write('providerRecordHash: $providerRecordHash, ')
          ..write('provenanceKind: $provenanceKind, ')
          ..write('verifiedAt: $verifiedAt, ')
          ..write('retrievedAt: $retrievedAt, ')
          ..write('evidenceHash: $evidenceHash, ')
          ..write('statusMeaning: $statusMeaning, ')
          ..write('operationalStatus: $operationalStatus, ')
          ..write('installationStatus: $installationStatus, ')
          ..write('confidence: $confidence')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    stationId,
    exitId,
    type,
    name,
    status,
    floorFrom,
    floorTo,
    description,
    sourceId,
    sourceSnapshotId,
    providerFacilityRef,
    providerRecordHash,
    provenanceKind,
    verifiedAt,
    retrievedAt,
    evidenceHash,
    statusMeaning,
    operationalStatus,
    installationStatus,
    confidence,
  ]);
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
          other.description == this.description &&
          other.sourceId == this.sourceId &&
          other.sourceSnapshotId == this.sourceSnapshotId &&
          other.providerFacilityRef == this.providerFacilityRef &&
          other.providerRecordHash == this.providerRecordHash &&
          other.provenanceKind == this.provenanceKind &&
          other.verifiedAt == this.verifiedAt &&
          other.retrievedAt == this.retrievedAt &&
          other.evidenceHash == this.evidenceHash &&
          other.statusMeaning == this.statusMeaning &&
          other.operationalStatus == this.operationalStatus &&
          other.installationStatus == this.installationStatus &&
          other.confidence == this.confidence);
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
  final Value<String> sourceId;
  final Value<String> sourceSnapshotId;
  final Value<String> providerFacilityRef;
  final Value<String> providerRecordHash;
  final Value<String> provenanceKind;
  final Value<DateTime?> verifiedAt;
  final Value<DateTime?> retrievedAt;
  final Value<String> evidenceHash;
  final Value<String> statusMeaning;
  final Value<String> operationalStatus;
  final Value<String> installationStatus;
  final Value<int> confidence;
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
    this.sourceId = const Value.absent(),
    this.sourceSnapshotId = const Value.absent(),
    this.providerFacilityRef = const Value.absent(),
    this.providerRecordHash = const Value.absent(),
    this.provenanceKind = const Value.absent(),
    this.verifiedAt = const Value.absent(),
    this.retrievedAt = const Value.absent(),
    this.evidenceHash = const Value.absent(),
    this.statusMeaning = const Value.absent(),
    this.operationalStatus = const Value.absent(),
    this.installationStatus = const Value.absent(),
    this.confidence = const Value.absent(),
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
    this.sourceId = const Value.absent(),
    this.sourceSnapshotId = const Value.absent(),
    this.providerFacilityRef = const Value.absent(),
    this.providerRecordHash = const Value.absent(),
    this.provenanceKind = const Value.absent(),
    this.verifiedAt = const Value.absent(),
    this.retrievedAt = const Value.absent(),
    this.evidenceHash = const Value.absent(),
    this.statusMeaning = const Value.absent(),
    this.operationalStatus = const Value.absent(),
    this.installationStatus = const Value.absent(),
    this.confidence = const Value.absent(),
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
    Expression<String>? sourceId,
    Expression<String>? sourceSnapshotId,
    Expression<String>? providerFacilityRef,
    Expression<String>? providerRecordHash,
    Expression<String>? provenanceKind,
    Expression<DateTime>? verifiedAt,
    Expression<DateTime>? retrievedAt,
    Expression<String>? evidenceHash,
    Expression<String>? statusMeaning,
    Expression<String>? operationalStatus,
    Expression<String>? installationStatus,
    Expression<int>? confidence,
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
      if (sourceId != null) 'source_id': sourceId,
      if (sourceSnapshotId != null) 'source_snapshot_id': sourceSnapshotId,
      if (providerFacilityRef != null)
        'provider_facility_ref': providerFacilityRef,
      if (providerRecordHash != null)
        'provider_record_hash': providerRecordHash,
      if (provenanceKind != null) 'provenance_kind': provenanceKind,
      if (verifiedAt != null) 'verified_at': verifiedAt,
      if (retrievedAt != null) 'retrieved_at': retrievedAt,
      if (evidenceHash != null) 'evidence_hash': evidenceHash,
      if (statusMeaning != null) 'status_meaning': statusMeaning,
      if (operationalStatus != null) 'operational_status': operationalStatus,
      if (installationStatus != null) 'installation_status': installationStatus,
      if (confidence != null) 'confidence': confidence,
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
    Value<String>? sourceId,
    Value<String>? sourceSnapshotId,
    Value<String>? providerFacilityRef,
    Value<String>? providerRecordHash,
    Value<String>? provenanceKind,
    Value<DateTime?>? verifiedAt,
    Value<DateTime?>? retrievedAt,
    Value<String>? evidenceHash,
    Value<String>? statusMeaning,
    Value<String>? operationalStatus,
    Value<String>? installationStatus,
    Value<int>? confidence,
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
      sourceId: sourceId ?? this.sourceId,
      sourceSnapshotId: sourceSnapshotId ?? this.sourceSnapshotId,
      providerFacilityRef: providerFacilityRef ?? this.providerFacilityRef,
      providerRecordHash: providerRecordHash ?? this.providerRecordHash,
      provenanceKind: provenanceKind ?? this.provenanceKind,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      retrievedAt: retrievedAt ?? this.retrievedAt,
      evidenceHash: evidenceHash ?? this.evidenceHash,
      statusMeaning: statusMeaning ?? this.statusMeaning,
      operationalStatus: operationalStatus ?? this.operationalStatus,
      installationStatus: installationStatus ?? this.installationStatus,
      confidence: confidence ?? this.confidence,
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
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (sourceSnapshotId.present) {
      map['source_snapshot_id'] = Variable<String>(sourceSnapshotId.value);
    }
    if (providerFacilityRef.present) {
      map['provider_facility_ref'] = Variable<String>(
        providerFacilityRef.value,
      );
    }
    if (providerRecordHash.present) {
      map['provider_record_hash'] = Variable<String>(providerRecordHash.value);
    }
    if (provenanceKind.present) {
      map['provenance_kind'] = Variable<String>(provenanceKind.value);
    }
    if (verifiedAt.present) {
      map['verified_at'] = Variable<DateTime>(verifiedAt.value);
    }
    if (retrievedAt.present) {
      map['retrieved_at'] = Variable<DateTime>(retrievedAt.value);
    }
    if (evidenceHash.present) {
      map['evidence_hash'] = Variable<String>(evidenceHash.value);
    }
    if (statusMeaning.present) {
      map['status_meaning'] = Variable<String>(statusMeaning.value);
    }
    if (operationalStatus.present) {
      map['operational_status'] = Variable<String>(operationalStatus.value);
    }
    if (installationStatus.present) {
      map['installation_status'] = Variable<String>(installationStatus.value);
    }
    if (confidence.present) {
      map['confidence'] = Variable<int>(confidence.value);
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
          ..write('sourceId: $sourceId, ')
          ..write('sourceSnapshotId: $sourceSnapshotId, ')
          ..write('providerFacilityRef: $providerFacilityRef, ')
          ..write('providerRecordHash: $providerRecordHash, ')
          ..write('provenanceKind: $provenanceKind, ')
          ..write('verifiedAt: $verifiedAt, ')
          ..write('retrievedAt: $retrievedAt, ')
          ..write('evidenceHash: $evidenceHash, ')
          ..write('statusMeaning: $statusMeaning, ')
          ..write('operationalStatus: $operationalStatus, ')
          ..write('installationStatus: $installationStatus, ')
          ..write('confidence: $confidence, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StationFacilityEvidenceTable extends StationFacilityEvidence
    with TableInfo<$StationFacilityEvidenceTable, StationFacilityEvidenceData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StationFacilityEvidenceTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _facilityTypeMeta = const VerificationMeta(
    'facilityType',
  );
  @override
  late final GeneratedColumn<String> facilityType = GeneratedColumn<String>(
    'facility_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _evidenceKindMeta = const VerificationMeta(
    'evidenceKind',
  );
  @override
  late final GeneratedColumn<String> evidenceKind = GeneratedColumn<String>(
    'evidence_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceSnapshotIdMeta = const VerificationMeta(
    'sourceSnapshotId',
  );
  @override
  late final GeneratedColumn<String> sourceSnapshotId = GeneratedColumn<String>(
    'source_snapshot_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _providerRecordHashMeta =
      const VerificationMeta('providerRecordHash');
  @override
  late final GeneratedColumn<String> providerRecordHash =
      GeneratedColumn<String>(
        'provider_record_hash',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _evidenceHashMeta = const VerificationMeta(
    'evidenceHash',
  );
  @override
  late final GeneratedColumn<String> evidenceHash = GeneratedColumn<String>(
    'evidence_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _provenanceKindMeta = const VerificationMeta(
    'provenanceKind',
  );
  @override
  late final GeneratedColumn<String> provenanceKind = GeneratedColumn<String>(
    'provenance_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _installationStatusMeta =
      const VerificationMeta('installationStatus');
  @override
  late final GeneratedColumn<String> installationStatus =
      GeneratedColumn<String>(
        'installation_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('UNKNOWN'),
      );
  static const VerificationMeta _operationalStatusMeta = const VerificationMeta(
    'operationalStatus',
  );
  @override
  late final GeneratedColumn<String> operationalStatus =
      GeneratedColumn<String>(
        'operational_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('UNKNOWN'),
      );
  static const VerificationMeta _statusMeaningMeta = const VerificationMeta(
    'statusMeaning',
  );
  @override
  late final GeneratedColumn<String> statusMeaning = GeneratedColumn<String>(
    'status_meaning',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _confidenceMeta = const VerificationMeta(
    'confidence',
  );
  @override
  late final GeneratedColumn<int> confidence = GeneratedColumn<int>(
    'confidence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _verifiedAtMeta = const VerificationMeta(
    'verifiedAt',
  );
  @override
  late final GeneratedColumn<DateTime> verifiedAt = GeneratedColumn<DateTime>(
    'verified_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _retrievedAtMeta = const VerificationMeta(
    'retrievedAt',
  );
  @override
  late final GeneratedColumn<DateTime> retrievedAt = GeneratedColumn<DateTime>(
    'retrieved_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _strictRouteEligibleMeta =
      const VerificationMeta('strictRouteEligible');
  @override
  late final GeneratedColumn<bool> strictRouteEligible = GeneratedColumn<bool>(
    'strict_route_eligible',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("strict_route_eligible" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _strictRouteEligibleReasonMeta =
      const VerificationMeta('strictRouteEligibleReason');
  @override
  late final GeneratedColumn<String> strictRouteEligibleReason =
      GeneratedColumn<String>(
        'strict_route_eligible_reason',
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
    facilityType,
    evidenceKind,
    sourceId,
    sourceSnapshotId,
    providerRecordHash,
    evidenceHash,
    provenanceKind,
    installationStatus,
    operationalStatus,
    statusMeaning,
    confidence,
    verifiedAt,
    retrievedAt,
    strictRouteEligible,
    strictRouteEligibleReason,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'station_facility_evidence';
  @override
  VerificationContext validateIntegrity(
    Insertable<StationFacilityEvidenceData> instance, {
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
    if (data.containsKey('facility_type')) {
      context.handle(
        _facilityTypeMeta,
        facilityType.isAcceptableOrUnknown(
          data['facility_type']!,
          _facilityTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_facilityTypeMeta);
    }
    if (data.containsKey('evidence_kind')) {
      context.handle(
        _evidenceKindMeta,
        evidenceKind.isAcceptableOrUnknown(
          data['evidence_kind']!,
          _evidenceKindMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_evidenceKindMeta);
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('source_snapshot_id')) {
      context.handle(
        _sourceSnapshotIdMeta,
        sourceSnapshotId.isAcceptableOrUnknown(
          data['source_snapshot_id']!,
          _sourceSnapshotIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceSnapshotIdMeta);
    }
    if (data.containsKey('provider_record_hash')) {
      context.handle(
        _providerRecordHashMeta,
        providerRecordHash.isAcceptableOrUnknown(
          data['provider_record_hash']!,
          _providerRecordHashMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_providerRecordHashMeta);
    }
    if (data.containsKey('evidence_hash')) {
      context.handle(
        _evidenceHashMeta,
        evidenceHash.isAcceptableOrUnknown(
          data['evidence_hash']!,
          _evidenceHashMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_evidenceHashMeta);
    }
    if (data.containsKey('provenance_kind')) {
      context.handle(
        _provenanceKindMeta,
        provenanceKind.isAcceptableOrUnknown(
          data['provenance_kind']!,
          _provenanceKindMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_provenanceKindMeta);
    }
    if (data.containsKey('installation_status')) {
      context.handle(
        _installationStatusMeta,
        installationStatus.isAcceptableOrUnknown(
          data['installation_status']!,
          _installationStatusMeta,
        ),
      );
    }
    if (data.containsKey('operational_status')) {
      context.handle(
        _operationalStatusMeta,
        operationalStatus.isAcceptableOrUnknown(
          data['operational_status']!,
          _operationalStatusMeta,
        ),
      );
    }
    if (data.containsKey('status_meaning')) {
      context.handle(
        _statusMeaningMeta,
        statusMeaning.isAcceptableOrUnknown(
          data['status_meaning']!,
          _statusMeaningMeta,
        ),
      );
    }
    if (data.containsKey('confidence')) {
      context.handle(
        _confidenceMeta,
        confidence.isAcceptableOrUnknown(data['confidence']!, _confidenceMeta),
      );
    }
    if (data.containsKey('verified_at')) {
      context.handle(
        _verifiedAtMeta,
        verifiedAt.isAcceptableOrUnknown(data['verified_at']!, _verifiedAtMeta),
      );
    }
    if (data.containsKey('retrieved_at')) {
      context.handle(
        _retrievedAtMeta,
        retrievedAt.isAcceptableOrUnknown(
          data['retrieved_at']!,
          _retrievedAtMeta,
        ),
      );
    }
    if (data.containsKey('strict_route_eligible')) {
      context.handle(
        _strictRouteEligibleMeta,
        strictRouteEligible.isAcceptableOrUnknown(
          data['strict_route_eligible']!,
          _strictRouteEligibleMeta,
        ),
      );
    }
    if (data.containsKey('strict_route_eligible_reason')) {
      context.handle(
        _strictRouteEligibleReasonMeta,
        strictRouteEligibleReason.isAcceptableOrUnknown(
          data['strict_route_eligible_reason']!,
          _strictRouteEligibleReasonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {stationId, lineId, facilityType};
  @override
  StationFacilityEvidenceData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StationFacilityEvidenceData(
      stationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}station_id'],
      )!,
      lineId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}line_id'],
      )!,
      facilityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}facility_type'],
      )!,
      evidenceKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}evidence_kind'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      sourceSnapshotId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_snapshot_id'],
      )!,
      providerRecordHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider_record_hash'],
      )!,
      evidenceHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}evidence_hash'],
      )!,
      provenanceKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provenance_kind'],
      )!,
      installationStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}installation_status'],
      )!,
      operationalStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operational_status'],
      )!,
      statusMeaning: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status_meaning'],
      )!,
      confidence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}confidence'],
      )!,
      verifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}verified_at'],
      ),
      retrievedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}retrieved_at'],
      ),
      strictRouteEligible: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}strict_route_eligible'],
      )!,
      strictRouteEligibleReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}strict_route_eligible_reason'],
      )!,
    );
  }

  @override
  $StationFacilityEvidenceTable createAlias(String alias) {
    return $StationFacilityEvidenceTable(attachedDatabase, alias);
  }
}

class StationFacilityEvidenceData extends DataClass
    implements Insertable<StationFacilityEvidenceData> {
  final String stationId;
  final String lineId;
  final String facilityType;
  final String evidenceKind;
  final String sourceId;
  final String sourceSnapshotId;
  final String providerRecordHash;
  final String evidenceHash;
  final String provenanceKind;
  final String installationStatus;
  final String operationalStatus;
  final String statusMeaning;
  final int confidence;
  final DateTime? verifiedAt;
  final DateTime? retrievedAt;
  final bool strictRouteEligible;
  final String strictRouteEligibleReason;
  const StationFacilityEvidenceData({
    required this.stationId,
    required this.lineId,
    required this.facilityType,
    required this.evidenceKind,
    required this.sourceId,
    required this.sourceSnapshotId,
    required this.providerRecordHash,
    required this.evidenceHash,
    required this.provenanceKind,
    required this.installationStatus,
    required this.operationalStatus,
    required this.statusMeaning,
    required this.confidence,
    this.verifiedAt,
    this.retrievedAt,
    required this.strictRouteEligible,
    required this.strictRouteEligibleReason,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['station_id'] = Variable<String>(stationId);
    map['line_id'] = Variable<String>(lineId);
    map['facility_type'] = Variable<String>(facilityType);
    map['evidence_kind'] = Variable<String>(evidenceKind);
    map['source_id'] = Variable<String>(sourceId);
    map['source_snapshot_id'] = Variable<String>(sourceSnapshotId);
    map['provider_record_hash'] = Variable<String>(providerRecordHash);
    map['evidence_hash'] = Variable<String>(evidenceHash);
    map['provenance_kind'] = Variable<String>(provenanceKind);
    map['installation_status'] = Variable<String>(installationStatus);
    map['operational_status'] = Variable<String>(operationalStatus);
    map['status_meaning'] = Variable<String>(statusMeaning);
    map['confidence'] = Variable<int>(confidence);
    if (!nullToAbsent || verifiedAt != null) {
      map['verified_at'] = Variable<DateTime>(verifiedAt);
    }
    if (!nullToAbsent || retrievedAt != null) {
      map['retrieved_at'] = Variable<DateTime>(retrievedAt);
    }
    map['strict_route_eligible'] = Variable<bool>(strictRouteEligible);
    map['strict_route_eligible_reason'] = Variable<String>(
      strictRouteEligibleReason,
    );
    return map;
  }

  StationFacilityEvidenceCompanion toCompanion(bool nullToAbsent) {
    return StationFacilityEvidenceCompanion(
      stationId: Value(stationId),
      lineId: Value(lineId),
      facilityType: Value(facilityType),
      evidenceKind: Value(evidenceKind),
      sourceId: Value(sourceId),
      sourceSnapshotId: Value(sourceSnapshotId),
      providerRecordHash: Value(providerRecordHash),
      evidenceHash: Value(evidenceHash),
      provenanceKind: Value(provenanceKind),
      installationStatus: Value(installationStatus),
      operationalStatus: Value(operationalStatus),
      statusMeaning: Value(statusMeaning),
      confidence: Value(confidence),
      verifiedAt: verifiedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(verifiedAt),
      retrievedAt: retrievedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(retrievedAt),
      strictRouteEligible: Value(strictRouteEligible),
      strictRouteEligibleReason: Value(strictRouteEligibleReason),
    );
  }

  factory StationFacilityEvidenceData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StationFacilityEvidenceData(
      stationId: serializer.fromJson<String>(json['stationId']),
      lineId: serializer.fromJson<String>(json['lineId']),
      facilityType: serializer.fromJson<String>(json['facilityType']),
      evidenceKind: serializer.fromJson<String>(json['evidenceKind']),
      sourceId: serializer.fromJson<String>(json['sourceId']),
      sourceSnapshotId: serializer.fromJson<String>(json['sourceSnapshotId']),
      providerRecordHash: serializer.fromJson<String>(
        json['providerRecordHash'],
      ),
      evidenceHash: serializer.fromJson<String>(json['evidenceHash']),
      provenanceKind: serializer.fromJson<String>(json['provenanceKind']),
      installationStatus: serializer.fromJson<String>(
        json['installationStatus'],
      ),
      operationalStatus: serializer.fromJson<String>(json['operationalStatus']),
      statusMeaning: serializer.fromJson<String>(json['statusMeaning']),
      confidence: serializer.fromJson<int>(json['confidence']),
      verifiedAt: serializer.fromJson<DateTime?>(json['verifiedAt']),
      retrievedAt: serializer.fromJson<DateTime?>(json['retrievedAt']),
      strictRouteEligible: serializer.fromJson<bool>(
        json['strictRouteEligible'],
      ),
      strictRouteEligibleReason: serializer.fromJson<String>(
        json['strictRouteEligibleReason'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'stationId': serializer.toJson<String>(stationId),
      'lineId': serializer.toJson<String>(lineId),
      'facilityType': serializer.toJson<String>(facilityType),
      'evidenceKind': serializer.toJson<String>(evidenceKind),
      'sourceId': serializer.toJson<String>(sourceId),
      'sourceSnapshotId': serializer.toJson<String>(sourceSnapshotId),
      'providerRecordHash': serializer.toJson<String>(providerRecordHash),
      'evidenceHash': serializer.toJson<String>(evidenceHash),
      'provenanceKind': serializer.toJson<String>(provenanceKind),
      'installationStatus': serializer.toJson<String>(installationStatus),
      'operationalStatus': serializer.toJson<String>(operationalStatus),
      'statusMeaning': serializer.toJson<String>(statusMeaning),
      'confidence': serializer.toJson<int>(confidence),
      'verifiedAt': serializer.toJson<DateTime?>(verifiedAt),
      'retrievedAt': serializer.toJson<DateTime?>(retrievedAt),
      'strictRouteEligible': serializer.toJson<bool>(strictRouteEligible),
      'strictRouteEligibleReason': serializer.toJson<String>(
        strictRouteEligibleReason,
      ),
    };
  }

  StationFacilityEvidenceData copyWith({
    String? stationId,
    String? lineId,
    String? facilityType,
    String? evidenceKind,
    String? sourceId,
    String? sourceSnapshotId,
    String? providerRecordHash,
    String? evidenceHash,
    String? provenanceKind,
    String? installationStatus,
    String? operationalStatus,
    String? statusMeaning,
    int? confidence,
    Value<DateTime?> verifiedAt = const Value.absent(),
    Value<DateTime?> retrievedAt = const Value.absent(),
    bool? strictRouteEligible,
    String? strictRouteEligibleReason,
  }) => StationFacilityEvidenceData(
    stationId: stationId ?? this.stationId,
    lineId: lineId ?? this.lineId,
    facilityType: facilityType ?? this.facilityType,
    evidenceKind: evidenceKind ?? this.evidenceKind,
    sourceId: sourceId ?? this.sourceId,
    sourceSnapshotId: sourceSnapshotId ?? this.sourceSnapshotId,
    providerRecordHash: providerRecordHash ?? this.providerRecordHash,
    evidenceHash: evidenceHash ?? this.evidenceHash,
    provenanceKind: provenanceKind ?? this.provenanceKind,
    installationStatus: installationStatus ?? this.installationStatus,
    operationalStatus: operationalStatus ?? this.operationalStatus,
    statusMeaning: statusMeaning ?? this.statusMeaning,
    confidence: confidence ?? this.confidence,
    verifiedAt: verifiedAt.present ? verifiedAt.value : this.verifiedAt,
    retrievedAt: retrievedAt.present ? retrievedAt.value : this.retrievedAt,
    strictRouteEligible: strictRouteEligible ?? this.strictRouteEligible,
    strictRouteEligibleReason:
        strictRouteEligibleReason ?? this.strictRouteEligibleReason,
  );
  StationFacilityEvidenceData copyWithCompanion(
    StationFacilityEvidenceCompanion data,
  ) {
    return StationFacilityEvidenceData(
      stationId: data.stationId.present ? data.stationId.value : this.stationId,
      lineId: data.lineId.present ? data.lineId.value : this.lineId,
      facilityType: data.facilityType.present
          ? data.facilityType.value
          : this.facilityType,
      evidenceKind: data.evidenceKind.present
          ? data.evidenceKind.value
          : this.evidenceKind,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      sourceSnapshotId: data.sourceSnapshotId.present
          ? data.sourceSnapshotId.value
          : this.sourceSnapshotId,
      providerRecordHash: data.providerRecordHash.present
          ? data.providerRecordHash.value
          : this.providerRecordHash,
      evidenceHash: data.evidenceHash.present
          ? data.evidenceHash.value
          : this.evidenceHash,
      provenanceKind: data.provenanceKind.present
          ? data.provenanceKind.value
          : this.provenanceKind,
      installationStatus: data.installationStatus.present
          ? data.installationStatus.value
          : this.installationStatus,
      operationalStatus: data.operationalStatus.present
          ? data.operationalStatus.value
          : this.operationalStatus,
      statusMeaning: data.statusMeaning.present
          ? data.statusMeaning.value
          : this.statusMeaning,
      confidence: data.confidence.present
          ? data.confidence.value
          : this.confidence,
      verifiedAt: data.verifiedAt.present
          ? data.verifiedAt.value
          : this.verifiedAt,
      retrievedAt: data.retrievedAt.present
          ? data.retrievedAt.value
          : this.retrievedAt,
      strictRouteEligible: data.strictRouteEligible.present
          ? data.strictRouteEligible.value
          : this.strictRouteEligible,
      strictRouteEligibleReason: data.strictRouteEligibleReason.present
          ? data.strictRouteEligibleReason.value
          : this.strictRouteEligibleReason,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StationFacilityEvidenceData(')
          ..write('stationId: $stationId, ')
          ..write('lineId: $lineId, ')
          ..write('facilityType: $facilityType, ')
          ..write('evidenceKind: $evidenceKind, ')
          ..write('sourceId: $sourceId, ')
          ..write('sourceSnapshotId: $sourceSnapshotId, ')
          ..write('providerRecordHash: $providerRecordHash, ')
          ..write('evidenceHash: $evidenceHash, ')
          ..write('provenanceKind: $provenanceKind, ')
          ..write('installationStatus: $installationStatus, ')
          ..write('operationalStatus: $operationalStatus, ')
          ..write('statusMeaning: $statusMeaning, ')
          ..write('confidence: $confidence, ')
          ..write('verifiedAt: $verifiedAt, ')
          ..write('retrievedAt: $retrievedAt, ')
          ..write('strictRouteEligible: $strictRouteEligible, ')
          ..write('strictRouteEligibleReason: $strictRouteEligibleReason')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    stationId,
    lineId,
    facilityType,
    evidenceKind,
    sourceId,
    sourceSnapshotId,
    providerRecordHash,
    evidenceHash,
    provenanceKind,
    installationStatus,
    operationalStatus,
    statusMeaning,
    confidence,
    verifiedAt,
    retrievedAt,
    strictRouteEligible,
    strictRouteEligibleReason,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StationFacilityEvidenceData &&
          other.stationId == this.stationId &&
          other.lineId == this.lineId &&
          other.facilityType == this.facilityType &&
          other.evidenceKind == this.evidenceKind &&
          other.sourceId == this.sourceId &&
          other.sourceSnapshotId == this.sourceSnapshotId &&
          other.providerRecordHash == this.providerRecordHash &&
          other.evidenceHash == this.evidenceHash &&
          other.provenanceKind == this.provenanceKind &&
          other.installationStatus == this.installationStatus &&
          other.operationalStatus == this.operationalStatus &&
          other.statusMeaning == this.statusMeaning &&
          other.confidence == this.confidence &&
          other.verifiedAt == this.verifiedAt &&
          other.retrievedAt == this.retrievedAt &&
          other.strictRouteEligible == this.strictRouteEligible &&
          other.strictRouteEligibleReason == this.strictRouteEligibleReason);
}

class StationFacilityEvidenceCompanion
    extends UpdateCompanion<StationFacilityEvidenceData> {
  final Value<String> stationId;
  final Value<String> lineId;
  final Value<String> facilityType;
  final Value<String> evidenceKind;
  final Value<String> sourceId;
  final Value<String> sourceSnapshotId;
  final Value<String> providerRecordHash;
  final Value<String> evidenceHash;
  final Value<String> provenanceKind;
  final Value<String> installationStatus;
  final Value<String> operationalStatus;
  final Value<String> statusMeaning;
  final Value<int> confidence;
  final Value<DateTime?> verifiedAt;
  final Value<DateTime?> retrievedAt;
  final Value<bool> strictRouteEligible;
  final Value<String> strictRouteEligibleReason;
  final Value<int> rowid;
  const StationFacilityEvidenceCompanion({
    this.stationId = const Value.absent(),
    this.lineId = const Value.absent(),
    this.facilityType = const Value.absent(),
    this.evidenceKind = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.sourceSnapshotId = const Value.absent(),
    this.providerRecordHash = const Value.absent(),
    this.evidenceHash = const Value.absent(),
    this.provenanceKind = const Value.absent(),
    this.installationStatus = const Value.absent(),
    this.operationalStatus = const Value.absent(),
    this.statusMeaning = const Value.absent(),
    this.confidence = const Value.absent(),
    this.verifiedAt = const Value.absent(),
    this.retrievedAt = const Value.absent(),
    this.strictRouteEligible = const Value.absent(),
    this.strictRouteEligibleReason = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StationFacilityEvidenceCompanion.insert({
    required String stationId,
    required String lineId,
    required String facilityType,
    required String evidenceKind,
    required String sourceId,
    required String sourceSnapshotId,
    required String providerRecordHash,
    required String evidenceHash,
    required String provenanceKind,
    this.installationStatus = const Value.absent(),
    this.operationalStatus = const Value.absent(),
    this.statusMeaning = const Value.absent(),
    this.confidence = const Value.absent(),
    this.verifiedAt = const Value.absent(),
    this.retrievedAt = const Value.absent(),
    this.strictRouteEligible = const Value.absent(),
    this.strictRouteEligibleReason = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : stationId = Value(stationId),
       lineId = Value(lineId),
       facilityType = Value(facilityType),
       evidenceKind = Value(evidenceKind),
       sourceId = Value(sourceId),
       sourceSnapshotId = Value(sourceSnapshotId),
       providerRecordHash = Value(providerRecordHash),
       evidenceHash = Value(evidenceHash),
       provenanceKind = Value(provenanceKind);
  static Insertable<StationFacilityEvidenceData> custom({
    Expression<String>? stationId,
    Expression<String>? lineId,
    Expression<String>? facilityType,
    Expression<String>? evidenceKind,
    Expression<String>? sourceId,
    Expression<String>? sourceSnapshotId,
    Expression<String>? providerRecordHash,
    Expression<String>? evidenceHash,
    Expression<String>? provenanceKind,
    Expression<String>? installationStatus,
    Expression<String>? operationalStatus,
    Expression<String>? statusMeaning,
    Expression<int>? confidence,
    Expression<DateTime>? verifiedAt,
    Expression<DateTime>? retrievedAt,
    Expression<bool>? strictRouteEligible,
    Expression<String>? strictRouteEligibleReason,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (stationId != null) 'station_id': stationId,
      if (lineId != null) 'line_id': lineId,
      if (facilityType != null) 'facility_type': facilityType,
      if (evidenceKind != null) 'evidence_kind': evidenceKind,
      if (sourceId != null) 'source_id': sourceId,
      if (sourceSnapshotId != null) 'source_snapshot_id': sourceSnapshotId,
      if (providerRecordHash != null)
        'provider_record_hash': providerRecordHash,
      if (evidenceHash != null) 'evidence_hash': evidenceHash,
      if (provenanceKind != null) 'provenance_kind': provenanceKind,
      if (installationStatus != null) 'installation_status': installationStatus,
      if (operationalStatus != null) 'operational_status': operationalStatus,
      if (statusMeaning != null) 'status_meaning': statusMeaning,
      if (confidence != null) 'confidence': confidence,
      if (verifiedAt != null) 'verified_at': verifiedAt,
      if (retrievedAt != null) 'retrieved_at': retrievedAt,
      if (strictRouteEligible != null)
        'strict_route_eligible': strictRouteEligible,
      if (strictRouteEligibleReason != null)
        'strict_route_eligible_reason': strictRouteEligibleReason,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StationFacilityEvidenceCompanion copyWith({
    Value<String>? stationId,
    Value<String>? lineId,
    Value<String>? facilityType,
    Value<String>? evidenceKind,
    Value<String>? sourceId,
    Value<String>? sourceSnapshotId,
    Value<String>? providerRecordHash,
    Value<String>? evidenceHash,
    Value<String>? provenanceKind,
    Value<String>? installationStatus,
    Value<String>? operationalStatus,
    Value<String>? statusMeaning,
    Value<int>? confidence,
    Value<DateTime?>? verifiedAt,
    Value<DateTime?>? retrievedAt,
    Value<bool>? strictRouteEligible,
    Value<String>? strictRouteEligibleReason,
    Value<int>? rowid,
  }) {
    return StationFacilityEvidenceCompanion(
      stationId: stationId ?? this.stationId,
      lineId: lineId ?? this.lineId,
      facilityType: facilityType ?? this.facilityType,
      evidenceKind: evidenceKind ?? this.evidenceKind,
      sourceId: sourceId ?? this.sourceId,
      sourceSnapshotId: sourceSnapshotId ?? this.sourceSnapshotId,
      providerRecordHash: providerRecordHash ?? this.providerRecordHash,
      evidenceHash: evidenceHash ?? this.evidenceHash,
      provenanceKind: provenanceKind ?? this.provenanceKind,
      installationStatus: installationStatus ?? this.installationStatus,
      operationalStatus: operationalStatus ?? this.operationalStatus,
      statusMeaning: statusMeaning ?? this.statusMeaning,
      confidence: confidence ?? this.confidence,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      retrievedAt: retrievedAt ?? this.retrievedAt,
      strictRouteEligible: strictRouteEligible ?? this.strictRouteEligible,
      strictRouteEligibleReason:
          strictRouteEligibleReason ?? this.strictRouteEligibleReason,
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
    if (facilityType.present) {
      map['facility_type'] = Variable<String>(facilityType.value);
    }
    if (evidenceKind.present) {
      map['evidence_kind'] = Variable<String>(evidenceKind.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (sourceSnapshotId.present) {
      map['source_snapshot_id'] = Variable<String>(sourceSnapshotId.value);
    }
    if (providerRecordHash.present) {
      map['provider_record_hash'] = Variable<String>(providerRecordHash.value);
    }
    if (evidenceHash.present) {
      map['evidence_hash'] = Variable<String>(evidenceHash.value);
    }
    if (provenanceKind.present) {
      map['provenance_kind'] = Variable<String>(provenanceKind.value);
    }
    if (installationStatus.present) {
      map['installation_status'] = Variable<String>(installationStatus.value);
    }
    if (operationalStatus.present) {
      map['operational_status'] = Variable<String>(operationalStatus.value);
    }
    if (statusMeaning.present) {
      map['status_meaning'] = Variable<String>(statusMeaning.value);
    }
    if (confidence.present) {
      map['confidence'] = Variable<int>(confidence.value);
    }
    if (verifiedAt.present) {
      map['verified_at'] = Variable<DateTime>(verifiedAt.value);
    }
    if (retrievedAt.present) {
      map['retrieved_at'] = Variable<DateTime>(retrievedAt.value);
    }
    if (strictRouteEligible.present) {
      map['strict_route_eligible'] = Variable<bool>(strictRouteEligible.value);
    }
    if (strictRouteEligibleReason.present) {
      map['strict_route_eligible_reason'] = Variable<String>(
        strictRouteEligibleReason.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StationFacilityEvidenceCompanion(')
          ..write('stationId: $stationId, ')
          ..write('lineId: $lineId, ')
          ..write('facilityType: $facilityType, ')
          ..write('evidenceKind: $evidenceKind, ')
          ..write('sourceId: $sourceId, ')
          ..write('sourceSnapshotId: $sourceSnapshotId, ')
          ..write('providerRecordHash: $providerRecordHash, ')
          ..write('evidenceHash: $evidenceHash, ')
          ..write('provenanceKind: $provenanceKind, ')
          ..write('installationStatus: $installationStatus, ')
          ..write('operationalStatus: $operationalStatus, ')
          ..write('statusMeaning: $statusMeaning, ')
          ..write('confidence: $confidence, ')
          ..write('verifiedAt: $verifiedAt, ')
          ..write('retrievedAt: $retrievedAt, ')
          ..write('strictRouteEligible: $strictRouteEligible, ')
          ..write('strictRouteEligibleReason: $strictRouteEligibleReason, ')
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
  static const VerificationMeta _distanceMetersMeta = const VerificationMeta(
    'distanceMeters',
  );
  @override
  late final GeneratedColumn<int> distanceMeters = GeneratedColumn<int>(
    'distance_meters',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
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
  static const VerificationMeta _requiresElevatorMeta = const VerificationMeta(
    'requiresElevator',
  );
  @override
  late final GeneratedColumn<bool> requiresElevator = GeneratedColumn<bool>(
    'requires_elevator',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("requires_elevator" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _requiresEscalatorMeta = const VerificationMeta(
    'requiresEscalator',
  );
  @override
  late final GeneratedColumn<bool> requiresEscalator = GeneratedColumn<bool>(
    'requires_escalator',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("requires_escalator" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _slopeLevelMeta = const VerificationMeta(
    'slopeLevel',
  );
  @override
  late final GeneratedColumn<int> slopeLevel = GeneratedColumn<int>(
    'slope_level',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _widthLevelMeta = const VerificationMeta(
    'widthLevel',
  );
  @override
  late final GeneratedColumn<int> widthLevel = GeneratedColumn<int>(
    'width_level',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(2),
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
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sourceSnapshotIdMeta = const VerificationMeta(
    'sourceSnapshotId',
  );
  @override
  late final GeneratedColumn<String> sourceSnapshotId = GeneratedColumn<String>(
    'source_snapshot_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _providerRecordHashMeta =
      const VerificationMeta('providerRecordHash');
  @override
  late final GeneratedColumn<String> providerRecordHash =
      GeneratedColumn<String>(
        'provider_record_hash',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant(''),
      );
  static const VerificationMeta _provenanceKindMeta = const VerificationMeta(
    'provenanceKind',
  );
  @override
  late final GeneratedColumn<String> provenanceKind = GeneratedColumn<String>(
    'provenance_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('UNKNOWN'),
  );
  static const VerificationMeta _verificationStatusMeta =
      const VerificationMeta('verificationStatus');
  @override
  late final GeneratedColumn<String> verificationStatus =
      GeneratedColumn<String>(
        'verification_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('UNKNOWN'),
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
  static const VerificationMeta _evidenceHashMeta = const VerificationMeta(
    'evidenceHash',
  );
  @override
  late final GeneratedColumn<String> evidenceHash = GeneratedColumn<String>(
    'evidence_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
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
    edgeType,
    distanceMeters,
    durationSeconds,
    includesStairs,
    requiresElevator,
    requiresEscalator,
    slopeLevel,
    widthLevel,
    reliabilityScore,
    accessibilityStatus,
    sourceId,
    sourceSnapshotId,
    providerRecordHash,
    provenanceKind,
    verificationStatus,
    facilityId,
    lastVerifiedAt,
    evidenceHash,
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
    if (data.containsKey('edge_type')) {
      context.handle(
        _edgeTypeMeta,
        edgeType.isAcceptableOrUnknown(data['edge_type']!, _edgeTypeMeta),
      );
    }
    if (data.containsKey('distance_meters')) {
      context.handle(
        _distanceMetersMeta,
        distanceMeters.isAcceptableOrUnknown(
          data['distance_meters']!,
          _distanceMetersMeta,
        ),
      );
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
    if (data.containsKey('includes_stairs')) {
      context.handle(
        _includesStairsMeta,
        includesStairs.isAcceptableOrUnknown(
          data['includes_stairs']!,
          _includesStairsMeta,
        ),
      );
    }
    if (data.containsKey('requires_elevator')) {
      context.handle(
        _requiresElevatorMeta,
        requiresElevator.isAcceptableOrUnknown(
          data['requires_elevator']!,
          _requiresElevatorMeta,
        ),
      );
    }
    if (data.containsKey('requires_escalator')) {
      context.handle(
        _requiresEscalatorMeta,
        requiresEscalator.isAcceptableOrUnknown(
          data['requires_escalator']!,
          _requiresEscalatorMeta,
        ),
      );
    }
    if (data.containsKey('slope_level')) {
      context.handle(
        _slopeLevelMeta,
        slopeLevel.isAcceptableOrUnknown(data['slope_level']!, _slopeLevelMeta),
      );
    }
    if (data.containsKey('width_level')) {
      context.handle(
        _widthLevelMeta,
        widthLevel.isAcceptableOrUnknown(data['width_level']!, _widthLevelMeta),
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
    if (data.containsKey('accessibility_status')) {
      context.handle(
        _accessibilityStatusMeta,
        accessibilityStatus.isAcceptableOrUnknown(
          data['accessibility_status']!,
          _accessibilityStatusMeta,
        ),
      );
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    }
    if (data.containsKey('source_snapshot_id')) {
      context.handle(
        _sourceSnapshotIdMeta,
        sourceSnapshotId.isAcceptableOrUnknown(
          data['source_snapshot_id']!,
          _sourceSnapshotIdMeta,
        ),
      );
    }
    if (data.containsKey('provider_record_hash')) {
      context.handle(
        _providerRecordHashMeta,
        providerRecordHash.isAcceptableOrUnknown(
          data['provider_record_hash']!,
          _providerRecordHashMeta,
        ),
      );
    }
    if (data.containsKey('provenance_kind')) {
      context.handle(
        _provenanceKindMeta,
        provenanceKind.isAcceptableOrUnknown(
          data['provenance_kind']!,
          _provenanceKindMeta,
        ),
      );
    }
    if (data.containsKey('verification_status')) {
      context.handle(
        _verificationStatusMeta,
        verificationStatus.isAcceptableOrUnknown(
          data['verification_status']!,
          _verificationStatusMeta,
        ),
      );
    }
    if (data.containsKey('facility_id')) {
      context.handle(
        _facilityIdMeta,
        facilityId.isAcceptableOrUnknown(data['facility_id']!, _facilityIdMeta),
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
    if (data.containsKey('evidence_hash')) {
      context.handle(
        _evidenceHashMeta,
        evidenceHash.isAcceptableOrUnknown(
          data['evidence_hash']!,
          _evidenceHashMeta,
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
      edgeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}edge_type'],
      )!,
      distanceMeters: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}distance_meters'],
      )!,
      durationSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_seconds'],
      )!,
      includesStairs: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}includes_stairs'],
      )!,
      requiresElevator: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}requires_elevator'],
      )!,
      requiresEscalator: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}requires_escalator'],
      )!,
      slopeLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}slope_level'],
      )!,
      widthLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}width_level'],
      )!,
      reliabilityScore: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reliability_score'],
      )!,
      accessibilityStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}accessibility_status'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      sourceSnapshotId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_snapshot_id'],
      )!,
      providerRecordHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider_record_hash'],
      )!,
      provenanceKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provenance_kind'],
      )!,
      verificationStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}verification_status'],
      )!,
      facilityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}facility_id'],
      ),
      lastVerifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_verified_at'],
      ),
      evidenceHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}evidence_hash'],
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
  final String edgeType;
  final int distanceMeters;
  final int durationSeconds;
  final bool includesStairs;
  final bool requiresElevator;
  final bool requiresEscalator;
  final int slopeLevel;
  final int widthLevel;
  final int reliabilityScore;
  final String accessibilityStatus;
  final String sourceId;
  final String sourceSnapshotId;
  final String providerRecordHash;
  final String provenanceKind;
  final String verificationStatus;
  final String? facilityId;
  final DateTime? lastVerifiedAt;
  final String evidenceHash;
  final String instruction;
  const InternalRouteEdge({
    required this.id,
    required this.fromNodeId,
    required this.toNodeId,
    required this.edgeType,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.includesStairs,
    required this.requiresElevator,
    required this.requiresEscalator,
    required this.slopeLevel,
    required this.widthLevel,
    required this.reliabilityScore,
    required this.accessibilityStatus,
    required this.sourceId,
    required this.sourceSnapshotId,
    required this.providerRecordHash,
    required this.provenanceKind,
    required this.verificationStatus,
    this.facilityId,
    this.lastVerifiedAt,
    required this.evidenceHash,
    required this.instruction,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['from_node_id'] = Variable<String>(fromNodeId);
    map['to_node_id'] = Variable<String>(toNodeId);
    map['edge_type'] = Variable<String>(edgeType);
    map['distance_meters'] = Variable<int>(distanceMeters);
    map['duration_seconds'] = Variable<int>(durationSeconds);
    map['includes_stairs'] = Variable<bool>(includesStairs);
    map['requires_elevator'] = Variable<bool>(requiresElevator);
    map['requires_escalator'] = Variable<bool>(requiresEscalator);
    map['slope_level'] = Variable<int>(slopeLevel);
    map['width_level'] = Variable<int>(widthLevel);
    map['reliability_score'] = Variable<int>(reliabilityScore);
    map['accessibility_status'] = Variable<String>(accessibilityStatus);
    map['source_id'] = Variable<String>(sourceId);
    map['source_snapshot_id'] = Variable<String>(sourceSnapshotId);
    map['provider_record_hash'] = Variable<String>(providerRecordHash);
    map['provenance_kind'] = Variable<String>(provenanceKind);
    map['verification_status'] = Variable<String>(verificationStatus);
    if (!nullToAbsent || facilityId != null) {
      map['facility_id'] = Variable<String>(facilityId);
    }
    if (!nullToAbsent || lastVerifiedAt != null) {
      map['last_verified_at'] = Variable<DateTime>(lastVerifiedAt);
    }
    map['evidence_hash'] = Variable<String>(evidenceHash);
    map['instruction'] = Variable<String>(instruction);
    return map;
  }

  InternalRouteEdgesCompanion toCompanion(bool nullToAbsent) {
    return InternalRouteEdgesCompanion(
      id: Value(id),
      fromNodeId: Value(fromNodeId),
      toNodeId: Value(toNodeId),
      edgeType: Value(edgeType),
      distanceMeters: Value(distanceMeters),
      durationSeconds: Value(durationSeconds),
      includesStairs: Value(includesStairs),
      requiresElevator: Value(requiresElevator),
      requiresEscalator: Value(requiresEscalator),
      slopeLevel: Value(slopeLevel),
      widthLevel: Value(widthLevel),
      reliabilityScore: Value(reliabilityScore),
      accessibilityStatus: Value(accessibilityStatus),
      sourceId: Value(sourceId),
      sourceSnapshotId: Value(sourceSnapshotId),
      providerRecordHash: Value(providerRecordHash),
      provenanceKind: Value(provenanceKind),
      verificationStatus: Value(verificationStatus),
      facilityId: facilityId == null && nullToAbsent
          ? const Value.absent()
          : Value(facilityId),
      lastVerifiedAt: lastVerifiedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastVerifiedAt),
      evidenceHash: Value(evidenceHash),
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
      edgeType: serializer.fromJson<String>(json['edgeType']),
      distanceMeters: serializer.fromJson<int>(json['distanceMeters']),
      durationSeconds: serializer.fromJson<int>(json['durationSeconds']),
      includesStairs: serializer.fromJson<bool>(json['includesStairs']),
      requiresElevator: serializer.fromJson<bool>(json['requiresElevator']),
      requiresEscalator: serializer.fromJson<bool>(json['requiresEscalator']),
      slopeLevel: serializer.fromJson<int>(json['slopeLevel']),
      widthLevel: serializer.fromJson<int>(json['widthLevel']),
      reliabilityScore: serializer.fromJson<int>(json['reliabilityScore']),
      accessibilityStatus: serializer.fromJson<String>(
        json['accessibilityStatus'],
      ),
      sourceId: serializer.fromJson<String>(json['sourceId']),
      sourceSnapshotId: serializer.fromJson<String>(json['sourceSnapshotId']),
      providerRecordHash: serializer.fromJson<String>(
        json['providerRecordHash'],
      ),
      provenanceKind: serializer.fromJson<String>(json['provenanceKind']),
      verificationStatus: serializer.fromJson<String>(
        json['verificationStatus'],
      ),
      facilityId: serializer.fromJson<String?>(json['facilityId']),
      lastVerifiedAt: serializer.fromJson<DateTime?>(json['lastVerifiedAt']),
      evidenceHash: serializer.fromJson<String>(json['evidenceHash']),
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
      'edgeType': serializer.toJson<String>(edgeType),
      'distanceMeters': serializer.toJson<int>(distanceMeters),
      'durationSeconds': serializer.toJson<int>(durationSeconds),
      'includesStairs': serializer.toJson<bool>(includesStairs),
      'requiresElevator': serializer.toJson<bool>(requiresElevator),
      'requiresEscalator': serializer.toJson<bool>(requiresEscalator),
      'slopeLevel': serializer.toJson<int>(slopeLevel),
      'widthLevel': serializer.toJson<int>(widthLevel),
      'reliabilityScore': serializer.toJson<int>(reliabilityScore),
      'accessibilityStatus': serializer.toJson<String>(accessibilityStatus),
      'sourceId': serializer.toJson<String>(sourceId),
      'sourceSnapshotId': serializer.toJson<String>(sourceSnapshotId),
      'providerRecordHash': serializer.toJson<String>(providerRecordHash),
      'provenanceKind': serializer.toJson<String>(provenanceKind),
      'verificationStatus': serializer.toJson<String>(verificationStatus),
      'facilityId': serializer.toJson<String?>(facilityId),
      'lastVerifiedAt': serializer.toJson<DateTime?>(lastVerifiedAt),
      'evidenceHash': serializer.toJson<String>(evidenceHash),
      'instruction': serializer.toJson<String>(instruction),
    };
  }

  InternalRouteEdge copyWith({
    String? id,
    String? fromNodeId,
    String? toNodeId,
    String? edgeType,
    int? distanceMeters,
    int? durationSeconds,
    bool? includesStairs,
    bool? requiresElevator,
    bool? requiresEscalator,
    int? slopeLevel,
    int? widthLevel,
    int? reliabilityScore,
    String? accessibilityStatus,
    String? sourceId,
    String? sourceSnapshotId,
    String? providerRecordHash,
    String? provenanceKind,
    String? verificationStatus,
    Value<String?> facilityId = const Value.absent(),
    Value<DateTime?> lastVerifiedAt = const Value.absent(),
    String? evidenceHash,
    String? instruction,
  }) => InternalRouteEdge(
    id: id ?? this.id,
    fromNodeId: fromNodeId ?? this.fromNodeId,
    toNodeId: toNodeId ?? this.toNodeId,
    edgeType: edgeType ?? this.edgeType,
    distanceMeters: distanceMeters ?? this.distanceMeters,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    includesStairs: includesStairs ?? this.includesStairs,
    requiresElevator: requiresElevator ?? this.requiresElevator,
    requiresEscalator: requiresEscalator ?? this.requiresEscalator,
    slopeLevel: slopeLevel ?? this.slopeLevel,
    widthLevel: widthLevel ?? this.widthLevel,
    reliabilityScore: reliabilityScore ?? this.reliabilityScore,
    accessibilityStatus: accessibilityStatus ?? this.accessibilityStatus,
    sourceId: sourceId ?? this.sourceId,
    sourceSnapshotId: sourceSnapshotId ?? this.sourceSnapshotId,
    providerRecordHash: providerRecordHash ?? this.providerRecordHash,
    provenanceKind: provenanceKind ?? this.provenanceKind,
    verificationStatus: verificationStatus ?? this.verificationStatus,
    facilityId: facilityId.present ? facilityId.value : this.facilityId,
    lastVerifiedAt: lastVerifiedAt.present
        ? lastVerifiedAt.value
        : this.lastVerifiedAt,
    evidenceHash: evidenceHash ?? this.evidenceHash,
    instruction: instruction ?? this.instruction,
  );
  InternalRouteEdge copyWithCompanion(InternalRouteEdgesCompanion data) {
    return InternalRouteEdge(
      id: data.id.present ? data.id.value : this.id,
      fromNodeId: data.fromNodeId.present
          ? data.fromNodeId.value
          : this.fromNodeId,
      toNodeId: data.toNodeId.present ? data.toNodeId.value : this.toNodeId,
      edgeType: data.edgeType.present ? data.edgeType.value : this.edgeType,
      distanceMeters: data.distanceMeters.present
          ? data.distanceMeters.value
          : this.distanceMeters,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
      includesStairs: data.includesStairs.present
          ? data.includesStairs.value
          : this.includesStairs,
      requiresElevator: data.requiresElevator.present
          ? data.requiresElevator.value
          : this.requiresElevator,
      requiresEscalator: data.requiresEscalator.present
          ? data.requiresEscalator.value
          : this.requiresEscalator,
      slopeLevel: data.slopeLevel.present
          ? data.slopeLevel.value
          : this.slopeLevel,
      widthLevel: data.widthLevel.present
          ? data.widthLevel.value
          : this.widthLevel,
      reliabilityScore: data.reliabilityScore.present
          ? data.reliabilityScore.value
          : this.reliabilityScore,
      accessibilityStatus: data.accessibilityStatus.present
          ? data.accessibilityStatus.value
          : this.accessibilityStatus,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      sourceSnapshotId: data.sourceSnapshotId.present
          ? data.sourceSnapshotId.value
          : this.sourceSnapshotId,
      providerRecordHash: data.providerRecordHash.present
          ? data.providerRecordHash.value
          : this.providerRecordHash,
      provenanceKind: data.provenanceKind.present
          ? data.provenanceKind.value
          : this.provenanceKind,
      verificationStatus: data.verificationStatus.present
          ? data.verificationStatus.value
          : this.verificationStatus,
      facilityId: data.facilityId.present
          ? data.facilityId.value
          : this.facilityId,
      lastVerifiedAt: data.lastVerifiedAt.present
          ? data.lastVerifiedAt.value
          : this.lastVerifiedAt,
      evidenceHash: data.evidenceHash.present
          ? data.evidenceHash.value
          : this.evidenceHash,
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
          ..write('edgeType: $edgeType, ')
          ..write('distanceMeters: $distanceMeters, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('includesStairs: $includesStairs, ')
          ..write('requiresElevator: $requiresElevator, ')
          ..write('requiresEscalator: $requiresEscalator, ')
          ..write('slopeLevel: $slopeLevel, ')
          ..write('widthLevel: $widthLevel, ')
          ..write('reliabilityScore: $reliabilityScore, ')
          ..write('accessibilityStatus: $accessibilityStatus, ')
          ..write('sourceId: $sourceId, ')
          ..write('sourceSnapshotId: $sourceSnapshotId, ')
          ..write('providerRecordHash: $providerRecordHash, ')
          ..write('provenanceKind: $provenanceKind, ')
          ..write('verificationStatus: $verificationStatus, ')
          ..write('facilityId: $facilityId, ')
          ..write('lastVerifiedAt: $lastVerifiedAt, ')
          ..write('evidenceHash: $evidenceHash, ')
          ..write('instruction: $instruction')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    fromNodeId,
    toNodeId,
    edgeType,
    distanceMeters,
    durationSeconds,
    includesStairs,
    requiresElevator,
    requiresEscalator,
    slopeLevel,
    widthLevel,
    reliabilityScore,
    accessibilityStatus,
    sourceId,
    sourceSnapshotId,
    providerRecordHash,
    provenanceKind,
    verificationStatus,
    facilityId,
    lastVerifiedAt,
    evidenceHash,
    instruction,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InternalRouteEdge &&
          other.id == this.id &&
          other.fromNodeId == this.fromNodeId &&
          other.toNodeId == this.toNodeId &&
          other.edgeType == this.edgeType &&
          other.distanceMeters == this.distanceMeters &&
          other.durationSeconds == this.durationSeconds &&
          other.includesStairs == this.includesStairs &&
          other.requiresElevator == this.requiresElevator &&
          other.requiresEscalator == this.requiresEscalator &&
          other.slopeLevel == this.slopeLevel &&
          other.widthLevel == this.widthLevel &&
          other.reliabilityScore == this.reliabilityScore &&
          other.accessibilityStatus == this.accessibilityStatus &&
          other.sourceId == this.sourceId &&
          other.sourceSnapshotId == this.sourceSnapshotId &&
          other.providerRecordHash == this.providerRecordHash &&
          other.provenanceKind == this.provenanceKind &&
          other.verificationStatus == this.verificationStatus &&
          other.facilityId == this.facilityId &&
          other.lastVerifiedAt == this.lastVerifiedAt &&
          other.evidenceHash == this.evidenceHash &&
          other.instruction == this.instruction);
}

class InternalRouteEdgesCompanion extends UpdateCompanion<InternalRouteEdge> {
  final Value<String> id;
  final Value<String> fromNodeId;
  final Value<String> toNodeId;
  final Value<String> edgeType;
  final Value<int> distanceMeters;
  final Value<int> durationSeconds;
  final Value<bool> includesStairs;
  final Value<bool> requiresElevator;
  final Value<bool> requiresEscalator;
  final Value<int> slopeLevel;
  final Value<int> widthLevel;
  final Value<int> reliabilityScore;
  final Value<String> accessibilityStatus;
  final Value<String> sourceId;
  final Value<String> sourceSnapshotId;
  final Value<String> providerRecordHash;
  final Value<String> provenanceKind;
  final Value<String> verificationStatus;
  final Value<String?> facilityId;
  final Value<DateTime?> lastVerifiedAt;
  final Value<String> evidenceHash;
  final Value<String> instruction;
  final Value<int> rowid;
  const InternalRouteEdgesCompanion({
    this.id = const Value.absent(),
    this.fromNodeId = const Value.absent(),
    this.toNodeId = const Value.absent(),
    this.edgeType = const Value.absent(),
    this.distanceMeters = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.includesStairs = const Value.absent(),
    this.requiresElevator = const Value.absent(),
    this.requiresEscalator = const Value.absent(),
    this.slopeLevel = const Value.absent(),
    this.widthLevel = const Value.absent(),
    this.reliabilityScore = const Value.absent(),
    this.accessibilityStatus = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.sourceSnapshotId = const Value.absent(),
    this.providerRecordHash = const Value.absent(),
    this.provenanceKind = const Value.absent(),
    this.verificationStatus = const Value.absent(),
    this.facilityId = const Value.absent(),
    this.lastVerifiedAt = const Value.absent(),
    this.evidenceHash = const Value.absent(),
    this.instruction = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InternalRouteEdgesCompanion.insert({
    required String id,
    required String fromNodeId,
    required String toNodeId,
    this.edgeType = const Value.absent(),
    this.distanceMeters = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.includesStairs = const Value.absent(),
    this.requiresElevator = const Value.absent(),
    this.requiresEscalator = const Value.absent(),
    this.slopeLevel = const Value.absent(),
    this.widthLevel = const Value.absent(),
    this.reliabilityScore = const Value.absent(),
    this.accessibilityStatus = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.sourceSnapshotId = const Value.absent(),
    this.providerRecordHash = const Value.absent(),
    this.provenanceKind = const Value.absent(),
    this.verificationStatus = const Value.absent(),
    this.facilityId = const Value.absent(),
    this.lastVerifiedAt = const Value.absent(),
    this.evidenceHash = const Value.absent(),
    this.instruction = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       fromNodeId = Value(fromNodeId),
       toNodeId = Value(toNodeId);
  static Insertable<InternalRouteEdge> custom({
    Expression<String>? id,
    Expression<String>? fromNodeId,
    Expression<String>? toNodeId,
    Expression<String>? edgeType,
    Expression<int>? distanceMeters,
    Expression<int>? durationSeconds,
    Expression<bool>? includesStairs,
    Expression<bool>? requiresElevator,
    Expression<bool>? requiresEscalator,
    Expression<int>? slopeLevel,
    Expression<int>? widthLevel,
    Expression<int>? reliabilityScore,
    Expression<String>? accessibilityStatus,
    Expression<String>? sourceId,
    Expression<String>? sourceSnapshotId,
    Expression<String>? providerRecordHash,
    Expression<String>? provenanceKind,
    Expression<String>? verificationStatus,
    Expression<String>? facilityId,
    Expression<DateTime>? lastVerifiedAt,
    Expression<String>? evidenceHash,
    Expression<String>? instruction,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (fromNodeId != null) 'from_node_id': fromNodeId,
      if (toNodeId != null) 'to_node_id': toNodeId,
      if (edgeType != null) 'edge_type': edgeType,
      if (distanceMeters != null) 'distance_meters': distanceMeters,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (includesStairs != null) 'includes_stairs': includesStairs,
      if (requiresElevator != null) 'requires_elevator': requiresElevator,
      if (requiresEscalator != null) 'requires_escalator': requiresEscalator,
      if (slopeLevel != null) 'slope_level': slopeLevel,
      if (widthLevel != null) 'width_level': widthLevel,
      if (reliabilityScore != null) 'reliability_score': reliabilityScore,
      if (accessibilityStatus != null)
        'accessibility_status': accessibilityStatus,
      if (sourceId != null) 'source_id': sourceId,
      if (sourceSnapshotId != null) 'source_snapshot_id': sourceSnapshotId,
      if (providerRecordHash != null)
        'provider_record_hash': providerRecordHash,
      if (provenanceKind != null) 'provenance_kind': provenanceKind,
      if (verificationStatus != null) 'verification_status': verificationStatus,
      if (facilityId != null) 'facility_id': facilityId,
      if (lastVerifiedAt != null) 'last_verified_at': lastVerifiedAt,
      if (evidenceHash != null) 'evidence_hash': evidenceHash,
      if (instruction != null) 'instruction': instruction,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InternalRouteEdgesCompanion copyWith({
    Value<String>? id,
    Value<String>? fromNodeId,
    Value<String>? toNodeId,
    Value<String>? edgeType,
    Value<int>? distanceMeters,
    Value<int>? durationSeconds,
    Value<bool>? includesStairs,
    Value<bool>? requiresElevator,
    Value<bool>? requiresEscalator,
    Value<int>? slopeLevel,
    Value<int>? widthLevel,
    Value<int>? reliabilityScore,
    Value<String>? accessibilityStatus,
    Value<String>? sourceId,
    Value<String>? sourceSnapshotId,
    Value<String>? providerRecordHash,
    Value<String>? provenanceKind,
    Value<String>? verificationStatus,
    Value<String?>? facilityId,
    Value<DateTime?>? lastVerifiedAt,
    Value<String>? evidenceHash,
    Value<String>? instruction,
    Value<int>? rowid,
  }) {
    return InternalRouteEdgesCompanion(
      id: id ?? this.id,
      fromNodeId: fromNodeId ?? this.fromNodeId,
      toNodeId: toNodeId ?? this.toNodeId,
      edgeType: edgeType ?? this.edgeType,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      includesStairs: includesStairs ?? this.includesStairs,
      requiresElevator: requiresElevator ?? this.requiresElevator,
      requiresEscalator: requiresEscalator ?? this.requiresEscalator,
      slopeLevel: slopeLevel ?? this.slopeLevel,
      widthLevel: widthLevel ?? this.widthLevel,
      reliabilityScore: reliabilityScore ?? this.reliabilityScore,
      accessibilityStatus: accessibilityStatus ?? this.accessibilityStatus,
      sourceId: sourceId ?? this.sourceId,
      sourceSnapshotId: sourceSnapshotId ?? this.sourceSnapshotId,
      providerRecordHash: providerRecordHash ?? this.providerRecordHash,
      provenanceKind: provenanceKind ?? this.provenanceKind,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      facilityId: facilityId ?? this.facilityId,
      lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
      evidenceHash: evidenceHash ?? this.evidenceHash,
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
    if (edgeType.present) {
      map['edge_type'] = Variable<String>(edgeType.value);
    }
    if (distanceMeters.present) {
      map['distance_meters'] = Variable<int>(distanceMeters.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (includesStairs.present) {
      map['includes_stairs'] = Variable<bool>(includesStairs.value);
    }
    if (requiresElevator.present) {
      map['requires_elevator'] = Variable<bool>(requiresElevator.value);
    }
    if (requiresEscalator.present) {
      map['requires_escalator'] = Variable<bool>(requiresEscalator.value);
    }
    if (slopeLevel.present) {
      map['slope_level'] = Variable<int>(slopeLevel.value);
    }
    if (widthLevel.present) {
      map['width_level'] = Variable<int>(widthLevel.value);
    }
    if (reliabilityScore.present) {
      map['reliability_score'] = Variable<int>(reliabilityScore.value);
    }
    if (accessibilityStatus.present) {
      map['accessibility_status'] = Variable<String>(accessibilityStatus.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (sourceSnapshotId.present) {
      map['source_snapshot_id'] = Variable<String>(sourceSnapshotId.value);
    }
    if (providerRecordHash.present) {
      map['provider_record_hash'] = Variable<String>(providerRecordHash.value);
    }
    if (provenanceKind.present) {
      map['provenance_kind'] = Variable<String>(provenanceKind.value);
    }
    if (verificationStatus.present) {
      map['verification_status'] = Variable<String>(verificationStatus.value);
    }
    if (facilityId.present) {
      map['facility_id'] = Variable<String>(facilityId.value);
    }
    if (lastVerifiedAt.present) {
      map['last_verified_at'] = Variable<DateTime>(lastVerifiedAt.value);
    }
    if (evidenceHash.present) {
      map['evidence_hash'] = Variable<String>(evidenceHash.value);
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
          ..write('edgeType: $edgeType, ')
          ..write('distanceMeters: $distanceMeters, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('includesStairs: $includesStairs, ')
          ..write('requiresElevator: $requiresElevator, ')
          ..write('requiresEscalator: $requiresEscalator, ')
          ..write('slopeLevel: $slopeLevel, ')
          ..write('widthLevel: $widthLevel, ')
          ..write('reliabilityScore: $reliabilityScore, ')
          ..write('accessibilityStatus: $accessibilityStatus, ')
          ..write('sourceId: $sourceId, ')
          ..write('sourceSnapshotId: $sourceSnapshotId, ')
          ..write('providerRecordHash: $providerRecordHash, ')
          ..write('provenanceKind: $provenanceKind, ')
          ..write('verificationStatus: $verificationStatus, ')
          ..write('facilityId: $facilityId, ')
          ..write('lastVerifiedAt: $lastVerifiedAt, ')
          ..write('evidenceHash: $evidenceHash, ')
          ..write('instruction: $instruction, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StationPathwayNodesTable extends StationPathwayNodes
    with TableInfo<$StationPathwayNodesTable, StationPathwayNode> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StationPathwayNodesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _lineIdMeta = const VerificationMeta('lineId');
  @override
  late final GeneratedColumn<String> lineId = GeneratedColumn<String>(
    'line_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _levelMeta = const VerificationMeta('level');
  @override
  late final GeneratedColumn<String> level = GeneratedColumn<String>(
    'level',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _legacyInternalRouteNodeIdMeta =
      const VerificationMeta('legacyInternalRouteNodeId');
  @override
  late final GeneratedColumn<String> legacyInternalRouteNodeId =
      GeneratedColumn<String>(
        'legacy_internal_route_node_id',
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
    lineId,
    nodeType,
    label,
    level,
    legacyInternalRouteNodeId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'station_pathway_nodes';
  @override
  VerificationContext validateIntegrity(
    Insertable<StationPathwayNode> instance, {
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
    if (data.containsKey('line_id')) {
      context.handle(
        _lineIdMeta,
        lineId.isAcceptableOrUnknown(data['line_id']!, _lineIdMeta),
      );
    }
    if (data.containsKey('node_type')) {
      context.handle(
        _nodeTypeMeta,
        nodeType.isAcceptableOrUnknown(data['node_type']!, _nodeTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_nodeTypeMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('level')) {
      context.handle(
        _levelMeta,
        level.isAcceptableOrUnknown(data['level']!, _levelMeta),
      );
    }
    if (data.containsKey('legacy_internal_route_node_id')) {
      context.handle(
        _legacyInternalRouteNodeIdMeta,
        legacyInternalRouteNodeId.isAcceptableOrUnknown(
          data['legacy_internal_route_node_id']!,
          _legacyInternalRouteNodeIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StationPathwayNode map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StationPathwayNode(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      stationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}station_id'],
      )!,
      lineId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}line_id'],
      ),
      nodeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}node_type'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      level: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}level'],
      )!,
      legacyInternalRouteNodeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}legacy_internal_route_node_id'],
      )!,
    );
  }

  @override
  $StationPathwayNodesTable createAlias(String alias) {
    return $StationPathwayNodesTable(attachedDatabase, alias);
  }
}

class StationPathwayNode extends DataClass
    implements Insertable<StationPathwayNode> {
  final String id;
  final String stationId;
  final String? lineId;
  final String nodeType;
  final String label;
  final String level;
  final String legacyInternalRouteNodeId;
  const StationPathwayNode({
    required this.id,
    required this.stationId,
    this.lineId,
    required this.nodeType,
    required this.label,
    required this.level,
    required this.legacyInternalRouteNodeId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['station_id'] = Variable<String>(stationId);
    if (!nullToAbsent || lineId != null) {
      map['line_id'] = Variable<String>(lineId);
    }
    map['node_type'] = Variable<String>(nodeType);
    map['label'] = Variable<String>(label);
    map['level'] = Variable<String>(level);
    map['legacy_internal_route_node_id'] = Variable<String>(
      legacyInternalRouteNodeId,
    );
    return map;
  }

  StationPathwayNodesCompanion toCompanion(bool nullToAbsent) {
    return StationPathwayNodesCompanion(
      id: Value(id),
      stationId: Value(stationId),
      lineId: lineId == null && nullToAbsent
          ? const Value.absent()
          : Value(lineId),
      nodeType: Value(nodeType),
      label: Value(label),
      level: Value(level),
      legacyInternalRouteNodeId: Value(legacyInternalRouteNodeId),
    );
  }

  factory StationPathwayNode.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StationPathwayNode(
      id: serializer.fromJson<String>(json['id']),
      stationId: serializer.fromJson<String>(json['stationId']),
      lineId: serializer.fromJson<String?>(json['lineId']),
      nodeType: serializer.fromJson<String>(json['nodeType']),
      label: serializer.fromJson<String>(json['label']),
      level: serializer.fromJson<String>(json['level']),
      legacyInternalRouteNodeId: serializer.fromJson<String>(
        json['legacyInternalRouteNodeId'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'stationId': serializer.toJson<String>(stationId),
      'lineId': serializer.toJson<String?>(lineId),
      'nodeType': serializer.toJson<String>(nodeType),
      'label': serializer.toJson<String>(label),
      'level': serializer.toJson<String>(level),
      'legacyInternalRouteNodeId': serializer.toJson<String>(
        legacyInternalRouteNodeId,
      ),
    };
  }

  StationPathwayNode copyWith({
    String? id,
    String? stationId,
    Value<String?> lineId = const Value.absent(),
    String? nodeType,
    String? label,
    String? level,
    String? legacyInternalRouteNodeId,
  }) => StationPathwayNode(
    id: id ?? this.id,
    stationId: stationId ?? this.stationId,
    lineId: lineId.present ? lineId.value : this.lineId,
    nodeType: nodeType ?? this.nodeType,
    label: label ?? this.label,
    level: level ?? this.level,
    legacyInternalRouteNodeId:
        legacyInternalRouteNodeId ?? this.legacyInternalRouteNodeId,
  );
  StationPathwayNode copyWithCompanion(StationPathwayNodesCompanion data) {
    return StationPathwayNode(
      id: data.id.present ? data.id.value : this.id,
      stationId: data.stationId.present ? data.stationId.value : this.stationId,
      lineId: data.lineId.present ? data.lineId.value : this.lineId,
      nodeType: data.nodeType.present ? data.nodeType.value : this.nodeType,
      label: data.label.present ? data.label.value : this.label,
      level: data.level.present ? data.level.value : this.level,
      legacyInternalRouteNodeId: data.legacyInternalRouteNodeId.present
          ? data.legacyInternalRouteNodeId.value
          : this.legacyInternalRouteNodeId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StationPathwayNode(')
          ..write('id: $id, ')
          ..write('stationId: $stationId, ')
          ..write('lineId: $lineId, ')
          ..write('nodeType: $nodeType, ')
          ..write('label: $label, ')
          ..write('level: $level, ')
          ..write('legacyInternalRouteNodeId: $legacyInternalRouteNodeId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    stationId,
    lineId,
    nodeType,
    label,
    level,
    legacyInternalRouteNodeId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StationPathwayNode &&
          other.id == this.id &&
          other.stationId == this.stationId &&
          other.lineId == this.lineId &&
          other.nodeType == this.nodeType &&
          other.label == this.label &&
          other.level == this.level &&
          other.legacyInternalRouteNodeId == this.legacyInternalRouteNodeId);
}

class StationPathwayNodesCompanion extends UpdateCompanion<StationPathwayNode> {
  final Value<String> id;
  final Value<String> stationId;
  final Value<String?> lineId;
  final Value<String> nodeType;
  final Value<String> label;
  final Value<String> level;
  final Value<String> legacyInternalRouteNodeId;
  final Value<int> rowid;
  const StationPathwayNodesCompanion({
    this.id = const Value.absent(),
    this.stationId = const Value.absent(),
    this.lineId = const Value.absent(),
    this.nodeType = const Value.absent(),
    this.label = const Value.absent(),
    this.level = const Value.absent(),
    this.legacyInternalRouteNodeId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StationPathwayNodesCompanion.insert({
    required String id,
    required String stationId,
    this.lineId = const Value.absent(),
    required String nodeType,
    required String label,
    this.level = const Value.absent(),
    this.legacyInternalRouteNodeId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       stationId = Value(stationId),
       nodeType = Value(nodeType),
       label = Value(label);
  static Insertable<StationPathwayNode> custom({
    Expression<String>? id,
    Expression<String>? stationId,
    Expression<String>? lineId,
    Expression<String>? nodeType,
    Expression<String>? label,
    Expression<String>? level,
    Expression<String>? legacyInternalRouteNodeId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (stationId != null) 'station_id': stationId,
      if (lineId != null) 'line_id': lineId,
      if (nodeType != null) 'node_type': nodeType,
      if (label != null) 'label': label,
      if (level != null) 'level': level,
      if (legacyInternalRouteNodeId != null)
        'legacy_internal_route_node_id': legacyInternalRouteNodeId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StationPathwayNodesCompanion copyWith({
    Value<String>? id,
    Value<String>? stationId,
    Value<String?>? lineId,
    Value<String>? nodeType,
    Value<String>? label,
    Value<String>? level,
    Value<String>? legacyInternalRouteNodeId,
    Value<int>? rowid,
  }) {
    return StationPathwayNodesCompanion(
      id: id ?? this.id,
      stationId: stationId ?? this.stationId,
      lineId: lineId ?? this.lineId,
      nodeType: nodeType ?? this.nodeType,
      label: label ?? this.label,
      level: level ?? this.level,
      legacyInternalRouteNodeId:
          legacyInternalRouteNodeId ?? this.legacyInternalRouteNodeId,
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
    if (lineId.present) {
      map['line_id'] = Variable<String>(lineId.value);
    }
    if (nodeType.present) {
      map['node_type'] = Variable<String>(nodeType.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (level.present) {
      map['level'] = Variable<String>(level.value);
    }
    if (legacyInternalRouteNodeId.present) {
      map['legacy_internal_route_node_id'] = Variable<String>(
        legacyInternalRouteNodeId.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StationPathwayNodesCompanion(')
          ..write('id: $id, ')
          ..write('stationId: $stationId, ')
          ..write('lineId: $lineId, ')
          ..write('nodeType: $nodeType, ')
          ..write('label: $label, ')
          ..write('level: $level, ')
          ..write('legacyInternalRouteNodeId: $legacyInternalRouteNodeId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StationPathwayEdgesTable extends StationPathwayEdges
    with TableInfo<$StationPathwayEdgesTable, StationPathwayEdge> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StationPathwayEdgesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _distanceMetersMeta = const VerificationMeta(
    'distanceMeters',
  );
  @override
  late final GeneratedColumn<int> distanceMeters = GeneratedColumn<int>(
    'distance_meters',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _bidirectionalMeta = const VerificationMeta(
    'bidirectional',
  );
  @override
  late final GeneratedColumn<bool> bidirectional = GeneratedColumn<bool>(
    'bidirectional',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("bidirectional" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
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
  static const VerificationMeta _requiresElevatorMeta = const VerificationMeta(
    'requiresElevator',
  );
  @override
  late final GeneratedColumn<bool> requiresElevator = GeneratedColumn<bool>(
    'requires_elevator',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("requires_elevator" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _requiresEscalatorMeta = const VerificationMeta(
    'requiresEscalator',
  );
  @override
  late final GeneratedColumn<bool> requiresEscalator = GeneratedColumn<bool>(
    'requires_escalator',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("requires_escalator" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _levelFromMeta = const VerificationMeta(
    'levelFrom',
  );
  @override
  late final GeneratedColumn<String> levelFrom = GeneratedColumn<String>(
    'level_from',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _levelToMeta = const VerificationMeta(
    'levelTo',
  );
  @override
  late final GeneratedColumn<String> levelTo = GeneratedColumn<String>(
    'level_to',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _requiresFacilityIdMeta =
      const VerificationMeta('requiresFacilityId');
  @override
  late final GeneratedColumn<String> requiresFacilityId =
      GeneratedColumn<String>(
        'requires_facility_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _minWidthCmMeta = const VerificationMeta(
    'minWidthCm',
  );
  @override
  late final GeneratedColumn<int> minWidthCm = GeneratedColumn<int>(
    'min_width_cm',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _slopePercentMeta = const VerificationMeta(
    'slopePercent',
  );
  @override
  late final GeneratedColumn<double> slopePercent = GeneratedColumn<double>(
    'slope_percent',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _verticalMetersMeta = const VerificationMeta(
    'verticalMeters',
  );
  @override
  late final GeneratedColumn<double> verticalMeters = GeneratedColumn<double>(
    'vertical_meters',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
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
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sourceSnapshotIdMeta = const VerificationMeta(
    'sourceSnapshotId',
  );
  @override
  late final GeneratedColumn<String> sourceSnapshotId = GeneratedColumn<String>(
    'source_snapshot_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _providerRecordHashMeta =
      const VerificationMeta('providerRecordHash');
  @override
  late final GeneratedColumn<String> providerRecordHash =
      GeneratedColumn<String>(
        'provider_record_hash',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant(''),
      );
  static const VerificationMeta _provenanceKindMeta = const VerificationMeta(
    'provenanceKind',
  );
  @override
  late final GeneratedColumn<String> provenanceKind = GeneratedColumn<String>(
    'provenance_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('UNKNOWN'),
  );
  static const VerificationMeta _verificationStatusMeta =
      const VerificationMeta('verificationStatus');
  @override
  late final GeneratedColumn<String> verificationStatus =
      GeneratedColumn<String>(
        'verification_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('UNKNOWN'),
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
  static const VerificationMeta _evidenceHashMeta = const VerificationMeta(
    'evidenceHash',
  );
  @override
  late final GeneratedColumn<String> evidenceHash = GeneratedColumn<String>(
    'evidence_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
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
  static const VerificationMeta _legacyInternalRouteEdgeIdMeta =
      const VerificationMeta('legacyInternalRouteEdgeId');
  @override
  late final GeneratedColumn<String> legacyInternalRouteEdgeId =
      GeneratedColumn<String>(
        'legacy_internal_route_edge_id',
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
    edgeType,
    durationSeconds,
    distanceMeters,
    bidirectional,
    includesStairs,
    requiresElevator,
    requiresEscalator,
    levelFrom,
    levelTo,
    requiresFacilityId,
    minWidthCm,
    slopePercent,
    verticalMeters,
    reliabilityScore,
    accessibilityStatus,
    sourceId,
    sourceSnapshotId,
    providerRecordHash,
    provenanceKind,
    verificationStatus,
    lastVerifiedAt,
    evidenceHash,
    instruction,
    legacyInternalRouteEdgeId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'station_pathway_edges';
  @override
  VerificationContext validateIntegrity(
    Insertable<StationPathwayEdge> instance, {
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
    if (data.containsKey('edge_type')) {
      context.handle(
        _edgeTypeMeta,
        edgeType.isAcceptableOrUnknown(data['edge_type']!, _edgeTypeMeta),
      );
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
    if (data.containsKey('distance_meters')) {
      context.handle(
        _distanceMetersMeta,
        distanceMeters.isAcceptableOrUnknown(
          data['distance_meters']!,
          _distanceMetersMeta,
        ),
      );
    }
    if (data.containsKey('bidirectional')) {
      context.handle(
        _bidirectionalMeta,
        bidirectional.isAcceptableOrUnknown(
          data['bidirectional']!,
          _bidirectionalMeta,
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
    if (data.containsKey('requires_elevator')) {
      context.handle(
        _requiresElevatorMeta,
        requiresElevator.isAcceptableOrUnknown(
          data['requires_elevator']!,
          _requiresElevatorMeta,
        ),
      );
    }
    if (data.containsKey('requires_escalator')) {
      context.handle(
        _requiresEscalatorMeta,
        requiresEscalator.isAcceptableOrUnknown(
          data['requires_escalator']!,
          _requiresEscalatorMeta,
        ),
      );
    }
    if (data.containsKey('level_from')) {
      context.handle(
        _levelFromMeta,
        levelFrom.isAcceptableOrUnknown(data['level_from']!, _levelFromMeta),
      );
    }
    if (data.containsKey('level_to')) {
      context.handle(
        _levelToMeta,
        levelTo.isAcceptableOrUnknown(data['level_to']!, _levelToMeta),
      );
    }
    if (data.containsKey('requires_facility_id')) {
      context.handle(
        _requiresFacilityIdMeta,
        requiresFacilityId.isAcceptableOrUnknown(
          data['requires_facility_id']!,
          _requiresFacilityIdMeta,
        ),
      );
    }
    if (data.containsKey('min_width_cm')) {
      context.handle(
        _minWidthCmMeta,
        minWidthCm.isAcceptableOrUnknown(
          data['min_width_cm']!,
          _minWidthCmMeta,
        ),
      );
    }
    if (data.containsKey('slope_percent')) {
      context.handle(
        _slopePercentMeta,
        slopePercent.isAcceptableOrUnknown(
          data['slope_percent']!,
          _slopePercentMeta,
        ),
      );
    }
    if (data.containsKey('vertical_meters')) {
      context.handle(
        _verticalMetersMeta,
        verticalMeters.isAcceptableOrUnknown(
          data['vertical_meters']!,
          _verticalMetersMeta,
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
    if (data.containsKey('accessibility_status')) {
      context.handle(
        _accessibilityStatusMeta,
        accessibilityStatus.isAcceptableOrUnknown(
          data['accessibility_status']!,
          _accessibilityStatusMeta,
        ),
      );
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    }
    if (data.containsKey('source_snapshot_id')) {
      context.handle(
        _sourceSnapshotIdMeta,
        sourceSnapshotId.isAcceptableOrUnknown(
          data['source_snapshot_id']!,
          _sourceSnapshotIdMeta,
        ),
      );
    }
    if (data.containsKey('provider_record_hash')) {
      context.handle(
        _providerRecordHashMeta,
        providerRecordHash.isAcceptableOrUnknown(
          data['provider_record_hash']!,
          _providerRecordHashMeta,
        ),
      );
    }
    if (data.containsKey('provenance_kind')) {
      context.handle(
        _provenanceKindMeta,
        provenanceKind.isAcceptableOrUnknown(
          data['provenance_kind']!,
          _provenanceKindMeta,
        ),
      );
    }
    if (data.containsKey('verification_status')) {
      context.handle(
        _verificationStatusMeta,
        verificationStatus.isAcceptableOrUnknown(
          data['verification_status']!,
          _verificationStatusMeta,
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
    if (data.containsKey('evidence_hash')) {
      context.handle(
        _evidenceHashMeta,
        evidenceHash.isAcceptableOrUnknown(
          data['evidence_hash']!,
          _evidenceHashMeta,
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
    if (data.containsKey('legacy_internal_route_edge_id')) {
      context.handle(
        _legacyInternalRouteEdgeIdMeta,
        legacyInternalRouteEdgeId.isAcceptableOrUnknown(
          data['legacy_internal_route_edge_id']!,
          _legacyInternalRouteEdgeIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StationPathwayEdge map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StationPathwayEdge(
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
      edgeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}edge_type'],
      )!,
      durationSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_seconds'],
      )!,
      distanceMeters: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}distance_meters'],
      )!,
      bidirectional: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}bidirectional'],
      )!,
      includesStairs: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}includes_stairs'],
      )!,
      requiresElevator: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}requires_elevator'],
      )!,
      requiresEscalator: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}requires_escalator'],
      )!,
      levelFrom: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}level_from'],
      )!,
      levelTo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}level_to'],
      )!,
      requiresFacilityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}requires_facility_id'],
      ),
      minWidthCm: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}min_width_cm'],
      ),
      slopePercent: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}slope_percent'],
      ),
      verticalMeters: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}vertical_meters'],
      ),
      reliabilityScore: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reliability_score'],
      )!,
      accessibilityStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}accessibility_status'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      sourceSnapshotId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_snapshot_id'],
      )!,
      providerRecordHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider_record_hash'],
      )!,
      provenanceKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provenance_kind'],
      )!,
      verificationStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}verification_status'],
      )!,
      lastVerifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_verified_at'],
      ),
      evidenceHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}evidence_hash'],
      )!,
      instruction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}instruction'],
      )!,
      legacyInternalRouteEdgeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}legacy_internal_route_edge_id'],
      )!,
    );
  }

  @override
  $StationPathwayEdgesTable createAlias(String alias) {
    return $StationPathwayEdgesTable(attachedDatabase, alias);
  }
}

class StationPathwayEdge extends DataClass
    implements Insertable<StationPathwayEdge> {
  final String id;
  final String fromNodeId;
  final String toNodeId;
  final String edgeType;
  final int durationSeconds;
  final int distanceMeters;
  final bool bidirectional;
  final bool includesStairs;
  final bool requiresElevator;
  final bool requiresEscalator;
  final String levelFrom;
  final String levelTo;
  final String? requiresFacilityId;
  final int? minWidthCm;
  final double? slopePercent;
  final double? verticalMeters;
  final int reliabilityScore;
  final String accessibilityStatus;
  final String sourceId;
  final String sourceSnapshotId;
  final String providerRecordHash;
  final String provenanceKind;
  final String verificationStatus;
  final DateTime? lastVerifiedAt;
  final String evidenceHash;
  final String instruction;
  final String legacyInternalRouteEdgeId;
  const StationPathwayEdge({
    required this.id,
    required this.fromNodeId,
    required this.toNodeId,
    required this.edgeType,
    required this.durationSeconds,
    required this.distanceMeters,
    required this.bidirectional,
    required this.includesStairs,
    required this.requiresElevator,
    required this.requiresEscalator,
    required this.levelFrom,
    required this.levelTo,
    this.requiresFacilityId,
    this.minWidthCm,
    this.slopePercent,
    this.verticalMeters,
    required this.reliabilityScore,
    required this.accessibilityStatus,
    required this.sourceId,
    required this.sourceSnapshotId,
    required this.providerRecordHash,
    required this.provenanceKind,
    required this.verificationStatus,
    this.lastVerifiedAt,
    required this.evidenceHash,
    required this.instruction,
    required this.legacyInternalRouteEdgeId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['from_node_id'] = Variable<String>(fromNodeId);
    map['to_node_id'] = Variable<String>(toNodeId);
    map['edge_type'] = Variable<String>(edgeType);
    map['duration_seconds'] = Variable<int>(durationSeconds);
    map['distance_meters'] = Variable<int>(distanceMeters);
    map['bidirectional'] = Variable<bool>(bidirectional);
    map['includes_stairs'] = Variable<bool>(includesStairs);
    map['requires_elevator'] = Variable<bool>(requiresElevator);
    map['requires_escalator'] = Variable<bool>(requiresEscalator);
    map['level_from'] = Variable<String>(levelFrom);
    map['level_to'] = Variable<String>(levelTo);
    if (!nullToAbsent || requiresFacilityId != null) {
      map['requires_facility_id'] = Variable<String>(requiresFacilityId);
    }
    if (!nullToAbsent || minWidthCm != null) {
      map['min_width_cm'] = Variable<int>(minWidthCm);
    }
    if (!nullToAbsent || slopePercent != null) {
      map['slope_percent'] = Variable<double>(slopePercent);
    }
    if (!nullToAbsent || verticalMeters != null) {
      map['vertical_meters'] = Variable<double>(verticalMeters);
    }
    map['reliability_score'] = Variable<int>(reliabilityScore);
    map['accessibility_status'] = Variable<String>(accessibilityStatus);
    map['source_id'] = Variable<String>(sourceId);
    map['source_snapshot_id'] = Variable<String>(sourceSnapshotId);
    map['provider_record_hash'] = Variable<String>(providerRecordHash);
    map['provenance_kind'] = Variable<String>(provenanceKind);
    map['verification_status'] = Variable<String>(verificationStatus);
    if (!nullToAbsent || lastVerifiedAt != null) {
      map['last_verified_at'] = Variable<DateTime>(lastVerifiedAt);
    }
    map['evidence_hash'] = Variable<String>(evidenceHash);
    map['instruction'] = Variable<String>(instruction);
    map['legacy_internal_route_edge_id'] = Variable<String>(
      legacyInternalRouteEdgeId,
    );
    return map;
  }

  StationPathwayEdgesCompanion toCompanion(bool nullToAbsent) {
    return StationPathwayEdgesCompanion(
      id: Value(id),
      fromNodeId: Value(fromNodeId),
      toNodeId: Value(toNodeId),
      edgeType: Value(edgeType),
      durationSeconds: Value(durationSeconds),
      distanceMeters: Value(distanceMeters),
      bidirectional: Value(bidirectional),
      includesStairs: Value(includesStairs),
      requiresElevator: Value(requiresElevator),
      requiresEscalator: Value(requiresEscalator),
      levelFrom: Value(levelFrom),
      levelTo: Value(levelTo),
      requiresFacilityId: requiresFacilityId == null && nullToAbsent
          ? const Value.absent()
          : Value(requiresFacilityId),
      minWidthCm: minWidthCm == null && nullToAbsent
          ? const Value.absent()
          : Value(minWidthCm),
      slopePercent: slopePercent == null && nullToAbsent
          ? const Value.absent()
          : Value(slopePercent),
      verticalMeters: verticalMeters == null && nullToAbsent
          ? const Value.absent()
          : Value(verticalMeters),
      reliabilityScore: Value(reliabilityScore),
      accessibilityStatus: Value(accessibilityStatus),
      sourceId: Value(sourceId),
      sourceSnapshotId: Value(sourceSnapshotId),
      providerRecordHash: Value(providerRecordHash),
      provenanceKind: Value(provenanceKind),
      verificationStatus: Value(verificationStatus),
      lastVerifiedAt: lastVerifiedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastVerifiedAt),
      evidenceHash: Value(evidenceHash),
      instruction: Value(instruction),
      legacyInternalRouteEdgeId: Value(legacyInternalRouteEdgeId),
    );
  }

  factory StationPathwayEdge.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StationPathwayEdge(
      id: serializer.fromJson<String>(json['id']),
      fromNodeId: serializer.fromJson<String>(json['fromNodeId']),
      toNodeId: serializer.fromJson<String>(json['toNodeId']),
      edgeType: serializer.fromJson<String>(json['edgeType']),
      durationSeconds: serializer.fromJson<int>(json['durationSeconds']),
      distanceMeters: serializer.fromJson<int>(json['distanceMeters']),
      bidirectional: serializer.fromJson<bool>(json['bidirectional']),
      includesStairs: serializer.fromJson<bool>(json['includesStairs']),
      requiresElevator: serializer.fromJson<bool>(json['requiresElevator']),
      requiresEscalator: serializer.fromJson<bool>(json['requiresEscalator']),
      levelFrom: serializer.fromJson<String>(json['levelFrom']),
      levelTo: serializer.fromJson<String>(json['levelTo']),
      requiresFacilityId: serializer.fromJson<String?>(
        json['requiresFacilityId'],
      ),
      minWidthCm: serializer.fromJson<int?>(json['minWidthCm']),
      slopePercent: serializer.fromJson<double?>(json['slopePercent']),
      verticalMeters: serializer.fromJson<double?>(json['verticalMeters']),
      reliabilityScore: serializer.fromJson<int>(json['reliabilityScore']),
      accessibilityStatus: serializer.fromJson<String>(
        json['accessibilityStatus'],
      ),
      sourceId: serializer.fromJson<String>(json['sourceId']),
      sourceSnapshotId: serializer.fromJson<String>(json['sourceSnapshotId']),
      providerRecordHash: serializer.fromJson<String>(
        json['providerRecordHash'],
      ),
      provenanceKind: serializer.fromJson<String>(json['provenanceKind']),
      verificationStatus: serializer.fromJson<String>(
        json['verificationStatus'],
      ),
      lastVerifiedAt: serializer.fromJson<DateTime?>(json['lastVerifiedAt']),
      evidenceHash: serializer.fromJson<String>(json['evidenceHash']),
      instruction: serializer.fromJson<String>(json['instruction']),
      legacyInternalRouteEdgeId: serializer.fromJson<String>(
        json['legacyInternalRouteEdgeId'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'fromNodeId': serializer.toJson<String>(fromNodeId),
      'toNodeId': serializer.toJson<String>(toNodeId),
      'edgeType': serializer.toJson<String>(edgeType),
      'durationSeconds': serializer.toJson<int>(durationSeconds),
      'distanceMeters': serializer.toJson<int>(distanceMeters),
      'bidirectional': serializer.toJson<bool>(bidirectional),
      'includesStairs': serializer.toJson<bool>(includesStairs),
      'requiresElevator': serializer.toJson<bool>(requiresElevator),
      'requiresEscalator': serializer.toJson<bool>(requiresEscalator),
      'levelFrom': serializer.toJson<String>(levelFrom),
      'levelTo': serializer.toJson<String>(levelTo),
      'requiresFacilityId': serializer.toJson<String?>(requiresFacilityId),
      'minWidthCm': serializer.toJson<int?>(minWidthCm),
      'slopePercent': serializer.toJson<double?>(slopePercent),
      'verticalMeters': serializer.toJson<double?>(verticalMeters),
      'reliabilityScore': serializer.toJson<int>(reliabilityScore),
      'accessibilityStatus': serializer.toJson<String>(accessibilityStatus),
      'sourceId': serializer.toJson<String>(sourceId),
      'sourceSnapshotId': serializer.toJson<String>(sourceSnapshotId),
      'providerRecordHash': serializer.toJson<String>(providerRecordHash),
      'provenanceKind': serializer.toJson<String>(provenanceKind),
      'verificationStatus': serializer.toJson<String>(verificationStatus),
      'lastVerifiedAt': serializer.toJson<DateTime?>(lastVerifiedAt),
      'evidenceHash': serializer.toJson<String>(evidenceHash),
      'instruction': serializer.toJson<String>(instruction),
      'legacyInternalRouteEdgeId': serializer.toJson<String>(
        legacyInternalRouteEdgeId,
      ),
    };
  }

  StationPathwayEdge copyWith({
    String? id,
    String? fromNodeId,
    String? toNodeId,
    String? edgeType,
    int? durationSeconds,
    int? distanceMeters,
    bool? bidirectional,
    bool? includesStairs,
    bool? requiresElevator,
    bool? requiresEscalator,
    String? levelFrom,
    String? levelTo,
    Value<String?> requiresFacilityId = const Value.absent(),
    Value<int?> minWidthCm = const Value.absent(),
    Value<double?> slopePercent = const Value.absent(),
    Value<double?> verticalMeters = const Value.absent(),
    int? reliabilityScore,
    String? accessibilityStatus,
    String? sourceId,
    String? sourceSnapshotId,
    String? providerRecordHash,
    String? provenanceKind,
    String? verificationStatus,
    Value<DateTime?> lastVerifiedAt = const Value.absent(),
    String? evidenceHash,
    String? instruction,
    String? legacyInternalRouteEdgeId,
  }) => StationPathwayEdge(
    id: id ?? this.id,
    fromNodeId: fromNodeId ?? this.fromNodeId,
    toNodeId: toNodeId ?? this.toNodeId,
    edgeType: edgeType ?? this.edgeType,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    distanceMeters: distanceMeters ?? this.distanceMeters,
    bidirectional: bidirectional ?? this.bidirectional,
    includesStairs: includesStairs ?? this.includesStairs,
    requiresElevator: requiresElevator ?? this.requiresElevator,
    requiresEscalator: requiresEscalator ?? this.requiresEscalator,
    levelFrom: levelFrom ?? this.levelFrom,
    levelTo: levelTo ?? this.levelTo,
    requiresFacilityId: requiresFacilityId.present
        ? requiresFacilityId.value
        : this.requiresFacilityId,
    minWidthCm: minWidthCm.present ? minWidthCm.value : this.minWidthCm,
    slopePercent: slopePercent.present ? slopePercent.value : this.slopePercent,
    verticalMeters: verticalMeters.present
        ? verticalMeters.value
        : this.verticalMeters,
    reliabilityScore: reliabilityScore ?? this.reliabilityScore,
    accessibilityStatus: accessibilityStatus ?? this.accessibilityStatus,
    sourceId: sourceId ?? this.sourceId,
    sourceSnapshotId: sourceSnapshotId ?? this.sourceSnapshotId,
    providerRecordHash: providerRecordHash ?? this.providerRecordHash,
    provenanceKind: provenanceKind ?? this.provenanceKind,
    verificationStatus: verificationStatus ?? this.verificationStatus,
    lastVerifiedAt: lastVerifiedAt.present
        ? lastVerifiedAt.value
        : this.lastVerifiedAt,
    evidenceHash: evidenceHash ?? this.evidenceHash,
    instruction: instruction ?? this.instruction,
    legacyInternalRouteEdgeId:
        legacyInternalRouteEdgeId ?? this.legacyInternalRouteEdgeId,
  );
  StationPathwayEdge copyWithCompanion(StationPathwayEdgesCompanion data) {
    return StationPathwayEdge(
      id: data.id.present ? data.id.value : this.id,
      fromNodeId: data.fromNodeId.present
          ? data.fromNodeId.value
          : this.fromNodeId,
      toNodeId: data.toNodeId.present ? data.toNodeId.value : this.toNodeId,
      edgeType: data.edgeType.present ? data.edgeType.value : this.edgeType,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
      distanceMeters: data.distanceMeters.present
          ? data.distanceMeters.value
          : this.distanceMeters,
      bidirectional: data.bidirectional.present
          ? data.bidirectional.value
          : this.bidirectional,
      includesStairs: data.includesStairs.present
          ? data.includesStairs.value
          : this.includesStairs,
      requiresElevator: data.requiresElevator.present
          ? data.requiresElevator.value
          : this.requiresElevator,
      requiresEscalator: data.requiresEscalator.present
          ? data.requiresEscalator.value
          : this.requiresEscalator,
      levelFrom: data.levelFrom.present ? data.levelFrom.value : this.levelFrom,
      levelTo: data.levelTo.present ? data.levelTo.value : this.levelTo,
      requiresFacilityId: data.requiresFacilityId.present
          ? data.requiresFacilityId.value
          : this.requiresFacilityId,
      minWidthCm: data.minWidthCm.present
          ? data.minWidthCm.value
          : this.minWidthCm,
      slopePercent: data.slopePercent.present
          ? data.slopePercent.value
          : this.slopePercent,
      verticalMeters: data.verticalMeters.present
          ? data.verticalMeters.value
          : this.verticalMeters,
      reliabilityScore: data.reliabilityScore.present
          ? data.reliabilityScore.value
          : this.reliabilityScore,
      accessibilityStatus: data.accessibilityStatus.present
          ? data.accessibilityStatus.value
          : this.accessibilityStatus,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      sourceSnapshotId: data.sourceSnapshotId.present
          ? data.sourceSnapshotId.value
          : this.sourceSnapshotId,
      providerRecordHash: data.providerRecordHash.present
          ? data.providerRecordHash.value
          : this.providerRecordHash,
      provenanceKind: data.provenanceKind.present
          ? data.provenanceKind.value
          : this.provenanceKind,
      verificationStatus: data.verificationStatus.present
          ? data.verificationStatus.value
          : this.verificationStatus,
      lastVerifiedAt: data.lastVerifiedAt.present
          ? data.lastVerifiedAt.value
          : this.lastVerifiedAt,
      evidenceHash: data.evidenceHash.present
          ? data.evidenceHash.value
          : this.evidenceHash,
      instruction: data.instruction.present
          ? data.instruction.value
          : this.instruction,
      legacyInternalRouteEdgeId: data.legacyInternalRouteEdgeId.present
          ? data.legacyInternalRouteEdgeId.value
          : this.legacyInternalRouteEdgeId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StationPathwayEdge(')
          ..write('id: $id, ')
          ..write('fromNodeId: $fromNodeId, ')
          ..write('toNodeId: $toNodeId, ')
          ..write('edgeType: $edgeType, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('distanceMeters: $distanceMeters, ')
          ..write('bidirectional: $bidirectional, ')
          ..write('includesStairs: $includesStairs, ')
          ..write('requiresElevator: $requiresElevator, ')
          ..write('requiresEscalator: $requiresEscalator, ')
          ..write('levelFrom: $levelFrom, ')
          ..write('levelTo: $levelTo, ')
          ..write('requiresFacilityId: $requiresFacilityId, ')
          ..write('minWidthCm: $minWidthCm, ')
          ..write('slopePercent: $slopePercent, ')
          ..write('verticalMeters: $verticalMeters, ')
          ..write('reliabilityScore: $reliabilityScore, ')
          ..write('accessibilityStatus: $accessibilityStatus, ')
          ..write('sourceId: $sourceId, ')
          ..write('sourceSnapshotId: $sourceSnapshotId, ')
          ..write('providerRecordHash: $providerRecordHash, ')
          ..write('provenanceKind: $provenanceKind, ')
          ..write('verificationStatus: $verificationStatus, ')
          ..write('lastVerifiedAt: $lastVerifiedAt, ')
          ..write('evidenceHash: $evidenceHash, ')
          ..write('instruction: $instruction, ')
          ..write('legacyInternalRouteEdgeId: $legacyInternalRouteEdgeId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    fromNodeId,
    toNodeId,
    edgeType,
    durationSeconds,
    distanceMeters,
    bidirectional,
    includesStairs,
    requiresElevator,
    requiresEscalator,
    levelFrom,
    levelTo,
    requiresFacilityId,
    minWidthCm,
    slopePercent,
    verticalMeters,
    reliabilityScore,
    accessibilityStatus,
    sourceId,
    sourceSnapshotId,
    providerRecordHash,
    provenanceKind,
    verificationStatus,
    lastVerifiedAt,
    evidenceHash,
    instruction,
    legacyInternalRouteEdgeId,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StationPathwayEdge &&
          other.id == this.id &&
          other.fromNodeId == this.fromNodeId &&
          other.toNodeId == this.toNodeId &&
          other.edgeType == this.edgeType &&
          other.durationSeconds == this.durationSeconds &&
          other.distanceMeters == this.distanceMeters &&
          other.bidirectional == this.bidirectional &&
          other.includesStairs == this.includesStairs &&
          other.requiresElevator == this.requiresElevator &&
          other.requiresEscalator == this.requiresEscalator &&
          other.levelFrom == this.levelFrom &&
          other.levelTo == this.levelTo &&
          other.requiresFacilityId == this.requiresFacilityId &&
          other.minWidthCm == this.minWidthCm &&
          other.slopePercent == this.slopePercent &&
          other.verticalMeters == this.verticalMeters &&
          other.reliabilityScore == this.reliabilityScore &&
          other.accessibilityStatus == this.accessibilityStatus &&
          other.sourceId == this.sourceId &&
          other.sourceSnapshotId == this.sourceSnapshotId &&
          other.providerRecordHash == this.providerRecordHash &&
          other.provenanceKind == this.provenanceKind &&
          other.verificationStatus == this.verificationStatus &&
          other.lastVerifiedAt == this.lastVerifiedAt &&
          other.evidenceHash == this.evidenceHash &&
          other.instruction == this.instruction &&
          other.legacyInternalRouteEdgeId == this.legacyInternalRouteEdgeId);
}

class StationPathwayEdgesCompanion extends UpdateCompanion<StationPathwayEdge> {
  final Value<String> id;
  final Value<String> fromNodeId;
  final Value<String> toNodeId;
  final Value<String> edgeType;
  final Value<int> durationSeconds;
  final Value<int> distanceMeters;
  final Value<bool> bidirectional;
  final Value<bool> includesStairs;
  final Value<bool> requiresElevator;
  final Value<bool> requiresEscalator;
  final Value<String> levelFrom;
  final Value<String> levelTo;
  final Value<String?> requiresFacilityId;
  final Value<int?> minWidthCm;
  final Value<double?> slopePercent;
  final Value<double?> verticalMeters;
  final Value<int> reliabilityScore;
  final Value<String> accessibilityStatus;
  final Value<String> sourceId;
  final Value<String> sourceSnapshotId;
  final Value<String> providerRecordHash;
  final Value<String> provenanceKind;
  final Value<String> verificationStatus;
  final Value<DateTime?> lastVerifiedAt;
  final Value<String> evidenceHash;
  final Value<String> instruction;
  final Value<String> legacyInternalRouteEdgeId;
  final Value<int> rowid;
  const StationPathwayEdgesCompanion({
    this.id = const Value.absent(),
    this.fromNodeId = const Value.absent(),
    this.toNodeId = const Value.absent(),
    this.edgeType = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.distanceMeters = const Value.absent(),
    this.bidirectional = const Value.absent(),
    this.includesStairs = const Value.absent(),
    this.requiresElevator = const Value.absent(),
    this.requiresEscalator = const Value.absent(),
    this.levelFrom = const Value.absent(),
    this.levelTo = const Value.absent(),
    this.requiresFacilityId = const Value.absent(),
    this.minWidthCm = const Value.absent(),
    this.slopePercent = const Value.absent(),
    this.verticalMeters = const Value.absent(),
    this.reliabilityScore = const Value.absent(),
    this.accessibilityStatus = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.sourceSnapshotId = const Value.absent(),
    this.providerRecordHash = const Value.absent(),
    this.provenanceKind = const Value.absent(),
    this.verificationStatus = const Value.absent(),
    this.lastVerifiedAt = const Value.absent(),
    this.evidenceHash = const Value.absent(),
    this.instruction = const Value.absent(),
    this.legacyInternalRouteEdgeId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StationPathwayEdgesCompanion.insert({
    required String id,
    required String fromNodeId,
    required String toNodeId,
    this.edgeType = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.distanceMeters = const Value.absent(),
    this.bidirectional = const Value.absent(),
    this.includesStairs = const Value.absent(),
    this.requiresElevator = const Value.absent(),
    this.requiresEscalator = const Value.absent(),
    this.levelFrom = const Value.absent(),
    this.levelTo = const Value.absent(),
    this.requiresFacilityId = const Value.absent(),
    this.minWidthCm = const Value.absent(),
    this.slopePercent = const Value.absent(),
    this.verticalMeters = const Value.absent(),
    this.reliabilityScore = const Value.absent(),
    this.accessibilityStatus = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.sourceSnapshotId = const Value.absent(),
    this.providerRecordHash = const Value.absent(),
    this.provenanceKind = const Value.absent(),
    this.verificationStatus = const Value.absent(),
    this.lastVerifiedAt = const Value.absent(),
    this.evidenceHash = const Value.absent(),
    this.instruction = const Value.absent(),
    this.legacyInternalRouteEdgeId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       fromNodeId = Value(fromNodeId),
       toNodeId = Value(toNodeId);
  static Insertable<StationPathwayEdge> custom({
    Expression<String>? id,
    Expression<String>? fromNodeId,
    Expression<String>? toNodeId,
    Expression<String>? edgeType,
    Expression<int>? durationSeconds,
    Expression<int>? distanceMeters,
    Expression<bool>? bidirectional,
    Expression<bool>? includesStairs,
    Expression<bool>? requiresElevator,
    Expression<bool>? requiresEscalator,
    Expression<String>? levelFrom,
    Expression<String>? levelTo,
    Expression<String>? requiresFacilityId,
    Expression<int>? minWidthCm,
    Expression<double>? slopePercent,
    Expression<double>? verticalMeters,
    Expression<int>? reliabilityScore,
    Expression<String>? accessibilityStatus,
    Expression<String>? sourceId,
    Expression<String>? sourceSnapshotId,
    Expression<String>? providerRecordHash,
    Expression<String>? provenanceKind,
    Expression<String>? verificationStatus,
    Expression<DateTime>? lastVerifiedAt,
    Expression<String>? evidenceHash,
    Expression<String>? instruction,
    Expression<String>? legacyInternalRouteEdgeId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (fromNodeId != null) 'from_node_id': fromNodeId,
      if (toNodeId != null) 'to_node_id': toNodeId,
      if (edgeType != null) 'edge_type': edgeType,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (distanceMeters != null) 'distance_meters': distanceMeters,
      if (bidirectional != null) 'bidirectional': bidirectional,
      if (includesStairs != null) 'includes_stairs': includesStairs,
      if (requiresElevator != null) 'requires_elevator': requiresElevator,
      if (requiresEscalator != null) 'requires_escalator': requiresEscalator,
      if (levelFrom != null) 'level_from': levelFrom,
      if (levelTo != null) 'level_to': levelTo,
      if (requiresFacilityId != null)
        'requires_facility_id': requiresFacilityId,
      if (minWidthCm != null) 'min_width_cm': minWidthCm,
      if (slopePercent != null) 'slope_percent': slopePercent,
      if (verticalMeters != null) 'vertical_meters': verticalMeters,
      if (reliabilityScore != null) 'reliability_score': reliabilityScore,
      if (accessibilityStatus != null)
        'accessibility_status': accessibilityStatus,
      if (sourceId != null) 'source_id': sourceId,
      if (sourceSnapshotId != null) 'source_snapshot_id': sourceSnapshotId,
      if (providerRecordHash != null)
        'provider_record_hash': providerRecordHash,
      if (provenanceKind != null) 'provenance_kind': provenanceKind,
      if (verificationStatus != null) 'verification_status': verificationStatus,
      if (lastVerifiedAt != null) 'last_verified_at': lastVerifiedAt,
      if (evidenceHash != null) 'evidence_hash': evidenceHash,
      if (instruction != null) 'instruction': instruction,
      if (legacyInternalRouteEdgeId != null)
        'legacy_internal_route_edge_id': legacyInternalRouteEdgeId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StationPathwayEdgesCompanion copyWith({
    Value<String>? id,
    Value<String>? fromNodeId,
    Value<String>? toNodeId,
    Value<String>? edgeType,
    Value<int>? durationSeconds,
    Value<int>? distanceMeters,
    Value<bool>? bidirectional,
    Value<bool>? includesStairs,
    Value<bool>? requiresElevator,
    Value<bool>? requiresEscalator,
    Value<String>? levelFrom,
    Value<String>? levelTo,
    Value<String?>? requiresFacilityId,
    Value<int?>? minWidthCm,
    Value<double?>? slopePercent,
    Value<double?>? verticalMeters,
    Value<int>? reliabilityScore,
    Value<String>? accessibilityStatus,
    Value<String>? sourceId,
    Value<String>? sourceSnapshotId,
    Value<String>? providerRecordHash,
    Value<String>? provenanceKind,
    Value<String>? verificationStatus,
    Value<DateTime?>? lastVerifiedAt,
    Value<String>? evidenceHash,
    Value<String>? instruction,
    Value<String>? legacyInternalRouteEdgeId,
    Value<int>? rowid,
  }) {
    return StationPathwayEdgesCompanion(
      id: id ?? this.id,
      fromNodeId: fromNodeId ?? this.fromNodeId,
      toNodeId: toNodeId ?? this.toNodeId,
      edgeType: edgeType ?? this.edgeType,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      bidirectional: bidirectional ?? this.bidirectional,
      includesStairs: includesStairs ?? this.includesStairs,
      requiresElevator: requiresElevator ?? this.requiresElevator,
      requiresEscalator: requiresEscalator ?? this.requiresEscalator,
      levelFrom: levelFrom ?? this.levelFrom,
      levelTo: levelTo ?? this.levelTo,
      requiresFacilityId: requiresFacilityId ?? this.requiresFacilityId,
      minWidthCm: minWidthCm ?? this.minWidthCm,
      slopePercent: slopePercent ?? this.slopePercent,
      verticalMeters: verticalMeters ?? this.verticalMeters,
      reliabilityScore: reliabilityScore ?? this.reliabilityScore,
      accessibilityStatus: accessibilityStatus ?? this.accessibilityStatus,
      sourceId: sourceId ?? this.sourceId,
      sourceSnapshotId: sourceSnapshotId ?? this.sourceSnapshotId,
      providerRecordHash: providerRecordHash ?? this.providerRecordHash,
      provenanceKind: provenanceKind ?? this.provenanceKind,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
      evidenceHash: evidenceHash ?? this.evidenceHash,
      instruction: instruction ?? this.instruction,
      legacyInternalRouteEdgeId:
          legacyInternalRouteEdgeId ?? this.legacyInternalRouteEdgeId,
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
    if (edgeType.present) {
      map['edge_type'] = Variable<String>(edgeType.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (distanceMeters.present) {
      map['distance_meters'] = Variable<int>(distanceMeters.value);
    }
    if (bidirectional.present) {
      map['bidirectional'] = Variable<bool>(bidirectional.value);
    }
    if (includesStairs.present) {
      map['includes_stairs'] = Variable<bool>(includesStairs.value);
    }
    if (requiresElevator.present) {
      map['requires_elevator'] = Variable<bool>(requiresElevator.value);
    }
    if (requiresEscalator.present) {
      map['requires_escalator'] = Variable<bool>(requiresEscalator.value);
    }
    if (levelFrom.present) {
      map['level_from'] = Variable<String>(levelFrom.value);
    }
    if (levelTo.present) {
      map['level_to'] = Variable<String>(levelTo.value);
    }
    if (requiresFacilityId.present) {
      map['requires_facility_id'] = Variable<String>(requiresFacilityId.value);
    }
    if (minWidthCm.present) {
      map['min_width_cm'] = Variable<int>(minWidthCm.value);
    }
    if (slopePercent.present) {
      map['slope_percent'] = Variable<double>(slopePercent.value);
    }
    if (verticalMeters.present) {
      map['vertical_meters'] = Variable<double>(verticalMeters.value);
    }
    if (reliabilityScore.present) {
      map['reliability_score'] = Variable<int>(reliabilityScore.value);
    }
    if (accessibilityStatus.present) {
      map['accessibility_status'] = Variable<String>(accessibilityStatus.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (sourceSnapshotId.present) {
      map['source_snapshot_id'] = Variable<String>(sourceSnapshotId.value);
    }
    if (providerRecordHash.present) {
      map['provider_record_hash'] = Variable<String>(providerRecordHash.value);
    }
    if (provenanceKind.present) {
      map['provenance_kind'] = Variable<String>(provenanceKind.value);
    }
    if (verificationStatus.present) {
      map['verification_status'] = Variable<String>(verificationStatus.value);
    }
    if (lastVerifiedAt.present) {
      map['last_verified_at'] = Variable<DateTime>(lastVerifiedAt.value);
    }
    if (evidenceHash.present) {
      map['evidence_hash'] = Variable<String>(evidenceHash.value);
    }
    if (instruction.present) {
      map['instruction'] = Variable<String>(instruction.value);
    }
    if (legacyInternalRouteEdgeId.present) {
      map['legacy_internal_route_edge_id'] = Variable<String>(
        legacyInternalRouteEdgeId.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StationPathwayEdgesCompanion(')
          ..write('id: $id, ')
          ..write('fromNodeId: $fromNodeId, ')
          ..write('toNodeId: $toNodeId, ')
          ..write('edgeType: $edgeType, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('distanceMeters: $distanceMeters, ')
          ..write('bidirectional: $bidirectional, ')
          ..write('includesStairs: $includesStairs, ')
          ..write('requiresElevator: $requiresElevator, ')
          ..write('requiresEscalator: $requiresEscalator, ')
          ..write('levelFrom: $levelFrom, ')
          ..write('levelTo: $levelTo, ')
          ..write('requiresFacilityId: $requiresFacilityId, ')
          ..write('minWidthCm: $minWidthCm, ')
          ..write('slopePercent: $slopePercent, ')
          ..write('verticalMeters: $verticalMeters, ')
          ..write('reliabilityScore: $reliabilityScore, ')
          ..write('accessibilityStatus: $accessibilityStatus, ')
          ..write('sourceId: $sourceId, ')
          ..write('sourceSnapshotId: $sourceSnapshotId, ')
          ..write('providerRecordHash: $providerRecordHash, ')
          ..write('provenanceKind: $provenanceKind, ')
          ..write('verificationStatus: $verificationStatus, ')
          ..write('lastVerifiedAt: $lastVerifiedAt, ')
          ..write('evidenceHash: $evidenceHash, ')
          ..write('instruction: $instruction, ')
          ..write('legacyInternalRouteEdgeId: $legacyInternalRouteEdgeId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TransferRulesTable extends TransferRules
    with TableInfo<$TransferRulesTable, TransferRule> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransferRulesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fromStationIdMeta = const VerificationMeta(
    'fromStationId',
  );
  @override
  late final GeneratedColumn<String> fromStationId = GeneratedColumn<String>(
    'from_station_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fromLineIdMeta = const VerificationMeta(
    'fromLineId',
  );
  @override
  late final GeneratedColumn<String> fromLineId = GeneratedColumn<String>(
    'from_line_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _toStationIdMeta = const VerificationMeta(
    'toStationId',
  );
  @override
  late final GeneratedColumn<String> toStationId = GeneratedColumn<String>(
    'to_station_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _toLineIdMeta = const VerificationMeta(
    'toLineId',
  );
  @override
  late final GeneratedColumn<String> toLineId = GeneratedColumn<String>(
    'to_line_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _transferTypeMeta = const VerificationMeta(
    'transferType',
  );
  @override
  late final GeneratedColumn<String> transferType = GeneratedColumn<String>(
    'transfer_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('IN_STATION'),
  );
  static const VerificationMeta _minTransferSecondsMeta =
      const VerificationMeta('minTransferSeconds');
  @override
  late final GeneratedColumn<int> minTransferSeconds = GeneratedColumn<int>(
    'min_transfer_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _pathwayEdgeIdMeta = const VerificationMeta(
    'pathwayEdgeId',
  );
  @override
  late final GeneratedColumn<String> pathwayEdgeId = GeneratedColumn<String>(
    'pathway_edge_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _strictStepFreePathwayEdgeIdMeta =
      const VerificationMeta('strictStepFreePathwayEdgeId');
  @override
  late final GeneratedColumn<String> strictStepFreePathwayEdgeId =
      GeneratedColumn<String>(
        'strict_step_free_pathway_edge_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _verificationStatusMeta =
      const VerificationMeta('verificationStatus');
  @override
  late final GeneratedColumn<String> verificationStatus =
      GeneratedColumn<String>(
        'verification_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('UNKNOWN'),
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    fromStationId,
    fromLineId,
    toStationId,
    toLineId,
    transferType,
    minTransferSeconds,
    pathwayEdgeId,
    strictStepFreePathwayEdgeId,
    sourceId,
    verificationStatus,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transfer_rules';
  @override
  VerificationContext validateIntegrity(
    Insertable<TransferRule> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('from_station_id')) {
      context.handle(
        _fromStationIdMeta,
        fromStationId.isAcceptableOrUnknown(
          data['from_station_id']!,
          _fromStationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fromStationIdMeta);
    }
    if (data.containsKey('from_line_id')) {
      context.handle(
        _fromLineIdMeta,
        fromLineId.isAcceptableOrUnknown(
          data['from_line_id']!,
          _fromLineIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fromLineIdMeta);
    }
    if (data.containsKey('to_station_id')) {
      context.handle(
        _toStationIdMeta,
        toStationId.isAcceptableOrUnknown(
          data['to_station_id']!,
          _toStationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_toStationIdMeta);
    }
    if (data.containsKey('to_line_id')) {
      context.handle(
        _toLineIdMeta,
        toLineId.isAcceptableOrUnknown(data['to_line_id']!, _toLineIdMeta),
      );
    } else if (isInserting) {
      context.missing(_toLineIdMeta);
    }
    if (data.containsKey('transfer_type')) {
      context.handle(
        _transferTypeMeta,
        transferType.isAcceptableOrUnknown(
          data['transfer_type']!,
          _transferTypeMeta,
        ),
      );
    }
    if (data.containsKey('min_transfer_seconds')) {
      context.handle(
        _minTransferSecondsMeta,
        minTransferSeconds.isAcceptableOrUnknown(
          data['min_transfer_seconds']!,
          _minTransferSecondsMeta,
        ),
      );
    }
    if (data.containsKey('pathway_edge_id')) {
      context.handle(
        _pathwayEdgeIdMeta,
        pathwayEdgeId.isAcceptableOrUnknown(
          data['pathway_edge_id']!,
          _pathwayEdgeIdMeta,
        ),
      );
    }
    if (data.containsKey('strict_step_free_pathway_edge_id')) {
      context.handle(
        _strictStepFreePathwayEdgeIdMeta,
        strictStepFreePathwayEdgeId.isAcceptableOrUnknown(
          data['strict_step_free_pathway_edge_id']!,
          _strictStepFreePathwayEdgeIdMeta,
        ),
      );
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    }
    if (data.containsKey('verification_status')) {
      context.handle(
        _verificationStatusMeta,
        verificationStatus.isAcceptableOrUnknown(
          data['verification_status']!,
          _verificationStatusMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TransferRule map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TransferRule(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      fromStationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_station_id'],
      )!,
      fromLineId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_line_id'],
      )!,
      toStationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}to_station_id'],
      )!,
      toLineId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}to_line_id'],
      )!,
      transferType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transfer_type'],
      )!,
      minTransferSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}min_transfer_seconds'],
      )!,
      pathwayEdgeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pathway_edge_id'],
      ),
      strictStepFreePathwayEdgeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}strict_step_free_pathway_edge_id'],
      ),
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      verificationStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}verification_status'],
      )!,
    );
  }

  @override
  $TransferRulesTable createAlias(String alias) {
    return $TransferRulesTable(attachedDatabase, alias);
  }
}

class TransferRule extends DataClass implements Insertable<TransferRule> {
  final String id;
  final String fromStationId;
  final String fromLineId;
  final String toStationId;
  final String toLineId;
  final String transferType;
  final int minTransferSeconds;
  final String? pathwayEdgeId;
  final String? strictStepFreePathwayEdgeId;
  final String sourceId;
  final String verificationStatus;
  const TransferRule({
    required this.id,
    required this.fromStationId,
    required this.fromLineId,
    required this.toStationId,
    required this.toLineId,
    required this.transferType,
    required this.minTransferSeconds,
    this.pathwayEdgeId,
    this.strictStepFreePathwayEdgeId,
    required this.sourceId,
    required this.verificationStatus,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['from_station_id'] = Variable<String>(fromStationId);
    map['from_line_id'] = Variable<String>(fromLineId);
    map['to_station_id'] = Variable<String>(toStationId);
    map['to_line_id'] = Variable<String>(toLineId);
    map['transfer_type'] = Variable<String>(transferType);
    map['min_transfer_seconds'] = Variable<int>(minTransferSeconds);
    if (!nullToAbsent || pathwayEdgeId != null) {
      map['pathway_edge_id'] = Variable<String>(pathwayEdgeId);
    }
    if (!nullToAbsent || strictStepFreePathwayEdgeId != null) {
      map['strict_step_free_pathway_edge_id'] = Variable<String>(
        strictStepFreePathwayEdgeId,
      );
    }
    map['source_id'] = Variable<String>(sourceId);
    map['verification_status'] = Variable<String>(verificationStatus);
    return map;
  }

  TransferRulesCompanion toCompanion(bool nullToAbsent) {
    return TransferRulesCompanion(
      id: Value(id),
      fromStationId: Value(fromStationId),
      fromLineId: Value(fromLineId),
      toStationId: Value(toStationId),
      toLineId: Value(toLineId),
      transferType: Value(transferType),
      minTransferSeconds: Value(minTransferSeconds),
      pathwayEdgeId: pathwayEdgeId == null && nullToAbsent
          ? const Value.absent()
          : Value(pathwayEdgeId),
      strictStepFreePathwayEdgeId:
          strictStepFreePathwayEdgeId == null && nullToAbsent
          ? const Value.absent()
          : Value(strictStepFreePathwayEdgeId),
      sourceId: Value(sourceId),
      verificationStatus: Value(verificationStatus),
    );
  }

  factory TransferRule.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TransferRule(
      id: serializer.fromJson<String>(json['id']),
      fromStationId: serializer.fromJson<String>(json['fromStationId']),
      fromLineId: serializer.fromJson<String>(json['fromLineId']),
      toStationId: serializer.fromJson<String>(json['toStationId']),
      toLineId: serializer.fromJson<String>(json['toLineId']),
      transferType: serializer.fromJson<String>(json['transferType']),
      minTransferSeconds: serializer.fromJson<int>(json['minTransferSeconds']),
      pathwayEdgeId: serializer.fromJson<String?>(json['pathwayEdgeId']),
      strictStepFreePathwayEdgeId: serializer.fromJson<String?>(
        json['strictStepFreePathwayEdgeId'],
      ),
      sourceId: serializer.fromJson<String>(json['sourceId']),
      verificationStatus: serializer.fromJson<String>(
        json['verificationStatus'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'fromStationId': serializer.toJson<String>(fromStationId),
      'fromLineId': serializer.toJson<String>(fromLineId),
      'toStationId': serializer.toJson<String>(toStationId),
      'toLineId': serializer.toJson<String>(toLineId),
      'transferType': serializer.toJson<String>(transferType),
      'minTransferSeconds': serializer.toJson<int>(minTransferSeconds),
      'pathwayEdgeId': serializer.toJson<String?>(pathwayEdgeId),
      'strictStepFreePathwayEdgeId': serializer.toJson<String?>(
        strictStepFreePathwayEdgeId,
      ),
      'sourceId': serializer.toJson<String>(sourceId),
      'verificationStatus': serializer.toJson<String>(verificationStatus),
    };
  }

  TransferRule copyWith({
    String? id,
    String? fromStationId,
    String? fromLineId,
    String? toStationId,
    String? toLineId,
    String? transferType,
    int? minTransferSeconds,
    Value<String?> pathwayEdgeId = const Value.absent(),
    Value<String?> strictStepFreePathwayEdgeId = const Value.absent(),
    String? sourceId,
    String? verificationStatus,
  }) => TransferRule(
    id: id ?? this.id,
    fromStationId: fromStationId ?? this.fromStationId,
    fromLineId: fromLineId ?? this.fromLineId,
    toStationId: toStationId ?? this.toStationId,
    toLineId: toLineId ?? this.toLineId,
    transferType: transferType ?? this.transferType,
    minTransferSeconds: minTransferSeconds ?? this.minTransferSeconds,
    pathwayEdgeId: pathwayEdgeId.present
        ? pathwayEdgeId.value
        : this.pathwayEdgeId,
    strictStepFreePathwayEdgeId: strictStepFreePathwayEdgeId.present
        ? strictStepFreePathwayEdgeId.value
        : this.strictStepFreePathwayEdgeId,
    sourceId: sourceId ?? this.sourceId,
    verificationStatus: verificationStatus ?? this.verificationStatus,
  );
  TransferRule copyWithCompanion(TransferRulesCompanion data) {
    return TransferRule(
      id: data.id.present ? data.id.value : this.id,
      fromStationId: data.fromStationId.present
          ? data.fromStationId.value
          : this.fromStationId,
      fromLineId: data.fromLineId.present
          ? data.fromLineId.value
          : this.fromLineId,
      toStationId: data.toStationId.present
          ? data.toStationId.value
          : this.toStationId,
      toLineId: data.toLineId.present ? data.toLineId.value : this.toLineId,
      transferType: data.transferType.present
          ? data.transferType.value
          : this.transferType,
      minTransferSeconds: data.minTransferSeconds.present
          ? data.minTransferSeconds.value
          : this.minTransferSeconds,
      pathwayEdgeId: data.pathwayEdgeId.present
          ? data.pathwayEdgeId.value
          : this.pathwayEdgeId,
      strictStepFreePathwayEdgeId: data.strictStepFreePathwayEdgeId.present
          ? data.strictStepFreePathwayEdgeId.value
          : this.strictStepFreePathwayEdgeId,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      verificationStatus: data.verificationStatus.present
          ? data.verificationStatus.value
          : this.verificationStatus,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TransferRule(')
          ..write('id: $id, ')
          ..write('fromStationId: $fromStationId, ')
          ..write('fromLineId: $fromLineId, ')
          ..write('toStationId: $toStationId, ')
          ..write('toLineId: $toLineId, ')
          ..write('transferType: $transferType, ')
          ..write('minTransferSeconds: $minTransferSeconds, ')
          ..write('pathwayEdgeId: $pathwayEdgeId, ')
          ..write('strictStepFreePathwayEdgeId: $strictStepFreePathwayEdgeId, ')
          ..write('sourceId: $sourceId, ')
          ..write('verificationStatus: $verificationStatus')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    fromStationId,
    fromLineId,
    toStationId,
    toLineId,
    transferType,
    minTransferSeconds,
    pathwayEdgeId,
    strictStepFreePathwayEdgeId,
    sourceId,
    verificationStatus,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TransferRule &&
          other.id == this.id &&
          other.fromStationId == this.fromStationId &&
          other.fromLineId == this.fromLineId &&
          other.toStationId == this.toStationId &&
          other.toLineId == this.toLineId &&
          other.transferType == this.transferType &&
          other.minTransferSeconds == this.minTransferSeconds &&
          other.pathwayEdgeId == this.pathwayEdgeId &&
          other.strictStepFreePathwayEdgeId ==
              this.strictStepFreePathwayEdgeId &&
          other.sourceId == this.sourceId &&
          other.verificationStatus == this.verificationStatus);
}

class TransferRulesCompanion extends UpdateCompanion<TransferRule> {
  final Value<String> id;
  final Value<String> fromStationId;
  final Value<String> fromLineId;
  final Value<String> toStationId;
  final Value<String> toLineId;
  final Value<String> transferType;
  final Value<int> minTransferSeconds;
  final Value<String?> pathwayEdgeId;
  final Value<String?> strictStepFreePathwayEdgeId;
  final Value<String> sourceId;
  final Value<String> verificationStatus;
  final Value<int> rowid;
  const TransferRulesCompanion({
    this.id = const Value.absent(),
    this.fromStationId = const Value.absent(),
    this.fromLineId = const Value.absent(),
    this.toStationId = const Value.absent(),
    this.toLineId = const Value.absent(),
    this.transferType = const Value.absent(),
    this.minTransferSeconds = const Value.absent(),
    this.pathwayEdgeId = const Value.absent(),
    this.strictStepFreePathwayEdgeId = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.verificationStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TransferRulesCompanion.insert({
    required String id,
    required String fromStationId,
    required String fromLineId,
    required String toStationId,
    required String toLineId,
    this.transferType = const Value.absent(),
    this.minTransferSeconds = const Value.absent(),
    this.pathwayEdgeId = const Value.absent(),
    this.strictStepFreePathwayEdgeId = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.verificationStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       fromStationId = Value(fromStationId),
       fromLineId = Value(fromLineId),
       toStationId = Value(toStationId),
       toLineId = Value(toLineId);
  static Insertable<TransferRule> custom({
    Expression<String>? id,
    Expression<String>? fromStationId,
    Expression<String>? fromLineId,
    Expression<String>? toStationId,
    Expression<String>? toLineId,
    Expression<String>? transferType,
    Expression<int>? minTransferSeconds,
    Expression<String>? pathwayEdgeId,
    Expression<String>? strictStepFreePathwayEdgeId,
    Expression<String>? sourceId,
    Expression<String>? verificationStatus,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (fromStationId != null) 'from_station_id': fromStationId,
      if (fromLineId != null) 'from_line_id': fromLineId,
      if (toStationId != null) 'to_station_id': toStationId,
      if (toLineId != null) 'to_line_id': toLineId,
      if (transferType != null) 'transfer_type': transferType,
      if (minTransferSeconds != null)
        'min_transfer_seconds': minTransferSeconds,
      if (pathwayEdgeId != null) 'pathway_edge_id': pathwayEdgeId,
      if (strictStepFreePathwayEdgeId != null)
        'strict_step_free_pathway_edge_id': strictStepFreePathwayEdgeId,
      if (sourceId != null) 'source_id': sourceId,
      if (verificationStatus != null) 'verification_status': verificationStatus,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TransferRulesCompanion copyWith({
    Value<String>? id,
    Value<String>? fromStationId,
    Value<String>? fromLineId,
    Value<String>? toStationId,
    Value<String>? toLineId,
    Value<String>? transferType,
    Value<int>? minTransferSeconds,
    Value<String?>? pathwayEdgeId,
    Value<String?>? strictStepFreePathwayEdgeId,
    Value<String>? sourceId,
    Value<String>? verificationStatus,
    Value<int>? rowid,
  }) {
    return TransferRulesCompanion(
      id: id ?? this.id,
      fromStationId: fromStationId ?? this.fromStationId,
      fromLineId: fromLineId ?? this.fromLineId,
      toStationId: toStationId ?? this.toStationId,
      toLineId: toLineId ?? this.toLineId,
      transferType: transferType ?? this.transferType,
      minTransferSeconds: minTransferSeconds ?? this.minTransferSeconds,
      pathwayEdgeId: pathwayEdgeId ?? this.pathwayEdgeId,
      strictStepFreePathwayEdgeId:
          strictStepFreePathwayEdgeId ?? this.strictStepFreePathwayEdgeId,
      sourceId: sourceId ?? this.sourceId,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (fromStationId.present) {
      map['from_station_id'] = Variable<String>(fromStationId.value);
    }
    if (fromLineId.present) {
      map['from_line_id'] = Variable<String>(fromLineId.value);
    }
    if (toStationId.present) {
      map['to_station_id'] = Variable<String>(toStationId.value);
    }
    if (toLineId.present) {
      map['to_line_id'] = Variable<String>(toLineId.value);
    }
    if (transferType.present) {
      map['transfer_type'] = Variable<String>(transferType.value);
    }
    if (minTransferSeconds.present) {
      map['min_transfer_seconds'] = Variable<int>(minTransferSeconds.value);
    }
    if (pathwayEdgeId.present) {
      map['pathway_edge_id'] = Variable<String>(pathwayEdgeId.value);
    }
    if (strictStepFreePathwayEdgeId.present) {
      map['strict_step_free_pathway_edge_id'] = Variable<String>(
        strictStepFreePathwayEdgeId.value,
      );
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (verificationStatus.present) {
      map['verification_status'] = Variable<String>(verificationStatus.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransferRulesCompanion(')
          ..write('id: $id, ')
          ..write('fromStationId: $fromStationId, ')
          ..write('fromLineId: $fromLineId, ')
          ..write('toStationId: $toStationId, ')
          ..write('toLineId: $toLineId, ')
          ..write('transferType: $transferType, ')
          ..write('minTransferSeconds: $minTransferSeconds, ')
          ..write('pathwayEdgeId: $pathwayEdgeId, ')
          ..write('strictStepFreePathwayEdgeId: $strictStepFreePathwayEdgeId, ')
          ..write('sourceId: $sourceId, ')
          ..write('verificationStatus: $verificationStatus, ')
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
  late final $ServiceCalendarsTable serviceCalendars = $ServiceCalendarsTable(
    this,
  );
  late final $ServiceCalendarDatesTable serviceCalendarDates =
      $ServiceCalendarDatesTable(this);
  late final $TransitRoutesTable transitRoutes = $TransitRoutesTable(this);
  late final $TransitTripsTable transitTrips = $TransitTripsTable(this);
  late final $TransitStopTimesTable transitStopTimes = $TransitStopTimesTable(
    this,
  );
  late final $TransitFrequenciesTable transitFrequencies =
      $TransitFrequenciesTable(this);
  late final $RealtimeProviderLineMappingsTable realtimeProviderLineMappings =
      $RealtimeProviderLineMappingsTable(this);
  late final $RealtimeProviderStationMappingsTable
  realtimeProviderStationMappings = $RealtimeProviderStationMappingsTable(this);
  late final $NetworkEdgesTable networkEdges = $NetworkEdgesTable(this);
  late final $StationExitsTable stationExits = $StationExitsTable(this);
  late final $FacilitiesTable facilities = $FacilitiesTable(this);
  late final $StationFacilityEvidenceTable stationFacilityEvidence =
      $StationFacilityEvidenceTable(this);
  late final $StationAccessibilitySummariesTable stationAccessibilitySummaries =
      $StationAccessibilitySummariesTable(this);
  late final $InternalRouteNodesTable internalRouteNodes =
      $InternalRouteNodesTable(this);
  late final $InternalRouteEdgesTable internalRouteEdges =
      $InternalRouteEdgesTable(this);
  late final $StationPathwayNodesTable stationPathwayNodes =
      $StationPathwayNodesTable(this);
  late final $StationPathwayEdgesTable stationPathwayEdges =
      $StationPathwayEdgesTable(this);
  late final $TransferRulesTable transferRules = $TransferRulesTable(this);
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
    serviceCalendars,
    serviceCalendarDates,
    transitRoutes,
    transitTrips,
    transitStopTimes,
    transitFrequencies,
    realtimeProviderLineMappings,
    realtimeProviderStationMappings,
    networkEdges,
    stationExits,
    facilities,
    stationFacilityEvidence,
    stationAccessibilitySummaries,
    internalRouteNodes,
    internalRouteEdges,
    stationPathwayNodes,
    stationPathwayEdges,
    transferRules,
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
typedef $$ServiceCalendarsTableCreateCompanionBuilder =
    ServiceCalendarsCompanion Function({
      required String serviceId,
      required bool monday,
      required bool tuesday,
      required bool wednesday,
      required bool thursday,
      required bool friday,
      required bool saturday,
      required bool sunday,
      required String startDate,
      required String endDate,
      Value<String> timezone,
      Value<int> rowid,
    });
typedef $$ServiceCalendarsTableUpdateCompanionBuilder =
    ServiceCalendarsCompanion Function({
      Value<String> serviceId,
      Value<bool> monday,
      Value<bool> tuesday,
      Value<bool> wednesday,
      Value<bool> thursday,
      Value<bool> friday,
      Value<bool> saturday,
      Value<bool> sunday,
      Value<String> startDate,
      Value<String> endDate,
      Value<String> timezone,
      Value<int> rowid,
    });

class $$ServiceCalendarsTableFilterComposer
    extends Composer<_$CatalogDatabase, $ServiceCalendarsTable> {
  $$ServiceCalendarsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get serviceId => $composableBuilder(
    column: $table.serviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get monday => $composableBuilder(
    column: $table.monday,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get tuesday => $composableBuilder(
    column: $table.tuesday,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get wednesday => $composableBuilder(
    column: $table.wednesday,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get thursday => $composableBuilder(
    column: $table.thursday,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get friday => $composableBuilder(
    column: $table.friday,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get saturday => $composableBuilder(
    column: $table.saturday,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get sunday => $composableBuilder(
    column: $table.sunday,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timezone => $composableBuilder(
    column: $table.timezone,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ServiceCalendarsTableOrderingComposer
    extends Composer<_$CatalogDatabase, $ServiceCalendarsTable> {
  $$ServiceCalendarsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get serviceId => $composableBuilder(
    column: $table.serviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get monday => $composableBuilder(
    column: $table.monday,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get tuesday => $composableBuilder(
    column: $table.tuesday,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get wednesday => $composableBuilder(
    column: $table.wednesday,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get thursday => $composableBuilder(
    column: $table.thursday,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get friday => $composableBuilder(
    column: $table.friday,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get saturday => $composableBuilder(
    column: $table.saturday,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get sunday => $composableBuilder(
    column: $table.sunday,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timezone => $composableBuilder(
    column: $table.timezone,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ServiceCalendarsTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $ServiceCalendarsTable> {
  $$ServiceCalendarsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get serviceId =>
      $composableBuilder(column: $table.serviceId, builder: (column) => column);

  GeneratedColumn<bool> get monday =>
      $composableBuilder(column: $table.monday, builder: (column) => column);

  GeneratedColumn<bool> get tuesday =>
      $composableBuilder(column: $table.tuesday, builder: (column) => column);

  GeneratedColumn<bool> get wednesday =>
      $composableBuilder(column: $table.wednesday, builder: (column) => column);

  GeneratedColumn<bool> get thursday =>
      $composableBuilder(column: $table.thursday, builder: (column) => column);

  GeneratedColumn<bool> get friday =>
      $composableBuilder(column: $table.friday, builder: (column) => column);

  GeneratedColumn<bool> get saturday =>
      $composableBuilder(column: $table.saturday, builder: (column) => column);

  GeneratedColumn<bool> get sunday =>
      $composableBuilder(column: $table.sunday, builder: (column) => column);

  GeneratedColumn<String> get startDate =>
      $composableBuilder(column: $table.startDate, builder: (column) => column);

  GeneratedColumn<String> get endDate =>
      $composableBuilder(column: $table.endDate, builder: (column) => column);

  GeneratedColumn<String> get timezone =>
      $composableBuilder(column: $table.timezone, builder: (column) => column);
}

class $$ServiceCalendarsTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $ServiceCalendarsTable,
          ServiceCalendar,
          $$ServiceCalendarsTableFilterComposer,
          $$ServiceCalendarsTableOrderingComposer,
          $$ServiceCalendarsTableAnnotationComposer,
          $$ServiceCalendarsTableCreateCompanionBuilder,
          $$ServiceCalendarsTableUpdateCompanionBuilder,
          (
            ServiceCalendar,
            BaseReferences<
              _$CatalogDatabase,
              $ServiceCalendarsTable,
              ServiceCalendar
            >,
          ),
          ServiceCalendar,
          PrefetchHooks Function()
        > {
  $$ServiceCalendarsTableTableManager(
    _$CatalogDatabase db,
    $ServiceCalendarsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ServiceCalendarsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ServiceCalendarsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ServiceCalendarsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> serviceId = const Value.absent(),
                Value<bool> monday = const Value.absent(),
                Value<bool> tuesday = const Value.absent(),
                Value<bool> wednesday = const Value.absent(),
                Value<bool> thursday = const Value.absent(),
                Value<bool> friday = const Value.absent(),
                Value<bool> saturday = const Value.absent(),
                Value<bool> sunday = const Value.absent(),
                Value<String> startDate = const Value.absent(),
                Value<String> endDate = const Value.absent(),
                Value<String> timezone = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ServiceCalendarsCompanion(
                serviceId: serviceId,
                monday: monday,
                tuesday: tuesday,
                wednesday: wednesday,
                thursday: thursday,
                friday: friday,
                saturday: saturday,
                sunday: sunday,
                startDate: startDate,
                endDate: endDate,
                timezone: timezone,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String serviceId,
                required bool monday,
                required bool tuesday,
                required bool wednesday,
                required bool thursday,
                required bool friday,
                required bool saturday,
                required bool sunday,
                required String startDate,
                required String endDate,
                Value<String> timezone = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ServiceCalendarsCompanion.insert(
                serviceId: serviceId,
                monday: monday,
                tuesday: tuesday,
                wednesday: wednesday,
                thursday: thursday,
                friday: friday,
                saturday: saturday,
                sunday: sunday,
                startDate: startDate,
                endDate: endDate,
                timezone: timezone,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ServiceCalendarsTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $ServiceCalendarsTable,
      ServiceCalendar,
      $$ServiceCalendarsTableFilterComposer,
      $$ServiceCalendarsTableOrderingComposer,
      $$ServiceCalendarsTableAnnotationComposer,
      $$ServiceCalendarsTableCreateCompanionBuilder,
      $$ServiceCalendarsTableUpdateCompanionBuilder,
      (
        ServiceCalendar,
        BaseReferences<
          _$CatalogDatabase,
          $ServiceCalendarsTable,
          ServiceCalendar
        >,
      ),
      ServiceCalendar,
      PrefetchHooks Function()
    >;
typedef $$ServiceCalendarDatesTableCreateCompanionBuilder =
    ServiceCalendarDatesCompanion Function({
      required String serviceId,
      required String date,
      required int exceptionType,
      Value<int> rowid,
    });
typedef $$ServiceCalendarDatesTableUpdateCompanionBuilder =
    ServiceCalendarDatesCompanion Function({
      Value<String> serviceId,
      Value<String> date,
      Value<int> exceptionType,
      Value<int> rowid,
    });

class $$ServiceCalendarDatesTableFilterComposer
    extends Composer<_$CatalogDatabase, $ServiceCalendarDatesTable> {
  $$ServiceCalendarDatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get serviceId => $composableBuilder(
    column: $table.serviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get exceptionType => $composableBuilder(
    column: $table.exceptionType,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ServiceCalendarDatesTableOrderingComposer
    extends Composer<_$CatalogDatabase, $ServiceCalendarDatesTable> {
  $$ServiceCalendarDatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get serviceId => $composableBuilder(
    column: $table.serviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get exceptionType => $composableBuilder(
    column: $table.exceptionType,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ServiceCalendarDatesTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $ServiceCalendarDatesTable> {
  $$ServiceCalendarDatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get serviceId =>
      $composableBuilder(column: $table.serviceId, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<int> get exceptionType => $composableBuilder(
    column: $table.exceptionType,
    builder: (column) => column,
  );
}

class $$ServiceCalendarDatesTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $ServiceCalendarDatesTable,
          ServiceCalendarDate,
          $$ServiceCalendarDatesTableFilterComposer,
          $$ServiceCalendarDatesTableOrderingComposer,
          $$ServiceCalendarDatesTableAnnotationComposer,
          $$ServiceCalendarDatesTableCreateCompanionBuilder,
          $$ServiceCalendarDatesTableUpdateCompanionBuilder,
          (
            ServiceCalendarDate,
            BaseReferences<
              _$CatalogDatabase,
              $ServiceCalendarDatesTable,
              ServiceCalendarDate
            >,
          ),
          ServiceCalendarDate,
          PrefetchHooks Function()
        > {
  $$ServiceCalendarDatesTableTableManager(
    _$CatalogDatabase db,
    $ServiceCalendarDatesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ServiceCalendarDatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ServiceCalendarDatesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ServiceCalendarDatesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> serviceId = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<int> exceptionType = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ServiceCalendarDatesCompanion(
                serviceId: serviceId,
                date: date,
                exceptionType: exceptionType,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String serviceId,
                required String date,
                required int exceptionType,
                Value<int> rowid = const Value.absent(),
              }) => ServiceCalendarDatesCompanion.insert(
                serviceId: serviceId,
                date: date,
                exceptionType: exceptionType,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ServiceCalendarDatesTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $ServiceCalendarDatesTable,
      ServiceCalendarDate,
      $$ServiceCalendarDatesTableFilterComposer,
      $$ServiceCalendarDatesTableOrderingComposer,
      $$ServiceCalendarDatesTableAnnotationComposer,
      $$ServiceCalendarDatesTableCreateCompanionBuilder,
      $$ServiceCalendarDatesTableUpdateCompanionBuilder,
      (
        ServiceCalendarDate,
        BaseReferences<
          _$CatalogDatabase,
          $ServiceCalendarDatesTable,
          ServiceCalendarDate
        >,
      ),
      ServiceCalendarDate,
      PrefetchHooks Function()
    >;
typedef $$TransitRoutesTableCreateCompanionBuilder =
    TransitRoutesCompanion Function({
      required String id,
      required String lineId,
      Value<String> routeShortName,
      Value<String> routeLongName,
      Value<String> directionName,
      Value<String> timezone,
      Value<int> rowid,
    });
typedef $$TransitRoutesTableUpdateCompanionBuilder =
    TransitRoutesCompanion Function({
      Value<String> id,
      Value<String> lineId,
      Value<String> routeShortName,
      Value<String> routeLongName,
      Value<String> directionName,
      Value<String> timezone,
      Value<int> rowid,
    });

class $$TransitRoutesTableFilterComposer
    extends Composer<_$CatalogDatabase, $TransitRoutesTable> {
  $$TransitRoutesTableFilterComposer({
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

  ColumnFilters<String> get lineId => $composableBuilder(
    column: $table.lineId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get routeShortName => $composableBuilder(
    column: $table.routeShortName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get routeLongName => $composableBuilder(
    column: $table.routeLongName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get directionName => $composableBuilder(
    column: $table.directionName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timezone => $composableBuilder(
    column: $table.timezone,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TransitRoutesTableOrderingComposer
    extends Composer<_$CatalogDatabase, $TransitRoutesTable> {
  $$TransitRoutesTableOrderingComposer({
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

  ColumnOrderings<String> get lineId => $composableBuilder(
    column: $table.lineId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get routeShortName => $composableBuilder(
    column: $table.routeShortName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get routeLongName => $composableBuilder(
    column: $table.routeLongName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get directionName => $composableBuilder(
    column: $table.directionName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timezone => $composableBuilder(
    column: $table.timezone,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TransitRoutesTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $TransitRoutesTable> {
  $$TransitRoutesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get lineId =>
      $composableBuilder(column: $table.lineId, builder: (column) => column);

  GeneratedColumn<String> get routeShortName => $composableBuilder(
    column: $table.routeShortName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get routeLongName => $composableBuilder(
    column: $table.routeLongName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get directionName => $composableBuilder(
    column: $table.directionName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get timezone =>
      $composableBuilder(column: $table.timezone, builder: (column) => column);
}

class $$TransitRoutesTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $TransitRoutesTable,
          TransitRoute,
          $$TransitRoutesTableFilterComposer,
          $$TransitRoutesTableOrderingComposer,
          $$TransitRoutesTableAnnotationComposer,
          $$TransitRoutesTableCreateCompanionBuilder,
          $$TransitRoutesTableUpdateCompanionBuilder,
          (
            TransitRoute,
            BaseReferences<
              _$CatalogDatabase,
              $TransitRoutesTable,
              TransitRoute
            >,
          ),
          TransitRoute,
          PrefetchHooks Function()
        > {
  $$TransitRoutesTableTableManager(
    _$CatalogDatabase db,
    $TransitRoutesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransitRoutesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransitRoutesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransitRoutesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> lineId = const Value.absent(),
                Value<String> routeShortName = const Value.absent(),
                Value<String> routeLongName = const Value.absent(),
                Value<String> directionName = const Value.absent(),
                Value<String> timezone = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransitRoutesCompanion(
                id: id,
                lineId: lineId,
                routeShortName: routeShortName,
                routeLongName: routeLongName,
                directionName: directionName,
                timezone: timezone,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String lineId,
                Value<String> routeShortName = const Value.absent(),
                Value<String> routeLongName = const Value.absent(),
                Value<String> directionName = const Value.absent(),
                Value<String> timezone = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransitRoutesCompanion.insert(
                id: id,
                lineId: lineId,
                routeShortName: routeShortName,
                routeLongName: routeLongName,
                directionName: directionName,
                timezone: timezone,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TransitRoutesTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $TransitRoutesTable,
      TransitRoute,
      $$TransitRoutesTableFilterComposer,
      $$TransitRoutesTableOrderingComposer,
      $$TransitRoutesTableAnnotationComposer,
      $$TransitRoutesTableCreateCompanionBuilder,
      $$TransitRoutesTableUpdateCompanionBuilder,
      (
        TransitRoute,
        BaseReferences<_$CatalogDatabase, $TransitRoutesTable, TransitRoute>,
      ),
      TransitRoute,
      PrefetchHooks Function()
    >;
typedef $$TransitTripsTableCreateCompanionBuilder =
    TransitTripsCompanion Function({
      required String id,
      required String routeId,
      required String serviceId,
      Value<String> tripHeadsign,
      Value<String> directionId,
      Value<String> servicePattern,
      Value<int> serviceDayStartSeconds,
      Value<int> rowid,
    });
typedef $$TransitTripsTableUpdateCompanionBuilder =
    TransitTripsCompanion Function({
      Value<String> id,
      Value<String> routeId,
      Value<String> serviceId,
      Value<String> tripHeadsign,
      Value<String> directionId,
      Value<String> servicePattern,
      Value<int> serviceDayStartSeconds,
      Value<int> rowid,
    });

class $$TransitTripsTableFilterComposer
    extends Composer<_$CatalogDatabase, $TransitTripsTable> {
  $$TransitTripsTableFilterComposer({
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

  ColumnFilters<String> get routeId => $composableBuilder(
    column: $table.routeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serviceId => $composableBuilder(
    column: $table.serviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tripHeadsign => $composableBuilder(
    column: $table.tripHeadsign,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get directionId => $composableBuilder(
    column: $table.directionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get servicePattern => $composableBuilder(
    column: $table.servicePattern,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serviceDayStartSeconds => $composableBuilder(
    column: $table.serviceDayStartSeconds,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TransitTripsTableOrderingComposer
    extends Composer<_$CatalogDatabase, $TransitTripsTable> {
  $$TransitTripsTableOrderingComposer({
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

  ColumnOrderings<String> get routeId => $composableBuilder(
    column: $table.routeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serviceId => $composableBuilder(
    column: $table.serviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tripHeadsign => $composableBuilder(
    column: $table.tripHeadsign,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get directionId => $composableBuilder(
    column: $table.directionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get servicePattern => $composableBuilder(
    column: $table.servicePattern,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serviceDayStartSeconds => $composableBuilder(
    column: $table.serviceDayStartSeconds,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TransitTripsTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $TransitTripsTable> {
  $$TransitTripsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get routeId =>
      $composableBuilder(column: $table.routeId, builder: (column) => column);

  GeneratedColumn<String> get serviceId =>
      $composableBuilder(column: $table.serviceId, builder: (column) => column);

  GeneratedColumn<String> get tripHeadsign => $composableBuilder(
    column: $table.tripHeadsign,
    builder: (column) => column,
  );

  GeneratedColumn<String> get directionId => $composableBuilder(
    column: $table.directionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get servicePattern => $composableBuilder(
    column: $table.servicePattern,
    builder: (column) => column,
  );

  GeneratedColumn<int> get serviceDayStartSeconds => $composableBuilder(
    column: $table.serviceDayStartSeconds,
    builder: (column) => column,
  );
}

class $$TransitTripsTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $TransitTripsTable,
          TransitTrip,
          $$TransitTripsTableFilterComposer,
          $$TransitTripsTableOrderingComposer,
          $$TransitTripsTableAnnotationComposer,
          $$TransitTripsTableCreateCompanionBuilder,
          $$TransitTripsTableUpdateCompanionBuilder,
          (
            TransitTrip,
            BaseReferences<_$CatalogDatabase, $TransitTripsTable, TransitTrip>,
          ),
          TransitTrip,
          PrefetchHooks Function()
        > {
  $$TransitTripsTableTableManager(
    _$CatalogDatabase db,
    $TransitTripsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransitTripsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransitTripsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransitTripsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> routeId = const Value.absent(),
                Value<String> serviceId = const Value.absent(),
                Value<String> tripHeadsign = const Value.absent(),
                Value<String> directionId = const Value.absent(),
                Value<String> servicePattern = const Value.absent(),
                Value<int> serviceDayStartSeconds = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransitTripsCompanion(
                id: id,
                routeId: routeId,
                serviceId: serviceId,
                tripHeadsign: tripHeadsign,
                directionId: directionId,
                servicePattern: servicePattern,
                serviceDayStartSeconds: serviceDayStartSeconds,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String routeId,
                required String serviceId,
                Value<String> tripHeadsign = const Value.absent(),
                Value<String> directionId = const Value.absent(),
                Value<String> servicePattern = const Value.absent(),
                Value<int> serviceDayStartSeconds = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransitTripsCompanion.insert(
                id: id,
                routeId: routeId,
                serviceId: serviceId,
                tripHeadsign: tripHeadsign,
                directionId: directionId,
                servicePattern: servicePattern,
                serviceDayStartSeconds: serviceDayStartSeconds,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TransitTripsTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $TransitTripsTable,
      TransitTrip,
      $$TransitTripsTableFilterComposer,
      $$TransitTripsTableOrderingComposer,
      $$TransitTripsTableAnnotationComposer,
      $$TransitTripsTableCreateCompanionBuilder,
      $$TransitTripsTableUpdateCompanionBuilder,
      (
        TransitTrip,
        BaseReferences<_$CatalogDatabase, $TransitTripsTable, TransitTrip>,
      ),
      TransitTrip,
      PrefetchHooks Function()
    >;
typedef $$TransitStopTimesTableCreateCompanionBuilder =
    TransitStopTimesCompanion Function({
      required String tripId,
      required int stopSequence,
      required String stationId,
      required String lineId,
      required int arrivalSeconds,
      required int departureSeconds,
      Value<int> pickupType,
      Value<int> dropOffType,
      Value<int> rowid,
    });
typedef $$TransitStopTimesTableUpdateCompanionBuilder =
    TransitStopTimesCompanion Function({
      Value<String> tripId,
      Value<int> stopSequence,
      Value<String> stationId,
      Value<String> lineId,
      Value<int> arrivalSeconds,
      Value<int> departureSeconds,
      Value<int> pickupType,
      Value<int> dropOffType,
      Value<int> rowid,
    });

class $$TransitStopTimesTableFilterComposer
    extends Composer<_$CatalogDatabase, $TransitStopTimesTable> {
  $$TransitStopTimesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get tripId => $composableBuilder(
    column: $table.tripId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get stopSequence => $composableBuilder(
    column: $table.stopSequence,
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

  ColumnFilters<int> get arrivalSeconds => $composableBuilder(
    column: $table.arrivalSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get departureSeconds => $composableBuilder(
    column: $table.departureSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pickupType => $composableBuilder(
    column: $table.pickupType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dropOffType => $composableBuilder(
    column: $table.dropOffType,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TransitStopTimesTableOrderingComposer
    extends Composer<_$CatalogDatabase, $TransitStopTimesTable> {
  $$TransitStopTimesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get tripId => $composableBuilder(
    column: $table.tripId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get stopSequence => $composableBuilder(
    column: $table.stopSequence,
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

  ColumnOrderings<int> get arrivalSeconds => $composableBuilder(
    column: $table.arrivalSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get departureSeconds => $composableBuilder(
    column: $table.departureSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pickupType => $composableBuilder(
    column: $table.pickupType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dropOffType => $composableBuilder(
    column: $table.dropOffType,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TransitStopTimesTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $TransitStopTimesTable> {
  $$TransitStopTimesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get tripId =>
      $composableBuilder(column: $table.tripId, builder: (column) => column);

  GeneratedColumn<int> get stopSequence => $composableBuilder(
    column: $table.stopSequence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get stationId =>
      $composableBuilder(column: $table.stationId, builder: (column) => column);

  GeneratedColumn<String> get lineId =>
      $composableBuilder(column: $table.lineId, builder: (column) => column);

  GeneratedColumn<int> get arrivalSeconds => $composableBuilder(
    column: $table.arrivalSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<int> get departureSeconds => $composableBuilder(
    column: $table.departureSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<int> get pickupType => $composableBuilder(
    column: $table.pickupType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dropOffType => $composableBuilder(
    column: $table.dropOffType,
    builder: (column) => column,
  );
}

class $$TransitStopTimesTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $TransitStopTimesTable,
          TransitStopTime,
          $$TransitStopTimesTableFilterComposer,
          $$TransitStopTimesTableOrderingComposer,
          $$TransitStopTimesTableAnnotationComposer,
          $$TransitStopTimesTableCreateCompanionBuilder,
          $$TransitStopTimesTableUpdateCompanionBuilder,
          (
            TransitStopTime,
            BaseReferences<
              _$CatalogDatabase,
              $TransitStopTimesTable,
              TransitStopTime
            >,
          ),
          TransitStopTime,
          PrefetchHooks Function()
        > {
  $$TransitStopTimesTableTableManager(
    _$CatalogDatabase db,
    $TransitStopTimesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransitStopTimesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransitStopTimesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransitStopTimesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> tripId = const Value.absent(),
                Value<int> stopSequence = const Value.absent(),
                Value<String> stationId = const Value.absent(),
                Value<String> lineId = const Value.absent(),
                Value<int> arrivalSeconds = const Value.absent(),
                Value<int> departureSeconds = const Value.absent(),
                Value<int> pickupType = const Value.absent(),
                Value<int> dropOffType = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransitStopTimesCompanion(
                tripId: tripId,
                stopSequence: stopSequence,
                stationId: stationId,
                lineId: lineId,
                arrivalSeconds: arrivalSeconds,
                departureSeconds: departureSeconds,
                pickupType: pickupType,
                dropOffType: dropOffType,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String tripId,
                required int stopSequence,
                required String stationId,
                required String lineId,
                required int arrivalSeconds,
                required int departureSeconds,
                Value<int> pickupType = const Value.absent(),
                Value<int> dropOffType = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransitStopTimesCompanion.insert(
                tripId: tripId,
                stopSequence: stopSequence,
                stationId: stationId,
                lineId: lineId,
                arrivalSeconds: arrivalSeconds,
                departureSeconds: departureSeconds,
                pickupType: pickupType,
                dropOffType: dropOffType,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TransitStopTimesTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $TransitStopTimesTable,
      TransitStopTime,
      $$TransitStopTimesTableFilterComposer,
      $$TransitStopTimesTableOrderingComposer,
      $$TransitStopTimesTableAnnotationComposer,
      $$TransitStopTimesTableCreateCompanionBuilder,
      $$TransitStopTimesTableUpdateCompanionBuilder,
      (
        TransitStopTime,
        BaseReferences<
          _$CatalogDatabase,
          $TransitStopTimesTable,
          TransitStopTime
        >,
      ),
      TransitStopTime,
      PrefetchHooks Function()
    >;
typedef $$TransitFrequenciesTableCreateCompanionBuilder =
    TransitFrequenciesCompanion Function({
      required String tripId,
      required int startTimeSeconds,
      required int endTimeSeconds,
      required int headwaySeconds,
      Value<bool> exactTimes,
      Value<int> rowid,
    });
typedef $$TransitFrequenciesTableUpdateCompanionBuilder =
    TransitFrequenciesCompanion Function({
      Value<String> tripId,
      Value<int> startTimeSeconds,
      Value<int> endTimeSeconds,
      Value<int> headwaySeconds,
      Value<bool> exactTimes,
      Value<int> rowid,
    });

class $$TransitFrequenciesTableFilterComposer
    extends Composer<_$CatalogDatabase, $TransitFrequenciesTable> {
  $$TransitFrequenciesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get tripId => $composableBuilder(
    column: $table.tripId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startTimeSeconds => $composableBuilder(
    column: $table.startTimeSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endTimeSeconds => $composableBuilder(
    column: $table.endTimeSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get headwaySeconds => $composableBuilder(
    column: $table.headwaySeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get exactTimes => $composableBuilder(
    column: $table.exactTimes,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TransitFrequenciesTableOrderingComposer
    extends Composer<_$CatalogDatabase, $TransitFrequenciesTable> {
  $$TransitFrequenciesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get tripId => $composableBuilder(
    column: $table.tripId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startTimeSeconds => $composableBuilder(
    column: $table.startTimeSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endTimeSeconds => $composableBuilder(
    column: $table.endTimeSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get headwaySeconds => $composableBuilder(
    column: $table.headwaySeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get exactTimes => $composableBuilder(
    column: $table.exactTimes,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TransitFrequenciesTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $TransitFrequenciesTable> {
  $$TransitFrequenciesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get tripId =>
      $composableBuilder(column: $table.tripId, builder: (column) => column);

  GeneratedColumn<int> get startTimeSeconds => $composableBuilder(
    column: $table.startTimeSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endTimeSeconds => $composableBuilder(
    column: $table.endTimeSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<int> get headwaySeconds => $composableBuilder(
    column: $table.headwaySeconds,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get exactTimes => $composableBuilder(
    column: $table.exactTimes,
    builder: (column) => column,
  );
}

class $$TransitFrequenciesTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $TransitFrequenciesTable,
          TransitFrequency,
          $$TransitFrequenciesTableFilterComposer,
          $$TransitFrequenciesTableOrderingComposer,
          $$TransitFrequenciesTableAnnotationComposer,
          $$TransitFrequenciesTableCreateCompanionBuilder,
          $$TransitFrequenciesTableUpdateCompanionBuilder,
          (
            TransitFrequency,
            BaseReferences<
              _$CatalogDatabase,
              $TransitFrequenciesTable,
              TransitFrequency
            >,
          ),
          TransitFrequency,
          PrefetchHooks Function()
        > {
  $$TransitFrequenciesTableTableManager(
    _$CatalogDatabase db,
    $TransitFrequenciesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransitFrequenciesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransitFrequenciesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransitFrequenciesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> tripId = const Value.absent(),
                Value<int> startTimeSeconds = const Value.absent(),
                Value<int> endTimeSeconds = const Value.absent(),
                Value<int> headwaySeconds = const Value.absent(),
                Value<bool> exactTimes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransitFrequenciesCompanion(
                tripId: tripId,
                startTimeSeconds: startTimeSeconds,
                endTimeSeconds: endTimeSeconds,
                headwaySeconds: headwaySeconds,
                exactTimes: exactTimes,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String tripId,
                required int startTimeSeconds,
                required int endTimeSeconds,
                required int headwaySeconds,
                Value<bool> exactTimes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransitFrequenciesCompanion.insert(
                tripId: tripId,
                startTimeSeconds: startTimeSeconds,
                endTimeSeconds: endTimeSeconds,
                headwaySeconds: headwaySeconds,
                exactTimes: exactTimes,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TransitFrequenciesTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $TransitFrequenciesTable,
      TransitFrequency,
      $$TransitFrequenciesTableFilterComposer,
      $$TransitFrequenciesTableOrderingComposer,
      $$TransitFrequenciesTableAnnotationComposer,
      $$TransitFrequenciesTableCreateCompanionBuilder,
      $$TransitFrequenciesTableUpdateCompanionBuilder,
      (
        TransitFrequency,
        BaseReferences<
          _$CatalogDatabase,
          $TransitFrequenciesTable,
          TransitFrequency
        >,
      ),
      TransitFrequency,
      PrefetchHooks Function()
    >;
typedef $$RealtimeProviderLineMappingsTableCreateCompanionBuilder =
    RealtimeProviderLineMappingsCompanion Function({
      required String providerId,
      required String providerLineId,
      required String lineId,
      required String sourceId,
      Value<bool> supportsArrivals,
      Value<bool> supportsTrainPositions,
      Value<String> mappingConfidence,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });
typedef $$RealtimeProviderLineMappingsTableUpdateCompanionBuilder =
    RealtimeProviderLineMappingsCompanion Function({
      Value<String> providerId,
      Value<String> providerLineId,
      Value<String> lineId,
      Value<String> sourceId,
      Value<bool> supportsArrivals,
      Value<bool> supportsTrainPositions,
      Value<String> mappingConfidence,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });

class $$RealtimeProviderLineMappingsTableFilterComposer
    extends Composer<_$CatalogDatabase, $RealtimeProviderLineMappingsTable> {
  $$RealtimeProviderLineMappingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get providerLineId => $composableBuilder(
    column: $table.providerLineId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lineId => $composableBuilder(
    column: $table.lineId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get supportsArrivals => $composableBuilder(
    column: $table.supportsArrivals,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get supportsTrainPositions => $composableBuilder(
    column: $table.supportsTrainPositions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mappingConfidence => $composableBuilder(
    column: $table.mappingConfidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RealtimeProviderLineMappingsTableOrderingComposer
    extends Composer<_$CatalogDatabase, $RealtimeProviderLineMappingsTable> {
  $$RealtimeProviderLineMappingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get providerLineId => $composableBuilder(
    column: $table.providerLineId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lineId => $composableBuilder(
    column: $table.lineId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get supportsArrivals => $composableBuilder(
    column: $table.supportsArrivals,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get supportsTrainPositions => $composableBuilder(
    column: $table.supportsTrainPositions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mappingConfidence => $composableBuilder(
    column: $table.mappingConfidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RealtimeProviderLineMappingsTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $RealtimeProviderLineMappingsTable> {
  $$RealtimeProviderLineMappingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get providerLineId => $composableBuilder(
    column: $table.providerLineId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lineId =>
      $composableBuilder(column: $table.lineId, builder: (column) => column);

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<bool> get supportsArrivals => $composableBuilder(
    column: $table.supportsArrivals,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get supportsTrainPositions => $composableBuilder(
    column: $table.supportsTrainPositions,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mappingConfidence => $composableBuilder(
    column: $table.mappingConfidence,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$RealtimeProviderLineMappingsTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $RealtimeProviderLineMappingsTable,
          RealtimeProviderLineMapping,
          $$RealtimeProviderLineMappingsTableFilterComposer,
          $$RealtimeProviderLineMappingsTableOrderingComposer,
          $$RealtimeProviderLineMappingsTableAnnotationComposer,
          $$RealtimeProviderLineMappingsTableCreateCompanionBuilder,
          $$RealtimeProviderLineMappingsTableUpdateCompanionBuilder,
          (
            RealtimeProviderLineMapping,
            BaseReferences<
              _$CatalogDatabase,
              $RealtimeProviderLineMappingsTable,
              RealtimeProviderLineMapping
            >,
          ),
          RealtimeProviderLineMapping,
          PrefetchHooks Function()
        > {
  $$RealtimeProviderLineMappingsTableTableManager(
    _$CatalogDatabase db,
    $RealtimeProviderLineMappingsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RealtimeProviderLineMappingsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$RealtimeProviderLineMappingsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$RealtimeProviderLineMappingsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> providerId = const Value.absent(),
                Value<String> providerLineId = const Value.absent(),
                Value<String> lineId = const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<bool> supportsArrivals = const Value.absent(),
                Value<bool> supportsTrainPositions = const Value.absent(),
                Value<String> mappingConfidence = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RealtimeProviderLineMappingsCompanion(
                providerId: providerId,
                providerLineId: providerLineId,
                lineId: lineId,
                sourceId: sourceId,
                supportsArrivals: supportsArrivals,
                supportsTrainPositions: supportsTrainPositions,
                mappingConfidence: mappingConfidence,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String providerId,
                required String providerLineId,
                required String lineId,
                required String sourceId,
                Value<bool> supportsArrivals = const Value.absent(),
                Value<bool> supportsTrainPositions = const Value.absent(),
                Value<String> mappingConfidence = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RealtimeProviderLineMappingsCompanion.insert(
                providerId: providerId,
                providerLineId: providerLineId,
                lineId: lineId,
                sourceId: sourceId,
                supportsArrivals: supportsArrivals,
                supportsTrainPositions: supportsTrainPositions,
                mappingConfidence: mappingConfidence,
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

typedef $$RealtimeProviderLineMappingsTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $RealtimeProviderLineMappingsTable,
      RealtimeProviderLineMapping,
      $$RealtimeProviderLineMappingsTableFilterComposer,
      $$RealtimeProviderLineMappingsTableOrderingComposer,
      $$RealtimeProviderLineMappingsTableAnnotationComposer,
      $$RealtimeProviderLineMappingsTableCreateCompanionBuilder,
      $$RealtimeProviderLineMappingsTableUpdateCompanionBuilder,
      (
        RealtimeProviderLineMapping,
        BaseReferences<
          _$CatalogDatabase,
          $RealtimeProviderLineMappingsTable,
          RealtimeProviderLineMapping
        >,
      ),
      RealtimeProviderLineMapping,
      PrefetchHooks Function()
    >;
typedef $$RealtimeProviderStationMappingsTableCreateCompanionBuilder =
    RealtimeProviderStationMappingsCompanion Function({
      required String providerId,
      required String providerLineId,
      required String providerStationId,
      required String stationId,
      required String lineId,
      required String sourceId,
      Value<String> queryName,
      Value<bool> supportsArrivals,
      Value<bool> supportsTrainPositions,
      Value<String> mappingConfidence,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });
typedef $$RealtimeProviderStationMappingsTableUpdateCompanionBuilder =
    RealtimeProviderStationMappingsCompanion Function({
      Value<String> providerId,
      Value<String> providerLineId,
      Value<String> providerStationId,
      Value<String> stationId,
      Value<String> lineId,
      Value<String> sourceId,
      Value<String> queryName,
      Value<bool> supportsArrivals,
      Value<bool> supportsTrainPositions,
      Value<String> mappingConfidence,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });

class $$RealtimeProviderStationMappingsTableFilterComposer
    extends Composer<_$CatalogDatabase, $RealtimeProviderStationMappingsTable> {
  $$RealtimeProviderStationMappingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get providerLineId => $composableBuilder(
    column: $table.providerLineId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get providerStationId => $composableBuilder(
    column: $table.providerStationId,
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

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get queryName => $composableBuilder(
    column: $table.queryName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get supportsArrivals => $composableBuilder(
    column: $table.supportsArrivals,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get supportsTrainPositions => $composableBuilder(
    column: $table.supportsTrainPositions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mappingConfidence => $composableBuilder(
    column: $table.mappingConfidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RealtimeProviderStationMappingsTableOrderingComposer
    extends Composer<_$CatalogDatabase, $RealtimeProviderStationMappingsTable> {
  $$RealtimeProviderStationMappingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get providerLineId => $composableBuilder(
    column: $table.providerLineId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get providerStationId => $composableBuilder(
    column: $table.providerStationId,
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

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get queryName => $composableBuilder(
    column: $table.queryName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get supportsArrivals => $composableBuilder(
    column: $table.supportsArrivals,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get supportsTrainPositions => $composableBuilder(
    column: $table.supportsTrainPositions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mappingConfidence => $composableBuilder(
    column: $table.mappingConfidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RealtimeProviderStationMappingsTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $RealtimeProviderStationMappingsTable> {
  $$RealtimeProviderStationMappingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get providerLineId => $composableBuilder(
    column: $table.providerLineId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get providerStationId => $composableBuilder(
    column: $table.providerStationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get stationId =>
      $composableBuilder(column: $table.stationId, builder: (column) => column);

  GeneratedColumn<String> get lineId =>
      $composableBuilder(column: $table.lineId, builder: (column) => column);

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get queryName =>
      $composableBuilder(column: $table.queryName, builder: (column) => column);

  GeneratedColumn<bool> get supportsArrivals => $composableBuilder(
    column: $table.supportsArrivals,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get supportsTrainPositions => $composableBuilder(
    column: $table.supportsTrainPositions,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mappingConfidence => $composableBuilder(
    column: $table.mappingConfidence,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$RealtimeProviderStationMappingsTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $RealtimeProviderStationMappingsTable,
          RealtimeProviderStationMapping,
          $$RealtimeProviderStationMappingsTableFilterComposer,
          $$RealtimeProviderStationMappingsTableOrderingComposer,
          $$RealtimeProviderStationMappingsTableAnnotationComposer,
          $$RealtimeProviderStationMappingsTableCreateCompanionBuilder,
          $$RealtimeProviderStationMappingsTableUpdateCompanionBuilder,
          (
            RealtimeProviderStationMapping,
            BaseReferences<
              _$CatalogDatabase,
              $RealtimeProviderStationMappingsTable,
              RealtimeProviderStationMapping
            >,
          ),
          RealtimeProviderStationMapping,
          PrefetchHooks Function()
        > {
  $$RealtimeProviderStationMappingsTableTableManager(
    _$CatalogDatabase db,
    $RealtimeProviderStationMappingsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RealtimeProviderStationMappingsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$RealtimeProviderStationMappingsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$RealtimeProviderStationMappingsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> providerId = const Value.absent(),
                Value<String> providerLineId = const Value.absent(),
                Value<String> providerStationId = const Value.absent(),
                Value<String> stationId = const Value.absent(),
                Value<String> lineId = const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<String> queryName = const Value.absent(),
                Value<bool> supportsArrivals = const Value.absent(),
                Value<bool> supportsTrainPositions = const Value.absent(),
                Value<String> mappingConfidence = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RealtimeProviderStationMappingsCompanion(
                providerId: providerId,
                providerLineId: providerLineId,
                providerStationId: providerStationId,
                stationId: stationId,
                lineId: lineId,
                sourceId: sourceId,
                queryName: queryName,
                supportsArrivals: supportsArrivals,
                supportsTrainPositions: supportsTrainPositions,
                mappingConfidence: mappingConfidence,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String providerId,
                required String providerLineId,
                required String providerStationId,
                required String stationId,
                required String lineId,
                required String sourceId,
                Value<String> queryName = const Value.absent(),
                Value<bool> supportsArrivals = const Value.absent(),
                Value<bool> supportsTrainPositions = const Value.absent(),
                Value<String> mappingConfidence = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RealtimeProviderStationMappingsCompanion.insert(
                providerId: providerId,
                providerLineId: providerLineId,
                providerStationId: providerStationId,
                stationId: stationId,
                lineId: lineId,
                sourceId: sourceId,
                queryName: queryName,
                supportsArrivals: supportsArrivals,
                supportsTrainPositions: supportsTrainPositions,
                mappingConfidence: mappingConfidence,
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

typedef $$RealtimeProviderStationMappingsTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $RealtimeProviderStationMappingsTable,
      RealtimeProviderStationMapping,
      $$RealtimeProviderStationMappingsTableFilterComposer,
      $$RealtimeProviderStationMappingsTableOrderingComposer,
      $$RealtimeProviderStationMappingsTableAnnotationComposer,
      $$RealtimeProviderStationMappingsTableCreateCompanionBuilder,
      $$RealtimeProviderStationMappingsTableUpdateCompanionBuilder,
      (
        RealtimeProviderStationMapping,
        BaseReferences<
          _$CatalogDatabase,
          $RealtimeProviderStationMappingsTable,
          RealtimeProviderStationMapping
        >,
      ),
      RealtimeProviderStationMapping,
      PrefetchHooks Function()
    >;
typedef $$NetworkEdgesTableCreateCompanionBuilder =
    NetworkEdgesCompanion Function({
      required String id,
      required String fromNodeId,
      required String toNodeId,
      Value<int> durationSeconds,
      Value<int> distanceMeters,
      Value<String> edgeType,
      Value<String> servicePattern,
      Value<bool> includesStairs,
      Value<String> stairAccessState,
      Value<String> accessibilityStatus,
      Value<int> reliabilityScore,
      Value<String> sourceId,
      Value<String> sourceSnapshotId,
      Value<String> providerRecordHash,
      Value<String> provenanceKind,
      Value<String> verificationStatus,
      Value<String?> facilityId,
      Value<DateTime?> lastVerifiedAt,
      Value<String> evidenceHash,
      Value<int> rowid,
    });
typedef $$NetworkEdgesTableUpdateCompanionBuilder =
    NetworkEdgesCompanion Function({
      Value<String> id,
      Value<String> fromNodeId,
      Value<String> toNodeId,
      Value<int> durationSeconds,
      Value<int> distanceMeters,
      Value<String> edgeType,
      Value<String> servicePattern,
      Value<bool> includesStairs,
      Value<String> stairAccessState,
      Value<String> accessibilityStatus,
      Value<int> reliabilityScore,
      Value<String> sourceId,
      Value<String> sourceSnapshotId,
      Value<String> providerRecordHash,
      Value<String> provenanceKind,
      Value<String> verificationStatus,
      Value<String?> facilityId,
      Value<DateTime?> lastVerifiedAt,
      Value<String> evidenceHash,
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

  ColumnFilters<int> get distanceMeters => $composableBuilder(
    column: $table.distanceMeters,
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

  ColumnFilters<String> get stairAccessState => $composableBuilder(
    column: $table.stairAccessState,
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

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceSnapshotId => $composableBuilder(
    column: $table.sourceSnapshotId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get providerRecordHash => $composableBuilder(
    column: $table.providerRecordHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get provenanceKind => $composableBuilder(
    column: $table.provenanceKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get verificationStatus => $composableBuilder(
    column: $table.verificationStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get facilityId => $composableBuilder(
    column: $table.facilityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastVerifiedAt => $composableBuilder(
    column: $table.lastVerifiedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get evidenceHash => $composableBuilder(
    column: $table.evidenceHash,
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

  ColumnOrderings<int> get distanceMeters => $composableBuilder(
    column: $table.distanceMeters,
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

  ColumnOrderings<String> get stairAccessState => $composableBuilder(
    column: $table.stairAccessState,
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

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceSnapshotId => $composableBuilder(
    column: $table.sourceSnapshotId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get providerRecordHash => $composableBuilder(
    column: $table.providerRecordHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get provenanceKind => $composableBuilder(
    column: $table.provenanceKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get verificationStatus => $composableBuilder(
    column: $table.verificationStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get facilityId => $composableBuilder(
    column: $table.facilityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastVerifiedAt => $composableBuilder(
    column: $table.lastVerifiedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get evidenceHash => $composableBuilder(
    column: $table.evidenceHash,
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

  GeneratedColumn<int> get distanceMeters => $composableBuilder(
    column: $table.distanceMeters,
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

  GeneratedColumn<String> get stairAccessState => $composableBuilder(
    column: $table.stairAccessState,
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

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get sourceSnapshotId => $composableBuilder(
    column: $table.sourceSnapshotId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get providerRecordHash => $composableBuilder(
    column: $table.providerRecordHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get provenanceKind => $composableBuilder(
    column: $table.provenanceKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get verificationStatus => $composableBuilder(
    column: $table.verificationStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get facilityId => $composableBuilder(
    column: $table.facilityId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastVerifiedAt => $composableBuilder(
    column: $table.lastVerifiedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get evidenceHash => $composableBuilder(
    column: $table.evidenceHash,
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
                Value<int> distanceMeters = const Value.absent(),
                Value<String> edgeType = const Value.absent(),
                Value<String> servicePattern = const Value.absent(),
                Value<bool> includesStairs = const Value.absent(),
                Value<String> stairAccessState = const Value.absent(),
                Value<String> accessibilityStatus = const Value.absent(),
                Value<int> reliabilityScore = const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<String> sourceSnapshotId = const Value.absent(),
                Value<String> providerRecordHash = const Value.absent(),
                Value<String> provenanceKind = const Value.absent(),
                Value<String> verificationStatus = const Value.absent(),
                Value<String?> facilityId = const Value.absent(),
                Value<DateTime?> lastVerifiedAt = const Value.absent(),
                Value<String> evidenceHash = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NetworkEdgesCompanion(
                id: id,
                fromNodeId: fromNodeId,
                toNodeId: toNodeId,
                durationSeconds: durationSeconds,
                distanceMeters: distanceMeters,
                edgeType: edgeType,
                servicePattern: servicePattern,
                includesStairs: includesStairs,
                stairAccessState: stairAccessState,
                accessibilityStatus: accessibilityStatus,
                reliabilityScore: reliabilityScore,
                sourceId: sourceId,
                sourceSnapshotId: sourceSnapshotId,
                providerRecordHash: providerRecordHash,
                provenanceKind: provenanceKind,
                verificationStatus: verificationStatus,
                facilityId: facilityId,
                lastVerifiedAt: lastVerifiedAt,
                evidenceHash: evidenceHash,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String fromNodeId,
                required String toNodeId,
                Value<int> durationSeconds = const Value.absent(),
                Value<int> distanceMeters = const Value.absent(),
                Value<String> edgeType = const Value.absent(),
                Value<String> servicePattern = const Value.absent(),
                Value<bool> includesStairs = const Value.absent(),
                Value<String> stairAccessState = const Value.absent(),
                Value<String> accessibilityStatus = const Value.absent(),
                Value<int> reliabilityScore = const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<String> sourceSnapshotId = const Value.absent(),
                Value<String> providerRecordHash = const Value.absent(),
                Value<String> provenanceKind = const Value.absent(),
                Value<String> verificationStatus = const Value.absent(),
                Value<String?> facilityId = const Value.absent(),
                Value<DateTime?> lastVerifiedAt = const Value.absent(),
                Value<String> evidenceHash = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NetworkEdgesCompanion.insert(
                id: id,
                fromNodeId: fromNodeId,
                toNodeId: toNodeId,
                durationSeconds: durationSeconds,
                distanceMeters: distanceMeters,
                edgeType: edgeType,
                servicePattern: servicePattern,
                includesStairs: includesStairs,
                stairAccessState: stairAccessState,
                accessibilityStatus: accessibilityStatus,
                reliabilityScore: reliabilityScore,
                sourceId: sourceId,
                sourceSnapshotId: sourceSnapshotId,
                providerRecordHash: providerRecordHash,
                provenanceKind: provenanceKind,
                verificationStatus: verificationStatus,
                facilityId: facilityId,
                lastVerifiedAt: lastVerifiedAt,
                evidenceHash: evidenceHash,
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
      Value<String> sourceId,
      Value<String> sourceSnapshotId,
      Value<String> providerFacilityRef,
      Value<String> providerRecordHash,
      Value<String> provenanceKind,
      Value<DateTime?> verifiedAt,
      Value<DateTime?> retrievedAt,
      Value<String> evidenceHash,
      Value<String> statusMeaning,
      Value<String> operationalStatus,
      Value<String> installationStatus,
      Value<int> confidence,
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
      Value<String> sourceId,
      Value<String> sourceSnapshotId,
      Value<String> providerFacilityRef,
      Value<String> providerRecordHash,
      Value<String> provenanceKind,
      Value<DateTime?> verifiedAt,
      Value<DateTime?> retrievedAt,
      Value<String> evidenceHash,
      Value<String> statusMeaning,
      Value<String> operationalStatus,
      Value<String> installationStatus,
      Value<int> confidence,
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

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceSnapshotId => $composableBuilder(
    column: $table.sourceSnapshotId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get providerFacilityRef => $composableBuilder(
    column: $table.providerFacilityRef,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get providerRecordHash => $composableBuilder(
    column: $table.providerRecordHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get provenanceKind => $composableBuilder(
    column: $table.provenanceKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get verifiedAt => $composableBuilder(
    column: $table.verifiedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get retrievedAt => $composableBuilder(
    column: $table.retrievedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get evidenceHash => $composableBuilder(
    column: $table.evidenceHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get statusMeaning => $composableBuilder(
    column: $table.statusMeaning,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operationalStatus => $composableBuilder(
    column: $table.operationalStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get installationStatus => $composableBuilder(
    column: $table.installationStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get confidence => $composableBuilder(
    column: $table.confidence,
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

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceSnapshotId => $composableBuilder(
    column: $table.sourceSnapshotId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get providerFacilityRef => $composableBuilder(
    column: $table.providerFacilityRef,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get providerRecordHash => $composableBuilder(
    column: $table.providerRecordHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get provenanceKind => $composableBuilder(
    column: $table.provenanceKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get verifiedAt => $composableBuilder(
    column: $table.verifiedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get retrievedAt => $composableBuilder(
    column: $table.retrievedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get evidenceHash => $composableBuilder(
    column: $table.evidenceHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get statusMeaning => $composableBuilder(
    column: $table.statusMeaning,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operationalStatus => $composableBuilder(
    column: $table.operationalStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get installationStatus => $composableBuilder(
    column: $table.installationStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get confidence => $composableBuilder(
    column: $table.confidence,
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

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get sourceSnapshotId => $composableBuilder(
    column: $table.sourceSnapshotId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get providerFacilityRef => $composableBuilder(
    column: $table.providerFacilityRef,
    builder: (column) => column,
  );

  GeneratedColumn<String> get providerRecordHash => $composableBuilder(
    column: $table.providerRecordHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get provenanceKind => $composableBuilder(
    column: $table.provenanceKind,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get verifiedAt => $composableBuilder(
    column: $table.verifiedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get retrievedAt => $composableBuilder(
    column: $table.retrievedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get evidenceHash => $composableBuilder(
    column: $table.evidenceHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get statusMeaning => $composableBuilder(
    column: $table.statusMeaning,
    builder: (column) => column,
  );

  GeneratedColumn<String> get operationalStatus => $composableBuilder(
    column: $table.operationalStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get installationStatus => $composableBuilder(
    column: $table.installationStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get confidence => $composableBuilder(
    column: $table.confidence,
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
                Value<String> sourceId = const Value.absent(),
                Value<String> sourceSnapshotId = const Value.absent(),
                Value<String> providerFacilityRef = const Value.absent(),
                Value<String> providerRecordHash = const Value.absent(),
                Value<String> provenanceKind = const Value.absent(),
                Value<DateTime?> verifiedAt = const Value.absent(),
                Value<DateTime?> retrievedAt = const Value.absent(),
                Value<String> evidenceHash = const Value.absent(),
                Value<String> statusMeaning = const Value.absent(),
                Value<String> operationalStatus = const Value.absent(),
                Value<String> installationStatus = const Value.absent(),
                Value<int> confidence = const Value.absent(),
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
                sourceId: sourceId,
                sourceSnapshotId: sourceSnapshotId,
                providerFacilityRef: providerFacilityRef,
                providerRecordHash: providerRecordHash,
                provenanceKind: provenanceKind,
                verifiedAt: verifiedAt,
                retrievedAt: retrievedAt,
                evidenceHash: evidenceHash,
                statusMeaning: statusMeaning,
                operationalStatus: operationalStatus,
                installationStatus: installationStatus,
                confidence: confidence,
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
                Value<String> sourceId = const Value.absent(),
                Value<String> sourceSnapshotId = const Value.absent(),
                Value<String> providerFacilityRef = const Value.absent(),
                Value<String> providerRecordHash = const Value.absent(),
                Value<String> provenanceKind = const Value.absent(),
                Value<DateTime?> verifiedAt = const Value.absent(),
                Value<DateTime?> retrievedAt = const Value.absent(),
                Value<String> evidenceHash = const Value.absent(),
                Value<String> statusMeaning = const Value.absent(),
                Value<String> operationalStatus = const Value.absent(),
                Value<String> installationStatus = const Value.absent(),
                Value<int> confidence = const Value.absent(),
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
                sourceId: sourceId,
                sourceSnapshotId: sourceSnapshotId,
                providerFacilityRef: providerFacilityRef,
                providerRecordHash: providerRecordHash,
                provenanceKind: provenanceKind,
                verifiedAt: verifiedAt,
                retrievedAt: retrievedAt,
                evidenceHash: evidenceHash,
                statusMeaning: statusMeaning,
                operationalStatus: operationalStatus,
                installationStatus: installationStatus,
                confidence: confidence,
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
typedef $$StationFacilityEvidenceTableCreateCompanionBuilder =
    StationFacilityEvidenceCompanion Function({
      required String stationId,
      required String lineId,
      required String facilityType,
      required String evidenceKind,
      required String sourceId,
      required String sourceSnapshotId,
      required String providerRecordHash,
      required String evidenceHash,
      required String provenanceKind,
      Value<String> installationStatus,
      Value<String> operationalStatus,
      Value<String> statusMeaning,
      Value<int> confidence,
      Value<DateTime?> verifiedAt,
      Value<DateTime?> retrievedAt,
      Value<bool> strictRouteEligible,
      Value<String> strictRouteEligibleReason,
      Value<int> rowid,
    });
typedef $$StationFacilityEvidenceTableUpdateCompanionBuilder =
    StationFacilityEvidenceCompanion Function({
      Value<String> stationId,
      Value<String> lineId,
      Value<String> facilityType,
      Value<String> evidenceKind,
      Value<String> sourceId,
      Value<String> sourceSnapshotId,
      Value<String> providerRecordHash,
      Value<String> evidenceHash,
      Value<String> provenanceKind,
      Value<String> installationStatus,
      Value<String> operationalStatus,
      Value<String> statusMeaning,
      Value<int> confidence,
      Value<DateTime?> verifiedAt,
      Value<DateTime?> retrievedAt,
      Value<bool> strictRouteEligible,
      Value<String> strictRouteEligibleReason,
      Value<int> rowid,
    });

class $$StationFacilityEvidenceTableFilterComposer
    extends Composer<_$CatalogDatabase, $StationFacilityEvidenceTable> {
  $$StationFacilityEvidenceTableFilterComposer({
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

  ColumnFilters<String> get facilityType => $composableBuilder(
    column: $table.facilityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get evidenceKind => $composableBuilder(
    column: $table.evidenceKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceSnapshotId => $composableBuilder(
    column: $table.sourceSnapshotId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get providerRecordHash => $composableBuilder(
    column: $table.providerRecordHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get evidenceHash => $composableBuilder(
    column: $table.evidenceHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get provenanceKind => $composableBuilder(
    column: $table.provenanceKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get installationStatus => $composableBuilder(
    column: $table.installationStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operationalStatus => $composableBuilder(
    column: $table.operationalStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get statusMeaning => $composableBuilder(
    column: $table.statusMeaning,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get verifiedAt => $composableBuilder(
    column: $table.verifiedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get retrievedAt => $composableBuilder(
    column: $table.retrievedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get strictRouteEligible => $composableBuilder(
    column: $table.strictRouteEligible,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get strictRouteEligibleReason => $composableBuilder(
    column: $table.strictRouteEligibleReason,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StationFacilityEvidenceTableOrderingComposer
    extends Composer<_$CatalogDatabase, $StationFacilityEvidenceTable> {
  $$StationFacilityEvidenceTableOrderingComposer({
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

  ColumnOrderings<String> get facilityType => $composableBuilder(
    column: $table.facilityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get evidenceKind => $composableBuilder(
    column: $table.evidenceKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceSnapshotId => $composableBuilder(
    column: $table.sourceSnapshotId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get providerRecordHash => $composableBuilder(
    column: $table.providerRecordHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get evidenceHash => $composableBuilder(
    column: $table.evidenceHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get provenanceKind => $composableBuilder(
    column: $table.provenanceKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get installationStatus => $composableBuilder(
    column: $table.installationStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operationalStatus => $composableBuilder(
    column: $table.operationalStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get statusMeaning => $composableBuilder(
    column: $table.statusMeaning,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get verifiedAt => $composableBuilder(
    column: $table.verifiedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get retrievedAt => $composableBuilder(
    column: $table.retrievedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get strictRouteEligible => $composableBuilder(
    column: $table.strictRouteEligible,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get strictRouteEligibleReason => $composableBuilder(
    column: $table.strictRouteEligibleReason,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StationFacilityEvidenceTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $StationFacilityEvidenceTable> {
  $$StationFacilityEvidenceTableAnnotationComposer({
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

  GeneratedColumn<String> get facilityType => $composableBuilder(
    column: $table.facilityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get evidenceKind => $composableBuilder(
    column: $table.evidenceKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get sourceSnapshotId => $composableBuilder(
    column: $table.sourceSnapshotId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get providerRecordHash => $composableBuilder(
    column: $table.providerRecordHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get evidenceHash => $composableBuilder(
    column: $table.evidenceHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get provenanceKind => $composableBuilder(
    column: $table.provenanceKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get installationStatus => $composableBuilder(
    column: $table.installationStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get operationalStatus => $composableBuilder(
    column: $table.operationalStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get statusMeaning => $composableBuilder(
    column: $table.statusMeaning,
    builder: (column) => column,
  );

  GeneratedColumn<int> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get verifiedAt => $composableBuilder(
    column: $table.verifiedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get retrievedAt => $composableBuilder(
    column: $table.retrievedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get strictRouteEligible => $composableBuilder(
    column: $table.strictRouteEligible,
    builder: (column) => column,
  );

  GeneratedColumn<String> get strictRouteEligibleReason => $composableBuilder(
    column: $table.strictRouteEligibleReason,
    builder: (column) => column,
  );
}

class $$StationFacilityEvidenceTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $StationFacilityEvidenceTable,
          StationFacilityEvidenceData,
          $$StationFacilityEvidenceTableFilterComposer,
          $$StationFacilityEvidenceTableOrderingComposer,
          $$StationFacilityEvidenceTableAnnotationComposer,
          $$StationFacilityEvidenceTableCreateCompanionBuilder,
          $$StationFacilityEvidenceTableUpdateCompanionBuilder,
          (
            StationFacilityEvidenceData,
            BaseReferences<
              _$CatalogDatabase,
              $StationFacilityEvidenceTable,
              StationFacilityEvidenceData
            >,
          ),
          StationFacilityEvidenceData,
          PrefetchHooks Function()
        > {
  $$StationFacilityEvidenceTableTableManager(
    _$CatalogDatabase db,
    $StationFacilityEvidenceTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StationFacilityEvidenceTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$StationFacilityEvidenceTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$StationFacilityEvidenceTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> stationId = const Value.absent(),
                Value<String> lineId = const Value.absent(),
                Value<String> facilityType = const Value.absent(),
                Value<String> evidenceKind = const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<String> sourceSnapshotId = const Value.absent(),
                Value<String> providerRecordHash = const Value.absent(),
                Value<String> evidenceHash = const Value.absent(),
                Value<String> provenanceKind = const Value.absent(),
                Value<String> installationStatus = const Value.absent(),
                Value<String> operationalStatus = const Value.absent(),
                Value<String> statusMeaning = const Value.absent(),
                Value<int> confidence = const Value.absent(),
                Value<DateTime?> verifiedAt = const Value.absent(),
                Value<DateTime?> retrievedAt = const Value.absent(),
                Value<bool> strictRouteEligible = const Value.absent(),
                Value<String> strictRouteEligibleReason = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StationFacilityEvidenceCompanion(
                stationId: stationId,
                lineId: lineId,
                facilityType: facilityType,
                evidenceKind: evidenceKind,
                sourceId: sourceId,
                sourceSnapshotId: sourceSnapshotId,
                providerRecordHash: providerRecordHash,
                evidenceHash: evidenceHash,
                provenanceKind: provenanceKind,
                installationStatus: installationStatus,
                operationalStatus: operationalStatus,
                statusMeaning: statusMeaning,
                confidence: confidence,
                verifiedAt: verifiedAt,
                retrievedAt: retrievedAt,
                strictRouteEligible: strictRouteEligible,
                strictRouteEligibleReason: strictRouteEligibleReason,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String stationId,
                required String lineId,
                required String facilityType,
                required String evidenceKind,
                required String sourceId,
                required String sourceSnapshotId,
                required String providerRecordHash,
                required String evidenceHash,
                required String provenanceKind,
                Value<String> installationStatus = const Value.absent(),
                Value<String> operationalStatus = const Value.absent(),
                Value<String> statusMeaning = const Value.absent(),
                Value<int> confidence = const Value.absent(),
                Value<DateTime?> verifiedAt = const Value.absent(),
                Value<DateTime?> retrievedAt = const Value.absent(),
                Value<bool> strictRouteEligible = const Value.absent(),
                Value<String> strictRouteEligibleReason = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StationFacilityEvidenceCompanion.insert(
                stationId: stationId,
                lineId: lineId,
                facilityType: facilityType,
                evidenceKind: evidenceKind,
                sourceId: sourceId,
                sourceSnapshotId: sourceSnapshotId,
                providerRecordHash: providerRecordHash,
                evidenceHash: evidenceHash,
                provenanceKind: provenanceKind,
                installationStatus: installationStatus,
                operationalStatus: operationalStatus,
                statusMeaning: statusMeaning,
                confidence: confidence,
                verifiedAt: verifiedAt,
                retrievedAt: retrievedAt,
                strictRouteEligible: strictRouteEligible,
                strictRouteEligibleReason: strictRouteEligibleReason,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StationFacilityEvidenceTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $StationFacilityEvidenceTable,
      StationFacilityEvidenceData,
      $$StationFacilityEvidenceTableFilterComposer,
      $$StationFacilityEvidenceTableOrderingComposer,
      $$StationFacilityEvidenceTableAnnotationComposer,
      $$StationFacilityEvidenceTableCreateCompanionBuilder,
      $$StationFacilityEvidenceTableUpdateCompanionBuilder,
      (
        StationFacilityEvidenceData,
        BaseReferences<
          _$CatalogDatabase,
          $StationFacilityEvidenceTable,
          StationFacilityEvidenceData
        >,
      ),
      StationFacilityEvidenceData,
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
      Value<String> edgeType,
      Value<int> distanceMeters,
      Value<int> durationSeconds,
      Value<bool> includesStairs,
      Value<bool> requiresElevator,
      Value<bool> requiresEscalator,
      Value<int> slopeLevel,
      Value<int> widthLevel,
      Value<int> reliabilityScore,
      Value<String> accessibilityStatus,
      Value<String> sourceId,
      Value<String> sourceSnapshotId,
      Value<String> providerRecordHash,
      Value<String> provenanceKind,
      Value<String> verificationStatus,
      Value<String?> facilityId,
      Value<DateTime?> lastVerifiedAt,
      Value<String> evidenceHash,
      Value<String> instruction,
      Value<int> rowid,
    });
typedef $$InternalRouteEdgesTableUpdateCompanionBuilder =
    InternalRouteEdgesCompanion Function({
      Value<String> id,
      Value<String> fromNodeId,
      Value<String> toNodeId,
      Value<String> edgeType,
      Value<int> distanceMeters,
      Value<int> durationSeconds,
      Value<bool> includesStairs,
      Value<bool> requiresElevator,
      Value<bool> requiresEscalator,
      Value<int> slopeLevel,
      Value<int> widthLevel,
      Value<int> reliabilityScore,
      Value<String> accessibilityStatus,
      Value<String> sourceId,
      Value<String> sourceSnapshotId,
      Value<String> providerRecordHash,
      Value<String> provenanceKind,
      Value<String> verificationStatus,
      Value<String?> facilityId,
      Value<DateTime?> lastVerifiedAt,
      Value<String> evidenceHash,
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

  ColumnFilters<String> get edgeType => $composableBuilder(
    column: $table.edgeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get distanceMeters => $composableBuilder(
    column: $table.distanceMeters,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get includesStairs => $composableBuilder(
    column: $table.includesStairs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get requiresElevator => $composableBuilder(
    column: $table.requiresElevator,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get requiresEscalator => $composableBuilder(
    column: $table.requiresEscalator,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get slopeLevel => $composableBuilder(
    column: $table.slopeLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get widthLevel => $composableBuilder(
    column: $table.widthLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reliabilityScore => $composableBuilder(
    column: $table.reliabilityScore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accessibilityStatus => $composableBuilder(
    column: $table.accessibilityStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceSnapshotId => $composableBuilder(
    column: $table.sourceSnapshotId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get providerRecordHash => $composableBuilder(
    column: $table.providerRecordHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get provenanceKind => $composableBuilder(
    column: $table.provenanceKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get verificationStatus => $composableBuilder(
    column: $table.verificationStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get facilityId => $composableBuilder(
    column: $table.facilityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastVerifiedAt => $composableBuilder(
    column: $table.lastVerifiedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get evidenceHash => $composableBuilder(
    column: $table.evidenceHash,
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

  ColumnOrderings<String> get edgeType => $composableBuilder(
    column: $table.edgeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get distanceMeters => $composableBuilder(
    column: $table.distanceMeters,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get includesStairs => $composableBuilder(
    column: $table.includesStairs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get requiresElevator => $composableBuilder(
    column: $table.requiresElevator,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get requiresEscalator => $composableBuilder(
    column: $table.requiresEscalator,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get slopeLevel => $composableBuilder(
    column: $table.slopeLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get widthLevel => $composableBuilder(
    column: $table.widthLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reliabilityScore => $composableBuilder(
    column: $table.reliabilityScore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accessibilityStatus => $composableBuilder(
    column: $table.accessibilityStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceSnapshotId => $composableBuilder(
    column: $table.sourceSnapshotId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get providerRecordHash => $composableBuilder(
    column: $table.providerRecordHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get provenanceKind => $composableBuilder(
    column: $table.provenanceKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get verificationStatus => $composableBuilder(
    column: $table.verificationStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get facilityId => $composableBuilder(
    column: $table.facilityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastVerifiedAt => $composableBuilder(
    column: $table.lastVerifiedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get evidenceHash => $composableBuilder(
    column: $table.evidenceHash,
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

  GeneratedColumn<String> get edgeType =>
      $composableBuilder(column: $table.edgeType, builder: (column) => column);

  GeneratedColumn<int> get distanceMeters => $composableBuilder(
    column: $table.distanceMeters,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get includesStairs => $composableBuilder(
    column: $table.includesStairs,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get requiresElevator => $composableBuilder(
    column: $table.requiresElevator,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get requiresEscalator => $composableBuilder(
    column: $table.requiresEscalator,
    builder: (column) => column,
  );

  GeneratedColumn<int> get slopeLevel => $composableBuilder(
    column: $table.slopeLevel,
    builder: (column) => column,
  );

  GeneratedColumn<int> get widthLevel => $composableBuilder(
    column: $table.widthLevel,
    builder: (column) => column,
  );

  GeneratedColumn<int> get reliabilityScore => $composableBuilder(
    column: $table.reliabilityScore,
    builder: (column) => column,
  );

  GeneratedColumn<String> get accessibilityStatus => $composableBuilder(
    column: $table.accessibilityStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get sourceSnapshotId => $composableBuilder(
    column: $table.sourceSnapshotId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get providerRecordHash => $composableBuilder(
    column: $table.providerRecordHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get provenanceKind => $composableBuilder(
    column: $table.provenanceKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get verificationStatus => $composableBuilder(
    column: $table.verificationStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get facilityId => $composableBuilder(
    column: $table.facilityId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastVerifiedAt => $composableBuilder(
    column: $table.lastVerifiedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get evidenceHash => $composableBuilder(
    column: $table.evidenceHash,
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
                Value<String> edgeType = const Value.absent(),
                Value<int> distanceMeters = const Value.absent(),
                Value<int> durationSeconds = const Value.absent(),
                Value<bool> includesStairs = const Value.absent(),
                Value<bool> requiresElevator = const Value.absent(),
                Value<bool> requiresEscalator = const Value.absent(),
                Value<int> slopeLevel = const Value.absent(),
                Value<int> widthLevel = const Value.absent(),
                Value<int> reliabilityScore = const Value.absent(),
                Value<String> accessibilityStatus = const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<String> sourceSnapshotId = const Value.absent(),
                Value<String> providerRecordHash = const Value.absent(),
                Value<String> provenanceKind = const Value.absent(),
                Value<String> verificationStatus = const Value.absent(),
                Value<String?> facilityId = const Value.absent(),
                Value<DateTime?> lastVerifiedAt = const Value.absent(),
                Value<String> evidenceHash = const Value.absent(),
                Value<String> instruction = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InternalRouteEdgesCompanion(
                id: id,
                fromNodeId: fromNodeId,
                toNodeId: toNodeId,
                edgeType: edgeType,
                distanceMeters: distanceMeters,
                durationSeconds: durationSeconds,
                includesStairs: includesStairs,
                requiresElevator: requiresElevator,
                requiresEscalator: requiresEscalator,
                slopeLevel: slopeLevel,
                widthLevel: widthLevel,
                reliabilityScore: reliabilityScore,
                accessibilityStatus: accessibilityStatus,
                sourceId: sourceId,
                sourceSnapshotId: sourceSnapshotId,
                providerRecordHash: providerRecordHash,
                provenanceKind: provenanceKind,
                verificationStatus: verificationStatus,
                facilityId: facilityId,
                lastVerifiedAt: lastVerifiedAt,
                evidenceHash: evidenceHash,
                instruction: instruction,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String fromNodeId,
                required String toNodeId,
                Value<String> edgeType = const Value.absent(),
                Value<int> distanceMeters = const Value.absent(),
                Value<int> durationSeconds = const Value.absent(),
                Value<bool> includesStairs = const Value.absent(),
                Value<bool> requiresElevator = const Value.absent(),
                Value<bool> requiresEscalator = const Value.absent(),
                Value<int> slopeLevel = const Value.absent(),
                Value<int> widthLevel = const Value.absent(),
                Value<int> reliabilityScore = const Value.absent(),
                Value<String> accessibilityStatus = const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<String> sourceSnapshotId = const Value.absent(),
                Value<String> providerRecordHash = const Value.absent(),
                Value<String> provenanceKind = const Value.absent(),
                Value<String> verificationStatus = const Value.absent(),
                Value<String?> facilityId = const Value.absent(),
                Value<DateTime?> lastVerifiedAt = const Value.absent(),
                Value<String> evidenceHash = const Value.absent(),
                Value<String> instruction = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InternalRouteEdgesCompanion.insert(
                id: id,
                fromNodeId: fromNodeId,
                toNodeId: toNodeId,
                edgeType: edgeType,
                distanceMeters: distanceMeters,
                durationSeconds: durationSeconds,
                includesStairs: includesStairs,
                requiresElevator: requiresElevator,
                requiresEscalator: requiresEscalator,
                slopeLevel: slopeLevel,
                widthLevel: widthLevel,
                reliabilityScore: reliabilityScore,
                accessibilityStatus: accessibilityStatus,
                sourceId: sourceId,
                sourceSnapshotId: sourceSnapshotId,
                providerRecordHash: providerRecordHash,
                provenanceKind: provenanceKind,
                verificationStatus: verificationStatus,
                facilityId: facilityId,
                lastVerifiedAt: lastVerifiedAt,
                evidenceHash: evidenceHash,
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
typedef $$StationPathwayNodesTableCreateCompanionBuilder =
    StationPathwayNodesCompanion Function({
      required String id,
      required String stationId,
      Value<String?> lineId,
      required String nodeType,
      required String label,
      Value<String> level,
      Value<String> legacyInternalRouteNodeId,
      Value<int> rowid,
    });
typedef $$StationPathwayNodesTableUpdateCompanionBuilder =
    StationPathwayNodesCompanion Function({
      Value<String> id,
      Value<String> stationId,
      Value<String?> lineId,
      Value<String> nodeType,
      Value<String> label,
      Value<String> level,
      Value<String> legacyInternalRouteNodeId,
      Value<int> rowid,
    });

class $$StationPathwayNodesTableFilterComposer
    extends Composer<_$CatalogDatabase, $StationPathwayNodesTable> {
  $$StationPathwayNodesTableFilterComposer({
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

  ColumnFilters<String> get lineId => $composableBuilder(
    column: $table.lineId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nodeType => $composableBuilder(
    column: $table.nodeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get legacyInternalRouteNodeId => $composableBuilder(
    column: $table.legacyInternalRouteNodeId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StationPathwayNodesTableOrderingComposer
    extends Composer<_$CatalogDatabase, $StationPathwayNodesTable> {
  $$StationPathwayNodesTableOrderingComposer({
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

  ColumnOrderings<String> get lineId => $composableBuilder(
    column: $table.lineId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nodeType => $composableBuilder(
    column: $table.nodeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get legacyInternalRouteNodeId => $composableBuilder(
    column: $table.legacyInternalRouteNodeId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StationPathwayNodesTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $StationPathwayNodesTable> {
  $$StationPathwayNodesTableAnnotationComposer({
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

  GeneratedColumn<String> get lineId =>
      $composableBuilder(column: $table.lineId, builder: (column) => column);

  GeneratedColumn<String> get nodeType =>
      $composableBuilder(column: $table.nodeType, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get level =>
      $composableBuilder(column: $table.level, builder: (column) => column);

  GeneratedColumn<String> get legacyInternalRouteNodeId => $composableBuilder(
    column: $table.legacyInternalRouteNodeId,
    builder: (column) => column,
  );
}

class $$StationPathwayNodesTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $StationPathwayNodesTable,
          StationPathwayNode,
          $$StationPathwayNodesTableFilterComposer,
          $$StationPathwayNodesTableOrderingComposer,
          $$StationPathwayNodesTableAnnotationComposer,
          $$StationPathwayNodesTableCreateCompanionBuilder,
          $$StationPathwayNodesTableUpdateCompanionBuilder,
          (
            StationPathwayNode,
            BaseReferences<
              _$CatalogDatabase,
              $StationPathwayNodesTable,
              StationPathwayNode
            >,
          ),
          StationPathwayNode,
          PrefetchHooks Function()
        > {
  $$StationPathwayNodesTableTableManager(
    _$CatalogDatabase db,
    $StationPathwayNodesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StationPathwayNodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StationPathwayNodesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$StationPathwayNodesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> stationId = const Value.absent(),
                Value<String?> lineId = const Value.absent(),
                Value<String> nodeType = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<String> level = const Value.absent(),
                Value<String> legacyInternalRouteNodeId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StationPathwayNodesCompanion(
                id: id,
                stationId: stationId,
                lineId: lineId,
                nodeType: nodeType,
                label: label,
                level: level,
                legacyInternalRouteNodeId: legacyInternalRouteNodeId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String stationId,
                Value<String?> lineId = const Value.absent(),
                required String nodeType,
                required String label,
                Value<String> level = const Value.absent(),
                Value<String> legacyInternalRouteNodeId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StationPathwayNodesCompanion.insert(
                id: id,
                stationId: stationId,
                lineId: lineId,
                nodeType: nodeType,
                label: label,
                level: level,
                legacyInternalRouteNodeId: legacyInternalRouteNodeId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StationPathwayNodesTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $StationPathwayNodesTable,
      StationPathwayNode,
      $$StationPathwayNodesTableFilterComposer,
      $$StationPathwayNodesTableOrderingComposer,
      $$StationPathwayNodesTableAnnotationComposer,
      $$StationPathwayNodesTableCreateCompanionBuilder,
      $$StationPathwayNodesTableUpdateCompanionBuilder,
      (
        StationPathwayNode,
        BaseReferences<
          _$CatalogDatabase,
          $StationPathwayNodesTable,
          StationPathwayNode
        >,
      ),
      StationPathwayNode,
      PrefetchHooks Function()
    >;
typedef $$StationPathwayEdgesTableCreateCompanionBuilder =
    StationPathwayEdgesCompanion Function({
      required String id,
      required String fromNodeId,
      required String toNodeId,
      Value<String> edgeType,
      Value<int> durationSeconds,
      Value<int> distanceMeters,
      Value<bool> bidirectional,
      Value<bool> includesStairs,
      Value<bool> requiresElevator,
      Value<bool> requiresEscalator,
      Value<String> levelFrom,
      Value<String> levelTo,
      Value<String?> requiresFacilityId,
      Value<int?> minWidthCm,
      Value<double?> slopePercent,
      Value<double?> verticalMeters,
      Value<int> reliabilityScore,
      Value<String> accessibilityStatus,
      Value<String> sourceId,
      Value<String> sourceSnapshotId,
      Value<String> providerRecordHash,
      Value<String> provenanceKind,
      Value<String> verificationStatus,
      Value<DateTime?> lastVerifiedAt,
      Value<String> evidenceHash,
      Value<String> instruction,
      Value<String> legacyInternalRouteEdgeId,
      Value<int> rowid,
    });
typedef $$StationPathwayEdgesTableUpdateCompanionBuilder =
    StationPathwayEdgesCompanion Function({
      Value<String> id,
      Value<String> fromNodeId,
      Value<String> toNodeId,
      Value<String> edgeType,
      Value<int> durationSeconds,
      Value<int> distanceMeters,
      Value<bool> bidirectional,
      Value<bool> includesStairs,
      Value<bool> requiresElevator,
      Value<bool> requiresEscalator,
      Value<String> levelFrom,
      Value<String> levelTo,
      Value<String?> requiresFacilityId,
      Value<int?> minWidthCm,
      Value<double?> slopePercent,
      Value<double?> verticalMeters,
      Value<int> reliabilityScore,
      Value<String> accessibilityStatus,
      Value<String> sourceId,
      Value<String> sourceSnapshotId,
      Value<String> providerRecordHash,
      Value<String> provenanceKind,
      Value<String> verificationStatus,
      Value<DateTime?> lastVerifiedAt,
      Value<String> evidenceHash,
      Value<String> instruction,
      Value<String> legacyInternalRouteEdgeId,
      Value<int> rowid,
    });

class $$StationPathwayEdgesTableFilterComposer
    extends Composer<_$CatalogDatabase, $StationPathwayEdgesTable> {
  $$StationPathwayEdgesTableFilterComposer({
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

  ColumnFilters<String> get edgeType => $composableBuilder(
    column: $table.edgeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get distanceMeters => $composableBuilder(
    column: $table.distanceMeters,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get bidirectional => $composableBuilder(
    column: $table.bidirectional,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get includesStairs => $composableBuilder(
    column: $table.includesStairs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get requiresElevator => $composableBuilder(
    column: $table.requiresElevator,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get requiresEscalator => $composableBuilder(
    column: $table.requiresEscalator,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get levelFrom => $composableBuilder(
    column: $table.levelFrom,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get levelTo => $composableBuilder(
    column: $table.levelTo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get requiresFacilityId => $composableBuilder(
    column: $table.requiresFacilityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get minWidthCm => $composableBuilder(
    column: $table.minWidthCm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get slopePercent => $composableBuilder(
    column: $table.slopePercent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get verticalMeters => $composableBuilder(
    column: $table.verticalMeters,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reliabilityScore => $composableBuilder(
    column: $table.reliabilityScore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accessibilityStatus => $composableBuilder(
    column: $table.accessibilityStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceSnapshotId => $composableBuilder(
    column: $table.sourceSnapshotId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get providerRecordHash => $composableBuilder(
    column: $table.providerRecordHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get provenanceKind => $composableBuilder(
    column: $table.provenanceKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get verificationStatus => $composableBuilder(
    column: $table.verificationStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastVerifiedAt => $composableBuilder(
    column: $table.lastVerifiedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get evidenceHash => $composableBuilder(
    column: $table.evidenceHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get instruction => $composableBuilder(
    column: $table.instruction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get legacyInternalRouteEdgeId => $composableBuilder(
    column: $table.legacyInternalRouteEdgeId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StationPathwayEdgesTableOrderingComposer
    extends Composer<_$CatalogDatabase, $StationPathwayEdgesTable> {
  $$StationPathwayEdgesTableOrderingComposer({
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

  ColumnOrderings<String> get edgeType => $composableBuilder(
    column: $table.edgeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get distanceMeters => $composableBuilder(
    column: $table.distanceMeters,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get bidirectional => $composableBuilder(
    column: $table.bidirectional,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get includesStairs => $composableBuilder(
    column: $table.includesStairs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get requiresElevator => $composableBuilder(
    column: $table.requiresElevator,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get requiresEscalator => $composableBuilder(
    column: $table.requiresEscalator,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get levelFrom => $composableBuilder(
    column: $table.levelFrom,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get levelTo => $composableBuilder(
    column: $table.levelTo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get requiresFacilityId => $composableBuilder(
    column: $table.requiresFacilityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get minWidthCm => $composableBuilder(
    column: $table.minWidthCm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get slopePercent => $composableBuilder(
    column: $table.slopePercent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get verticalMeters => $composableBuilder(
    column: $table.verticalMeters,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reliabilityScore => $composableBuilder(
    column: $table.reliabilityScore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accessibilityStatus => $composableBuilder(
    column: $table.accessibilityStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceSnapshotId => $composableBuilder(
    column: $table.sourceSnapshotId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get providerRecordHash => $composableBuilder(
    column: $table.providerRecordHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get provenanceKind => $composableBuilder(
    column: $table.provenanceKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get verificationStatus => $composableBuilder(
    column: $table.verificationStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastVerifiedAt => $composableBuilder(
    column: $table.lastVerifiedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get evidenceHash => $composableBuilder(
    column: $table.evidenceHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get instruction => $composableBuilder(
    column: $table.instruction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get legacyInternalRouteEdgeId => $composableBuilder(
    column: $table.legacyInternalRouteEdgeId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StationPathwayEdgesTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $StationPathwayEdgesTable> {
  $$StationPathwayEdgesTableAnnotationComposer({
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

  GeneratedColumn<String> get edgeType =>
      $composableBuilder(column: $table.edgeType, builder: (column) => column);

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<int> get distanceMeters => $composableBuilder(
    column: $table.distanceMeters,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get bidirectional => $composableBuilder(
    column: $table.bidirectional,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get includesStairs => $composableBuilder(
    column: $table.includesStairs,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get requiresElevator => $composableBuilder(
    column: $table.requiresElevator,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get requiresEscalator => $composableBuilder(
    column: $table.requiresEscalator,
    builder: (column) => column,
  );

  GeneratedColumn<String> get levelFrom =>
      $composableBuilder(column: $table.levelFrom, builder: (column) => column);

  GeneratedColumn<String> get levelTo =>
      $composableBuilder(column: $table.levelTo, builder: (column) => column);

  GeneratedColumn<String> get requiresFacilityId => $composableBuilder(
    column: $table.requiresFacilityId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get minWidthCm => $composableBuilder(
    column: $table.minWidthCm,
    builder: (column) => column,
  );

  GeneratedColumn<double> get slopePercent => $composableBuilder(
    column: $table.slopePercent,
    builder: (column) => column,
  );

  GeneratedColumn<double> get verticalMeters => $composableBuilder(
    column: $table.verticalMeters,
    builder: (column) => column,
  );

  GeneratedColumn<int> get reliabilityScore => $composableBuilder(
    column: $table.reliabilityScore,
    builder: (column) => column,
  );

  GeneratedColumn<String> get accessibilityStatus => $composableBuilder(
    column: $table.accessibilityStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get sourceSnapshotId => $composableBuilder(
    column: $table.sourceSnapshotId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get providerRecordHash => $composableBuilder(
    column: $table.providerRecordHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get provenanceKind => $composableBuilder(
    column: $table.provenanceKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get verificationStatus => $composableBuilder(
    column: $table.verificationStatus,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastVerifiedAt => $composableBuilder(
    column: $table.lastVerifiedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get evidenceHash => $composableBuilder(
    column: $table.evidenceHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get instruction => $composableBuilder(
    column: $table.instruction,
    builder: (column) => column,
  );

  GeneratedColumn<String> get legacyInternalRouteEdgeId => $composableBuilder(
    column: $table.legacyInternalRouteEdgeId,
    builder: (column) => column,
  );
}

class $$StationPathwayEdgesTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $StationPathwayEdgesTable,
          StationPathwayEdge,
          $$StationPathwayEdgesTableFilterComposer,
          $$StationPathwayEdgesTableOrderingComposer,
          $$StationPathwayEdgesTableAnnotationComposer,
          $$StationPathwayEdgesTableCreateCompanionBuilder,
          $$StationPathwayEdgesTableUpdateCompanionBuilder,
          (
            StationPathwayEdge,
            BaseReferences<
              _$CatalogDatabase,
              $StationPathwayEdgesTable,
              StationPathwayEdge
            >,
          ),
          StationPathwayEdge,
          PrefetchHooks Function()
        > {
  $$StationPathwayEdgesTableTableManager(
    _$CatalogDatabase db,
    $StationPathwayEdgesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StationPathwayEdgesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StationPathwayEdgesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$StationPathwayEdgesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> fromNodeId = const Value.absent(),
                Value<String> toNodeId = const Value.absent(),
                Value<String> edgeType = const Value.absent(),
                Value<int> durationSeconds = const Value.absent(),
                Value<int> distanceMeters = const Value.absent(),
                Value<bool> bidirectional = const Value.absent(),
                Value<bool> includesStairs = const Value.absent(),
                Value<bool> requiresElevator = const Value.absent(),
                Value<bool> requiresEscalator = const Value.absent(),
                Value<String> levelFrom = const Value.absent(),
                Value<String> levelTo = const Value.absent(),
                Value<String?> requiresFacilityId = const Value.absent(),
                Value<int?> minWidthCm = const Value.absent(),
                Value<double?> slopePercent = const Value.absent(),
                Value<double?> verticalMeters = const Value.absent(),
                Value<int> reliabilityScore = const Value.absent(),
                Value<String> accessibilityStatus = const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<String> sourceSnapshotId = const Value.absent(),
                Value<String> providerRecordHash = const Value.absent(),
                Value<String> provenanceKind = const Value.absent(),
                Value<String> verificationStatus = const Value.absent(),
                Value<DateTime?> lastVerifiedAt = const Value.absent(),
                Value<String> evidenceHash = const Value.absent(),
                Value<String> instruction = const Value.absent(),
                Value<String> legacyInternalRouteEdgeId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StationPathwayEdgesCompanion(
                id: id,
                fromNodeId: fromNodeId,
                toNodeId: toNodeId,
                edgeType: edgeType,
                durationSeconds: durationSeconds,
                distanceMeters: distanceMeters,
                bidirectional: bidirectional,
                includesStairs: includesStairs,
                requiresElevator: requiresElevator,
                requiresEscalator: requiresEscalator,
                levelFrom: levelFrom,
                levelTo: levelTo,
                requiresFacilityId: requiresFacilityId,
                minWidthCm: minWidthCm,
                slopePercent: slopePercent,
                verticalMeters: verticalMeters,
                reliabilityScore: reliabilityScore,
                accessibilityStatus: accessibilityStatus,
                sourceId: sourceId,
                sourceSnapshotId: sourceSnapshotId,
                providerRecordHash: providerRecordHash,
                provenanceKind: provenanceKind,
                verificationStatus: verificationStatus,
                lastVerifiedAt: lastVerifiedAt,
                evidenceHash: evidenceHash,
                instruction: instruction,
                legacyInternalRouteEdgeId: legacyInternalRouteEdgeId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String fromNodeId,
                required String toNodeId,
                Value<String> edgeType = const Value.absent(),
                Value<int> durationSeconds = const Value.absent(),
                Value<int> distanceMeters = const Value.absent(),
                Value<bool> bidirectional = const Value.absent(),
                Value<bool> includesStairs = const Value.absent(),
                Value<bool> requiresElevator = const Value.absent(),
                Value<bool> requiresEscalator = const Value.absent(),
                Value<String> levelFrom = const Value.absent(),
                Value<String> levelTo = const Value.absent(),
                Value<String?> requiresFacilityId = const Value.absent(),
                Value<int?> minWidthCm = const Value.absent(),
                Value<double?> slopePercent = const Value.absent(),
                Value<double?> verticalMeters = const Value.absent(),
                Value<int> reliabilityScore = const Value.absent(),
                Value<String> accessibilityStatus = const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<String> sourceSnapshotId = const Value.absent(),
                Value<String> providerRecordHash = const Value.absent(),
                Value<String> provenanceKind = const Value.absent(),
                Value<String> verificationStatus = const Value.absent(),
                Value<DateTime?> lastVerifiedAt = const Value.absent(),
                Value<String> evidenceHash = const Value.absent(),
                Value<String> instruction = const Value.absent(),
                Value<String> legacyInternalRouteEdgeId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StationPathwayEdgesCompanion.insert(
                id: id,
                fromNodeId: fromNodeId,
                toNodeId: toNodeId,
                edgeType: edgeType,
                durationSeconds: durationSeconds,
                distanceMeters: distanceMeters,
                bidirectional: bidirectional,
                includesStairs: includesStairs,
                requiresElevator: requiresElevator,
                requiresEscalator: requiresEscalator,
                levelFrom: levelFrom,
                levelTo: levelTo,
                requiresFacilityId: requiresFacilityId,
                minWidthCm: minWidthCm,
                slopePercent: slopePercent,
                verticalMeters: verticalMeters,
                reliabilityScore: reliabilityScore,
                accessibilityStatus: accessibilityStatus,
                sourceId: sourceId,
                sourceSnapshotId: sourceSnapshotId,
                providerRecordHash: providerRecordHash,
                provenanceKind: provenanceKind,
                verificationStatus: verificationStatus,
                lastVerifiedAt: lastVerifiedAt,
                evidenceHash: evidenceHash,
                instruction: instruction,
                legacyInternalRouteEdgeId: legacyInternalRouteEdgeId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StationPathwayEdgesTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $StationPathwayEdgesTable,
      StationPathwayEdge,
      $$StationPathwayEdgesTableFilterComposer,
      $$StationPathwayEdgesTableOrderingComposer,
      $$StationPathwayEdgesTableAnnotationComposer,
      $$StationPathwayEdgesTableCreateCompanionBuilder,
      $$StationPathwayEdgesTableUpdateCompanionBuilder,
      (
        StationPathwayEdge,
        BaseReferences<
          _$CatalogDatabase,
          $StationPathwayEdgesTable,
          StationPathwayEdge
        >,
      ),
      StationPathwayEdge,
      PrefetchHooks Function()
    >;
typedef $$TransferRulesTableCreateCompanionBuilder =
    TransferRulesCompanion Function({
      required String id,
      required String fromStationId,
      required String fromLineId,
      required String toStationId,
      required String toLineId,
      Value<String> transferType,
      Value<int> minTransferSeconds,
      Value<String?> pathwayEdgeId,
      Value<String?> strictStepFreePathwayEdgeId,
      Value<String> sourceId,
      Value<String> verificationStatus,
      Value<int> rowid,
    });
typedef $$TransferRulesTableUpdateCompanionBuilder =
    TransferRulesCompanion Function({
      Value<String> id,
      Value<String> fromStationId,
      Value<String> fromLineId,
      Value<String> toStationId,
      Value<String> toLineId,
      Value<String> transferType,
      Value<int> minTransferSeconds,
      Value<String?> pathwayEdgeId,
      Value<String?> strictStepFreePathwayEdgeId,
      Value<String> sourceId,
      Value<String> verificationStatus,
      Value<int> rowid,
    });

class $$TransferRulesTableFilterComposer
    extends Composer<_$CatalogDatabase, $TransferRulesTable> {
  $$TransferRulesTableFilterComposer({
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

  ColumnFilters<String> get fromStationId => $composableBuilder(
    column: $table.fromStationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fromLineId => $composableBuilder(
    column: $table.fromLineId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toStationId => $composableBuilder(
    column: $table.toStationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toLineId => $composableBuilder(
    column: $table.toLineId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get transferType => $composableBuilder(
    column: $table.transferType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get minTransferSeconds => $composableBuilder(
    column: $table.minTransferSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pathwayEdgeId => $composableBuilder(
    column: $table.pathwayEdgeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get strictStepFreePathwayEdgeId => $composableBuilder(
    column: $table.strictStepFreePathwayEdgeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get verificationStatus => $composableBuilder(
    column: $table.verificationStatus,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TransferRulesTableOrderingComposer
    extends Composer<_$CatalogDatabase, $TransferRulesTable> {
  $$TransferRulesTableOrderingComposer({
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

  ColumnOrderings<String> get fromStationId => $composableBuilder(
    column: $table.fromStationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fromLineId => $composableBuilder(
    column: $table.fromLineId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toStationId => $composableBuilder(
    column: $table.toStationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toLineId => $composableBuilder(
    column: $table.toLineId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get transferType => $composableBuilder(
    column: $table.transferType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get minTransferSeconds => $composableBuilder(
    column: $table.minTransferSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pathwayEdgeId => $composableBuilder(
    column: $table.pathwayEdgeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get strictStepFreePathwayEdgeId => $composableBuilder(
    column: $table.strictStepFreePathwayEdgeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get verificationStatus => $composableBuilder(
    column: $table.verificationStatus,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TransferRulesTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $TransferRulesTable> {
  $$TransferRulesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get fromStationId => $composableBuilder(
    column: $table.fromStationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fromLineId => $composableBuilder(
    column: $table.fromLineId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get toStationId => $composableBuilder(
    column: $table.toStationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get toLineId =>
      $composableBuilder(column: $table.toLineId, builder: (column) => column);

  GeneratedColumn<String> get transferType => $composableBuilder(
    column: $table.transferType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get minTransferSeconds => $composableBuilder(
    column: $table.minTransferSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<String> get pathwayEdgeId => $composableBuilder(
    column: $table.pathwayEdgeId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get strictStepFreePathwayEdgeId => $composableBuilder(
    column: $table.strictStepFreePathwayEdgeId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get verificationStatus => $composableBuilder(
    column: $table.verificationStatus,
    builder: (column) => column,
  );
}

class $$TransferRulesTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $TransferRulesTable,
          TransferRule,
          $$TransferRulesTableFilterComposer,
          $$TransferRulesTableOrderingComposer,
          $$TransferRulesTableAnnotationComposer,
          $$TransferRulesTableCreateCompanionBuilder,
          $$TransferRulesTableUpdateCompanionBuilder,
          (
            TransferRule,
            BaseReferences<
              _$CatalogDatabase,
              $TransferRulesTable,
              TransferRule
            >,
          ),
          TransferRule,
          PrefetchHooks Function()
        > {
  $$TransferRulesTableTableManager(
    _$CatalogDatabase db,
    $TransferRulesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransferRulesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransferRulesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransferRulesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> fromStationId = const Value.absent(),
                Value<String> fromLineId = const Value.absent(),
                Value<String> toStationId = const Value.absent(),
                Value<String> toLineId = const Value.absent(),
                Value<String> transferType = const Value.absent(),
                Value<int> minTransferSeconds = const Value.absent(),
                Value<String?> pathwayEdgeId = const Value.absent(),
                Value<String?> strictStepFreePathwayEdgeId =
                    const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<String> verificationStatus = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransferRulesCompanion(
                id: id,
                fromStationId: fromStationId,
                fromLineId: fromLineId,
                toStationId: toStationId,
                toLineId: toLineId,
                transferType: transferType,
                minTransferSeconds: minTransferSeconds,
                pathwayEdgeId: pathwayEdgeId,
                strictStepFreePathwayEdgeId: strictStepFreePathwayEdgeId,
                sourceId: sourceId,
                verificationStatus: verificationStatus,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String fromStationId,
                required String fromLineId,
                required String toStationId,
                required String toLineId,
                Value<String> transferType = const Value.absent(),
                Value<int> minTransferSeconds = const Value.absent(),
                Value<String?> pathwayEdgeId = const Value.absent(),
                Value<String?> strictStepFreePathwayEdgeId =
                    const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<String> verificationStatus = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransferRulesCompanion.insert(
                id: id,
                fromStationId: fromStationId,
                fromLineId: fromLineId,
                toStationId: toStationId,
                toLineId: toLineId,
                transferType: transferType,
                minTransferSeconds: minTransferSeconds,
                pathwayEdgeId: pathwayEdgeId,
                strictStepFreePathwayEdgeId: strictStepFreePathwayEdgeId,
                sourceId: sourceId,
                verificationStatus: verificationStatus,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TransferRulesTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $TransferRulesTable,
      TransferRule,
      $$TransferRulesTableFilterComposer,
      $$TransferRulesTableOrderingComposer,
      $$TransferRulesTableAnnotationComposer,
      $$TransferRulesTableCreateCompanionBuilder,
      $$TransferRulesTableUpdateCompanionBuilder,
      (
        TransferRule,
        BaseReferences<_$CatalogDatabase, $TransferRulesTable, TransferRule>,
      ),
      TransferRule,
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
  $$ServiceCalendarsTableTableManager get serviceCalendars =>
      $$ServiceCalendarsTableTableManager(_db, _db.serviceCalendars);
  $$ServiceCalendarDatesTableTableManager get serviceCalendarDates =>
      $$ServiceCalendarDatesTableTableManager(_db, _db.serviceCalendarDates);
  $$TransitRoutesTableTableManager get transitRoutes =>
      $$TransitRoutesTableTableManager(_db, _db.transitRoutes);
  $$TransitTripsTableTableManager get transitTrips =>
      $$TransitTripsTableTableManager(_db, _db.transitTrips);
  $$TransitStopTimesTableTableManager get transitStopTimes =>
      $$TransitStopTimesTableTableManager(_db, _db.transitStopTimes);
  $$TransitFrequenciesTableTableManager get transitFrequencies =>
      $$TransitFrequenciesTableTableManager(_db, _db.transitFrequencies);
  $$RealtimeProviderLineMappingsTableTableManager
  get realtimeProviderLineMappings =>
      $$RealtimeProviderLineMappingsTableTableManager(
        _db,
        _db.realtimeProviderLineMappings,
      );
  $$RealtimeProviderStationMappingsTableTableManager
  get realtimeProviderStationMappings =>
      $$RealtimeProviderStationMappingsTableTableManager(
        _db,
        _db.realtimeProviderStationMappings,
      );
  $$NetworkEdgesTableTableManager get networkEdges =>
      $$NetworkEdgesTableTableManager(_db, _db.networkEdges);
  $$StationExitsTableTableManager get stationExits =>
      $$StationExitsTableTableManager(_db, _db.stationExits);
  $$FacilitiesTableTableManager get facilities =>
      $$FacilitiesTableTableManager(_db, _db.facilities);
  $$StationFacilityEvidenceTableTableManager get stationFacilityEvidence =>
      $$StationFacilityEvidenceTableTableManager(
        _db,
        _db.stationFacilityEvidence,
      );
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
  $$StationPathwayNodesTableTableManager get stationPathwayNodes =>
      $$StationPathwayNodesTableTableManager(_db, _db.stationPathwayNodes);
  $$StationPathwayEdgesTableTableManager get stationPathwayEdges =>
      $$StationPathwayEdgesTableTableManager(_db, _db.stationPathwayEdges);
  $$TransferRulesTableTableManager get transferRules =>
      $$TransferRulesTableTableManager(_db, _db.transferRules);
  $$DataQualityRecordsTableTableManager get dataQualityRecords =>
      $$DataQualityRecordsTableTableManager(_db, _db.dataQualityRecords);
}
