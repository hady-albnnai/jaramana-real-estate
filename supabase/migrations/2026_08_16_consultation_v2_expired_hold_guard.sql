-- 2026-08-16 — حفظ payment_needs_slot دون أن يلغيه RAISE/rollback.
CREATE OR REPLACE FUNCTION public.approve_payment_final_v5(p_payment_id uuid,p_admin_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v_pay public.payments%ROWTYPE; v_intent public.consultation_intents%ROWTYPE;
 v_res public.lawyer_time_reservations%ROWTYPE; v_role integer;
BEGIN
 SELECT * INTO v_pay FROM public.payments WHERE id=p_payment_id FOR UPDATE;
 IF v_pay.id IS NULL THEN RAISE EXCEPTION 'PAYMENT_NOT_FOUND'; END IF;
 IF v_pay.consultation_intent_id IS NULL THEN RETURN public.approve_payment_final_v4(p_payment_id,p_admin_id); END IF;
 SELECT * INTO v_intent FROM public.consultation_intents WHERE id=v_pay.consultation_intent_id FOR UPDATE;
 IF v_intent.reservation_id IS NULL THEN RETURN public.approve_payment_final_v4(p_payment_id,p_admin_id); END IF;
 SELECT role INTO v_role FROM public.users WHERE id=p_admin_id AND sts=0 AND i_del=0;
 IF v_role IS NULL OR v_role<5 THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
 SELECT * INTO v_res FROM public.lawyer_time_reservations WHERE id=v_intent.reservation_id FOR UPDATE;
 IF v_res.id IS NULL OR v_res.status<>'held' OR v_res.hold_expires_at<=now() THEN
  UPDATE public.lawyer_time_reservations SET status='expired',ts_upd=now()
   WHERE id=v_intent.reservation_id AND status='held';
  UPDATE public.consultation_intents SET status='payment_needs_slot',failure_code='SLOT_HOLD_EXPIRED',ts_upd=now()
   WHERE id=v_intent.id AND status='payment_pending';
  INSERT INTO public.notifications(uid,tp,ttl,bdy,ref_id,act,i_rd,i_del,ts_crt)
  VALUES(v_intent.user_uid,1,'📅 اختر موعداً جديداً',
   'انتهت مهلة الموعد المؤقت. اختر موعداً جديداً وستبقى دفعتك الحالية دون دفع ثانٍ.',
   v_intent.id::text,'legal_payment_needs_new_slot',0,0,now());
  RETURN jsonb_build_object('success',false,'error','SLOT_HOLD_EXPIRED',
   'intent_id',v_intent.id,'payment_id',v_pay.id,'needs_new_slot',true);
 END IF;
 RETURN public.approve_payment_final_v4(p_payment_id,p_admin_id);
END;
$function$;
REVOKE ALL ON FUNCTION public.approve_payment_final_v5(uuid,uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.approve_payment_final_v5(uuid,uuid) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.approve_payment_final_v5(uuid,uuid) TO service_role;
