-- =============================================================================
-- 2026-08-16 — Consultation Flow V2: atomic transaction API (غير مفعّل افتراضياً)
-- =============================================================================

-- Feature flag مغلق حتى اكتمال Flutter واختبار allowlist.
UPDATE public.app_config
SET value = jsonb_set(
  value,
  '{features,consultationFlowV2}',
  COALESCE(value #> '{features,consultationFlowV2}', 'false'::jsonb),
  true
)
WHERE key='main';

-- اختيار محامٍ لديه وقت حر فعلي، لا مجرد جدول غير فارغ.
CREATE OR REPLACE FUNCTION public.pick_lawyer_with_free_slots(
  p_exclude uuid[] DEFAULT '{}',
  p_days integer DEFAULT 30
)
RETURNS uuid
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
  SELECT lp.uid
  FROM public.lawyer_profiles lp
  JOIN public.users u ON u.id=lp.uid
  WHERE lp.is_active=true AND u.role=7 AND u.sts=0 AND u.i_del=0
    AND NOT (lp.uid=ANY(COALESCE(p_exclude,'{}'::uuid[])))
    AND EXISTS (
      SELECT 1 FROM public.get_lawyer_free_slots(lp.uid,LEAST(GREATEST(p_days,1),30)) LIMIT 1
    )
  ORDER BY lp.active_tasks_count,lp.created_at
  LIMIT 1;
$function$;

REVOKE ALL ON FUNCTION public.pick_lawyer_with_free_slots(uuid[],integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.pick_lawyer_with_free_slots(uuid[],integer) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.pick_lawyer_with_free_slots(uuid[],integer) TO service_role;

-- إنشاء intent وحجز slot (إن لزم) في transaction واحدة.
CREATE OR REPLACE FUNCTION public.prepare_consultation_intent_v2(
  p_user_uid uuid,
  p_flow text,
  p_parent_consultation_id uuid,
  p_subject text,
  p_attachments text[],
  p_slot timestamptz,
  p_idempotency_key uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE
  v_existing public.consultation_intents%ROWTYPE;
  v_parent public.legal_consultations%ROWTYPE;
  v_cfg jsonb;
  v_phone numeric; v_onsite numeric; v_renew numeric;
  v_flow text := lower(trim(COALESCE(p_flow,'')));
  v_service integer; v_amount numeric; v_discount numeric := 0;
  v_lawyer uuid; v_alias text; v_intent uuid; v_reservation uuid;
  v_gap integer; v_slot_end timestamptz; v_path text;
BEGIN
  IF p_idempotency_key IS NULL THEN RAISE EXCEPTION 'IDEMPOTENCY_KEY_REQUIRED'; END IF;
  IF v_flow NOT IN ('phone_new','onsite_new','phone_renew','onsite_convert') THEN
    RAISE EXCEPTION 'INVALID_CONSULTATION_FLOW';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id=p_user_uid AND sts=0 AND i_del=0) THEN
    RAISE EXCEPTION 'USER_NOT_ACTIVE_OR_NOT_FOUND';
  END IF;

  SELECT * INTO v_existing FROM public.consultation_intents
   WHERE user_uid=p_user_uid AND idempotency_key=p_idempotency_key;
  IF v_existing.id IS NOT NULL THEN
    RETURN jsonb_build_object('success',true,'intent_id',v_existing.id,'status',v_existing.status,
      'quoted_amount',v_existing.quoted_amount,'reservation_id',v_existing.reservation_id,'duplicate',true);
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_uid::text || ':' || v_flow,0));
  SELECT value INTO v_cfg FROM public.app_config WHERE key='main';
  v_phone := (v_cfg->'legalPrice'->>'phone')::numeric;
  v_onsite := (v_cfg->'legalPrice'->>'onsite')::numeric;
  v_renew := (v_cfg->'legalPrice'->>'renew')::numeric;
  IF v_phone IS NULL OR v_onsite IS NULL OR v_renew IS NULL OR v_phone<0 OR v_onsite<0 OR v_renew<0 THEN
    RAISE EXCEPTION 'INVALID_LEGAL_PRICE';
  END IF;
  v_gap := GREATEST(15,COALESCE((public.appt_booking_config()->>'gap_mins')::integer,60));

  IF v_flow IN ('phone_renew','onsite_convert') THEN
    SELECT * INTO v_parent FROM public.legal_consultations
     WHERE id=p_parent_consultation_id AND user_uid=p_user_uid AND service_type=0 AND i_del=0
     FOR UPDATE;
    IF v_parent.id IS NULL THEN RAISE EXCEPTION 'CONSULTATION_NOT_FOUND'; END IF;
    IF v_parent.lawyer_uid IS NULL THEN RAISE EXCEPTION 'NO_LAWYER_ASSIGNED'; END IF;
    v_lawyer := v_parent.lawyer_uid;
  END IF;

  IF v_flow IN ('phone_new','onsite_new') AND length(trim(COALESCE(p_subject,'')))<10 THEN
    RAISE EXCEPTION 'SUBJECT_TOO_SHORT';
  END IF;
  IF COALESCE(array_length(p_attachments,1),0)>5 THEN RAISE EXCEPTION 'TOO_MANY_ATTACHMENTS'; END IF;
  FOREACH v_path IN ARRAY COALESCE(p_attachments,'{}'::text[]) LOOP
    IF v_path NOT LIKE p_user_uid::text || '/%' OR position('..' IN v_path)>0 THEN
      RAISE EXCEPTION 'INVALID_ATTACHMENT_PATH';
    END IF;
  END LOOP;

  IF v_flow='phone_new' THEN
    v_service:=0; v_amount:=v_phone;
    v_lawyer:=public.pick_next_lawyer('{}'::uuid[],false);
  ELSIF v_flow='phone_renew' THEN
    v_service:=0; v_amount:=v_renew;
    IF v_parent.chat_started_at IS NULL OR now()>v_parent.chat_started_at+interval '7 days' THEN
      RAISE EXCEPTION 'CHAT_EXPIRED_7DAYS';
    END IF;
  ELSIF v_flow='onsite_new' THEN
    v_service:=1; v_amount:=v_onsite;
    IF p_slot IS NULL THEN RAISE EXCEPTION 'SLOT_REQUIRED_FOR_ONSITE'; END IF;
    SELECT lp.uid INTO v_lawyer
    FROM public.lawyer_profiles lp JOIN public.users u ON u.id=lp.uid
    WHERE lp.is_active=true AND u.role=7 AND u.sts=0 AND u.i_del=0
      AND EXISTS (
        SELECT 1 FROM public.get_lawyer_free_slots(lp.uid,30) s
        WHERE abs(extract(epoch FROM (s.slot_dt-p_slot)))<1
      )
    ORDER BY lp.active_tasks_count,lp.created_at LIMIT 1;
  ELSE
    v_service:=1; v_discount:=v_phone; v_amount:=GREATEST(0,v_onsite-v_phone);
    IF p_slot IS NULL THEN RAISE EXCEPTION 'SLOT_REQUIRED_FOR_ONSITE'; END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.get_lawyer_free_slots(v_lawyer,30) s
      WHERE abs(extract(epoch FROM (s.slot_dt-p_slot)))<1
    ) THEN RAISE EXCEPTION 'SLOT_NO_LONGER_AVAILABLE'; END IF;
  END IF;
  IF v_lawyer IS NULL THEN RAISE EXCEPTION 'NO_ACTIVE_LAWYERS'; END IF;
  v_alias:=public.lawyer_alias_for(v_lawyer);

  INSERT INTO public.consultation_intents(
    user_uid,flow,parent_consultation_id,subject,attachments,service_type,lawyer_uid,
    quoted_amount,base_discount,price_snapshot,status,idempotency_key,expires_at
  ) VALUES (
    p_user_uid,v_flow,p_parent_consultation_id,COALESCE(NULLIF(trim(p_subject),''),v_parent.subject,''),
    COALESCE(p_attachments,'{}'::text[]),v_service,v_lawyer,v_amount,v_discount,
    jsonb_build_object('phone',v_phone,'onsite',v_onsite,'renew',v_renew,'captured_at',now()),
    'draft',p_idempotency_key,CASE WHEN v_service=1 THEN now()+interval '6 hours' ELSE NULL END
  ) RETURNING id INTO v_intent;

  IF v_service=1 THEN
    v_slot_end:=p_slot+make_interval(mins=>v_gap);
    BEGIN
      INSERT INTO public.lawyer_time_reservations(
        lawyer_uid,user_uid,consultation_intent_id,slot_start,slot_end,status,
        hold_expires_at,idempotency_key
      ) VALUES (v_lawyer,p_user_uid,v_intent,p_slot,v_slot_end,'held',now()+interval '6 hours',p_idempotency_key)
      RETURNING id INTO v_reservation;
    EXCEPTION WHEN exclusion_violation OR unique_violation THEN
      RAISE EXCEPTION 'SLOT_NO_LONGER_AVAILABLE';
    END;
    UPDATE public.consultation_intents SET reservation_id=v_reservation WHERE id=v_intent;
  END IF;

  RETURN jsonb_build_object('success',true,'intent_id',v_intent,'flow',v_flow,
    'quoted_amount',v_amount,'base_discount',v_discount,'reservation_id',v_reservation,
    'hold_expires_at',CASE WHEN v_service=1 THEN now()+interval '6 hours' ELSE NULL END,
    'lawyer_alias',COALESCE(v_alias,'محامي المكتب'));
END;
$function$;

REVOKE ALL ON FUNCTION public.prepare_consultation_intent_v2(uuid,text,uuid,text,text[],timestamptz,uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.prepare_consultation_intent_v2(uuid,text,uuid,text,text[],timestamptz,uuid) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_consultation_intent_v2(uuid,text,uuid,text,text[],timestamptz,uuid) TO service_role;

-- الدفع المرتبط بالـintent؛ السعر والمرجع والـhold كلها خادمية.
CREATE OR REPLACE FUNCTION public.create_consultation_payment_v2(
  p_user_uid uuid,
  p_intent_id uuid,
  p_payment jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE
  v_intent public.consultation_intents%ROWTYPE;
  v_res public.lawyer_time_reservations%ROWTYPE;
  v_payment public.payments%ROWTYPE;
  v_channel text; v_proof text; v_ref text; v_amt numeric;
BEGIN
  SELECT * INTO v_intent FROM public.consultation_intents
   WHERE id=p_intent_id AND user_uid=p_user_uid FOR UPDATE;
  IF v_intent.id IS NULL THEN RAISE EXCEPTION 'CONSULTATION_INTENT_NOT_FOUND'; END IF;
  IF v_intent.status NOT IN ('draft','payment_needs_slot') THEN
    IF v_intent.status='payment_pending' THEN
      SELECT * INTO v_payment FROM public.payments WHERE consultation_intent_id=v_intent.id;
      RETURN jsonb_build_object('success',true,'payment_id',v_payment.id,'duplicate',true);
    END IF;
    RAISE EXCEPTION 'CONSULTATION_INTENT_NOT_PAYABLE';
  END IF;
  IF v_intent.reservation_id IS NOT NULL THEN
    SELECT * INTO v_res FROM public.lawyer_time_reservations WHERE id=v_intent.reservation_id FOR UPDATE;
    IF v_res.id IS NULL OR v_res.status<>'held' OR v_res.hold_expires_at<=now() THEN
      UPDATE public.consultation_intents SET status='payment_needs_slot',ts_upd=now() WHERE id=v_intent.id;
      RAISE EXCEPTION 'SLOT_HOLD_EXPIRED';
    END IF;
  END IF;

  v_channel:=trim(COALESCE(p_payment->>'channel',''));
  v_proof:=trim(COALESCE(p_payment->>'proof',''));
  v_ref:=trim(COALESCE(p_payment->>'ref',''));
  v_amt:=COALESCE((p_payment->>'amt')::numeric,-1);
  IF v_channel='' THEN RAISE EXCEPTION 'INVALID_CHANNEL'; END IF;
  IF v_proof='' OR v_ref='' THEN RAISE EXCEPTION 'MISSING_PAYMENT_PROOF_OR_REFERENCE'; END IF;
  IF v_proof NOT LIKE p_user_uid::text || '/%' OR position('..' IN v_proof)>0 THEN
    RAISE EXCEPTION 'UNAUTHORIZED_FOLDER';
  END IF;
  IF v_amt<>v_intent.quoted_amount THEN RAISE EXCEPTION 'AMOUNT_MISMATCH'; END IF;

  INSERT INTO public.payments(
    uid,tp,pkg,amt,cur,mtd,channel,proof,ref,meta,sts,consultation_intent_id,ts_crt
  ) VALUES (
    p_user_uid,2,v_intent.service_type,v_intent.quoted_amount,1,0,v_channel,v_proof,v_ref,
    jsonb_build_object('service','legal_consultation','flow',v_intent.flow,'intent_id',v_intent.id,
      'continue_chat',CASE WHEN v_intent.flow='phone_renew' THEN v_intent.parent_consultation_id::text ELSE NULL END),
    0,v_intent.id,now()
  ) RETURNING * INTO v_payment;
  UPDATE public.consultation_intents SET status='payment_pending',ts_upd=now() WHERE id=v_intent.id;
  RETURN jsonb_build_object('success',true,'payment_id',v_payment.id,'intent_id',v_intent.id,
    'amount',v_payment.amt,'status',v_payment.sts);
END;
$function$;

REVOKE ALL ON FUNCTION public.create_consultation_payment_v2(uuid,uuid,jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_consultation_payment_v2(uuid,uuid,jsonb) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.create_consultation_payment_v2(uuid,uuid,jsonb) TO service_role;

-- انتهاء الحجوزات المؤقتة دون إشعارات كاذبة.
CREATE OR REPLACE FUNCTION public.expire_consultation_reservations_v2()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v_count integer;
BEGIN
  WITH expired AS (
    UPDATE public.lawyer_time_reservations SET status='expired',ts_upd=now()
    WHERE status='held' AND hold_expires_at<=now() RETURNING consultation_intent_id
  ), changed AS (
    UPDATE public.consultation_intents i SET status='payment_needs_slot',ts_upd=now()
    WHERE i.id IN (SELECT consultation_intent_id FROM expired)
      AND i.status IN ('draft','payment_pending') RETURNING 1
  ) SELECT COUNT(*) INTO v_count FROM expired;
  RETURN v_count;
END;
$function$;

REVOKE ALL ON FUNCTION public.expire_consultation_reservations_v2() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.expire_consultation_reservations_v2() FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.expire_consultation_reservations_v2() TO service_role;

DO $cron$
DECLARE v_job integer;
BEGIN
  SELECT jobid INTO v_job FROM cron.job WHERE command='SELECT public.expire_consultation_reservations_v2();' LIMIT 1;
  IF v_job IS NOT NULL THEN PERFORM cron.unschedule(v_job); END IF;
  PERFORM cron.schedule('expire-consultation-reservations-v2','*/5 * * * *',
    'SELECT public.expire_consultation_reservations_v2();');
END;
$cron$;

-- Backfill تاريخي بلا إشعار: حقول legacy تبقى المصدر حتى تفعيل V2.
INSERT INTO public.consultation_chat_sessions(
  consultation_id,ordinal,kind,payment_id,duration_minutes,free_extension_minutes,status,
  starts_at,ends_at,start_reason,ended_at,ts_crt,ts_upd
)
SELECT l.id,1,'legacy_aggregate',l.payment_id,
  GREATEST(1,COALESCE(l.chat_duration_minutes,15)),0,
  CASE WHEN l.status=1 AND now()<l.chat_started_at+make_interval(mins=>COALESCE(l.chat_duration_minutes,15))
       THEN 'active' ELSE 'ended' END,
  l.chat_started_at,l.chat_started_at+make_interval(mins=>COALESCE(l.chat_duration_minutes,15)),
  'legacy',CASE WHEN l.status=1 AND now()<l.chat_started_at+make_interval(mins=>COALESCE(l.chat_duration_minutes,15))
                THEN NULL ELSE COALESCE(l.ts_upd,l.chat_started_at+make_interval(mins=>COALESCE(l.chat_duration_minutes,15))) END,
  l.ts_crt,now()
FROM public.legal_consultations l
WHERE l.chat_started_at IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.consultation_chat_sessions s WHERE s.consultation_id=l.id);
