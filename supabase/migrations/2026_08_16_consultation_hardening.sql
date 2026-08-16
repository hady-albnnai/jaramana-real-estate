-- =============================================================================
-- 2026-08-16 — التحصين النهائي لمسار الاستشارة الهاتفية
-- =============================================================================
-- 1) منع إعادة استخدام دفعة واحدة لأكثر من استشارة.
-- 2) جعل حجز الاستشارة + ربط الدفعة/استهلاك الرصيد عملية ذرية.
-- 3) اعتماد تجديد المحادثة بعد الدفع فقط وبعملية مقفلة ذرياً.
-- 4) مفتاح عدم تكرار لرسائل المحادثة.
-- 5) إغلاق المحادثة آلياً عند نهاية مدتها الحالية كل دقيقة.
-- =============================================================================

ALTER TABLE public.consultation_chats
  ADD COLUMN IF NOT EXISTS client_message_id uuid;

CREATE UNIQUE INDEX IF NOT EXISTS uq_consultation_chat_client_message
  ON public.consultation_chats (consultation_id, sender_id, client_message_id)
  WHERE client_message_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_legal_consultation_payment
  ON public.legal_consultations (payment_id)
  WHERE payment_id IS NOT NULL;

-- الحجز الذري: لا استشارة جديدة بلا دفعة معتمدة غير مستخدمة أو رصيد صالح.
CREATE OR REPLACE FUNCTION public.create_legal_consultation_internal(
  p_user_uid uuid,
  p_service_type integer,
  p_subject text,
  p_price numeric
)
RETURNS SETOF public.legal_consultations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_lawyer_uid uuid;
  v_pending_pay integer;
  v_open_cons integer;
  v_payment_id uuid;
  v_credit_id uuid;
  v_consult public.legal_consultations%ROWTYPE;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;
  IF p_service_type IS NULL OR p_service_type NOT IN (0, 1) THEN
    RAISE EXCEPTION 'INVALID_SERVICE_TYPE';
  END IF;
  IF NULLIF(BTRIM(COALESCE(p_subject, '')), '') IS NULL THEN
    RAISE EXCEPTION 'SUBJECT_REQUIRED';
  END IF;

  -- يمنع سباق حجزين متزامنين للمستخدم والنوع نفسيهما.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_uid::text || ':' || p_service_type::text, 0));

  SELECT COUNT(*) INTO v_pending_pay
    FROM public.payments
   WHERE uid = p_user_uid AND tp = 2 AND sts = 0
     AND COALESCE(pkg, 0) = p_service_type;
  IF v_pending_pay > 0 THEN
    RAISE EXCEPTION 'PENDING_CONSULTATION_PAYMENT_EXISTS';
  END IF;

  SELECT COUNT(*) INTO v_open_cons
    FROM public.legal_consultations
   WHERE user_uid = p_user_uid
     AND service_type = p_service_type
     AND i_del = 0
     AND (
          status IN (0, 5)
       OR (status = 1 AND chat_started_at IS NULL)
       OR (status = 1 AND chat_started_at IS NOT NULL
           AND NOW() < chat_started_at
             + make_interval(mins => COALESCE(chat_duration_minutes, 15)))
     );
  IF v_open_cons > 0 THEN
    RAISE EXCEPTION 'OPEN_CONSULTATION_EXISTS';
  END IF;

  -- الرصيد الممنوح له الأولوية، ثم أقدم دفعة مطابقة معتمدة وغير مستخدمة.
  SELECT id INTO v_credit_id
    FROM public.consultation_credits
   WHERE user_uid = p_user_uid
     AND service_type = p_service_type
     AND consumed = false
   ORDER BY ts_crt
   FOR UPDATE SKIP LOCKED
   LIMIT 1;

  IF v_credit_id IS NULL THEN
    SELECT p.id INTO v_payment_id
      FROM public.payments p
     WHERE p.uid = p_user_uid
       AND p.tp = 2
       AND p.sts = 1
       AND COALESCE(p.pkg, 0) = p_service_type
       AND COALESCE(p.meta->>'service', '') = 'legal_consultation'
       AND NULLIF(p.meta->>'continue_chat', '') IS NULL
       AND p.amt = p_price
       AND NOT EXISTS (
         SELECT 1 FROM public.legal_consultations lc WHERE lc.payment_id = p.id
       )
     ORDER BY p.ts_crt
     FOR UPDATE OF p SKIP LOCKED
     LIMIT 1;

    IF v_payment_id IS NULL THEN
      RAISE EXCEPTION 'CONSULTATION_PAYMENT_REQUIRED';
    END IF;
  END IF;

  v_lawyer_uid := public.pick_next_lawyer('{}', p_service_type = 1);

  INSERT INTO public.legal_consultations (
    user_uid, lawyer_uid, service_type, subject, price, status,
    payment_id, payment_status, ts_crt, ts_upd
  ) VALUES (
    p_user_uid, v_lawyer_uid, p_service_type, BTRIM(p_subject), p_price, 0,
    v_payment_id, CASE WHEN v_payment_id IS NULL THEN 1 ELSE 1 END, NOW(), NOW()
  ) RETURNING * INTO v_consult;

  IF v_credit_id IS NOT NULL THEN
    UPDATE public.consultation_credits
       SET consumed = true, consumed_at = NOW(), consultation_id = v_consult.id
     WHERE id = v_credit_id AND consumed = false;
    IF NOT FOUND THEN RAISE EXCEPTION 'CONSULTATION_CREDIT_ALREADY_USED'; END IF;
  END IF;

  RETURN NEXT v_consult;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_legal_consultation_internal(uuid, integer, text, numeric) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_legal_consultation_internal(uuid, integer, text, numeric) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_legal_consultation_internal(uuid, integer, text, numeric) TO service_role;

-- نسخة اعتماد جديدة: أنواع الدفع الأخرى تُفوّض للدالة المستقرة القديمة،
-- والاستشارة تُعالج هنا بعد اكتمال كل التحققات وقفل الصف.
CREATE OR REPLACE FUNCTION public.approve_payment_final_v2(
  p_payment_id uuid,
  p_admin_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_admin_role integer;
  v_payment public.payments%ROWTYPE;
  v_chat uuid;
  v_cons public.legal_consultations%ROWTYPE;
  v_config jsonb;
  v_add_mins integer;
  v_old_end timestamptz;
  v_new_duration integer;
  v_new_renew_count integer;
  v_service text;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_UID_MISMATCH');
  END IF;
  SELECT role INTO v_admin_role FROM public.users
   WHERE id = p_admin_id AND i_del = 0;
  IF v_admin_role IS NULL OR v_admin_role < 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'FORBIDDEN');
  END IF;

  SELECT * INTO v_payment FROM public.payments
   WHERE id = p_payment_id
   FOR UPDATE;
  IF v_payment.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'PAYMENT_NOT_FOUND');
  END IF;
  IF COALESCE(v_payment.sts, -1) <> 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'PAYMENT_NOT_PENDING');
  END IF;

  IF COALESCE(v_payment.tp, -1) <> 2 THEN
    RETURN public.approve_payment_final(p_payment_id, p_admin_id);
  END IF;
  IF COALESCE(v_payment.meta->>'service', '') <> 'legal_consultation' THEN
    RETURN jsonb_build_object('success', false, 'error', 'CONSULTATION_META_INVALID');
  END IF;
  IF COALESCE(v_payment.pkg, -1) NOT IN (0, 1) THEN
    RETURN jsonb_build_object('success', false, 'error', 'CONSULTATION_TYPE_INVALID');
  END IF;

  v_service := CASE v_payment.pkg WHEN 0 THEN 'phone' ELSE 'onsite' END;
  BEGIN
    v_chat := NULLIF(v_payment.meta->>'continue_chat', '')::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RETURN jsonb_build_object('success', false, 'error', 'CONSULTATION_ID_INVALID');
  END;

  IF v_chat IS NOT NULL THEN
    SELECT * INTO v_cons FROM public.legal_consultations
     WHERE id = v_chat AND i_del = 0
     FOR UPDATE;
    IF v_cons.id IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'CONSULTATION_NOT_FOUND');
    END IF;
    IF v_cons.user_uid <> v_payment.uid THEN
      RETURN jsonb_build_object('success', false, 'error', 'CONSULTATION_OWNER_MISMATCH');
    END IF;
    IF v_cons.service_type <> 0 THEN
      RETURN jsonb_build_object('success', false, 'error', 'PHONE_CONSULTATION_REQUIRED');
    END IF;
    IF v_cons.chat_started_at IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'CHAT_NOT_STARTED');
    END IF;
    IF NOW() > v_cons.chat_started_at + INTERVAL '7 days' THEN
      RETURN jsonb_build_object('success', false, 'error', 'CHAT_EXPIRED_7DAYS');
    END IF;

    SELECT value INTO v_config FROM public.app_config WHERE key = 'main';
    v_add_mins := GREATEST(1, COALESCE((v_config->'legalPrice'->>'durationMins')::integer, 15));
    v_old_end := v_cons.chat_started_at
      + make_interval(mins => COALESCE(v_cons.chat_duration_minutes, v_add_mins));
    v_new_duration := CEIL(EXTRACT(EPOCH FROM
      (GREATEST(v_old_end, NOW()) - v_cons.chat_started_at)) / 60.0)::integer + v_add_mins;
    v_new_renew_count := COALESCE(v_cons.renew_count, 0) + 1;

    UPDATE public.legal_consultations
       SET chat_duration_minutes = v_new_duration,
           renew_count = v_new_renew_count,
           status = 1,
           payment_status = 1,
           ts_upd = NOW()
     WHERE id = v_chat;

    INSERT INTO public.consultation_chats
      (consultation_id, sender_id, message_type, content)
    VALUES (
      v_chat, v_payment.uid, 'system',
      '⏱️ تم تأكيد الدفع — تجديد المحادثة ' || v_add_mins::text ||
      ' دقيقة إضافية (التجديد رقم ' || v_new_renew_count::text || ')'
    );
  END IF;

  UPDATE public.payments
     SET sts = 1, appr_by = p_admin_id
   WHERE id = p_payment_id AND sts = 0;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PAYMENT_CONCURRENTLY_PROCESSED';
  END IF;

  IF v_chat IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true, 'type', 'consultation_renew', 'service', v_service,
      'consultation_id', v_chat, 'duration_minutes', v_new_duration,
      'renew_count', v_new_renew_count
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true, 'type', 'consultation', 'service', v_service,
    'pkg', v_payment.pkg, 'amount', v_payment.amt
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$function$;

REVOKE ALL ON FUNCTION public.approve_payment_final_v2(uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.approve_payment_final_v2(uuid, uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.approve_payment_final_v2(uuid, uuid) TO service_role;

-- الإغلاق فور انتهاء المدة الحالية، بدلاً من الانتظار سبعة أيام.
CREATE OR REPLACE FUNCTION public.close_expired_phone_consultations()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  r record;
  v_closed integer := 0;
BEGIN
  FOR r IN
    UPDATE public.legal_consultations
       SET status = 2, ts_upd = NOW()
     WHERE status = 1
       AND service_type = 0
       AND i_del = 0
       AND chat_started_at IS NOT NULL
       AND NOW() >= chat_started_at
         + make_interval(mins => COALESCE(chat_duration_minutes, 15))
     RETURNING id, user_uid, lawyer_uid
  LOOP
    v_closed := v_closed + 1;
    INSERT INTO public.notifications
      (uid, tp, ttl, bdy, ref_id, act, i_rd, i_del, ts_crt)
    VALUES (
      r.user_uid, 1, '✅ اكتملت استشارتك',
      'انتهى وقت الاستشارة الهاتفية. يمكنك الآن تقييم الخدمة أو طلب تجديد مدفوع.',
      r.id::text, 'legal_consultation_update', 0, 0, NOW()
    );
    IF r.lawyer_uid IS NOT NULL THEN
      PERFORM public.update_lawyer_active_tasks(r.lawyer_uid);
    END IF;
  END LOOP;
  RETURN jsonb_build_object('success', true, 'closed', v_closed, 'ran_at', NOW());
END;
$function$;

REVOKE ALL ON FUNCTION public.close_expired_phone_consultations() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.close_expired_phone_consultations() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.close_expired_phone_consultations() TO service_role;

DO $cron$
DECLARE v_job integer;
BEGIN
  SELECT jobid INTO v_job FROM cron.job
   WHERE command = 'SELECT public.close_expired_phone_consultations();'
   LIMIT 1;
  IF v_job IS NOT NULL THEN PERFORM cron.unschedule(v_job); END IF;
  PERFORM cron.schedule(
    'close-expired-phone-consultations',
    '* * * * *',
    'SELECT public.close_expired_phone_consultations();'
  );
END;
$cron$;
