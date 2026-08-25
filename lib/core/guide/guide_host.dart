import 'package:flutter/material.dart';

import 'guide_controller.dart';
import 'guide_presenter.dart';

/// App-level lifecycle owner for the guide. It renders the original child
/// unchanged and provides one controller to future guide-aware screens.
class GuideHost extends StatefulWidget {
  const GuideHost({
    super.key,
    required this.child,
    this.controller,
  });

  final Widget child;
  final GuideController? controller;

  @override
  State<GuideHost> createState() => _GuideHostState();

  static GuideController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_GuideScope>();
    if (scope == null) {
      throw FlutterError('GuideHost.of() called without a GuideHost ancestor.');
    }
    return scope.controller;
  }
}

class _GuideHostState extends State<GuideHost> with WidgetsBindingObserver {
  late GuideController _controller;
  late bool _ownsController;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ??
        GuideController(presenter: OverlayEntryGuidePresenter());
    _ownsController = widget.controller == null;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.attachContext(context);
  }

  @override
  void didUpdateWidget(covariant GuideHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    if (_ownsController) _controller.dispose();
    _controller = widget.controller ??
        GuideController(presenter: OverlayEntryGuidePresenter());
    _ownsController = widget.controller == null;
    _controller.attachContext(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller.onLifecycleState(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _controller.attachContext(context);
    return _GuideScope(controller: _controller, child: widget.child);
  }
}

class _GuideScope extends InheritedNotifier<GuideController> {
  const _GuideScope({
    required GuideController controller,
    required Widget child,
  }) : super(notifier: controller, child: child);

  GuideController get controller => notifier!;
}
