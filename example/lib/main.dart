import 'package:explode_widget/explode_widget.dart';
import 'package:flutter/material.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'explode_widget',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF4F46E5),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    home: const HomePage(),
  );
}

/// The presets the demo offers, and what each one is for.
enum Preset {
  standard('Standard', 'the defaults'),
  dust('Dust', 'many small pieces, drifting'),
  shatter('Shatter', 'few big pieces, thrown hard'),
  drift('Drift', 'slow and close: gentle speeds, almost no gravity');

  const Preset(this.label, this.blurb);

  final String label;
  final String blurb;

  ExplodeSettings get settings => switch (this) {
    Preset.standard => const ExplodeSettings(),
    Preset.dust => ExplodeSettings.dust,
    Preset.shatter => ExplodeSettings.shatter,
    // Note the speeds, not just the duration: velocity is in pixels per
    // second, so a longer duration on its own does not slow anything down -
    // it only gives the fragments longer to leave the screen.
    Preset.drift => const ExplodeSettings(
      duration: Duration(milliseconds: 4000),
      grid: ExplodeGrid.auto(900),
      minSpeed: 15,
      maxSpeed: 60,
      gravity: 50,
      spin: 1.2,
      shrink: 0.5,
      stagger: 0.3,
    ),
  };
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Preset _preset = Preset.standard;
  final List<ExplodeController> _controllers = List<ExplodeController>.generate(
    3,
    (_) => ExplodeController(),
  );

  void _resetAll() {
    for (final ExplodeController controller in _controllers) {
      if (controller.phase != null) controller.reset();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('explode_widget'),
        actions: <Widget>[
          TextButton.icon(
            onPressed: _resetAll,
            icon: const Icon(Icons.refresh),
            label: const Text('Put it all back'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          Text(
            'Tap anything below. It shatters from the point you touched, into '
            'fragments of its own pixels - then reset and it is back, with its '
            'state untouched.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          SegmentedButton<Preset>(
            segments: <ButtonSegment<Preset>>[
              for (final Preset preset in Preset.values)
                ButtonSegment<Preset>(
                  value: preset,
                  label: Text(preset.label),
                  tooltip: preset.blurb,
                ),
            ],
            selected: <Preset>{_preset},
            onSelectionChanged: (Set<Preset> selected) {
              // A changed key rebuilds the widgets, so the preset applies to a
              // fresh explosion rather than to one already in flight.
              setState(() => _preset = selected.first);
            },
          ),
          const SizedBox(height: 8),
          Text(_preset.blurb, style: theme.textTheme.bodySmall),
          const SizedBox(height: 28),
          _Section(
            title: 'A card, with text and a gradient',
            child: ExplodeWidget(
              key: ValueKey<String>('card-${_preset.name}'),
              settings: _preset.settings,
              controller: _controllers[0],
              child: const _GradientCard(),
            ),
          ),
          _Section(
            title: 'A live widget: the count survives the explosion',
            trailing: Builder(
              builder: (BuildContext context) => FilledButton(
                onPressed: () => _controllers[1].explode(),
                child: const Text('Explode from code'),
              ),
            ),
            child: ExplodeWidget(
              key: ValueKey<String>('counter-${_preset.name}'),
              settings: _preset.settings,
              controller: _controllers[1],
              explodeOnTap: false,
              child: const _Counter(),
            ),
          ),
          _Section(
            title: 'A grid of chips, all at once',
            child: ExplodeWidget(
              key: ValueKey<String>('chips-${_preset.name}'),
              settings: _preset.settings,
              controller: _controllers[2],
              child: const _Chips(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 36),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        child,
        if (trailing != null) ...<Widget>[
          const SizedBox(height: 12),
          trailing!,
        ],
      ],
    ),
  );
}

class _GradientCard extends StatelessWidget {
  const _GradientCard();

  @override
  Widget build(BuildContext context) => Container(
    height: 160,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[Color(0xFF4F46E5), Color(0xFFEC4899)],
      ),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          'Tap me',
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          'Every fragment is a rectangle of this card, so the letters and the '
          'gradient fly apart with it.',
          style: TextStyle(color: Colors.white70),
        ),
      ],
    ),
  );
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: <Widget>[
          Text('Counter: $_count', style: const TextStyle(fontSize: 22)),
          const Spacer(),
          IconButton.filled(
            onPressed: () => setState(() => _count++),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    ),
  );
}

class _Chips extends StatelessWidget {
  const _Chips();

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: <Widget>[
      for (final String label in <String>[
        'sliver',
        'render object',
        'drawAtlas',
        'toImageSync',
        'no rebuilds',
        'one draw call',
        'any widget',
        'MIT',
      ])
        Chip(label: Text(label)),
    ],
  );
}
