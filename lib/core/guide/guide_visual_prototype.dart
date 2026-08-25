import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A self-contained visual prototype for the guide bubble.
///
/// This widget intentionally has no knowledge of routing, authentication,
/// persistence, providers, or business actions. It is the P0 visual contract
/// that the later GuidePresenter/GuideController will render.
class GuideVisualPrototype extends StatefulWidget {
  const GuideVisualPrototype({
    super.key,
    required this.child,
    required this.targetRect,
    required this.title,
    required this.message,
    this.roleLabel,
    this.stepLabel,
    this.isFirstStep = false,
    this.isLastStep = false,
    this.onBack,
    this.onNext,
    this.onClose,
    this.onSkip,
    this.onConfirmSkip,
    this.overlayOpacity = 0.20,
    this.cardOpacity = 0.96,
    this.targetPadding = 6,
    this.cardRadius = 24,
    this.animationDuration = const Duration(milliseconds: 260),
    this.repositionDuration = const Duration(milliseconds: 220),
    this.reduceMotion = false,
  });

  final Widget child;
  final Rect targetRect;
  final String title;
  final String message;
  final String? roleLabel;
  final String? stepLabel;
  final bool isFirstStep;
  final bool isLastStep;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final VoidCallback? onClose;
  final VoidCallback? onSkip;
  final VoidCallback? onConfirmSkip;
  final double overlayOpacity;
  /// High-opacity target bubbles preserve the underlying context without
  /// allowing it to compete with Arabic body text.
  final double cardOpacity;
  final double targetPadding;
  final double cardRadius;
  final Duration animationDuration;
  final Duration repositionDuration;
  final bool reduceMotion;

  @override
  State<GuideVisualPrototype> createState() => _GuideVisualPrototypeState();
}

class _GuideVisualPrototypeState extends State<GuideVisualPrototype> {
  bool _showSkipConfirmation = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        _GuideBarrierAndSpotlight(
          targetRect: widget.targetRect,
          padding: widget.targetPadding,
          opacity: widget.overlayOpacity,
        ),
        _GuideBubbleLayer(
          targetRect: widget.targetRect,
          title: widget.title,
          message: widget.message,
          roleLabel: widget.roleLabel,
          stepLabel: widget.stepLabel,
          isFirstStep: widget.isFirstStep,
          isLastStep: widget.isLastStep,
          cardRadius: widget.cardRadius,
          cardOpacity: widget.cardOpacity,
          onBack: widget.onBack,
          onNext: widget.onNext,
          onClose: widget.onClose,
          onSkip: () => setState(() => _showSkipConfirmation = true),
          reduceMotion: widget.reduceMotion,
          animationDuration: widget.animationDuration,
          repositionDuration: widget.repositionDuration,
        ),
        if (_showSkipConfirmation)
          _SkipConfirmation(
            cardRadius: widget.cardRadius,
            onContinue: () => setState(() => _showSkipConfirmation = false),
            onSkip: () {
              setState(() => _showSkipConfirmation = false);
              widget.onConfirmSkip?.call();
            },
          ),
      ],
    );
  }
}

class _GuideBarrierAndSpotlight extends StatelessWidget {
  const _GuideBarrierAndSpotlight({
    required this.targetRect,
    required this.padding,
    required this.opacity,
  });

  final Rect targetRect;
  final double padding;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return BlockSemantics(
      child: IgnorePointer(
        ignoring: false,
        child: CustomPaint(
          painter: _SpotlightPainter(
            targetRect: targetRect,
            padding: padding,
            opacity: opacity,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({
    required this.targetRect,
    required this.padding,
    required this.opacity,
  });

  final Rect targetRect;
  final double padding;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    final overlayPaint = Paint()..color = Colors.black.withOpacity(opacity);
    canvas.drawRect(Offset.zero & size, overlayPaint);

    final highlight = targetRect.inflate(padding);
    final radius = math.min(16.0, highlight.shortestSide / 3);
    final clearPaint = Paint()..blendMode = BlendMode.clear;
    canvas.drawRRect(
      RRect.fromRectAndRadius(highlight, Radius.circular(radius)),
      clearPaint,
    );

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFFF9E4B7)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(highlight, Radius.circular(radius)),
      borderPaint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.padding != padding ||
        oldDelegate.opacity != opacity;
  }
}

class _GuideBubbleLayer extends StatelessWidget {
  const _GuideBubbleLayer({
    required this.targetRect,
    required this.title,
    required this.message,
    required this.roleLabel,
    required this.stepLabel,
    required this.isFirstStep,
    required this.isLastStep,
    required this.cardRadius,
    required this.cardOpacity,
    required this.onBack,
    required this.onNext,
    required this.onClose,
    required this.onSkip,
    required this.reduceMotion,
    required this.animationDuration,
    required this.repositionDuration,
  });

  final Rect targetRect;
  final String title;
  final String message;
  final String? roleLabel;
  final String? stepLabel;
  final bool isFirstStep;
  final bool isLastStep;
  final double cardRadius;
  final double cardOpacity;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final VoidCallback? onClose;
  final VoidCallback? onSkip;
  final bool reduceMotion;
  final Duration animationDuration;
  final Duration repositionDuration;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
        final media = MediaQuery.of(context);
        final safeTop = media.padding.top + 12;
        final safeBottom = media.padding.bottom + 12;
        final screen = Size(constraints.maxWidth, constraints.maxHeight);
        final cardWidth = _cardWidth(screen.width);
        final cardHeight = _estimatedCardHeight(screen.width);
        final placement = _placement(
          screen: screen,
          cardWidth: cardWidth,
          cardHeight: cardHeight,
          safeTop: safeTop,
          safeBottom: safeBottom,
        );

        final card = _BubbleCard(
          title: title,
          message: message,
          roleLabel: roleLabel,
          stepLabel: stepLabel,
          isFirstStep: isFirstStep,
          isLastStep: isLastStep,
          cardRadius: cardRadius,
          cardOpacity: cardOpacity,
          onBack: onBack,
          onNext: onNext,
          onClose: onClose,
          onSkip: onSkip,
        );

        final alignment = Alignment(
          ((placement.left + placement.width / 2) / screen.width * 2) - 1,
          ((placement.top + cardHeight / 2) / screen.height * 2) - 1,
        );

        final cardTop = placement.top;
        final cardBottom = placement.top + cardHeight;
        final cardCenterX = placement.left + placement.width / 2;
        final targetIsAbove = targetRect.bottom <= cardTop;

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _ArrowPainter(
                  targetRect: targetRect,
                  cardTop: cardTop,
                  cardBottom: cardBottom,
                  cardCenterX: cardCenterX,
                  targetIsAbove: targetIsAbove,
                  padding: targetRect.width > 0 ? 6 : 0,
                ),
              ),
            ),
            AnimatedAlign(
              duration: reduceMotion ? Duration.zero : repositionDuration,
              curve: Curves.easeOut,
              alignment: alignment,
              child: SizedBox(
              width: placement.width,
              child: FocusScope(
                autofocus: true,
                child: Semantics(
                  container: true,
                  explicitChildNodes: true,
                  scopesRoute: true,
                  namesRoute: true,
                  label: [
                    if (roleLabel != null) roleLabel!,
                    title,
                    message,
                    if (stepLabel != null) stepLabel!,
                  ].join('. '),
                  child: reduceMotion
                      ? card
                      : TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: animationDuration,
                          curve: Curves.easeOut,
                          builder: (context, value, child) => Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(0, 10 * (1 - value)),
                              child: child,
                            ),
                          ),
                          child: card,
                        ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
  }

  double _cardWidth(double screenWidth) {
    if (screenWidth < 360) return screenWidth - 24;
    if (screenWidth < 600) return screenWidth - 32;
    if (screenWidth < 900) return math.min(480, screenWidth - 48);
    return math.min(520, screenWidth - 64);
  }

  double _estimatedCardHeight(double screenWidth) {
    if (screenWidth < 360) return 300;
    if (screenWidth < 600) return 270;
    return 240;
  }

  _Placement _placement({
    required Size screen,
    required double cardWidth,
    required double cardHeight,
    required double safeTop,
    required double safeBottom,
  }) {
    final horizontal = (screen.width - cardWidth) / 2;
    final candidates = <_Placement>[
      _Placement(
        left: horizontal,
        top: targetRect.bottom + 16,
        width: cardWidth,
      ),
      _Placement(
        left: horizontal,
        top: targetRect.top - cardHeight - 16,
        width: cardWidth,
      ),
    ];

    for (final candidate in candidates) {
      final bottom = candidate.top + cardHeight;
      if (candidate.top >= safeTop && bottom <= screen.height - safeBottom) {
        return candidate;
      }
    }

    final clampedTop = (screen.height - safeBottom - cardHeight)
        .clamp(safeTop, screen.height - safeBottom)
        .toDouble();
    return _Placement(left: horizontal, top: clampedTop, width: cardWidth);
  }
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter({
    required this.targetRect,
    required this.cardTop,
    required this.cardBottom,
    required this.cardCenterX,
    required this.targetIsAbove,
    required this.padding,
  });

  final Rect targetRect;
  final double cardTop;
  final double cardBottom;
  final double cardCenterX;
  final bool targetIsAbove;
  final double padding;

  @override
  void paint(Canvas canvas, Size size) {
    if (targetRect.width <= 0 || targetRect.height <= 0) return;
    final paint = Paint()
      ..color = const Color(0xFFD4AF37)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final x = targetRect.center.dx;
    final start = targetIsAbove
        ? Offset(cardCenterX, cardTop)
        : Offset(cardCenterX, cardBottom);
    final end = targetIsAbove
        ? Offset(x, targetRect.bottom + padding)
        : Offset(x, targetRect.top - padding);
    canvas.drawLine(start, end, paint);

    // A small directional head makes the relationship unambiguous without
    // turning the spotlight into a noisy animation.
    final direction = (end - start);
    final length = direction.distance;
    if (length > 8) {
      final unit = direction / length;
      final perpendicular = Offset(-unit.dy, unit.dx);
      final headBase = end - unit * 8;
      final path = Path()
        ..moveTo(end.dx, end.dy)
        ..lineTo(
          headBase.dx + perpendicular.dx * 4,
          headBase.dy + perpendicular.dy * 4,
        )
        ..moveTo(end.dx, end.dy)
        ..lineTo(
          headBase.dx - perpendicular.dx * 4,
          headBase.dy - perpendicular.dy * 4,
        );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.cardTop != cardTop ||
        oldDelegate.cardBottom != cardBottom ||
        oldDelegate.cardCenterX != cardCenterX;
  }
}

class _Placement {
  const _Placement({required this.left, required this.top, required this.width});

  final double left;
  final double top;
  final double width;
}

class _BubbleCard extends StatelessWidget {
  const _BubbleCard({
    required this.title,
    required this.message,
    required this.roleLabel,
    required this.stepLabel,
    required this.isFirstStep,
    required this.isLastStep,
    required this.cardRadius,
    required this.cardOpacity,
    required this.onBack,
    required this.onNext,
    required this.onClose,
    required this.onSkip,
  });

  final String title;
  final String message;
  final String? roleLabel;
  final String? stepLabel;
  final bool isFirstStep;
  final bool isLastStep;
  final double cardRadius;
  final double cardOpacity;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final VoidCallback? onClose;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(minHeight: 190),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(cardOpacity.clamp(0.96, 1.0).toDouble()),
          borderRadius: BorderRadius.circular(cardRadius),
          border: Border.all(color: const Color(0xFFD4AF37), width: 1),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 16,
              spreadRadius: 0,
              offset: Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
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
                      if (roleLabel != null)
                        Text(
                          roleLabel!,
                          style: const TextStyle(
                            color: Color(0xFF8A6D1D),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF17130A),
                          fontSize: 19,
                          height: 1.3,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'إغلاق',
                  child: IconButton(
                    tooltip: 'إغلاق',
                    icon: const Icon(Icons.close, color: Color(0xFF6F6656)),
                    iconSize: 24,
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    padding: EdgeInsets.zero,
                    onPressed: onClose,
                  ),
                ),
              ],
            ),
            if (stepLabel != null) ...[
              const SizedBox(height: 4),
              Text(
                stepLabel!,
                style: const TextStyle(
                  color: Color(0xFF8A6D1D),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 10),
            SingleChildScrollView(
              child: Text(
                message,
                style: const TextStyle(
                  color: Color(0xFF6F6656),
                  fontSize: 16,
                  height: 1.55,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              textDirection: TextDirection.rtl,
              children: [
                if (onBack != null)
                  TextButton(
                    onPressed: isFirstStep ? null : onBack,
                    child: const Text('رجوع'),
                  ),
                const Spacer(),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: onNext,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD4AF37),
                        foregroundColor: const Color(0xFF17130A),
                        shape: const StadiumBorder(),
                      ),
                      child: Text(isLastStep ? 'إنهاء الجولة' : 'التالي'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: onSkip,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF6F6656),
                  minimumSize: const Size(48, 48),
                ),
                child: const Text('تخطي الجولة'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkipConfirmation extends StatelessWidget {
  const _SkipConfirmation({
    required this.cardRadius,
    required this.onContinue,
    required this.onSkip,
  });

  final double cardRadius;
  final VoidCallback onContinue;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        scopesRoute: true,
        namesRoute: true,
        label: 'هل تريد تخطي الجولة؟',
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(cardRadius),
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
              children: [
                const Text(
                  'هل تريد تخطي الجولة؟',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF17130A),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onContinue,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          side: const BorderSide(color: Color(0xFF6F6656)),
                          foregroundColor: const Color(0xFF6F6656),
                        ),
                        child: const Text('متابعة الجولة'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: onSkip,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          backgroundColor: const Color(0xFFB3261E),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('تخطي الجولة'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
