import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Where the blast comes from.
sealed class ExplodeOrigin {
  const ExplodeOrigin();

  /// The point that was tapped. Falls back to [alignment] when the explosion
  /// was started from the controller rather than a tap.
  const factory ExplodeOrigin.tap() = _TapOrigin;

  /// A fixed point in the widget, e.g. `Alignment.topLeft`.
  const factory ExplodeOrigin.at(Alignment alignment) = _AlignedOrigin;

  /// Resolves to a local point inside a widget of [size].
  Offset resolve(Size size, Offset? tap);
}

final class _TapOrigin extends ExplodeOrigin {
  const _TapOrigin();

  @override
  Offset resolve(Size size, Offset? tap) =>
      tap ?? Alignment.center.alongSize(size);
}

final class _AlignedOrigin extends ExplodeOrigin {
  const _AlignedOrigin(this.alignment);

  final Alignment alignment;

  @override
  Offset resolve(Size size, Offset? tap) => alignment.alongSize(size);
}

/// How many pieces the widget breaks into.
///
/// The widget is cut on a grid, because a grid is the one tiling where every
/// fragment is a rectangle - and a rectangle is what `drawAtlas` can draw
/// thousands of in a single call.
@immutable
class ExplodeGrid {
  /// An explicit grid.
  const ExplodeGrid({required this.columns, required this.rows})
    : assert(columns > 0 && rows > 0, 'a grid needs at least one cell'),
      targetCount = null;

  /// Roughly [count] fragments, laid out to match the widget's aspect ratio.
  ///
  /// A 300x100 widget asked for 300 fragments becomes 30x10, not 17x17: square
  /// fragments read as debris, stretched ones read as a glitch.
  const ExplodeGrid.auto(int count)
    : assert(count > 0, 'a grid needs at least one cell'),
      targetCount = count,
      columns = 0,
      rows = 0;

  final int columns;
  final int rows;
  final int? targetCount;

  /// The grid for a widget of [size], with [auto] resolved.
  (int columns, int rows) resolve(Size size) {
    final int? target = targetCount;
    if (target == null) return (columns, rows);
    if (size.isEmpty) return (1, 1);

    final double ratio = size.width / size.height;
    final int c = (math.sqrt(target * ratio)).round().clamp(1, target);
    final int r = (target / c).round().clamp(1, target);
    return (c, r);
  }

  @override
  bool operator ==(Object other) =>
      other is ExplodeGrid &&
      other.columns == columns &&
      other.rows == rows &&
      other.targetCount == targetCount;

  @override
  int get hashCode => Object.hash(columns, rows, targetCount);
}

/// Everything about how the explosion looks and moves.
@immutable
class ExplodeSettings {
  const ExplodeSettings({
    this.duration = const Duration(milliseconds: 900),
    this.grid = const ExplodeGrid.auto(600),
    this.origin = const ExplodeOrigin.tap(),
    this.minSpeed = 120,
    this.maxSpeed = 520,
    this.gravity = 1400,
    this.spin = 6,
    this.shrink = 0.4,
    this.stagger = 0.25,
    this.fade = Curves.easeInQuad,
    this.pixelRatio,
    this.seed,
    this.collapseWhenGone = false,
  }) : assert(minSpeed >= 0 && maxSpeed >= minSpeed, 'speeds must be a range'),
       assert(stagger >= 0 && stagger < 1, 'stagger is a fraction of duration'),
       assert(shrink >= 0 && shrink <= 1, 'shrink is a fraction of the size');

  /// How long the whole thing takes, including the staggered start.
  final Duration duration;

  /// How the widget is cut up.
  final ExplodeGrid grid;

  /// Where the blast comes from.
  final ExplodeOrigin origin;

  /// Speed range in logical pixels per second, before gravity.
  final double minSpeed;
  final double maxSpeed;

  /// Downward acceleration in logical pixels per second squared. Zero floats.
  final double gravity;

  /// Peak spin in radians per second, in either direction. Zero keeps
  /// fragments upright, which reads as a slide rather than a shatter.
  final double spin;

  /// How much of its size a fragment loses by the end, 0 to 1.
  final double shrink;

  /// How much of [duration] is spent letting the shockwave reach the far
  /// fragments. Zero starts everything at once, which looks mechanical.
  final double stagger;

  /// Applied to each fragment's own progress to fade it out.
  final Curve fade;

  /// Resolution of the captured snapshot. Defaults to the view's device pixel
  /// ratio, so fragments are as sharp as the widget was.
  ///
  /// Halving it quarters the texture memory, which is the knob to reach for on
  /// a very large widget.
  final double? pixelRatio;

  /// Fixes the randomness, so the same widget shatters the same way. Tests
  /// need it; a UI usually does not.
  final int? seed;

  /// Whether the widget gives up its space once the fragments are gone.
  ///
  /// False by default: collapsing relayouts everything around it, and a hole
  /// where the widget was is usually the intent.
  final bool collapseWhenGone;

  ExplodeSettings copyWith({
    Duration? duration,
    ExplodeGrid? grid,
    ExplodeOrigin? origin,
    double? minSpeed,
    double? maxSpeed,
    double? gravity,
    double? spin,
    double? shrink,
    double? stagger,
    Curve? fade,
    double? pixelRatio,
    int? seed,
    bool? collapseWhenGone,
  }) => ExplodeSettings(
    duration: duration ?? this.duration,
    grid: grid ?? this.grid,
    origin: origin ?? this.origin,
    minSpeed: minSpeed ?? this.minSpeed,
    maxSpeed: maxSpeed ?? this.maxSpeed,
    gravity: gravity ?? this.gravity,
    spin: spin ?? this.spin,
    shrink: shrink ?? this.shrink,
    stagger: stagger ?? this.stagger,
    fade: fade ?? this.fade,
    pixelRatio: pixelRatio ?? this.pixelRatio,
    seed: seed ?? this.seed,
    collapseWhenGone: collapseWhenGone ?? this.collapseWhenGone,
  );

  /// Fine dust that drifts: many small fragments, little gravity, slow.
  static const ExplodeSettings dust = ExplodeSettings(
    duration: Duration(milliseconds: 1600),
    grid: ExplodeGrid.auto(2400),
    minSpeed: 40,
    maxSpeed: 180,
    gravity: 240,
    spin: 2,
    shrink: 0.8,
    stagger: 0.4,
  );

  /// Big pieces thrown hard, like glass.
  static const ExplodeSettings shatter = ExplodeSettings(
    duration: Duration(milliseconds: 1100),
    grid: ExplodeGrid.auto(120),
    minSpeed: 200,
    maxSpeed: 900,
    gravity: 2200,
    spin: 9,
    shrink: 0.1,
    stagger: 0.1,
  );
}
