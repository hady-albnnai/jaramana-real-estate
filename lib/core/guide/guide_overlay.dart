import 'package:flutter/material.dart';

import 'guide_visual_prototype.dart';

/// Production-facing overlay widget for the guide layer.
///
/// The visual contract is kept in one place by delegating to the P0-tested
/// visual component. This widget adds no routing, auth, persistence, or
/// business behavior; the controller supplies those callbacks later.
class GuideOverlay extends StatelessWidget {
  const GuideOverlay({
    super.key,
    required this.targetRect,
    required this.title,
    required this.message,
    this.roleLabel,
    this.stepLabel,
    this.isFirstStep = false,
    this.isLastStep = false,
    this.actionLabel,
    this.onBack,
    this.onNext,
    this.onClose,
    this.onConfirmSkip,
    this.reduceMotion = false,
    this.child = const SizedBox.expand(),
  });

  final Rect targetRect;
  final String title;
  final String message;
  final String? roleLabel;
  final String? stepLabel;
  final bool isFirstStep;
  final bool isLastStep;
  final String? actionLabel;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final VoidCallback? onClose;
  final VoidCallback? onConfirmSkip;
  final bool reduceMotion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GuideVisualPrototype(
      targetRect: targetRect,
      title: title,
      message: message,
      roleLabel: roleLabel,
      stepLabel: stepLabel,
      isFirstStep: isFirstStep,
      isLastStep: isLastStep,
      actionLabel: actionLabel,
      onBack: onBack,
      onNext: onNext,
      onClose: onClose,
      onConfirmSkip: onConfirmSkip,
      reduceMotion: reduceMotion,
      child: child,
    );
  }
}
