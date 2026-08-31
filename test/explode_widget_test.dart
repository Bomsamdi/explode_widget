import 'dart:math';
import 'dart:ui' as ui;

import 'package:explode_widget/explode_widget.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const Color kChildColour = Color(0xFF4F46E5);

void main() {
  Widget host(
    Widget child, {
    ExplodeSettings settings = const ExplodeSettings(seed: 1),
    ExplodeController? controller,
    bool explodeOnTap = true,
    VoidCallback? onCompleted,
    Key? boundaryKey,
    Key? explodeKey,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: RepaintBoundary(
          key: boundaryKey,
          child: ExplodeWidget(
            key: explodeKey,
            settings: settings,
            controller: controller,
            explodeOnTap: explodeOnTap,
            onCompleted: onCompleted,
            child: child,
          ),
        ),
      ),
    ),
  );

  Widget block([Color colour = kChildColour]) =>
      SizedBox(width: 100, height: 100, child: ColoredBox(color: colour));

  RenderExplode renderOf(WidgetTester tester) =>
      tester.renderObject<RenderExplode>(find.byType(ExplodeWidget));

  group('the generated seed', () {
    test('stays inside what Random.nextInt accepts after compiling to JS', () {
      // `1 << 32` is 0 in JavaScript, and nextInt(0) throws RangeError - a
      // defect that only appears in a browser, so the bound is pinned here.
      expect(RenderExplode.debugSeedBound, greaterThan(0));
      expect(RenderExplode.debugSeedBound, lessThanOrEqualTo(0x7FFFFFFF));
      expect(
        () => Random().nextInt(RenderExplode.debugSeedBound),
        returnsNormally,
      );
    });
  });

  group('phases', () {
    testWidgets('a tap shatters the child and the fragments then go', (
      WidgetTester tester,
    ) async {
      int completed = 0;
      await tester.pumpWidget(host(block(), onCompleted: () => completed++));
      final RenderExplode render = renderOf(tester);

      expect(render.phase, ExplodePhase.idle);

      await tester.tap(find.byType(ExplodeWidget));
      await tester.pump();
      expect(render.phase, ExplodePhase.exploding);
      expect(completed, 0);

      await tester.pump(const Duration(milliseconds: 500));
      expect(render.phase, ExplodePhase.exploding);

      await tester.pump(const Duration(seconds: 1));
      expect(render.phase, ExplodePhase.gone);
      expect(completed, 1);

      // And it stays gone rather than reporting again on later frames.
      await tester.pump(const Duration(seconds: 1));
      expect(completed, 1);
    });

    testWidgets('a second tap while exploding is ignored', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(host(block()));
      final RenderExplode render = renderOf(tester);

      await tester.tap(find.byType(ExplodeWidget));
      await tester.pump(const Duration(milliseconds: 100));
      // Once exploding, the widget stops taking hits at all.
      expect(render.hitTestSelf(const Offset(50, 50)), isFalse);
    });

    testWidgets('explodeOnTap: false leaves taps alone', (
      WidgetTester tester,
    ) async {
      final ExplodeController controller = ExplodeController();
      await tester.pumpWidget(
        host(block(), controller: controller, explodeOnTap: false),
      );
      final RenderExplode render = renderOf(tester);

      await tester.tap(find.byType(ExplodeWidget), warnIfMissed: false);
      await tester.pump();
      expect(render.phase, ExplodePhase.idle);

      controller.explode();
      await tester.pump();
      expect(render.phase, ExplodePhase.exploding);
    });
  });

  group('the child survives', () {
    testWidgets('reset brings it back with its state intact', (
      WidgetTester tester,
    ) async {
      final ExplodeController controller = ExplodeController();
      await tester.pumpWidget(
        host(const _Counter(), controller: controller, explodeOnTap: false),
      );

      await tester.tap(find.text('tap: 0'));
      await tester.pump();
      expect(find.text('tap: 1'), findsOneWidget);

      controller.explode();
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.phase, ExplodePhase.exploding);

      controller.reset();
      await tester.pump();

      // Never rebuilt, never disposed: the count is still there.
      expect(controller.phase, ExplodePhase.idle);
      expect(find.text('tap: 1'), findsOneWidget);
    });

    testWidgets('it is still findable while it is exploding', (
      WidgetTester tester,
    ) async {
      final ExplodeController controller = ExplodeController();
      await tester.pumpWidget(
        host(const _Counter(), controller: controller, explodeOnTap: false),
      );

      controller.explode();
      await tester.pump(const Duration(milliseconds: 200));

      // Hidden, not removed - so semantics and state are where they were.
      expect(find.text('tap: 0'), findsOneWidget);
    });
  });

  group('the fragments are made of the child', () {
    testWidgets('they carry its colour, and nothing is left at the end', (
      WidgetTester tester,
    ) async {
      const Key boundary = Key('boundary');
      final ExplodeController controller = ExplodeController();
      await tester.pumpWidget(
        host(
          block(),
          boundaryKey: boundary,
          controller: controller,
          explodeOnTap: false,
          // No stagger and slow, so the fragments are still on screen when we
          // look at the pixels.
          settings: const ExplodeSettings(
            seed: 1,
            stagger: 0,
            // Fast enough that a good share of the fragments has left the
            // boundary after 100 ms, which is what tells a real explosion
            // apart from a child that simply kept being painted.
            minSpeed: 200,
            maxSpeed: 400,
            gravity: 0,
            spin: 0,
            shrink: 0,
            duration: Duration(seconds: 1),
            grid: ExplodeGrid(columns: 10, rows: 10),
          ),
        ),
      );

      final int before = await _countChildColour(tester, boundary);
      expect(before, greaterThan(0), reason: 'the child should be visible');

      controller.explode();
      // The first frame only starts the ticker - its elapsed time is zero, so
      // the fragments still sit exactly where the child was.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final int during = await _countChildColour(tester, boundary);
      expect(
        during,
        greaterThan(0),
        reason: 'fragments must be pieces of the child, not coloured dots',
      );
      expect(
        during,
        lessThan((before * 0.9).round()),
        reason: 'the fragments must have scattered, not sat where they were',
      );

      await tester.pump(const Duration(seconds: 2));
      expect(controller.phase, ExplodePhase.gone);
      expect(await _countChildColour(tester, boundary), 0);
    });
  });

  testWidgets('shrink makes the fragments smaller as they fly', (
    WidgetTester tester,
  ) async {
    const Key boundary = Key('boundary');

    Future<int> midFlight({required double shrink}) async {
      // A different key each time, so the element - and with it the render
      // object and its animation - is built from scratch. Without it the
      // second run inherits the first run's finished animation and measures a
      // scale of zero whatever shrink says.
      final ExplodeController controller = ExplodeController();
      await tester.pumpWidget(
        host(
          block(),
          boundaryKey: boundary,
          explodeKey: ValueKey<double>(shrink),
          controller: controller,
          explodeOnTap: false,
          settings: ExplodeSettings(
            seed: 3,
            stagger: 0,
            minSpeed: 0,
            maxSpeed: 0,
            gravity: 0,
            spin: 0,
            shrink: shrink,
            fade: Curves.linear,
            duration: const Duration(seconds: 1),
            grid: const ExplodeGrid(columns: 10, rows: 10),
          ),
        ),
      );

      controller.explode();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      return _countChildColour(tester, boundary);
    }

    // Speeds are zero, so the only thing that can change the painted area
    // is the shrink itself.
    final int whole = await midFlight(shrink: 0);
    final int shrunk = await midFlight(shrink: 1);

    expect(whole, greaterThan(0));
    expect(shrunk, lessThan((whole * 0.6).round()));
  });

  testWidgets('fade takes the fragments down as they age', (
    WidgetTester tester,
  ) async {
    const Key boundary = Key('boundary');
    final ExplodeController controller = ExplodeController();
    await tester.pumpWidget(
      host(
        block(),
        boundaryKey: boundary,
        controller: controller,
        explodeOnTap: false,
        settings: const ExplodeSettings(
          seed: 4,
          stagger: 0,
          minSpeed: 0,
          maxSpeed: 0,
          gravity: 0,
          spin: 0,
          shrink: 0,
          fade: Curves.linear,
          duration: Duration(seconds: 1),
          grid: ExplodeGrid(columns: 4, rows: 4),
        ),
      ),
    );

    expect(await _maxAlpha(tester, boundary), 255);

    controller.explode();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Linear fade, half way through: half transparent, not still solid.
    expect(await _maxAlpha(tester, boundary), closeTo(127, 4));
  });

  group('layout', () {
    testWidgets('the widget keeps its space by default', (
      WidgetTester tester,
    ) async {
      final ExplodeController controller = ExplodeController();
      await tester.pumpWidget(
        host(block(), controller: controller, explodeOnTap: false),
      );

      controller.explode();
      await tester.pumpAndSettle();

      expect(controller.phase, ExplodePhase.gone);
      expect(tester.getSize(find.byType(ExplodeWidget)), const Size(100, 100));
    });

    testWidgets('collapseWhenGone gives the space back', (
      WidgetTester tester,
    ) async {
      final ExplodeController controller = ExplodeController();
      await tester.pumpWidget(
        host(
          block(),
          controller: controller,
          explodeOnTap: false,
          settings: const ExplodeSettings(seed: 1, collapseWhenGone: true),
        ),
      );

      controller.explode();
      await tester.pumpAndSettle();

      expect(controller.phase, ExplodePhase.gone);
      expect(tester.getSize(find.byType(ExplodeWidget)), Size.zero);
    });
  });

  group('the controller', () {
    test('reports nothing before it is attached', () {
      final ExplodeController controller = ExplodeController();

      expect(controller.phase, isNull);
      expect(controller.isExploded, isFalse);
    });

    test('explode() before the widget exists says so', () {
      expect(
        () => ExplodeController().explode(),
        throwsA(
          isA<AssertionError>().having(
            (AssertionError e) => e.message.toString(),
            'message',
            contains('before the ExplodeWidget was built'),
          ),
        ),
      );
    });

    testWidgets('the newest widget wins when a controller is shared', (
      WidgetTester tester,
    ) async {
      // Documented, not asserted: a widget that changes key is rebuilt before
      // the old one is unmounted, so a shared controller cannot be told apart
      // from a re-keyed one. The newest attachment is the live one.
      final ExplodeController controller = ExplodeController();

      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ExplodeWidget(controller: controller, child: block()),
              ExplodeWidget(controller: controller, child: block()),
            ],
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      controller.explode();
      await tester.pumpAndSettle();

      final Iterable<RenderExplode> renders = tester
          .widgetList<ExplodeWidget>(find.byType(ExplodeWidget))
          .map(
            (ExplodeWidget w) =>
                tester.renderObject<RenderExplode>(find.byWidget(w)),
          );

      // Exactly one of the two exploded.
      expect(
        renders.where((RenderExplode r) => r.phase == ExplodePhase.gone),
        hasLength(1),
      );
    });

    testWidgets('it detaches when the widget goes away', (
      WidgetTester tester,
    ) async {
      final ExplodeController controller = ExplodeController();
      await tester.pumpWidget(host(block(), controller: controller));
      expect(controller.phase, ExplodePhase.idle);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(controller.phase, isNull);
    });
  });

  group('teardown', () {
    testWidgets('an exploding widget can be removed mid-flight', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(host(block()));

      await tester.tap(find.byType(ExplodeWidget));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
    });

    testWidgets('changing the settings mid-flight does not break it', (
      WidgetTester tester,
    ) async {
      final ExplodeController controller = ExplodeController();
      await tester.pumpWidget(
        host(block(), controller: controller, explodeOnTap: false),
      );

      controller.explode();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.pumpWidget(
        host(
          block(),
          controller: controller,
          explodeOnTap: false,
          settings: const ExplodeSettings(seed: 1, gravity: 0, spin: 0),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      expect(tester.takeException(), isNull);
      expect(controller.phase, ExplodePhase.gone);
    });
  });
}

/// Counts pixels close to the child's colour inside [boundary].
Future<int> _countChildColour(WidgetTester tester, Key boundary) async {
  final RenderRepaintBoundary render = tester
      .renderObject<RenderRepaintBoundary>(find.byKey(boundary));

  int count = 0;
  await tester.runAsync(() async {
    final ui.Image image = render.toImageSync();
    final ByteData? bytes = await image.toByteData();
    image.dispose();
    if (bytes == null) return;

    final Uint8List pixels = bytes.buffer.asUint8List();
    for (int i = 0; i < pixels.length; i += 4) {
      final int a = pixels[i + 3];
      if (a < 40) continue;
      // Premultiplied, so compare the child's colour scaled by the alpha.
      final double f = a / 255;
      final bool matches =
          (pixels[i] - 0x4F * f).abs() < 24 &&
          (pixels[i + 1] - 0x46 * f).abs() < 24 &&
          (pixels[i + 2] - 0xE5 * f).abs() < 24;
      if (matches) count++;
    }
  });
  return count;
}

/// The most opaque pixel inside [boundary].
Future<int> _maxAlpha(WidgetTester tester, Key boundary) async {
  final RenderRepaintBoundary render = tester
      .renderObject<RenderRepaintBoundary>(find.byKey(boundary));

  int highest = 0;
  await tester.runAsync(() async {
    final ui.Image image = render.toImageSync();
    final ByteData? bytes = await image.toByteData();
    image.dispose();
    if (bytes == null) return;

    final Uint8List pixels = bytes.buffer.asUint8List();
    for (int i = 3; i < pixels.length; i += 4) {
      if (pixels[i] > highest) highest = pixels[i];
    }
  });
  return highest;
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _taps = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => setState(() => _taps++),
    child: Container(
      width: 120,
      height: 60,
      color: kChildColour,
      alignment: Alignment.center,
      child: Text('tap: $_taps', textDirection: TextDirection.ltr),
    ),
  );
}
