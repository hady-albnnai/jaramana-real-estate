-- ============================================================================
-- 📸 إصلاحان بمسار المصوّر — 2026-07-30
--
-- ① فقدان الصور عند إعادة التسليم
--    submit_photography_task_internal تكتب `SET media = p_media` أي استبدال
--    كامل. سيناريو الضرر: المكتب يرفض التسليم (sts=4) طالباً صورة إضافية،
--    فيرسل المصوّر الصورة الجديدة وحدها ⇒ الخمس صور السابقة تُمحى نهائياً.
--    الإصلاح: دمج تراكمي بلا تكرار (الروابط الجديدة تُضاف للقديمة)، مع
--    باراميتر p_replace للاستبدال الصريح عند الحاجة (افتراضياً false).
--
-- ② لا فحص تعارض مواعيد للمصوّر
--    مواعيد المعاينة محميّة بـ TIME_CONFLICT، أما التصوير فلا شيء يمنع
--    إسناد مهمتين لنفس المصوّر بنفس الساعة ⇒ ازدواج ميداني حتمي.
--    الإصلاح: دالة assert_photographer_free تُطلق PHOTOGRAPHER_TIME_CONFLICT
--    عند تداخل ضمن نافذة gap_mins من app_config.appt (افتراضي 60 دقيقة)،
--    وتستثني المهمة نفسها والمهام المنتهية (معتمدة/مرفوضة/ملغاة).
-- ============================================================================

-- ① ─────────────── دمج الوسائط بدل استبدالها
DROP FUNCTION IF EXISTS public.submit_photography_task_internal(uuid, uuid, jsonb, text);

CREATE OR REPLACE FUNCTION public.submit_photography_task_internal(
  p_photographer_uid uuid,
  p_task_id uuid,
  p_media jsonb,
  p_photographer_note text DEFAULT ''::text,
  p_replace boolean DEFAULT false
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_old   JSONB;
  v_final JSONB;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_photographer_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  IF jsonb_typeof(COALESCE(p_media, '[]'::jsonb)) <> 'array' THEN
    RAISE EXCEPTION 'INVALID_MEDIA_ARRAY';
  END IF;

  SELECT COALESCE(media, '[]'::jsonb) INTO v_old
  FROM public.photography_tasks
  WHERE id = p_task_id
    AND photographer_id = p_photographer_uid
    AND sts IN (0, 1, 4);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'TASK_NOT_FOUND_OR_NOT_ALLOWED';
  END IF;

  IF COALESCE(p_replace, false) THEN
    v_final := COALESCE(p_media, '[]'::jsonb);
  ELSE
    -- دمج تراكمي بلا تكرار مع الحفاظ على ترتيب الظهور
    SELECT COALESCE(jsonb_agg(u.val ORDER BY u.ord), '[]'::jsonb)
      INTO v_final
    FROM (
      SELECT DISTINCT ON (val) val, ord
      FROM (
        SELECT value AS val, ordinality AS ord
        FROM jsonb_array_elements(v_old) WITH ORDINALITY
        UNION ALL
        SELECT value AS val,
               ordinality + jsonb_array_length(v_old) AS ord
        FROM jsonb_array_elements(COALESCE(p_media, '[]'::jsonb)) WITH ORDINALITY
      ) AS merged
      ORDER BY val, ord
    ) AS u;
  END IF;

  UPDATE public.photography_tasks
  SET media = v_final,
      photographer_note = COALESCE(p_photographer_note, ''),
      sts = 2,
      ts_submit = NOW(),
      ts_upd = NOW()
  WHERE id = p_task_id
    AND photographer_id = p_photographer_uid
    AND sts IN (0, 1, 4);

  RETURN TRUE;
END;
$function$;

REVOKE ALL     ON FUNCTION public.submit_photography_task_internal(uuid, uuid, jsonb, text, boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.submit_photography_task_internal(uuid, uuid, jsonb, text, boolean) FROM anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.submit_photography_task_internal(uuid, uuid, jsonb, text, boolean) TO service_role;

-- ② ─────────────── حارس تعارض مواعيد المصوّر
CREATE OR REPLACE FUNCTION public.assert_photographer_free(
  p_photographer_uid uuid,
  p_dt timestamptz,
  p_exclude_task uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_gap  INT;
  v_busy INT;
BEGIN
  IF p_photographer_uid IS NULL OR p_dt IS NULL THEN
    RETURN TRUE;  -- لا موعد ⇒ لا تعارض
  END IF;

  v_gap := COALESCE(
    (SELECT (value->'appt'->>'gap_mins')::INT FROM public.app_config WHERE key = 'main'),
    60
  );
  IF v_gap IS NULL OR v_gap <= 0 THEN v_gap := 60; END IF;

  SELECT COUNT(*) INTO v_busy
  FROM public.photography_tasks t
  WHERE t.photographer_id = p_photographer_uid
    AND t.ts_scheduled IS NOT NULL
    AND t.sts IN (0, 1)                                  -- النشطة فقط
    AND (p_exclude_task IS NULL OR t.id <> p_exclude_task)
    AND t.ts_scheduled > p_dt - make_interval(mins => v_gap)
    AND t.ts_scheduled < p_dt + make_interval(mins => v_gap);

  IF v_busy > 0 THEN
    RAISE EXCEPTION 'PHOTOGRAPHER_TIME_CONFLICT';
  END IF;

  RETURN TRUE;
END;
$function$;

REVOKE ALL     ON FUNCTION public.assert_photographer_free(uuid, timestamptz, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.assert_photographer_free(uuid, timestamptz, uuid) FROM anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.assert_photographer_free(uuid, timestamptz, uuid) TO service_role;

-- ============================================================================
-- ✅ تحققات
-- ============================================================================

-- ① التوقيع الجديد موجود (5 باراميترات) والقديم أُسقط → المتوقع: صف واحد
SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'submit_photography_task_internal';

-- ② التحصين الرباعي للدالتين → المتوقع: secdef=true · anon/auth=false · service=true
SELECT p.proname,
       p.prosecdef AS secdef,
       array_to_string(p.proconfig, ',') AS cfg,
       has_function_privilege('anon',         p.oid, 'EXECUTE') AS anon_exec,
       has_function_privilege('service_role', p.oid, 'EXECUTE') AS svc_exec
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('submit_photography_task_internal', 'assert_photographer_free');
