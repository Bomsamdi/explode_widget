import 'dart:math' as math;
import 'dart:ui' as ui;

import 'explode_settings.dart';

/// One piece of the widget: a rectangle of the snapshot, thrown.
///
/// The motion is a closed form of the elapsed time rather than a step-by-step
/// integration. Two reasons: a dropped frame cannot change where a fragment
/// ends up, and a test can ask where any fragment is at any moment without
/// pumping the clock there.
class ExplodeFragment {
  ExplodeFragment({
    required this.source,
    required this.origin,
    required this.velocity,
    required this.spin,
    required this.delay,
  });

  /// The fragment's rectangle inside the snapshot, in image pixels.
  final ui.Rect source;

  /// Where the fragment's centre starts, in the widget's local coordinates.
  final ui.Offset origin;

  /// Initial velocity in logical pixels per second.
  final ui.Offset velocity;

  /// Angular velocity in radians per second.
  final double spin;

  /// How long this fragment waits before it moves, in seconds. The far side of
  /// the widget leaves a little after the near side, so the blast travels.
  final double delay;

  /// Seconds this fragment has been moving, given the whole explosion is
  /// [elapsed] seconds old.
  double age(double elapsed) => math.max(0, elapsed - delay);

  /// The centre, after [elapsed] seconds of the explosion.
  ui.Offset positionAt(double elapsed, double gravity) {
    final double t = age(elapsed);
    return ui.Offset(
      origin.dx + velocity.dx * t,
      origin.dy + velocity.dy * t + 0.5 * gravity * t * t,
    );
  }

  double rotationAt(double elapsed) => spin * age(elapsed);

  /// This fragment's own 0..1 progress, which is what fades and shrinks it.
  ///
  /// A fragment that waits is not yet fading, so a staggered explosion does
  /// not go transparent before it has moved.
  double progressAt(double elapsed, double lifetime) {
    if (lifetime <= 0) return 1;
    return (age(elapsed) / lifetime).clamp(0.0, 1.0);
  }
}

/// Cuts a snapshot into fragments and gives each one a trajectory.
class ExplodeFragmentBuilder {
  const ExplodeFragmentBuilder();

  /// Builds the fragments for a widget of [size], captured at [pixelRatio].
  ///
  /// [tap] is where the pointer went down, when there was one.
  List<ExplodeFragment> build({
    required ui.Size size,
    required double pixelRatio,
    required ExplodeSettings settings,
    required int seed,
    ui.Offset? tap,
  }) {
    if (size.isEmpty) return const <ExplodeFragment>[];

    final (int columns, int rows) = settings.grid.resolve(size);
    final double cellWidth = size.width / columns;
    final double cellHeight = size.height / rows;
    final ui.Offset blast = settings.origin.resolve(size, tap);
    final math.Random random = math.Random(seed);

    // The far corner sets the scale for the stagger, so the shockwave always
    // finishes crossing the widget within the fraction it was given.
    final double reach = _farthestCorner(size, blast);
    final double lifetime = settings.duration.inMicroseconds / 1e6;
    final double staggerSeconds = lifetime * settings.stagger;

    final List<ExplodeFragment> fragments = <ExplodeFragment>[];
    for (int row = 0; row < rows; row++) {
      for (int column = 0; column < columns; column++) {
        final ui.Offset centre = ui.Offset(
          (column + 0.5) * cellWidth,
          (row + 0.5) * cellHeight,
        );

        final double distance = (centre - blast).distance;
        final double direction = _direction(centre - blast, random);
        final double speed = ui.lerpDouble(
          settings.minSpeed,
          settings.maxSpeed,
          random.nextDouble(),
        )!;

        fragments.add(
          ExplodeFragment(
            source: ui.Rect.fromLTWH(
              column * cellWidth * pixelRatio,
              row * cellHeight * pixelRatio,
              cellWidth * pixelRatio,
              cellHeight * pixelRatio,
            ),
            origin: centre,
            velocity: ui.Offset(
              math.cos(direction) * speed,
              math.sin(direction) * speed,
            ),
            spin: (random.nextDouble() * 2 - 1) * settings.spin,
            delay: reach == 0 ? 0 : staggerSeconds * (distance / reach),
          ),
        );
      }
    }
    return fragments;
  }

  /// Outward from the blast, with a little jitter so the grid does not show as
  /// rays. A fragment sitting exactly on the blast gets a random direction,
  /// because it has no outward to go.
  double _direction(ui.Offset away, math.Random random) {
    const double jitter = 0.35;
    final double base = away.distance < 0.01
        ? random.nextDouble() * 2 * math.pi
        : math.atan2(away.dy, away.dx);
    return base + (random.nextDouble() * 2 - 1) * jitter;
  }

  double _farthestCorner(ui.Size size, ui.Offset from) {
    double farthest = 0;
    for (final ui.Offset corner in <ui.Offset>[
      ui.Offset.zero,
      ui.Offset(size.width, 0),
      ui.Offset(0, size.height),
      ui.Offset(size.width, size.height),
    ]) {
      farthest = math.max(farthest, (corner - from).distance);
    }
    return farthest;
  }
}
