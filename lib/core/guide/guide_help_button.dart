import 'dart:async';

import 'package:flutter/material.dart';

import 'guide_models.dart';
import 'guide_storage.dart';

/// Temporary, role-scoped help affordance shown after declining a guide.
class GuideHelpButton extends StatefulWidget {
  const GuideHelpButton({
    super.key,
    required this.scope,
    this.uid = '',
    required this.onPressed,
  });

  final GuideScope scope;
  final String uid;
  final VoidCallback onPressed;

  @override
  State<GuideHelpButton> createState() => _GuideHelpButtonState();
}

class _GuideHelpButtonState extends State<GuideHelpButton>
    with WidgetsBindingObserver {
  Timer? _expiryTimer;
  bool _active = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() {
    _expiryTimer?.cancel();
    final until = GuideStorage().readHelpUntil(
      scope: widget.scope,
      uid: widget.uid,
    );
    final active = until != null && until.isAfter(DateTime.now());
    if (mounted) setState(() => _active = active);
    if (active) {
      _expiryTimer = Timer(until!.difference(DateTime.now()), () {
        if (mounted) setState(() => _active = false);
      });
    }
  }

  @override
  void didUpdateWidget(covariant GuideHelpButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope || oldWidget.uid != widget.uid) {
      _refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_active) return const SizedBox.shrink();
    return Semantics(
      button: true,
      label: 'إعادة الجولة التعريفية',
      child: SizedBox(
        width: 48,
        height: 48,
        child: IconButton(
          tooltip: 'إعادة الجولة التعريفية',
          onPressed: widget.onPressed,
          padding: EdgeInsets.zero,
          icon: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFF9E4B7),
              border: Border.all(color: const Color(0xFF8A6D1D)),
            ),
            child: const Text(
              '?',
              style: TextStyle(
                color: Color(0xFF17130A),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
