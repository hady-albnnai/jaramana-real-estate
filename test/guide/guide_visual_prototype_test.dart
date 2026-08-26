import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sweeda_real_estate/core/guide/guide_visual_prototype.dart';

void main() {
  testWidgets('renders the responsive guide bubble and controls', (tester) async {
    var nextPressed = false;
    var closed = false;
    var skipped = false;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar', 'SY'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: GuideVisualPrototype(
            targetRect: const Rect.fromLTWH(120, 180, 80, 48),
            title: 'إدارة العروض الخاصة بك',
            message: 'هنا تظهر العروض الخاصة بك وتتابع حالاتها.',
            roleLabel: 'جولة المستخدم',
            stepLabel: 'الخطوة 1 من 3',
            isFirstStep: true,
            onNext: () => nextPressed = true,
            onClose: () => closed = true,
            onConfirmSkip: () => skipped = true,
            child: const Scaffold(body: SizedBox.expand()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('إدارة العروض الخاصة بك'), findsOneWidget);
    expect(find.text('الخطوة 1 من 3'), findsOneWidget);
    expect(find.text('التالي'), findsOneWidget);
    expect(find.text('تخطي الجولة'), findsOneWidget);

    await tester.tap(find.text('التالي'));
    expect(nextPressed, isTrue);

    await tester.tap(find.bySemanticsLabel('إغلاق'));
    expect(closed, isTrue);

    await tester.tap(find.text('تخطي الجولة'));
    await tester.pumpAndSettle();
    expect(find.text('هل تريد تخطي الجولة؟'), findsOneWidget);
    await tester.tap(find.text('تخطي الجولة').last);
    expect(skipped, isTrue);
  });

  testWidgets('supports narrow layouts without a fixed card height', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: GuideVisualPrototype(
            targetRect: const Rect.fromLTWH(100, 80, 60, 40),
            title: 'مزايا الوسيط',
            message: 'بصفتك وسيطاً معتمداً يمكنك إدراج حتى خمسة عروض وخمسة طلبات.',
            child: const Scaffold(body: SizedBox.expand()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('مزايا الوسيط'), findsOneWidget);
    expect(tester.getSize(find.text('مزايا الوسيط')).height, greaterThan(0));
  });
}
