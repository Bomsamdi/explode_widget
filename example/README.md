# explode_widget example

Tap the card, the chips, or press **Explode from code** — each one shatters into
fragments of its own pixels and vanishes. **Put it all back** resets everything.

Four presets:

- **Standard** — the defaults: 600 fragments, ~900 ms.
- **Dust** — 2400 small pieces, low gravity, drifting for 1.6 s.
- **Shatter** — 120 big pieces thrown hard, like glass.
- **Drift** — slow *and* close: note that it lowers the **speeds**, not only
  the duration. Velocity is in pixels per second, so a longer duration on its
  own just gives the fragments more time to leave the screen.

The middle tile is the point of the package: its counter keeps its value across
an explosion and a reset, because the child is hidden rather than removed from
the tree.

```sh
flutter run          # any device
flutter run -d chrome
flutter test
```
