import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mali_crash_app/main.dart';

void main() {
  test('does not overlap cycle task with rotation checkpoints', () {
    expect(
      shouldCycleTaskForIteration(
        iteration: 6,
        cycleTask: true,
        rotateSurface: true,
      ),
      isTrue,
    );
    expect(
      shouldCycleTaskForIteration(
        iteration: 12,
        cycleTask: true,
        rotateSurface: true,
      ),
      isFalse,
    );
    expect(
      shouldCycleTaskForIteration(
        iteration: 18,
        cycleTask: true,
        rotateSurface: true,
      ),
      isTrue,
    );
    expect(
      shouldCycleTaskForIteration(
        iteration: 30,
        cycleTask: true,
        rotateSurface: true,
      ),
      isTrue,
    );
  });

  test('tracks distinct rotation transitions and cycle task requests', () {
    final telemetry = ReproTelemetry();

    telemetry.recordRotationTransition(DeviceOrientation.landscapeLeft);
    telemetry.recordRotationTransition(DeviceOrientation.landscapeLeft);
    telemetry.recordRotationTransition(DeviceOrientation.portraitUp);
    telemetry.recordCycleTaskRequest();
    telemetry.recordCycleTaskRequest();
    telemetry.recordCycleTaskCompletion();

    expect(telemetry.rotationTransitions, 2);
    expect(telemetry.cycleTaskRequests, 2);
    expect(telemetry.cycleTaskCompletions, 1);
  });

  test('counts cycle task completion only after a successful await', () {
    final telemetry = ReproTelemetry();

    telemetry.recordCycleTaskRequest();

    expect(telemetry.cycleTaskRequests, 1);
    expect(telemetry.cycleTaskCompletions, 0);

    telemetry.recordCycleTaskCompletion();

    expect(telemetry.cycleTaskCompletions, 1);
  });

  test('includes counters in heartbeat and final result fields', () {
    final telemetry = ReproTelemetry();
    telemetry.recordRotationTransition(DeviceOrientation.landscapeLeft);
    telemetry.recordCycleTaskRequest();
    telemetry.recordCycleTaskCompletion();

    expect(
      telemetry.heartbeat(
        scenario: 5,
        iteration: 10,
        imageCount: 20,
      ),
      'scenario=5 iteration=10 images=20 '
      'rotationTransitions=1 cycleTaskRequests=1 '
      'cycleTaskCompletions=1',
    );
    expect(
      telemetry.resultFields,
      {
        'rotationTransitions': 1,
        'cycleTaskRequests': 1,
        'cycleTaskCompletions': 1,
      },
    );
  });
}
