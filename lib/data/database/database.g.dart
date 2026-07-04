// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $ProfilesTable extends Profiles with TableInfo<$ProfilesTable, Profile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    clientDefault: () => 1,
  );
  static const VerificationMeta _heightCmMeta = const VerificationMeta(
    'heightCm',
  );
  @override
  late final GeneratedColumn<double> heightCm = GeneratedColumn<double>(
    'height_cm',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _weightKgMeta = const VerificationMeta(
    'weightKg',
  );
  @override
  late final GeneratedColumn<double> weightKg = GeneratedColumn<double>(
    'weight_kg',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyFatPctMeta = const VerificationMeta(
    'bodyFatPct',
  );
  @override
  late final GeneratedColumn<double> bodyFatPct = GeneratedColumn<double>(
    'body_fat_pct',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ageMeta = const VerificationMeta('age');
  @override
  late final GeneratedColumn<int> age = GeneratedColumn<int>(
    'age',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _genderMeta = const VerificationMeta('gender');
  @override
  late final GeneratedColumn<String> gender = GeneratedColumn<String>(
    'gender',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activityLevelMeta = const VerificationMeta(
    'activityLevel',
  );
  @override
  late final GeneratedColumn<double> activityLevel = GeneratedColumn<double>(
    'activity_level',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _goalMeta = const VerificationMeta('goal');
  @override
  late final GeneratedColumn<String> goal = GeneratedColumn<String>(
    'goal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _goalRateKgPerWeekMeta = const VerificationMeta(
    'goalRateKgPerWeek',
  );
  @override
  late final GeneratedColumn<double> goalRateKgPerWeek =
      GeneratedColumn<double>(
        'goal_rate_kg_per_week',
        aliasedName,
        false,
        type: DriftSqlType.double,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _formulaMeta = const VerificationMeta(
    'formula',
  );
  @override
  late final GeneratedColumn<String> formula = GeneratedColumn<String>(
    'formula',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dailyCalorieTargetMeta =
      const VerificationMeta('dailyCalorieTarget');
  @override
  late final GeneratedColumn<int> dailyCalorieTarget = GeneratedColumn<int>(
    'daily_calorie_target',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _proteinGPerKgMeta = const VerificationMeta(
    'proteinGPerKg',
  );
  @override
  late final GeneratedColumn<double> proteinGPerKg = GeneratedColumn<double>(
    'protein_g_per_kg',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fatGPerKgMeta = const VerificationMeta(
    'fatGPerKg',
  );
  @override
  late final GeneratedColumn<double> fatGPerKg = GeneratedColumn<double>(
    'fat_g_per_kg',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _carbGPerKgMeta = const VerificationMeta(
    'carbGPerKg',
  );
  @override
  late final GeneratedColumn<double> carbGPerKg = GeneratedColumn<double>(
    'carb_g_per_kg',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tdeeAdjustmentKcalMeta =
      const VerificationMeta('tdeeAdjustmentKcal');
  @override
  late final GeneratedColumn<int> tdeeAdjustmentKcal = GeneratedColumn<int>(
    'tdee_adjustment_kcal',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _specialConditionMeta = const VerificationMeta(
    'specialCondition',
  );
  @override
  late final GeneratedColumn<String> specialCondition = GeneratedColumn<String>(
    'special_condition',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dietPreferenceMeta = const VerificationMeta(
    'dietPreference',
  );
  @override
  late final GeneratedColumn<String> dietPreference = GeneratedColumn<String>(
    'diet_preference',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _healthConditionMeta = const VerificationMeta(
    'healthCondition',
  );
  @override
  late final GeneratedColumn<String> healthCondition = GeneratedColumn<String>(
    'health_condition',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    heightCm,
    weightKg,
    bodyFatPct,
    age,
    gender,
    activityLevel,
    goal,
    goalRateKgPerWeek,
    formula,
    dailyCalorieTarget,
    proteinGPerKg,
    fatGPerKg,
    carbGPerKg,
    tdeeAdjustmentKcal,
    updatedAt,
    specialCondition,
    dietPreference,
    healthCondition,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<Profile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('height_cm')) {
      context.handle(
        _heightCmMeta,
        heightCm.isAcceptableOrUnknown(data['height_cm']!, _heightCmMeta),
      );
    } else if (isInserting) {
      context.missing(_heightCmMeta);
    }
    if (data.containsKey('weight_kg')) {
      context.handle(
        _weightKgMeta,
        weightKg.isAcceptableOrUnknown(data['weight_kg']!, _weightKgMeta),
      );
    } else if (isInserting) {
      context.missing(_weightKgMeta);
    }
    if (data.containsKey('body_fat_pct')) {
      context.handle(
        _bodyFatPctMeta,
        bodyFatPct.isAcceptableOrUnknown(
          data['body_fat_pct']!,
          _bodyFatPctMeta,
        ),
      );
    }
    if (data.containsKey('age')) {
      context.handle(
        _ageMeta,
        age.isAcceptableOrUnknown(data['age']!, _ageMeta),
      );
    } else if (isInserting) {
      context.missing(_ageMeta);
    }
    if (data.containsKey('gender')) {
      context.handle(
        _genderMeta,
        gender.isAcceptableOrUnknown(data['gender']!, _genderMeta),
      );
    } else if (isInserting) {
      context.missing(_genderMeta);
    }
    if (data.containsKey('activity_level')) {
      context.handle(
        _activityLevelMeta,
        activityLevel.isAcceptableOrUnknown(
          data['activity_level']!,
          _activityLevelMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_activityLevelMeta);
    }
    if (data.containsKey('goal')) {
      context.handle(
        _goalMeta,
        goal.isAcceptableOrUnknown(data['goal']!, _goalMeta),
      );
    } else if (isInserting) {
      context.missing(_goalMeta);
    }
    if (data.containsKey('goal_rate_kg_per_week')) {
      context.handle(
        _goalRateKgPerWeekMeta,
        goalRateKgPerWeek.isAcceptableOrUnknown(
          data['goal_rate_kg_per_week']!,
          _goalRateKgPerWeekMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_goalRateKgPerWeekMeta);
    }
    if (data.containsKey('formula')) {
      context.handle(
        _formulaMeta,
        formula.isAcceptableOrUnknown(data['formula']!, _formulaMeta),
      );
    } else if (isInserting) {
      context.missing(_formulaMeta);
    }
    if (data.containsKey('daily_calorie_target')) {
      context.handle(
        _dailyCalorieTargetMeta,
        dailyCalorieTarget.isAcceptableOrUnknown(
          data['daily_calorie_target']!,
          _dailyCalorieTargetMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_dailyCalorieTargetMeta);
    }
    if (data.containsKey('protein_g_per_kg')) {
      context.handle(
        _proteinGPerKgMeta,
        proteinGPerKg.isAcceptableOrUnknown(
          data['protein_g_per_kg']!,
          _proteinGPerKgMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_proteinGPerKgMeta);
    }
    if (data.containsKey('fat_g_per_kg')) {
      context.handle(
        _fatGPerKgMeta,
        fatGPerKg.isAcceptableOrUnknown(data['fat_g_per_kg']!, _fatGPerKgMeta),
      );
    } else if (isInserting) {
      context.missing(_fatGPerKgMeta);
    }
    if (data.containsKey('carb_g_per_kg')) {
      context.handle(
        _carbGPerKgMeta,
        carbGPerKg.isAcceptableOrUnknown(
          data['carb_g_per_kg']!,
          _carbGPerKgMeta,
        ),
      );
    }
    if (data.containsKey('tdee_adjustment_kcal')) {
      context.handle(
        _tdeeAdjustmentKcalMeta,
        tdeeAdjustmentKcal.isAcceptableOrUnknown(
          data['tdee_adjustment_kcal']!,
          _tdeeAdjustmentKcalMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('special_condition')) {
      context.handle(
        _specialConditionMeta,
        specialCondition.isAcceptableOrUnknown(
          data['special_condition']!,
          _specialConditionMeta,
        ),
      );
    }
    if (data.containsKey('diet_preference')) {
      context.handle(
        _dietPreferenceMeta,
        dietPreference.isAcceptableOrUnknown(
          data['diet_preference']!,
          _dietPreferenceMeta,
        ),
      );
    }
    if (data.containsKey('health_condition')) {
      context.handle(
        _healthConditionMeta,
        healthCondition.isAcceptableOrUnknown(
          data['health_condition']!,
          _healthConditionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Profile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Profile(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      heightCm: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}height_cm'],
      )!,
      weightKg: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}weight_kg'],
      )!,
      bodyFatPct: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}body_fat_pct'],
      ),
      age: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}age'],
      )!,
      gender: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gender'],
      )!,
      activityLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}activity_level'],
      )!,
      goal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}goal'],
      )!,
      goalRateKgPerWeek: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}goal_rate_kg_per_week'],
      )!,
      formula: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}formula'],
      )!,
      dailyCalorieTarget: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}daily_calorie_target'],
      )!,
      proteinGPerKg: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}protein_g_per_kg'],
      )!,
      fatGPerKg: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}fat_g_per_kg'],
      )!,
      carbGPerKg: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}carb_g_per_kg'],
      ),
      tdeeAdjustmentKcal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tdee_adjustment_kcal'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      specialCondition: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}special_condition'],
      ),
      dietPreference: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}diet_preference'],
      ),
      healthCondition: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}health_condition'],
      ),
    );
  }

  @override
  $ProfilesTable createAlias(String alias) {
    return $ProfilesTable(attachedDatabase, alias);
  }
}

class Profile extends DataClass implements Insertable<Profile> {
  final int id;
  final double heightCm;
  final double weightKg;
  final double? bodyFatPct;
  final int age;
  final String gender;
  final double activityLevel;
  final String goal;
  final double goalRateKgPerWeek;
  final String formula;
  final int dailyCalorieTarget;
  final double proteinGPerKg;
  final double fatGPerKg;
  final double? carbGPerKg;
  final int tdeeAdjustmentKcal;
  final int updatedAt;
  final String? specialCondition;
  final String? dietPreference;
  final String? healthCondition;
  const Profile({
    required this.id,
    required this.heightCm,
    required this.weightKg,
    this.bodyFatPct,
    required this.age,
    required this.gender,
    required this.activityLevel,
    required this.goal,
    required this.goalRateKgPerWeek,
    required this.formula,
    required this.dailyCalorieTarget,
    required this.proteinGPerKg,
    required this.fatGPerKg,
    this.carbGPerKg,
    required this.tdeeAdjustmentKcal,
    required this.updatedAt,
    this.specialCondition,
    this.dietPreference,
    this.healthCondition,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['height_cm'] = Variable<double>(heightCm);
    map['weight_kg'] = Variable<double>(weightKg);
    if (!nullToAbsent || bodyFatPct != null) {
      map['body_fat_pct'] = Variable<double>(bodyFatPct);
    }
    map['age'] = Variable<int>(age);
    map['gender'] = Variable<String>(gender);
    map['activity_level'] = Variable<double>(activityLevel);
    map['goal'] = Variable<String>(goal);
    map['goal_rate_kg_per_week'] = Variable<double>(goalRateKgPerWeek);
    map['formula'] = Variable<String>(formula);
    map['daily_calorie_target'] = Variable<int>(dailyCalorieTarget);
    map['protein_g_per_kg'] = Variable<double>(proteinGPerKg);
    map['fat_g_per_kg'] = Variable<double>(fatGPerKg);
    if (!nullToAbsent || carbGPerKg != null) {
      map['carb_g_per_kg'] = Variable<double>(carbGPerKg);
    }
    map['tdee_adjustment_kcal'] = Variable<int>(tdeeAdjustmentKcal);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || specialCondition != null) {
      map['special_condition'] = Variable<String>(specialCondition);
    }
    if (!nullToAbsent || dietPreference != null) {
      map['diet_preference'] = Variable<String>(dietPreference);
    }
    if (!nullToAbsent || healthCondition != null) {
      map['health_condition'] = Variable<String>(healthCondition);
    }
    return map;
  }

  ProfilesCompanion toCompanion(bool nullToAbsent) {
    return ProfilesCompanion(
      id: Value(id),
      heightCm: Value(heightCm),
      weightKg: Value(weightKg),
      bodyFatPct: bodyFatPct == null && nullToAbsent
          ? const Value.absent()
          : Value(bodyFatPct),
      age: Value(age),
      gender: Value(gender),
      activityLevel: Value(activityLevel),
      goal: Value(goal),
      goalRateKgPerWeek: Value(goalRateKgPerWeek),
      formula: Value(formula),
      dailyCalorieTarget: Value(dailyCalorieTarget),
      proteinGPerKg: Value(proteinGPerKg),
      fatGPerKg: Value(fatGPerKg),
      carbGPerKg: carbGPerKg == null && nullToAbsent
          ? const Value.absent()
          : Value(carbGPerKg),
      tdeeAdjustmentKcal: Value(tdeeAdjustmentKcal),
      updatedAt: Value(updatedAt),
      specialCondition: specialCondition == null && nullToAbsent
          ? const Value.absent()
          : Value(specialCondition),
      dietPreference: dietPreference == null && nullToAbsent
          ? const Value.absent()
          : Value(dietPreference),
      healthCondition: healthCondition == null && nullToAbsent
          ? const Value.absent()
          : Value(healthCondition),
    );
  }

  factory Profile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Profile(
      id: serializer.fromJson<int>(json['id']),
      heightCm: serializer.fromJson<double>(json['heightCm']),
      weightKg: serializer.fromJson<double>(json['weightKg']),
      bodyFatPct: serializer.fromJson<double?>(json['bodyFatPct']),
      age: serializer.fromJson<int>(json['age']),
      gender: serializer.fromJson<String>(json['gender']),
      activityLevel: serializer.fromJson<double>(json['activityLevel']),
      goal: serializer.fromJson<String>(json['goal']),
      goalRateKgPerWeek: serializer.fromJson<double>(json['goalRateKgPerWeek']),
      formula: serializer.fromJson<String>(json['formula']),
      dailyCalorieTarget: serializer.fromJson<int>(json['dailyCalorieTarget']),
      proteinGPerKg: serializer.fromJson<double>(json['proteinGPerKg']),
      fatGPerKg: serializer.fromJson<double>(json['fatGPerKg']),
      carbGPerKg: serializer.fromJson<double?>(json['carbGPerKg']),
      tdeeAdjustmentKcal: serializer.fromJson<int>(json['tdeeAdjustmentKcal']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      specialCondition: serializer.fromJson<String?>(json['specialCondition']),
      dietPreference: serializer.fromJson<String?>(json['dietPreference']),
      healthCondition: serializer.fromJson<String?>(json['healthCondition']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'heightCm': serializer.toJson<double>(heightCm),
      'weightKg': serializer.toJson<double>(weightKg),
      'bodyFatPct': serializer.toJson<double?>(bodyFatPct),
      'age': serializer.toJson<int>(age),
      'gender': serializer.toJson<String>(gender),
      'activityLevel': serializer.toJson<double>(activityLevel),
      'goal': serializer.toJson<String>(goal),
      'goalRateKgPerWeek': serializer.toJson<double>(goalRateKgPerWeek),
      'formula': serializer.toJson<String>(formula),
      'dailyCalorieTarget': serializer.toJson<int>(dailyCalorieTarget),
      'proteinGPerKg': serializer.toJson<double>(proteinGPerKg),
      'fatGPerKg': serializer.toJson<double>(fatGPerKg),
      'carbGPerKg': serializer.toJson<double?>(carbGPerKg),
      'tdeeAdjustmentKcal': serializer.toJson<int>(tdeeAdjustmentKcal),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'specialCondition': serializer.toJson<String?>(specialCondition),
      'dietPreference': serializer.toJson<String?>(dietPreference),
      'healthCondition': serializer.toJson<String?>(healthCondition),
    };
  }

  Profile copyWith({
    int? id,
    double? heightCm,
    double? weightKg,
    Value<double?> bodyFatPct = const Value.absent(),
    int? age,
    String? gender,
    double? activityLevel,
    String? goal,
    double? goalRateKgPerWeek,
    String? formula,
    int? dailyCalorieTarget,
    double? proteinGPerKg,
    double? fatGPerKg,
    Value<double?> carbGPerKg = const Value.absent(),
    int? tdeeAdjustmentKcal,
    int? updatedAt,
    Value<String?> specialCondition = const Value.absent(),
    Value<String?> dietPreference = const Value.absent(),
    Value<String?> healthCondition = const Value.absent(),
  }) => Profile(
    id: id ?? this.id,
    heightCm: heightCm ?? this.heightCm,
    weightKg: weightKg ?? this.weightKg,
    bodyFatPct: bodyFatPct.present ? bodyFatPct.value : this.bodyFatPct,
    age: age ?? this.age,
    gender: gender ?? this.gender,
    activityLevel: activityLevel ?? this.activityLevel,
    goal: goal ?? this.goal,
    goalRateKgPerWeek: goalRateKgPerWeek ?? this.goalRateKgPerWeek,
    formula: formula ?? this.formula,
    dailyCalorieTarget: dailyCalorieTarget ?? this.dailyCalorieTarget,
    proteinGPerKg: proteinGPerKg ?? this.proteinGPerKg,
    fatGPerKg: fatGPerKg ?? this.fatGPerKg,
    carbGPerKg: carbGPerKg.present ? carbGPerKg.value : this.carbGPerKg,
    tdeeAdjustmentKcal: tdeeAdjustmentKcal ?? this.tdeeAdjustmentKcal,
    updatedAt: updatedAt ?? this.updatedAt,
    specialCondition: specialCondition.present
        ? specialCondition.value
        : this.specialCondition,
    dietPreference: dietPreference.present
        ? dietPreference.value
        : this.dietPreference,
    healthCondition: healthCondition.present
        ? healthCondition.value
        : this.healthCondition,
  );
  Profile copyWithCompanion(ProfilesCompanion data) {
    return Profile(
      id: data.id.present ? data.id.value : this.id,
      heightCm: data.heightCm.present ? data.heightCm.value : this.heightCm,
      weightKg: data.weightKg.present ? data.weightKg.value : this.weightKg,
      bodyFatPct: data.bodyFatPct.present
          ? data.bodyFatPct.value
          : this.bodyFatPct,
      age: data.age.present ? data.age.value : this.age,
      gender: data.gender.present ? data.gender.value : this.gender,
      activityLevel: data.activityLevel.present
          ? data.activityLevel.value
          : this.activityLevel,
      goal: data.goal.present ? data.goal.value : this.goal,
      goalRateKgPerWeek: data.goalRateKgPerWeek.present
          ? data.goalRateKgPerWeek.value
          : this.goalRateKgPerWeek,
      formula: data.formula.present ? data.formula.value : this.formula,
      dailyCalorieTarget: data.dailyCalorieTarget.present
          ? data.dailyCalorieTarget.value
          : this.dailyCalorieTarget,
      proteinGPerKg: data.proteinGPerKg.present
          ? data.proteinGPerKg.value
          : this.proteinGPerKg,
      fatGPerKg: data.fatGPerKg.present ? data.fatGPerKg.value : this.fatGPerKg,
      carbGPerKg: data.carbGPerKg.present
          ? data.carbGPerKg.value
          : this.carbGPerKg,
      tdeeAdjustmentKcal: data.tdeeAdjustmentKcal.present
          ? data.tdeeAdjustmentKcal.value
          : this.tdeeAdjustmentKcal,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      specialCondition: data.specialCondition.present
          ? data.specialCondition.value
          : this.specialCondition,
      dietPreference: data.dietPreference.present
          ? data.dietPreference.value
          : this.dietPreference,
      healthCondition: data.healthCondition.present
          ? data.healthCondition.value
          : this.healthCondition,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Profile(')
          ..write('id: $id, ')
          ..write('heightCm: $heightCm, ')
          ..write('weightKg: $weightKg, ')
          ..write('bodyFatPct: $bodyFatPct, ')
          ..write('age: $age, ')
          ..write('gender: $gender, ')
          ..write('activityLevel: $activityLevel, ')
          ..write('goal: $goal, ')
          ..write('goalRateKgPerWeek: $goalRateKgPerWeek, ')
          ..write('formula: $formula, ')
          ..write('dailyCalorieTarget: $dailyCalorieTarget, ')
          ..write('proteinGPerKg: $proteinGPerKg, ')
          ..write('fatGPerKg: $fatGPerKg, ')
          ..write('carbGPerKg: $carbGPerKg, ')
          ..write('tdeeAdjustmentKcal: $tdeeAdjustmentKcal, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('specialCondition: $specialCondition, ')
          ..write('dietPreference: $dietPreference, ')
          ..write('healthCondition: $healthCondition')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    heightCm,
    weightKg,
    bodyFatPct,
    age,
    gender,
    activityLevel,
    goal,
    goalRateKgPerWeek,
    formula,
    dailyCalorieTarget,
    proteinGPerKg,
    fatGPerKg,
    carbGPerKg,
    tdeeAdjustmentKcal,
    updatedAt,
    specialCondition,
    dietPreference,
    healthCondition,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Profile &&
          other.id == this.id &&
          other.heightCm == this.heightCm &&
          other.weightKg == this.weightKg &&
          other.bodyFatPct == this.bodyFatPct &&
          other.age == this.age &&
          other.gender == this.gender &&
          other.activityLevel == this.activityLevel &&
          other.goal == this.goal &&
          other.goalRateKgPerWeek == this.goalRateKgPerWeek &&
          other.formula == this.formula &&
          other.dailyCalorieTarget == this.dailyCalorieTarget &&
          other.proteinGPerKg == this.proteinGPerKg &&
          other.fatGPerKg == this.fatGPerKg &&
          other.carbGPerKg == this.carbGPerKg &&
          other.tdeeAdjustmentKcal == this.tdeeAdjustmentKcal &&
          other.updatedAt == this.updatedAt &&
          other.specialCondition == this.specialCondition &&
          other.dietPreference == this.dietPreference &&
          other.healthCondition == this.healthCondition);
}

class ProfilesCompanion extends UpdateCompanion<Profile> {
  final Value<int> id;
  final Value<double> heightCm;
  final Value<double> weightKg;
  final Value<double?> bodyFatPct;
  final Value<int> age;
  final Value<String> gender;
  final Value<double> activityLevel;
  final Value<String> goal;
  final Value<double> goalRateKgPerWeek;
  final Value<String> formula;
  final Value<int> dailyCalorieTarget;
  final Value<double> proteinGPerKg;
  final Value<double> fatGPerKg;
  final Value<double?> carbGPerKg;
  final Value<int> tdeeAdjustmentKcal;
  final Value<int> updatedAt;
  final Value<String?> specialCondition;
  final Value<String?> dietPreference;
  final Value<String?> healthCondition;
  const ProfilesCompanion({
    this.id = const Value.absent(),
    this.heightCm = const Value.absent(),
    this.weightKg = const Value.absent(),
    this.bodyFatPct = const Value.absent(),
    this.age = const Value.absent(),
    this.gender = const Value.absent(),
    this.activityLevel = const Value.absent(),
    this.goal = const Value.absent(),
    this.goalRateKgPerWeek = const Value.absent(),
    this.formula = const Value.absent(),
    this.dailyCalorieTarget = const Value.absent(),
    this.proteinGPerKg = const Value.absent(),
    this.fatGPerKg = const Value.absent(),
    this.carbGPerKg = const Value.absent(),
    this.tdeeAdjustmentKcal = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.specialCondition = const Value.absent(),
    this.dietPreference = const Value.absent(),
    this.healthCondition = const Value.absent(),
  });
  ProfilesCompanion.insert({
    this.id = const Value.absent(),
    required double heightCm,
    required double weightKg,
    this.bodyFatPct = const Value.absent(),
    required int age,
    required String gender,
    required double activityLevel,
    required String goal,
    required double goalRateKgPerWeek,
    required String formula,
    required int dailyCalorieTarget,
    required double proteinGPerKg,
    required double fatGPerKg,
    this.carbGPerKg = const Value.absent(),
    this.tdeeAdjustmentKcal = const Value.absent(),
    required int updatedAt,
    this.specialCondition = const Value.absent(),
    this.dietPreference = const Value.absent(),
    this.healthCondition = const Value.absent(),
  }) : heightCm = Value(heightCm),
       weightKg = Value(weightKg),
       age = Value(age),
       gender = Value(gender),
       activityLevel = Value(activityLevel),
       goal = Value(goal),
       goalRateKgPerWeek = Value(goalRateKgPerWeek),
       formula = Value(formula),
       dailyCalorieTarget = Value(dailyCalorieTarget),
       proteinGPerKg = Value(proteinGPerKg),
       fatGPerKg = Value(fatGPerKg),
       updatedAt = Value(updatedAt);
  static Insertable<Profile> custom({
    Expression<int>? id,
    Expression<double>? heightCm,
    Expression<double>? weightKg,
    Expression<double>? bodyFatPct,
    Expression<int>? age,
    Expression<String>? gender,
    Expression<double>? activityLevel,
    Expression<String>? goal,
    Expression<double>? goalRateKgPerWeek,
    Expression<String>? formula,
    Expression<int>? dailyCalorieTarget,
    Expression<double>? proteinGPerKg,
    Expression<double>? fatGPerKg,
    Expression<double>? carbGPerKg,
    Expression<int>? tdeeAdjustmentKcal,
    Expression<int>? updatedAt,
    Expression<String>? specialCondition,
    Expression<String>? dietPreference,
    Expression<String>? healthCondition,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (heightCm != null) 'height_cm': heightCm,
      if (weightKg != null) 'weight_kg': weightKg,
      if (bodyFatPct != null) 'body_fat_pct': bodyFatPct,
      if (age != null) 'age': age,
      if (gender != null) 'gender': gender,
      if (activityLevel != null) 'activity_level': activityLevel,
      if (goal != null) 'goal': goal,
      if (goalRateKgPerWeek != null) 'goal_rate_kg_per_week': goalRateKgPerWeek,
      if (formula != null) 'formula': formula,
      if (dailyCalorieTarget != null)
        'daily_calorie_target': dailyCalorieTarget,
      if (proteinGPerKg != null) 'protein_g_per_kg': proteinGPerKg,
      if (fatGPerKg != null) 'fat_g_per_kg': fatGPerKg,
      if (carbGPerKg != null) 'carb_g_per_kg': carbGPerKg,
      if (tdeeAdjustmentKcal != null)
        'tdee_adjustment_kcal': tdeeAdjustmentKcal,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (specialCondition != null) 'special_condition': specialCondition,
      if (dietPreference != null) 'diet_preference': dietPreference,
      if (healthCondition != null) 'health_condition': healthCondition,
    });
  }

  ProfilesCompanion copyWith({
    Value<int>? id,
    Value<double>? heightCm,
    Value<double>? weightKg,
    Value<double?>? bodyFatPct,
    Value<int>? age,
    Value<String>? gender,
    Value<double>? activityLevel,
    Value<String>? goal,
    Value<double>? goalRateKgPerWeek,
    Value<String>? formula,
    Value<int>? dailyCalorieTarget,
    Value<double>? proteinGPerKg,
    Value<double>? fatGPerKg,
    Value<double?>? carbGPerKg,
    Value<int>? tdeeAdjustmentKcal,
    Value<int>? updatedAt,
    Value<String?>? specialCondition,
    Value<String?>? dietPreference,
    Value<String?>? healthCondition,
  }) {
    return ProfilesCompanion(
      id: id ?? this.id,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      bodyFatPct: bodyFatPct ?? this.bodyFatPct,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      activityLevel: activityLevel ?? this.activityLevel,
      goal: goal ?? this.goal,
      goalRateKgPerWeek: goalRateKgPerWeek ?? this.goalRateKgPerWeek,
      formula: formula ?? this.formula,
      dailyCalorieTarget: dailyCalorieTarget ?? this.dailyCalorieTarget,
      proteinGPerKg: proteinGPerKg ?? this.proteinGPerKg,
      fatGPerKg: fatGPerKg ?? this.fatGPerKg,
      carbGPerKg: carbGPerKg ?? this.carbGPerKg,
      tdeeAdjustmentKcal: tdeeAdjustmentKcal ?? this.tdeeAdjustmentKcal,
      updatedAt: updatedAt ?? this.updatedAt,
      specialCondition: specialCondition ?? this.specialCondition,
      dietPreference: dietPreference ?? this.dietPreference,
      healthCondition: healthCondition ?? this.healthCondition,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (heightCm.present) {
      map['height_cm'] = Variable<double>(heightCm.value);
    }
    if (weightKg.present) {
      map['weight_kg'] = Variable<double>(weightKg.value);
    }
    if (bodyFatPct.present) {
      map['body_fat_pct'] = Variable<double>(bodyFatPct.value);
    }
    if (age.present) {
      map['age'] = Variable<int>(age.value);
    }
    if (gender.present) {
      map['gender'] = Variable<String>(gender.value);
    }
    if (activityLevel.present) {
      map['activity_level'] = Variable<double>(activityLevel.value);
    }
    if (goal.present) {
      map['goal'] = Variable<String>(goal.value);
    }
    if (goalRateKgPerWeek.present) {
      map['goal_rate_kg_per_week'] = Variable<double>(goalRateKgPerWeek.value);
    }
    if (formula.present) {
      map['formula'] = Variable<String>(formula.value);
    }
    if (dailyCalorieTarget.present) {
      map['daily_calorie_target'] = Variable<int>(dailyCalorieTarget.value);
    }
    if (proteinGPerKg.present) {
      map['protein_g_per_kg'] = Variable<double>(proteinGPerKg.value);
    }
    if (fatGPerKg.present) {
      map['fat_g_per_kg'] = Variable<double>(fatGPerKg.value);
    }
    if (carbGPerKg.present) {
      map['carb_g_per_kg'] = Variable<double>(carbGPerKg.value);
    }
    if (tdeeAdjustmentKcal.present) {
      map['tdee_adjustment_kcal'] = Variable<int>(tdeeAdjustmentKcal.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (specialCondition.present) {
      map['special_condition'] = Variable<String>(specialCondition.value);
    }
    if (dietPreference.present) {
      map['diet_preference'] = Variable<String>(dietPreference.value);
    }
    if (healthCondition.present) {
      map['health_condition'] = Variable<String>(healthCondition.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProfilesCompanion(')
          ..write('id: $id, ')
          ..write('heightCm: $heightCm, ')
          ..write('weightKg: $weightKg, ')
          ..write('bodyFatPct: $bodyFatPct, ')
          ..write('age: $age, ')
          ..write('gender: $gender, ')
          ..write('activityLevel: $activityLevel, ')
          ..write('goal: $goal, ')
          ..write('goalRateKgPerWeek: $goalRateKgPerWeek, ')
          ..write('formula: $formula, ')
          ..write('dailyCalorieTarget: $dailyCalorieTarget, ')
          ..write('proteinGPerKg: $proteinGPerKg, ')
          ..write('fatGPerKg: $fatGPerKg, ')
          ..write('carbGPerKg: $carbGPerKg, ')
          ..write('tdeeAdjustmentKcal: $tdeeAdjustmentKcal, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('specialCondition: $specialCondition, ')
          ..write('dietPreference: $dietPreference, ')
          ..write('healthCondition: $healthCondition')
          ..write(')'))
        .toString();
  }
}

class $FoodItemsTable extends FoodItems
    with TableInfo<$FoodItemsTable, FoodItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FoodItemsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _defaultServingGMeta = const VerificationMeta(
    'defaultServingG',
  );
  @override
  late final GeneratedColumn<double> defaultServingG = GeneratedColumn<double>(
    'default_serving_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _caloriesPer100gMeta = const VerificationMeta(
    'caloriesPer100g',
  );
  @override
  late final GeneratedColumn<double> caloriesPer100g = GeneratedColumn<double>(
    'calories_per100g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _proteinPer100gMeta = const VerificationMeta(
    'proteinPer100g',
  );
  @override
  late final GeneratedColumn<double> proteinPer100g = GeneratedColumn<double>(
    'protein_per100g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fatPer100gMeta = const VerificationMeta(
    'fatPer100g',
  );
  @override
  late final GeneratedColumn<double> fatPer100g = GeneratedColumn<double>(
    'fat_per100g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _carbsPer100gMeta = const VerificationMeta(
    'carbsPer100g',
  );
  @override
  late final GeneratedColumn<double> carbsPer100g = GeneratedColumn<double>(
    'carbs_per100g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _aliasesJsonMeta = const VerificationMeta(
    'aliasesJson',
  );
  @override
  late final GeneratedColumn<String> aliasesJson = GeneratedColumn<String>(
    'aliases_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ediblePercentMeta = const VerificationMeta(
    'ediblePercent',
  );
  @override
  late final GeneratedColumn<double> ediblePercent = GeneratedColumn<double>(
    'edible_percent',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceVersionMeta = const VerificationMeta(
    'sourceVersion',
  );
  @override
  late final GeneratedColumn<String> sourceVersion = GeneratedColumn<String>(
    'source_version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _confidenceMeta = const VerificationMeta(
    'confidence',
  );
  @override
  late final GeneratedColumn<double> confidence = GeneratedColumn<double>(
    'confidence',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _componentsJsonMeta = const VerificationMeta(
    'componentsJson',
  );
  @override
  late final GeneratedColumn<String> componentsJson = GeneratedColumn<String>(
    'components_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _thumbnailPathMeta = const VerificationMeta(
    'thumbnailPath',
  );
  @override
  late final GeneratedColumn<String> thumbnailPath = GeneratedColumn<String>(
    'thumbnail_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    defaultServingG,
    caloriesPer100g,
    proteinPer100g,
    fatPer100g,
    carbsPer100g,
    aliasesJson,
    ediblePercent,
    source,
    sourceVersion,
    confidence,
    componentsJson,
    thumbnailPath,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'food_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<FoodItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('default_serving_g')) {
      context.handle(
        _defaultServingGMeta,
        defaultServingG.isAcceptableOrUnknown(
          data['default_serving_g']!,
          _defaultServingGMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_defaultServingGMeta);
    }
    if (data.containsKey('calories_per100g')) {
      context.handle(
        _caloriesPer100gMeta,
        caloriesPer100g.isAcceptableOrUnknown(
          data['calories_per100g']!,
          _caloriesPer100gMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_caloriesPer100gMeta);
    }
    if (data.containsKey('protein_per100g')) {
      context.handle(
        _proteinPer100gMeta,
        proteinPer100g.isAcceptableOrUnknown(
          data['protein_per100g']!,
          _proteinPer100gMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_proteinPer100gMeta);
    }
    if (data.containsKey('fat_per100g')) {
      context.handle(
        _fatPer100gMeta,
        fatPer100g.isAcceptableOrUnknown(data['fat_per100g']!, _fatPer100gMeta),
      );
    } else if (isInserting) {
      context.missing(_fatPer100gMeta);
    }
    if (data.containsKey('carbs_per100g')) {
      context.handle(
        _carbsPer100gMeta,
        carbsPer100g.isAcceptableOrUnknown(
          data['carbs_per100g']!,
          _carbsPer100gMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_carbsPer100gMeta);
    }
    if (data.containsKey('aliases_json')) {
      context.handle(
        _aliasesJsonMeta,
        aliasesJson.isAcceptableOrUnknown(
          data['aliases_json']!,
          _aliasesJsonMeta,
        ),
      );
    }
    if (data.containsKey('edible_percent')) {
      context.handle(
        _ediblePercentMeta,
        ediblePercent.isAcceptableOrUnknown(
          data['edible_percent']!,
          _ediblePercentMeta,
        ),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('source_version')) {
      context.handle(
        _sourceVersionMeta,
        sourceVersion.isAcceptableOrUnknown(
          data['source_version']!,
          _sourceVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceVersionMeta);
    }
    if (data.containsKey('confidence')) {
      context.handle(
        _confidenceMeta,
        confidence.isAcceptableOrUnknown(data['confidence']!, _confidenceMeta),
      );
    }
    if (data.containsKey('components_json')) {
      context.handle(
        _componentsJsonMeta,
        componentsJson.isAcceptableOrUnknown(
          data['components_json']!,
          _componentsJsonMeta,
        ),
      );
    }
    if (data.containsKey('thumbnail_path')) {
      context.handle(
        _thumbnailPathMeta,
        thumbnailPath.isAcceptableOrUnknown(
          data['thumbnail_path']!,
          _thumbnailPathMeta,
        ),
      );
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FoodItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FoodItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      defaultServingG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}default_serving_g'],
      )!,
      caloriesPer100g: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}calories_per100g'],
      )!,
      proteinPer100g: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}protein_per100g'],
      )!,
      fatPer100g: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}fat_per100g'],
      )!,
      carbsPer100g: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}carbs_per100g'],
      )!,
      aliasesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}aliases_json'],
      ),
      ediblePercent: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}edible_percent'],
      ),
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      sourceVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_version'],
      )!,
      confidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}confidence'],
      ),
      componentsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}components_json'],
      ),
      thumbnailPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumbnail_path'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $FoodItemsTable createAlias(String alias) {
    return $FoodItemsTable(attachedDatabase, alias);
  }
}

class FoodItem extends DataClass implements Insertable<FoodItem> {
  final int id;
  final String name;
  final double defaultServingG;
  final double caloriesPer100g;
  final double proteinPer100g;
  final double fatPer100g;
  final double carbsPer100g;
  final String? aliasesJson;
  final double? ediblePercent;
  final String source;
  final String sourceVersion;
  final double? confidence;
  final String? componentsJson;
  final String? thumbnailPath;
  final int createdAt;
  const FoodItem({
    required this.id,
    required this.name,
    required this.defaultServingG,
    required this.caloriesPer100g,
    required this.proteinPer100g,
    required this.fatPer100g,
    required this.carbsPer100g,
    this.aliasesJson,
    this.ediblePercent,
    required this.source,
    required this.sourceVersion,
    this.confidence,
    this.componentsJson,
    this.thumbnailPath,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['default_serving_g'] = Variable<double>(defaultServingG);
    map['calories_per100g'] = Variable<double>(caloriesPer100g);
    map['protein_per100g'] = Variable<double>(proteinPer100g);
    map['fat_per100g'] = Variable<double>(fatPer100g);
    map['carbs_per100g'] = Variable<double>(carbsPer100g);
    if (!nullToAbsent || aliasesJson != null) {
      map['aliases_json'] = Variable<String>(aliasesJson);
    }
    if (!nullToAbsent || ediblePercent != null) {
      map['edible_percent'] = Variable<double>(ediblePercent);
    }
    map['source'] = Variable<String>(source);
    map['source_version'] = Variable<String>(sourceVersion);
    if (!nullToAbsent || confidence != null) {
      map['confidence'] = Variable<double>(confidence);
    }
    if (!nullToAbsent || componentsJson != null) {
      map['components_json'] = Variable<String>(componentsJson);
    }
    if (!nullToAbsent || thumbnailPath != null) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  FoodItemsCompanion toCompanion(bool nullToAbsent) {
    return FoodItemsCompanion(
      id: Value(id),
      name: Value(name),
      defaultServingG: Value(defaultServingG),
      caloriesPer100g: Value(caloriesPer100g),
      proteinPer100g: Value(proteinPer100g),
      fatPer100g: Value(fatPer100g),
      carbsPer100g: Value(carbsPer100g),
      aliasesJson: aliasesJson == null && nullToAbsent
          ? const Value.absent()
          : Value(aliasesJson),
      ediblePercent: ediblePercent == null && nullToAbsent
          ? const Value.absent()
          : Value(ediblePercent),
      source: Value(source),
      sourceVersion: Value(sourceVersion),
      confidence: confidence == null && nullToAbsent
          ? const Value.absent()
          : Value(confidence),
      componentsJson: componentsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(componentsJson),
      thumbnailPath: thumbnailPath == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailPath),
      createdAt: Value(createdAt),
    );
  }

  factory FoodItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FoodItem(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      defaultServingG: serializer.fromJson<double>(json['defaultServingG']),
      caloriesPer100g: serializer.fromJson<double>(json['caloriesPer100g']),
      proteinPer100g: serializer.fromJson<double>(json['proteinPer100g']),
      fatPer100g: serializer.fromJson<double>(json['fatPer100g']),
      carbsPer100g: serializer.fromJson<double>(json['carbsPer100g']),
      aliasesJson: serializer.fromJson<String?>(json['aliasesJson']),
      ediblePercent: serializer.fromJson<double?>(json['ediblePercent']),
      source: serializer.fromJson<String>(json['source']),
      sourceVersion: serializer.fromJson<String>(json['sourceVersion']),
      confidence: serializer.fromJson<double?>(json['confidence']),
      componentsJson: serializer.fromJson<String?>(json['componentsJson']),
      thumbnailPath: serializer.fromJson<String?>(json['thumbnailPath']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'defaultServingG': serializer.toJson<double>(defaultServingG),
      'caloriesPer100g': serializer.toJson<double>(caloriesPer100g),
      'proteinPer100g': serializer.toJson<double>(proteinPer100g),
      'fatPer100g': serializer.toJson<double>(fatPer100g),
      'carbsPer100g': serializer.toJson<double>(carbsPer100g),
      'aliasesJson': serializer.toJson<String?>(aliasesJson),
      'ediblePercent': serializer.toJson<double?>(ediblePercent),
      'source': serializer.toJson<String>(source),
      'sourceVersion': serializer.toJson<String>(sourceVersion),
      'confidence': serializer.toJson<double?>(confidence),
      'componentsJson': serializer.toJson<String?>(componentsJson),
      'thumbnailPath': serializer.toJson<String?>(thumbnailPath),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  FoodItem copyWith({
    int? id,
    String? name,
    double? defaultServingG,
    double? caloriesPer100g,
    double? proteinPer100g,
    double? fatPer100g,
    double? carbsPer100g,
    Value<String?> aliasesJson = const Value.absent(),
    Value<double?> ediblePercent = const Value.absent(),
    String? source,
    String? sourceVersion,
    Value<double?> confidence = const Value.absent(),
    Value<String?> componentsJson = const Value.absent(),
    Value<String?> thumbnailPath = const Value.absent(),
    int? createdAt,
  }) => FoodItem(
    id: id ?? this.id,
    name: name ?? this.name,
    defaultServingG: defaultServingG ?? this.defaultServingG,
    caloriesPer100g: caloriesPer100g ?? this.caloriesPer100g,
    proteinPer100g: proteinPer100g ?? this.proteinPer100g,
    fatPer100g: fatPer100g ?? this.fatPer100g,
    carbsPer100g: carbsPer100g ?? this.carbsPer100g,
    aliasesJson: aliasesJson.present ? aliasesJson.value : this.aliasesJson,
    ediblePercent: ediblePercent.present
        ? ediblePercent.value
        : this.ediblePercent,
    source: source ?? this.source,
    sourceVersion: sourceVersion ?? this.sourceVersion,
    confidence: confidence.present ? confidence.value : this.confidence,
    componentsJson: componentsJson.present
        ? componentsJson.value
        : this.componentsJson,
    thumbnailPath: thumbnailPath.present
        ? thumbnailPath.value
        : this.thumbnailPath,
    createdAt: createdAt ?? this.createdAt,
  );
  FoodItem copyWithCompanion(FoodItemsCompanion data) {
    return FoodItem(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      defaultServingG: data.defaultServingG.present
          ? data.defaultServingG.value
          : this.defaultServingG,
      caloriesPer100g: data.caloriesPer100g.present
          ? data.caloriesPer100g.value
          : this.caloriesPer100g,
      proteinPer100g: data.proteinPer100g.present
          ? data.proteinPer100g.value
          : this.proteinPer100g,
      fatPer100g: data.fatPer100g.present
          ? data.fatPer100g.value
          : this.fatPer100g,
      carbsPer100g: data.carbsPer100g.present
          ? data.carbsPer100g.value
          : this.carbsPer100g,
      aliasesJson: data.aliasesJson.present
          ? data.aliasesJson.value
          : this.aliasesJson,
      ediblePercent: data.ediblePercent.present
          ? data.ediblePercent.value
          : this.ediblePercent,
      source: data.source.present ? data.source.value : this.source,
      sourceVersion: data.sourceVersion.present
          ? data.sourceVersion.value
          : this.sourceVersion,
      confidence: data.confidence.present
          ? data.confidence.value
          : this.confidence,
      componentsJson: data.componentsJson.present
          ? data.componentsJson.value
          : this.componentsJson,
      thumbnailPath: data.thumbnailPath.present
          ? data.thumbnailPath.value
          : this.thumbnailPath,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FoodItem(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('defaultServingG: $defaultServingG, ')
          ..write('caloriesPer100g: $caloriesPer100g, ')
          ..write('proteinPer100g: $proteinPer100g, ')
          ..write('fatPer100g: $fatPer100g, ')
          ..write('carbsPer100g: $carbsPer100g, ')
          ..write('aliasesJson: $aliasesJson, ')
          ..write('ediblePercent: $ediblePercent, ')
          ..write('source: $source, ')
          ..write('sourceVersion: $sourceVersion, ')
          ..write('confidence: $confidence, ')
          ..write('componentsJson: $componentsJson, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    defaultServingG,
    caloriesPer100g,
    proteinPer100g,
    fatPer100g,
    carbsPer100g,
    aliasesJson,
    ediblePercent,
    source,
    sourceVersion,
    confidence,
    componentsJson,
    thumbnailPath,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FoodItem &&
          other.id == this.id &&
          other.name == this.name &&
          other.defaultServingG == this.defaultServingG &&
          other.caloriesPer100g == this.caloriesPer100g &&
          other.proteinPer100g == this.proteinPer100g &&
          other.fatPer100g == this.fatPer100g &&
          other.carbsPer100g == this.carbsPer100g &&
          other.aliasesJson == this.aliasesJson &&
          other.ediblePercent == this.ediblePercent &&
          other.source == this.source &&
          other.sourceVersion == this.sourceVersion &&
          other.confidence == this.confidence &&
          other.componentsJson == this.componentsJson &&
          other.thumbnailPath == this.thumbnailPath &&
          other.createdAt == this.createdAt);
}

class FoodItemsCompanion extends UpdateCompanion<FoodItem> {
  final Value<int> id;
  final Value<String> name;
  final Value<double> defaultServingG;
  final Value<double> caloriesPer100g;
  final Value<double> proteinPer100g;
  final Value<double> fatPer100g;
  final Value<double> carbsPer100g;
  final Value<String?> aliasesJson;
  final Value<double?> ediblePercent;
  final Value<String> source;
  final Value<String> sourceVersion;
  final Value<double?> confidence;
  final Value<String?> componentsJson;
  final Value<String?> thumbnailPath;
  final Value<int> createdAt;
  const FoodItemsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.defaultServingG = const Value.absent(),
    this.caloriesPer100g = const Value.absent(),
    this.proteinPer100g = const Value.absent(),
    this.fatPer100g = const Value.absent(),
    this.carbsPer100g = const Value.absent(),
    this.aliasesJson = const Value.absent(),
    this.ediblePercent = const Value.absent(),
    this.source = const Value.absent(),
    this.sourceVersion = const Value.absent(),
    this.confidence = const Value.absent(),
    this.componentsJson = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  FoodItemsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required double defaultServingG,
    required double caloriesPer100g,
    required double proteinPer100g,
    required double fatPer100g,
    required double carbsPer100g,
    this.aliasesJson = const Value.absent(),
    this.ediblePercent = const Value.absent(),
    required String source,
    required String sourceVersion,
    this.confidence = const Value.absent(),
    this.componentsJson = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    required int createdAt,
  }) : name = Value(name),
       defaultServingG = Value(defaultServingG),
       caloriesPer100g = Value(caloriesPer100g),
       proteinPer100g = Value(proteinPer100g),
       fatPer100g = Value(fatPer100g),
       carbsPer100g = Value(carbsPer100g),
       source = Value(source),
       sourceVersion = Value(sourceVersion),
       createdAt = Value(createdAt);
  static Insertable<FoodItem> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<double>? defaultServingG,
    Expression<double>? caloriesPer100g,
    Expression<double>? proteinPer100g,
    Expression<double>? fatPer100g,
    Expression<double>? carbsPer100g,
    Expression<String>? aliasesJson,
    Expression<double>? ediblePercent,
    Expression<String>? source,
    Expression<String>? sourceVersion,
    Expression<double>? confidence,
    Expression<String>? componentsJson,
    Expression<String>? thumbnailPath,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (defaultServingG != null) 'default_serving_g': defaultServingG,
      if (caloriesPer100g != null) 'calories_per100g': caloriesPer100g,
      if (proteinPer100g != null) 'protein_per100g': proteinPer100g,
      if (fatPer100g != null) 'fat_per100g': fatPer100g,
      if (carbsPer100g != null) 'carbs_per100g': carbsPer100g,
      if (aliasesJson != null) 'aliases_json': aliasesJson,
      if (ediblePercent != null) 'edible_percent': ediblePercent,
      if (source != null) 'source': source,
      if (sourceVersion != null) 'source_version': sourceVersion,
      if (confidence != null) 'confidence': confidence,
      if (componentsJson != null) 'components_json': componentsJson,
      if (thumbnailPath != null) 'thumbnail_path': thumbnailPath,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  FoodItemsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<double>? defaultServingG,
    Value<double>? caloriesPer100g,
    Value<double>? proteinPer100g,
    Value<double>? fatPer100g,
    Value<double>? carbsPer100g,
    Value<String?>? aliasesJson,
    Value<double?>? ediblePercent,
    Value<String>? source,
    Value<String>? sourceVersion,
    Value<double?>? confidence,
    Value<String?>? componentsJson,
    Value<String?>? thumbnailPath,
    Value<int>? createdAt,
  }) {
    return FoodItemsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      defaultServingG: defaultServingG ?? this.defaultServingG,
      caloriesPer100g: caloriesPer100g ?? this.caloriesPer100g,
      proteinPer100g: proteinPer100g ?? this.proteinPer100g,
      fatPer100g: fatPer100g ?? this.fatPer100g,
      carbsPer100g: carbsPer100g ?? this.carbsPer100g,
      aliasesJson: aliasesJson ?? this.aliasesJson,
      ediblePercent: ediblePercent ?? this.ediblePercent,
      source: source ?? this.source,
      sourceVersion: sourceVersion ?? this.sourceVersion,
      confidence: confidence ?? this.confidence,
      componentsJson: componentsJson ?? this.componentsJson,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (defaultServingG.present) {
      map['default_serving_g'] = Variable<double>(defaultServingG.value);
    }
    if (caloriesPer100g.present) {
      map['calories_per100g'] = Variable<double>(caloriesPer100g.value);
    }
    if (proteinPer100g.present) {
      map['protein_per100g'] = Variable<double>(proteinPer100g.value);
    }
    if (fatPer100g.present) {
      map['fat_per100g'] = Variable<double>(fatPer100g.value);
    }
    if (carbsPer100g.present) {
      map['carbs_per100g'] = Variable<double>(carbsPer100g.value);
    }
    if (aliasesJson.present) {
      map['aliases_json'] = Variable<String>(aliasesJson.value);
    }
    if (ediblePercent.present) {
      map['edible_percent'] = Variable<double>(ediblePercent.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (sourceVersion.present) {
      map['source_version'] = Variable<String>(sourceVersion.value);
    }
    if (confidence.present) {
      map['confidence'] = Variable<double>(confidence.value);
    }
    if (componentsJson.present) {
      map['components_json'] = Variable<String>(componentsJson.value);
    }
    if (thumbnailPath.present) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FoodItemsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('defaultServingG: $defaultServingG, ')
          ..write('caloriesPer100g: $caloriesPer100g, ')
          ..write('proteinPer100g: $proteinPer100g, ')
          ..write('fatPer100g: $fatPer100g, ')
          ..write('carbsPer100g: $carbsPer100g, ')
          ..write('aliasesJson: $aliasesJson, ')
          ..write('ediblePercent: $ediblePercent, ')
          ..write('source: $source, ')
          ..write('sourceVersion: $sourceVersion, ')
          ..write('confidence: $confidence, ')
          ..write('componentsJson: $componentsJson, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $MealLogsTable extends MealLogs with TableInfo<$MealLogsTable, MealLog> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MealLogsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mealTypeMeta = const VerificationMeta(
    'mealType',
  );
  @override
  late final GeneratedColumn<String> mealType = GeneratedColumn<String>(
    'meal_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _foodItemIdMeta = const VerificationMeta(
    'foodItemId',
  );
  @override
  late final GeneratedColumn<int> foodItemId = GeneratedColumn<int>(
    'food_item_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES food_items (id)',
    ),
  );
  static const VerificationMeta _actualServingGMeta = const VerificationMeta(
    'actualServingG',
  );
  @override
  late final GeneratedColumn<double> actualServingG = GeneratedColumn<double>(
    'actual_serving_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actualCaloriesMeta = const VerificationMeta(
    'actualCalories',
  );
  @override
  late final GeneratedColumn<double> actualCalories = GeneratedColumn<double>(
    'actual_calories',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actualProteinGMeta = const VerificationMeta(
    'actualProteinG',
  );
  @override
  late final GeneratedColumn<double> actualProteinG = GeneratedColumn<double>(
    'actual_protein_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actualFatGMeta = const VerificationMeta(
    'actualFatG',
  );
  @override
  late final GeneratedColumn<double> actualFatG = GeneratedColumn<double>(
    'actual_fat_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actualCarbsGMeta = const VerificationMeta(
    'actualCarbsG',
  );
  @override
  late final GeneratedColumn<double> actualCarbsG = GeneratedColumn<double>(
    'actual_carbs_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originalImagePathMeta = const VerificationMeta(
    'originalImagePath',
  );
  @override
  late final GeneratedColumn<String> originalImagePath =
      GeneratedColumn<String>(
        'original_image_path',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _recognitionConfidenceMeta =
      const VerificationMeta('recognitionConfidence');
  @override
  late final GeneratedColumn<double> recognitionConfidence =
      GeneratedColumn<double>(
        'recognition_confidence',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _componentsSnapshotJsonMeta =
      const VerificationMeta('componentsSnapshotJson');
  @override
  late final GeneratedColumn<String> componentsSnapshotJson =
      GeneratedColumn<String>(
        'components_snapshot_json',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _loggedAtMeta = const VerificationMeta(
    'loggedAt',
  );
  @override
  late final GeneratedColumn<int> loggedAt = GeneratedColumn<int>(
    'logged_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    date,
    mealType,
    foodItemId,
    actualServingG,
    actualCalories,
    actualProteinG,
    actualFatG,
    actualCarbsG,
    originalImagePath,
    recognitionConfidence,
    componentsSnapshotJson,
    loggedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'meal_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<MealLog> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('meal_type')) {
      context.handle(
        _mealTypeMeta,
        mealType.isAcceptableOrUnknown(data['meal_type']!, _mealTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mealTypeMeta);
    }
    if (data.containsKey('food_item_id')) {
      context.handle(
        _foodItemIdMeta,
        foodItemId.isAcceptableOrUnknown(
          data['food_item_id']!,
          _foodItemIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_foodItemIdMeta);
    }
    if (data.containsKey('actual_serving_g')) {
      context.handle(
        _actualServingGMeta,
        actualServingG.isAcceptableOrUnknown(
          data['actual_serving_g']!,
          _actualServingGMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_actualServingGMeta);
    }
    if (data.containsKey('actual_calories')) {
      context.handle(
        _actualCaloriesMeta,
        actualCalories.isAcceptableOrUnknown(
          data['actual_calories']!,
          _actualCaloriesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_actualCaloriesMeta);
    }
    if (data.containsKey('actual_protein_g')) {
      context.handle(
        _actualProteinGMeta,
        actualProteinG.isAcceptableOrUnknown(
          data['actual_protein_g']!,
          _actualProteinGMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_actualProteinGMeta);
    }
    if (data.containsKey('actual_fat_g')) {
      context.handle(
        _actualFatGMeta,
        actualFatG.isAcceptableOrUnknown(
          data['actual_fat_g']!,
          _actualFatGMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_actualFatGMeta);
    }
    if (data.containsKey('actual_carbs_g')) {
      context.handle(
        _actualCarbsGMeta,
        actualCarbsG.isAcceptableOrUnknown(
          data['actual_carbs_g']!,
          _actualCarbsGMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_actualCarbsGMeta);
    }
    if (data.containsKey('original_image_path')) {
      context.handle(
        _originalImagePathMeta,
        originalImagePath.isAcceptableOrUnknown(
          data['original_image_path']!,
          _originalImagePathMeta,
        ),
      );
    }
    if (data.containsKey('recognition_confidence')) {
      context.handle(
        _recognitionConfidenceMeta,
        recognitionConfidence.isAcceptableOrUnknown(
          data['recognition_confidence']!,
          _recognitionConfidenceMeta,
        ),
      );
    }
    if (data.containsKey('components_snapshot_json')) {
      context.handle(
        _componentsSnapshotJsonMeta,
        componentsSnapshotJson.isAcceptableOrUnknown(
          data['components_snapshot_json']!,
          _componentsSnapshotJsonMeta,
        ),
      );
    }
    if (data.containsKey('logged_at')) {
      context.handle(
        _loggedAtMeta,
        loggedAt.isAcceptableOrUnknown(data['logged_at']!, _loggedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_loggedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MealLog map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MealLog(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      mealType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}meal_type'],
      )!,
      foodItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}food_item_id'],
      )!,
      actualServingG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}actual_serving_g'],
      )!,
      actualCalories: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}actual_calories'],
      )!,
      actualProteinG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}actual_protein_g'],
      )!,
      actualFatG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}actual_fat_g'],
      )!,
      actualCarbsG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}actual_carbs_g'],
      )!,
      originalImagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_image_path'],
      ),
      recognitionConfidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}recognition_confidence'],
      ),
      componentsSnapshotJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}components_snapshot_json'],
      ),
      loggedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}logged_at'],
      )!,
    );
  }

  @override
  $MealLogsTable createAlias(String alias) {
    return $MealLogsTable(attachedDatabase, alias);
  }
}

class MealLog extends DataClass implements Insertable<MealLog> {
  final int id;
  final String date;
  final String mealType;
  final int foodItemId;
  final double actualServingG;
  final double actualCalories;
  final double actualProteinG;
  final double actualFatG;
  final double actualCarbsG;
  final String? originalImagePath;
  final double? recognitionConfidence;
  final String? componentsSnapshotJson;
  final int loggedAt;
  const MealLog({
    required this.id,
    required this.date,
    required this.mealType,
    required this.foodItemId,
    required this.actualServingG,
    required this.actualCalories,
    required this.actualProteinG,
    required this.actualFatG,
    required this.actualCarbsG,
    this.originalImagePath,
    this.recognitionConfidence,
    this.componentsSnapshotJson,
    required this.loggedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['date'] = Variable<String>(date);
    map['meal_type'] = Variable<String>(mealType);
    map['food_item_id'] = Variable<int>(foodItemId);
    map['actual_serving_g'] = Variable<double>(actualServingG);
    map['actual_calories'] = Variable<double>(actualCalories);
    map['actual_protein_g'] = Variable<double>(actualProteinG);
    map['actual_fat_g'] = Variable<double>(actualFatG);
    map['actual_carbs_g'] = Variable<double>(actualCarbsG);
    if (!nullToAbsent || originalImagePath != null) {
      map['original_image_path'] = Variable<String>(originalImagePath);
    }
    if (!nullToAbsent || recognitionConfidence != null) {
      map['recognition_confidence'] = Variable<double>(recognitionConfidence);
    }
    if (!nullToAbsent || componentsSnapshotJson != null) {
      map['components_snapshot_json'] = Variable<String>(
        componentsSnapshotJson,
      );
    }
    map['logged_at'] = Variable<int>(loggedAt);
    return map;
  }

  MealLogsCompanion toCompanion(bool nullToAbsent) {
    return MealLogsCompanion(
      id: Value(id),
      date: Value(date),
      mealType: Value(mealType),
      foodItemId: Value(foodItemId),
      actualServingG: Value(actualServingG),
      actualCalories: Value(actualCalories),
      actualProteinG: Value(actualProteinG),
      actualFatG: Value(actualFatG),
      actualCarbsG: Value(actualCarbsG),
      originalImagePath: originalImagePath == null && nullToAbsent
          ? const Value.absent()
          : Value(originalImagePath),
      recognitionConfidence: recognitionConfidence == null && nullToAbsent
          ? const Value.absent()
          : Value(recognitionConfidence),
      componentsSnapshotJson: componentsSnapshotJson == null && nullToAbsent
          ? const Value.absent()
          : Value(componentsSnapshotJson),
      loggedAt: Value(loggedAt),
    );
  }

  factory MealLog.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MealLog(
      id: serializer.fromJson<int>(json['id']),
      date: serializer.fromJson<String>(json['date']),
      mealType: serializer.fromJson<String>(json['mealType']),
      foodItemId: serializer.fromJson<int>(json['foodItemId']),
      actualServingG: serializer.fromJson<double>(json['actualServingG']),
      actualCalories: serializer.fromJson<double>(json['actualCalories']),
      actualProteinG: serializer.fromJson<double>(json['actualProteinG']),
      actualFatG: serializer.fromJson<double>(json['actualFatG']),
      actualCarbsG: serializer.fromJson<double>(json['actualCarbsG']),
      originalImagePath: serializer.fromJson<String?>(
        json['originalImagePath'],
      ),
      recognitionConfidence: serializer.fromJson<double?>(
        json['recognitionConfidence'],
      ),
      componentsSnapshotJson: serializer.fromJson<String?>(
        json['componentsSnapshotJson'],
      ),
      loggedAt: serializer.fromJson<int>(json['loggedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'date': serializer.toJson<String>(date),
      'mealType': serializer.toJson<String>(mealType),
      'foodItemId': serializer.toJson<int>(foodItemId),
      'actualServingG': serializer.toJson<double>(actualServingG),
      'actualCalories': serializer.toJson<double>(actualCalories),
      'actualProteinG': serializer.toJson<double>(actualProteinG),
      'actualFatG': serializer.toJson<double>(actualFatG),
      'actualCarbsG': serializer.toJson<double>(actualCarbsG),
      'originalImagePath': serializer.toJson<String?>(originalImagePath),
      'recognitionConfidence': serializer.toJson<double?>(
        recognitionConfidence,
      ),
      'componentsSnapshotJson': serializer.toJson<String?>(
        componentsSnapshotJson,
      ),
      'loggedAt': serializer.toJson<int>(loggedAt),
    };
  }

  MealLog copyWith({
    int? id,
    String? date,
    String? mealType,
    int? foodItemId,
    double? actualServingG,
    double? actualCalories,
    double? actualProteinG,
    double? actualFatG,
    double? actualCarbsG,
    Value<String?> originalImagePath = const Value.absent(),
    Value<double?> recognitionConfidence = const Value.absent(),
    Value<String?> componentsSnapshotJson = const Value.absent(),
    int? loggedAt,
  }) => MealLog(
    id: id ?? this.id,
    date: date ?? this.date,
    mealType: mealType ?? this.mealType,
    foodItemId: foodItemId ?? this.foodItemId,
    actualServingG: actualServingG ?? this.actualServingG,
    actualCalories: actualCalories ?? this.actualCalories,
    actualProteinG: actualProteinG ?? this.actualProteinG,
    actualFatG: actualFatG ?? this.actualFatG,
    actualCarbsG: actualCarbsG ?? this.actualCarbsG,
    originalImagePath: originalImagePath.present
        ? originalImagePath.value
        : this.originalImagePath,
    recognitionConfidence: recognitionConfidence.present
        ? recognitionConfidence.value
        : this.recognitionConfidence,
    componentsSnapshotJson: componentsSnapshotJson.present
        ? componentsSnapshotJson.value
        : this.componentsSnapshotJson,
    loggedAt: loggedAt ?? this.loggedAt,
  );
  MealLog copyWithCompanion(MealLogsCompanion data) {
    return MealLog(
      id: data.id.present ? data.id.value : this.id,
      date: data.date.present ? data.date.value : this.date,
      mealType: data.mealType.present ? data.mealType.value : this.mealType,
      foodItemId: data.foodItemId.present
          ? data.foodItemId.value
          : this.foodItemId,
      actualServingG: data.actualServingG.present
          ? data.actualServingG.value
          : this.actualServingG,
      actualCalories: data.actualCalories.present
          ? data.actualCalories.value
          : this.actualCalories,
      actualProteinG: data.actualProteinG.present
          ? data.actualProteinG.value
          : this.actualProteinG,
      actualFatG: data.actualFatG.present
          ? data.actualFatG.value
          : this.actualFatG,
      actualCarbsG: data.actualCarbsG.present
          ? data.actualCarbsG.value
          : this.actualCarbsG,
      originalImagePath: data.originalImagePath.present
          ? data.originalImagePath.value
          : this.originalImagePath,
      recognitionConfidence: data.recognitionConfidence.present
          ? data.recognitionConfidence.value
          : this.recognitionConfidence,
      componentsSnapshotJson: data.componentsSnapshotJson.present
          ? data.componentsSnapshotJson.value
          : this.componentsSnapshotJson,
      loggedAt: data.loggedAt.present ? data.loggedAt.value : this.loggedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MealLog(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('mealType: $mealType, ')
          ..write('foodItemId: $foodItemId, ')
          ..write('actualServingG: $actualServingG, ')
          ..write('actualCalories: $actualCalories, ')
          ..write('actualProteinG: $actualProteinG, ')
          ..write('actualFatG: $actualFatG, ')
          ..write('actualCarbsG: $actualCarbsG, ')
          ..write('originalImagePath: $originalImagePath, ')
          ..write('recognitionConfidence: $recognitionConfidence, ')
          ..write('componentsSnapshotJson: $componentsSnapshotJson, ')
          ..write('loggedAt: $loggedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    date,
    mealType,
    foodItemId,
    actualServingG,
    actualCalories,
    actualProteinG,
    actualFatG,
    actualCarbsG,
    originalImagePath,
    recognitionConfidence,
    componentsSnapshotJson,
    loggedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MealLog &&
          other.id == this.id &&
          other.date == this.date &&
          other.mealType == this.mealType &&
          other.foodItemId == this.foodItemId &&
          other.actualServingG == this.actualServingG &&
          other.actualCalories == this.actualCalories &&
          other.actualProteinG == this.actualProteinG &&
          other.actualFatG == this.actualFatG &&
          other.actualCarbsG == this.actualCarbsG &&
          other.originalImagePath == this.originalImagePath &&
          other.recognitionConfidence == this.recognitionConfidence &&
          other.componentsSnapshotJson == this.componentsSnapshotJson &&
          other.loggedAt == this.loggedAt);
}

class MealLogsCompanion extends UpdateCompanion<MealLog> {
  final Value<int> id;
  final Value<String> date;
  final Value<String> mealType;
  final Value<int> foodItemId;
  final Value<double> actualServingG;
  final Value<double> actualCalories;
  final Value<double> actualProteinG;
  final Value<double> actualFatG;
  final Value<double> actualCarbsG;
  final Value<String?> originalImagePath;
  final Value<double?> recognitionConfidence;
  final Value<String?> componentsSnapshotJson;
  final Value<int> loggedAt;
  const MealLogsCompanion({
    this.id = const Value.absent(),
    this.date = const Value.absent(),
    this.mealType = const Value.absent(),
    this.foodItemId = const Value.absent(),
    this.actualServingG = const Value.absent(),
    this.actualCalories = const Value.absent(),
    this.actualProteinG = const Value.absent(),
    this.actualFatG = const Value.absent(),
    this.actualCarbsG = const Value.absent(),
    this.originalImagePath = const Value.absent(),
    this.recognitionConfidence = const Value.absent(),
    this.componentsSnapshotJson = const Value.absent(),
    this.loggedAt = const Value.absent(),
  });
  MealLogsCompanion.insert({
    this.id = const Value.absent(),
    required String date,
    required String mealType,
    required int foodItemId,
    required double actualServingG,
    required double actualCalories,
    required double actualProteinG,
    required double actualFatG,
    required double actualCarbsG,
    this.originalImagePath = const Value.absent(),
    this.recognitionConfidence = const Value.absent(),
    this.componentsSnapshotJson = const Value.absent(),
    required int loggedAt,
  }) : date = Value(date),
       mealType = Value(mealType),
       foodItemId = Value(foodItemId),
       actualServingG = Value(actualServingG),
       actualCalories = Value(actualCalories),
       actualProteinG = Value(actualProteinG),
       actualFatG = Value(actualFatG),
       actualCarbsG = Value(actualCarbsG),
       loggedAt = Value(loggedAt);
  static Insertable<MealLog> custom({
    Expression<int>? id,
    Expression<String>? date,
    Expression<String>? mealType,
    Expression<int>? foodItemId,
    Expression<double>? actualServingG,
    Expression<double>? actualCalories,
    Expression<double>? actualProteinG,
    Expression<double>? actualFatG,
    Expression<double>? actualCarbsG,
    Expression<String>? originalImagePath,
    Expression<double>? recognitionConfidence,
    Expression<String>? componentsSnapshotJson,
    Expression<int>? loggedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (date != null) 'date': date,
      if (mealType != null) 'meal_type': mealType,
      if (foodItemId != null) 'food_item_id': foodItemId,
      if (actualServingG != null) 'actual_serving_g': actualServingG,
      if (actualCalories != null) 'actual_calories': actualCalories,
      if (actualProteinG != null) 'actual_protein_g': actualProteinG,
      if (actualFatG != null) 'actual_fat_g': actualFatG,
      if (actualCarbsG != null) 'actual_carbs_g': actualCarbsG,
      if (originalImagePath != null) 'original_image_path': originalImagePath,
      if (recognitionConfidence != null)
        'recognition_confidence': recognitionConfidence,
      if (componentsSnapshotJson != null)
        'components_snapshot_json': componentsSnapshotJson,
      if (loggedAt != null) 'logged_at': loggedAt,
    });
  }

  MealLogsCompanion copyWith({
    Value<int>? id,
    Value<String>? date,
    Value<String>? mealType,
    Value<int>? foodItemId,
    Value<double>? actualServingG,
    Value<double>? actualCalories,
    Value<double>? actualProteinG,
    Value<double>? actualFatG,
    Value<double>? actualCarbsG,
    Value<String?>? originalImagePath,
    Value<double?>? recognitionConfidence,
    Value<String?>? componentsSnapshotJson,
    Value<int>? loggedAt,
  }) {
    return MealLogsCompanion(
      id: id ?? this.id,
      date: date ?? this.date,
      mealType: mealType ?? this.mealType,
      foodItemId: foodItemId ?? this.foodItemId,
      actualServingG: actualServingG ?? this.actualServingG,
      actualCalories: actualCalories ?? this.actualCalories,
      actualProteinG: actualProteinG ?? this.actualProteinG,
      actualFatG: actualFatG ?? this.actualFatG,
      actualCarbsG: actualCarbsG ?? this.actualCarbsG,
      originalImagePath: originalImagePath ?? this.originalImagePath,
      recognitionConfidence:
          recognitionConfidence ?? this.recognitionConfidence,
      componentsSnapshotJson:
          componentsSnapshotJson ?? this.componentsSnapshotJson,
      loggedAt: loggedAt ?? this.loggedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (mealType.present) {
      map['meal_type'] = Variable<String>(mealType.value);
    }
    if (foodItemId.present) {
      map['food_item_id'] = Variable<int>(foodItemId.value);
    }
    if (actualServingG.present) {
      map['actual_serving_g'] = Variable<double>(actualServingG.value);
    }
    if (actualCalories.present) {
      map['actual_calories'] = Variable<double>(actualCalories.value);
    }
    if (actualProteinG.present) {
      map['actual_protein_g'] = Variable<double>(actualProteinG.value);
    }
    if (actualFatG.present) {
      map['actual_fat_g'] = Variable<double>(actualFatG.value);
    }
    if (actualCarbsG.present) {
      map['actual_carbs_g'] = Variable<double>(actualCarbsG.value);
    }
    if (originalImagePath.present) {
      map['original_image_path'] = Variable<String>(originalImagePath.value);
    }
    if (recognitionConfidence.present) {
      map['recognition_confidence'] = Variable<double>(
        recognitionConfidence.value,
      );
    }
    if (componentsSnapshotJson.present) {
      map['components_snapshot_json'] = Variable<String>(
        componentsSnapshotJson.value,
      );
    }
    if (loggedAt.present) {
      map['logged_at'] = Variable<int>(loggedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MealLogsCompanion(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('mealType: $mealType, ')
          ..write('foodItemId: $foodItemId, ')
          ..write('actualServingG: $actualServingG, ')
          ..write('actualCalories: $actualCalories, ')
          ..write('actualProteinG: $actualProteinG, ')
          ..write('actualFatG: $actualFatG, ')
          ..write('actualCarbsG: $actualCarbsG, ')
          ..write('originalImagePath: $originalImagePath, ')
          ..write('recognitionConfidence: $recognitionConfidence, ')
          ..write('componentsSnapshotJson: $componentsSnapshotJson, ')
          ..write('loggedAt: $loggedAt')
          ..write(')'))
        .toString();
  }
}

class $WeightLogsTable extends WeightLogs
    with TableInfo<$WeightLogsTable, WeightLog> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WeightLogsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _weightKgMeta = const VerificationMeta(
    'weightKg',
  );
  @override
  late final GeneratedColumn<double> weightKg = GeneratedColumn<double>(
    'weight_kg',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, date, weightKg];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'weight_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<WeightLog> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('weight_kg')) {
      context.handle(
        _weightKgMeta,
        weightKg.isAcceptableOrUnknown(data['weight_kg']!, _weightKgMeta),
      );
    } else if (isInserting) {
      context.missing(_weightKgMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WeightLog map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WeightLog(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      weightKg: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}weight_kg'],
      )!,
    );
  }

  @override
  $WeightLogsTable createAlias(String alias) {
    return $WeightLogsTable(attachedDatabase, alias);
  }
}

class WeightLog extends DataClass implements Insertable<WeightLog> {
  final int id;
  final String date;
  final double weightKg;
  const WeightLog({
    required this.id,
    required this.date,
    required this.weightKg,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['date'] = Variable<String>(date);
    map['weight_kg'] = Variable<double>(weightKg);
    return map;
  }

  WeightLogsCompanion toCompanion(bool nullToAbsent) {
    return WeightLogsCompanion(
      id: Value(id),
      date: Value(date),
      weightKg: Value(weightKg),
    );
  }

  factory WeightLog.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WeightLog(
      id: serializer.fromJson<int>(json['id']),
      date: serializer.fromJson<String>(json['date']),
      weightKg: serializer.fromJson<double>(json['weightKg']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'date': serializer.toJson<String>(date),
      'weightKg': serializer.toJson<double>(weightKg),
    };
  }

  WeightLog copyWith({int? id, String? date, double? weightKg}) => WeightLog(
    id: id ?? this.id,
    date: date ?? this.date,
    weightKg: weightKg ?? this.weightKg,
  );
  WeightLog copyWithCompanion(WeightLogsCompanion data) {
    return WeightLog(
      id: data.id.present ? data.id.value : this.id,
      date: data.date.present ? data.date.value : this.date,
      weightKg: data.weightKg.present ? data.weightKg.value : this.weightKg,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WeightLog(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('weightKg: $weightKg')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, date, weightKg);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WeightLog &&
          other.id == this.id &&
          other.date == this.date &&
          other.weightKg == this.weightKg);
}

class WeightLogsCompanion extends UpdateCompanion<WeightLog> {
  final Value<int> id;
  final Value<String> date;
  final Value<double> weightKg;
  const WeightLogsCompanion({
    this.id = const Value.absent(),
    this.date = const Value.absent(),
    this.weightKg = const Value.absent(),
  });
  WeightLogsCompanion.insert({
    this.id = const Value.absent(),
    required String date,
    required double weightKg,
  }) : date = Value(date),
       weightKg = Value(weightKg);
  static Insertable<WeightLog> custom({
    Expression<int>? id,
    Expression<String>? date,
    Expression<double>? weightKg,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (date != null) 'date': date,
      if (weightKg != null) 'weight_kg': weightKg,
    });
  }

  WeightLogsCompanion copyWith({
    Value<int>? id,
    Value<String>? date,
    Value<double>? weightKg,
  }) {
    return WeightLogsCompanion(
      id: id ?? this.id,
      date: date ?? this.date,
      weightKg: weightKg ?? this.weightKg,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (weightKg.present) {
      map['weight_kg'] = Variable<double>(weightKg.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WeightLogsCompanion(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('weightKg: $weightKg')
          ..write(')'))
        .toString();
  }
}

class $PendingRecognitionsTable extends PendingRecognitions
    with TableInfo<$PendingRecognitionsTable, PendingRecognition> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingRecognitionsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _imagePathMeta = const VerificationMeta(
    'imagePath',
  );
  @override
  late final GeneratedColumn<String> imagePath = GeneratedColumn<String>(
    'image_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mealTypeMeta = const VerificationMeta(
    'mealType',
  );
  @override
  late final GeneratedColumn<String> mealType = GeneratedColumn<String>(
    'meal_type',
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
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _retryCountMeta = const VerificationMeta(
    'retryCount',
  );
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
    'retry_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _resultFoodItemIdMeta = const VerificationMeta(
    'resultFoodItemId',
  );
  @override
  late final GeneratedColumn<int> resultFoodItemId = GeneratedColumn<int>(
    'result_food_item_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES food_items (id)',
    ),
  );
  static const VerificationMeta _errorMessageMeta = const VerificationMeta(
    'errorMessage',
  );
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
    'error_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _promptVersionMeta = const VerificationMeta(
    'promptVersion',
  );
  @override
  late final GeneratedColumn<String> promptVersion = GeneratedColumn<String>(
    'prompt_version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _processedAtMeta = const VerificationMeta(
    'processedAt',
  );
  @override
  late final GeneratedColumn<int> processedAt = GeneratedColumn<int>(
    'processed_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    imagePath,
    mealType,
    date,
    status,
    retryCount,
    resultFoodItemId,
    errorMessage,
    promptVersion,
    createdAt,
    processedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_recognitions';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingRecognition> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('image_path')) {
      context.handle(
        _imagePathMeta,
        imagePath.isAcceptableOrUnknown(data['image_path']!, _imagePathMeta),
      );
    } else if (isInserting) {
      context.missing(_imagePathMeta);
    }
    if (data.containsKey('meal_type')) {
      context.handle(
        _mealTypeMeta,
        mealType.isAcceptableOrUnknown(data['meal_type']!, _mealTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mealTypeMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('retry_count')) {
      context.handle(
        _retryCountMeta,
        retryCount.isAcceptableOrUnknown(data['retry_count']!, _retryCountMeta),
      );
    }
    if (data.containsKey('result_food_item_id')) {
      context.handle(
        _resultFoodItemIdMeta,
        resultFoodItemId.isAcceptableOrUnknown(
          data['result_food_item_id']!,
          _resultFoodItemIdMeta,
        ),
      );
    }
    if (data.containsKey('error_message')) {
      context.handle(
        _errorMessageMeta,
        errorMessage.isAcceptableOrUnknown(
          data['error_message']!,
          _errorMessageMeta,
        ),
      );
    }
    if (data.containsKey('prompt_version')) {
      context.handle(
        _promptVersionMeta,
        promptVersion.isAcceptableOrUnknown(
          data['prompt_version']!,
          _promptVersionMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('processed_at')) {
      context.handle(
        _processedAtMeta,
        processedAt.isAcceptableOrUnknown(
          data['processed_at']!,
          _processedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PendingRecognition map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingRecognition(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      imagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_path'],
      )!,
      mealType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}meal_type'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      retryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retry_count'],
      )!,
      resultFoodItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}result_food_item_id'],
      ),
      errorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_message'],
      ),
      promptVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}prompt_version'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      processedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}processed_at'],
      ),
    );
  }

  @override
  $PendingRecognitionsTable createAlias(String alias) {
    return $PendingRecognitionsTable(attachedDatabase, alias);
  }
}

class PendingRecognition extends DataClass
    implements Insertable<PendingRecognition> {
  final int id;
  final String imagePath;
  final String mealType;
  final String date;
  final String status;
  final int retryCount;
  final int? resultFoodItemId;
  final String? errorMessage;
  final String? promptVersion;
  final int createdAt;
  final int? processedAt;
  const PendingRecognition({
    required this.id,
    required this.imagePath,
    required this.mealType,
    required this.date,
    required this.status,
    required this.retryCount,
    this.resultFoodItemId,
    this.errorMessage,
    this.promptVersion,
    required this.createdAt,
    this.processedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['image_path'] = Variable<String>(imagePath);
    map['meal_type'] = Variable<String>(mealType);
    map['date'] = Variable<String>(date);
    map['status'] = Variable<String>(status);
    map['retry_count'] = Variable<int>(retryCount);
    if (!nullToAbsent || resultFoodItemId != null) {
      map['result_food_item_id'] = Variable<int>(resultFoodItemId);
    }
    if (!nullToAbsent || errorMessage != null) {
      map['error_message'] = Variable<String>(errorMessage);
    }
    if (!nullToAbsent || promptVersion != null) {
      map['prompt_version'] = Variable<String>(promptVersion);
    }
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || processedAt != null) {
      map['processed_at'] = Variable<int>(processedAt);
    }
    return map;
  }

  PendingRecognitionsCompanion toCompanion(bool nullToAbsent) {
    return PendingRecognitionsCompanion(
      id: Value(id),
      imagePath: Value(imagePath),
      mealType: Value(mealType),
      date: Value(date),
      status: Value(status),
      retryCount: Value(retryCount),
      resultFoodItemId: resultFoodItemId == null && nullToAbsent
          ? const Value.absent()
          : Value(resultFoodItemId),
      errorMessage: errorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(errorMessage),
      promptVersion: promptVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(promptVersion),
      createdAt: Value(createdAt),
      processedAt: processedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(processedAt),
    );
  }

  factory PendingRecognition.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingRecognition(
      id: serializer.fromJson<int>(json['id']),
      imagePath: serializer.fromJson<String>(json['imagePath']),
      mealType: serializer.fromJson<String>(json['mealType']),
      date: serializer.fromJson<String>(json['date']),
      status: serializer.fromJson<String>(json['status']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      resultFoodItemId: serializer.fromJson<int?>(json['resultFoodItemId']),
      errorMessage: serializer.fromJson<String?>(json['errorMessage']),
      promptVersion: serializer.fromJson<String?>(json['promptVersion']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      processedAt: serializer.fromJson<int?>(json['processedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'imagePath': serializer.toJson<String>(imagePath),
      'mealType': serializer.toJson<String>(mealType),
      'date': serializer.toJson<String>(date),
      'status': serializer.toJson<String>(status),
      'retryCount': serializer.toJson<int>(retryCount),
      'resultFoodItemId': serializer.toJson<int?>(resultFoodItemId),
      'errorMessage': serializer.toJson<String?>(errorMessage),
      'promptVersion': serializer.toJson<String?>(promptVersion),
      'createdAt': serializer.toJson<int>(createdAt),
      'processedAt': serializer.toJson<int?>(processedAt),
    };
  }

  PendingRecognition copyWith({
    int? id,
    String? imagePath,
    String? mealType,
    String? date,
    String? status,
    int? retryCount,
    Value<int?> resultFoodItemId = const Value.absent(),
    Value<String?> errorMessage = const Value.absent(),
    Value<String?> promptVersion = const Value.absent(),
    int? createdAt,
    Value<int?> processedAt = const Value.absent(),
  }) => PendingRecognition(
    id: id ?? this.id,
    imagePath: imagePath ?? this.imagePath,
    mealType: mealType ?? this.mealType,
    date: date ?? this.date,
    status: status ?? this.status,
    retryCount: retryCount ?? this.retryCount,
    resultFoodItemId: resultFoodItemId.present
        ? resultFoodItemId.value
        : this.resultFoodItemId,
    errorMessage: errorMessage.present ? errorMessage.value : this.errorMessage,
    promptVersion: promptVersion.present
        ? promptVersion.value
        : this.promptVersion,
    createdAt: createdAt ?? this.createdAt,
    processedAt: processedAt.present ? processedAt.value : this.processedAt,
  );
  PendingRecognition copyWithCompanion(PendingRecognitionsCompanion data) {
    return PendingRecognition(
      id: data.id.present ? data.id.value : this.id,
      imagePath: data.imagePath.present ? data.imagePath.value : this.imagePath,
      mealType: data.mealType.present ? data.mealType.value : this.mealType,
      date: data.date.present ? data.date.value : this.date,
      status: data.status.present ? data.status.value : this.status,
      retryCount: data.retryCount.present
          ? data.retryCount.value
          : this.retryCount,
      resultFoodItemId: data.resultFoodItemId.present
          ? data.resultFoodItemId.value
          : this.resultFoodItemId,
      errorMessage: data.errorMessage.present
          ? data.errorMessage.value
          : this.errorMessage,
      promptVersion: data.promptVersion.present
          ? data.promptVersion.value
          : this.promptVersion,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      processedAt: data.processedAt.present
          ? data.processedAt.value
          : this.processedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingRecognition(')
          ..write('id: $id, ')
          ..write('imagePath: $imagePath, ')
          ..write('mealType: $mealType, ')
          ..write('date: $date, ')
          ..write('status: $status, ')
          ..write('retryCount: $retryCount, ')
          ..write('resultFoodItemId: $resultFoodItemId, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('promptVersion: $promptVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('processedAt: $processedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    imagePath,
    mealType,
    date,
    status,
    retryCount,
    resultFoodItemId,
    errorMessage,
    promptVersion,
    createdAt,
    processedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingRecognition &&
          other.id == this.id &&
          other.imagePath == this.imagePath &&
          other.mealType == this.mealType &&
          other.date == this.date &&
          other.status == this.status &&
          other.retryCount == this.retryCount &&
          other.resultFoodItemId == this.resultFoodItemId &&
          other.errorMessage == this.errorMessage &&
          other.promptVersion == this.promptVersion &&
          other.createdAt == this.createdAt &&
          other.processedAt == this.processedAt);
}

class PendingRecognitionsCompanion extends UpdateCompanion<PendingRecognition> {
  final Value<int> id;
  final Value<String> imagePath;
  final Value<String> mealType;
  final Value<String> date;
  final Value<String> status;
  final Value<int> retryCount;
  final Value<int?> resultFoodItemId;
  final Value<String?> errorMessage;
  final Value<String?> promptVersion;
  final Value<int> createdAt;
  final Value<int?> processedAt;
  const PendingRecognitionsCompanion({
    this.id = const Value.absent(),
    this.imagePath = const Value.absent(),
    this.mealType = const Value.absent(),
    this.date = const Value.absent(),
    this.status = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.resultFoodItemId = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.promptVersion = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.processedAt = const Value.absent(),
  });
  PendingRecognitionsCompanion.insert({
    this.id = const Value.absent(),
    required String imagePath,
    required String mealType,
    required String date,
    required String status,
    this.retryCount = const Value.absent(),
    this.resultFoodItemId = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.promptVersion = const Value.absent(),
    required int createdAt,
    this.processedAt = const Value.absent(),
  }) : imagePath = Value(imagePath),
       mealType = Value(mealType),
       date = Value(date),
       status = Value(status),
       createdAt = Value(createdAt);
  static Insertable<PendingRecognition> custom({
    Expression<int>? id,
    Expression<String>? imagePath,
    Expression<String>? mealType,
    Expression<String>? date,
    Expression<String>? status,
    Expression<int>? retryCount,
    Expression<int>? resultFoodItemId,
    Expression<String>? errorMessage,
    Expression<String>? promptVersion,
    Expression<int>? createdAt,
    Expression<int>? processedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (imagePath != null) 'image_path': imagePath,
      if (mealType != null) 'meal_type': mealType,
      if (date != null) 'date': date,
      if (status != null) 'status': status,
      if (retryCount != null) 'retry_count': retryCount,
      if (resultFoodItemId != null) 'result_food_item_id': resultFoodItemId,
      if (errorMessage != null) 'error_message': errorMessage,
      if (promptVersion != null) 'prompt_version': promptVersion,
      if (createdAt != null) 'created_at': createdAt,
      if (processedAt != null) 'processed_at': processedAt,
    });
  }

  PendingRecognitionsCompanion copyWith({
    Value<int>? id,
    Value<String>? imagePath,
    Value<String>? mealType,
    Value<String>? date,
    Value<String>? status,
    Value<int>? retryCount,
    Value<int?>? resultFoodItemId,
    Value<String?>? errorMessage,
    Value<String?>? promptVersion,
    Value<int>? createdAt,
    Value<int?>? processedAt,
  }) {
    return PendingRecognitionsCompanion(
      id: id ?? this.id,
      imagePath: imagePath ?? this.imagePath,
      mealType: mealType ?? this.mealType,
      date: date ?? this.date,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      resultFoodItemId: resultFoodItemId ?? this.resultFoodItemId,
      errorMessage: errorMessage ?? this.errorMessage,
      promptVersion: promptVersion ?? this.promptVersion,
      createdAt: createdAt ?? this.createdAt,
      processedAt: processedAt ?? this.processedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (imagePath.present) {
      map['image_path'] = Variable<String>(imagePath.value);
    }
    if (mealType.present) {
      map['meal_type'] = Variable<String>(mealType.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (resultFoodItemId.present) {
      map['result_food_item_id'] = Variable<int>(resultFoodItemId.value);
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
    }
    if (promptVersion.present) {
      map['prompt_version'] = Variable<String>(promptVersion.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (processedAt.present) {
      map['processed_at'] = Variable<int>(processedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingRecognitionsCompanion(')
          ..write('id: $id, ')
          ..write('imagePath: $imagePath, ')
          ..write('mealType: $mealType, ')
          ..write('date: $date, ')
          ..write('status: $status, ')
          ..write('retryCount: $retryCount, ')
          ..write('resultFoodItemId: $resultFoodItemId, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('promptVersion: $promptVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('processedAt: $processedAt')
          ..write(')'))
        .toString();
  }
}

class $InsightSummariesTable extends InsightSummaries
    with TableInfo<$InsightSummariesTable, InsightSummary> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InsightSummariesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _periodTypeMeta = const VerificationMeta(
    'periodType',
  );
  @override
  late final GeneratedColumn<String> periodType = GeneratedColumn<String>(
    'period_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _periodStartMeta = const VerificationMeta(
    'periodStart',
  );
  @override
  late final GeneratedColumn<String> periodStart = GeneratedColumn<String>(
    'period_start',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _periodEndMeta = const VerificationMeta(
    'periodEnd',
  );
  @override
  late final GeneratedColumn<String> periodEnd = GeneratedColumn<String>(
    'period_end',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _summaryTextMeta = const VerificationMeta(
    'summaryText',
  );
  @override
  late final GeneratedColumn<String> summaryText = GeneratedColumn<String>(
    'summary_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isEditedMeta = const VerificationMeta(
    'isEdited',
  );
  @override
  late final GeneratedColumn<int> isEdited = GeneratedColumn<int>(
    'is_edited',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _generatedAtMeta = const VerificationMeta(
    'generatedAt',
  );
  @override
  late final GeneratedColumn<int> generatedAt = GeneratedColumn<int>(
    'generated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    periodType,
    periodStart,
    periodEnd,
    summaryText,
    isEdited,
    generatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'insight_summaries';
  @override
  VerificationContext validateIntegrity(
    Insertable<InsightSummary> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('period_type')) {
      context.handle(
        _periodTypeMeta,
        periodType.isAcceptableOrUnknown(data['period_type']!, _periodTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_periodTypeMeta);
    }
    if (data.containsKey('period_start')) {
      context.handle(
        _periodStartMeta,
        periodStart.isAcceptableOrUnknown(
          data['period_start']!,
          _periodStartMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_periodStartMeta);
    }
    if (data.containsKey('period_end')) {
      context.handle(
        _periodEndMeta,
        periodEnd.isAcceptableOrUnknown(data['period_end']!, _periodEndMeta),
      );
    } else if (isInserting) {
      context.missing(_periodEndMeta);
    }
    if (data.containsKey('summary_text')) {
      context.handle(
        _summaryTextMeta,
        summaryText.isAcceptableOrUnknown(
          data['summary_text']!,
          _summaryTextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_summaryTextMeta);
    }
    if (data.containsKey('is_edited')) {
      context.handle(
        _isEditedMeta,
        isEdited.isAcceptableOrUnknown(data['is_edited']!, _isEditedMeta),
      );
    }
    if (data.containsKey('generated_at')) {
      context.handle(
        _generatedAtMeta,
        generatedAt.isAcceptableOrUnknown(
          data['generated_at']!,
          _generatedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_generatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  InsightSummary map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InsightSummary(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      periodType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}period_type'],
      )!,
      periodStart: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}period_start'],
      )!,
      periodEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}period_end'],
      )!,
      summaryText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary_text'],
      )!,
      isEdited: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}is_edited'],
      )!,
      generatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}generated_at'],
      )!,
    );
  }

  @override
  $InsightSummariesTable createAlias(String alias) {
    return $InsightSummariesTable(attachedDatabase, alias);
  }
}

class InsightSummary extends DataClass implements Insertable<InsightSummary> {
  final int id;
  final String periodType;
  final String periodStart;
  final String periodEnd;
  final String summaryText;
  final int isEdited;
  final int generatedAt;
  const InsightSummary({
    required this.id,
    required this.periodType,
    required this.periodStart,
    required this.periodEnd,
    required this.summaryText,
    required this.isEdited,
    required this.generatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['period_type'] = Variable<String>(periodType);
    map['period_start'] = Variable<String>(periodStart);
    map['period_end'] = Variable<String>(periodEnd);
    map['summary_text'] = Variable<String>(summaryText);
    map['is_edited'] = Variable<int>(isEdited);
    map['generated_at'] = Variable<int>(generatedAt);
    return map;
  }

  InsightSummariesCompanion toCompanion(bool nullToAbsent) {
    return InsightSummariesCompanion(
      id: Value(id),
      periodType: Value(periodType),
      periodStart: Value(periodStart),
      periodEnd: Value(periodEnd),
      summaryText: Value(summaryText),
      isEdited: Value(isEdited),
      generatedAt: Value(generatedAt),
    );
  }

  factory InsightSummary.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InsightSummary(
      id: serializer.fromJson<int>(json['id']),
      periodType: serializer.fromJson<String>(json['periodType']),
      periodStart: serializer.fromJson<String>(json['periodStart']),
      periodEnd: serializer.fromJson<String>(json['periodEnd']),
      summaryText: serializer.fromJson<String>(json['summaryText']),
      isEdited: serializer.fromJson<int>(json['isEdited']),
      generatedAt: serializer.fromJson<int>(json['generatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'periodType': serializer.toJson<String>(periodType),
      'periodStart': serializer.toJson<String>(periodStart),
      'periodEnd': serializer.toJson<String>(periodEnd),
      'summaryText': serializer.toJson<String>(summaryText),
      'isEdited': serializer.toJson<int>(isEdited),
      'generatedAt': serializer.toJson<int>(generatedAt),
    };
  }

  InsightSummary copyWith({
    int? id,
    String? periodType,
    String? periodStart,
    String? periodEnd,
    String? summaryText,
    int? isEdited,
    int? generatedAt,
  }) => InsightSummary(
    id: id ?? this.id,
    periodType: periodType ?? this.periodType,
    periodStart: periodStart ?? this.periodStart,
    periodEnd: periodEnd ?? this.periodEnd,
    summaryText: summaryText ?? this.summaryText,
    isEdited: isEdited ?? this.isEdited,
    generatedAt: generatedAt ?? this.generatedAt,
  );
  InsightSummary copyWithCompanion(InsightSummariesCompanion data) {
    return InsightSummary(
      id: data.id.present ? data.id.value : this.id,
      periodType: data.periodType.present
          ? data.periodType.value
          : this.periodType,
      periodStart: data.periodStart.present
          ? data.periodStart.value
          : this.periodStart,
      periodEnd: data.periodEnd.present ? data.periodEnd.value : this.periodEnd,
      summaryText: data.summaryText.present
          ? data.summaryText.value
          : this.summaryText,
      isEdited: data.isEdited.present ? data.isEdited.value : this.isEdited,
      generatedAt: data.generatedAt.present
          ? data.generatedAt.value
          : this.generatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InsightSummary(')
          ..write('id: $id, ')
          ..write('periodType: $periodType, ')
          ..write('periodStart: $periodStart, ')
          ..write('periodEnd: $periodEnd, ')
          ..write('summaryText: $summaryText, ')
          ..write('isEdited: $isEdited, ')
          ..write('generatedAt: $generatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    periodType,
    periodStart,
    periodEnd,
    summaryText,
    isEdited,
    generatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InsightSummary &&
          other.id == this.id &&
          other.periodType == this.periodType &&
          other.periodStart == this.periodStart &&
          other.periodEnd == this.periodEnd &&
          other.summaryText == this.summaryText &&
          other.isEdited == this.isEdited &&
          other.generatedAt == this.generatedAt);
}

class InsightSummariesCompanion extends UpdateCompanion<InsightSummary> {
  final Value<int> id;
  final Value<String> periodType;
  final Value<String> periodStart;
  final Value<String> periodEnd;
  final Value<String> summaryText;
  final Value<int> isEdited;
  final Value<int> generatedAt;
  const InsightSummariesCompanion({
    this.id = const Value.absent(),
    this.periodType = const Value.absent(),
    this.periodStart = const Value.absent(),
    this.periodEnd = const Value.absent(),
    this.summaryText = const Value.absent(),
    this.isEdited = const Value.absent(),
    this.generatedAt = const Value.absent(),
  });
  InsightSummariesCompanion.insert({
    this.id = const Value.absent(),
    required String periodType,
    required String periodStart,
    required String periodEnd,
    required String summaryText,
    this.isEdited = const Value.absent(),
    required int generatedAt,
  }) : periodType = Value(periodType),
       periodStart = Value(periodStart),
       periodEnd = Value(periodEnd),
       summaryText = Value(summaryText),
       generatedAt = Value(generatedAt);
  static Insertable<InsightSummary> custom({
    Expression<int>? id,
    Expression<String>? periodType,
    Expression<String>? periodStart,
    Expression<String>? periodEnd,
    Expression<String>? summaryText,
    Expression<int>? isEdited,
    Expression<int>? generatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (periodType != null) 'period_type': periodType,
      if (periodStart != null) 'period_start': periodStart,
      if (periodEnd != null) 'period_end': periodEnd,
      if (summaryText != null) 'summary_text': summaryText,
      if (isEdited != null) 'is_edited': isEdited,
      if (generatedAt != null) 'generated_at': generatedAt,
    });
  }

  InsightSummariesCompanion copyWith({
    Value<int>? id,
    Value<String>? periodType,
    Value<String>? periodStart,
    Value<String>? periodEnd,
    Value<String>? summaryText,
    Value<int>? isEdited,
    Value<int>? generatedAt,
  }) {
    return InsightSummariesCompanion(
      id: id ?? this.id,
      periodType: periodType ?? this.periodType,
      periodStart: periodStart ?? this.periodStart,
      periodEnd: periodEnd ?? this.periodEnd,
      summaryText: summaryText ?? this.summaryText,
      isEdited: isEdited ?? this.isEdited,
      generatedAt: generatedAt ?? this.generatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (periodType.present) {
      map['period_type'] = Variable<String>(periodType.value);
    }
    if (periodStart.present) {
      map['period_start'] = Variable<String>(periodStart.value);
    }
    if (periodEnd.present) {
      map['period_end'] = Variable<String>(periodEnd.value);
    }
    if (summaryText.present) {
      map['summary_text'] = Variable<String>(summaryText.value);
    }
    if (isEdited.present) {
      map['is_edited'] = Variable<int>(isEdited.value);
    }
    if (generatedAt.present) {
      map['generated_at'] = Variable<int>(generatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InsightSummariesCompanion(')
          ..write('id: $id, ')
          ..write('periodType: $periodType, ')
          ..write('periodStart: $periodStart, ')
          ..write('periodEnd: $periodEnd, ')
          ..write('summaryText: $summaryText, ')
          ..write('isEdited: $isEdited, ')
          ..write('generatedAt: $generatedAt')
          ..write(')'))
        .toString();
  }
}

class $RecognitionFeedbacksTable extends RecognitionFeedbacks
    with TableInfo<$RecognitionFeedbacksTable, RecognitionFeedback> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecognitionFeedbacksTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _mealLogIdMeta = const VerificationMeta(
    'mealLogId',
  );
  @override
  late final GeneratedColumn<int> mealLogId = GeneratedColumn<int>(
    'meal_log_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES meal_logs (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _isCorrectMeta = const VerificationMeta(
    'isCorrect',
  );
  @override
  late final GeneratedColumn<int> isCorrect = GeneratedColumn<int>(
    'is_correct',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _correctedDishNameMeta = const VerificationMeta(
    'correctedDishName',
  );
  @override
  late final GeneratedColumn<String> correctedDishName =
      GeneratedColumn<String>(
        'corrected_dish_name',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _correctedServingGMeta = const VerificationMeta(
    'correctedServingG',
  );
  @override
  late final GeneratedColumn<double> correctedServingG =
      GeneratedColumn<double>(
        'corrected_serving_g',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _promptVersionMeta = const VerificationMeta(
    'promptVersion',
  );
  @override
  late final GeneratedColumn<String> promptVersion = GeneratedColumn<String>(
    'prompt_version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    mealLogId,
    isCorrect,
    correctedDishName,
    correctedServingG,
    promptVersion,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recognition_feedbacks';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecognitionFeedback> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('meal_log_id')) {
      context.handle(
        _mealLogIdMeta,
        mealLogId.isAcceptableOrUnknown(data['meal_log_id']!, _mealLogIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mealLogIdMeta);
    }
    if (data.containsKey('is_correct')) {
      context.handle(
        _isCorrectMeta,
        isCorrect.isAcceptableOrUnknown(data['is_correct']!, _isCorrectMeta),
      );
    } else if (isInserting) {
      context.missing(_isCorrectMeta);
    }
    if (data.containsKey('corrected_dish_name')) {
      context.handle(
        _correctedDishNameMeta,
        correctedDishName.isAcceptableOrUnknown(
          data['corrected_dish_name']!,
          _correctedDishNameMeta,
        ),
      );
    }
    if (data.containsKey('corrected_serving_g')) {
      context.handle(
        _correctedServingGMeta,
        correctedServingG.isAcceptableOrUnknown(
          data['corrected_serving_g']!,
          _correctedServingGMeta,
        ),
      );
    }
    if (data.containsKey('prompt_version')) {
      context.handle(
        _promptVersionMeta,
        promptVersion.isAcceptableOrUnknown(
          data['prompt_version']!,
          _promptVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_promptVersionMeta);
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RecognitionFeedback map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecognitionFeedback(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      mealLogId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}meal_log_id'],
      )!,
      isCorrect: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}is_correct'],
      )!,
      correctedDishName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}corrected_dish_name'],
      ),
      correctedServingG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}corrected_serving_g'],
      ),
      promptVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}prompt_version'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $RecognitionFeedbacksTable createAlias(String alias) {
    return $RecognitionFeedbacksTable(attachedDatabase, alias);
  }
}

class RecognitionFeedback extends DataClass
    implements Insertable<RecognitionFeedback> {
  final int id;
  final int mealLogId;
  final int isCorrect;
  final String? correctedDishName;
  final double? correctedServingG;
  final String promptVersion;
  final int createdAt;
  const RecognitionFeedback({
    required this.id,
    required this.mealLogId,
    required this.isCorrect,
    this.correctedDishName,
    this.correctedServingG,
    required this.promptVersion,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['meal_log_id'] = Variable<int>(mealLogId);
    map['is_correct'] = Variable<int>(isCorrect);
    if (!nullToAbsent || correctedDishName != null) {
      map['corrected_dish_name'] = Variable<String>(correctedDishName);
    }
    if (!nullToAbsent || correctedServingG != null) {
      map['corrected_serving_g'] = Variable<double>(correctedServingG);
    }
    map['prompt_version'] = Variable<String>(promptVersion);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  RecognitionFeedbacksCompanion toCompanion(bool nullToAbsent) {
    return RecognitionFeedbacksCompanion(
      id: Value(id),
      mealLogId: Value(mealLogId),
      isCorrect: Value(isCorrect),
      correctedDishName: correctedDishName == null && nullToAbsent
          ? const Value.absent()
          : Value(correctedDishName),
      correctedServingG: correctedServingG == null && nullToAbsent
          ? const Value.absent()
          : Value(correctedServingG),
      promptVersion: Value(promptVersion),
      createdAt: Value(createdAt),
    );
  }

  factory RecognitionFeedback.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecognitionFeedback(
      id: serializer.fromJson<int>(json['id']),
      mealLogId: serializer.fromJson<int>(json['mealLogId']),
      isCorrect: serializer.fromJson<int>(json['isCorrect']),
      correctedDishName: serializer.fromJson<String?>(
        json['correctedDishName'],
      ),
      correctedServingG: serializer.fromJson<double?>(
        json['correctedServingG'],
      ),
      promptVersion: serializer.fromJson<String>(json['promptVersion']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'mealLogId': serializer.toJson<int>(mealLogId),
      'isCorrect': serializer.toJson<int>(isCorrect),
      'correctedDishName': serializer.toJson<String?>(correctedDishName),
      'correctedServingG': serializer.toJson<double?>(correctedServingG),
      'promptVersion': serializer.toJson<String>(promptVersion),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  RecognitionFeedback copyWith({
    int? id,
    int? mealLogId,
    int? isCorrect,
    Value<String?> correctedDishName = const Value.absent(),
    Value<double?> correctedServingG = const Value.absent(),
    String? promptVersion,
    int? createdAt,
  }) => RecognitionFeedback(
    id: id ?? this.id,
    mealLogId: mealLogId ?? this.mealLogId,
    isCorrect: isCorrect ?? this.isCorrect,
    correctedDishName: correctedDishName.present
        ? correctedDishName.value
        : this.correctedDishName,
    correctedServingG: correctedServingG.present
        ? correctedServingG.value
        : this.correctedServingG,
    promptVersion: promptVersion ?? this.promptVersion,
    createdAt: createdAt ?? this.createdAt,
  );
  RecognitionFeedback copyWithCompanion(RecognitionFeedbacksCompanion data) {
    return RecognitionFeedback(
      id: data.id.present ? data.id.value : this.id,
      mealLogId: data.mealLogId.present ? data.mealLogId.value : this.mealLogId,
      isCorrect: data.isCorrect.present ? data.isCorrect.value : this.isCorrect,
      correctedDishName: data.correctedDishName.present
          ? data.correctedDishName.value
          : this.correctedDishName,
      correctedServingG: data.correctedServingG.present
          ? data.correctedServingG.value
          : this.correctedServingG,
      promptVersion: data.promptVersion.present
          ? data.promptVersion.value
          : this.promptVersion,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecognitionFeedback(')
          ..write('id: $id, ')
          ..write('mealLogId: $mealLogId, ')
          ..write('isCorrect: $isCorrect, ')
          ..write('correctedDishName: $correctedDishName, ')
          ..write('correctedServingG: $correctedServingG, ')
          ..write('promptVersion: $promptVersion, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    mealLogId,
    isCorrect,
    correctedDishName,
    correctedServingG,
    promptVersion,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecognitionFeedback &&
          other.id == this.id &&
          other.mealLogId == this.mealLogId &&
          other.isCorrect == this.isCorrect &&
          other.correctedDishName == this.correctedDishName &&
          other.correctedServingG == this.correctedServingG &&
          other.promptVersion == this.promptVersion &&
          other.createdAt == this.createdAt);
}

class RecognitionFeedbacksCompanion
    extends UpdateCompanion<RecognitionFeedback> {
  final Value<int> id;
  final Value<int> mealLogId;
  final Value<int> isCorrect;
  final Value<String?> correctedDishName;
  final Value<double?> correctedServingG;
  final Value<String> promptVersion;
  final Value<int> createdAt;
  const RecognitionFeedbacksCompanion({
    this.id = const Value.absent(),
    this.mealLogId = const Value.absent(),
    this.isCorrect = const Value.absent(),
    this.correctedDishName = const Value.absent(),
    this.correctedServingG = const Value.absent(),
    this.promptVersion = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  RecognitionFeedbacksCompanion.insert({
    this.id = const Value.absent(),
    required int mealLogId,
    required int isCorrect,
    this.correctedDishName = const Value.absent(),
    this.correctedServingG = const Value.absent(),
    required String promptVersion,
    required int createdAt,
  }) : mealLogId = Value(mealLogId),
       isCorrect = Value(isCorrect),
       promptVersion = Value(promptVersion),
       createdAt = Value(createdAt);
  static Insertable<RecognitionFeedback> custom({
    Expression<int>? id,
    Expression<int>? mealLogId,
    Expression<int>? isCorrect,
    Expression<String>? correctedDishName,
    Expression<double>? correctedServingG,
    Expression<String>? promptVersion,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (mealLogId != null) 'meal_log_id': mealLogId,
      if (isCorrect != null) 'is_correct': isCorrect,
      if (correctedDishName != null) 'corrected_dish_name': correctedDishName,
      if (correctedServingG != null) 'corrected_serving_g': correctedServingG,
      if (promptVersion != null) 'prompt_version': promptVersion,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  RecognitionFeedbacksCompanion copyWith({
    Value<int>? id,
    Value<int>? mealLogId,
    Value<int>? isCorrect,
    Value<String?>? correctedDishName,
    Value<double?>? correctedServingG,
    Value<String>? promptVersion,
    Value<int>? createdAt,
  }) {
    return RecognitionFeedbacksCompanion(
      id: id ?? this.id,
      mealLogId: mealLogId ?? this.mealLogId,
      isCorrect: isCorrect ?? this.isCorrect,
      correctedDishName: correctedDishName ?? this.correctedDishName,
      correctedServingG: correctedServingG ?? this.correctedServingG,
      promptVersion: promptVersion ?? this.promptVersion,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (mealLogId.present) {
      map['meal_log_id'] = Variable<int>(mealLogId.value);
    }
    if (isCorrect.present) {
      map['is_correct'] = Variable<int>(isCorrect.value);
    }
    if (correctedDishName.present) {
      map['corrected_dish_name'] = Variable<String>(correctedDishName.value);
    }
    if (correctedServingG.present) {
      map['corrected_serving_g'] = Variable<double>(correctedServingG.value);
    }
    if (promptVersion.present) {
      map['prompt_version'] = Variable<String>(promptVersion.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecognitionFeedbacksCompanion(')
          ..write('id: $id, ')
          ..write('mealLogId: $mealLogId, ')
          ..write('isCorrect: $isCorrect, ')
          ..write('correctedDishName: $correctedDishName, ')
          ..write('correctedServingG: $correctedServingG, ')
          ..write('promptVersion: $promptVersion, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $RecommendationFeedbacksTable extends RecommendationFeedbacks
    with TableInfo<$RecommendationFeedbacksTable, RecommendationFeedback> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecommendationFeedbacksTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _foodNameMeta = const VerificationMeta(
    'foodName',
  );
  @override
  late final GeneratedColumn<String> foodName = GeneratedColumn<String>(
    'food_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  @override
  late final GeneratedColumn<int> rating = GeneratedColumn<int>(
    'rating',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mealTypeMeta = const VerificationMeta(
    'mealType',
  );
  @override
  late final GeneratedColumn<String> mealType = GeneratedColumn<String>(
    'meal_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _recommendDateMeta = const VerificationMeta(
    'recommendDate',
  );
  @override
  late final GeneratedColumn<String> recommendDate = GeneratedColumn<String>(
    'recommend_date',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    foodName,
    rating,
    mealType,
    recommendDate,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recommendation_feedbacks';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecommendationFeedback> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('food_name')) {
      context.handle(
        _foodNameMeta,
        foodName.isAcceptableOrUnknown(data['food_name']!, _foodNameMeta),
      );
    } else if (isInserting) {
      context.missing(_foodNameMeta);
    }
    if (data.containsKey('rating')) {
      context.handle(
        _ratingMeta,
        rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta),
      );
    } else if (isInserting) {
      context.missing(_ratingMeta);
    }
    if (data.containsKey('meal_type')) {
      context.handle(
        _mealTypeMeta,
        mealType.isAcceptableOrUnknown(data['meal_type']!, _mealTypeMeta),
      );
    }
    if (data.containsKey('recommend_date')) {
      context.handle(
        _recommendDateMeta,
        recommendDate.isAcceptableOrUnknown(
          data['recommend_date']!,
          _recommendDateMeta,
        ),
      );
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RecommendationFeedback map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecommendationFeedback(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      foodName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}food_name'],
      )!,
      rating: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rating'],
      )!,
      mealType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}meal_type'],
      ),
      recommendDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recommend_date'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $RecommendationFeedbacksTable createAlias(String alias) {
    return $RecommendationFeedbacksTable(attachedDatabase, alias);
  }
}

class RecommendationFeedback extends DataClass
    implements Insertable<RecommendationFeedback> {
  final int id;
  final String foodName;

  /// 1=不喜欢 / 2=一般 / 3=喜欢
  final int rating;

  /// 当时推荐的餐次 breakfast/lunch/dinner/snack，便于时段感知学习
  final String? mealType;

  /// 当时推荐的日期 YYYY-MM-DD，便于按时间窗口过滤
  final String? recommendDate;
  final int createdAt;
  const RecommendationFeedback({
    required this.id,
    required this.foodName,
    required this.rating,
    this.mealType,
    this.recommendDate,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['food_name'] = Variable<String>(foodName);
    map['rating'] = Variable<int>(rating);
    if (!nullToAbsent || mealType != null) {
      map['meal_type'] = Variable<String>(mealType);
    }
    if (!nullToAbsent || recommendDate != null) {
      map['recommend_date'] = Variable<String>(recommendDate);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  RecommendationFeedbacksCompanion toCompanion(bool nullToAbsent) {
    return RecommendationFeedbacksCompanion(
      id: Value(id),
      foodName: Value(foodName),
      rating: Value(rating),
      mealType: mealType == null && nullToAbsent
          ? const Value.absent()
          : Value(mealType),
      recommendDate: recommendDate == null && nullToAbsent
          ? const Value.absent()
          : Value(recommendDate),
      createdAt: Value(createdAt),
    );
  }

  factory RecommendationFeedback.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecommendationFeedback(
      id: serializer.fromJson<int>(json['id']),
      foodName: serializer.fromJson<String>(json['foodName']),
      rating: serializer.fromJson<int>(json['rating']),
      mealType: serializer.fromJson<String?>(json['mealType']),
      recommendDate: serializer.fromJson<String?>(json['recommendDate']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'foodName': serializer.toJson<String>(foodName),
      'rating': serializer.toJson<int>(rating),
      'mealType': serializer.toJson<String?>(mealType),
      'recommendDate': serializer.toJson<String?>(recommendDate),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  RecommendationFeedback copyWith({
    int? id,
    String? foodName,
    int? rating,
    Value<String?> mealType = const Value.absent(),
    Value<String?> recommendDate = const Value.absent(),
    int? createdAt,
  }) => RecommendationFeedback(
    id: id ?? this.id,
    foodName: foodName ?? this.foodName,
    rating: rating ?? this.rating,
    mealType: mealType.present ? mealType.value : this.mealType,
    recommendDate: recommendDate.present
        ? recommendDate.value
        : this.recommendDate,
    createdAt: createdAt ?? this.createdAt,
  );
  RecommendationFeedback copyWithCompanion(
    RecommendationFeedbacksCompanion data,
  ) {
    return RecommendationFeedback(
      id: data.id.present ? data.id.value : this.id,
      foodName: data.foodName.present ? data.foodName.value : this.foodName,
      rating: data.rating.present ? data.rating.value : this.rating,
      mealType: data.mealType.present ? data.mealType.value : this.mealType,
      recommendDate: data.recommendDate.present
          ? data.recommendDate.value
          : this.recommendDate,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecommendationFeedback(')
          ..write('id: $id, ')
          ..write('foodName: $foodName, ')
          ..write('rating: $rating, ')
          ..write('mealType: $mealType, ')
          ..write('recommendDate: $recommendDate, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, foodName, rating, mealType, recommendDate, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecommendationFeedback &&
          other.id == this.id &&
          other.foodName == this.foodName &&
          other.rating == this.rating &&
          other.mealType == this.mealType &&
          other.recommendDate == this.recommendDate &&
          other.createdAt == this.createdAt);
}

class RecommendationFeedbacksCompanion
    extends UpdateCompanion<RecommendationFeedback> {
  final Value<int> id;
  final Value<String> foodName;
  final Value<int> rating;
  final Value<String?> mealType;
  final Value<String?> recommendDate;
  final Value<int> createdAt;
  const RecommendationFeedbacksCompanion({
    this.id = const Value.absent(),
    this.foodName = const Value.absent(),
    this.rating = const Value.absent(),
    this.mealType = const Value.absent(),
    this.recommendDate = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  RecommendationFeedbacksCompanion.insert({
    this.id = const Value.absent(),
    required String foodName,
    required int rating,
    this.mealType = const Value.absent(),
    this.recommendDate = const Value.absent(),
    required int createdAt,
  }) : foodName = Value(foodName),
       rating = Value(rating),
       createdAt = Value(createdAt);
  static Insertable<RecommendationFeedback> custom({
    Expression<int>? id,
    Expression<String>? foodName,
    Expression<int>? rating,
    Expression<String>? mealType,
    Expression<String>? recommendDate,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (foodName != null) 'food_name': foodName,
      if (rating != null) 'rating': rating,
      if (mealType != null) 'meal_type': mealType,
      if (recommendDate != null) 'recommend_date': recommendDate,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  RecommendationFeedbacksCompanion copyWith({
    Value<int>? id,
    Value<String>? foodName,
    Value<int>? rating,
    Value<String?>? mealType,
    Value<String?>? recommendDate,
    Value<int>? createdAt,
  }) {
    return RecommendationFeedbacksCompanion(
      id: id ?? this.id,
      foodName: foodName ?? this.foodName,
      rating: rating ?? this.rating,
      mealType: mealType ?? this.mealType,
      recommendDate: recommendDate ?? this.recommendDate,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (foodName.present) {
      map['food_name'] = Variable<String>(foodName.value);
    }
    if (rating.present) {
      map['rating'] = Variable<int>(rating.value);
    }
    if (mealType.present) {
      map['meal_type'] = Variable<String>(mealType.value);
    }
    if (recommendDate.present) {
      map['recommend_date'] = Variable<String>(recommendDate.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecommendationFeedbacksCompanion(')
          ..write('id: $id, ')
          ..write('foodName: $foodName, ')
          ..write('rating: $rating, ')
          ..write('mealType: $mealType, ')
          ..write('recommendDate: $recommendDate, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$EatWiseDatabase extends GeneratedDatabase {
  _$EatWiseDatabase(QueryExecutor e) : super(e);
  $EatWiseDatabaseManager get managers => $EatWiseDatabaseManager(this);
  late final $ProfilesTable profiles = $ProfilesTable(this);
  late final $FoodItemsTable foodItems = $FoodItemsTable(this);
  late final $MealLogsTable mealLogs = $MealLogsTable(this);
  late final $WeightLogsTable weightLogs = $WeightLogsTable(this);
  late final $PendingRecognitionsTable pendingRecognitions =
      $PendingRecognitionsTable(this);
  late final $InsightSummariesTable insightSummaries = $InsightSummariesTable(
    this,
  );
  late final $RecognitionFeedbacksTable recognitionFeedbacks =
      $RecognitionFeedbacksTable(this);
  late final $RecommendationFeedbacksTable recommendationFeedbacks =
      $RecommendationFeedbacksTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    profiles,
    foodItems,
    mealLogs,
    weightLogs,
    pendingRecognitions,
    insightSummaries,
    recognitionFeedbacks,
    recommendationFeedbacks,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'meal_logs',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('recognition_feedbacks', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$ProfilesTableCreateCompanionBuilder =
    ProfilesCompanion Function({
      Value<int> id,
      required double heightCm,
      required double weightKg,
      Value<double?> bodyFatPct,
      required int age,
      required String gender,
      required double activityLevel,
      required String goal,
      required double goalRateKgPerWeek,
      required String formula,
      required int dailyCalorieTarget,
      required double proteinGPerKg,
      required double fatGPerKg,
      Value<double?> carbGPerKg,
      Value<int> tdeeAdjustmentKcal,
      required int updatedAt,
      Value<String?> specialCondition,
      Value<String?> dietPreference,
      Value<String?> healthCondition,
    });
typedef $$ProfilesTableUpdateCompanionBuilder =
    ProfilesCompanion Function({
      Value<int> id,
      Value<double> heightCm,
      Value<double> weightKg,
      Value<double?> bodyFatPct,
      Value<int> age,
      Value<String> gender,
      Value<double> activityLevel,
      Value<String> goal,
      Value<double> goalRateKgPerWeek,
      Value<String> formula,
      Value<int> dailyCalorieTarget,
      Value<double> proteinGPerKg,
      Value<double> fatGPerKg,
      Value<double?> carbGPerKg,
      Value<int> tdeeAdjustmentKcal,
      Value<int> updatedAt,
      Value<String?> specialCondition,
      Value<String?> dietPreference,
      Value<String?> healthCondition,
    });

class $$ProfilesTableFilterComposer
    extends Composer<_$EatWiseDatabase, $ProfilesTable> {
  $$ProfilesTableFilterComposer({
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

  ColumnFilters<double> get heightCm => $composableBuilder(
    column: $table.heightCm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get weightKg => $composableBuilder(
    column: $table.weightKg,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bodyFatPct => $composableBuilder(
    column: $table.bodyFatPct,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get age => $composableBuilder(
    column: $table.age,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gender => $composableBuilder(
    column: $table.gender,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get activityLevel => $composableBuilder(
    column: $table.activityLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get goal => $composableBuilder(
    column: $table.goal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get goalRateKgPerWeek => $composableBuilder(
    column: $table.goalRateKgPerWeek,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get formula => $composableBuilder(
    column: $table.formula,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dailyCalorieTarget => $composableBuilder(
    column: $table.dailyCalorieTarget,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get proteinGPerKg => $composableBuilder(
    column: $table.proteinGPerKg,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get fatGPerKg => $composableBuilder(
    column: $table.fatGPerKg,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get carbGPerKg => $composableBuilder(
    column: $table.carbGPerKg,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tdeeAdjustmentKcal => $composableBuilder(
    column: $table.tdeeAdjustmentKcal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get specialCondition => $composableBuilder(
    column: $table.specialCondition,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dietPreference => $composableBuilder(
    column: $table.dietPreference,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get healthCondition => $composableBuilder(
    column: $table.healthCondition,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProfilesTableOrderingComposer
    extends Composer<_$EatWiseDatabase, $ProfilesTable> {
  $$ProfilesTableOrderingComposer({
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

  ColumnOrderings<double> get heightCm => $composableBuilder(
    column: $table.heightCm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get weightKg => $composableBuilder(
    column: $table.weightKg,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bodyFatPct => $composableBuilder(
    column: $table.bodyFatPct,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get age => $composableBuilder(
    column: $table.age,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gender => $composableBuilder(
    column: $table.gender,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get activityLevel => $composableBuilder(
    column: $table.activityLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get goal => $composableBuilder(
    column: $table.goal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get goalRateKgPerWeek => $composableBuilder(
    column: $table.goalRateKgPerWeek,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get formula => $composableBuilder(
    column: $table.formula,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dailyCalorieTarget => $composableBuilder(
    column: $table.dailyCalorieTarget,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get proteinGPerKg => $composableBuilder(
    column: $table.proteinGPerKg,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get fatGPerKg => $composableBuilder(
    column: $table.fatGPerKg,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get carbGPerKg => $composableBuilder(
    column: $table.carbGPerKg,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tdeeAdjustmentKcal => $composableBuilder(
    column: $table.tdeeAdjustmentKcal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get specialCondition => $composableBuilder(
    column: $table.specialCondition,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dietPreference => $composableBuilder(
    column: $table.dietPreference,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get healthCondition => $composableBuilder(
    column: $table.healthCondition,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProfilesTableAnnotationComposer
    extends Composer<_$EatWiseDatabase, $ProfilesTable> {
  $$ProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get heightCm =>
      $composableBuilder(column: $table.heightCm, builder: (column) => column);

  GeneratedColumn<double> get weightKg =>
      $composableBuilder(column: $table.weightKg, builder: (column) => column);

  GeneratedColumn<double> get bodyFatPct => $composableBuilder(
    column: $table.bodyFatPct,
    builder: (column) => column,
  );

  GeneratedColumn<int> get age =>
      $composableBuilder(column: $table.age, builder: (column) => column);

  GeneratedColumn<String> get gender =>
      $composableBuilder(column: $table.gender, builder: (column) => column);

  GeneratedColumn<double> get activityLevel => $composableBuilder(
    column: $table.activityLevel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get goal =>
      $composableBuilder(column: $table.goal, builder: (column) => column);

  GeneratedColumn<double> get goalRateKgPerWeek => $composableBuilder(
    column: $table.goalRateKgPerWeek,
    builder: (column) => column,
  );

  GeneratedColumn<String> get formula =>
      $composableBuilder(column: $table.formula, builder: (column) => column);

  GeneratedColumn<int> get dailyCalorieTarget => $composableBuilder(
    column: $table.dailyCalorieTarget,
    builder: (column) => column,
  );

  GeneratedColumn<double> get proteinGPerKg => $composableBuilder(
    column: $table.proteinGPerKg,
    builder: (column) => column,
  );

  GeneratedColumn<double> get fatGPerKg =>
      $composableBuilder(column: $table.fatGPerKg, builder: (column) => column);

  GeneratedColumn<double> get carbGPerKg => $composableBuilder(
    column: $table.carbGPerKg,
    builder: (column) => column,
  );

  GeneratedColumn<int> get tdeeAdjustmentKcal => $composableBuilder(
    column: $table.tdeeAdjustmentKcal,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get specialCondition => $composableBuilder(
    column: $table.specialCondition,
    builder: (column) => column,
  );

  GeneratedColumn<String> get dietPreference => $composableBuilder(
    column: $table.dietPreference,
    builder: (column) => column,
  );

  GeneratedColumn<String> get healthCondition => $composableBuilder(
    column: $table.healthCondition,
    builder: (column) => column,
  );
}

class $$ProfilesTableTableManager
    extends
        RootTableManager<
          _$EatWiseDatabase,
          $ProfilesTable,
          Profile,
          $$ProfilesTableFilterComposer,
          $$ProfilesTableOrderingComposer,
          $$ProfilesTableAnnotationComposer,
          $$ProfilesTableCreateCompanionBuilder,
          $$ProfilesTableUpdateCompanionBuilder,
          (Profile, BaseReferences<_$EatWiseDatabase, $ProfilesTable, Profile>),
          Profile,
          PrefetchHooks Function()
        > {
  $$ProfilesTableTableManager(_$EatWiseDatabase db, $ProfilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<double> heightCm = const Value.absent(),
                Value<double> weightKg = const Value.absent(),
                Value<double?> bodyFatPct = const Value.absent(),
                Value<int> age = const Value.absent(),
                Value<String> gender = const Value.absent(),
                Value<double> activityLevel = const Value.absent(),
                Value<String> goal = const Value.absent(),
                Value<double> goalRateKgPerWeek = const Value.absent(),
                Value<String> formula = const Value.absent(),
                Value<int> dailyCalorieTarget = const Value.absent(),
                Value<double> proteinGPerKg = const Value.absent(),
                Value<double> fatGPerKg = const Value.absent(),
                Value<double?> carbGPerKg = const Value.absent(),
                Value<int> tdeeAdjustmentKcal = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String?> specialCondition = const Value.absent(),
                Value<String?> dietPreference = const Value.absent(),
                Value<String?> healthCondition = const Value.absent(),
              }) => ProfilesCompanion(
                id: id,
                heightCm: heightCm,
                weightKg: weightKg,
                bodyFatPct: bodyFatPct,
                age: age,
                gender: gender,
                activityLevel: activityLevel,
                goal: goal,
                goalRateKgPerWeek: goalRateKgPerWeek,
                formula: formula,
                dailyCalorieTarget: dailyCalorieTarget,
                proteinGPerKg: proteinGPerKg,
                fatGPerKg: fatGPerKg,
                carbGPerKg: carbGPerKg,
                tdeeAdjustmentKcal: tdeeAdjustmentKcal,
                updatedAt: updatedAt,
                specialCondition: specialCondition,
                dietPreference: dietPreference,
                healthCondition: healthCondition,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required double heightCm,
                required double weightKg,
                Value<double?> bodyFatPct = const Value.absent(),
                required int age,
                required String gender,
                required double activityLevel,
                required String goal,
                required double goalRateKgPerWeek,
                required String formula,
                required int dailyCalorieTarget,
                required double proteinGPerKg,
                required double fatGPerKg,
                Value<double?> carbGPerKg = const Value.absent(),
                Value<int> tdeeAdjustmentKcal = const Value.absent(),
                required int updatedAt,
                Value<String?> specialCondition = const Value.absent(),
                Value<String?> dietPreference = const Value.absent(),
                Value<String?> healthCondition = const Value.absent(),
              }) => ProfilesCompanion.insert(
                id: id,
                heightCm: heightCm,
                weightKg: weightKg,
                bodyFatPct: bodyFatPct,
                age: age,
                gender: gender,
                activityLevel: activityLevel,
                goal: goal,
                goalRateKgPerWeek: goalRateKgPerWeek,
                formula: formula,
                dailyCalorieTarget: dailyCalorieTarget,
                proteinGPerKg: proteinGPerKg,
                fatGPerKg: fatGPerKg,
                carbGPerKg: carbGPerKg,
                tdeeAdjustmentKcal: tdeeAdjustmentKcal,
                updatedAt: updatedAt,
                specialCondition: specialCondition,
                dietPreference: dietPreference,
                healthCondition: healthCondition,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$EatWiseDatabase,
      $ProfilesTable,
      Profile,
      $$ProfilesTableFilterComposer,
      $$ProfilesTableOrderingComposer,
      $$ProfilesTableAnnotationComposer,
      $$ProfilesTableCreateCompanionBuilder,
      $$ProfilesTableUpdateCompanionBuilder,
      (Profile, BaseReferences<_$EatWiseDatabase, $ProfilesTable, Profile>),
      Profile,
      PrefetchHooks Function()
    >;
typedef $$FoodItemsTableCreateCompanionBuilder =
    FoodItemsCompanion Function({
      Value<int> id,
      required String name,
      required double defaultServingG,
      required double caloriesPer100g,
      required double proteinPer100g,
      required double fatPer100g,
      required double carbsPer100g,
      Value<String?> aliasesJson,
      Value<double?> ediblePercent,
      required String source,
      required String sourceVersion,
      Value<double?> confidence,
      Value<String?> componentsJson,
      Value<String?> thumbnailPath,
      required int createdAt,
    });
typedef $$FoodItemsTableUpdateCompanionBuilder =
    FoodItemsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<double> defaultServingG,
      Value<double> caloriesPer100g,
      Value<double> proteinPer100g,
      Value<double> fatPer100g,
      Value<double> carbsPer100g,
      Value<String?> aliasesJson,
      Value<double?> ediblePercent,
      Value<String> source,
      Value<String> sourceVersion,
      Value<double?> confidence,
      Value<String?> componentsJson,
      Value<String?> thumbnailPath,
      Value<int> createdAt,
    });

final class $$FoodItemsTableReferences
    extends BaseReferences<_$EatWiseDatabase, $FoodItemsTable, FoodItem> {
  $$FoodItemsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$MealLogsTable, List<MealLog>> _mealLogsRefsTable(
    _$EatWiseDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.mealLogs,
    aliasName: 'food_items__id__meal_logs__food_item_id',
  );

  $$MealLogsTableProcessedTableManager get mealLogsRefs {
    final manager = $$MealLogsTableTableManager(
      $_db,
      $_db.mealLogs,
    ).filter((f) => f.foodItemId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_mealLogsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $PendingRecognitionsTable,
    List<PendingRecognition>
  >
  _pendingRecognitionsRefsTable(_$EatWiseDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.pendingRecognitions,
        aliasName: 'food_items__id__pending_recognitions__result_food_item_id',
      );

  $$PendingRecognitionsTableProcessedTableManager get pendingRecognitionsRefs {
    final manager = $$PendingRecognitionsTableTableManager(
      $_db,
      $_db.pendingRecognitions,
    ).filter((f) => f.resultFoodItemId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _pendingRecognitionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$FoodItemsTableFilterComposer
    extends Composer<_$EatWiseDatabase, $FoodItemsTable> {
  $$FoodItemsTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get defaultServingG => $composableBuilder(
    column: $table.defaultServingG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get caloriesPer100g => $composableBuilder(
    column: $table.caloriesPer100g,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get proteinPer100g => $composableBuilder(
    column: $table.proteinPer100g,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get fatPer100g => $composableBuilder(
    column: $table.fatPer100g,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get carbsPer100g => $composableBuilder(
    column: $table.carbsPer100g,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aliasesJson => $composableBuilder(
    column: $table.aliasesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get ediblePercent => $composableBuilder(
    column: $table.ediblePercent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceVersion => $composableBuilder(
    column: $table.sourceVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get componentsJson => $composableBuilder(
    column: $table.componentsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> mealLogsRefs(
    Expression<bool> Function($$MealLogsTableFilterComposer f) f,
  ) {
    final $$MealLogsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mealLogs,
      getReferencedColumn: (t) => t.foodItemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MealLogsTableFilterComposer(
            $db: $db,
            $table: $db.mealLogs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> pendingRecognitionsRefs(
    Expression<bool> Function($$PendingRecognitionsTableFilterComposer f) f,
  ) {
    final $$PendingRecognitionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.pendingRecognitions,
      getReferencedColumn: (t) => t.resultFoodItemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PendingRecognitionsTableFilterComposer(
            $db: $db,
            $table: $db.pendingRecognitions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FoodItemsTableOrderingComposer
    extends Composer<_$EatWiseDatabase, $FoodItemsTable> {
  $$FoodItemsTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get defaultServingG => $composableBuilder(
    column: $table.defaultServingG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get caloriesPer100g => $composableBuilder(
    column: $table.caloriesPer100g,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get proteinPer100g => $composableBuilder(
    column: $table.proteinPer100g,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get fatPer100g => $composableBuilder(
    column: $table.fatPer100g,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get carbsPer100g => $composableBuilder(
    column: $table.carbsPer100g,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aliasesJson => $composableBuilder(
    column: $table.aliasesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get ediblePercent => $composableBuilder(
    column: $table.ediblePercent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceVersion => $composableBuilder(
    column: $table.sourceVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get componentsJson => $composableBuilder(
    column: $table.componentsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FoodItemsTableAnnotationComposer
    extends Composer<_$EatWiseDatabase, $FoodItemsTable> {
  $$FoodItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<double> get defaultServingG => $composableBuilder(
    column: $table.defaultServingG,
    builder: (column) => column,
  );

  GeneratedColumn<double> get caloriesPer100g => $composableBuilder(
    column: $table.caloriesPer100g,
    builder: (column) => column,
  );

  GeneratedColumn<double> get proteinPer100g => $composableBuilder(
    column: $table.proteinPer100g,
    builder: (column) => column,
  );

  GeneratedColumn<double> get fatPer100g => $composableBuilder(
    column: $table.fatPer100g,
    builder: (column) => column,
  );

  GeneratedColumn<double> get carbsPer100g => $composableBuilder(
    column: $table.carbsPer100g,
    builder: (column) => column,
  );

  GeneratedColumn<String> get aliasesJson => $composableBuilder(
    column: $table.aliasesJson,
    builder: (column) => column,
  );

  GeneratedColumn<double> get ediblePercent => $composableBuilder(
    column: $table.ediblePercent,
    builder: (column) => column,
  );

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get sourceVersion => $composableBuilder(
    column: $table.sourceVersion,
    builder: (column) => column,
  );

  GeneratedColumn<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get componentsJson => $composableBuilder(
    column: $table.componentsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> mealLogsRefs<T extends Object>(
    Expression<T> Function($$MealLogsTableAnnotationComposer a) f,
  ) {
    final $$MealLogsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mealLogs,
      getReferencedColumn: (t) => t.foodItemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MealLogsTableAnnotationComposer(
            $db: $db,
            $table: $db.mealLogs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> pendingRecognitionsRefs<T extends Object>(
    Expression<T> Function($$PendingRecognitionsTableAnnotationComposer a) f,
  ) {
    final $$PendingRecognitionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.pendingRecognitions,
          getReferencedColumn: (t) => t.resultFoodItemId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$PendingRecognitionsTableAnnotationComposer(
                $db: $db,
                $table: $db.pendingRecognitions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$FoodItemsTableTableManager
    extends
        RootTableManager<
          _$EatWiseDatabase,
          $FoodItemsTable,
          FoodItem,
          $$FoodItemsTableFilterComposer,
          $$FoodItemsTableOrderingComposer,
          $$FoodItemsTableAnnotationComposer,
          $$FoodItemsTableCreateCompanionBuilder,
          $$FoodItemsTableUpdateCompanionBuilder,
          (FoodItem, $$FoodItemsTableReferences),
          FoodItem,
          PrefetchHooks Function({
            bool mealLogsRefs,
            bool pendingRecognitionsRefs,
          })
        > {
  $$FoodItemsTableTableManager(_$EatWiseDatabase db, $FoodItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FoodItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FoodItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FoodItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<double> defaultServingG = const Value.absent(),
                Value<double> caloriesPer100g = const Value.absent(),
                Value<double> proteinPer100g = const Value.absent(),
                Value<double> fatPer100g = const Value.absent(),
                Value<double> carbsPer100g = const Value.absent(),
                Value<String?> aliasesJson = const Value.absent(),
                Value<double?> ediblePercent = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String> sourceVersion = const Value.absent(),
                Value<double?> confidence = const Value.absent(),
                Value<String?> componentsJson = const Value.absent(),
                Value<String?> thumbnailPath = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
              }) => FoodItemsCompanion(
                id: id,
                name: name,
                defaultServingG: defaultServingG,
                caloriesPer100g: caloriesPer100g,
                proteinPer100g: proteinPer100g,
                fatPer100g: fatPer100g,
                carbsPer100g: carbsPer100g,
                aliasesJson: aliasesJson,
                ediblePercent: ediblePercent,
                source: source,
                sourceVersion: sourceVersion,
                confidence: confidence,
                componentsJson: componentsJson,
                thumbnailPath: thumbnailPath,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required double defaultServingG,
                required double caloriesPer100g,
                required double proteinPer100g,
                required double fatPer100g,
                required double carbsPer100g,
                Value<String?> aliasesJson = const Value.absent(),
                Value<double?> ediblePercent = const Value.absent(),
                required String source,
                required String sourceVersion,
                Value<double?> confidence = const Value.absent(),
                Value<String?> componentsJson = const Value.absent(),
                Value<String?> thumbnailPath = const Value.absent(),
                required int createdAt,
              }) => FoodItemsCompanion.insert(
                id: id,
                name: name,
                defaultServingG: defaultServingG,
                caloriesPer100g: caloriesPer100g,
                proteinPer100g: proteinPer100g,
                fatPer100g: fatPer100g,
                carbsPer100g: carbsPer100g,
                aliasesJson: aliasesJson,
                ediblePercent: ediblePercent,
                source: source,
                sourceVersion: sourceVersion,
                confidence: confidence,
                componentsJson: componentsJson,
                thumbnailPath: thumbnailPath,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$FoodItemsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({mealLogsRefs = false, pendingRecognitionsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (mealLogsRefs) db.mealLogs,
                    if (pendingRecognitionsRefs) db.pendingRecognitions,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (mealLogsRefs)
                        await $_getPrefetchedData<
                          FoodItem,
                          $FoodItemsTable,
                          MealLog
                        >(
                          currentTable: table,
                          referencedTable: $$FoodItemsTableReferences
                              ._mealLogsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$FoodItemsTableReferences(
                                db,
                                table,
                                p0,
                              ).mealLogsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.foodItemId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (pendingRecognitionsRefs)
                        await $_getPrefetchedData<
                          FoodItem,
                          $FoodItemsTable,
                          PendingRecognition
                        >(
                          currentTable: table,
                          referencedTable: $$FoodItemsTableReferences
                              ._pendingRecognitionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$FoodItemsTableReferences(
                                db,
                                table,
                                p0,
                              ).pendingRecognitionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.resultFoodItemId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$FoodItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$EatWiseDatabase,
      $FoodItemsTable,
      FoodItem,
      $$FoodItemsTableFilterComposer,
      $$FoodItemsTableOrderingComposer,
      $$FoodItemsTableAnnotationComposer,
      $$FoodItemsTableCreateCompanionBuilder,
      $$FoodItemsTableUpdateCompanionBuilder,
      (FoodItem, $$FoodItemsTableReferences),
      FoodItem,
      PrefetchHooks Function({bool mealLogsRefs, bool pendingRecognitionsRefs})
    >;
typedef $$MealLogsTableCreateCompanionBuilder =
    MealLogsCompanion Function({
      Value<int> id,
      required String date,
      required String mealType,
      required int foodItemId,
      required double actualServingG,
      required double actualCalories,
      required double actualProteinG,
      required double actualFatG,
      required double actualCarbsG,
      Value<String?> originalImagePath,
      Value<double?> recognitionConfidence,
      Value<String?> componentsSnapshotJson,
      required int loggedAt,
    });
typedef $$MealLogsTableUpdateCompanionBuilder =
    MealLogsCompanion Function({
      Value<int> id,
      Value<String> date,
      Value<String> mealType,
      Value<int> foodItemId,
      Value<double> actualServingG,
      Value<double> actualCalories,
      Value<double> actualProteinG,
      Value<double> actualFatG,
      Value<double> actualCarbsG,
      Value<String?> originalImagePath,
      Value<double?> recognitionConfidence,
      Value<String?> componentsSnapshotJson,
      Value<int> loggedAt,
    });

final class $$MealLogsTableReferences
    extends BaseReferences<_$EatWiseDatabase, $MealLogsTable, MealLog> {
  $$MealLogsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $FoodItemsTable _foodItemIdTable(_$EatWiseDatabase db) =>
      db.foodItems.createAlias('meal_logs__food_item_id__food_items__id');

  $$FoodItemsTableProcessedTableManager get foodItemId {
    final $_column = $_itemColumn<int>('food_item_id')!;

    final manager = $$FoodItemsTableTableManager(
      $_db,
      $_db.foodItems,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_foodItemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<
    $RecognitionFeedbacksTable,
    List<RecognitionFeedback>
  >
  _recognitionFeedbacksRefsTable(_$EatWiseDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.recognitionFeedbacks,
        aliasName: 'meal_logs__id__recognition_feedbacks__meal_log_id',
      );

  $$RecognitionFeedbacksTableProcessedTableManager
  get recognitionFeedbacksRefs {
    final manager = $$RecognitionFeedbacksTableTableManager(
      $_db,
      $_db.recognitionFeedbacks,
    ).filter((f) => f.mealLogId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _recognitionFeedbacksRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$MealLogsTableFilterComposer
    extends Composer<_$EatWiseDatabase, $MealLogsTable> {
  $$MealLogsTableFilterComposer({
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

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mealType => $composableBuilder(
    column: $table.mealType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get actualServingG => $composableBuilder(
    column: $table.actualServingG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get actualCalories => $composableBuilder(
    column: $table.actualCalories,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get actualProteinG => $composableBuilder(
    column: $table.actualProteinG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get actualFatG => $composableBuilder(
    column: $table.actualFatG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get actualCarbsG => $composableBuilder(
    column: $table.actualCarbsG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originalImagePath => $composableBuilder(
    column: $table.originalImagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get recognitionConfidence => $composableBuilder(
    column: $table.recognitionConfidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get componentsSnapshotJson => $composableBuilder(
    column: $table.componentsSnapshotJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get loggedAt => $composableBuilder(
    column: $table.loggedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$FoodItemsTableFilterComposer get foodItemId {
    final $$FoodItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.foodItemId,
      referencedTable: $db.foodItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoodItemsTableFilterComposer(
            $db: $db,
            $table: $db.foodItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> recognitionFeedbacksRefs(
    Expression<bool> Function($$RecognitionFeedbacksTableFilterComposer f) f,
  ) {
    final $$RecognitionFeedbacksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.recognitionFeedbacks,
      getReferencedColumn: (t) => t.mealLogId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecognitionFeedbacksTableFilterComposer(
            $db: $db,
            $table: $db.recognitionFeedbacks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MealLogsTableOrderingComposer
    extends Composer<_$EatWiseDatabase, $MealLogsTable> {
  $$MealLogsTableOrderingComposer({
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

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mealType => $composableBuilder(
    column: $table.mealType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get actualServingG => $composableBuilder(
    column: $table.actualServingG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get actualCalories => $composableBuilder(
    column: $table.actualCalories,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get actualProteinG => $composableBuilder(
    column: $table.actualProteinG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get actualFatG => $composableBuilder(
    column: $table.actualFatG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get actualCarbsG => $composableBuilder(
    column: $table.actualCarbsG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originalImagePath => $composableBuilder(
    column: $table.originalImagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get recognitionConfidence => $composableBuilder(
    column: $table.recognitionConfidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get componentsSnapshotJson => $composableBuilder(
    column: $table.componentsSnapshotJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get loggedAt => $composableBuilder(
    column: $table.loggedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$FoodItemsTableOrderingComposer get foodItemId {
    final $$FoodItemsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.foodItemId,
      referencedTable: $db.foodItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoodItemsTableOrderingComposer(
            $db: $db,
            $table: $db.foodItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MealLogsTableAnnotationComposer
    extends Composer<_$EatWiseDatabase, $MealLogsTable> {
  $$MealLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get mealType =>
      $composableBuilder(column: $table.mealType, builder: (column) => column);

  GeneratedColumn<double> get actualServingG => $composableBuilder(
    column: $table.actualServingG,
    builder: (column) => column,
  );

  GeneratedColumn<double> get actualCalories => $composableBuilder(
    column: $table.actualCalories,
    builder: (column) => column,
  );

  GeneratedColumn<double> get actualProteinG => $composableBuilder(
    column: $table.actualProteinG,
    builder: (column) => column,
  );

  GeneratedColumn<double> get actualFatG => $composableBuilder(
    column: $table.actualFatG,
    builder: (column) => column,
  );

  GeneratedColumn<double> get actualCarbsG => $composableBuilder(
    column: $table.actualCarbsG,
    builder: (column) => column,
  );

  GeneratedColumn<String> get originalImagePath => $composableBuilder(
    column: $table.originalImagePath,
    builder: (column) => column,
  );

  GeneratedColumn<double> get recognitionConfidence => $composableBuilder(
    column: $table.recognitionConfidence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get componentsSnapshotJson => $composableBuilder(
    column: $table.componentsSnapshotJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get loggedAt =>
      $composableBuilder(column: $table.loggedAt, builder: (column) => column);

  $$FoodItemsTableAnnotationComposer get foodItemId {
    final $$FoodItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.foodItemId,
      referencedTable: $db.foodItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoodItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.foodItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> recognitionFeedbacksRefs<T extends Object>(
    Expression<T> Function($$RecognitionFeedbacksTableAnnotationComposer a) f,
  ) {
    final $$RecognitionFeedbacksTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.recognitionFeedbacks,
          getReferencedColumn: (t) => t.mealLogId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$RecognitionFeedbacksTableAnnotationComposer(
                $db: $db,
                $table: $db.recognitionFeedbacks,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$MealLogsTableTableManager
    extends
        RootTableManager<
          _$EatWiseDatabase,
          $MealLogsTable,
          MealLog,
          $$MealLogsTableFilterComposer,
          $$MealLogsTableOrderingComposer,
          $$MealLogsTableAnnotationComposer,
          $$MealLogsTableCreateCompanionBuilder,
          $$MealLogsTableUpdateCompanionBuilder,
          (MealLog, $$MealLogsTableReferences),
          MealLog,
          PrefetchHooks Function({
            bool foodItemId,
            bool recognitionFeedbacksRefs,
          })
        > {
  $$MealLogsTableTableManager(_$EatWiseDatabase db, $MealLogsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MealLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MealLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MealLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<String> mealType = const Value.absent(),
                Value<int> foodItemId = const Value.absent(),
                Value<double> actualServingG = const Value.absent(),
                Value<double> actualCalories = const Value.absent(),
                Value<double> actualProteinG = const Value.absent(),
                Value<double> actualFatG = const Value.absent(),
                Value<double> actualCarbsG = const Value.absent(),
                Value<String?> originalImagePath = const Value.absent(),
                Value<double?> recognitionConfidence = const Value.absent(),
                Value<String?> componentsSnapshotJson = const Value.absent(),
                Value<int> loggedAt = const Value.absent(),
              }) => MealLogsCompanion(
                id: id,
                date: date,
                mealType: mealType,
                foodItemId: foodItemId,
                actualServingG: actualServingG,
                actualCalories: actualCalories,
                actualProteinG: actualProteinG,
                actualFatG: actualFatG,
                actualCarbsG: actualCarbsG,
                originalImagePath: originalImagePath,
                recognitionConfidence: recognitionConfidence,
                componentsSnapshotJson: componentsSnapshotJson,
                loggedAt: loggedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String date,
                required String mealType,
                required int foodItemId,
                required double actualServingG,
                required double actualCalories,
                required double actualProteinG,
                required double actualFatG,
                required double actualCarbsG,
                Value<String?> originalImagePath = const Value.absent(),
                Value<double?> recognitionConfidence = const Value.absent(),
                Value<String?> componentsSnapshotJson = const Value.absent(),
                required int loggedAt,
              }) => MealLogsCompanion.insert(
                id: id,
                date: date,
                mealType: mealType,
                foodItemId: foodItemId,
                actualServingG: actualServingG,
                actualCalories: actualCalories,
                actualProteinG: actualProteinG,
                actualFatG: actualFatG,
                actualCarbsG: actualCarbsG,
                originalImagePath: originalImagePath,
                recognitionConfidence: recognitionConfidence,
                componentsSnapshotJson: componentsSnapshotJson,
                loggedAt: loggedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MealLogsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({foodItemId = false, recognitionFeedbacksRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (recognitionFeedbacksRefs) db.recognitionFeedbacks,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (foodItemId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.foodItemId,
                                    referencedTable: $$MealLogsTableReferences
                                        ._foodItemIdTable(db),
                                    referencedColumn: $$MealLogsTableReferences
                                        ._foodItemIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (recognitionFeedbacksRefs)
                        await $_getPrefetchedData<
                          MealLog,
                          $MealLogsTable,
                          RecognitionFeedback
                        >(
                          currentTable: table,
                          referencedTable: $$MealLogsTableReferences
                              ._recognitionFeedbacksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MealLogsTableReferences(
                                db,
                                table,
                                p0,
                              ).recognitionFeedbacksRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.mealLogId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$MealLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$EatWiseDatabase,
      $MealLogsTable,
      MealLog,
      $$MealLogsTableFilterComposer,
      $$MealLogsTableOrderingComposer,
      $$MealLogsTableAnnotationComposer,
      $$MealLogsTableCreateCompanionBuilder,
      $$MealLogsTableUpdateCompanionBuilder,
      (MealLog, $$MealLogsTableReferences),
      MealLog,
      PrefetchHooks Function({bool foodItemId, bool recognitionFeedbacksRefs})
    >;
typedef $$WeightLogsTableCreateCompanionBuilder =
    WeightLogsCompanion Function({
      Value<int> id,
      required String date,
      required double weightKg,
    });
typedef $$WeightLogsTableUpdateCompanionBuilder =
    WeightLogsCompanion Function({
      Value<int> id,
      Value<String> date,
      Value<double> weightKg,
    });

class $$WeightLogsTableFilterComposer
    extends Composer<_$EatWiseDatabase, $WeightLogsTable> {
  $$WeightLogsTableFilterComposer({
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

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get weightKg => $composableBuilder(
    column: $table.weightKg,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WeightLogsTableOrderingComposer
    extends Composer<_$EatWiseDatabase, $WeightLogsTable> {
  $$WeightLogsTableOrderingComposer({
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

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get weightKg => $composableBuilder(
    column: $table.weightKg,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WeightLogsTableAnnotationComposer
    extends Composer<_$EatWiseDatabase, $WeightLogsTable> {
  $$WeightLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<double> get weightKg =>
      $composableBuilder(column: $table.weightKg, builder: (column) => column);
}

class $$WeightLogsTableTableManager
    extends
        RootTableManager<
          _$EatWiseDatabase,
          $WeightLogsTable,
          WeightLog,
          $$WeightLogsTableFilterComposer,
          $$WeightLogsTableOrderingComposer,
          $$WeightLogsTableAnnotationComposer,
          $$WeightLogsTableCreateCompanionBuilder,
          $$WeightLogsTableUpdateCompanionBuilder,
          (
            WeightLog,
            BaseReferences<_$EatWiseDatabase, $WeightLogsTable, WeightLog>,
          ),
          WeightLog,
          PrefetchHooks Function()
        > {
  $$WeightLogsTableTableManager(_$EatWiseDatabase db, $WeightLogsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WeightLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WeightLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WeightLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<double> weightKg = const Value.absent(),
              }) => WeightLogsCompanion(id: id, date: date, weightKg: weightKg),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String date,
                required double weightKg,
              }) => WeightLogsCompanion.insert(
                id: id,
                date: date,
                weightKg: weightKg,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WeightLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$EatWiseDatabase,
      $WeightLogsTable,
      WeightLog,
      $$WeightLogsTableFilterComposer,
      $$WeightLogsTableOrderingComposer,
      $$WeightLogsTableAnnotationComposer,
      $$WeightLogsTableCreateCompanionBuilder,
      $$WeightLogsTableUpdateCompanionBuilder,
      (
        WeightLog,
        BaseReferences<_$EatWiseDatabase, $WeightLogsTable, WeightLog>,
      ),
      WeightLog,
      PrefetchHooks Function()
    >;
typedef $$PendingRecognitionsTableCreateCompanionBuilder =
    PendingRecognitionsCompanion Function({
      Value<int> id,
      required String imagePath,
      required String mealType,
      required String date,
      required String status,
      Value<int> retryCount,
      Value<int?> resultFoodItemId,
      Value<String?> errorMessage,
      Value<String?> promptVersion,
      required int createdAt,
      Value<int?> processedAt,
    });
typedef $$PendingRecognitionsTableUpdateCompanionBuilder =
    PendingRecognitionsCompanion Function({
      Value<int> id,
      Value<String> imagePath,
      Value<String> mealType,
      Value<String> date,
      Value<String> status,
      Value<int> retryCount,
      Value<int?> resultFoodItemId,
      Value<String?> errorMessage,
      Value<String?> promptVersion,
      Value<int> createdAt,
      Value<int?> processedAt,
    });

final class $$PendingRecognitionsTableReferences
    extends
        BaseReferences<
          _$EatWiseDatabase,
          $PendingRecognitionsTable,
          PendingRecognition
        > {
  $$PendingRecognitionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $FoodItemsTable _resultFoodItemIdTable(_$EatWiseDatabase db) => db
      .foodItems
      .createAlias('pending_recognitions__result_food_item_id__food_items__id');

  $$FoodItemsTableProcessedTableManager? get resultFoodItemId {
    final $_column = $_itemColumn<int>('result_food_item_id');
    if ($_column == null) return null;
    final manager = $$FoodItemsTableTableManager(
      $_db,
      $_db.foodItems,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_resultFoodItemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PendingRecognitionsTableFilterComposer
    extends Composer<_$EatWiseDatabase, $PendingRecognitionsTable> {
  $$PendingRecognitionsTableFilterComposer({
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

  ColumnFilters<String> get imagePath => $composableBuilder(
    column: $table.imagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mealType => $composableBuilder(
    column: $table.mealType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get promptVersion => $composableBuilder(
    column: $table.promptVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get processedAt => $composableBuilder(
    column: $table.processedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$FoodItemsTableFilterComposer get resultFoodItemId {
    final $$FoodItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.resultFoodItemId,
      referencedTable: $db.foodItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoodItemsTableFilterComposer(
            $db: $db,
            $table: $db.foodItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PendingRecognitionsTableOrderingComposer
    extends Composer<_$EatWiseDatabase, $PendingRecognitionsTable> {
  $$PendingRecognitionsTableOrderingComposer({
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

  ColumnOrderings<String> get imagePath => $composableBuilder(
    column: $table.imagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mealType => $composableBuilder(
    column: $table.mealType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get promptVersion => $composableBuilder(
    column: $table.promptVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get processedAt => $composableBuilder(
    column: $table.processedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$FoodItemsTableOrderingComposer get resultFoodItemId {
    final $$FoodItemsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.resultFoodItemId,
      referencedTable: $db.foodItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoodItemsTableOrderingComposer(
            $db: $db,
            $table: $db.foodItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PendingRecognitionsTableAnnotationComposer
    extends Composer<_$EatWiseDatabase, $PendingRecognitionsTable> {
  $$PendingRecognitionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get imagePath =>
      $composableBuilder(column: $table.imagePath, builder: (column) => column);

  GeneratedColumn<String> get mealType =>
      $composableBuilder(column: $table.mealType, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get promptVersion => $composableBuilder(
    column: $table.promptVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get processedAt => $composableBuilder(
    column: $table.processedAt,
    builder: (column) => column,
  );

  $$FoodItemsTableAnnotationComposer get resultFoodItemId {
    final $$FoodItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.resultFoodItemId,
      referencedTable: $db.foodItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoodItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.foodItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PendingRecognitionsTableTableManager
    extends
        RootTableManager<
          _$EatWiseDatabase,
          $PendingRecognitionsTable,
          PendingRecognition,
          $$PendingRecognitionsTableFilterComposer,
          $$PendingRecognitionsTableOrderingComposer,
          $$PendingRecognitionsTableAnnotationComposer,
          $$PendingRecognitionsTableCreateCompanionBuilder,
          $$PendingRecognitionsTableUpdateCompanionBuilder,
          (PendingRecognition, $$PendingRecognitionsTableReferences),
          PendingRecognition,
          PrefetchHooks Function({bool resultFoodItemId})
        > {
  $$PendingRecognitionsTableTableManager(
    _$EatWiseDatabase db,
    $PendingRecognitionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingRecognitionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingRecognitionsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$PendingRecognitionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> imagePath = const Value.absent(),
                Value<String> mealType = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<int?> resultFoodItemId = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                Value<String?> promptVersion = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int?> processedAt = const Value.absent(),
              }) => PendingRecognitionsCompanion(
                id: id,
                imagePath: imagePath,
                mealType: mealType,
                date: date,
                status: status,
                retryCount: retryCount,
                resultFoodItemId: resultFoodItemId,
                errorMessage: errorMessage,
                promptVersion: promptVersion,
                createdAt: createdAt,
                processedAt: processedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String imagePath,
                required String mealType,
                required String date,
                required String status,
                Value<int> retryCount = const Value.absent(),
                Value<int?> resultFoodItemId = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                Value<String?> promptVersion = const Value.absent(),
                required int createdAt,
                Value<int?> processedAt = const Value.absent(),
              }) => PendingRecognitionsCompanion.insert(
                id: id,
                imagePath: imagePath,
                mealType: mealType,
                date: date,
                status: status,
                retryCount: retryCount,
                resultFoodItemId: resultFoodItemId,
                errorMessage: errorMessage,
                promptVersion: promptVersion,
                createdAt: createdAt,
                processedAt: processedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PendingRecognitionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({resultFoodItemId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (resultFoodItemId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.resultFoodItemId,
                                referencedTable:
                                    $$PendingRecognitionsTableReferences
                                        ._resultFoodItemIdTable(db),
                                referencedColumn:
                                    $$PendingRecognitionsTableReferences
                                        ._resultFoodItemIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$PendingRecognitionsTableProcessedTableManager =
    ProcessedTableManager<
      _$EatWiseDatabase,
      $PendingRecognitionsTable,
      PendingRecognition,
      $$PendingRecognitionsTableFilterComposer,
      $$PendingRecognitionsTableOrderingComposer,
      $$PendingRecognitionsTableAnnotationComposer,
      $$PendingRecognitionsTableCreateCompanionBuilder,
      $$PendingRecognitionsTableUpdateCompanionBuilder,
      (PendingRecognition, $$PendingRecognitionsTableReferences),
      PendingRecognition,
      PrefetchHooks Function({bool resultFoodItemId})
    >;
typedef $$InsightSummariesTableCreateCompanionBuilder =
    InsightSummariesCompanion Function({
      Value<int> id,
      required String periodType,
      required String periodStart,
      required String periodEnd,
      required String summaryText,
      Value<int> isEdited,
      required int generatedAt,
    });
typedef $$InsightSummariesTableUpdateCompanionBuilder =
    InsightSummariesCompanion Function({
      Value<int> id,
      Value<String> periodType,
      Value<String> periodStart,
      Value<String> periodEnd,
      Value<String> summaryText,
      Value<int> isEdited,
      Value<int> generatedAt,
    });

class $$InsightSummariesTableFilterComposer
    extends Composer<_$EatWiseDatabase, $InsightSummariesTable> {
  $$InsightSummariesTableFilterComposer({
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

  ColumnFilters<String> get periodType => $composableBuilder(
    column: $table.periodType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get periodStart => $composableBuilder(
    column: $table.periodStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get periodEnd => $composableBuilder(
    column: $table.periodEnd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summaryText => $composableBuilder(
    column: $table.summaryText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get isEdited => $composableBuilder(
    column: $table.isEdited,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get generatedAt => $composableBuilder(
    column: $table.generatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$InsightSummariesTableOrderingComposer
    extends Composer<_$EatWiseDatabase, $InsightSummariesTable> {
  $$InsightSummariesTableOrderingComposer({
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

  ColumnOrderings<String> get periodType => $composableBuilder(
    column: $table.periodType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get periodStart => $composableBuilder(
    column: $table.periodStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get periodEnd => $composableBuilder(
    column: $table.periodEnd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summaryText => $composableBuilder(
    column: $table.summaryText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get isEdited => $composableBuilder(
    column: $table.isEdited,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get generatedAt => $composableBuilder(
    column: $table.generatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$InsightSummariesTableAnnotationComposer
    extends Composer<_$EatWiseDatabase, $InsightSummariesTable> {
  $$InsightSummariesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get periodType => $composableBuilder(
    column: $table.periodType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get periodStart => $composableBuilder(
    column: $table.periodStart,
    builder: (column) => column,
  );

  GeneratedColumn<String> get periodEnd =>
      $composableBuilder(column: $table.periodEnd, builder: (column) => column);

  GeneratedColumn<String> get summaryText => $composableBuilder(
    column: $table.summaryText,
    builder: (column) => column,
  );

  GeneratedColumn<int> get isEdited =>
      $composableBuilder(column: $table.isEdited, builder: (column) => column);

  GeneratedColumn<int> get generatedAt => $composableBuilder(
    column: $table.generatedAt,
    builder: (column) => column,
  );
}

class $$InsightSummariesTableTableManager
    extends
        RootTableManager<
          _$EatWiseDatabase,
          $InsightSummariesTable,
          InsightSummary,
          $$InsightSummariesTableFilterComposer,
          $$InsightSummariesTableOrderingComposer,
          $$InsightSummariesTableAnnotationComposer,
          $$InsightSummariesTableCreateCompanionBuilder,
          $$InsightSummariesTableUpdateCompanionBuilder,
          (
            InsightSummary,
            BaseReferences<
              _$EatWiseDatabase,
              $InsightSummariesTable,
              InsightSummary
            >,
          ),
          InsightSummary,
          PrefetchHooks Function()
        > {
  $$InsightSummariesTableTableManager(
    _$EatWiseDatabase db,
    $InsightSummariesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InsightSummariesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InsightSummariesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InsightSummariesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> periodType = const Value.absent(),
                Value<String> periodStart = const Value.absent(),
                Value<String> periodEnd = const Value.absent(),
                Value<String> summaryText = const Value.absent(),
                Value<int> isEdited = const Value.absent(),
                Value<int> generatedAt = const Value.absent(),
              }) => InsightSummariesCompanion(
                id: id,
                periodType: periodType,
                periodStart: periodStart,
                periodEnd: periodEnd,
                summaryText: summaryText,
                isEdited: isEdited,
                generatedAt: generatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String periodType,
                required String periodStart,
                required String periodEnd,
                required String summaryText,
                Value<int> isEdited = const Value.absent(),
                required int generatedAt,
              }) => InsightSummariesCompanion.insert(
                id: id,
                periodType: periodType,
                periodStart: periodStart,
                periodEnd: periodEnd,
                summaryText: summaryText,
                isEdited: isEdited,
                generatedAt: generatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$InsightSummariesTableProcessedTableManager =
    ProcessedTableManager<
      _$EatWiseDatabase,
      $InsightSummariesTable,
      InsightSummary,
      $$InsightSummariesTableFilterComposer,
      $$InsightSummariesTableOrderingComposer,
      $$InsightSummariesTableAnnotationComposer,
      $$InsightSummariesTableCreateCompanionBuilder,
      $$InsightSummariesTableUpdateCompanionBuilder,
      (
        InsightSummary,
        BaseReferences<
          _$EatWiseDatabase,
          $InsightSummariesTable,
          InsightSummary
        >,
      ),
      InsightSummary,
      PrefetchHooks Function()
    >;
typedef $$RecognitionFeedbacksTableCreateCompanionBuilder =
    RecognitionFeedbacksCompanion Function({
      Value<int> id,
      required int mealLogId,
      required int isCorrect,
      Value<String?> correctedDishName,
      Value<double?> correctedServingG,
      required String promptVersion,
      required int createdAt,
    });
typedef $$RecognitionFeedbacksTableUpdateCompanionBuilder =
    RecognitionFeedbacksCompanion Function({
      Value<int> id,
      Value<int> mealLogId,
      Value<int> isCorrect,
      Value<String?> correctedDishName,
      Value<double?> correctedServingG,
      Value<String> promptVersion,
      Value<int> createdAt,
    });

final class $$RecognitionFeedbacksTableReferences
    extends
        BaseReferences<
          _$EatWiseDatabase,
          $RecognitionFeedbacksTable,
          RecognitionFeedback
        > {
  $$RecognitionFeedbacksTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $MealLogsTable _mealLogIdTable(_$EatWiseDatabase db) => db.mealLogs
      .createAlias('recognition_feedbacks__meal_log_id__meal_logs__id');

  $$MealLogsTableProcessedTableManager get mealLogId {
    final $_column = $_itemColumn<int>('meal_log_id')!;

    final manager = $$MealLogsTableTableManager(
      $_db,
      $_db.mealLogs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_mealLogIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$RecognitionFeedbacksTableFilterComposer
    extends Composer<_$EatWiseDatabase, $RecognitionFeedbacksTable> {
  $$RecognitionFeedbacksTableFilterComposer({
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

  ColumnFilters<int> get isCorrect => $composableBuilder(
    column: $table.isCorrect,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get correctedDishName => $composableBuilder(
    column: $table.correctedDishName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get correctedServingG => $composableBuilder(
    column: $table.correctedServingG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get promptVersion => $composableBuilder(
    column: $table.promptVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$MealLogsTableFilterComposer get mealLogId {
    final $$MealLogsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mealLogId,
      referencedTable: $db.mealLogs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MealLogsTableFilterComposer(
            $db: $db,
            $table: $db.mealLogs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecognitionFeedbacksTableOrderingComposer
    extends Composer<_$EatWiseDatabase, $RecognitionFeedbacksTable> {
  $$RecognitionFeedbacksTableOrderingComposer({
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

  ColumnOrderings<int> get isCorrect => $composableBuilder(
    column: $table.isCorrect,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get correctedDishName => $composableBuilder(
    column: $table.correctedDishName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get correctedServingG => $composableBuilder(
    column: $table.correctedServingG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get promptVersion => $composableBuilder(
    column: $table.promptVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$MealLogsTableOrderingComposer get mealLogId {
    final $$MealLogsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mealLogId,
      referencedTable: $db.mealLogs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MealLogsTableOrderingComposer(
            $db: $db,
            $table: $db.mealLogs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecognitionFeedbacksTableAnnotationComposer
    extends Composer<_$EatWiseDatabase, $RecognitionFeedbacksTable> {
  $$RecognitionFeedbacksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get isCorrect =>
      $composableBuilder(column: $table.isCorrect, builder: (column) => column);

  GeneratedColumn<String> get correctedDishName => $composableBuilder(
    column: $table.correctedDishName,
    builder: (column) => column,
  );

  GeneratedColumn<double> get correctedServingG => $composableBuilder(
    column: $table.correctedServingG,
    builder: (column) => column,
  );

  GeneratedColumn<String> get promptVersion => $composableBuilder(
    column: $table.promptVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$MealLogsTableAnnotationComposer get mealLogId {
    final $$MealLogsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mealLogId,
      referencedTable: $db.mealLogs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MealLogsTableAnnotationComposer(
            $db: $db,
            $table: $db.mealLogs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecognitionFeedbacksTableTableManager
    extends
        RootTableManager<
          _$EatWiseDatabase,
          $RecognitionFeedbacksTable,
          RecognitionFeedback,
          $$RecognitionFeedbacksTableFilterComposer,
          $$RecognitionFeedbacksTableOrderingComposer,
          $$RecognitionFeedbacksTableAnnotationComposer,
          $$RecognitionFeedbacksTableCreateCompanionBuilder,
          $$RecognitionFeedbacksTableUpdateCompanionBuilder,
          (RecognitionFeedback, $$RecognitionFeedbacksTableReferences),
          RecognitionFeedback,
          PrefetchHooks Function({bool mealLogId})
        > {
  $$RecognitionFeedbacksTableTableManager(
    _$EatWiseDatabase db,
    $RecognitionFeedbacksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecognitionFeedbacksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecognitionFeedbacksTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$RecognitionFeedbacksTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> mealLogId = const Value.absent(),
                Value<int> isCorrect = const Value.absent(),
                Value<String?> correctedDishName = const Value.absent(),
                Value<double?> correctedServingG = const Value.absent(),
                Value<String> promptVersion = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
              }) => RecognitionFeedbacksCompanion(
                id: id,
                mealLogId: mealLogId,
                isCorrect: isCorrect,
                correctedDishName: correctedDishName,
                correctedServingG: correctedServingG,
                promptVersion: promptVersion,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int mealLogId,
                required int isCorrect,
                Value<String?> correctedDishName = const Value.absent(),
                Value<double?> correctedServingG = const Value.absent(),
                required String promptVersion,
                required int createdAt,
              }) => RecognitionFeedbacksCompanion.insert(
                id: id,
                mealLogId: mealLogId,
                isCorrect: isCorrect,
                correctedDishName: correctedDishName,
                correctedServingG: correctedServingG,
                promptVersion: promptVersion,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RecognitionFeedbacksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({mealLogId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (mealLogId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.mealLogId,
                                referencedTable:
                                    $$RecognitionFeedbacksTableReferences
                                        ._mealLogIdTable(db),
                                referencedColumn:
                                    $$RecognitionFeedbacksTableReferences
                                        ._mealLogIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$RecognitionFeedbacksTableProcessedTableManager =
    ProcessedTableManager<
      _$EatWiseDatabase,
      $RecognitionFeedbacksTable,
      RecognitionFeedback,
      $$RecognitionFeedbacksTableFilterComposer,
      $$RecognitionFeedbacksTableOrderingComposer,
      $$RecognitionFeedbacksTableAnnotationComposer,
      $$RecognitionFeedbacksTableCreateCompanionBuilder,
      $$RecognitionFeedbacksTableUpdateCompanionBuilder,
      (RecognitionFeedback, $$RecognitionFeedbacksTableReferences),
      RecognitionFeedback,
      PrefetchHooks Function({bool mealLogId})
    >;
typedef $$RecommendationFeedbacksTableCreateCompanionBuilder =
    RecommendationFeedbacksCompanion Function({
      Value<int> id,
      required String foodName,
      required int rating,
      Value<String?> mealType,
      Value<String?> recommendDate,
      required int createdAt,
    });
typedef $$RecommendationFeedbacksTableUpdateCompanionBuilder =
    RecommendationFeedbacksCompanion Function({
      Value<int> id,
      Value<String> foodName,
      Value<int> rating,
      Value<String?> mealType,
      Value<String?> recommendDate,
      Value<int> createdAt,
    });

class $$RecommendationFeedbacksTableFilterComposer
    extends Composer<_$EatWiseDatabase, $RecommendationFeedbacksTable> {
  $$RecommendationFeedbacksTableFilterComposer({
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

  ColumnFilters<String> get foodName => $composableBuilder(
    column: $table.foodName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mealType => $composableBuilder(
    column: $table.mealType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recommendDate => $composableBuilder(
    column: $table.recommendDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RecommendationFeedbacksTableOrderingComposer
    extends Composer<_$EatWiseDatabase, $RecommendationFeedbacksTable> {
  $$RecommendationFeedbacksTableOrderingComposer({
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

  ColumnOrderings<String> get foodName => $composableBuilder(
    column: $table.foodName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mealType => $composableBuilder(
    column: $table.mealType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recommendDate => $composableBuilder(
    column: $table.recommendDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RecommendationFeedbacksTableAnnotationComposer
    extends Composer<_$EatWiseDatabase, $RecommendationFeedbacksTable> {
  $$RecommendationFeedbacksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get foodName =>
      $composableBuilder(column: $table.foodName, builder: (column) => column);

  GeneratedColumn<int> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);

  GeneratedColumn<String> get mealType =>
      $composableBuilder(column: $table.mealType, builder: (column) => column);

  GeneratedColumn<String> get recommendDate => $composableBuilder(
    column: $table.recommendDate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$RecommendationFeedbacksTableTableManager
    extends
        RootTableManager<
          _$EatWiseDatabase,
          $RecommendationFeedbacksTable,
          RecommendationFeedback,
          $$RecommendationFeedbacksTableFilterComposer,
          $$RecommendationFeedbacksTableOrderingComposer,
          $$RecommendationFeedbacksTableAnnotationComposer,
          $$RecommendationFeedbacksTableCreateCompanionBuilder,
          $$RecommendationFeedbacksTableUpdateCompanionBuilder,
          (
            RecommendationFeedback,
            BaseReferences<
              _$EatWiseDatabase,
              $RecommendationFeedbacksTable,
              RecommendationFeedback
            >,
          ),
          RecommendationFeedback,
          PrefetchHooks Function()
        > {
  $$RecommendationFeedbacksTableTableManager(
    _$EatWiseDatabase db,
    $RecommendationFeedbacksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecommendationFeedbacksTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$RecommendationFeedbacksTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$RecommendationFeedbacksTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> foodName = const Value.absent(),
                Value<int> rating = const Value.absent(),
                Value<String?> mealType = const Value.absent(),
                Value<String?> recommendDate = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
              }) => RecommendationFeedbacksCompanion(
                id: id,
                foodName: foodName,
                rating: rating,
                mealType: mealType,
                recommendDate: recommendDate,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String foodName,
                required int rating,
                Value<String?> mealType = const Value.absent(),
                Value<String?> recommendDate = const Value.absent(),
                required int createdAt,
              }) => RecommendationFeedbacksCompanion.insert(
                id: id,
                foodName: foodName,
                rating: rating,
                mealType: mealType,
                recommendDate: recommendDate,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RecommendationFeedbacksTableProcessedTableManager =
    ProcessedTableManager<
      _$EatWiseDatabase,
      $RecommendationFeedbacksTable,
      RecommendationFeedback,
      $$RecommendationFeedbacksTableFilterComposer,
      $$RecommendationFeedbacksTableOrderingComposer,
      $$RecommendationFeedbacksTableAnnotationComposer,
      $$RecommendationFeedbacksTableCreateCompanionBuilder,
      $$RecommendationFeedbacksTableUpdateCompanionBuilder,
      (
        RecommendationFeedback,
        BaseReferences<
          _$EatWiseDatabase,
          $RecommendationFeedbacksTable,
          RecommendationFeedback
        >,
      ),
      RecommendationFeedback,
      PrefetchHooks Function()
    >;

class $EatWiseDatabaseManager {
  final _$EatWiseDatabase _db;
  $EatWiseDatabaseManager(this._db);
  $$ProfilesTableTableManager get profiles =>
      $$ProfilesTableTableManager(_db, _db.profiles);
  $$FoodItemsTableTableManager get foodItems =>
      $$FoodItemsTableTableManager(_db, _db.foodItems);
  $$MealLogsTableTableManager get mealLogs =>
      $$MealLogsTableTableManager(_db, _db.mealLogs);
  $$WeightLogsTableTableManager get weightLogs =>
      $$WeightLogsTableTableManager(_db, _db.weightLogs);
  $$PendingRecognitionsTableTableManager get pendingRecognitions =>
      $$PendingRecognitionsTableTableManager(_db, _db.pendingRecognitions);
  $$InsightSummariesTableTableManager get insightSummaries =>
      $$InsightSummariesTableTableManager(_db, _db.insightSummaries);
  $$RecognitionFeedbacksTableTableManager get recognitionFeedbacks =>
      $$RecognitionFeedbacksTableTableManager(_db, _db.recognitionFeedbacks);
  $$RecommendationFeedbacksTableTableManager get recommendationFeedbacks =>
      $$RecommendationFeedbacksTableTableManager(
        _db,
        _db.recommendationFeedbacks,
      );
}
