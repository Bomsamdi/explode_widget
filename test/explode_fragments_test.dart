import 'dart:ui' as ui;

import 'package:explode_widget/explode_widget.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ExplodeFragmentBuilder builder = ExplodeFragmentBuilder();

  List<ExplodeFragment> build({
    ui.Size size = const ui.Size(200, 100),
    ExplodeSettings settings = const ExplodeSettings(),
    double pixelRatio = 2,
    int seed = 7,
    ui.Offset? tap,
  }) => builder.build(
    size: size,
    pixelRatio: pixelRatio,
    settings: settings,
    seed: seed,
    tap: tap,
  );

  group('the grid', () {
    test('an explicit grid gives exactly that many fragments', () {
      expect(
        build(
          settings: const ExplodeSettings(
            grid: ExplodeGrid(columns: 8, rows: 5),
          ),
        ),
        hasLength(40),
      );
    });

    test('auto follows the aspect ratio, so fragments stay square-ish', () {
      // 300x100 is three times as wide as it is tall, so the grid should be
      // too - 30x10, not 17x17.
      expect(const ExplodeGrid.auto(300).resolve(const ui.Size(300, 100)), (
        30,
        10,
      ));
      expect(const ExplodeGrid.auto(400).resolve(const ui.Size(100, 100)), (
        20,
        20,
      ));
    });

    test('auto never asks for zero columns on an extreme ratio', () {
      final (int c, int r) = const ExplodeGrid.auto(
        4,
      ).resolve(const ui.Size(1000, 2));
      expect(c, greaterThan(0));
      expect(r, greaterThan(0));
    });

    test('an empty widget has nothing to shatter', () {
      expect(build(size: ui.Size.zero), isEmpty);
    });
  });

  group('the source rectangles', () {
    test('tile the snapshot exactly, with no gap and no overlap', () {
      const ui.Size size = ui.Size(200, 100);
      const double pixelRatio = 2;
      final List<ExplodeFragment> fragments = build(
        size: size,
        pixelRatio: pixelRatio,
        settings: const ExplodeSettings(grid: ExplodeGrid(columns: 4, rows: 2)),
      );

      // Together they cover the whole image.
      final double area = fragments.fold<double>(
        0,
        (double sum, ExplodeFragment f) =>
            sum + f.source.width * f.source.height,
      );
      expect(
        area,
        closeTo(size.width * pixelRatio * size.height * pixelRatio, 0.001),
      );

      // And none of them reaches outside it.
      for (final ExplodeFragment f in fragments) {
        expect(f.source.left, greaterThanOrEqualTo(0));
        expect(f.source.top, greaterThanOrEqualTo(0));
        expect(f.source.right, lessThanOrEqualTo(size.width * pixelRatio));
        expect(f.source.bottom, lessThanOrEqualTo(size.height * pixelRatio));
      }

      // Row 0 column 1 sits exactly one cell to the right of column 0.
      expect(fragments[1].source.left, closeTo(100, 0.001));
      expect(fragments[1].source.top, 0);
    });

    test('scale with the pixel ratio, because the snapshot does', () {
      final ExplodeFragment atOne = build(
        pixelRatio: 1,
        settings: const ExplodeSettings(grid: ExplodeGrid(columns: 2, rows: 2)),
      ).first;
      final ExplodeFragment atThree = build(
        pixelRatio: 3,
        settings: const ExplodeSettings(grid: ExplodeGrid(columns: 2, rows: 2)),
      ).first;

      expect(atThree.source.width, closeTo(atOne.source.width * 3, 0.001));
    });
  });

  group('the throw', () {
    test('fragments fly away from the blast, not towards it', () {
      final List<ExplodeFragment> fragments = build(
        settings: const ExplodeSettings(
          grid: ExplodeGrid(columns: 6, rows: 6),
          origin: ExplodeOrigin.at(Alignment.center),
          spin: 0,
          stagger: 0,
        ),
      );
      const ui.Offset centre = ui.Offset(100, 50);

      // Jitter can angle a fragment, but not turn it round: the dot product of
      // "where it is" and "where it is going" must stay positive.
      for (final ExplodeFragment f in fragments) {
        final ui.Offset away = f.origin - centre;
        if (away.distance < 1) continue;
        final double dot = away.dx * f.velocity.dx + away.dy * f.velocity.dy;
        expect(dot, greaterThan(0), reason: 'fragment at ${f.origin} flew in');
      }
    });

    test('a tap decides where the blast comes from', () {
      final ExplodeFragment topLeft = build(
        settings: const ExplodeSettings(
          grid: ExplodeGrid(columns: 2, rows: 1),
          origin: ExplodeOrigin.tap(),
          stagger: 0,
        ),
        tap: const ui.Offset(200, 50),
      ).first;

      // Tapped on the right edge, so the left fragment is thrown left.
      expect(topLeft.velocity.dx, lessThan(0));
    });

    test('an alignment origin ignores the tap', () {
      final ExplodeFragment left = build(
        settings: const ExplodeSettings(
          grid: ExplodeGrid(columns: 2, rows: 1),
          origin: ExplodeOrigin.at(Alignment.centerLeft),
          stagger: 0,
        ),
        tap: const ui.Offset(200, 50),
      ).first;

      expect(left.velocity.dx, greaterThan(0));
    });

    test('speed stays inside the range it was given', () {
      final List<ExplodeFragment> fragments = build(
        settings: const ExplodeSettings(
          grid: ExplodeGrid(columns: 10, rows: 10),
          minSpeed: 100,
          maxSpeed: 200,
        ),
      );

      for (final ExplodeFragment f in fragments) {
        expect(f.velocity.distance, inInclusiveRange(99.9, 200.1));
      }
    });

    test('spin of zero keeps every fragment upright', () {
      final List<ExplodeFragment> fragments = build(
        settings: const ExplodeSettings(
          grid: ExplodeGrid(columns: 4, rows: 4),
          spin: 0,
        ),
      );

      for (final ExplodeFragment f in fragments) {
        expect(f.rotationAt(1), 0);
      }
    });
  });

  group('the motion', () {
    test('is a closed form, so a dropped frame changes nothing', () {
      final ExplodeFragment f = ExplodeFragment(
        source: const ui.Rect.fromLTWH(0, 0, 10, 10),
        origin: const ui.Offset(50, 20),
        velocity: const ui.Offset(30, -60),
        spin: 2,
        delay: 0,
      );

      // x = x0 + vx t ; y = y0 + vy t + g t^2 / 2
      expect(f.positionAt(0.5, 1000).dx, closeTo(50 + 15, 0.0001));
      expect(f.positionAt(0.5, 1000).dy, closeTo(20 - 30 + 125, 0.0001));
      expect(f.rotationAt(0.5), closeTo(1, 0.0001));
    });

    test('a delayed fragment has not moved yet, nor started fading', () {
      final ExplodeFragment f = ExplodeFragment(
        source: const ui.Rect.fromLTWH(0, 0, 10, 10),
        origin: const ui.Offset(50, 20),
        velocity: const ui.Offset(100, 100),
        spin: 5,
        delay: 0.3,
      );

      expect(f.positionAt(0.2, 1000), const ui.Offset(50, 20));
      expect(f.rotationAt(0.2), 0);
      expect(f.progressAt(0.2, 1), 0);
      // And once its turn comes, time is measured from then.
      expect(f.positionAt(0.4, 0).dx, closeTo(60, 0.0001));
    });

    test('progress is clamped, so a late frame does not overshoot', () {
      final ExplodeFragment f = ExplodeFragment(
        source: ui.Rect.zero,
        origin: ui.Offset.zero,
        velocity: ui.Offset.zero,
        spin: 0,
        delay: 0,
      );

      expect(f.progressAt(99, 1), 1);
      expect(f.progressAt(-1, 1), 0);
    });
  });

  group('the stagger', () {
    test('the near fragment leaves first and the far one last', () {
      final List<ExplodeFragment> fragments = build(
        size: const ui.Size(200, 100),
        settings: const ExplodeSettings(
          grid: ExplodeGrid(columns: 20, rows: 10),
          origin: ExplodeOrigin.at(Alignment.topLeft),
          duration: Duration(seconds: 1),
          stagger: 0.5,
        ),
      );

      final ExplodeFragment nearest = fragments.reduce(
        (ExplodeFragment a, ExplodeFragment b) =>
            a.origin.distance < b.origin.distance ? a : b,
      );
      final ExplodeFragment farthest = fragments.reduce(
        (ExplodeFragment a, ExplodeFragment b) =>
            a.origin.distance > b.origin.distance ? a : b,
      );

      expect(nearest.delay, lessThan(farthest.delay));
      // Nobody waits longer than the fraction of the duration allowed.
      for (final ExplodeFragment f in fragments) {
        expect(f.delay, inInclusiveRange(0, 0.5));
      }
    });

    test('no stagger means everything leaves at once', () {
      final List<ExplodeFragment> fragments = build(
        settings: const ExplodeSettings(
          grid: ExplodeGrid(columns: 5, rows: 5),
          stagger: 0,
        ),
      );

      expect(fragments.every((ExplodeFragment f) => f.delay == 0), isTrue);
    });
  });

  group('randomness', () {
    test('the same seed shatters the same way', () {
      final List<ExplodeFragment> a = build(seed: 42);
      final List<ExplodeFragment> b = build(seed: 42);

      expect(a, hasLength(b.length));
      for (int i = 0; i < a.length; i++) {
        expect(a[i].velocity, b[i].velocity);
        expect(a[i].spin, b[i].spin);
      }
    });

    test('a different seed shatters differently', () {
      final List<ExplodeFragment> a = build(seed: 1);
      final List<ExplodeFragment> b = build(seed: 2);

      final bool identical = List<bool>.generate(
        a.length,
        (int i) => a[i].velocity == b[i].velocity,
      ).every((bool same) => same);
      expect(identical, isFalse);
    });

    test('a fragment sitting on the blast still goes somewhere', () {
      // A 1x1 grid puts the only fragment exactly on a centre origin, so
      // "away from the blast" is the zero vector and needs a fallback.
      final ExplodeFragment only = build(
        settings: const ExplodeSettings(
          grid: ExplodeGrid(columns: 1, rows: 1),
          origin: ExplodeOrigin.at(Alignment.center),
          minSpeed: 100,
          maxSpeed: 100,
        ),
      ).single;

      expect(only.velocity.distance, closeTo(100, 0.001));
      expect(only.velocity.dx.isNaN, isFalse);
      expect(only.velocity.dy.isNaN, isFalse);
    });
  });

  test('a thousand fragments is a normal ask', () {
    final List<ExplodeFragment> fragments = build(
      size: const ui.Size(400, 400),
      settings: const ExplodeSettings(grid: ExplodeGrid.auto(1000)),
    );

    expect(fragments.length, closeTo(1000, 60));
    expect(
      fragments.every((ExplodeFragment f) => f.velocity.distance > 0),
      isTrue,
    );
  });
}
