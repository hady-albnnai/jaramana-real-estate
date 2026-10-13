-- ============================================================================
-- 2026_08_15 — LAW-001: إنشاء ملف المحامي تلقائياً + ردم الملفات الناقصة
-- ============================================================================
-- اكتُشف أثناء اختبار المالك الحي (بلاغ: «الحضورية تعطي لا توجد مواعيد»):
--
-- الفحص كشف عطلين:
--   ① محامي ١ ملفه موجود لكن `avl = {}` ⇒ لا مواعيد (سلوك صحيح — عولج
--      بضبط الأوقات من حساب المحامي نفسه عبر set_availability_slots).
--   ② 🔴 **محامي ٢ بلا صف في lawyer_profiles إطلاقاً.**
--
-- خطورة ②: `pick_next_lawyer` تبني على
--     FROM lawyer_profiles lp JOIN users u ON u.id = lp.uid
-- أي أن **أي محامٍ بلا ملف لا يستقبل إسناداً أبداً** — لا يظهر في الدور
-- ولا في «الأقل انشغالاً». وهذا يكسر قاعدة المالك الموثّقة:
--     «أساس الإسناد هو الدور والأقل انشغالاً»
-- فلو كان محامٍ واحد فقط يملك ملفاً، صار كل الحمل عليه وحده، ولو جُمّد
-- أو أُلغي توفّره توقفت الخدمة كلياً رغم وجود محامين آخرين.
--
-- السبب الجذري: **لا يوجد أي مسار ينشئ الصف** — لا محفّز، ولا إدراج في
-- أي Edge Function، ولا في أي هجرة سابقة. الملف الوحيد الموجود أُنشئ يدوياً.
--
-- الإصلاح بطبقتين:
--   (أ) محفّز على users يُنشئ الملف تلقائياً عند صيرورة الدور 7 (إنشاءً
--       أو ترقيةً) ⇒ لا تكرار للعطل مستقبلاً.
--   (ب) ردم فوري للمحامين الحاليين بلا ملف.
--
-- ⚠️ `avl` يبقى `{}` عمداً: النظام لا يخترع أوقات دوام. المحامي يضبطها
--    بنفسه من لوحته، وحتى ذلك الحين تُخفى الحضورية عنه (سلوك مقصود يمنع
--    حجز موعد لا وجود له).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.ensure_lawyer_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  -- يُنشأ عند الإدراج بدور 7، أو عند الترقية إليه لاحقاً.
  IF NEW.role = 7 AND COALESCE(NEW.i_del, 0) = 0 THEN
    INSERT INTO lawyer_profiles (uid, is_active, avl, active_tasks_count)
    VALUES (NEW.id, TRUE, '{}'::jsonb, 0)
    ON CONFLICT (uid) DO NOTHING;   -- لا يمسّ ملفاً قائماً ولا يُصفّر أوقاته
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_ensure_lawyer_profile ON public.users;
CREATE TRIGGER trg_ensure_lawyer_profile
  AFTER INSERT OR UPDATE OF role ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.ensure_lawyer_profile();

-- ── §7 تحصين دالة المحفّز ──
REVOKE ALL ON FUNCTION public.ensure_lawyer_profile() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.ensure_lawyer_profile() FROM anon, authenticated;

-- ============================================================================
-- (ب) ردم الملفات الناقصة للمحامين الحاليين
-- ============================================================================
INSERT INTO lawyer_profiles (uid, is_active, avl, active_tasks_count)
SELECT u.id, TRUE, '{}'::jsonb, 0
  FROM users u
 WHERE u.role = 7
   AND u.i_del = 0
   AND NOT EXISTS (SELECT 1 FROM lawyer_profiles lp WHERE lp.uid = u.id)
ON CONFLICT (uid) DO NOTHING;
