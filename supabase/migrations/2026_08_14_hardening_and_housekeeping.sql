-- تحصين §7 متمّم: set_consultation_expiry دالة trigger (بلا معاملات) وكانت
-- الوحيدة القابلة للتنفيذ من anon/authenticated. غير قابلة للاستغلال عملياً
-- (تعمل على NEW داخل السياق)، لكن نُغلقها التزاماً بالقاعدة الرباعية.
REVOKE ALL ON FUNCTION public.set_consultation_expiry() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.set_consultation_expiry() FROM anon, authenticated;
-- ============================================================================
-- SEC-006 — إزالة منح الكتابة الزائدة عن anon و authenticated
-- ============================================================================
-- الوضع المكتشَف (2026-08-14): anon و authenticated يملكان:
--   • TRUNCATE على 22 جدولاً (منها users · payments · staff_sessions · deals)
--   • INSERT/UPDATE/DELETE على 5 جداول (expediting_tasks · fraud_suspects ·
--     lawyer_profiles · legal_consultations · users_public)
--
-- ⚠️ لا اختراق فعلي اليوم: RLS يحجب الصفوف (أُكِّد حياً — UPDATE على
-- expediting_tasks أعاد [] ولم يغيّر شيئاً، وINSERT في users_public رُفض
-- 42501). لكن هذا **خط دفاع مفقود**: المنح والـRLS طبقتان مستقلتان، وأي
-- سياسة تُضاف مستقبلاً بحسن نية (مثل «اسمح للمستخدم بتعديل صفّه») تفتح
-- الباب فوراً لأن طبقة المنح لا تعترض.
--
-- ولا مبرر لأيٍّ منها: **كل** الكتابة في هذا التطبيق تمرّ عبر Edge Functions
-- بمفتاح الخدمة (staff_session_token)، لا عبر REST المباشر — تحقُّق: التطبيق
-- يستخدم REST للقراءة فقط عدا ratings.insert (وهي عبر سياسة صريحة).
--
-- TRUNCATE تحديداً كارثي: أمر واحد يمسح جدولاً كاملاً ويتجاوز RLS تماماً
-- (TRUNCATE لا يخضع لسياسات الصفوف!). وجوده لدور عام خطأ جسيم.
-- ============================================================================

DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT DISTINCT table_name
    FROM information_schema.role_table_grants
    WHERE table_schema = 'public'
      AND grantee IN ('anon','authenticated')
      AND privilege_type IN ('INSERT','UPDATE','DELETE','TRUNCATE')
  LOOP
    EXECUTE format(
      'REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.%I FROM anon, authenticated',
      r.table_name);
  END LOOP;
END $$;

-- استثناء مقصود: التقييمات تُكتب من التطبيق مباشرة عبر سياسة RLS صريحة
-- (rating_dialog.dart → ratings.insert). نُعيد INSERT وحده لها.
GRANT INSERT ON public.ratings TO authenticated;
-- ============================================================================
-- PERF-001 — فهارس مفقودة على جداول القسم القانوني
-- ============================================================================
-- الوضع: legal_consultations و expediting_tasks لا تحملان سوى فهرس المفتاح
-- الأساسي، بينما **كل** استعلامات لوحة المحامي وشاشة المعقّب تصفّي بـ
-- lawyer_uid / expediter_uid / user_uid / status ⇒ مسح كامل للجدول في كل
-- فتحة شاشة. غير محسوس اليوم (عشرات الصفوف) لكنه يتدهور خطياً مع النمو،
-- وهو أرخص إصلاح ممكن (ثوانٍ الآن، ساعات لاحقاً على جدول ممتلئ).
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_legal_cons_lawyer
  ON public.legal_consultations (lawyer_uid, status, ts_crt DESC);

CREATE INDEX IF NOT EXISTS idx_legal_cons_user
  ON public.legal_consultations (user_uid, ts_crt DESC);

CREATE INDEX IF NOT EXISTS idx_legal_cons_status
  ON public.legal_consultations (status)
  WHERE status IN (0, 1, 5);

CREATE INDEX IF NOT EXISTS idx_expediting_expediter
  ON public.expediting_tasks (expediter_uid, status);

CREATE INDEX IF NOT EXISTS idx_expediting_lawyer
  ON public.expediting_tasks (lawyer_uid, status);
-- ============================================================================
-- PERF-002 — صيانة دورية للجداول المتراكمة
-- ============================================================================
-- الوضع المكتشَف (2026-08-14):
--   • staff_sessions: 714 صفاً منذ 2026-06-16 — جلسات منتهية/ملغاة لا تُحذف
--     أبداً. الجدول 312 kB وهو من أكثر ما يُستعلَم (كل نداء API يمرّ عليه
--     عبر validate_staff_session التي تدور على كل جلسات المستخدم).
--   • otp_codes: كل الرموز منتهية ولا تُنظَّف.
--   • activity_log و notifications: بلا سقف زمني.
-- الأثر: تباطؤ تدريجي في كل نداء، وتضخّم نسخ احتياطية بلا فائدة.
-- الحل: مهمة يومية واحدة تحذف ما انتهت الحاجة إليه، مع إبقاء نافذة معقولة
-- للتدقيق (سجل الإدارة 180 يوماً، الإشعارات 90 يوماً بعد القراءة).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.daily_housekeeping()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $fn$
DECLARE
  v_sessions INT := 0;
  v_otp      INT := 0;
  v_notif    INT := 0;
  v_log      INT := 0;
  v_views    INT := 0;
  v_logins   INT := 0;
BEGIN
  -- الجلسات: المنتهية أو الملغاة منذ أكثر من 7 أيام
  DELETE FROM public.staff_sessions
  WHERE (revoked = 1 OR expires_at < NOW())
    AND COALESCE(last_used_at, created_at) < NOW() - INTERVAL '7 days';
  GET DIAGNOSTICS v_sessions = ROW_COUNT;

  -- رموز التحقق: المنتهية منذ أكثر من يوم
  DELETE FROM public.otp_codes
  WHERE expires_at < NOW() - INTERVAL '1 day';
  GET DIAGNOSTICS v_otp = ROW_COUNT;

  -- الإشعارات المقروءة الأقدم من 90 يوماً (غير المقروءة تبقى)
  DELETE FROM public.notifications
  WHERE i_rd = 1 AND ts_crt < NOW() - INTERVAL '90 days';
  GET DIAGNOSTICS v_notif = ROW_COUNT;

  -- سجل التدقيق: نافذة 180 يوماً
  DELETE FROM public.activity_log
  WHERE ts_crt < NOW() - INTERVAL '180 days';
  GET DIAGNOSTICS v_log = ROW_COUNT;

  -- سجل المشاهدات: يومان يكفيان لنافذة التهدئة
  DELETE FROM public.offer_view_log
  WHERE ts_crt < NOW() - INTERVAL '2 days';
  GET DIAGNOSTICS v_views = ROW_COUNT;

  -- محاولات الدخول: 24 ساعة
  DELETE FROM public.login_attempts
  WHERE ts_crt < NOW() - INTERVAL '24 hours';
  GET DIAGNOSTICS v_logins = ROW_COUNT;

  RETURN jsonb_build_object(
    'success', true, 'ts', NOW(),
    'sessions', v_sessions, 'otp', v_otp, 'notifications', v_notif,
    'activity_log', v_log, 'offer_views', v_views, 'login_attempts', v_logins
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.daily_housekeeping() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.daily_housekeeping() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.daily_housekeeping() TO service_role;

SELECT cron.unschedule('daily-housekeeping')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'daily-housekeeping');

SELECT cron.schedule('daily-housekeeping', '50 3 * * *',
  $$SELECT public.daily_housekeeping();$$);
