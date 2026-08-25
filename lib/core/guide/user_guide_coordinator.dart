import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import 'guide_copy.dart';
import 'guide_host.dart';
import 'guide_intro.dart';
import 'guide_models.dart';
import 'guide_storage.dart';
import 'guide_target_registry.dart';

/// Coordinates the first-run tour for a signed-in regular user.
/// It starts only on the stable user home route and never invokes a business
/// callback; navigation remains owned by the existing bottom bar.
class UserGuideCoordinator {
  UserGuideCoordinator._();

  static const _route = '/user/home';
  static const _version = GuideStorage.contentVersion;

  static Future<void> maybeStart(BuildContext context, {bool force = false}) async {
    try {
      await _maybeStart(context, force: force);
    } catch (error, stack) {
      debugPrint('[GUIDE] user coordinator failed: $error');
      debugPrintStack(stackTrace: stack);
    }
  }

  static Future<void> _maybeStart(BuildContext context, {required bool force}) async {
    if (!context.mounted) return;
    final auth = context.read<AuthProvider>();
    final uid = auth.userModel?.uid.trim() ?? '';
    if (!auth.isLoggedIn || uid.isEmpty || auth.isBroker || auth.isInternal) return;

    final controller = GuideHost.maybeOf(context);
    final registry = GuideHost.maybeRegistryOf(context);
    if (controller == null || registry == null || controller.isDisposed) {
      debugPrint('[GUIDE] user start skipped: host/registry unavailable');
      return;
    }
    controller.attachContext(context);

    final storage = GuideStorage();
    final existing = storage.readRun(scope: GuideScope.user, uid: uid);
    if (!force && existing != null &&
        (existing.isComplete || existing.isSkipped || existing.isDeclined)) {
      if (!existing.isDeclined || existing.hasTemporaryHelp) return;
    }

    if (force) controller.cancelForRouteChange();
    if (!controller.beginSession(
      scope: GuideScope.user,
      uid: uid,
      role: auth.userModel!.role,
      route: _route,
      contentVersion: _version,
    )) return;

    var run = GuideRunState.initial(
      scope: GuideScope.user,
      uid: uid,
      role: auth.userModel!.role,
      route: _route,
      contentVersion: _version,
      stepIds: const [
        GuideStepIds.userOffers,
        GuideStepIds.userRequests,
        GuideStepIds.userAppointments,
      ],
    );

    Future<void> save({GuideRunStatus? status, String? stepId, GuideStepStatus? stepStatus}) async {
      if (stepId != null && run.steps.containsKey(stepId)) {
        final steps = Map<String, GuideStepState>.from(run.steps);
        final old = steps[stepId]!;
        final now = DateTime.now().toUtc();
        steps[stepId] = old.copyWith(
          status: stepStatus,
          shownAt: stepStatus == GuideStepStatus.shown ? now : null,
          completedAt: stepStatus == GuideStepStatus.completed ? now : null,
          skippedAt: stepStatus == GuideStepStatus.skipped ? now : null,
        );
        run = run.copyWith(steps: steps);
      }
      if (status != null) run = run.copyWith(status: status);
      await storage.saveRun(run);
    }

    Future<void> skip() async {
      await save(status: GuideRunStatus.skipped);
      if (!controller.isDisposed) controller.hide();
    }

    Future<void> showTarget(String id, String title, String message, int number,
        {required bool last, required VoidCallback next}) async {
      final snapshot = await _waitForTarget(registry, id);
      if (!context.mounted || snapshot?.ready != true) {
        await save(stepId: id, stepStatus: GuideStepStatus.retryable);
        controller.hide();
        return;
      }
      await save(status: GuideRunStatus.balloonsActive,
          stepId: id, stepStatus: GuideStepStatus.shown);
      controller.showStep(
        targetRect: snapshot!.rect!,
        title: title,
        message: message,
        roleLabel: GuideCopy.roleLabel(GuideScope.user),
        stepLabel: 'الخطوة $number من 3',
        isFirstStep: number == 1,
        isLastStep: last,
        onNext: () async {
          await save(stepId: id, stepStatus: GuideStepStatus.completed);
          await next();
        },
        onClose: () async {
          await save(stepId: id, stepStatus: GuideStepStatus.retryable);
          controller.hide();
        },
        onConfirmSkip: skip,
      );
    }

    Future<void> showAppointments() => showTarget(
          GuideStepIds.userAppointments,
          GuideCopy.userAppointmentsTitle,
          GuideCopy.userAppointmentsBody,
          3,
          last: true,
          next: () async {
            await save(status: GuideRunStatus.completed);
            controller.hide();
          },
        );
    Future<void> showRequests() => showTarget(
          GuideStepIds.userRequests,
          GuideCopy.userRequestsTitle,
          GuideCopy.userRequestsBody,
          2,
          last: false,
          next: showAppointments,
        );
    Future<void> showOffers() => showTarget(
          GuideStepIds.userOffers,
          GuideCopy.userOffersTitle,
          GuideCopy.userOffersBody,
          1,
          last: false,
          next: showRequests,
        );

    await save(status: GuideRunStatus.questionShown);
    final presented = controller.showWidget((_) => GuideQuestion(
          scope: GuideScope.user,
          onYes: () async {
            await save(status: GuideRunStatus.introActive);
            controller.showWidget((_) => GuideIntroSlides(
                  scope: GuideScope.user,
                  slides: GuideCopy.userIntroSlides,
                  onComplete: showOffers,
                  onSkip: skip,
                  onClose: () async {
                    await save(status: GuideRunStatus.skipped);
                    controller.hide();
                  },
                ));
          },
          onNo: () async {
            run = run.copyWith(
              status: GuideRunStatus.declined,
              helpUntil: DateTime.now().add(const Duration(minutes: 30)),
            );
            await storage.saveRun(run);
            await storage.saveHelpUntil(
                scope: GuideScope.user, uid: uid, until: run.helpUntil!);
            controller.hide();
          },
          onClose: () async {
            await save(status: GuideRunStatus.skipped);
            controller.hide();
          },
        ));
    if (!presented) debugPrint('[GUIDE] user question could not be presented');
  }

  static Future<GuideTargetSnapshot?> _waitForTarget(
      GuideTargetRegistry registry, String id) async {
    const delays = [Duration.zero, Duration(milliseconds: 16),
      Duration(milliseconds: 100), Duration(milliseconds: 300), Duration(milliseconds: 500)];
    for (final delay in delays) {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      final snapshot = registry.refresh(id);
      if (snapshot.ready) return snapshot;
    }
    return registry.snapshot(id);
  }
}
