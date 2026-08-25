import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sweeda_real_estate/core/guide/guide_host.dart';
import 'package:sweeda_real_estate/core/guide/visitor_guide_coordinator.dart';

void main() {
  testWidgets('starts the visitor question only when a GuideHost is present',
      (tester) async {
    late BuildContext hostContext;

    await tester.pumpWidget(
      MaterialApp(
        home: GuideHost(
          child: Builder(
            builder: (context) {
              hostContext = context;
              return const Scaffold(body: SizedBox.expand());
            },
          ),
        ),
      ),
    );
    await tester.pump();

    await VisitorGuideCoordinator.maybeStart(hostContext);
    await tester.pumpAndSettle();

    expect(find.text('جولة الزائر'), findsOneWidget);
    expect(find.text('هل ترغب في جولة تعريفية سريعة؟'), findsOneWidget);
  });
}
