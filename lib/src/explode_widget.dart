import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'explode_settings.dart';
import 'render_explode.dart';

/// Starts and resets an explosion from outside the widget.
///
/// Attach one to an [ExplodeWidget], keep it in your `State`, and dispose it
/// with the rest.
///
/// Give each widget its own controller. If the same controller is passed to
/// two widgets that are alive at once, it drives the most recently built one
/// and the other becomes unreachable - the package cannot warn about it,
/// because that is indistinguishable from a widget whose key just changed.
class ExplodeController {
  RenderExplode? _render;

  /// Whether the widget this controller drives has finished exploding.
  ///
  /// False before the controller is attached to anything.
  bool get isExploded => _render?.isExploded ?? false;

  /// What the widget is doing, or null before it is attached.
  ExplodePhase? get phase => _render?.phase;

  /// Shatters the widget. Does nothing if it is already shattered.
  ///
  /// [origin] is a point in the widget's own coordinates; without one, the
  /// settings decide - and [ExplodeOrigin.tap] falls back to the centre,
  /// because no pointer was involved.
  void explode({ui.Offset? origin}) {
    assert(
      _render != null,
      'ExplodeController.explode() was called before the ExplodeWidget was '
      'built. Call it from a callback, not from initState.',
    );
    _render?.explode(origin: origin);
  }

  /// Puts the child back. Its state was never disposed, so this is instant.
  void reset() {
    assert(
      _render != null,
      'ExplodeController.reset() was called before the ExplodeWidget was built.',
    );
    _render?.reset();
  }

  /// Not part of the public surface: called by [RenderExplode] when it takes
  /// this controller on.
  @internal
  void attachToRender(RenderExplode render) {
    // The newest widget wins, and there is deliberately no assertion here.
    //
    // A widget that changes key, or moves in the tree, is built before the old
    // one is unmounted - and measuring showed the outgoing render object is
    // still `attached` at that moment, so there is no reliable way to tell
    // that legitimate case apart from two live widgets sharing a controller.
    // An assertion that fires on a key change would be worse than the footgun
    // it guards, so the behaviour is documented on the class instead.
    _render = render;
  }

  /// Not part of the public surface: called by [RenderExplode] when it lets
  /// this controller go.
  @internal
  void detachFromRender(RenderExplode render) {
    if (_render == render) _render = null;
  }
}

/// Shatters any widget into thousands of pieces of itself.
///
/// Wrap something and tap it:
///
/// ```dart
/// ExplodeWidget(
///   child: Card(child: ListTile(title: Text('Tap me'))),
/// )
/// ```
///
/// The child is captured as an image the moment the explosion starts, cut into
/// a grid, and every piece is thrown with its own velocity and spin. Because
/// the pieces are rectangles of that image, what flies apart is the widget
/// itself - text, gradients, borders and all - not a cloud of dots in matching
/// colours.
///
/// The child is not removed from the tree while it explodes, only hidden. Its
/// state survives, so [ExplodeController.reset] brings it back instantly.
///
/// What cannot be captured: platform views (a map, a web view, a camera
/// preview) rasterise to nothing, so they explode into transparent fragments.
/// That is a limit of taking a picture of the layer tree, not of this package.
class ExplodeWidget extends StatefulWidget {
  const ExplodeWidget({
    required this.child,
    this.settings = const ExplodeSettings(),
    this.controller,
    this.explodeOnTap = true,
    this.onCompleted,
    super.key,
  });

  /// The widget that gets shattered.
  final Widget child;

  /// How the explosion looks and moves.
  final ExplodeSettings settings;

  /// Lets you explode and reset from code.
  final ExplodeController? controller;

  /// Whether a tap on the child starts the explosion.
  ///
  /// A child with its own tap handler wins the gesture arena, so wrapping a
  /// button and leaving this on will press the button instead. Use the
  /// controller for those.
  final bool explodeOnTap;

  /// Called once the last fragment has faded.
  final VoidCallback? onCompleted;

  @override
  State<ExplodeWidget> createState() => _ExplodeWidgetState();
}

class _ExplodeWidgetState extends State<ExplodeWidget>
    with SingleTickerProviderStateMixin {
  @override
  Widget build(BuildContext context) => _ExplodeRenderWidget(
    vsync: this,
    settings: widget.settings,
    controller: widget.controller,
    explodeOnTap: widget.explodeOnTap,
    onCompleted: widget.onCompleted,
    child: widget.child,
  );
}

class _ExplodeRenderWidget extends SingleChildRenderObjectWidget {
  const _ExplodeRenderWidget({
    required this.vsync,
    required this.settings,
    required this.explodeOnTap,
    this.controller,
    this.onCompleted,
    super.child,
  });

  final TickerProvider vsync;
  final ExplodeSettings settings;
  final ExplodeController? controller;
  final bool explodeOnTap;
  final VoidCallback? onCompleted;

  @override
  RenderExplode createRenderObject(BuildContext context) {
    return RenderExplode(
      vsync: vsync,
      settings: settings,
      explodeOnTap: explodeOnTap,
      controller: controller,
      onCompleted: onCompleted,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderExplode renderObject) {
    renderObject
      ..settings = settings
      ..explodeOnTap = explodeOnTap
      ..controller = controller
      ..onCompleted = onCompleted;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      FlagProperty(
        'explodeOnTap',
        value: explodeOnTap,
        ifFalse: 'controller only',
      ),
    );
  }
}
