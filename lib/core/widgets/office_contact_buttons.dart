import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../utils/social_links.dart';

/// ☎💬 أزرار التواصل مع المكتب — اتصال + واتساب (2026-09-22)
/// تُعرض تحت زر حجز المعاينة في شاشات العروض.
/// 🩹 2026-09-25: عند تمرير رقم العرض تُدرجه رسالة الواتساب تلقائياً.
class OfficeContactButtons extends StatelessWidget {
  const OfficeContactButtons({super.key, this.offerNumber});

  final int? offerNumber;

  static const String officePhone = '0934222900';

  Future<void> _call() async {
    try {
      await launchUrl(Uri.parse('tel:$officePhone'),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _whatsapp() async {
    final num = SocialLinks.toWhatsAppNumber(officePhone);
    if (num.isEmpty) return;
    final text = Uri.encodeComponent(offerNumber == null
        ? 'مرحباً، أريد الاستفسار عن عرض في تطبيق المكتب العقاري الإلكتروني'
        : 'مرحباً، أريد الاستفسار عن العرض رقم #$offerNumber في تطبيق المكتب العقاري الإلكتروني');
    try {
      await launchUrl(Uri.parse('https://wa.me/$num?text=$text'),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _call,
            icon: const Icon(Icons.call, size: 18),
            label: const Text('اتصال'),
          ),
        ),
        AppTheme.gapWidthSmall,
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _whatsapp,
            icon: const Icon(Icons.chat, size: 18),
            label: const Text('واتساب'),
          ),
        ),
      ],
    );
  }
}