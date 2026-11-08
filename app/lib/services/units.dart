/// Metric or imperial display. The band always receives metric values
/// (as Mi Fitness sends them); this only changes what the app shows.
library;

enum UnitSystem {
  metric('Metric', '°C · km · kg · cm'),
  imperial('Imperial', '°F · mi · lb · ft');

  const UnitSystem(this.label, this.example);
  final String label;
  final String example;

  bool get isImperial => this == UnitSystem.imperial;

  static UnitSystem parse(String? s) =>
      UnitSystem.values.firstWhere((u) => u.name == s, orElse: () => metric);

  String get temperatureSymbol => isImperial ? '°F' : '°C';

  /// Whole degrees in this system from Celsius.
  int temperature(num celsius) =>
      (isImperial ? celsius * 9 / 5 + 32 : celsius).round();

  String distance(num metres) => isImperial
      ? '${(metres / 1609.344).toStringAsFixed(2)} mi'
      : '${(metres / 1000).toStringAsFixed(2)} km';

  String weight(num kg) => isImperial
      ? '${(kg * 2.20462).round()} lb'
      : '${kg.toStringAsFixed(kg % 1 == 0 ? 0 : 1)} kg';

  String height(num cm) {
    if (!isImperial) return '${cm.round()} cm';
    final inches = (cm / 2.54).round();
    return '${inches ~/ 12}′ ${inches % 12}″';
  }
}
