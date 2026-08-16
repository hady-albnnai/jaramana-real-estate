-- =============================================================================
-- 2026-08-16 — waitlist + explicit consent for alternate lawyer
-- =============================================================================
ALTER TABLE public.consultation_intents
  ADD COLUMN IF NOT EXISTS other_lawyer_consent boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.prepare_alternate_onsite_intent_v2(
  p_user_uid uuid,p_parent_consultation_id uuid,p_slot timestamptz,p_idempotency_key uuid
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v_parent public.legal_consultations%ROWTYPE; v_cfg jsonb; v_phone numeric; v_onsite numeric;
  v_lawyer uuid; v_intent uuid; v_res uuid; v_gap integer; v_alias text;
BEGIN
  IF p_idempotency_key IS NULL OR p_slot IS NULL THEN RAISE EXCEPTION 'MISSING_REQUIRED_FIELDS'; END IF;
  SELECT * INTO v_parent FROM public.legal_consultations
   WHERE id=p_parent_consultation_id AND user_uid=p_user_uid AND service_type=0 AND i_del=0 FOR UPDATE;
  IF v_parent.id IS NULL THEN RAISE EXCEPTION 'CONSULTATION_NOT_FOUND'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_uid::text||':onsite_convert',0));
  SELECT id INTO v_intent FROM public.consultation_intents WHERE user_uid=p_user_uid AND idempotency_key=p_idempotency_key;
  IF v_intent IS NOT NULL THEN
    RETURN jsonb_build_object('success',true,'intent_id',v_intent,'duplicate',true);
  END IF;
  SELECT lp.uid INTO v_lawyer FROM public.lawyer_profiles lp JOIN public.users u ON u.id=lp.uid
  WHERE lp.uid<>v_parent.lawyer_uid AND lp.is_active=true AND u.role=7 AND u.sts=0 AND u.i_del=0
    AND EXISTS(SELECT 1 FROM public.get_lawyer_free_slots(lp.uid,30) s
      WHERE abs(extract(epoch FROM(s.slot_dt-p_slot)))<1)
  ORDER BY lp.active_tasks_count,lp.created_at LIMIT 1;
  IF v_lawyer IS NULL THEN RAISE EXCEPTION 'SLOT_NO_LONGER_AVAILABLE'; END IF;
  SELECT value INTO v_cfg FROM public.app_config WHERE key='main';
  v_phone:=(v_cfg->'legalPrice'->>'phone')::numeric; v_onsite:=(v_cfg->'legalPrice'->>'onsite')::numeric;
  IF v_phone IS NULL OR v_onsite IS NULL THEN RAISE EXCEPTION 'INVALID_LEGAL_PRICE'; END IF;
  v_gap:=GREATEST(15,COALESCE((public.appt_booking_config()->>'gap_mins')::integer,60));
  INSERT INTO public.consultation_intents(user_uid,flow,parent_consultation_id,subject,attachments,
    service_type,lawyer_uid,quoted_amount,base_discount,price_snapshot,status,idempotency_key,
    expires_at,other_lawyer_consent)
  VALUES(p_user_uid,'onsite_convert',v_parent.id,v_parent.subject,COALESCE(v_parent.attachments,'{}'),
    1,v_lawyer,GREATEST(0,v_onsite-v_phone),v_phone,
    jsonb_build_object('phone',v_phone,'onsite',v_onsite,'captured_at',now()),'draft',p_idempotency_key,
    now()+interval '6 hours',true) RETURNING id INTO v_intent;
  BEGIN
    INSERT INTO public.lawyer_time_reservations(lawyer_uid,user_uid,consultation_intent_id,
      slot_start,slot_end,status,hold_expires_at,idempotency_key)
    VALUES(v_lawyer,p_user_uid,v_intent,p_slot,p_slot+make_interval(mins=>v_gap),'held',
      now()+interval '6 hours',p_idempotency_key) RETURNING id INTO v_res;
  EXCEPTION WHEN exclusion_violation OR unique_violation THEN RAISE EXCEPTION 'SLOT_NO_LONGER_AVAILABLE'; END;
  UPDATE public.consultation_intents SET reservation_id=v_res WHERE id=v_intent;
  v_alias:=public.lawyer_alias_for(v_lawyer);
  RETURN jsonb_build_object('success',true,'intent_id',v_intent,'flow','onsite_convert',
    'quoted_amount',GREATEST(0,v_onsite-v_phone),'base_discount',v_phone,'reservation_id',v_res,
    'hold_expires_at',now()+interval '6 hours','lawyer_alias',v_alias,'other_lawyer_consent',true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.join_consultation_waitlist_v2(
  p_user_uid uuid,p_parent_consultation_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v_parent public.legal_consultations%ROWTYPE; v_id uuid;
BEGIN
  SELECT * INTO v_parent FROM public.legal_consultations
   WHERE id=p_parent_consultation_id AND user_uid=p_user_uid AND service_type=0 AND i_del=0;
  IF v_parent.id IS NULL OR v_parent.lawyer_uid IS NULL THEN RAISE EXCEPTION 'CONSULTATION_NOT_FOUND'; END IF;
  SELECT id INTO v_id FROM public.consultation_waitlist WHERE user_uid=p_user_uid
    AND lawyer_uid=v_parent.lawyer_uid AND parent_consultation_id=v_parent.id AND status='active';
  IF v_id IS NULL THEN
    INSERT INTO public.consultation_waitlist(user_uid,lawyer_uid,parent_consultation_id,status)
    VALUES(p_user_uid,v_parent.lawyer_uid,v_parent.id,'active') RETURNING id INTO v_id;
  END IF;
  RETURN jsonb_build_object('success',true,'waitlist_id',v_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.process_consultation_waitlist_v2()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE r record; v_count integer:=0;
BEGIN
  FOR r IN SELECT * FROM public.consultation_waitlist WHERE status='active' ORDER BY ts_crt
  LOOP
    IF EXISTS(SELECT 1 FROM public.get_lawyer_free_slots(r.lawyer_uid,30) LIMIT 1) THEN
      UPDATE public.consultation_waitlist SET status='notified',notified_at=now(),ts_upd=now() WHERE id=r.id;
      INSERT INTO public.notifications(uid,tp,ttl,bdy,ref_id,act,i_rd,i_del,ts_crt)
      VALUES(r.user_uid,1,'📅 أصبح موعد مع محاميك متاحاً',
        'أضيف أو تحرر موعد خلال الثلاثين يوماً القادمة. افتح الاستشارة واحجزه قبل أن يؤخذ.',
        r.parent_consultation_id::text,'legal_waitlist_available',0,0,now());
      v_count:=v_count+1;
    END IF;
  END LOOP;
  RETURN v_count;
END;
$function$;

REVOKE ALL ON FUNCTION public.prepare_alternate_onsite_intent_v2(uuid,uuid,timestamptz,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.join_consultation_waitlist_v2(uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.process_consultation_waitlist_v2() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.prepare_alternate_onsite_intent_v2(uuid,uuid,timestamptz,uuid) FROM anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.join_consultation_waitlist_v2(uuid,uuid) FROM anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.process_consultation_waitlist_v2() FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_alternate_onsite_intent_v2(uuid,uuid,timestamptz,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.join_consultation_waitlist_v2(uuid,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.process_consultation_waitlist_v2() TO service_role;

DO $cron$
DECLARE v_job integer;
BEGIN
 SELECT jobid INTO v_job FROM cron.job WHERE command='SELECT public.process_consultation_waitlist_v2();' LIMIT 1;
 IF v_job IS NOT NULL THEN PERFORM cron.unschedule(v_job); END IF;
 PERFORM cron.schedule('process-consultation-waitlist-v2','*/15 * * * *',
  'SELECT public.process_consultation_waitlist_v2();');
END;
$cron$;

-- V4 يعالج فقط التحويل بمحامٍ بديل مصرح به، ويفوض كل ما عداه إلى V3.
CREATE OR REPLACE FUNCTION public.approve_payment_final_v4(p_payment_id uuid,p_admin_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v_role integer; v_pay public.payments%ROWTYPE; v_intent public.consultation_intents%ROWTYPE;
 v_res public.lawyer_time_reservations%ROWTYPE; v_parent public.legal_consultations%ROWTYPE;
 v_child public.legal_consultations%ROWTYPE; v_appt uuid; v_alias text;
BEGIN
 IF auth.uid() IS NOT NULL AND auth.uid()<>p_admin_id THEN RAISE EXCEPTION 'AUTH_UID_MISMATCH'; END IF;
 SELECT * INTO v_pay FROM public.payments WHERE id=p_payment_id FOR UPDATE;
 IF v_pay.id IS NULL THEN RAISE EXCEPTION 'PAYMENT_NOT_FOUND'; END IF;
 IF v_pay.consultation_intent_id IS NULL THEN RETURN public.approve_payment_final_v3(p_payment_id,p_admin_id); END IF;
 SELECT * INTO v_intent FROM public.consultation_intents WHERE id=v_pay.consultation_intent_id FOR UPDATE;
 IF NOT (v_intent.flow='onsite_convert' AND v_intent.other_lawyer_consent) THEN
   RETURN public.approve_payment_final_v3(p_payment_id,p_admin_id);
 END IF;
 SELECT role INTO v_role FROM public.users WHERE id=p_admin_id AND sts=0 AND i_del=0;
 IF v_role IS NULL OR v_role<5 THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
 IF v_pay.sts<>0 OR v_intent.status<>'payment_pending' THEN RAISE EXCEPTION 'PAYMENT_NOT_PENDING'; END IF;
 SELECT * INTO v_parent FROM public.legal_consultations
  WHERE id=v_intent.parent_consultation_id AND user_uid=v_intent.user_uid AND service_type=0 AND i_del=0 FOR UPDATE;
 IF v_parent.id IS NULL OR v_parent.lawyer_uid=v_intent.lawyer_uid THEN RAISE EXCEPTION 'ALTERNATE_LAWYER_CONSENT_INVALID'; END IF;
 SELECT * INTO v_res FROM public.lawyer_time_reservations WHERE id=v_intent.reservation_id FOR UPDATE;
 IF v_res.id IS NULL OR v_res.status<>'held' OR v_res.hold_expires_at<=now() OR
    v_res.lawyer_uid<>v_intent.lawyer_uid OR v_res.user_uid<>v_intent.user_uid THEN
   UPDATE public.consultation_intents SET status='payment_needs_slot',ts_upd=now() WHERE id=v_intent.id;
   RAISE EXCEPTION 'SLOT_HOLD_EXPIRED';
 END IF;
 v_alias:=public.lawyer_alias_for(v_intent.lawyer_uid);
 INSERT INTO public.legal_consultations(user_uid,lawyer_uid,service_type,subject,price,status,
  attachments,lawyer_alias,payment_id,payment_status,parent_consultation_id,requested_slot,ts_crt,ts_upd)
 VALUES(v_intent.user_uid,v_intent.lawyer_uid,1,v_intent.subject,
  v_intent.quoted_amount+v_intent.base_discount,1,v_intent.attachments,v_alias,v_pay.id,1,
  v_parent.id,v_res.slot_start,now(),now()) RETURNING * INTO v_child;
 INSERT INTO public.appointments(kind,consultation_id,bkr_id,req_uid,dt,dt_end,sts,ts_crt,admin_nt,executor_notes)
 VALUES('legal',v_child.id,v_intent.lawyer_uid,v_intent.user_uid,v_res.slot_start,v_res.slot_end,1,now(),
  '⚖️ جلسة قانونية مؤكدة — محامٍ بديل بموافقة العميل','جلسة قانونية: '||left(v_intent.subject,180)) RETURNING id INTO v_appt;
 UPDATE public.legal_consultations SET appointment_id=v_appt WHERE id=v_child.id;
 UPDATE public.legal_consultations SET converted_to_onsite=true,onsite_discount=v_intent.base_discount,ts_upd=now() WHERE id=v_parent.id;
 UPDATE public.lawyer_time_reservations SET status='confirmed',appointment_id=v_appt,ts_upd=now() WHERE id=v_res.id;
 UPDATE public.consultation_intents SET status='materialized',materialized_consultation_id=v_child.id,ts_upd=now() WHERE id=v_intent.id;
 UPDATE public.payments SET sts=1,appr_by=p_admin_id WHERE id=v_pay.id AND sts=0;
 INSERT INTO public.notifications(uid,tp,ttl,bdy,ref_id,act,i_rd,i_del,ts_crt)
 VALUES(v_intent.user_uid,1,'✅ تم تثبيت الجلسة مع المحامي البديل',
  'تم اعتماد الدفع وتأكيد الموعد الذي وافقت عليه.',v_appt::text,'legal_onsite_confirmed',0,0,now()),
 (v_intent.lawyer_uid,1,'🏢 جلسة قانونية محولة إليك بموافقة العميل',
  'تم تثبيت جلسة مدفوعة ضمن وقتك المنشور.',v_appt::text,'legal_onsite_confirmed',0,0,now());
 PERFORM public.update_lawyer_active_tasks(v_intent.lawyer_uid);
 RETURN jsonb_build_object('success',true,'type','consultation_v2','flow',v_intent.flow,
  'consultation_id',v_child.id,'appointment_id',v_appt,'payment_id',v_pay.id,'alternate_lawyer',true);
END;
$function$;
REVOKE ALL ON FUNCTION public.approve_payment_final_v4(uuid,uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.approve_payment_final_v4(uuid,uuid) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.approve_payment_final_v4(uuid,uuid) TO service_role;
