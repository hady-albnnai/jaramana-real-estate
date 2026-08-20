-- ══════════════════════════════════════════════════════════════════
-- 2026-08-20 — لا تُمنح نقاط التطبيق للإدارة (ملاحظة المالك)
--
-- تريغر منحة نقاط نشر العرض (trg_offer_approved_award_points) كان
-- يمنح +نقاط لصاحب العرض عند الانتقال إلى «منشور» — بمن فيهم
-- الموظفون/الإدارة عند إنشاء عرض من شاشة الإدارة (usr_id = موظف).
-- قرار المالك: نقاط التطبيق لا يجوز أن تُمنح للإدارة.
-- الإصلاح: حارس دور — تُمنح فقط لأصحاب العروض من العملاء (role < 4).
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.trg_offer_approved_award_points()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_pts INT := 500;
  v_cfg JSONB;
  v_role INT;
BEGIN
  IF NEW.sts = 2 AND (OLD.sts IS DISTINCT FROM 2) THEN
    IF NEW.usr_id IS NOT NULL AND NEW.i_del = 0 THEN
      -- 🔒 2026-08-20: لا منح للإدارة/الموظفين (role >= 4) — النقاط للعملاء فقط
      SELECT role INTO v_role FROM public.users
       WHERE id = NEW.usr_id AND i_del = 0;
      IF v_role IS NOT NULL AND v_role < 4 THEN
        SELECT value INTO v_cfg FROM public.app_config WHERE key = 'main';
        IF v_cfg IS NOT NULL AND (v_cfg -> 'pts' ->> 'addO') ~ '^\d+$' THEN
          v_pts := (v_cfg -> 'pts' ->> 'addO')::INT;
        END IF;
        PERFORM public.award_points_safe(NEW.usr_id, 'add_offer', v_pts);
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.trg_offer_approved_award_points() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.trg_offer_approved_award_points() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.trg_offer_approved_award_points() TO service_role;

-- التريغر يبقى بنفس الاسم يشير للدالة المعاد تعريفها

-- ──────────────────────────────────────────────────────────────────────
-- تحقق نهائي مدمج: staff_guard_patched = true
-- ──────────────────────────────────────────────────────────────────────
SELECT pg_get_functiondef('public.trg_offer_approved_award_points()'::regprocedure)
  LIKE '%v_role < 4%' AS staff_guard_patched;
