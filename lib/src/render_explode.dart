import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';

import 'explode_fragments.dart';
import 'explode_settings.dart';
import 'explode_widget.dart';

/// What the render object is doing right now.
enum ExplodePhase {
  /// Painting the child, waiting.
  idle,

  /// Painting fragments; the child is still in the tree but not painted.
  exploding,

  /// The fragments have flown; nothing is painted.
  gone,
}

/// Shatters its child into fragments of the child's own pixels.
///
/// The interesting part is that this needs no help from the widget layer. It is
/// its own repaint boundary, so it owns an [OffsetLayer] and can rasterise
/// itself with [OffsetLayer.toImageSync] - synchronously, in the same frame as
/// the tap. Every fragment is then a rectangle of that snapshot, and all of
/// them are drawn with one [Canvas.drawAtlas] call, so a thousand fragments
/// cost about what one image costs.
///
/// Nothing rebuilds while the explosion runs: the animation only ever calls
/// [markNeedsPaint].
class RenderExplode extends RenderProxyBox {
  RenderExplode({
    required TickerProvider vsync,
    required ExplodeSettings settings,
    required bool explodeOnTap,
    ExplodeController? controller,
    this.onCompleted,
    RenderBox? child,
  }) : _settings = settings,
       _explodeOnTap = explodeOnTap,
       super(child) {
    this.controller = controller;
    _animation = AnimationController(vsync: vsync, duration: settings.duration)
      ..addListener(markNeedsPaint)
      ..addStatusListener(_onStatus);
    _tap = TapGestureRecognizer(debugOwner: this)..onTapDown = _onTapDown;
  }

  late final AnimationController _animation;
  late final TapGestureRecognizer _tap;

  final ExplodeFragmentBuilder _builder = const ExplodeFragmentBuilder();

  ui.Image? _snapshot;
  List<ExplodeFragment> _fragments = const <ExplodeFragment>[];
  double _capturedPixelRatio = 1;
  ExplodePhase _phase = ExplodePhase.idle;

  /// Reusable buffers, so a frame allocates nothing per fragment.
  Float32List? _transforms;
  Float32List? _rects;
  Int32List? _colors;

  ExplodePhase get phase => _phase;

  /// True once the fragments are gone and nothing is painted.
  bool get isExploded => _phase == ExplodePhase.gone;

  ExplodeSettings get settings => _settings;
  ExplodeSettings _settings;
  set settings(ExplodeSettings value) {
    if (_settings == value) return;
    final bool gridChanged = _settings.grid != value.grid;
    _settings = value;
    _animation.duration = value.duration;
    // Changing the grid mid-flight would renumber the fragments, so it only
    // takes effect on the next explosion.
    if (gridChanged && _phase == ExplodePhase.idle) _fragments = const [];
    markNeedsPaint();
  }

  /// The controller that drives this render object, if any.
  ///
  /// Owned here rather than in the widget, because a rebuild that swaps the
  /// controller does not recreate the render object - and a controller that
  /// silently drives nothing is the worst kind of bug to look for.
  ExplodeController? get controller => _controller;
  ExplodeController? _controller;
  set controller(ExplodeController? value) {
    if (_controller == value) return;
    _controller?.detachFromRender(this);
    _controller = value;
    _controller?.attachToRender(this);
  }

  bool get explodeOnTap => _explodeOnTap;
  bool _explodeOnTap;
  set explodeOnTap(bool value) {
    if (_explodeOnTap == value) return;
    _explodeOnTap = value;
  }

  /// Called once the last fragment has faded.
  VoidCallback? onCompleted;

  /// Takes the snapshot and throws it.
  ///
  /// [origin] is a local point; without one the settings decide.
  void explode({ui.Offset? origin}) {
    if (_phase != ExplodePhase.idle) return;
    if (!hasSize || size.isEmpty || child == null) return;

    final ui.Image? snapshot = _capture();
    if (snapshot == null) return;

    _snapshot?.dispose();
    _snapshot = snapshot;
    _fragments = _builder.build(
      size: size,
      pixelRatio: _capturedPixelRatio,
      settings: _settings,
      seed: _settings.seed ?? _random.nextInt(debugSeedBound),
      tap: origin,
    );
    _allocate(_fragments.length);

    _phase = ExplodePhase.exploding;
    _animation
      ..reset()
      ..forward();
    markNeedsPaint();
  }

  /// Puts the child back, exactly as it was.
  ///
  /// The child was never removed from the tree - only stopped being painted -
  /// so its state, controllers and scroll positions are still there.
  void reset() {
    if (_phase == ExplodePhase.idle) return;
    _animation.stop();
    _phase = ExplodePhase.idle;
    _release();
    if (_settings.collapseWhenGone) markNeedsLayout();
    markNeedsPaint();
  }

  static final math.Random _random = math.Random();

  /// The exclusive upper bound for a generated seed.
  ///
  /// Written as a literal on purpose. JavaScript's bitwise operators are
  /// 32 bit, so `1 << 32` is **0** on the web and `Random.nextInt` throws
  /// `RangeError` - which the VM tests cannot see, because there `1 << 32` is
  /// four billion. This is a compiled-for-the-web hazard, not a maths one.
  @visibleForTesting
  static const int debugSeedBound = 0x7FFFFFFF;

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _phase = ExplodePhase.gone;
    // The snapshot is the expensive part; nothing draws it any more.
    _release();
    if (_settings.collapseWhenGone) markNeedsLayout();
    markNeedsPaint();
    onCompleted?.call();
  }

  void _release() {
    _snapshot?.dispose();
    _snapshot = null;
    _fragments = const <ExplodeFragment>[];
    _transforms = null;
    _rects = null;
    _colors = null;
  }

  ui.Image? _capture() {
    final ContainerLayer? boundary = layer;
    if (boundary is! OffsetLayer) return null;
    assert(() {
      if (debugNeedsPaint) {
        throw FlutterError(
          'ExplodeWidget captured a snapshot of a widget that has not been '
          'painted yet.\nExplode it after the first frame - from a tap, or '
          'from a callback scheduled with addPostFrameCallback.',
        );
      }
      return true;
    }());

    _capturedPixelRatio =
        _settings.pixelRatio ??
        // The child was rasterised at the view's ratio, so anything else here
        // would either blur the fragments or waste memory.
        (RendererBinding.instance.renderViews.isEmpty
            ? 1.0
            : RendererBinding
                  .instance
                  .renderViews
                  .first
                  .configuration
                  .devicePixelRatio);
    return boundary.toImageSync(
      ui.Offset.zero & size,
      pixelRatio: _capturedPixelRatio,
    );
  }

  void _allocate(int count) {
    _transforms = Float32List(count * 4);
    _rects = Float32List(count * 4);
    _colors = Int32List(count);
  }

  // A repaint boundary of our own is what makes toImageSync possible, and it
  // also means a frame of the explosion repaints nothing but this subtree.
  @override
  bool get isRepaintBoundary => true;

  @override
  void performLayout() {
    if (_phase == ExplodePhase.gone && _settings.collapseWhenGone) {
      child?.layout(constraints, parentUsesSize: false);
      size = constraints.smallest;
      return;
    }
    super.performLayout();
  }

  @override
  void paint(PaintingContext context, ui.Offset offset) {
    switch (_phase) {
      case ExplodePhase.idle:
        super.paint(context, offset);
      case ExplodePhase.exploding:
        _paintFragments(context.canvas, offset);
      case ExplodePhase.gone:
        break;
    }
  }

  void _paintFragments(ui.Canvas canvas, ui.Offset offset) {
    final ui.Image? snapshot = _snapshot;
    final Float32List? transforms = _transforms;
    final Float32List? rects = _rects;
    final Int32List? colors = _colors;
    if (snapshot == null ||
        transforms == null ||
        rects == null ||
        colors == null) {
      return;
    }

    final double elapsed = _animation.value * _lifetime;
    final double lifetime = _lifetime * (1 - _settings.stagger);

    for (int i = 0; i < _fragments.length; i++) {
      final ExplodeFragment fragment = _fragments[i];
      final double progress = fragment.progressAt(elapsed, lifetime);
      final ui.Offset centre = fragment.positionAt(elapsed, _settings.gravity);
      final double scale =
          (1 - _settings.shrink * progress) / _capturedPixelRatio;
      final double rotation = fragment.rotationAt(elapsed);

      // RSTransform packs scaled cosine, scaled sine and a translation. The
      // anchor is in source pixels, so the sprite turns about its own centre.
      final double scaledCos = math.cos(rotation) * scale;
      final double scaledSin = math.sin(rotation) * scale;
      final double anchorX = fragment.source.width / 2;
      final double anchorY = fragment.source.height / 2;

      final int t = i * 4;
      transforms[t] = scaledCos;
      transforms[t + 1] = scaledSin;
      transforms[t + 2] =
          offset.dx + centre.dx - (scaledCos * anchorX - scaledSin * anchorY);
      transforms[t + 3] =
          offset.dy + centre.dy - (scaledSin * anchorX + scaledCos * anchorY);

      rects[t] = fragment.source.left;
      rects[t + 1] = fragment.source.top;
      rects[t + 2] = fragment.source.right;
      rects[t + 3] = fragment.source.bottom;

      // White modulated by the fragment's own alpha: multiplying leaves the
      // colours alone and scales the transparency.
      final int alpha = (255 * (1 - _settings.fade.transform(progress)))
          .round()
          .clamp(0, 255);
      colors[i] = (alpha << 24) | 0x00FFFFFF;
    }

    canvas.drawRawAtlas(
      snapshot,
      transforms,
      rects,
      colors,
      ui.BlendMode.modulate,
      null,
      ui.Paint()..filterQuality = ui.FilterQuality.low,
    );
  }

  double get _lifetime =>
      (_animation.duration ?? Duration.zero).inMicroseconds / 1e6;

  @override
  bool hitTestSelf(ui.Offset position) =>
      _explodeOnTap && _phase == ExplodePhase.idle;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (_explodeOnTap && event is PointerDownEvent) _tap.addPointer(event);
    super.handleEvent(event, entry);
  }

  void _onTapDown(TapDownDetails details) =>
      explode(origin: details.localPosition);

  @override
  void detach() {
    _animation.stop();
    super.detach();
  }

  @override
  void dispose() {
    _controller?.detachFromRender(this);
    _controller = null;
    _animation.dispose();
    _tap.dispose();
    _release();
    super.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(EnumProperty<ExplodePhase>('phase', _phase))
      ..add(IntProperty('fragments', _fragments.length))
      ..add(
        FlagProperty(
          'explodeOnTap',
          value: _explodeOnTap,
          ifFalse: 'controller only',
        ),
      );
  }
}
