# explode_widget

[![Pub Version](https://img.shields.io/pub/v/explode_widget)](https://pub.dev/packages/explode_widget)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![pub points](https://img.shields.io/pub/points/explode_widget)](https://pub.dev/packages/explode_widget/score)
[![likes](https://img.shields.io/pub/likes/explode_widget)](https://pub.dev/packages/explode_widget/score)

Shatters any widget into thousands of fragments of its own pixels.

```dart
ExplodeWidget(
  child: Card(child: ListTile(title: Text('Tap me'))),
)
```

Tap it. The widget is captured, cut into a grid, and every piece is thrown with
its own velocity, spin and fade then it is gone.

The pieces are rectangles of the widget's own snapshot, so what flies apart is
the widget itself: its text, its gradient, its border. Not a cloud of dots in
matching colours.

## How it works, and why that matters

The whole thing lives in one `RenderObject`.

`RenderExplode` makes itself a repaint boundary, which means it owns an
`OffsetLayer` — and a layer can rasterise itself with `toImageSync`,
**synchronously**, in the same frame as the tap. No `GlobalKey`, no
`RepaintBoundary` for you to remember, and no async gap where the widget is
neither whole nor exploding.

Every fragment is then one sprite in a single `Canvas.drawRawAtlas` call. That
is the primitive built for exactly this: a thousand rotated, scaled, faded
rectangles of one texture, drawn in one go. A per-particle `drawRect` loop is
what makes a thousand particles stutter; this is why the default is 600
fragments and 2400 is a reasonable ask.

And nothing rebuilds while it runs. The animation's only side effect is
`markNeedsPaint`, so no widget in your tree is asked to build a frame of the
explosion.

The child also stays in the tree the whole time — it is hidden, not removed. So
its state, its controllers and its scroll positions are all still there, and
putting it back is instant:

```dart
final ExplodeController controller = ExplodeController();
// ...
ExplodeWidget(controller: controller, explodeOnTap: false, child: MyForm());
// ...
controller.explode();
controller.reset();   // the form is back, with everything the user typed
```

## Settings

```dart
ExplodeWidget(
  settings: const ExplodeSettings(
    duration: Duration(milliseconds: 900),
    grid: ExplodeGrid.auto(600),        // or ExplodeGrid(columns: 30, rows: 20)
    origin: ExplodeOrigin.tap(),        // or .at(Alignment.topLeft)
    minSpeed: 120,                      // logical pixels per second
    maxSpeed: 520,
    gravity: 1400,                      // pixels per second squared
    spin: 6,                            // radians per second, either way
    shrink: 0.4,                        // how much size a fragment loses
    stagger: 0.25,                      // the far side leaves a little later
    fade: Curves.easeInQuad,
    pixelRatio: null,                   // defaults to the view's
    seed: null,                         // fix it and it shatters the same way
    collapseWhenGone: false,
  ),
  child: child,
)
```

`ExplodeSettings.dust` and `ExplodeSettings.shatter` are ready-made: many small
pieces drifting, and few big ones thrown hard.

### `duration` does not slow the motion down

Speeds are in pixels per **second**, so doubling the duration does not halve
the speed — it gives the fragments twice as long to leave the screen, and you
watch an empty hole fade. To slow an explosion down, bring the speeds and the
gravity down with it:

```dart
// Four seconds of drifting, rather than four seconds of nothing.
const ExplodeSettings(
  duration: Duration(milliseconds: 4000),
  minSpeed: 15, maxSpeed: 60, gravity: 50,
);
```

`ExplodeGrid.auto` follows the widget's aspect ratio, so a 300x100 widget asked
for 300 fragments becomes 30x10, not 17x17 — square debris rather than a
glitch.

`origin` decides where the blast comes from. `ExplodeOrigin.tap()` uses the
point that was touched, which is why the near side of the widget leaves first
and the far side follows.

## What it will not do

- **Platform views do not rasterise.** A map, a web view or a camera preview
  captures as nothing, so it explodes into transparent fragments. That is a
  limit of photographing the layer tree, not of this package.
- **A child with its own tap handler wins the gesture arena.** Wrapping a
  button and leaving `explodeOnTap: true` presses the button. Use the
  controller for those.
- **One controller drives one widget.** Give two live widgets the same
  controller and it drives the most recently built one. There is deliberately
  no assertion: a widget whose key just changed is built before the old one is
  unmounted, and the two cases cannot be told apart from inside.
- **Dashed edges, non-rectangular shards, physics between fragments.** The grid
  is what `drawAtlas` can draw in one call, and that is the whole trick.

## Example

`/example` is a Flutter app with four presets, a widget whose counter survives
the explosion, and a reset button. Run it and tap things.

## License

MIT.
