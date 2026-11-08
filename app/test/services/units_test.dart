import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/services/units.dart';

void main() {
  test('temperatures convert from Celsius', () {
    expect(UnitSystem.imperial.temperature(20), 68);
    expect(UnitSystem.metric.temperature(20.4), 20);
    expect(UnitSystem.imperial.temperature(-40), -40);
  });

  test('lengths and weights format per system', () {
    expect(UnitSystem.metric.height(175), '175 cm');
    expect(UnitSystem.imperial.height(175), '5′ 9″');
    expect(UnitSystem.imperial.weight(70), '154 lb');
    expect(UnitSystem.metric.weight(70), '70 kg');
    expect(UnitSystem.imperial.distance(1609.344), '1.00 mi');
  });

  test('unknown stored values fall back to metric', () {
    expect(UnitSystem.parse('imperial'), UnitSystem.imperial);
    expect(UnitSystem.parse(null), UnitSystem.metric);
  });
}
