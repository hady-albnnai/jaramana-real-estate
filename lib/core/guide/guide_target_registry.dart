import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// A measurable snapshot of a registered visual target.
class GuideTargetSnapshot {
  const GuideTargetSnapshot({
    required this.id,
    required this.ready,
    this.rect,
    this.generation = 0,
  });

  final String id;
  final bool ready;
  final Rect? rect;
  final int generation;
}

typedef GuideRectResolver = Rect? Function(BuildContext? overlayContext);

/// Central registry for visual targets. It owns no business logic and never
/// makes a target interactive; it only registers and measures it.
class GuideTargetRegistry extends ChangeNotifier {
  final Map<String, GuideRectResolver> _resolvers = {};
  final Map<String, GuideTargetSnapshot> _snapshots = {};
  int _generation = 0;

  Iterable<String> get ids => _resolvers.keys;

  void register(String id, GuideRectResolver resolver) {
    if (id.trim().isEmpty) return;
    _resolvers[id] = resolver;
    _snapshots[id] = GuideTargetSnapshot(id: id, ready: false);
    notifyListeners();
  }

  void unregister(String id) {
    _resolvers.remove(id);
    _snapshots.remove(id);
    notifyListeners();
  }

  GuideTargetSnapshot? snapshot(String id) => _snapshots[id];

  Rect? rectFor(String id, {BuildContext? overlayContext}) {
    final resolver = _resolvers[id];
    if (resolver == null) return null;
    return resolver(overlayContext);
  }

  GuideTargetSnapshot refresh(String id, {BuildContext? overlayContext}) {
    final resolver = _resolvers[id];
    if (resolver == null) {
      return GuideTargetSnapshot(id: id, ready: false);
    }

    final rect = resolver(overlayContext);
    final ready = rect != null &&
        rect.width > 0 &&
        rect.height > 0 &&
        rect.left.isFinite &&
        rect.top.isFinite &&
        rect.right.isFinite &&
        rect.bottom.isFinite;
    final snapshot = GuideTargetSnapshot(
      id: id,
      ready: ready,
      rect: ready ? rect : null,
      generation: ++_generation,
    );
    _snapshots[id] = snapshot;
    notifyListeners();
    return snapshot;
  }

  void refreshAll({BuildContext? overlayContext}) {
    for (final id in _resolvers.keys.toList()) {
      refresh(id, overlayContext: overlayContext);
    }
  }
}
