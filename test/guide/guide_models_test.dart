import 'package:flutter_test/flutter_test.dart';
import 'package:jaramana_real_estate/core/guide/guide_copy.dart';
import 'package:jaramana_real_estate/core/guide/guide_models.dart';

void main() {
  group('GuideScope and approved copy', () {
    test('keeps role scopes independent', () {
      expect(GuideScope.visitor.key, 'visitor');
      expect(GuideScope.user.key, 'user');
      expect(GuideScope.broker.key, 'broker');
      expect(GuideCopy.roleLabel(GuideScope.broker), 'جولة الوسيط');
      expect(GuideCopy.question(GuideScope.user), contains('وظائف حسابك'));
      expect(GuideCopy.userIntroSlides, hasLength(3));
    });

    test('maps stable step IDs to approved copy', () {
      expect(GuideCopy.titleFor(GuideStepIds.userOffers), 'إدارة العروض الخاصة بك');
      expect(GuideCopy.bodyFor(GuideStepIds.brokerBenefits), contains('خمسة عروض'));
      expect(GuideCopy.titleFor('unknown-step'), isEmpty);
    });
  });

  group('GuideLoadState', () {
    test('represents empty, stale, and retryable errors distinctly', () {
      const empty = GuideLoadState<String>.empty();
      const stale = GuideLoadState<String>.stale('old');
      const error = GuideLoadState<String>.error('failed');

      expect(empty.status, GuideLoadStatus.empty);
      expect(stale.status, GuideLoadStatus.stale);
      expect(stale.hasData, isTrue);
      expect(error.status, GuideLoadStatus.error);
      expect(error.retryable, isTrue);
    });
  });

  group('GuideRunState persistence', () {
    test('round trips a versioned user run', () {
      final now = DateTime.utc(2026, 8, 23, 12, 0);
      final state = GuideRunState.initial(
        scope: GuideScope.user,
        uid: 'user-1',
        role: 0,
        route: '/user/home',
        stepIds: const [GuideStepIds.userOffers, GuideStepIds.userRequests],
      ).copyWith(
        status: GuideRunStatus.balloonsActive,
        currentStepId: GuideStepIds.userOffers,
        steps: {
          GuideStepIds.userOffers: GuideStepState(
            stepId: GuideStepIds.userOffers,
            status: GuideStepStatus.shown,
            contentVersion: 'guide.v1',
            shownAt: now,
          ),
          GuideStepIds.userRequests: GuideStepState.pending(
            GuideStepIds.userRequests,
            'guide.v1',
          ),
        },
      );

      final decoded = GuideRunState.fromJson(state.toJson());
      expect(decoded.scope, GuideScope.user);
      expect(decoded.uid, 'user-1');
      expect(decoded.status, GuideRunStatus.balloonsActive);
      expect(decoded.currentStepId, GuideStepIds.userOffers);
      expect(decoded.steps[GuideStepIds.userOffers]?.status, GuideStepStatus.shown);
      expect(decoded.steps[GuideStepIds.userOffers]?.shownAt, now);
    });

    test('uses safe defaults for malformed enum values', () {
      final state = GuideRunState.fromJson({
        'scope': 'invalid',
        'status': 'invalid',
        'steps': [
          {'stepId': 'x', 'status': 'invalid', 'contentVersion': 'guide.v1'},
        ],
      });

      expect(state.scope, GuideScope.visitor);
      expect(state.status, GuideRunStatus.notStarted);
      expect(state.steps['x']?.status, GuideStepStatus.pending);
    });
  });

  test('session token changes when generation changes', () {
    final first = GuideSessionToken(
      scope: GuideScope.broker,
      uid: 'b-1',
      role: 1,
      route: '/broker/dashboard',
      contentVersion: 'guide.v1',
      generation: 1,
    );
    final second = GuideSessionToken(
      scope: GuideScope.broker,
      uid: 'b-1',
      role: 1,
      route: '/broker/dashboard',
      contentVersion: 'guide.v1',
      generation: 2,
    );

    expect(first.matches(second), isFalse);
  });
}
