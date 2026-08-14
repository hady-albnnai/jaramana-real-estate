CREATE OR REPLACE FUNCTION public.admin_reject_verification_by_admin(p_admin_uid uuid, p_target_uid uuid, p_reason text DEFAULT ''::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 4 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  IF COALESCE(trim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'REJECTION_REASON_REQUIRED';
  END IF;
  -- 🔒 BUG-013 (2026-08-14): كان الشرط بلا `AND vrf = 1` ⇒ استدعاء «رفض»
  -- على **أي** مستخدم — بما فيه موثّق منذ شهور لم يطلب شيئاً — يجرّده من
  -- توثيقه ويرسل له «تم رفض طلب التوثيق» بلا أن يكون قد قدّم طلباً أصلاً.
  -- أُكِّد حياً: رُفض حساب حالته vrf=2 ونجحت العملية.
  -- (دالة الاعتماد كانت تحمل الشرط الصحيح؛ الرفض وحده أُغفل.)
  UPDATE users SET vrf = 0, ts_upd = NOW()
  WHERE id = p_target_uid AND i_del = 0 AND vrf = 1;
  IF FOUND THEN
    INSERT INTO notifications (uid, tp, ttl, bdy, ts_crt)
    VALUES (p_target_uid, 4, 'تم رفض طلب التوثيق', COALESCE(NULLIF(trim(p_reason),''), 'لم يتم قبول الوثائق المرفقة'), NOW());
    PERFORM public.log_admin_action(p_admin_uid, 104, 'رفض توثيق الهوية: ' || trim(p_reason), p_target_uid::TEXT, 'users');
  END IF;
  RETURN FOUND;
END;
$function$;
CREATE OR REPLACE FUNCTION public.submit_photography_task_internal(p_photographer_uid uuid, p_task_id uuid, p_media jsonb, p_photographer_note text DEFAULT ''::text, p_replace boolean DEFAULT false)
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

  -- 🔒 BUG-014 (2026-08-14): كان فحص النوع وحده يمرّر المصفوفة الفارغة
  -- ⇒ تسليم مهمة تصوير **بصفر صور** ينجح وتنتقل الحالة إلى «بانتظار
  -- المراجعة» ثم تُعتمد بلا أي وسائط. دفاع بالعمق مع حارس الإيدج.
  IF jsonb_array_length(COALESCE(p_media, '[]'::jsonb)) = 0 THEN
    RAISE EXCEPTION 'MEDIA_REQUIRED';
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
CREATE OR REPLACE FUNCTION public.create_report_internal(p_reporter_uid uuid, p_report jsonb)
 RETURNS SETOF reports
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_target UUID;
  v_tgt_id UUID;
  v_offer_owner UUID;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_reporter_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  v_target := NULLIF(p_report->>'tgt_uid', '')::UUID;
  IF v_target IS NOT NULL AND v_target = p_reporter_uid THEN
    RAISE EXCEPTION 'CANNOT_REPORT_OWN';
  END IF;

  BEGIN
    v_tgt_id := NULLIF(p_report->>'tgt_id', '')::UUID;
  EXCEPTION WHEN OTHERS THEN
    v_tgt_id := NULL;
  END;
  IF v_tgt_id IS NOT NULL THEN
    SELECT usr_id INTO v_offer_owner FROM public.offers WHERE id = v_tgt_id AND i_del = 0;
    IF v_offer_owner IS NOT NULL AND v_offer_owner = p_reporter_uid THEN
      RAISE EXCEPTION 'CANNOT_REPORT_OWN';
    END IF;
  END IF;

  -- 🔒 BUG-015 (2026-08-14): التبليغ كان بلا أي تحقق سوى «لا تبلّغ عن نفسك».
  -- أُكِّد حياً قبول: تبليغ مكرر على نفس الهدف · هدف غير موجود إطلاقاً ·
  -- سبب خارج المجال (rsn=99). النتيجة: إغراق لوحة الإدارة ببلاغات كيدية
  -- متكررة وبلاغات على كيانات وهمية لا يمكن اتخاذ إجراء بشأنها.

  -- (1) سبب ضمن المجال المعرَّف (0..5)
  IF COALESCE((p_report->>'rsn')::INT, 0) < 0
     OR COALESCE((p_report->>'rsn')::INT, 0) > 5 THEN
    RAISE EXCEPTION 'INVALID_REPORT_REASON';
  END IF;

  -- (2) نوع الهدف ضمن المجال (0 عرض · 1 مستخدم · 2 طلب)
  IF COALESCE((p_report->>'tgt_tp')::INT, 0) < 0
     OR COALESCE((p_report->>'tgt_tp')::INT, 0) > 2 THEN
    RAISE EXCEPTION 'INVALID_TARGET_TYPE';
  END IF;

  -- (3) الهدف موجود فعلاً — لا بلاغات على كيانات وهمية
  IF v_tgt_id IS NOT NULL THEN
    IF COALESCE((p_report->>'tgt_tp')::INT, 0) = 0
       AND NOT EXISTS (SELECT 1 FROM public.offers WHERE id = v_tgt_id AND i_del = 0) THEN
      RAISE EXCEPTION 'TARGET_NOT_FOUND';
    END IF;
    IF COALESCE((p_report->>'tgt_tp')::INT, 0) = 2
       AND NOT EXISTS (SELECT 1 FROM public.requests WHERE id = v_tgt_id) THEN
      RAISE EXCEPTION 'TARGET_NOT_FOUND';
    END IF;
  END IF;
  IF v_target IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_target AND i_del = 0) THEN
    RAISE EXCEPTION 'TARGET_NOT_FOUND';
  END IF;

  -- (4) منع التكرار: بلاغ مفتوح من نفس المبلِّغ على نفس الهدف
  IF EXISTS (
    SELECT 1 FROM public.reports
    WHERE rep_uid = p_reporter_uid
      AND sts = 0
      AND COALESCE(tgt_id, '') = COALESCE(p_report->>'tgt_id', '')
      AND tgt_tp = COALESCE((p_report->>'tgt_tp')::INT, 0)
  ) THEN
    RAISE EXCEPTION 'DUPLICATE_OPEN_REPORT';
  END IF;

  RETURN QUERY
  INSERT INTO reports (
    rep_uid, tgt_uid, tgt_tp, tgt_id, rsn, det, sts, act, act_dur, note, act_by, ts_crt
  ) VALUES (
    p_reporter_uid,
    v_target,
    COALESCE((p_report->>'tgt_tp')::INT, 0),
    COALESCE(p_report->>'tgt_id', ''),
    COALESCE((p_report->>'rsn')::INT, 0),
    COALESCE(p_report->>'det', ''),
    0,
    0,
    0,
    '',
    NULL,
    NOW()
  ) RETURNING *;
END;
$function$;
