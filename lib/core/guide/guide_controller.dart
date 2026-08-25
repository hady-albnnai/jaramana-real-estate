import 'package:flutter/widgets.dart';

import 'guide_models.dart';
import 'guide_presenter.dart';

/// The single owner of a guide run and its visual presenter.
///
/// It deliberately does not know about providers, business actions, or
/// concrete screens. Later phases will feed it role- and route-specific steps.
class GuideController extends ChangeNotifier {
  GuideController({required GuidePresenter presenter}) : _presenter = presenter;

  final GuidePresenter _presenter;
  GuideSessionToken? _sessionToken;
  bool _suspended = false;
  bool _disposed = false;
  int _generation = 0;
  VoidCallback? _replayPresentation;

  GuideSessionToken? get sessionToken => _sessionToken;
  bool get isSuspended => _suspended;
  bool get isDisposed => _disposed;
  bool get isShowing => _presenter.isShowing;

  /// Starts a new logical session only when it is different from the active
  /// one. This makes initialSession/signedIn/rebuild idempotent.
  bool beginSession({
    required GuideScope scope,
    required String uid,
    required int role,
    required String route,
    String contentVersion = 'guide.v1',
  }) {
    if (_disposed) return false;
    final current = _sessionToken;
    if (current != null &&
        current.scope == scope &&
        current.uid == uid &&
        current.role == role &&
        current.route == route &&
        current.contentVersion == contentVersion) {
      return false;
    }
    final next = GuideSessionToken(
      scope: scope,
      uid: uid,
      role: role,
      route: route,
      contentVersion: contentVersion,
      generation: ++_generation,
    );
    _replayPresentation = null;
    if (_presenter.isShowing) _presenter.hide();
    _sessionToken = next;
    _suspended = false;
    notifyListeners();
    return true;
  }

  /// Shows a question or intro widget through the same presenter.
  bool showWidget(WidgetBuilder builder) {
    if (_disposed || _sessionToken == null) return false;
    final context = _contextForPresentation;
    if (context == null) return false;
    _replayPresentation = () {
      final currentContext = _contextForPresentation;
      if (currentContext != null && !_disposed && !_suspended) {
        _presenter.showWidget(context: currentContext, builder: builder);
      }
    };
    _replayPresentation!.call();
    notifyListeners();
    return true;
  }

  /// Shows one already-approved step. Progression and persistence are added
  /// by the later state-machine phase; this method only owns presentation.
  bool showStep({
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
    if (_disposed || _sessionToken == null) return false;
    final context = _contextForPresentation;
    if (context == null) return false;
    _replayPresentation = () {
      final currentContext = _contextForPresentation;
      if (currentContext == null || _disposed || _suspended) return;
      _presenter.show(
        context: currentContext,
        targetRect: targetRect,
        title: title,
        message: message,
        roleLabel: roleLabel,
        stepLabel: stepLabel,
        isFirstStep: isFirstStep,
        isLastStep: isLastStep,
        onBack: onBack,
        onNext: onNext,
        onClose: onClose,
        onConfirmSkip: onConfirmSkip,
        reduceMotion: reduceMotion,
      );
    };
    _replayPresentation!.call();
    notifyListeners();
    return true;
  }

  // Set by GuideHost before this controller is used. Kept private so screens
  // cannot replace the host context or bypass the central owner.
  BuildContext? _contextForPresentation;
  void attachContext(BuildContext context) => _contextForPresentation = context;

  void hide() {
    if (_disposed) return;
    _replayPresentation = null;
    _presenter.hide();
    notifyListeners();
  }

  void cancelForRouteChange() {
    if (_disposed) return;
    _presenter.hide();
    _sessionToken = null;
    _suspended = false;
    notifyListeners();
  }

  void cancelForAuthChange() => cancelForRouteChange();

  void onLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _suspended = false;
        if (_replayPresentation != null && !_presenter.isShowing) {
          _replayPresentation!.call();
        }
        notifyListeners();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _suspended = true;
        _presenter.hide();
        notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _presenter.dispose();
    _sessionToken = null;
    _contextForPresentation = null;
    super.dispose();
  }
}
