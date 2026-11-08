/// The wearer's profile and daily goals (8/0), as Mi Fitness sends them
/// after pairing and whenever they change. The band uses them for calorie
/// and heart-rate-zone maths and for its goal rings.
///
/// Message (fitness payload field 1), all optional:
///   1 height cm · 2 weight kg (float) · 3 birthday yyyymmdd · 4 sex
///   (1 male, 2 female) · 5 max HR · 6 calorie goal · 7 step goal ·
///   9 stand goal (hours) · 10 sleep goal (minutes) · 11 exercise goal
///   (minutes) · 12–15 "value is a default" flags for height, weight,
///   birthday and sex.
library;

import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/pb.dart';

enum Sex { male, female, unspecified }

class UserProfile {
  const UserProfile({
    this.heightCm,
    this.weightKg,
    this.birthday,
    this.sex = Sex.unspecified,
    this.stepGoal = 8000,
    this.calorieGoal = 350,
    this.standGoal = 12,
    this.exerciseGoal = 30,
    this.sleepGoalMinutes = 480,
  });

  final int? heightCm;
  final double? weightKg;
  final DateTime? birthday;
  final Sex sex;
  final int stepGoal;
  final int calorieGoal;
  final int standGoal;
  final int exerciseGoal;
  final int sleepGoalMinutes;

  /// Mi Fitness's stand-ins when a value is unknown.
  static const defaultHeight = 170, defaultWeight = 60.0;
  static final defaultBirthday = DateTime(1990);

  /// 220 − age, the usual estimate the band also uses.
  int? maxHeartRate({DateTime? now}) {
    final b = birthday;
    if (b == null) return null;
    final today = now ?? DateTime.now();
    var age = today.year - b.year;
    if (today.month < b.month ||
        (today.month == b.month && today.day < b.day)) {
      age--;
    }
    return 220 - age;
  }

  UserProfile copyWith({
    int? heightCm,
    double? weightKg,
    DateTime? birthday,
    Sex? sex,
    int? stepGoal,
    int? calorieGoal,
    int? standGoal,
    int? exerciseGoal,
    int? sleepGoalMinutes,
  }) => UserProfile(
    heightCm: heightCm ?? this.heightCm,
    weightKg: weightKg ?? this.weightKg,
    birthday: birthday ?? this.birthday,
    sex: sex ?? this.sex,
    stepGoal: stepGoal ?? this.stepGoal,
    calorieGoal: calorieGoal ?? this.calorieGoal,
    standGoal: standGoal ?? this.standGoal,
    exerciseGoal: exerciseGoal ?? this.exerciseGoal,
    sleepGoalMinutes: sleepGoalMinutes ?? this.sleepGoalMinutes,
  );

  Map<String, String> toJson() => {
    if (heightCm != null) 'height': '$heightCm',
    if (weightKg != null) 'weight': '$weightKg',
    if (birthday != null) 'birthday': birthday!.toIso8601String(),
    'sex': sex.name,
    'steps': '$stepGoal',
    'calories': '$calorieGoal',
    'stand': '$standGoal',
    'exercise': '$exerciseGoal',
    'sleep': '$sleepGoalMinutes',
  };

  static UserProfile fromJson(Map<String, dynamic> j) {
    int? i(String k) => int.tryParse('${j[k] ?? ''}');
    const d = UserProfile();
    return UserProfile(
      heightCm: i('height'),
      weightKg: double.tryParse('${j['weight'] ?? ''}'),
      birthday: DateTime.tryParse('${j['birthday'] ?? ''}'),
      sex: Sex.values.firstWhere(
        (s) => s.name == j['sex'],
        orElse: () => Sex.unspecified,
      ),
      stepGoal: i('steps') ?? d.stepGoal,
      calorieGoal: i('calories') ?? d.calorieGoal,
      standGoal: i('stand') ?? d.standGoal,
      exerciseGoal: i('exercise') ?? d.exerciseGoal,
      sleepGoalMinutes: i('sleep') ?? d.sleepGoalMinutes,
    );
  }
}

int _yyyymmdd(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

Command profileCommand(UserProfile p) {
  final birthday = p.birthday;
  final maxHr = p.maxHeartRate();
  return Command.of(typeFitness, 0, [
    PbBytes(
      1,
      pbEncode([
        PbVarint(1, p.heightCm ?? UserProfile.defaultHeight),
        PbFloat(2, p.weightKg ?? UserProfile.defaultWeight),
        PbVarint(3, _yyyymmdd(birthday ?? UserProfile.defaultBirthday)),
        PbVarint(4, p.sex == Sex.female ? 2 : 1),
        if (maxHr != null) PbVarint(5, maxHr),
        PbVarint(6, p.calorieGoal),
        PbVarint(7, p.stepGoal),
        PbVarint(9, p.standGoal),
        PbVarint(10, p.sleepGoalMinutes),
        PbVarint(11, p.exerciseGoal),
        if (p.heightCm == null) const PbVarint(12, 1),
        if (p.weightKg == null) const PbVarint(13, 1),
        if (birthday == null) const PbVarint(14, 1),
        if (p.sex == Sex.unspecified) const PbVarint(15, 1),
      ]),
    ),
  ]);
}
