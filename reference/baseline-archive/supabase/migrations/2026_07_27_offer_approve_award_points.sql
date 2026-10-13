-- ============================================================
-- منحة النقاط لصاحب العرض عند الاعتماد — سيرفرياً خالصاً (2026-07-27)
-- الخلل القديم: المنحة كانت تُستدعى من واجهة الإدارة (عميل → إيدج user-rewards)
--   فيرفضها validateStaff لأن المانح ≠ المستفيد (AUTH_TOKEN_REQUIRED) وتُبتلع بصمت
--   ⇒ منحة +500 لم تصل يوماً واحداً لأي صاحب عرض.
-- الحل: تريغر DB على offers — يُغطي كل مسارات الاعتماد (RPC / أدمن / SQL يدوي)
--   ويهرب عبر award_points_safe (حد يومي 3 = سد حلقة رفع-تعديل-إعادة اعتماد)
-- idempotent بالكامل + رباعي التحصين (الدستور §7)
-- ============================================================

-- الخطوة 1/3: الدالة + التريغر (نفّذ الكل مرة واحدة)
CREATE OR REPLACE FUNCTION public.trg_offer_approved_award_points()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $$
DECLARE
  v_pts INT := 500;  -- القيمة الافتراضية، وتُقرأ من الكونفغ الحي إن وُجدت
  v_cfg JSONB;
BEGIN
  -- منح مرة واحدة فقط عند الانتقال الحقيقي إلى «منشور» (sts=2):
  -- لا منح عند 2→2 (حفظ بلا تغيير) ولا عند أي تحديث لا يشمل sts
  IF NEW.sts = 2 AND (OLD.sts IS DISTINCT FROM 2) THEN
    IF NEW.usr_id IS NOT NULL AND NEW.i_del = 0 THEN
      SELECT value INTO v_cfg FROM public.app_config WHERE key = 'main';
      IF v_cfg IS NOT NULL AND (v_cfg -> 'pts' ->> 'addO') ~ '^\d+$' THEN
        v_pts := (v_cfg -> 'pts' ->> 'addO')::INT;
      END IF;
      -- award_points_safe يفرض الحد اليومي 3 لهذا الحدث (حلقة المزرعة مسدودة)
      PERFORM public.award_points_safe(NEW.usr_id, 'add_offer', v_pts);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_offer_approved_award_points ON public.offers;
CREATE TRIGGER trg_offer_approved_award_points
  AFTER UPDATE OF sts ON public.offers
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_offer_approved_award_points();

-- رباعي التحصين (الدستور §7) — Triggers ما بتننادى من العميل أصلاً بس القاعدة قاعدة
REVOKE ALL ON FUNCTION public.trg_offer_approved_award_points() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.trg_offer_approved_award_points() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.trg_offer_approved_award_points() TO service_role;

-- الخطوة 2/3: تحقق الوجود — لازم صف واحد لكل استعلام
SELECT tgname, tgrelid::regclass AS tbl, tgenabled
FROM pg_trigger WHERE tgname = 'trg_offer_approved_award_points';

-- الخطوة 3/3: تحقق التحصين — لازم ما يرجع ولا صف (مثل باقي الدوال)
SELECT p.proname AS unpinned_or_open_fn
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'trg_offer_approved_award_points'
  AND (NOT p.prosecdef
       OR NOT EXISTS (
            SELECT 1 FROM unnest(COALESCE(p.proconfig, ARRAY[]::text[])) c
            WHERE c LIKE 'search_path=%'));
