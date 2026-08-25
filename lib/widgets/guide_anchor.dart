import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../core/guide/guide_target_registry.dart';

/// Registers a real widget as a measurable guide target.
///
/// The anchor is intentionally passive: it does not change the child's
/// callbacks or semantics and never starts a guide by itself.
class GuideAnchor extends StatefulWidget {
  const GuideAnchor({
    super.key,
    required this.id,
    required this.registry,
    required this.child,
  });

  final String id;
  final GuideTargetRegistry registry;
  final Widget child;

  @override
  State<GuideAnchor> createState() => _GuideAnchorState();
}

class _GuideAnchorState extends State<GuideAnchor> {
  final GlobalKey _targetKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _registerAndRefresh());
  }

  @override
  void didUpdateWidget(covariant GuideAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.registry != widget.registry || oldWidget.id != widget.id) {
      oldWidget.registry.unregister(oldWidget.id);
      WidgetsBinding.instance.addPostFrameCallback((_) => _registerAndRefresh());
    }
  }

  void _registerAndRefresh() {
    if (!mounted) return;
    widget.registry.register(widget.id, (overlayContext) {
      final targetContext = _targetKey.currentContext;
      final targetObject = targetContext?.findRenderObject();
      if (targetObject is! RenderBox || !targetObject.hasSize) return null;
      final size = targetObject.size;
      if (size.width <= 0 || size.height <= 0) return null;

      final overlayObject = overlayContext?.findRenderObject();
      final topLeft = overlayObject is RenderBox
          ? targetObject.localToGlobal(Offset.zero, ancestor: overlayObject)
          : targetObject.localToGlobal(Offset.zero);
      return topLeft & size;
    });
    widget.registry.refresh(widget.id);
  }

  @override
  void dispose() {
    widget.registry.unregister(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _targetKey, child: widget.child);
  }
}
