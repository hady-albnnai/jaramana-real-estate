import 'package:flutter/material.dart';

import 'guide_controller.dart';
import 'guide_presenter.dart';
import 'guide_target_registry.dart';

/// App-level lifecycle owner for the guide. It renders the original child
/// unchanged and provides one controller to future guide-aware screens.
class GuideHost extends StatefulWidget {
  const GuideHost({
    super.key,
    required this.child,
    this.controller,
    this.registry,
  });

  final Widget child;
  final GuideController? controller;
  final GuideTargetRegistry? registry;

  @override
  State<GuideHost> createState() => _GuideHostState();

  static GuideController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_GuideScope>();
    if (scope == null) {
      throw FlutterError('GuideHost.of() called without a GuideHost ancestor.');
    }
    return scope.controller;
  }

  static GuideTargetRegistry registryOf(BuildContext context) {
    final registry = maybeRegistryOf(context);
    if (registry == null) {
      throw FlutterError('GuideHost.registryOf() called without a GuideHost ancestor.');
    }
    return registry;
  }

  static GuideTargetRegistry? maybeRegistryOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_GuideScope>()?.registry;
  }
}

class _GuideHostState extends State<GuideHost> with WidgetsBindingObserver {
  late GuideController _controller;
  late GuideTargetRegistry _registry;
  late bool _ownsController;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ??
        GuideController(presenter: OverlayEntryGuidePresenter());
    _registry = widget.registry ?? GuideTargetRegistry();
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
    if (oldWidget.controller != widget.controller) {
      if (_ownsController) _controller.dispose();
      _controller = widget.controller ??
          GuideController(presenter: OverlayEntryGuidePresenter());
      _ownsController = widget.controller == null;
      _controller.attachContext(context);
    }
    if (oldWidget.registry != widget.registry) {
      _registry = widget.registry ?? GuideTargetRegistry();
    }
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
    return _GuideScope(
      controller: _controller,
      registry: _registry,
      child: widget.child,
    );
  }
}

class _GuideScope extends InheritedNotifier<GuideController> {
  const _GuideScope({
    required GuideController controller,
    required this.registry,
    required super.child,
  }) : super(notifier: controller);

  final GuideTargetRegistry registry;

  GuideController get controller => notifier!;

  @override
  bool updateShouldNotify(covariant _GuideScope oldWidget) {
    return super.updateShouldNotify(oldWidget) || oldWidget.registry != registry;
  }
}
