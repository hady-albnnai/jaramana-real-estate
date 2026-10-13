-- 2026-08-16 — إعادة جدولة الجلسة القانونية بنفس الدفعة والمحامي.
CREATE OR REPLACE FUNCTION public.reschedule_legal_appointment_v2(
 p_actor_uid uuid,p_appointment_id uuid,p_slot timestamptz,p_idempotency_key uuid
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE a public.appointments%ROWTYPE; c public.legal_consultations%ROWTYPE;
 old_r public.lawyer_time_reservations%ROWTYPE; new_r uuid; v_role integer; v_gap integer;
BEGIN
 IF p_slot IS NULL OR p_idempotency_key IS NULL THEN RAISE EXCEPTION 'MISSING_REQUIRED_FIELDS'; END IF;
 SELECT role INTO v_role FROM public.users WHERE id=p_actor_uid AND sts=0 AND i_del=0;
 SELECT * INTO a FROM public.appointments WHERE id=p_appointment_id AND kind='legal' FOR UPDATE;
 IF a.id IS NULL THEN RAISE EXCEPTION 'APPOINTMENT_NOT_FOUND'; END IF;
 IF p_actor_uid NOT IN (a.req_uid,a.bkr_id) AND COALESCE(v_role,-1) NOT IN (5,6) THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
 IF a.sts=2 OR a.dt<=now() THEN RAISE EXCEPTION 'APPOINTMENT_FINALIZED'; END IF;
 SELECT * INTO c FROM public.legal_consultations WHERE id=a.consultation_id AND i_del=0 FOR UPDATE;
 IF c.id IS NULL THEN RAISE EXCEPTION 'CONSULTATION_NOT_FOUND'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.get_lawyer_free_slots(a.bkr_id,30) s
   WHERE abs(extract(epoch FROM(s.slot_dt-p_slot)))<1) THEN RAISE EXCEPTION 'SLOT_NO_LONGER_AVAILABLE'; END IF;
 SELECT * INTO old_r FROM public.lawyer_time_reservations WHERE appointment_id=a.id ORDER BY ts_crt DESC LIMIT 1 FOR UPDATE;
 IF old_r.id IS NULL THEN RAISE EXCEPTION 'RESERVATION_NOT_FOUND'; END IF;
 UPDATE public.lawyer_time_reservations SET status='released',ts_upd=now() WHERE id=old_r.id;
 v_gap:=GREATEST(15,COALESCE((public.appt_booking_config()->>'gap_mins')::integer,60));
 BEGIN
  INSERT INTO public.lawyer_time_reservations(lawyer_uid,user_uid,consultation_intent_id,
   slot_start,slot_end,status,hold_expires_at,appointment_id,idempotency_key)
  VALUES(a.bkr_id,a.req_uid,old_r.consultation_intent_id,p_slot,p_slot+make_interval(mins=>v_gap),
   'confirmed',now(),a.id,p_idempotency_key) RETURNING id INTO new_r;
 EXCEPTION WHEN exclusion_violation OR unique_violation THEN
  UPDATE public.lawyer_time_reservations SET status='confirmed',ts_upd=now() WHERE id=old_r.id;
  RAISE EXCEPTION 'SLOT_NO_LONGER_AVAILABLE';
 END;
 UPDATE public.appointments SET dt=p_slot,dt_end=p_slot+make_interval(mins=>v_gap),sts=1,
  cnl_by=NULL,cnl_rsn=NULL,rmnd_24=0,rmnd_2=0,rmnd_qtr=0,rmnd_end=0 WHERE id=a.id;
 UPDATE public.legal_consultations SET status=1,requested_slot=p_slot,ts_upd=now() WHERE id=c.id;
 INSERT INTO public.notifications(uid,tp,ttl,bdy,ref_id,act,i_rd,i_del,ts_crt)
 SELECT x.uid,1,'📅 تم تغيير موعد الجلسة القانونية',
  'الموعد الجديد: '||to_char(p_slot AT TIME ZONE 'Asia/Damascus','YYYY/MM/DD HH24:MI'),
  a.id::text,'legal_appointment_update',0,0,now()
 FROM (VALUES(a.req_uid),(a.bkr_id)) x(uid) WHERE x.uid IS NOT NULL AND x.uid<>p_actor_uid;
 RETURN jsonb_build_object('success',true,'appointment_id',a.id,'reservation_id',new_r,
  'slot',p_slot,'status',1);
END;
$function$;
REVOKE ALL ON FUNCTION public.reschedule_legal_appointment_v2(uuid,uuid,timestamptz,uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.reschedule_legal_appointment_v2(uuid,uuid,timestamptz,uuid) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.reschedule_legal_appointment_v2(uuid,uuid,timestamptz,uuid) TO service_role;
