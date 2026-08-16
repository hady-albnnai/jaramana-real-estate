-- =============================================================================
-- 2026-08-16 — إصلاح تعارض pick_next_lawyer الذي حوّل خطأ RPC إلى slots=[]
-- =============================================================================
-- التوقيع القديم uuid[] يتعارض مع التوقيع الجديد uuid[],boolean لأن الباراميتر
-- الثاني له default. كل المستدعين الحيين يُنقلون للتوقيع الصريح ذي الباراميترين.

DROP FUNCTION IF EXISTS public.pick_next_lawyer(uuid[]);

-- تثبيت ACL للتوقيع الوحيد الباقي.
REVOKE ALL ON FUNCTION public.pick_next_lawyer(uuid[], boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.pick_next_lawyer(uuid[], boolean) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pick_next_lawyer(uuid[], boolean) TO service_role;

-- تحقق تنفيذي: يجب أن يبقى توقيع واحد فقط.
DO $verify$
DECLARE v_count integer;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'pick_next_lawyer';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'PICK_NEXT_LAWYER_SIGNATURE_COUNT_INVALID:%', v_count;
  END IF;
END;
$verify$;
