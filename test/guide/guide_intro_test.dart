import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sweeda_real_estate/core/guide/guide_intro.dart';
import 'package:sweeda_real_estate/core/guide/guide_models.dart';

void main() {
  testWidgets('question exposes role, actions, and rejection hint', (tester) async {
    var yes = false;
    var no = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: GuideQuestion(
            scope: GuideScope.user,
            onYes: () => yes = true,
            onNo: () => no = true,
          ),
        ),
      ),
    );

    expect(find.text('جولة المستخدم'), findsOneWidget);
    expect(find.text('هل ترغب في التعرّف إلى أهم وظائف حسابك؟'), findsOneWidget);
    expect(find.text('يمكنك إعادة الجولة خلال ٣٠ دقيقة'), findsOneWidget);

    await tester.tap(find.text('نعم، ابدأ'));
    await tester.tap(find.text('لا، شكراً'));
    expect(yes, isTrue);
    expect(no, isTrue);
  });

  testWidgets('slides support back, progress, finish, skip, and close', (tester) async {
    var completed = false;
    var skipped = false;
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: GuideIntroSlides(
            scope: GuideScope.visitor,
            slides: const ['الشريحة الأولى', 'الشريحة الثانية'],
            onComplete: () => completed = true,
            onSkip: () => skipped = true,
            onClose: () => closed = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('الخطوة 1 من 2'), findsOneWidget);
    expect(find.text('الشريحة الأولى'), findsOneWidget);
    expect(find.text('رجوع'), findsOneWidget);
    final backButton = find
        .ancestor(of: find.text('رجوع'), matching: find.byType(TextButton))
        .last;
    expect(tester.widget<TextButton>(backButton).onPressed, isNull);

    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();
    expect(find.text('الخطوة 2 من 2'), findsOneWidget);
    expect(find.text('الشريحة الثانية'), findsOneWidget);
    expect(find.text('إنهاء الجولة'), findsOneWidget);

    await tester.tap(find.text('رجوع'));
    await tester.pumpAndSettle();
    expect(find.text('الشريحة الأولى'), findsOneWidget);

    await tester.tap(find.byTooltip('إغلاق'));
    expect(closed, isTrue);
    await tester.tap(find.text('تخطي الجولة'));
    expect(skipped, isTrue);

    // A fresh instance verifies the final action independently.
    await tester.pumpWidget(
      MaterialApp(
        home: GuideIntroSlides(
          scope: GuideScope.visitor,
          slides: const ['واحدة'],
          onComplete: () => completed = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('إنهاء الجولة'));
    expect(completed, isTrue);
  });
}
