import 'package:flutter_test/flutter_test.dart';
import 'package:sweeda_real_estate/core/guide/guide_models.dart';
import 'package:sweeda_real_estate/core/guide/guide_storage.dart';

void main() {
  final storage = GuideStorage();

  test('creates isolated versioned keys for each scope', () {
    expect(
      storage.runKey(scope: GuideScope.visitor),
      'guide.v1.visitor.run',
    );
    expect(
      storage.runKey(scope: GuideScope.user, uid: 'u-1'),
      'guide.v1.user.u-1.run',
    );
    expect(
      storage.helpUntilKey(scope: GuideScope.broker, uid: 'b-1'),
      'guide.v1.broker.b-1.help_until',
    );
  });

  test('requires a uid for registered scopes', () {
    expect(
      () => storage.runKey(scope: GuideScope.user),
      throwsArgumentError,
    );
    expect(
      () => storage.helpUntilKey(scope: GuideScope.broker),
      throwsArgumentError,
    );
  });

  test('does not claim a save succeeded before Hive is ready', () async {
    final state = GuideRunState.initial(
      scope: GuideScope.visitor,
      uid: '',
      role: 0,
      route: '/home',
    );

    expect(await storage.saveRun(state), isFalse);
    expect(
      await storage.saveHelpUntil(
        scope: GuideScope.visitor,
        until: DateTime.utc(2026, 8, 23),
      ),
      isFalse,
    );
  });
}
