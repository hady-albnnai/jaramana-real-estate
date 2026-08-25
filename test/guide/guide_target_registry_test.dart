import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sweeda_real_estate/core/guide/guide_models.dart';
import 'package:sweeda_real_estate/core/guide/guide_target_registry.dart';
import 'package:sweeda_real_estate/widgets/guide_anchor.dart';

void main() {
  testWidgets('GuideAnchor registers and measures a real target', (tester) async {
    final registry = GuideTargetRegistry();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: GuideAnchor(
              id: GuideStepIds.userOffers,
              registry: registry,
              child: const SizedBox(width: 120, height: 48),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final snapshot = registry.refresh(GuideStepIds.userOffers);
    expect(snapshot.ready, isTrue);
    expect(snapshot.rect?.width, 120);
    expect(snapshot.rect?.height, 48);
    expect(snapshot.generation, greaterThan(0));
  });

  testWidgets('registry rejects zero-size targets without throwing', (tester) async {
    final registry = GuideTargetRegistry();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: GuideAnchor(
              id: 'zero-target',
              registry: registry,
              child: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final snapshot = registry.refresh('zero-target');
    expect(snapshot.ready, isFalse);
    expect(snapshot.rect, isNull);
  });

  testWidgets('anchor unregisters when removed', (tester) async {
    final registry = GuideTargetRegistry();
    await tester.pumpWidget(
      MaterialApp(
        home: GuideAnchor(
          id: 'temporary',
          registry: registry,
          child: const SizedBox(width: 10, height: 10),
        ),
      ),
    );
    await tester.pump();
    expect(registry.ids, contains('temporary'));

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    expect(registry.ids, isNot(contains('temporary')));
  });
}
