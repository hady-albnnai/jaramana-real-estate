import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../utils/social_links.dart';

/// 📞💬 أزرار التواصل مع المكتب — اتصال + واتساب برقمين معتمدين (2026-09-22)
/// تُعرض تحت زر حجز المعاينة في شاشات العرض.
/// 🩹 2026-09-25: عند تمرير رقم العرض تُدرجه رسالة الواتساب تلقائياً.
/// 2026-09-28: الرقم الثاني المعتمد — زرا واتساب، كل زر يحمل رقمه بخط صغير.
class OfficeContactButtons extends StatelessWidget {
  const OfficeContactButtons({super.key, this.offerNumber});

  final int? offerNumber;

  /// الرقمان المعتمدان للمكتب — كلاهما واتساب (قرار المالك 2026-09-28).
  static const String officePhone = '0934222900';
  static const String officePhone2 = '0958750199';

  Future<void> _call() async {
    try {
      await launchUrl(Uri.parse('tel:$officePhone'),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _whatsapp(String phone) async {
    final num = SocialLinks.toWhatsAppNumber(phone);
    if (num.isEmpty) return;
    final text = Uri.encodeComponent(offerNumber == null
        ? 'مرحباً، أريد الاستفسار عن عرض في تطبيق المكتب العقاري الإلكتروني'
        : 'مرحباً، أريد الاستفسار عن العرض رقم #$offerNumber في تطبيق المكتب العقاري الإلكتروني');
    try {
      await launchUrl(Uri.parse('https://wa.me/$num?text=$text'),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  /// زر واتساب قابل لإعادة الاستخدام — يحمل الرقم تحت العنوان بخط صغير.
  Widget _waButton(String phone) {
    return Expanded(
      child: ElevatedButton.icon(
        onPressed: () => _whatsapp(phone),
        icon: const Icon(Icons.chat, size: 18),
        label: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('واتساب'),
            Text(phone,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9)),
          ],
        ),
      ),
    );
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
        _waButton(officePhone),
        AppTheme.gapWidthSmall,
        _waButton(officePhone2),
      ],
    );
  }
}