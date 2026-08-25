import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sweeda_real_estate/core/guide/guide_presenter.dart';

void main() {
  testWidgets('presenter inserts and removes exactly one overlay', (tester) async {
    final presenter = OverlayEntryGuidePresenter();
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.expand())),
    );

    presenter.show(
      context: tester.element(find.byType(Scaffold)),
      targetRect: const Rect.fromLTWH(40, 120, 80, 48),
      title: 'عنوان الاختبار',
      message: 'نص الاختبار',
      roleLabel: 'جولة المستخدم',
      stepLabel: 'الخطوة 1 من 3',
      isFirstStep: true,
    );
    await tester.pumpAndSettle();

    expect(presenter.isShowing, isTrue);
    expect(find.text('عنوان الاختبار'), findsOneWidget);
    expect(find.text('نص الاختبار'), findsOneWidget);

    presenter.show(
      context: tester.element(find.byType(Scaffold)),
      targetRect: const Rect.fromLTWH(40, 120, 80, 48),
      title: 'عنوان ثانٍ',
      message: 'نص ثانٍ',
    );
    await tester.pumpAndSettle();

    expect(find.text('عنوان الاختبار'), findsNothing);
    expect(find.text('عنوان ثانٍ'), findsOneWidget);
    presenter.dispose();
    await tester.pump();
    expect(presenter.isShowing, isFalse);
  });
}
