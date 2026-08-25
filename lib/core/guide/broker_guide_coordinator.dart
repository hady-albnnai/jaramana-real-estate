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

/// Coordinates the short first-entry tour for an approved broker.
/// The broker tour intentionally has one benefit balloon, not a repetition of
/// the regular user's tour.
class BrokerGuideCoordinator {
  BrokerGuideCoordinator._();

  static const _route = '/broker/dashboard';
  static const _version = GuideStorage.contentVersion;

  static Future<void> maybeStart(BuildContext context, {bool force = false}) async {
    try {
      await _maybeStart(context, force: force);
    } catch (error, stack) {
      debugPrint('[GUIDE] broker coordinator failed: $error');
      debugPrintStack(stackTrace: stack);
    }
  }

  static Future<void> _maybeStart(BuildContext context, {required bool force}) async {
    if (!context.mounted) return;
    final auth = context.read<AuthProvider>();
    final uid = auth.userModel?.uid.trim() ?? '';
    if (!auth.isLoggedIn || !auth.isBroker || uid.isEmpty) return;

    final controller = GuideHost.maybeOf(context);
    final registry = GuideHost.maybeRegistryOf(context);
    if (controller == null || registry == null || controller.isDisposed) return;
    controller.attachContext(context);

    final storage = GuideStorage();
    final existing = storage.readRun(scope: GuideScope.broker, uid: uid);
    if (!force && existing != null &&
        (existing.isComplete || existing.isSkipped || existing.isDeclined)) {
      if (!existing.isDeclined || existing.hasTemporaryHelp) return;
    }
    if (force) controller.cancelForRouteChange();
    if (!controller.beginSession(
      scope: GuideScope.broker,
      uid: uid,
      role: auth.userModel!.role,
      route: _route,
      contentVersion: _version,
    )) {
      return;
    }

    var run = GuideRunState.initial(
      scope: GuideScope.broker,
      uid: uid,
      role: auth.userModel!.role,
      route: _route,
      contentVersion: _version,
      stepIds: const [GuideStepIds.brokerSections],
    );

    Future<void> save({GuideRunStatus? status, GuideStepStatus? stepStatus}) async {
      if (stepStatus != null) {
        final old = run.steps[GuideStepIds.brokerSections]!;
        final now = DateTime.now().toUtc();
        run = run.copyWith(steps: {
          ...run.steps,
          GuideStepIds.brokerSections: old.copyWith(
            status: stepStatus,
            shownAt: stepStatus == GuideStepStatus.shown ? now : null,
            completedAt: stepStatus == GuideStepStatus.completed ? now : null,
          ),
        });
      }
      if (status != null) run = run.copyWith(status: status);
      await storage.saveRun(run);
    }

    Future<void> skip() async {
      await save(status: GuideRunStatus.skipped);
      if (!controller.isDisposed) controller.hide();
    }

    Future<void> showBenefits() async {
      final snapshot = await _waitForTarget(registry, GuideStepIds.brokerSections);
      if (!context.mounted || snapshot?.ready != true) {
        await save(stepStatus: GuideStepStatus.retryable);
        controller.hide();
        return;
      }
      await save(status: GuideRunStatus.balloonsActive,
          stepStatus: GuideStepStatus.shown);
      controller.showStep(
        targetRect: snapshot!.rect!,
        title: GuideCopy.brokerBenefitsTitle,
        message: GuideCopy.brokerBenefitsBody,
        roleLabel: GuideCopy.roleLabel(GuideScope.broker),
        isFirstStep: true,
        isLastStep: true,
        actionLabel: GuideCopy.understood,
        onNext: () async {
          await save(status: GuideRunStatus.completed,
              stepStatus: GuideStepStatus.completed);
          controller.hide();
        },
        onClose: () async {
          await save(stepStatus: GuideStepStatus.retryable);
          controller.hide();
        },
        onConfirmSkip: skip,
      );
    }

    await save(status: GuideRunStatus.questionShown);
    controller.showWidget((_) => GuideQuestion(
          scope: GuideScope.broker,
          onYes: () async {
            await showBenefits();
          },
          onNo: () async {
            run = run.copyWith(
              status: GuideRunStatus.declined,
              helpUntil: DateTime.now().add(const Duration(minutes: 30)),
            );
            await storage.saveRun(run);
            await storage.saveHelpUntil(
                scope: GuideScope.broker, uid: uid, until: run.helpUntil!);
            controller.hide();
          },
          onClose: () async {
            await save(status: GuideRunStatus.skipped);
            controller.hide();
          },
        ));
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
