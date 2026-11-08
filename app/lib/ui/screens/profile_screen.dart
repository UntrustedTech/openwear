import 'package:flutter/cupertino.dart'
    show CupertinoDatePicker, CupertinoDatePickerMode, CupertinoPicker;
import 'package:flutter/material.dart';
import 'package:openwear/protocol/profile.dart';
import 'package:openwear/services/band_service.dart';
import 'package:openwear/services/units.dart';
import 'package:openwear/ui/common.dart';
import 'package:openwear/ui/kit/kit.dart';

/// Body data and daily goals; changes go to the band right away.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.band});
  final BandService band;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: band,
    builder: (context, _) {
      final p = band.profile;
      final u = band.units;
      Future<void> save(UserProfile next) =>
          runAction(context, () => band.setProfile(next));
      return SubPage(
        title: 'Profile & goals',
        children: [
          RowGroup(
            label: 'About you',
            note:
                'The band uses these for calories and heart-rate zones. They '
                'stay on your phone and band.',
            children: [
              _row(
                'Height',
                p.heightCm == null ? 'Not set' : u.height(p.heightCm ?? 0),
                () => _pickNumber(
                  context,
                  title: 'Height',
                  values: [for (var cm = 120; cm <= 220; cm++) cm],
                  label: u.height,
                  current: p.heightCm ?? UserProfile.defaultHeight,
                  onPicked: (v) => save(p.copyWith(heightCm: v)),
                ),
              ),
              _row(
                'Weight',
                p.weightKg == null ? 'Not set' : u.weight(p.weightKg ?? 0),
                () => _pickNumber(
                  context,
                  title: 'Weight',
                  values: [for (var kg = 30; kg <= 200; kg++) kg],
                  label: u.weight,
                  current: (p.weightKg ?? UserProfile.defaultWeight).round(),
                  onPicked: (v) => save(p.copyWith(weightKg: v.toDouble())),
                ),
              ),
              _row(
                'Birthday',
                switch (p.birthday) {
                  null => 'Not set',
                  final d => _date(d),
                },
                () => _pickDate(
                  context,
                  p.birthday ?? UserProfile.defaultBirthday,
                  (d) => save(p.copyWith(birthday: d)),
                ),
              ),
              _row(
                'Sex',
                switch (p.sex) {
                  Sex.male => 'Male',
                  Sex.female => 'Female',
                  Sex.unspecified => 'Not set',
                },
                () => _pickSex(context, p.sex, (s) => save(p.copyWith(sex: s))),
              ),
            ],
          ),
          RowGroup(
            label: 'Daily goals',
            note: 'Shown on the band and on the Today screen.',
            children: [
              _goal(
                context,
                'Steps',
                p.stepGoal,
                1000,
                30000,
                500,
                (v) => save(p.copyWith(stepGoal: v)),
              ),
              _goal(
                context,
                'Move (kcal)',
                p.calorieGoal,
                100,
                2000,
                50,
                (v) => save(p.copyWith(calorieGoal: v)),
              ),
              _goal(
                context,
                'Exercise (min)',
                p.exerciseGoal,
                10,
                180,
                5,
                (v) => save(p.copyWith(exerciseGoal: v)),
              ),
              _goal(
                context,
                'Stand (hours)',
                p.standGoal,
                4,
                16,
                1,
                (v) => save(p.copyWith(standGoal: v)),
              ),
              _goal(
                context,
                'Sleep (min)',
                p.sleepGoalMinutes,
                300,
                720,
                30,
                (v) => save(p.copyWith(sleepGoalMinutes: v)),
              ),
            ],
          ),
        ],
      );
    },
  );

  Widget _row(String title, String value, VoidCallback onTap) =>
      KitRow(title: title, value: value, chevron: true, onTap: onTap);

  Widget _goal(
    BuildContext context,
    String title,
    int value,
    int min,
    int max,
    int step,
    ValueChanged<int> onPicked,
  ) => _row(
    title,
    groupThousands(value),
    () => _pickNumber(
      context,
      title: title,
      values: [for (var v = min; v <= max; v += step) v],
      label: groupThousands,
      current: value,
      onPicked: onPicked,
    ),
  );
}

String _date(DateTime d) => '${d.day}/${d.month}/${d.year}';

Future<void> _pickNumber(
  BuildContext context, {
  required String title,
  required List<int> values,
  required String Function(int) label,
  required int current,
  required ValueChanged<int> onPicked,
}) async {
  var index = values.indexWhere((v) => v >= current);
  if (index < 0) index = values.length - 1;
  var chosen = values[index];
  final ok = await showWheelSheet(
    context,
    title: title,
    wheel: CupertinoPicker(
      itemExtent: 40,
      scrollController: FixedExtentScrollController(initialItem: index),
      onSelectedItemChanged: (i) => chosen = values[i],
      children: [for (final v in values) Center(child: Text(label(v)))],
    ),
  );
  if (ok) onPicked(chosen);
}

Future<void> _pickDate(
  BuildContext context,
  DateTime current,
  ValueChanged<DateTime> onPicked,
) async {
  var chosen = current;
  final now = DateTime.now();
  final ok = await showWheelSheet(
    context,
    title: 'Birthday',
    wheel: CupertinoDatePicker(
      mode: CupertinoDatePickerMode.date,
      initialDateTime: current,
      minimumDate: DateTime(1920),
      maximumDate: DateTime(now.year - 5, now.month, now.day),
      onDateTimeChanged: (d) => chosen = d,
    ),
  );
  if (ok) onPicked(DateTime(chosen.year, chosen.month, chosen.day));
}

Future<void> _pickSex(
  BuildContext context,
  Sex current,
  ValueChanged<Sex> onPicked,
) async {
  final s = await showOptionSheet<Sex>(
    context,
    title: 'Sex',
    message: 'Used for calorie estimates.',
    selected: current,
    options: const [
      SheetOption(Sex.female, 'Female'),
      SheetOption(Sex.male, 'Male'),
      SheetOption(Sex.unspecified, 'Prefer not to say'),
    ],
  );
  if (s != null) onPicked(s);
}

/// Chooses metric or imperial display.
Future<void> chooseUnits(BuildContext context, BandService band) async {
  final u = await showOptionSheet<UnitSystem>(
    context,
    title: 'Units',
    message:
        'How OpenWear shows measurements. The band always receives metric '
        'values and converts them using its own settings.',
    selected: band.units,
    options: [
      for (final s in UnitSystem.values)
        SheetOption(s, s.label, detail: s.example),
    ],
  );
  if (u != null) await band.setUnits(u);
}
