-- ============================================================================
-- 2026_08_15 — PHOTO-001: ربط صور التصوير بالعرض معطّل باسم عمود خاطئ
-- ============================================================================
-- اكتُشف أثناء اختبار مسار التصوير كاملاً (إسناد ← تنفيذ ← تسليم ← ربط):
--   attach_media يُرجع: record "v_task" has no field "offer_id"
--
-- السبب الجذري: الدالة تقرأ `v_task.offer_id` في **موضعين**، بينما العمود
-- في جدول photography_tasks اسمه **`off_id`** (تحقّقنا من information_schema).
-- PL/pgSQL لا يكتشف هذا وقت الإنشاء لأن `v_task` من نوع RECORD يُحلّ وقت
-- التنفيذ ⇒ الخطأ لا يظهر إلا عند أول استدعاء حقيقي.
--
-- الأثر: **ربط صور المصوّر بالعرض معطّل كلياً** — المصوّر يصوّر ويسلّم
-- بنجاح (sts=2)، لكن الإدارة لا تستطيع نقل الصور للعرض إطلاقاً ⇒ العرض
-- يبقى بلا صور ⇒ بوابة IMG-001 ترفض اعتماده ⇒ **دورة التصوير مسدودة
-- من طرفيها**: لا صور ولا نشر.
--
-- الإصلاح: تصحيح اسم العمود في الموضعين + تحصين §7.
-- ⚠️ تحسين إضافي: التحقق من وجود العرض قبل التحديث — كانت الدالة تُرجع
--    TRUE حتى لو كانت المهمة بلا عرض مرتبط (off_id NULL) فيظن المدير أن
--    الصور رُبطت وهي لم تُربط بشيء (§13 لا نجاح كاذب).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.attach_photography_media_to_offer_internal(
  p_admin_uid uuid,
  p_task_id   uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_role   INT;
  v_task   RECORD;
  v_imgs   JSONB;
  v_merged JSONB;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_MISMATCH';
  END IF;

  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 3 THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  SELECT * INTO v_task FROM photography_tasks WHERE id = p_task_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'TASK_NOT_FOUND';
  END IF;

  -- 🔧 PHOTO-001: كان `v_task.offer_id` — والعمود الصحيح `off_id`.
  IF v_task.off_id IS NULL THEN
    RAISE EXCEPTION 'TASK_HAS_NO_OFFER';
  END IF;

  -- §13: لا نجاح كاذب — نتأكد أن العرض موجود فعلاً قبل الدمج.
  SELECT COALESCE(imgs, '[]'::jsonb) INTO v_imgs
    FROM offers WHERE id = v_task.off_id AND i_del = 0;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'OFFER_NOT_FOUND';
  END IF;

  IF COALESCE(jsonb_array_length(NULLIF(v_task.media, 'null'::jsonb)), 0) = 0 THEN
    RAISE EXCEPTION 'MEDIA_REQUIRED';
  END IF;

  -- دمج صور العرض القائمة مع صور المصوّر بلا تكرار
  SELECT jsonb_agg(DISTINCT val) INTO v_merged FROM (
    SELECT jsonb_array_elements(v_imgs) AS val
    UNION
    SELECT jsonb_array_elements(COALESCE(v_task.media, '[]'::jsonb))
  ) c;

  UPDATE offers
     SET imgs = COALESCE(v_merged, '[]'::jsonb)
   WHERE id = v_task.off_id AND i_del = 0;

  UPDATE photography_tasks SET sts = 3, ts_upd = NOW() WHERE id = p_task_id;
  RETURN TRUE;
END;
$function$;

REVOKE ALL ON FUNCTION public.attach_photography_media_to_offer_internal(uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.attach_photography_media_to_offer_internal(uuid, uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.attach_photography_media_to_offer_internal(uuid, uuid) TO service_role;
