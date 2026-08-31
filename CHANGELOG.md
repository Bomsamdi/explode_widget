## 0.1.1

* Shortened the pubspec description to fit the 180 characters pub.dev indexes.
  Nothing else changed - 0.1.0 went out at 185 and lost 10 of its 160 analysis
  points for it.

## 0.1.0

First release.

* `ExplodeWidget` shatters any child into fragments of its own pixels, on tap
  or from an `ExplodeController`.
* Implemented as a single `RenderObject`: it is its own repaint boundary, so it
  rasterises its layer with `OffsetLayer.toImageSync` synchronously, and draws
  every fragment in one `Canvas.drawRawAtlas` call. Nothing in the widget tree
  rebuilds while the explosion runs.
* The child is hidden rather than removed, so its state survives and
  `ExplodeController.reset()` puts it back instantly.
* `ExplodeSettings` covers the grid, the blast origin, speed, gravity, spin,
  shrink, stagger, fade, pixel ratio and a seed for a repeatable explosion.
  `ExplodeSettings.dust` and `.shatter` are presets.
* `ExplodeGrid.auto` picks a grid from the widget's aspect ratio, so fragments
  stay square.
