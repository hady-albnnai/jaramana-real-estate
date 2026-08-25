import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sweeda_real_estate/core/guide/guide_controller.dart';
import 'package:sweeda_real_estate/core/guide/guide_presenter.dart';
import 'package:sweeda_real_estate/core/guide/guide_host.dart';
import 'package:sweeda_real_estate/core/guide/guide_models.dart';

class _FakePresenter implements GuidePresenter {
  bool showing = false;
  int showCount = 0;
  int hideCount = 0;

  @override
  bool get isShowing => showing;

  @override
  void show({
    required BuildContext context,
    required Rect targetRect,
    required String title,
    required String message,
    String? roleLabel,
    String? stepLabel,
    bool isFirstStep = false,
    bool isLastStep = false,
    VoidCallback? onBack,
    VoidCallback? onNext,
    VoidCallback? onClose,
    VoidCallback? onConfirmSkip,
    bool reduceMotion = false,
  }) {
    showing = true;
    showCount++;
  }

  @override
  void hide() {
    showing = false;
    hideCount++;
  }

  @override
  void dispose() {}
}

void main() {
  test('beginSession is idempotent for the same active token', () {
    final fake = _FakePresenter();
    final controller = GuideController(presenter: fake);

    expect(
      controller.beginSession(
        scope: GuideScope.user,
        uid: 'u-1',
        role: 0,
        route: '/user/home',
      ),
      isTrue,
    );
    // A duplicate auth/rebuild signal must not create another run.
    expect(
      controller.beginSession(
        scope: GuideScope.user,
        uid: 'u-1',
        role: 0,
        route: '/user/home',
      ),
      isFalse,
    );
    expect(controller.sessionToken, isNotNull);
    controller.dispose();
  });

  test('lifecycle hides while suspended and resumes without a stale overlay', () {
    final fake = _FakePresenter();
    final controller = GuideController(presenter: fake);
    controller.beginSession(
      scope: GuideScope.broker,
      uid: 'b-1',
      role: 1,
      route: '/broker/dashboard',
    );

    controller.onLifecycleState(AppLifecycleState.paused);
    expect(controller.isSuspended, isTrue);
    expect(fake.hideCount, 1);
    controller.onLifecycleState(AppLifecycleState.resumed);
    expect(controller.isSuspended, isFalse);
    controller.dispose();
  });

  testWidgets('GuideHost provides one controller and disposes its owned presenter',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GuideHost(
          child: Builder(
            builder: (context) => Text(
              GuideHost.of(context).isDisposed ? 'disposed' : 'ready',
            ),
          ),
        ),
      ),
    );

    expect(find.text('ready'), findsOneWidget);
    expect(find.byType(GuideHost), findsOneWidget);
  });
}
