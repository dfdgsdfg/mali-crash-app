import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mali_crash_app/main.dart';

void main() {
  test('rotation checkpoints alternate landscapeLeft and portraitUp', () {
    expect(
      [
        rotationOrientationForIteration(4),
        rotationOrientationForIteration(8),
        rotationOrientationForIteration(12),
        rotationOrientationForIteration(16),
      ],
      [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.portraitUp,
      ],
    );
  });
}
