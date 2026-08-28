-- ══════════════════════════════════════════════════════════════════════════════
-- 2026-08-28: تجهيز التوزيع المباشر للتطبيق (بلا Google Play)
--
-- 1) فاحص التحديث: يضبط أحدث إصدار (1.1.0) + رابط التحميل الثابت لآخر إصدار
--    على GitHub Releases للمستودع العام sweeda-app
--    (https://github.com/<user>/<repo>/releases/latest/download/app-release.apk
--     يبقى ثابتاً دائماً ويشير لآخر APK مرفوع باسم app-release.apk).
--    المدير يحدّث رقم الإصدار لاحقاً من محرر الإعدادات مع كل إصدار جديد.
--
-- 2) صفحات السياسات: الروابط القديمة على hady-albnnai.github.io/sweeda-real-estate-office-elc
--    ميتة (404 — Pages غير مفعّل على المستودع الخاص). الجديدة تُستضاف على Pages
--    للمستودع العام sweeda-app بعد إنشائه وتفعيل Pages عليه.
--
-- ⚠️ الترتيب: أنشئ المستودع العام وفعّل Pages **قبل** تشغيل هذا الملف حتى لا
--    تبقى الروابط ميتة. idempotent: إعادة التشغيل تعيد نفس القيم.
-- ══════════════════════════════════════════════════════════════════════════════

-- روابط السياسات الجديدة (Pages للمستودع العام)
UPDATE public.app_config
SET value = jsonb_set(
      jsonb_set(
        value,
        '{txts,privacyPolicyUrl}',
        '"https://hady-albnnai.github.io/sweeda-app/legal/privacy-policy.html"'::jsonb,
        true
      ),
      '{txts,termsUrl}',
      '"https://hady-albnnai.github.io/sweeda-app/legal/terms-of-use.html"'::jsonb,
      true
    )
WHERE key = 'main';

-- فاحص التحديث: أحدث إصدار + رابط التحميل الثابت
UPDATE public.app_config
SET value = jsonb_set(
      jsonb_set(
        value,
        '{txts,appLatestVersion}',
        '"1.1.0"'::jsonb,
        true
      ),
      '{txts,appDownloadLink}',
        '"https://github.com/hady-albnnai/sweeda-app/releases/latest/download/app-release.apk"'::jsonb,
      true
    )
WHERE key = 'main';
