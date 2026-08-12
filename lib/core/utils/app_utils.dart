import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// أدوات مساعدة للتنسيق والتحقق
class AppUtils {
  static String formatPrice(num price, {int currency = 0}) {
    final formatter = NumberFormat('#,###');
    final symbol = currency == 0 ? '\$' : 'ل.س';
    return '${formatter.format(price)} $symbol';
  }

  /// تنسيق التاريخ فقط (yyyy/MM/dd)
  static String formatDate(dynamic ts) {
    return formatTimestamp(ts, pattern: 'yyyy/MM/dd');
  }

  /// تنسيق الوقت فقط (HH:mm)
  static String formatTime(dynamic ts) {
    return formatTimestamp(ts, pattern: 'HH:mm');
  }

  static String formatTimestamp(dynamic ts, {String pattern = 'yyyy/MM/dd'}) {
    if (ts == null) return '';
    DateTime date;
    if (ts is DateTime) {
      date = ts;
    } else if (ts is String) {
      try {
        date = DateTime.parse(ts);
      } catch (_) {
        return '';
      }
    } else {
      return '';
    }
    // محاولة العربية، وعند الفشل نستخدم الافتراضي
    try {
      return DateFormat(pattern, 'ar').format(date);
    } catch (_) {
      return DateFormat(pattern).format(date);
    }
  }

  static String offerStatusText(int status) {
    switch (status) {
      case 0: return 'مسودة';
      case 1: return 'قيد المراجعة';
      case 2: return 'منشور';
      case 3: return 'مرفوض';
      case 4: return 'منتهي';
      case 5: return 'محجوز';
      case 6: return 'مكتمل';
      default: return 'غير معروف';
    }
  }

  static String offerTypeText(int type) => type == 0 ? 'عقار' : 'سيارة';
  static String transactionText(int type) => type == 0 ? 'بيع' : 'إيجار';

  static String deedTypeText(int type, int offerType) {
    if (offerType == 0) { // عقار
      switch (type) {
        case 0: return 'طابو أخضر';
        case 1: return 'حصة سهمية-حكم محكمة';
        case 2: return 'حصة سهمية-كاتب بالعدل';
        case 3: return 'مستملك';
        case 4: return 'تسلسل عقود';
        case 5: return 'جمعيات سكنية';
        case 6: return 'نمرة قديمة';
        case 7: return 'نمرة جديدة';
        case 8: return 'وارد';
        default: return 'غير محدد';
      }
    } else { // سيارة
      switch (type) {
        case 0: return 'مواصلات نظامي';
        case 1: return 'حكم محكمة';
        case 2: return 'وارد مع تسلسل ملكية حصراً';
        default: return 'غير محدد';
      }
    }
  }

  /// عرض رقم الهاتف بالتنسيق المحلي (09xxxxxxxx) — يحذف +963
  static String displayPhone(String phone) {
    if (phone.isEmpty) return '';
    final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.startsWith('963') && digits.length == 12) {
      return '0${digits.substring(3)}';
    }
    if (phone.startsWith('+963')) {
      return '0${phone.substring(4)}';
    }
    return phone;
  }

  static bool isValidPhone(String phone) {
    return RegExp(r'^09\d{8}$').hasMatch(phone);
  }

  static String truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  /// عرض إشعار لطيف ومتحرك يطفو للأعلى لمدة ثانيتين عند اكتساب النقاط
  static void showPointsAwarded(BuildContext context, int points, {String label = 'نقاط مكافأة'}) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _FloatingPointsWidget(
        points: points,
        label: label,
        onFinish: () {
          if (entry.mounted) entry.remove();
        },
      ),
    );
    overlay.insert(entry);
  }
}

class _FloatingPointsWidget extends StatefulWidget {
  final int points;
  final String label;
  final VoidCallback onFinish;
  const _FloatingPointsWidget({required this.points, required this.label, required this.onFinish});

  @override
  State<_FloatingPointsWidget> createState() => _FloatingPointsWidgetState();
}

class _FloatingPointsWidgetState extends State<_FloatingPointsWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));
    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 15),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 30),
    ]).animate(_controller);

    _offset = Tween<Offset>(
      begin: const Offset(0, 30),
      end: const Offset(0, -60),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward().then((_) {
      if (mounted) widget.onFinish();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 120,
      left: 40,
      right: 40,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Opacity(
              opacity: _opacity.value,
              child: Transform.translate(
                offset: _offset.value,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primaryGold.withOpacity(0.95),
                          const Color(0xFFE5C158).withOpacity(0.95),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4)),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star, color: AppTheme.deepBlack, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          '+${widget.points} ${widget.label} 🔥',
                          style: const TextStyle(
                            color: AppTheme.deepBlack,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
