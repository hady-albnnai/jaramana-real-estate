import 'package:flutter/widgets.dart';

import 'guide_copy.dart';
import 'guide_host.dart';
import 'guide_intro.dart';
import 'guide_models.dart';
import 'guide_storage.dart';
import 'guide_target_registry.dart';

/// Coordinates only the visitor guide. It is deliberately separate from the
/// visitor screen's data providers and never invokes a business callback.
class VisitorGuideCoordinator {
  VisitorGuideCoordinator._();

  static const _route = '/home';
  static const _role = 0;
  static const _version = GuideStorage.contentVersion;

  static Future<void> maybeStart(BuildContext context) async {
    if (!context.mounted) return;
    final controller = GuideHost.maybeOf(context);
    final registry = GuideHost.maybeRegistryOf(context);
    if (controller == null || registry == null || controller.isDisposed) return;

    final storage = GuideStorage();
    final existing = storage.readRun(scope: GuideScope.visitor);
    if (existing != null &&
        (existing.isComplete || existing.isSkipped || existing.isDeclined)) {
      if (!existing.isDeclined || existing.hasTemporaryHelp) return;
    }

    final started = controller.beginSession(
      scope: GuideScope.visitor,
      uid: '',
      role: _role,
      route: _route,
      contentVersion: _version,
    );
    if (!started) return;

    var run = GuideRunState.initial(
      scope: GuideScope.visitor,
      uid: '',
      role: _role,
      route: _route,
      contentVersion: _version,
      stepIds: const [
        GuideStepIds.visitorOffers,
        GuideStepIds.visitorFilters,
        GuideStepIds.visitorShare,
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

    Future<void> showFilters() async {
      final snapshot = await _waitForTarget(registry, GuideStepIds.visitorFilters);
      if (!context.mounted || snapshot?.ready != true) {
        await save(stepId: GuideStepIds.visitorFilters, stepStatus: GuideStepStatus.retryable);
        controller.hide();
        return;
      }
      await save(stepId: GuideStepIds.visitorFilters, stepStatus: GuideStepStatus.shown);
      controller.showStep(
        targetRect: snapshot!.rect!,
        title: GuideCopy.visitorFiltersTitle,
        message: GuideCopy.visitorFiltersBody,
        roleLabel: GuideCopy.roleLabel(GuideScope.visitor),
        stepLabel: 'الخطوة 2 من 2',
        isLastStep: true,
        onNext: () async {
          await save(status: GuideRunStatus.completed,
              stepId: GuideStepIds.visitorFilters, stepStatus: GuideStepStatus.completed);
          controller.hide();
        },
        onClose: () async {
          await save(stepId: GuideStepIds.visitorFilters, stepStatus: GuideStepStatus.retryable);
          controller.hide();
        },
        onConfirmSkip: skip,
      );
    }

    Future<void> showOffers() async {
      final snapshot = await _waitForTarget(registry, GuideStepIds.visitorOffers);
      if (!context.mounted || snapshot?.ready != true) {
        await save(stepId: GuideStepIds.visitorOffers, stepStatus: GuideStepStatus.retryable);
        controller.hide();
        return;
      }
      await save(status: GuideRunStatus.balloonsActive,
          stepId: GuideStepIds.visitorOffers, stepStatus: GuideStepStatus.shown);
      controller.showStep(
        targetRect: snapshot!.rect!,
        title: GuideCopy.visitorOffersTitle,
        message: GuideCopy.visitorOffersBody,
        roleLabel: GuideCopy.roleLabel(GuideScope.visitor),
        stepLabel: 'الخطوة 1 من 2',
        isFirstStep: true,
        onNext: () async {
          await save(stepId: GuideStepIds.visitorOffers, stepStatus: GuideStepStatus.completed);
          await showFilters();
        },
        onClose: () async {
          await save(stepId: GuideStepIds.visitorOffers, stepStatus: GuideStepStatus.retryable);
          controller.hide();
        },
        onConfirmSkip: skip,
      );
    }


    await save(status: GuideRunStatus.questionShown);
    controller.showWidget((overlayContext) => GuideQuestion(
      scope: GuideScope.visitor,
      onYes: () async {
        await save(status: GuideRunStatus.introActive);
        controller.showWidget((_) => GuideIntroSlides(
          scope: GuideScope.visitor,
          slides: GuideCopy.visitorIntroSlides,
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
        controller.hide();
      },
      onClose: () async {
        await save(status: GuideRunStatus.skipped);
        controller.hide();
      },
    ));
  }

  static Future<GuideTargetSnapshot?> _waitForTarget(
    GuideTargetRegistry registry,
    String id,
  ) async {
    const delays = [
      Duration.zero,
      Duration(milliseconds: 16),
      Duration(milliseconds: 100),
      Duration(milliseconds: 300),
      Duration(milliseconds: 500),
      Duration(milliseconds: 600),
    ];
    for (final delay in delays) {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      final snapshot = registry.refresh(id);
      if (snapshot.ready) return snapshot;
    }
    return registry.snapshot(id);
  }
}
