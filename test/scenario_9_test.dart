import 'package:flutter_test/flutter_test.dart';

import 'package:mali_crash_app/main.dart';

void main() {
  test('scenario 9 mirrors the production cache-miss double-decode path', () {
    final scenario = scenarioForNumber(9);

    expect(scenario.number, 9);
    expect(scenario.batchSize, productionFeedPageSize);
    expect(scenario.performsDiskResizeProbe, isTrue);
    expect(scenario.analyzesPixels, isFalse);
    expect(scenario.rotateSurface, isFalse);
    expect(scenario.cycleTask, isFalse);
  });

  test('scenario 9 has a ten-minute Test Loop deadline', () {
    expect(testLoopDurationForScenario(9), const Duration(minutes: 10));
  });

  test('production resize probe discards a target-width decoded image', () {
    expect(
      shouldDiscardProductionResize(
        decodedWidth: productionFeedPortraitCacheWidth,
        maxWidth: productionFeedPortraitCacheWidth,
      ),
      isTrue,
    );
    expect(
      shouldDiscardProductionResize(
        decodedWidth: productionFeedPortraitCacheWidth + 1,
        maxWidth: productionFeedPortraitCacheWidth,
      ),
      isFalse,
    );
  });
}
