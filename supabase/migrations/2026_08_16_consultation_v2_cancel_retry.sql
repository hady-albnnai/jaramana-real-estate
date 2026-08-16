-- =============================================================================
-- 2026-08-16 — no-refund onsite cancellation + rejected payment retry
-- =============================================================================

CREATE OR REPLACE FUNCTION public.cancel_legal_appointment_v2(
 p_user_uid uuid,p_appointment_id uuid,p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE a public.appointments%ROWTYPE; c public.legal_consultations%ROWTYPE;
BEGIN
 IF length(trim(COALESCE(p_reason,'')))<5 THEN RAISE EXCEPTION 'CANCEL_REASON_REQUIRED'; END IF;
 SELECT * INTO a FROM public.appointments WHERE id=p_appointment_id AND kind='legal' FOR UPDATE;
 IF a.id IS NULL THEN RAISE EXCEPTION 'APPOINTMENT_NOT_FOUND'; END IF;
 IF a.req_uid<>p_user_uid THEN RAISE EXCEPTION 'NOT_YOUR_APPOINTMENT'; END IF;
 IF a.sts<>1 OR a.dt<=now() THEN RAISE EXCEPTION 'APPOINTMENT_FINALIZED'; END IF;
 SELECT * INTO c FROM public.legal_consultations WHERE id=a.consultation_id AND i_del=0 FOR UPDATE;
 UPDATE public.appointments SET sts=3,cnl_by=p_user_uid,
  cnl_rsn='إلغاء المستخدم بلا استرداد: '||trim(p_reason) WHERE id=a.id;
 UPDATE public.legal_consultations SET status=3,
  notes='ألغى المستخدم الجلسة — لا استرداد ولا رصيد. السبب: '||trim(p_reason),ts_upd=now() WHERE id=c.id;
 UPDATE public.lawyer_time_reservations SET status='cancelled',ts_upd=now()
  WHERE appointment_id=a.id AND status='confirmed';
 INSERT INTO public.notifications(uid,tp,ttl,bdy,ref_id,act,i_rd,i_del,ts_crt)
 SELECT x.uid,1,'⚠️ ألغى المستخدم الجلسة القانونية',
  'أُلغي الموعد. وفق سياسة الخدمة لا يعاد المبلغ ولا يمنح رصيد بعد اعتماد الدفع. السبب: '||trim(p_reason),
  a.id::text,'legal_appointment_update',0,0,now()
 FROM (VALUES(a.bkr_id)) x(uid) WHERE x.uid IS NOT NULL;
 PERFORM public.update_lawyer_active_tasks(a.bkr_id);
 RETURN jsonb_build_object('success',true,'appointment_id',a.id,'status',3,
  'refund',false,'credit_granted',false);
END;
$function$;

CREATE OR REPLACE FUNCTION public.prepare_rejected_payment_retry_v2(p_user_uid uuid,p_intent_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE i public.consultation_intents%ROWTYPE; p public.payments%ROWTYPE; v_status text;
BEGIN
 SELECT * INTO i FROM public.consultation_intents WHERE id=p_intent_id AND user_uid=p_user_uid FOR UPDATE;
 IF i.id IS NULL OR i.status<>'failed' OR i.failure_code<>'PAYMENT_REJECTED' THEN
  RAISE EXCEPTION 'CONSULTATION_INTENT_NOT_RETRYABLE';
 END IF;
 SELECT * INTO p FROM public.payments WHERE consultation_intent_id=i.id AND sts=2 FOR UPDATE;
 IF p.id IS NULL THEN RAISE EXCEPTION 'REJECTED_PAYMENT_NOT_FOUND'; END IF;
 v_status:=CASE WHEN i.service_type=1 THEN 'payment_needs_slot' ELSE 'draft' END;
 UPDATE public.consultation_intents SET status=v_status,failure_code=NULL,ts_upd=now() WHERE id=i.id;
 RETURN jsonb_build_object('success',true,'intent_id',i.id,'payment_id',p.id,'status',v_status,
  'flow',i.flow,'parent_consultation_id',i.parent_consultation_id,'subject',i.subject,
  'attachments',i.attachments,'service_type',i.service_type,'quoted_amount',i.quoted_amount);
END;
$function$;

CREATE OR REPLACE FUNCTION public.retry_consultation_payment_v2(
 p_user_uid uuid,p_intent_id uuid,p_payment jsonb
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE i public.consultation_intents%ROWTYPE; p public.payments%ROWTYPE;
 v_res public.lawyer_time_reservations%ROWTYPE; v_proof text; v_ref text; v_channel text; v_amt numeric;
BEGIN
 SELECT * INTO i FROM public.consultation_intents WHERE id=p_intent_id AND user_uid=p_user_uid FOR UPDATE;
 IF i.id IS NULL OR i.status<>'draft' THEN RAISE EXCEPTION 'CONSULTATION_INTENT_NOT_RETRYABLE'; END IF;
 IF i.service_type=1 THEN
  SELECT * INTO v_res FROM public.lawyer_time_reservations WHERE id=i.reservation_id FOR UPDATE;
  IF v_res.id IS NULL OR v_res.status<>'held' OR v_res.hold_expires_at<=now() THEN RAISE EXCEPTION 'SLOT_HOLD_EXPIRED'; END IF;
 END IF;
 SELECT * INTO p FROM public.payments WHERE consultation_intent_id=i.id AND sts=2 FOR UPDATE;
 IF p.id IS NULL THEN RAISE EXCEPTION 'REJECTED_PAYMENT_NOT_FOUND'; END IF;
 v_proof:=trim(COALESCE(p_payment->>'proof','')); v_ref:=trim(COALESCE(p_payment->>'ref',''));
 v_channel:=trim(COALESCE(p_payment->>'channel','')); v_amt:=COALESCE((p_payment->>'amt')::numeric,-1);
 IF v_proof='' OR v_ref='' THEN RAISE EXCEPTION 'MISSING_PAYMENT_PROOF_OR_REFERENCE'; END IF;
 IF v_proof NOT LIKE p_user_uid::text||'/%' OR position('..' IN v_proof)>0 THEN RAISE EXCEPTION 'UNAUTHORIZED_FOLDER'; END IF;
 IF v_amt<>i.quoted_amount THEN RAISE EXCEPTION 'AMOUNT_MISMATCH'; END IF;
 UPDATE public.payments SET sts=0,appr_by=NULL,proof=v_proof,ref=v_ref,channel=v_channel,
  meta=(meta-'reject_reason')||jsonb_build_object('retried_at',now()) WHERE id=p.id;
 UPDATE public.consultation_intents SET status='payment_pending',ts_upd=now() WHERE id=i.id;
 RETURN jsonb_build_object('success',true,'payment_id',p.id,'intent_id',i.id,'status',0,'reused',true);
END;
$function$;

REVOKE ALL ON FUNCTION public.cancel_legal_appointment_v2(uuid,uuid,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.prepare_rejected_payment_retry_v2(uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.retry_consultation_payment_v2(uuid,uuid,jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cancel_legal_appointment_v2(uuid,uuid,text) FROM anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.prepare_rejected_payment_retry_v2(uuid,uuid) FROM anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.retry_consultation_payment_v2(uuid,uuid,jsonb) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_legal_appointment_v2(uuid,uuid,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.prepare_rejected_payment_retry_v2(uuid,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.retry_consultation_payment_v2(uuid,uuid,jsonb) TO service_role;
