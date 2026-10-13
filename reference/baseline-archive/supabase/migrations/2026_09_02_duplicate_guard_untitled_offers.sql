-- ═══ 2026-09-02: إصلاح حارس تكرار العروض (بلاغ «سقف الوسيط 3») ═══
-- المشكلة: check_offer_duplicate كانت تطابق (العنوان+السعر) على كل مستخدمي النظام،
-- ومع العنوان الافتراضي «عرض جديد» (يُرسل تلقائياً عند ترك العنوان فارغاً) كان أي
-- تسعير متطابق مع أي عرض آخر في النظام يُرفض بـ DUPLICATE_OFFER — وبرسالة عامة
-- على التطبيق 1.1.0 فهمها الوسيط «السقف 3 عروض».
-- الإصلاح (مُنفَّذ حياً على الإنتاج بتاريخ 2026-09-02 بموافقة المالك):
--   1) العنوان الفارغ/الافتراضي «عرض جديد» لا يُفحص ضد التكرار إطلاقاً؛
--      صمامات الأمان تبقى: حصة العروض + مراجعة الإدارة قبل النشر.
--   2) التطابق محصور بعروض المستخدم نفسه بدل المطابقة الشاملة.
-- التراجع: تعريف ما قبل الإصلاح محفوظ بسجل البلاغ (pg_get_functiondef بتاريخ 2026-09-02).
CREATE OR REPLACE FUNCTION public.check_offer_duplicate(p_ttl text, p_prc numeric, p_loc jsonb, p_usr_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_dup BOOLEAN;
  v_norm_ttl TEXT;
BEGIN
  -- 🩹 2026-09-02 (بلاغ «سقف الوسيط 3»):
  -- (1) من ينشر بلا عنوان (فارغ أو الافتراضي «عرض جديد») لا يُفحص ضد التكرار —
  --     الحصة ومراجعة الإدارة قبل النشر هما صماما الأمان.
  -- (2) التطابق محصور بعروض المستخدم نفسه بدل المطابقة الشاملة التي كانت
  --     تمنع مستخدمين مختلفين بنفس العنوان والسعر.
  v_norm_ttl := LOWER(REGEXP_REPLACE(BTRIM(COALESCE(p_ttl, '')), '[[:space:]]+', ' ', 'g'));

  IF v_norm_ttl = '' OR v_norm_ttl = 'عرض جديد' THEN
    RETURN FALSE; -- لا عنوان حقيقي → لا منع
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM offers
    WHERE usr_id = p_usr_id
      AND LOWER(REGEXP_REPLACE(BTRIM(ttl), '[[:space:]]+', ' ', 'g')) = v_norm_ttl
      AND prc = p_prc
      AND i_del = 0
      AND COALESCE(photo_req, 0) = 0
  ) INTO v_dup;
  RETURN v_dup;
END;
$function$

REVOKE ALL ON FUNCTION public.check_offer_duplicate(text, numeric, jsonb, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.check_offer_duplicate(text, numeric, jsonb, uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_offer_duplicate(text, numeric, jsonb, uuid) TO service_role;
