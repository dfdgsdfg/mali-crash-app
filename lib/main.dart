import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('dev.flutter.repro/mali_crash');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaliCrashApp(launchConfig: await LaunchConfig.load()));
}

class LaunchConfig {
  const LaunchConfig({required this.isTestLoop, required this.scenario});

  final bool isTestLoop;
  final int scenario;

  static Future<LaunchConfig> load() async {
    try {
      final value = await _channel.invokeMapMethod<String, Object?>(
        'getLaunchConfig',
      );
      return LaunchConfig(
        isTestLoop: value?['isTestLoop'] == true,
        scenario: value?['scenario'] as int? ?? 0,
      );
    } on PlatformException {
      return const LaunchConfig(isTestLoop: false, scenario: 0);
    }
  }
}

class ReproScenario {
  const ReproScenario({
    required this.number,
    required this.label,
    required this.darkMode,
    required this.batchSize,
    this.analysisConcurrency = 0,
    this.rotateSurface = false,
    this.cycleTask = false,
    this.analyzesPixels = true,
    this.performsDiskResizeProbe = false,
  });

  final int number;
  final String label;
  final bool darkMode;
  final int batchSize;
  final int analysisConcurrency;
  final bool rotateSurface;
  final bool cycleTask;
  final bool analyzesPixels;
  final bool performsDiskResizeProbe;
}

const scenarios = <ReproScenario>[
  ReproScenario(
    number: 1,
    label: 'Light: decode + resize',
    darkMode: false,
    batchSize: 12,
  ),
  ReproScenario(
    number: 2,
    label: 'Dark: decode + ColorFilter',
    darkMode: true,
    batchSize: 12,
  ),
  ReproScenario(
    number: 3,
    label: 'Dark: app-like GPU analysis',
    darkMode: true,
    batchSize: 12,
    analysisConcurrency: 4,
  ),
  ReproScenario(
    number: 4,
    label: 'Dark analysis + surface rotation',
    darkMode: true,
    batchSize: 16,
    analysisConcurrency: 4,
    rotateSurface: true,
  ),
  ReproScenario(
    number: 5,
    label: 'Maximum: analysis + lifecycle churn',
    darkMode: true,
    batchSize: 20,
    analysisConcurrency: 8,
    rotateSurface: true,
    cycleTask: true,
  ),
  ReproScenario(
    number: 6,
    label: 'Dark: external lifecycle workload',
    darkMode: true,
    batchSize: 20,
    analysisConcurrency: 8,
  ),
  ReproScenario(
    number: 7,
    label: 'Dark: external lifecycle decode-only control',
    darkMode: true,
    batchSize: 20,
    analysisConcurrency: 8,
    rotateSurface: false,
    cycleTask: false,
    analyzesPixels: false,
  ),
  ReproScenario(
    number: 8,
    label: 'Production-like lazy feed decode/display',
    darkMode: false,
    batchSize: productionFeedPageSize,
    analysisConcurrency: 10,
    rotateSurface: false,
    cycleTask: false,
    analyzesPixels: false,
  ),
  ReproScenario(
    number: 9,
    label: 'Production-like feed with disk resize probe',
    darkMode: false,
    batchSize: productionFeedPageSize,
    analysisConcurrency: 10,
    rotateSurface: false,
    cycleTask: false,
    analyzesPixels: false,
    performsDiskResizeProbe: true,
  ),
];

const productionFeedItemCount = 120;
const productionFeedPageSize = 30;
const productionFeedSourceWidth = 1280;
const productionFeedSourceHeight = 720;
const productionFeedCacheMaximumBytes = 48 * 1024 * 1024;
const productionFeedPortraitCacheWidth = 600;
const productionFeedLandscapeCacheWidth = 1024;
const productionFeedScrollTick = Duration(milliseconds: 250);
const productionFeedScrollDelta = 200.0;

int productionFeedCacheWidthForOrientation(Orientation orientation) {
  return orientation == Orientation.landscape
      ? productionFeedLandscapeCacheWidth
      : productionFeedPortraitCacheWidth;
}

class ProductionFeedItem {
  const ProductionFeedItem({required this.index, required this.cacheWidth});

  final int index;
  final int cacheWidth;

  String get providerKey => 'production-feed-$index-width-$cacheWidth';
}

List<ProductionFeedItem> productionFeedItems({required int cacheWidth}) {
  return List<ProductionFeedItem>.generate(
    productionFeedItemCount,
    (index) => ProductionFeedItem(index: index, cacheWidth: cacheWidth),
    growable: false,
  );
}

ReproScenario scenarioForNumber(int number) {
  return scenarios.where((scenario) => scenario.number == number).firstOrNull ??
      scenarios[2];
}

Duration testLoopDurationForScenario(int scenario) {
  return Duration(
    minutes:
        scenario == 5 ||
            scenario == 6 ||
            scenario == 7 ||
            scenario == 8 ||
            scenario == 9
        ? 10
        : 3,
  );
}

bool shouldDiscardProductionResize({
  required int decodedWidth,
  required int maxWidth,
}) {
  return decodedWidth <= maxWidth;
}

DeviceOrientation rotationOrientationForIteration(int iteration) {
  return (iteration ~/ 4).isOdd
      ? DeviceOrientation.landscapeLeft
      : DeviceOrientation.portraitUp;
}

bool shouldCycleTaskForIteration({
  required int iteration,
  required bool cycleTask,
  required bool rotateSurface,
}) {
  if (!cycleTask || iteration % 6 != 0) return false;
  return !rotateSurface || iteration % 4 != 0;
}

class ReproTelemetry {
  DeviceOrientation? _lastRotation;
  int _rotationTransitions = 0;
  int _cycleTaskRequests = 0;
  int _cycleTaskCompletions = 0;
  int _feedScrollCycles = 0;
  int _feedPageAdmissions = 0;
  int _feedProviderVariants = 0;
  int _feedResizeProbeRequests = 0;
  int _feedResizeProbeCompletions = 0;
  final Set<String> _feedDecodedKeys = <String>{};

  int get rotationTransitions => _rotationTransitions;
  int get cycleTaskRequests => _cycleTaskRequests;
  int get cycleTaskCompletions => _cycleTaskCompletions;
  int get feedScrollCycles => _feedScrollCycles;
  int get feedPageAdmissions => _feedPageAdmissions;
  int get feedProviderVariants => _feedProviderVariants;
  int get feedDecodedItems => _feedDecodedKeys.length;
  int get feedResizeProbeRequests => _feedResizeProbeRequests;
  int get feedResizeProbeCompletions => _feedResizeProbeCompletions;

  Map<String, Object?> get resultFields => {
    'rotationTransitions': rotationTransitions,
    'cycleTaskRequests': cycleTaskRequests,
    'cycleTaskCompletions': cycleTaskCompletions,
  };

  Map<String, Object?> get feedResultFields => {
    'feedScrollCycles': feedScrollCycles,
    'feedPageAdmissions': feedPageAdmissions,
    'feedProviderVariants': feedProviderVariants,
    'feedDecodedItems': feedDecodedItems,
    'feedResizeProbeRequests': feedResizeProbeRequests,
    'feedResizeProbeCompletions': feedResizeProbeCompletions,
    'feedCacheMaximumBytes': productionFeedCacheMaximumBytes,
  };

  void recordRotationTransition(DeviceOrientation orientation) {
    if (_lastRotation == orientation) return;
    _lastRotation = orientation;
    _rotationTransitions++;
  }

  void recordCycleTaskRequest() {
    _cycleTaskRequests++;
  }

  void recordCycleTaskCompletion() {
    _cycleTaskCompletions++;
  }

  void recordFeedScrollCycle() {
    _feedScrollCycles++;
  }

  void recordFeedPageAdmission() {
    _feedPageAdmissions++;
  }

  void recordFeedProviderVariant(int itemCount) {
    _feedProviderVariants += itemCount;
  }

  void recordFeedDecodedItem(String providerKey) {
    _feedDecodedKeys.add(providerKey);
  }

  void recordFeedResizeProbeRequest() {
    _feedResizeProbeRequests++;
  }

  void recordFeedResizeProbeCompletion() {
    _feedResizeProbeCompletions++;
  }

  String heartbeat({
    required int scenario,
    required int iteration,
    required int imageCount,
    Map<String, Object?>? feedFields,
  }) {
    final base =
        'scenario=$scenario iteration=$iteration images=$imageCount '
        'rotationTransitions=$rotationTransitions '
        'cycleTaskRequests=$cycleTaskRequests '
        'cycleTaskCompletions=$cycleTaskCompletions';
    if (feedFields == null) return base;
    return '$base ${feedFields.entries.map((entry) => '${entry.key}=${entry.value}').join(' ')}';
  }

  void reset() {
    _lastRotation = null;
    _rotationTransitions = 0;
    _cycleTaskRequests = 0;
    _cycleTaskCompletions = 0;
    _feedScrollCycles = 0;
    _feedPageAdmissions = 0;
    _feedProviderVariants = 0;
    _feedResizeProbeRequests = 0;
    _feedResizeProbeCompletions = 0;
    _feedDecodedKeys.clear();
  }
}

class ProductionFeedImageProvider
    extends ImageProvider<ProductionFeedImageProvider> {
  const ProductionFeedImageProvider({
    required this.bytes,
    required this.itemIndex,
    required this.cacheWidth,
    this.performsDiskResizeProbe = false,
    this.onResizeProbeRequest = _noop,
    this.onResizeProbeCompletion = _noop,
  });

  final Uint8List bytes;
  final int itemIndex;
  final int cacheWidth;
  final bool performsDiskResizeProbe;
  final VoidCallback onResizeProbeRequest;
  final VoidCallback onResizeProbeCompletion;

  String get providerKey => 'production-feed-$itemIndex-width-$cacheWidth';

  @override
  Future<ProductionFeedImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) {
    return SynchronousFuture<ProductionFeedImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    ProductionFeedImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _decode(key, decode),
      scale: 1.0,
      debugLabel: key.providerKey,
    );
  }

  Future<ui.Codec> _decode(
    ProductionFeedImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    if (key.performsDiskResizeProbe) {
      await _probeProductionResize(key);
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(key.bytes);
    return decode(
      buffer,
      getTargetSize: (width, height) => ui.TargetImageSize(
        width: key.cacheWidth,
        height: (height * key.cacheWidth / width).round(),
      ),
    );
  }

  Future<void> _probeProductionResize(ProductionFeedImageProvider key) async {
    key.onResizeProbeRequest();
    try {
      final codec = await ui.instantiateImageCodec(
        key.bytes,
        targetWidth: key.cacheWidth,
      );
      try {
        final image = (await codec.getNextFrame()).image;
        try {
          if (!shouldDiscardProductionResize(
            decodedWidth: image.width,
            maxWidth: key.cacheWidth,
          )) {
            await image.toByteData(format: ui.ImageByteFormat.png);
          }
        } finally {
          image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } finally {
      key.onResizeProbeCompletion();
    }
  }

  @override
  bool operator ==(Object other) {
    return other is ProductionFeedImageProvider &&
        other.itemIndex == itemIndex &&
        other.cacheWidth == cacheWidth &&
        other.performsDiskResizeProbe == performsDiskResizeProbe;
  }

  @override
  int get hashCode =>
      Object.hash(itemIndex, cacheWidth, performsDiskResizeProbe);
}

void _noop() {}

class ProductionFeed extends StatefulWidget {
  const ProductionFeed({
    super.key,
    required this.sourceBytes,
    required this.onScrollCycle,
    required this.onPageAdmission,
    required this.onProviderVariant,
    required this.onDecodedItem,
    this.performsDiskResizeProbe = false,
    this.onResizeProbeRequest = _noop,
    this.onResizeProbeCompletion = _noop,
  });

  final Uint8List sourceBytes;
  final VoidCallback onScrollCycle;
  final VoidCallback onPageAdmission;
  final void Function(int itemCount) onProviderVariant;
  final ValueChanged<String> onDecodedItem;
  final bool performsDiskResizeProbe;
  final VoidCallback onResizeProbeRequest;
  final VoidCallback onResizeProbeCompletion;

  @override
  State<ProductionFeed> createState() => _ProductionFeedState();
}

class _ProductionFeedState extends State<ProductionFeed> {
  final ScrollController _scrollController = ScrollController();
  final Set<int> _admittedPages = <int>{};
  final Set<String> _decodedItems = <String>{};
  Timer? _scrollTimer;
  int? _reportedCacheWidth;

  @override
  void initState() {
    super.initState();
    _scrollTimer = Timer.periodic(
      productionFeedScrollTick,
      (_) => _advanceScroll(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cacheWidth = productionFeedCacheWidthForOrientation(
      MediaQuery.orientationOf(context),
    );
    if (_reportedCacheWidth == cacheWidth) return;
    _reportedCacheWidth = cacheWidth;
    widget.onProviderVariant(productionFeedItemCount);
  }

  void _advanceScroll() {
    if (!_scrollController.hasClients) return;
    final nextOffset = _scrollController.offset + productionFeedScrollDelta;
    if (nextOffset >= _scrollController.position.maxScrollExtent) {
      _scrollController.jumpTo(0);
      widget.onScrollCycle();
      return;
    }
    unawaited(
      _scrollController.animateTo(
        nextOffset,
        duration: productionFeedScrollTick,
        curve: Curves.linear,
      ),
    );
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cacheWidth = productionFeedCacheWidthForOrientation(
      MediaQuery.orientationOf(context),
    );
    final items = productionFeedItems(cacheWidth: cacheWidth);
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemHeight = constraints.maxWidth * 9 / 16;
        return ListView.builder(
          controller: _scrollController,
          itemExtent: itemHeight + 8,
          itemCount: items.length,
          padding: const EdgeInsets.all(8),
          itemBuilder: (context, index) {
            final item = items[index];
            if (index % productionFeedPageSize == 0 &&
                _admittedPages.add(index ~/ productionFeedPageSize)) {
              widget.onPageAdmission();
            }
            final provider = ProductionFeedImageProvider(
              bytes: widget.sourceBytes,
              itemIndex: item.index,
              cacheWidth: item.cacheWidth,
              performsDiskResizeProbe: widget.performsDiskResizeProbe,
              onResizeProbeRequest: widget.onResizeProbeRequest,
              onResizeProbeCompletion: widget.onResizeProbeCompletion,
            );
            final child = Image(
              image: provider,
              width: constraints.maxWidth,
              height: itemHeight,
              fit: BoxFit.cover,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (frame != null && _decodedItems.add(item.providerKey)) {
                  widget.onDecodedItem(item.providerKey);
                }
                return child;
              },
              errorBuilder: (context, error, stackTrace) =>
                  const ColoredBox(color: Colors.red),
            );
            return RepaintBoundary(
              key: ValueKey<String>(item.providerKey),
              child: child,
            );
          },
        );
      },
    );
  }
}

class MaliCrashApp extends StatelessWidget {
  const MaliCrashApp({super.key, required this.launchConfig});

  final LaunchConfig launchConfig;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mali GLES crash reproducer',
      theme: ThemeData(colorSchemeSeed: Colors.orange),
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: MaliDebugScreen(launchConfig: launchConfig),
    );
  }
}

class MaliDebugScreen extends StatefulWidget {
  const MaliDebugScreen({super.key, required this.launchConfig});

  final LaunchConfig launchConfig;

  @override
  State<MaliDebugScreen> createState() => _MaliDebugScreenState();
}

class _MaliDebugScreenState extends State<MaliDebugScreen> {
  static const _targetSizes = <int>[96, 128, 160, 192, 256, 320, 384, 512];
  late ReproScenario _scenario;
  Uint8List? _sourceBytes;
  List<ui.Image> _images = const [];
  Map<String, Object?> _deviceInfo = const {};
  bool _running = false;
  bool _stopRequested = false;
  int _iteration = 0;
  String _status = 'Preparing source image…';
  DateTime? _deadline;
  final _telemetry = ReproTelemetry();

  @override
  void initState() {
    super.initState();
    _scenario = scenarioForNumber(widget.launchConfig.scenario);
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    final results = await Future.wait<Object?>([
      _scenario.number >= 8 ? _generateFeedSourcePng() : _generateSourcePng(),
      _channel
          .invokeMapMethod<String, Object?>('getDeviceInfo')
          .catchError((_) => <String, Object?>{}),
    ]);
    if (!mounted) return;
    if (_scenario.number >= 8) {
      PaintingBinding.instance.imageCache.maximumSizeBytes =
          productionFeedCacheMaximumBytes;
      PaintingBinding.instance.imageCache.clear();
    }
    setState(() {
      _sourceBytes = results[0]! as Uint8List;
      _deviceInfo = (results[1] as Map<String, Object?>?) ?? const {};
      _status = widget.launchConfig.isTestLoop
          ? 'Test Lab scenario ${_scenario.number} ready'
          : 'Ready';
    });
    if (widget.launchConfig.isTestLoop) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_start()));
    }
  }

  Future<Uint8List> _generateSourcePng() async {
    const size = 1536;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final bounds = Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble());
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          colors: [Colors.white, Colors.orange, Colors.indigo, Colors.black],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(bounds),
    );
    for (var index = 0; index < 96; index++) {
      final x = ((index * 137) % size).toDouble();
      final y = ((index * 251) % size).toDouble();
      canvas.drawCircle(
        Offset(x, y),
        24 + (index % 9) * 9,
        Paint()
          ..color = Colors.primaries[index % Colors.primaries.length]
              .withValues(alpha: 0.7),
      );
    }
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(size, size);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) throw StateError('Could not encode source PNG');
        return bytes.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  Future<Uint8List> _generateFeedSourcePng() async {
    const width = productionFeedSourceWidth;
    const height = productionFeedSourceHeight;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final bounds = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          colors: [Colors.blue, Colors.orange, Colors.green, Colors.indigo],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(bounds),
    );
    for (var index = 0; index < 64; index++) {
      canvas.drawCircle(
        Offset(
          ((index * 173) % width).toDouble(),
          ((index * 97) % height).toDouble(),
        ),
        18 + (index % 7) * 8,
        Paint()
          ..color = Colors.primaries[index % Colors.primaries.length]
              .withValues(alpha: 0.65),
      );
    }
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(width, height);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) throw StateError('Could not encode feed source PNG');
        return bytes.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  Future<void> _start() async {
    if (_running || _sourceBytes == null) return;
    setState(() {
      _running = true;
      _stopRequested = false;
      _iteration = 0;
      _telemetry.reset();
      _deadline = widget.launchConfig.isTestLoop
          ? DateTime.now().add(testLoopDurationForScenario(_scenario.number))
          : null;
      _status = 'Running scenario ${_scenario.number}';
    });

    Object? failure;
    StackTrace? failureStack;
    try {
      while (!_stopRequested && mounted) {
        if (_deadline case final deadline?
            when DateTime.now().isAfter(deadline)) {
          break;
        }
        await _runIteration();
      }
    } catch (error, stackTrace) {
      failure = error;
      failureStack = stackTrace;
      _log('Dart failure: $error\n$stackTrace');
    } finally {
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      if (mounted) {
        setState(() {
          _running = false;
          _status = failure == null
              ? 'Stopped after $_iteration iterations'
              : 'Failed: $failure';
        });
      }
    }

    if (widget.launchConfig.isTestLoop) {
      await _finishTestLoop(failure, failureStack);
    }
  }

  Future<void> _runIteration() async {
    if (_scenario.number >= 8) {
      await _runFeedIteration();
      return;
    }
    final sourceBytes = _sourceBytes!;
    final decoded = await Future.wait(
      List.generate(_scenario.batchSize, (index) async {
        final size = _targetSizes[(index + _iteration) % _targetSizes.length];
        final codec = await ui.instantiateImageCodec(
          sourceBytes,
          targetWidth: size,
          targetHeight: size,
          allowUpscaling: false,
        );
        try {
          return (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      }),
    );

    if (_scenario.analyzesPixels) {
      await _analyzeInChunks(decoded, _scenario.analysisConcurrency);
    }
    if (!mounted) {
      for (final image in decoded) {
        image.dispose();
      }
      return;
    }

    final previous = _images;
    setState(() {
      _images = decoded;
      _iteration++;
      _status = 'Running scenario ${_scenario.number} · iteration $_iteration';
    });
    await WidgetsBinding.instance.endOfFrame;
    for (final image in previous) {
      image.dispose();
    }

    if (_scenario.rotateSurface && _iteration % 4 == 0) {
      final orientation = rotationOrientationForIteration(_iteration);
      await SystemChrome.setPreferredOrientations([orientation]);
      _telemetry.recordRotationTransition(orientation);
    }
    if (shouldCycleTaskForIteration(
      iteration: _iteration,
      cycleTask: _scenario.cycleTask,
      rotateSurface: _scenario.rotateSurface,
    )) {
      _telemetry.recordCycleTaskRequest();
      await _channel.invokeMethod<void>('cycleTask');
      _telemetry.recordCycleTaskCompletion();
    }
    if (_iteration % 10 == 0) {
      _log(
        _telemetry.heartbeat(
          scenario: _scenario.number,
          iteration: _iteration,
          imageCount: decoded.length,
        ),
      );
    }

    PaintingBinding.instance.imageCache.clear();
    await Future<void>.delayed(const Duration(milliseconds: 8));
  }

  Future<void> _runFeedIteration() async {
    if (!mounted) return;
    setState(() {
      _iteration++;
      _status = 'Running scenario ${_scenario.number} · iteration $_iteration';
    });
    await WidgetsBinding.instance.endOfFrame;
    if (_iteration % 10 == 0) {
      _log(
        _telemetry.heartbeat(
          scenario: _scenario.number,
          iteration: _iteration,
          imageCount: productionFeedItemCount,
          feedFields: _telemetry.feedResultFields,
        ),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 8));
  }

  Future<void> _analyzeInChunks(List<ui.Image> images, int concurrency) async {
    for (var offset = 0; offset < images.length; offset += concurrency) {
      final end = math.min(offset + concurrency, images.length);
      await Future.wait(images.sublist(offset, end).map(_analyzeImage));
    }
  }

  Future<void> _analyzeImage(ui.Image image) async {
    final targetWidth = math.max(1, math.min(32, image.width));
    final targetHeight = math.max(1, math.min(32, image.height));
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, targetWidth.toDouble(), targetHeight.toDouble()),
      Paint(),
    );
    final picture = recorder.endRecording();
    try {
      final scaled = await picture.toImage(targetWidth, targetHeight);
      try {
        final pixels = await scaled.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (pixels == null) throw StateError('GPU readback returned null');
        pixels.getUint8((_iteration * 17) % pixels.lengthInBytes);
      } finally {
        scaled.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  Future<void> _finishTestLoop(Object? failure, StackTrace? stackTrace) async {
    final result = <String, Object?>{
      'scenario': _scenario.number,
      'iterations': _iteration,
      'success': failure == null,
      ..._telemetry.resultFields,
      ..._telemetry.feedResultFields,
      if (failure != null) 'error': '$failure',
      if (stackTrace != null) 'stackTrace': '$stackTrace',
    };
    try {
      await _channel.invokeMethod<void>('finishTestLoop', result);
    } on PlatformException catch (error) {
      _log('Could not finish Test Loop: $error');
    }
  }

  void _log(String message) {
    developer.log(message, name: 'MaliRepro');
    unawaited(_channel.invokeMethod<void>('log', message).catchError((_) {}));
  }

  @override
  void dispose() {
    _stopRequested = true;
    for (final image in _images) {
      image.dispose();
    }
    unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = _scenario.darkMode
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData(colorSchemeSeed: Colors.orange);
    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(title: const Text('Mali GLES crash reproducer')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<ReproScenario>(
                    initialValue: _scenario,
                    decoration: const InputDecoration(labelText: 'Scenario'),
                    items: [
                      for (final scenario in scenarios)
                        DropdownMenuItem(
                          value: scenario,
                          child: Text('${scenario.number}. ${scenario.label}'),
                        ),
                    ],
                    onChanged: _running
                        ? null
                        : (scenario) {
                            if (scenario != null) {
                              setState(() => _scenario = scenario);
                            }
                          },
                  ),
                  const SizedBox(height: 8),
                  Text(_status),
                  Text(
                    'renderer shaderFilter=${ui.ImageFilter.isShaderFilterSupported} · '
                    '${_deviceInfo.entries.map((entry) => '${entry.key}=${entry.value}').join(' · ')}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _sourceBytes == null
                        ? null
                        : _running
                        ? () => setState(() => _stopRequested = true)
                        : _start,
                    icon: Icon(_running ? Icons.stop : Icons.play_arrow),
                    label: Text(_running ? 'Stop' : 'Start'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _scenario.number >= 8
                  ? ProductionFeed(
                      sourceBytes: _sourceBytes ?? Uint8List(0),
                      onScrollCycle: _telemetry.recordFeedScrollCycle,
                      onPageAdmission: _telemetry.recordFeedPageAdmission,
                      onProviderVariant: _telemetry.recordFeedProviderVariant,
                      onDecodedItem: _telemetry.recordFeedDecodedItem,
                      performsDiskResizeProbe:
                          _scenario.performsDiskResizeProbe,
                      onResizeProbeRequest:
                          _telemetry.recordFeedResizeProbeRequest,
                      onResizeProbeCompletion:
                          _telemetry.recordFeedResizeProbeCompletion,
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(8),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisSpacing: 4,
                            crossAxisSpacing: 4,
                          ),
                      itemCount: _images.length,
                      itemBuilder: (context, index) {
                        final child = RawImage(
                          image: _images[index],
                          fit: BoxFit.cover,
                        );
                        if (!_scenario.darkMode) return child;
                        return ColorFiltered(
                          colorFilter: ColorFilter.mode(
                            Colors.black.withValues(alpha: 0.08),
                            BlendMode.darken,
                          ),
                          child: child,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
