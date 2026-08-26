import 'package:flutter/widgets.dart';

import 'guide_overlay.dart';

/// A small abstraction around the platform overlay primitive.
/// The controller never depends on OverlayEntry directly, so the primitive
/// can be replaced after the P4 visual/accessibility checks if needed.
abstract interface class GuidePresenter {
  bool get isShowing;

  void showWidget({
    required BuildContext context,
    required WidgetBuilder builder,
  });

  void show({
    required BuildContext context,
    required Rect targetRect,
    required String title,
    required String message,
    String? roleLabel,
    String? stepLabel,
    bool isFirstStep,
    bool isLastStep,
    String? actionLabel,
    VoidCallback? onBack,
    VoidCallback? onNext,
    VoidCallback? onClose,
    VoidCallback? onConfirmSkip,
    bool reduceMotion,
  });

  void hide();

  void dispose();
}

/// OverlayEntry implementation used by the first P4 prototype.
class OverlayEntryGuidePresenter implements GuidePresenter {
  OverlayEntry? _entry;

  @override
  bool get isShowing => _entry?.mounted ?? false;

  @override
  void showWidget({
    required BuildContext context,
    required WidgetBuilder builder,
  }) {
    hide();
    final overlay = Overlay.maybeOf(context, rootOverlay: true) ??
        Navigator.maybeOf(context, rootNavigator: true)?.overlay;
    if (overlay == null) {
      debugPrint('[GUIDE] no Navigator overlay available for widget');
      return;
    }
    final entry = OverlayEntry(builder: builder);
    _entry = entry;
    overlay.insert(entry);
  }

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
    String? actionLabel,
    VoidCallback? onBack,
    VoidCallback? onNext,
    VoidCallback? onClose,
    VoidCallback? onConfirmSkip,
    bool reduceMotion = false,
  }) {
    hide();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => GuideOverlay(
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
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  @override
  void hide() {
    final entry = _entry;
    _entry = null;
    entry?.remove();
    entry?.dispose();
  }

  @override
  void dispose() => hide();
}
