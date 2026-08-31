import 'package:explode_widget/explode_widget.dart';
import 'package:explode_widget_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('every demo tile can explode and come back', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.text('Tap me'), findsOneWidget);
    expect(find.byType(ExplodeWidget), findsAtLeastNWidgets(2));

    // The counter sits below the fold in an 800x600 test window.
    await tester.scrollUntilVisible(find.text('Explode from code'), 200);
    await tester.pumpAndSettle();

    // It keeps its state across an explosion.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.text('Counter: 1'), findsOneWidget);

    await tester.tap(find.text('Explode from code'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Put it all back'));
    await tester.pumpAndSettle();
    expect(find.text('Counter: 1'), findsOneWidget);
  });

  testWidgets('a tap on the card shatters it', (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());

    final RenderExplode card = tester.renderObject<RenderExplode>(
      find.ancestor(
        of: find.text('Tap me'),
        matching: find.byType(ExplodeWidget),
      ),
    );
    expect(card.phase, ExplodePhase.idle);

    await tester.tap(find.text('Tap me'));
    await tester.pump();
    expect(card.phase, ExplodePhase.exploding);

    await tester.pumpAndSettle();
    expect(card.phase, ExplodePhase.gone);
  });

  testWidgets('switching preset gives each tile a fresh widget', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());

    await tester.tap(find.text('Tap me'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Shatter'));
    await tester.pumpAndSettle();

    // A new key means a new render object, so the card is whole again.
    final RenderExplode card = tester.renderObject<RenderExplode>(
      find.ancestor(
        of: find.text('Tap me'),
        matching: find.byType(ExplodeWidget),
      ),
    );
    expect(card.phase, ExplodePhase.idle);
  });
}
