-- =============================================================================
-- 2026-08-16 — exact lazy session boundaries + legal appointment reminders
-- =============================================================================

CREATE OR REPLACE FUNCTION public.sync_chat_session_v2(p_consultation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE s public.consultation_chat_sessions%ROWTYPE; c public.legal_consultations%ROWTYPE;
 v_changed boolean:=false; v_event text;
BEGIN
 SELECT * INTO c FROM public.legal_consultations WHERE id=p_consultation_id AND i_del=0 FOR UPDATE;
 IF c.id IS NULL THEN RAISE EXCEPTION 'CONSULTATION_NOT_FOUND'; END IF;
 SELECT * INTO s FROM public.consultation_chat_sessions
  WHERE consultation_id=c.id AND status IN ('join_window','active') ORDER BY ordinal DESC LIMIT 1 FOR UPDATE;
 IF s.id IS NULL THEN RETURN jsonb_build_object('success',true,'changed',false,'status',NULL); END IF;
 IF s.status='join_window' AND s.starts_at<=now() THEN
  UPDATE public.consultation_chat_sessions SET status='active',start_reason='grace_expired',ts_upd=now() WHERE id=s.id;
  UPDATE public.legal_consultations SET status=1,chat_started_at=s.starts_at,
   chat_duration_minutes=s.duration_minutes+s.free_extension_minutes,ts_upd=now() WHERE id=c.id;
  INSERT INTO public.notifications(uid,tp,ttl,bdy,ref_id,act,i_rd,i_del,ts_crt)
  VALUES(c.user_uid,1,'⏱️ بدأ وقت الاستشارة تلقائياً',
   'لم تدخل خلال مهلة الدقيقتين، وبدأ عداد الاستشارة تلقائياً.',c.id::text,
   'legal_session_auto_started',0,0,now());
  v_changed:=true; v_event:='active'; s.status:='active';
 END IF;
 IF s.status='active' AND s.ends_at<=now() THEN
  UPDATE public.consultation_chat_sessions SET status='ended',ended_at=now(),ts_upd=now() WHERE id=s.id;
  UPDATE public.legal_consultations SET status=2,ts_upd=now() WHERE id=c.id;
  INSERT INTO public.notifications(uid,tp,ttl,bdy,ref_id,act,i_rd,i_del,ts_crt)
  VALUES(c.user_uid,1,'⏱️ انتهى وقت الاستشارة',
   'يمكنك التجديد أو التحويل إلى جلسة حضورية أو إنهاء القضية وتقييمها.',c.id::text,
   'legal_session_ended',0,0,now());
  v_changed:=true; v_event:='ended'; s.status:='ended';
 END IF;
 RETURN jsonb_build_object('success',true,'changed',v_changed,'status',s.status,
  'event',v_event,'consultation_id',c.id,'session_id',s.id);
END;
$function$;
REVOKE ALL ON FUNCTION public.sync_chat_session_v2(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sync_chat_session_v2(uuid) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.sync_chat_session_v2(uuid) TO service_role;

-- مواعيد العروض فقط في التذكير والصيانة العامة.
CREATE OR REPLACE FUNCTION public.send_appointment_reminders()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v integer;
BEGIN
 FOR v IN WITH due AS (
  UPDATE public.appointments SET rmnd_24=1 WHERE kind='offer' AND sts=1 AND i_force=0
   AND dt>now() AND dt<=now()+interval '24 hours' AND rmnd_24=0
  RETURNING id,req_uid,supervisor_uid,off_id,dt)
  SELECT public._appt_reminder_fanout(id,req_uid,supervisor_uid,off_id,dt,'غداً (قبل ٢٤ ساعة)') FROM due LOOP END LOOP;
 FOR v IN WITH due AS (
  UPDATE public.appointments SET rmnd_2=1 WHERE kind='offer' AND sts=1 AND i_force=0
   AND dt>now() AND dt<=now()+interval '2 hours' AND rmnd_2=0
  RETURNING id,req_uid,supervisor_uid,off_id,dt)
  SELECT public._appt_reminder_fanout(id,req_uid,supervisor_uid,off_id,dt,'بعد ساعتين') FROM due LOOP END LOOP;
 FOR v IN WITH due AS (
  UPDATE public.appointments SET rmnd_qtr=1 WHERE kind='offer' AND sts=1 AND i_force=0
   AND dt>now() AND dt<=now()+interval '15 minutes' AND rmnd_qtr=0
  RETURNING id,req_uid,supervisor_uid,off_id,dt)
  SELECT public._appt_reminder_fanout(id,req_uid,supervisor_uid,off_id,dt,'بعد ربع ساعة — انطلق الآن') FROM due LOOP END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.send_legal_appointment_reminders_v2()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE r record; v_count integer:=0; v_label text;
BEGIN
 FOR r IN
  WITH due AS (
   UPDATE public.appointments SET rmnd_24=1 WHERE kind='legal' AND sts=1
    AND dt>now() AND dt<=now()+interval '24 hours' AND rmnd_24=0 RETURNING *)
  SELECT * FROM due
 LOOP
  v_label:='خلال 24 ساعة'; v_count:=v_count+1;
  INSERT INTO public.notifications(uid,tp,ttl,bdy,ref_id,act,i_rd,i_del,ts_crt)
  SELECT x.uid,1,'⚖️ تذكير بالجلسة القانونية',
   'موعد الجلسة '||v_label||' — '||to_char(r.dt AT TIME ZONE 'Asia/Damascus','YYYY/MM/DD HH24:MI'),
   r.id::text,'legal_appointment_reminder',0,0,now()
  FROM (VALUES(r.req_uid),(r.bkr_id)) x(uid) WHERE x.uid IS NOT NULL;
 END LOOP;
 FOR r IN WITH due AS (
  UPDATE public.appointments SET rmnd_2=1 WHERE kind='legal' AND sts=1
   AND dt>now() AND dt<=now()+interval '2 hours' AND rmnd_2=0 RETURNING *) SELECT * FROM due
 LOOP
  v_label:='خلال ساعتين'; v_count:=v_count+1;
  INSERT INTO public.notifications(uid,tp,ttl,bdy,ref_id,act,i_rd,i_del,ts_crt)
  SELECT x.uid,1,'⚖️ تذكير بالجلسة القانونية',
   'موعد الجلسة '||v_label||' — '||to_char(r.dt AT TIME ZONE 'Asia/Damascus','YYYY/MM/DD HH24:MI'),
   r.id::text,'legal_appointment_reminder',0,0,now()
  FROM (VALUES(r.req_uid),(r.bkr_id)) x(uid) WHERE x.uid IS NOT NULL;
 END LOOP;
 FOR r IN WITH due AS (
  UPDATE public.appointments SET rmnd_qtr=1 WHERE kind='legal' AND sts=1
   AND dt>now() AND dt<=now()+interval '15 minutes' AND rmnd_qtr=0 RETURNING *) SELECT * FROM due
 LOOP
  v_label:='خلال 15 دقيقة'; v_count:=v_count+1;
  INSERT INTO public.notifications(uid,tp,ttl,bdy,ref_id,act,i_rd,i_del,ts_crt)
  SELECT x.uid,1,'⚖️ الجلسة القانونية بعد 15 دقيقة',
   'يرجى التوجه إلى المكتب والاستعداد للجلسة — '||to_char(r.dt AT TIME ZONE 'Asia/Damascus','HH24:MI'),
   r.id::text,'legal_appointment_reminder',0,0,now()
  FROM (VALUES(r.req_uid),(r.bkr_id)) x(uid) WHERE x.uid IS NOT NULL;
 END LOOP;
 RETURN v_count;
END;
$function$;

CREATE OR REPLACE FUNCTION public.appointments_daily_maintenance()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v_closed integer:=0; r record;
BEGIN
 FOR r IN SELECT id,own_id,req_uid FROM public.appointments
  WHERE kind='offer' AND sts IN(0,1) AND dt<now()-interval '24 hours'
 LOOP
  UPDATE public.appointments SET sts=3,cnl_rsn='إغلاق تلقائي: مضى الموعد بلا تأكيد الحضور' WHERE id=r.id;
  v_closed:=v_closed+1;
 END LOOP;
 RETURN jsonb_build_object('success',true,'closed',v_closed,'ts',now());
END;
$function$;

REVOKE ALL ON FUNCTION public.send_legal_appointment_reminders_v2() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.send_legal_appointment_reminders_v2() FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.send_legal_appointment_reminders_v2() TO service_role;

DO $cron$
DECLARE v_job integer;
BEGIN
 SELECT jobid INTO v_job FROM cron.job WHERE command='SELECT public.send_legal_appointment_reminders_v2();' LIMIT 1;
 IF v_job IS NOT NULL THEN PERFORM cron.unschedule(v_job); END IF;
 PERFORM cron.schedule('legal-appointment-reminders-v2','*/15 * * * *',
  'SELECT public.send_legal_appointment_reminders_v2();');
END;
$cron$;

CREATE OR REPLACE FUNCTION public.enqueue_consultation_notification_push()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v_role integer;
BEGIN
 SELECT role INTO v_role FROM public.users WHERE id=NEW.uid;
 IF NEW.act IN ('legal_session_auto_started','legal_session_ended','legal_waitlist_available',
    'legal_payment_needs_new_slot','legal_appointment_reminder')
    OR (NEW.act='legal_onsite_confirmed' AND v_role=7)
    OR (NEW.act='legal_consultation_update' AND NEW.ttl LIKE '✅ قبل المحامي%') THEN
  INSERT INTO public.consultation_event_outbox(event_key,event_type,recipient_uid,reference_id,payload)
  VALUES('notification:'||NEW.id,NEW.act,NEW.uid,
   CASE WHEN NEW.ref_id ~* '^[0-9a-f-]{36}$' THEN NEW.ref_id::uuid ELSE NULL END,
   jsonb_build_object('title',NEW.ttl,'body',NEW.bdy,'act',NEW.act,'ref_id',NEW.ref_id))
  ON CONFLICT(event_key) DO NOTHING;
 END IF;
 RETURN NEW;
END;
$function$;
