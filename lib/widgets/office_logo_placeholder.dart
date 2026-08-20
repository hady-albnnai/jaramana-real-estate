import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// 🏢 (2026-08-20): مكان الصورة الفاشلة/المفقودة — خلفية فاتحة بشعار المكتب
/// بدل المربع الأسود القديم (قرار المالك: توحيدها بشعار المكتب).
class OfficeLogoPlaceholder extends StatelessWidget {
  /// مقاس الشعار داخل المربع.
  final double logoSize;

  const OfficeLogoPlaceholder({super.key, this.logoSize = 26});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.inputBackground,
      alignment: Alignment.center,
      child: Image.asset(
        'assets/images/logo.png',
        width: logoSize,
        height: logoSize,
        fit: BoxFit.contain,
        // إن تعذّر تحميل الشعار نفسه لأي سبب: أيقونة مكتب بدل شاشة خطأ
        errorBuilder: (_, __, ___) => Icon(
          Icons.home_work_outlined,
          size: logoSize,
          color: AppTheme.primaryGold.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
