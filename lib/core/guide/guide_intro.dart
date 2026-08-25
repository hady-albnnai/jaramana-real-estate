import 'package:flutter/material.dart';

import 'guide_copy.dart';
import 'guide_models.dart';

/// First-run question. It is intentionally independent from routing and
/// persistence; GuideController wires its callbacks in a later phase.
class GuideQuestion extends StatelessWidget {
  const GuideQuestion({
    super.key,
    required this.scope,
    this.onYes,
    this.onNo,
    this.onClose,
  });

  final GuideScope scope;
  final VoidCallback? onYes;
  final VoidCallback? onNo;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return _GuideModalShell(
      roleLabel: GuideCopy.roleLabel(scope),
      title: GuideCopy.question(scope),
      onClose: onClose,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 22),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: onYes,
              style: _primaryButtonStyle(),
              child: const Text(GuideCopy.yes),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onNo,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 48),
              foregroundColor: const Color(0xFF6F6656),
              side: const BorderSide(color: Color(0xFFB8AE9B)),
            ),
            child: const Text(GuideCopy.no),
          ),
          const SizedBox(height: 6),
          const Text(
            GuideCopy.rejectionHint,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF6F6656),
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Text-only intro slides with adaptive layout and accessible progress.
class GuideIntroSlides extends StatefulWidget {
  const GuideIntroSlides({
    super.key,
    required this.scope,
    required this.slides,
    this.onComplete,
    this.onSkip,
    this.onClose,
  });

  final GuideScope scope;
  final List<String> slides;
  final VoidCallback? onComplete;
  final VoidCallback? onSkip;
  final VoidCallback? onClose;

  @override
  State<GuideIntroSlides> createState() => _GuideIntroSlidesState();
}

class _GuideIntroSlidesState extends State<GuideIntroSlides> {
  late final PageController _pageController;
  int _index = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _isLast => _index == widget.slides.length - 1;

  Future<void> _next() async {
    if (_busy || widget.slides.isEmpty) return;
    setState(() => _busy = true);
    try {
      if (_isLast) {
        widget.onComplete?.call();
        return;
      }
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _back() async {
    if (_busy || _index == 0) return;
    setState(() => _busy = true);
    try {
      await _pageController.previousPage(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.slides.isEmpty) return const SizedBox.shrink();
    return _GuideModalShell(
      roleLabel: GuideCopy.roleLabel(widget.scope),
      title: '',
      onClose: widget.onClose,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProgressIndicator(
            index: _index,
            total: widget.slides.length,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 250,
            child: PageView.builder(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.slides.length,
              onPageChanged: (value) => setState(() => _index = value),
              itemBuilder: (_, index) => SingleChildScrollView(
                child: Text(
                  widget.slides[index],
                  textAlign: TextAlign.start,
                  style: const TextStyle(
                    color: Color(0xFF6F6656),
                    fontSize: 16,
                    height: 1.6,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            textDirection: TextDirection.rtl,
            children: [
              TextButton(
                onPressed: _index == 0 || _busy ? null : _back,
                child: const Text(GuideCopy.back),
              ),
              const Spacer(),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _next,
                    style: _primaryButtonStyle(),
                    child: Text(_isLast ? GuideCopy.finish : GuideCopy.next),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: _busy ? null : widget.onSkip,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              foregroundColor: const Color(0xFF6F6656),
            ),
            child: const Text(GuideCopy.skip),
          ),
        ],
      ),
    );
  }
}

class _GuideModalShell extends StatelessWidget {
  const _GuideModalShell({
    required this.roleLabel,
    required this.title,
    required this.child,
    this.onClose,
  });

  final String roleLabel;
  final String title;
  final Widget child;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      scopesRoute: true,
      namesRoute: true,
      label: [roleLabel, if (title.isNotEmpty) title].join('. '),
      child: Material(
        color: Colors.transparent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ModalBarrier(
              color: Color.fromRGBO(0, 0, 0, 0.20),
              dismissible: false,
            ),
            Center(
              child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFD4AF37)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              roleLabel,
                              style: const TextStyle(
                                color: Color(0xFF8A6D1D),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (title.isNotEmpty)
                              Text(
                                title,
                                style: const TextStyle(
                                  color: Color(0xFF17130A),
                                  fontSize: 20,
                                  height: 1.3,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: GuideCopy.close,
                        child: IconButton(
                          tooltip: GuideCopy.close,
                          icon: const Icon(Icons.close, color: Color(0xFF6F6656)),
                          iconSize: 32,
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          padding: EdgeInsets.zero,
                          onPressed: onClose,
                        ),
                      ),
                    ],
                  ),
                  child,
                ],
              ),
            ),
          ),
        ),
        ],
      ),
    ),
  );
  }

  static ButtonStyle _primaryButtonStyle() => ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFD4AF37),
        foregroundColor: const Color(0xFF17130A),
        shape: const StadiumBorder(),
        minimumSize: const Size(48, 48),
      );
}

ButtonStyle _primaryButtonStyle() => _GuideModalShell._primaryButtonStyle();

class _ProgressIndicator extends StatelessWidget {
  const _ProgressIndicator({required this.index, required this.total});

  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'الخطوة ${index + 1} من $total',
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
          ...List.generate(
            total,
            (i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: i == index ? 10 : 8,
                height: i == index ? 10 : 8,
                decoration: BoxDecoration(
                  color: i == index
                      ? const Color(0xFF8A6D1D)
                      : const Color(0xFFD9C98A),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'الخطوة ${index + 1} من $total',
            style: const TextStyle(
              color: Color(0xFF6F6656),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      ),
    );
  }
}
