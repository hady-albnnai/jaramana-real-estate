-- =============================================================================
-- 2026-08-16 — V2 payment notifications, rejection cleanup, reversal compensation
-- =============================================================================

CREATE OR REPLACE FUNCTION public.trg_consultation_payment_v2()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v_intent public.consultation_intents%ROWTYPE; v_title text; v_body text; v_act text;
BEGIN
  IF NEW.sts=OLD.sts OR NEW.consultation_intent_id IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO v_intent FROM public.consultation_intents WHERE id=NEW.consultation_intent_id;
  IF v_intent.id IS NULL THEN RETURN NEW; END IF;
  IF NEW.sts=1 THEN
    IF v_intent.flow='phone_new' THEN
      v_title:='✅ تم اعتماد دفعة الاستشارة';
      v_body:='تم إرسال استشارتك تلقائياً إلى المحامي. لا تحتاج لإرسال الطلب مرة ثانية.';
      v_act:='legal_consultation_update';
    ELSIF v_intent.flow='phone_renew' THEN
      v_title:='✅ تم اعتماد تجديد المحادثة';
      v_body:='تم تجهيز مدة جديدة وإشعار المحامي. يبدأ الوقت عند استئنافه وانضمامك أو بعد مهلة الدقيقتين.';
      v_act:='legal_renewal_paid_ready';
    ELSE
      v_title:='✅ تم تثبيت الجلسة الحضورية';
      v_body:='تم اعتماد الدفع وتأكيد الموعد تلقائياً ضمن وقت المحامي المنشور.';
      v_act:='legal_onsite_confirmed';
    END IF;
  ELSIF NEW.sts=2 THEN
    v_title:='❌ لم تُقبل دفعة الاستشارة';
    v_body:='لم تُقبل الدفعة. السبب: '||COALESCE(NULLIF(trim(NEW.meta->>'reject_reason'),''),'راجع البيانات وأعد المحاولة.');
    v_act:='payment';
    UPDATE public.consultation_intents SET status='failed',failure_code='PAYMENT_REJECTED',ts_upd=now()
     WHERE id=v_intent.id AND status='payment_pending';
    UPDATE public.lawyer_time_reservations SET status='released',ts_upd=now()
     WHERE consultation_intent_id=v_intent.id AND status='held';
  ELSIF NEW.sts=3 THEN
    v_title:='↩️ تم التراجع عن اعتماد الدفعة';
    v_body:='تم التراجع عن اعتماد الدفعة. راجع تفاصيل الاستشارة أو تواصل مع المكتب.';
    v_act:='payment_reversed';
  ELSE RETURN NEW;
  END IF;
  INSERT INTO public.notifications(uid,tp,ttl,bdy,ref_id,act,i_rd,i_del,ts_crt)
  VALUES(NEW.uid,3,v_title,v_body,NEW.id::text,v_act,0,0,now());
  PERFORM public.send_push_notification(NEW.uid,v_title,v_body,
    jsonb_build_object('act',v_act,'ref_id',COALESCE(v_intent.materialized_consultation_id,NEW.id)::text));
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.trg_consultation_payment_v2() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.trg_consultation_payment_v2() FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.trg_consultation_payment_v2() TO service_role;

DROP TRIGGER IF EXISTS trg_payment_notify ON public.payments;
CREATE TRIGGER trg_payment_notify AFTER UPDATE OF sts ON public.payments
FOR EACH ROW WHEN (NEW.consultation_intent_id IS NULL)
EXECUTE FUNCTION public.trg_payment_approved();
DROP TRIGGER IF EXISTS trg_payment_notify_v2 ON public.payments;
CREATE TRIGGER trg_payment_notify_v2 AFTER UPDATE OF sts ON public.payments
FOR EACH ROW WHEN (NEW.consultation_intent_id IS NOT NULL)
EXECUTE FUNCTION public.trg_consultation_payment_v2();

CREATE OR REPLACE FUNCTION public.admin_reverse_payment_v2(
  p_admin_uid uuid,p_payment_id uuid,p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v_role integer; v_pay public.payments%ROWTYPE; v_intent public.consultation_intents%ROWTYPE;
  v_cons public.legal_consultations%ROWTYPE; v_session public.consultation_chat_sessions%ROWTYPE;
  v_appt public.appointments%ROWTYPE;
BEGIN
  SELECT role INTO v_role FROM public.users WHERE id=p_admin_uid AND sts=0 AND i_del=0;
  IF v_role<>6 THEN RAISE EXCEPTION 'ONLY_MANAGER_CAN_REVERSE'; END IF;
  IF length(trim(COALESCE(p_reason,'')))<3 THEN RAISE EXCEPTION 'REVERSAL_REASON_REQUIRED'; END IF;
  SELECT * INTO v_pay FROM public.payments WHERE id=p_payment_id FOR UPDATE;
  IF v_pay.id IS NULL THEN RAISE EXCEPTION 'PAYMENT_NOT_FOUND'; END IF;
  IF v_pay.consultation_intent_id IS NULL THEN
    RETURN public.admin_reverse_payment(p_admin_uid,p_payment_id,p_reason);
  END IF;
  IF v_pay.sts<>1 THEN RAISE EXCEPTION 'PAYMENT_NOT_APPROVED'; END IF;
  SELECT * INTO v_intent FROM public.consultation_intents WHERE id=v_pay.consultation_intent_id FOR UPDATE;
  SELECT * INTO v_cons FROM public.legal_consultations WHERE id=v_intent.materialized_consultation_id FOR UPDATE;

  IF v_intent.flow='phone_renew' THEN
    SELECT * INTO v_session FROM public.consultation_chat_sessions WHERE payment_id=v_pay.id FOR UPDATE;
    IF v_session.status<>'ready' THEN RAISE EXCEPTION 'CONSULTATION_SERVICE_ALREADY_CONSUMED'; END IF;
    UPDATE public.consultation_chat_sessions SET status='reversed',ts_upd=now() WHERE id=v_session.id;
    UPDATE public.legal_consultations SET renew_count=GREATEST(0,COALESCE(renew_count,0)-1),ts_upd=now()
     WHERE id=v_intent.parent_consultation_id;
  ELSIF v_intent.flow='phone_new' THEN
    IF EXISTS(SELECT 1 FROM public.consultation_chat_sessions WHERE consultation_id=v_cons.id AND status IN ('join_window','active','ended')) THEN
      RAISE EXCEPTION 'CONSULTATION_SERVICE_ALREADY_CONSUMED';
    END IF;
    UPDATE public.legal_consultations SET status=3,notes='عكس دفعة: '||trim(p_reason),ts_upd=now() WHERE id=v_cons.id;
  ELSE
    SELECT * INTO v_appt FROM public.appointments WHERE consultation_id=v_cons.id FOR UPDATE;
    IF v_appt.sts=2 OR v_appt.dt<=now() THEN RAISE EXCEPTION 'CONSULTATION_SERVICE_ALREADY_CONSUMED'; END IF;
    UPDATE public.appointments SET sts=3,cnl_by=p_admin_uid,cnl_rsn='عكس دفعة: '||trim(p_reason) WHERE id=v_appt.id;
    UPDATE public.legal_consultations SET status=3,notes='عكس دفعة: '||trim(p_reason),ts_upd=now() WHERE id=v_cons.id;
    UPDATE public.lawyer_time_reservations SET status='cancelled',ts_upd=now()
     WHERE appointment_id=v_appt.id AND status='confirmed';
    IF v_intent.flow='onsite_convert' THEN
      UPDATE public.legal_consultations SET converted_to_onsite=false,onsite_discount=0,ts_upd=now()
       WHERE id=v_intent.parent_consultation_id;
    END IF;
  END IF;

  UPDATE public.consultation_intents SET status='cancelled',failure_code='PAYMENT_REVERSED',ts_upd=now() WHERE id=v_intent.id;
  UPDATE public.payments SET sts=3,meta=meta||jsonb_build_object('reversed_by',p_admin_uid,
    'reversed_at',now(),'reversal_reason',trim(p_reason),'prev_sts',1) WHERE id=v_pay.id;
  PERFORM public.update_lawyer_active_tasks(v_intent.lawyer_uid);
  PERFORM public.log_admin_action(p_admin_uid,121,'عكس دفعة استشارة V2 — '||trim(p_reason),p_payment_id::text,'payments');
  RETURN jsonb_build_object('success',true,'payment_id',p_payment_id,'flow',v_intent.flow,'compensated',true);
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_reverse_payment_v2(uuid,uuid,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_reverse_payment_v2(uuid,uuid,text) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reverse_payment_v2(uuid,uuid,text) TO service_role;
