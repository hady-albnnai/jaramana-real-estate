-- 2026-08-16 — اختيار موعد بديل لنفس intent/دفعة بعد انتهاء hold.
CREATE OR REPLACE FUNCTION public.replace_consultation_reservation_v2(
  p_user_uid uuid,p_intent_id uuid,p_slot timestamptz,p_allow_other_lawyer boolean,p_idempotency_key uuid
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v_intent public.consultation_intents%ROWTYPE; v_parent public.legal_consultations%ROWTYPE;
 v_lawyer uuid; v_res uuid; v_gap integer; v_alias text; v_status text;
BEGIN
 SELECT * INTO v_intent FROM public.consultation_intents WHERE id=p_intent_id AND user_uid=p_user_uid FOR UPDATE;
 IF v_intent.id IS NULL THEN RAISE EXCEPTION 'CONSULTATION_INTENT_NOT_FOUND'; END IF;
 IF v_intent.service_type<>1 OR v_intent.status NOT IN ('payment_needs_slot','payment_pending','draft') THEN
  RAISE EXCEPTION 'CONSULTATION_INTENT_NOT_RESCHEDULABLE';
 END IF;
 IF p_slot IS NULL OR p_idempotency_key IS NULL THEN RAISE EXCEPTION 'MISSING_REQUIRED_FIELDS'; END IF;
 SELECT * INTO v_parent FROM public.legal_consultations WHERE id=v_intent.parent_consultation_id AND i_del=0;
 IF v_intent.flow='onsite_convert' AND v_parent.id IS NULL THEN RAISE EXCEPTION 'CONSULTATION_NOT_FOUND'; END IF;
 IF v_intent.flow='onsite_convert' AND NOT p_allow_other_lawyer THEN
  v_lawyer:=v_parent.lawyer_uid;
  IF NOT EXISTS(SELECT 1 FROM public.get_lawyer_free_slots(v_lawyer,30) s WHERE abs(extract(epoch FROM(s.slot_dt-p_slot)))<1) THEN
   RAISE EXCEPTION 'SLOT_NO_LONGER_AVAILABLE';
  END IF;
 ELSE
  SELECT lp.uid INTO v_lawyer FROM public.lawyer_profiles lp JOIN public.users u ON u.id=lp.uid
  WHERE lp.is_active=true AND u.role=7 AND u.sts=0 AND u.i_del=0
   AND (v_intent.flow<>'onsite_convert' OR p_allow_other_lawyer OR lp.uid=v_parent.lawyer_uid)
   AND EXISTS(SELECT 1 FROM public.get_lawyer_free_slots(lp.uid,30) s WHERE abs(extract(epoch FROM(s.slot_dt-p_slot)))<1)
  ORDER BY CASE WHEN lp.uid=v_parent.lawyer_uid THEN 0 ELSE 1 END,lp.active_tasks_count,lp.created_at LIMIT 1;
 END IF;
 IF v_lawyer IS NULL THEN RAISE EXCEPTION 'SLOT_NO_LONGER_AVAILABLE'; END IF;
 UPDATE public.lawyer_time_reservations SET status='released',ts_upd=now()
  WHERE consultation_intent_id=v_intent.id AND status IN ('held','expired');
 v_gap:=GREATEST(15,COALESCE((public.appt_booking_config()->>'gap_mins')::integer,60));
 BEGIN
  INSERT INTO public.lawyer_time_reservations(lawyer_uid,user_uid,consultation_intent_id,
   slot_start,slot_end,status,hold_expires_at,idempotency_key)
  VALUES(v_lawyer,p_user_uid,v_intent.id,p_slot,p_slot+make_interval(mins=>v_gap),'held',
   now()+interval '6 hours',p_idempotency_key) RETURNING id INTO v_res;
 EXCEPTION WHEN exclusion_violation OR unique_violation THEN RAISE EXCEPTION 'SLOT_NO_LONGER_AVAILABLE'; END;
 v_status:=CASE WHEN EXISTS(SELECT 1 FROM public.payments WHERE consultation_intent_id=v_intent.id AND sts=0)
  THEN 'payment_pending' ELSE 'draft' END;
 UPDATE public.consultation_intents SET reservation_id=v_res,lawyer_uid=v_lawyer,
  other_lawyer_consent=(v_intent.flow='onsite_convert' AND v_lawyer<>v_parent.lawyer_uid),
  status=v_status,expires_at=now()+interval '6 hours',failure_code=NULL,ts_upd=now()
 WHERE id=v_intent.id;
 v_alias:=public.lawyer_alias_for(v_lawyer);
 RETURN jsonb_build_object('success',true,'intent_id',v_intent.id,'reservation_id',v_res,
  'status',v_status,'hold_expires_at',now()+interval '6 hours','lawyer_alias',v_alias,
  'other_lawyer_consent',(v_intent.flow='onsite_convert' AND v_lawyer<>v_parent.lawyer_uid));
END;
$function$;
REVOKE ALL ON FUNCTION public.replace_consultation_reservation_v2(uuid,uuid,timestamptz,boolean,uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.replace_consultation_reservation_v2(uuid,uuid,timestamptz,boolean,uuid) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.replace_consultation_reservation_v2(uuid,uuid,timestamptz,boolean,uuid) TO service_role;
