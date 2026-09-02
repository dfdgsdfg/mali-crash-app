import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mali_crash_app/main.dart';

void main() {
  test('scenario 8 is a production-like external feed workload', () {
    final scenario = scenarioForNumber(8);

    expect(scenario.number, 8);
    expect(scenario.darkMode, isFalse);
    expect(scenario.batchSize, 30);
    expect(scenario.analysisConcurrency, 10);
    expect(scenario.analyzesPixels, isFalse);
    expect(scenario.rotateSurface, isFalse);
    expect(scenario.cycleTask, isFalse);
  });

  test('scenario 8 has a ten-minute Test Loop deadline', () {
    expect(testLoopDurationForScenario(8), const Duration(minutes: 10));
  });

  test('feed admits 30-item pages and uses distinct orientation variants', () {
    final portrait = productionFeedItems(
      cacheWidth: productionFeedPortraitCacheWidth,
    );
    final landscape = productionFeedItems(
      cacheWidth: productionFeedLandscapeCacheWidth,
    );

    expect(portrait, hasLength(productionFeedItemCount));
    expect(portrait.map((item) => item.providerKey).toSet(), hasLength(120));
    expect(landscape.map((item) => item.providerKey).toSet(), hasLength(120));
    expect(
      portrait
          .map((item) => item.providerKey)
          .toSet()
          .intersection(landscape.map((item) => item.providerKey).toSet()),
      isEmpty,
    );
    expect(productionFeedPageSize, 30);
    expect(productionFeedSourceWidth, greaterThanOrEqualTo(1280));
    expect(productionFeedSourceHeight, greaterThanOrEqualTo(720));
    expect(
      productionFeedSourceHeight / productionFeedSourceWidth,
      closeTo(9 / 16, 0.0001),
    );
    expect(
      productionFeedScrollDelta /
          productionFeedScrollTick.inMilliseconds *
          Duration.millisecondsPerSecond,
      inInclusiveRange(700, 1000),
    );
    expect(productionFeedCacheMaximumBytes, 48 * 1024 * 1024);
    expect(
      productionFeedCacheWidthForOrientation(Orientation.portrait),
      productionFeedPortraitCacheWidth,
    );
    expect(
      productionFeedCacheWidthForOrientation(Orientation.landscape),
      productionFeedLandscapeCacheWidth,
    );
  });

  testWidgets('feed uses fixed item keys and no dark filter', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 600,
          child: ProductionFeed(
            sourceBytes: Uint8List(0),
            onScrollCycle: () {},
            onPageAdmission: () {},
            onProviderVariant: (_) {},
            onDecodedItem: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const ValueKey<String>('production-feed-0-width-1024')),
      findsOneWidget,
    );
    expect(find.byType(ColorFiltered), findsNothing);
  });
}
