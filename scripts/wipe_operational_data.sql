-- ══════════════════════════════════════════════════════════════════════════════
-- التنظيف الشامل لبيانات التشغيل — 2026-08-28 (طلب المالك)
--
-- «نضفلي التطبيق من كل شي فيه يعني اشعارات صور عروض اي شي بالتطبيق عدا
--  المستخدمين والموظفين»
--
-- ما يُحذف (يبقى):
--   • users بالكامل (كل المستخدمين والموظفين والأدوار والصلاحيات والتوثيق)
--   • auth.users (حسابات الدخول)
--   • app_config + internal_config + legal_finance_config
--   • staff_sessions (يبقى الجميع مسجل دخول)
--   • user_devices (استمرار الإشعارات)
--   • باكيت التخزين: ids_private (صور هويات الموظفين) + config_assets
--
-- ما يُحذف: كل جداول التشغيل الديناميكية (عروض، طلبات، مواعيد، صفقات،
-- دفعات، إشعارات، تصوير، استشارات، محادثات، تقارير، سجلات، OTP،
-- social_publications...) + ملفات باكيتات: offer_images، consultation_files،
-- expediting_docs، payment_proofs + تصفير الحقول التشغيلية للمستخدمين
-- (نقاط/شارة/باقة/إحصاءات/تتابع) مع إبقاء الهوية والدور والوساطة والتوثيق.
--
-- ⚠️ تنفيذ لمرة واحدة عبر -WipeData في deploy_supabase (ليس migration دائم
--   كي لا يعيد المسح مع كل نشر!).
-- ══════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1) تفريغ ديناميكي لكل جداول public عدا قائمة الإبقاء ──
-- (ديناميكي عمداً مثل مسح 2026-08-16: يغطي أي جدول تشغيلي حتى غير المذكور)
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT tablename
    FROM pg_tables
    WHERE schemaname = 'public'
      AND tablename NOT IN (
            'users',
            'app_config',
            'internal_config',
            'legal_finance_config',
            'staff_sessions',
            'user_devices'
          )
  LOOP
    EXECUTE format('TRUNCATE TABLE public.%I CASCADE', r.tablename);
  END LOOP;
END $$;

-- ── 2) ملفات التخزين التشغيلية (تبقى ids_private + config_assets) ──
DELETE FROM storage.objects
WHERE bucket_id IN ('offer_images', 'consultation_files', 'expediting_docs', 'payment_proofs');

-- ── 3) تصفير الحقول التشغيلية للمستخدمين (الهوية والأدوار كما هي) ──
UPDATE public.users SET
  pt = 0,
  bg = 0, bg_ts = NULL,
  b_pkg = 0, pkg_end = NULL, pkg_grace = NULL, pkg_xoff = 0,
  stats = '{"off":0,"req":0,"app":0,"dl":0}'::jsonb,
  wk_lgn = '[]'::jsonb,
  strk = 0, strk_dt = NULL;

COMMIT;

-- ── 4) تقرير التحقق بعد المسح ──
SELECT
  (SELECT count(*) FROM public.users) AS users_count,
  (SELECT count(*) FROM public.staff_sessions) AS staff_sessions_count,
  (SELECT count(*) FROM public.offers) AS offers_count,
  (SELECT count(*) FROM public.notifications) AS notifications_count,
  (SELECT count(*) FROM public.payments) AS payments_count,
  (SELECT count(*) FROM public.appointments) AS appointments_count,
  (SELECT count(*) FROM storage.objects WHERE bucket_id = 'offer_images') AS offer_images_files,
  (SELECT count(*) FROM storage.objects WHERE bucket_id = 'ids_private') AS staff_ids_files_kept,
  (SELECT count(*) FROM public.app_config) AS config_rows;
