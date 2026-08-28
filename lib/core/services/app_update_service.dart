import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../utils/social_links.dart';

/// 🔄 فاحص تحديث التطبيق (2026-08-28) — وضع التوزيع المباشر خارج Google Play:
/// لا يوجد تحديث تلقائي، لذا يقارن التطبيق إصداره بإصدار `txts.appLatestVersion`
/// الذي يحدّثه المدير مع كل إصدار جديد، ويعرض مرة واحدة عند الإقلاع نافذة
/// «تحديث جديد» بزر تحميل مباشر إلى `txts.appDownloadLink`
/// (رابط GitHub Releases الثابت latest/download).
class AppUpdateService {
  AppUpdateService._();

  /// مرة واحدة لكل جلسة — النافذة لا تُلح على المستخدم عند كل تنقل.
  static bool _shownThisSession = false;

  /// مقارنة إصدارات دلالية (1.2.10 > 1.2.9 > 1.2 > 1.1.5).
  /// تتجاهل أي لاحقة غير رقمية بسلام (مثل 1.1.0-beta).
  static bool isNewer(String latest, String current) {
    int parsePart(String s) => int.tryParse(s.trim()) ?? 0;
    List<int> parseVersion(String v) => (v.trim().split('+').first.split('-').first)
        .split('.')
        .map(parsePart)
        .toList();
    final l = parseVersion(latest);
    final c = parseVersion(current);
    for (var i = 0; i < 3; i++) {
      final li = i < l.length ? l[i] : 0;
      final ci = i < c.length ? c[i] : 0;
      if (li != ci) return li > ci;
    }
    return false;
  }

  /// يعرض نافذة التحديث إن توفر إصدار أحدث **ولم تُعرض الجلسة الحالية**.
  /// تُستدعى من شاشة البداية بعد تحميل الإعدادات وقبل التوجيه.
  static Future<void> showIfAvailable(
    BuildContext context,
    String latestVersion,
    String downloadLink,
  ) async {
    if (_shownThisSession) return;
    final latest = latestVersion.trim();
    final link = downloadLink.trim();
    if (latest.isEmpty || link.isEmpty) return; // المدير لم يفعّل الفاحص بعد
    if (!SocialLinks.isValidUrl(link)) return; // رابط غير آمن ⇒ لا نفتحه أبداً

    final info = await PackageInfo.fromPlatform();
    if (!isNewer(latest, info.version)) {
      _shownThisSession = true; // محدَّث — لا نعيد الفحص هذه الجلسة
      return;
    }
    if (!context.mounted) return;
    _shownThisSession = true;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('🔄 تحديث جديد متوفر',
            style: TextStyle(
                color: AppTheme.textWhite, fontWeight: FontWeight.bold)),
        content: Text(
          'صدر إصدار جديد من التطبيق ($latest) وأنت تستخدم ${info.version}.\n'
          'حدّث التطبيق لتحصل على أحدث الميزات والإصلاحات.',
          style: const TextStyle(
              color: AppTheme.textGrey, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('لاحقاً',
                style: TextStyle(color: AppTheme.textGrey)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGold),
            onPressed: () {
              Navigator.pop(dialogContext);
              _openDownloadLink(link);
            },
            icon: const Icon(Icons.download),
            label: const Text('تحميل الآن',
                style: TextStyle(
                    color: AppTheme.deepBlack,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  static Future<void> _openDownloadLink(String link) async {
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // المتصفح غير متوفر — تجاهل بصمت (الرابط يظهر أيضاً في «عن التطبيق»).
    }
  }
}
