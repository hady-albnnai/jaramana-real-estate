import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/config_provider.dart';
import '../theme/app_theme.dart';
import '../utils/social_links.dart';

/// أزرار التواصل الرسمية للمكتب. الأرقام تأتي حصراً من إعدادات جرمانا.
class OfficeContactButtons extends StatelessWidget {
  const OfficeContactButtons({super.key, this.offerNumber});

  final int? offerNumber;

  Future<void> _call(String phone) async {
    if (phone.isEmpty) return;
    try {
      await launchUrl(Uri.parse('tel:$phone'), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _whatsapp(String phone) async {
    final number = SocialLinks.toWhatsAppNumber(phone);
    if (number.isEmpty) return;
    final text = Uri.encodeComponent(
      offerNumber == null
          ? 'مرحباً، أريد الاستفسار عن عرض في تطبيق المكتب العقاري الالكتروني - جرمانا'
          : 'مرحباً، أريد الاستفسار عن العرض رقم #$offerNumber في تطبيق المكتب العقاري الالكتروني - جرمانا',
    );
    try {
      await launchUrl(Uri.parse('https://wa.me/$number?text=$text'),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Widget _waButton(String phone) => Expanded(
        child: ElevatedButton.icon(
          onPressed: () => _whatsapp(phone),
          icon: const Icon(Icons.chat, size: 18),
          label: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('واتساب'),
              Text(phone, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9)),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final config = context.watch<ConfigProvider>().config;
    final contacts = <String>{
      (config?.contactWhatsApp ?? '').trim(),
      (config?.whatsapp2 ?? '').trim(),
    }.where((phone) => phone.isNotEmpty).toList();

    if (contacts.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _call(contacts.first),
            icon: const Icon(Icons.call, size: 18),
            label: const Text('اتصال'),
          ),
        ),
        AppTheme.gapWidthSmall,
        ...contacts.expand((phone) => <Widget>[
              _waButton(phone),
              if (phone != contacts.last) AppTheme.gapWidthSmall,
            ]),
      ],
    );
  }
}
