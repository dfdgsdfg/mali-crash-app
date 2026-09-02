import 'package:flutter_test/flutter_test.dart';

import 'package:mali_crash_app/main.dart';

void main() {
  test('scenario 6 uses the external lifecycle workload contract', () {
    final scenario = scenarioForNumber(6);

    expect(scenario.number, 6);
    expect(scenario.darkMode, isTrue);
    expect(scenario.batchSize, 20);
    expect(scenario.analysisConcurrency, 8);
    expect(scenario.rotateSurface, isFalse);
    expect(scenario.cycleTask, isFalse);
  });

  test('scenario 6 has a ten-minute Test Loop deadline', () {
    expect(testLoopDurationForScenario(6), const Duration(minutes: 10));
    expect(testLoopDurationForScenario(7), const Duration(minutes: 10));
    expect(testLoopDurationForScenario(3), const Duration(minutes: 3));
  });

  test('scenario 7 keeps decode workload but disables GPU pixel analysis', () {
    final scenario = scenarioForNumber(7);

    expect(scenario.number, 7);
    expect(scenario.darkMode, isTrue);
    expect(scenario.batchSize, 20);
    expect(scenario.analysisConcurrency, 8);
    expect(scenario.analyzesPixels, isFalse);
    expect(scenario.rotateSurface, isFalse);
    expect(scenario.cycleTask, isFalse);
  });
}
