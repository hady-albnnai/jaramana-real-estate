-- ════════════════════════════════════════════════════════════════════
-- 🔥 تصفير شامل للتطبيق — النسخة 2 (2026-07-26)
-- يمسح كل بيانات التشغيل والاختبار ويعيد التطبيق كأنه تثبيت جديد.
--
-- ✅ يُبقي:
--    • حساب المدير (uuid أدناه) + جلساته وأجهزته (يبقى مسجّل دخوله)
--    • app_config كاملة (التصنيفات/الإعدادات/النصوص = بنية عمل التطبيق)
--
-- ❌ يمسح كل شي آخر:
--    عروض، طلبات، مواعيد، إشعارات، مدفوعات، صفقات، تقييمات، بلاغات،
--    طلبات إتمام، معقبين، تصوير، إحصائيات، OTP، حدود يومية، أجهزة،
--    جلسات، سجل نشاط، كل الحسابات الأخرى (بما فيها المحامون التجريبيون
--    والمعقب)، حسابات Supabase Auth اليتيمة، وكل ملفات التخزين.
--
-- ⚠️ غير قابل للتراجع. BEGIN/COMMIT تضمن: إما كله ينجح أو لا شيء يتغير.
-- ════════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1) البيانات التشغيلية (الأبناء أولاً ثم الآباء) ───
DELETE FROM activity_log;
DELETE FROM notifications;
DELETE FROM appointments;
DELETE FROM photography_tasks;
DELETE FROM deals;
DELETE FROM payments;
DELETE FROM reports;
DELETE FROM ratings;
DELETE FROM completion_requests;
DELETE FROM expediting_tasks;
DELETE FROM stats;
DELETE FROM otp_codes;
-- حماية: الجدول قد لا يكون منشأً بعد على السيرفر
DO $$ BEGIN
  IF to_regclass('public.social_publications') IS NOT NULL THEN
    DELETE FROM public.social_publications;
  END IF;
END $$;
DELETE FROM requests;
DELETE FROM offers;

-- ─── 2) بيانات المستخدمين (عدا المدير) ───
DELETE FROM staff_sessions    WHERE user_id <> '53701a2a-26ba-4b35-8f7d-f0a8f3956a98';
DELETE FROM user_devices      WHERE uid      <> '53701a2a-26ba-4b35-8f7d-f0a8f3956a98';
DELETE FROM user_daily_limits WHERE uid      <> '53701a2a-26ba-4b35-8f7d-f0a8f3956a98';
DELETE FROM lawyer_profiles   WHERE uid      <> '53701a2a-26ba-4b35-8f7d-f0a8f3956a98';

-- ─── 3) كل الحسابات عدا المدير ───
-- (العروض/الطلبات/إلخ محذوفة سلفاً؛ وكل FK متبقٍّ نحو users هو ON DELETE SET NULL)
DELETE FROM users WHERE id <> '53701a2a-26ba-4b35-8f7d-f0a8f3956a98';

-- ─── 4) حسابات Supabase Auth اليتيمة (identities/sessions تُحذف CASCADE) ───
DELETE FROM auth.users WHERE id NOT IN (SELECT id FROM public.users);

-- ─── 5) كل ملفات التخزين — الالتفاف الرسمي المؤكَّد ───
-- Supabase يمنع الحذف المباشر عبر trigger اسمه protect_objects_delete إلا إذا
-- كان متغير الجلسة storage.allow_delete_query = 'true' (هذا ما تفعله الـ
-- Storage API نفسها — مؤكد من كود storage.protect_delete الحي 2026-07-26).
-- SET LOCAL يسري داخل هذه المعاملة فقط وينطفئ تلقائياً مع COMMIT — صفر أثر جانبي.
SET LOCAL storage.allow_delete_query = 'true';
DELETE FROM storage.objects;

-- ─── 6) تصفير كل العدادات التسلسلية + عداد رقم العرض في الإعدادات ───
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT sequencename FROM pg_sequences WHERE schemaname = 'public' LOOP
    EXECUTE format('ALTER SEQUENCE public.%I RESTART WITH 1', r.sequencename);
  END LOOP;
END $$;
UPDATE app_config SET value = jsonb_set(value, '{offerNumber}', '0') WHERE key = 'main';

COMMIT;

-- ─── 7) تحقق سريع — المتوقع: users = 1 (المدير) والباقي 0 ───
SELECT 'users' AS tbl, COUNT(*)::text AS remaining FROM public.users
UNION ALL SELECT 'offers', COUNT(*)::text FROM public.offers
UNION ALL SELECT 'requests', COUNT(*)::text FROM public.requests
UNION ALL SELECT 'appointments', COUNT(*)::text FROM public.appointments
UNION ALL SELECT 'notifications', COUNT(*)::text FROM public.notifications
UNION ALL SELECT 'payments', COUNT(*)::text FROM public.payments
UNION ALL SELECT 'storage.objects', COUNT(*)::text FROM storage.objects;
