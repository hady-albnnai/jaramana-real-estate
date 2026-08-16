-- =============================================================================
-- 2026-08-16 — Consultation Flow V2: session lifecycle + two-minute join window
-- =============================================================================

CREATE OR REPLACE FUNCTION public.ensure_initial_chat_session_v2(p_consultation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v_cons public.legal_consultations%ROWTYPE; v_cfg jsonb; v_minutes integer; v_session uuid;
BEGIN
  SELECT * INTO v_cons FROM public.legal_consultations WHERE id=p_consultation_id AND i_del=0 FOR UPDATE;
  IF v_cons.id IS NULL THEN RAISE EXCEPTION 'CONSULTATION_NOT_FOUND'; END IF;
  IF v_cons.service_type<>0 OR v_cons.status<>1 THEN RAISE EXCEPTION 'CONSULTATION_NOT_CONFIRMED'; END IF;
  SELECT id INTO v_session FROM public.consultation_chat_sessions
   WHERE consultation_id=v_cons.id AND status IN ('ready','join_window','active') ORDER BY ordinal DESC LIMIT 1;
  IF v_session IS NOT NULL THEN RETURN jsonb_build_object('success',true,'session_id',v_session,'duplicate',true); END IF;
  SELECT value INTO v_cfg FROM public.app_config WHERE key='main';
  v_minutes:=(v_cfg->'legalPrice'->>'durationMins')::integer;
  IF v_minutes IS NULL OR v_minutes<1 THEN RAISE EXCEPTION 'INVALID_DURATION_MINS'; END IF;
  INSERT INTO public.consultation_chat_sessions(consultation_id,ordinal,kind,duration_minutes,status)
  VALUES(v_cons.id,COALESCE((SELECT MAX(ordinal)+1 FROM public.consultation_chat_sessions WHERE consultation_id=v_cons.id),1),
    'initial',v_minutes,'ready') RETURNING id INTO v_session;
  RETURN jsonb_build_object('success',true,'session_id',v_session,'duration_minutes',v_minutes);
END;
$function$;

CREATE OR REPLACE FUNCTION public.lawyer_ready_chat_session_v2(
  p_lawyer_uid uuid,p_consultation_id uuid,p_idempotency_key uuid
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v_cons public.legal_consultations%ROWTYPE; v_session public.consultation_chat_sessions%ROWTYPE;
  v_ready timestamptz:=now(); v_deadline timestamptz;
BEGIN
  IF p_idempotency_key IS NULL THEN RAISE EXCEPTION 'IDEMPOTENCY_KEY_REQUIRED'; END IF;
  SELECT * INTO v_cons FROM public.legal_consultations WHERE id=p_consultation_id AND i_del=0 FOR UPDATE;
  IF v_cons.id IS NULL THEN RAISE EXCEPTION 'CONSULTATION_NOT_FOUND'; END IF;
  IF v_cons.lawyer_uid<>p_lawyer_uid THEN RAISE EXCEPTION 'NOT_ASSIGNED_LAWYER'; END IF;
  SELECT * INTO v_session FROM public.consultation_chat_sessions
   WHERE consultation_id=v_cons.id AND status IN ('ready','join_window') ORDER BY ordinal DESC LIMIT 1 FOR UPDATE;
  IF v_session.id IS NULL THEN RAISE EXCEPTION 'NO_READY_CHAT_SESSION'; END IF;
  IF v_session.status='join_window' THEN
    RETURN jsonb_build_object('success',true,'session_id',v_session.id,'join_deadline',v_session.join_deadline,
      'starts_at',v_session.starts_at,'duplicate',true);
  END IF;
  v_deadline:=v_ready+interval '2 minutes';
  UPDATE public.consultation_chat_sessions SET status='join_window',lawyer_ready_at=v_ready,
    join_deadline=v_deadline,starts_at=v_deadline,
    ends_at=v_deadline+make_interval(mins=>v_session.duration_minutes),ready_idempotency_key=p_idempotency_key,ts_upd=now()
  WHERE id=v_session.id;
  INSERT INTO public.notifications(uid,tp,ttl,bdy,ref_id,act,i_rd,i_del,ts_crt)
  VALUES(v_cons.user_uid,1,'💬 المحامي جاهز لبدء الاستشارة',
    'افتح المحادثة خلال دقيقتين. يبدأ الوقت عند دخولك أو تلقائياً بعد انتهاء المهلة.',
    v_cons.id::text,'legal_lawyer_ready',0,0,now());
  INSERT INTO public.consultation_event_outbox(event_key,event_type,recipient_uid,reference_id,payload)
  VALUES('lawyer-ready:'||v_session.id,'legal_lawyer_ready',v_cons.user_uid,v_cons.id,
    jsonb_build_object('session_id',v_session.id,'join_deadline',v_deadline)) ON CONFLICT(event_key) DO NOTHING;
  RETURN jsonb_build_object('success',true,'session_id',v_session.id,'join_deadline',v_deadline,'starts_at',v_deadline);
END;
$function$;

CREATE OR REPLACE FUNCTION public.join_chat_session_v2(
  p_user_uid uuid,p_consultation_id uuid,p_idempotency_key uuid
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v_cons public.legal_consultations%ROWTYPE; v_session public.consultation_chat_sessions%ROWTYPE;
  v_now timestamptz:=now(); v_start timestamptz; v_end timestamptz; v_reason text;
BEGIN
  IF p_idempotency_key IS NULL THEN RAISE EXCEPTION 'IDEMPOTENCY_KEY_REQUIRED'; END IF;
  SELECT * INTO v_cons FROM public.legal_consultations WHERE id=p_consultation_id AND i_del=0 FOR UPDATE;
  IF v_cons.id IS NULL THEN RAISE EXCEPTION 'CONSULTATION_NOT_FOUND'; END IF;
  IF v_cons.user_uid<>p_user_uid THEN RAISE EXCEPTION 'NOT_OWNER'; END IF;
  SELECT * INTO v_session FROM public.consultation_chat_sessions
   WHERE consultation_id=v_cons.id AND status IN ('join_window','active') ORDER BY ordinal DESC LIMIT 1 FOR UPDATE;
  IF v_session.id IS NULL THEN RAISE EXCEPTION 'CHAT_NOT_READY'; END IF;
  IF v_session.status='active' THEN
    RETURN jsonb_build_object('success',true,'session_id',v_session.id,'starts_at',v_session.starts_at,
      'ends_at',v_session.ends_at,'start_reason',v_session.start_reason,'duplicate',true);
  END IF;
  IF v_now<v_session.join_deadline THEN v_start:=v_now; v_reason:='user_joined';
  ELSE v_start:=v_session.starts_at; v_reason:='grace_expired'; END IF;
  v_end:=v_start+make_interval(mins=>v_session.duration_minutes+v_session.free_extension_minutes);
  UPDATE public.consultation_chat_sessions SET status='active',user_joined_at=v_now,
    starts_at=v_start,ends_at=v_end,start_reason=v_reason,join_idempotency_key=p_idempotency_key,ts_upd=now()
  WHERE id=v_session.id;
  UPDATE public.legal_consultations SET status=1,chat_started_at=v_start,
    chat_duration_minutes=v_session.duration_minutes+v_session.free_extension_minutes,ts_upd=now()
  WHERE id=v_cons.id;
  INSERT INTO public.consultation_chats(consultation_id,sender_id,message_type,content)
  VALUES(v_cons.id,p_user_uid,'system','بدأت جلسة الاستشارة — المدة '||v_session.duration_minutes::text||' دقيقة');
  INSERT INTO public.notifications(uid,tp,ttl,bdy,ref_id,act,i_rd,i_del,ts_crt)
  SELECT v_cons.lawyer_uid,1,'✅ انضم العميل وبدأت الاستشارة','بدأ عداد جلسة الاستشارة الآن.',
    v_cons.id::text,'legal_user_joined',0,0,now() WHERE v_cons.lawyer_uid IS NOT NULL;
  INSERT INTO public.consultation_event_outbox(event_key,event_type,recipient_uid,reference_id,payload)
  SELECT 'user-joined:'||v_session.id,'legal_user_joined',v_cons.lawyer_uid,v_cons.id,
    jsonb_build_object('session_id',v_session.id,'starts_at',v_start,'ends_at',v_end)
  WHERE v_cons.lawyer_uid IS NOT NULL ON CONFLICT(event_key) DO NOTHING;
  RETURN jsonb_build_object('success',true,'session_id',v_session.id,'starts_at',v_start,'ends_at',v_end,
    'start_reason',v_reason);
END;
$function$;

CREATE OR REPLACE FUNCTION public.extend_chat_session_v2(p_lawyer_uid uuid,p_consultation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v_cons public.legal_consultations%ROWTYPE; v_session public.consultation_chat_sessions%ROWTYPE;
BEGIN
  SELECT * INTO v_cons FROM public.legal_consultations WHERE id=p_consultation_id AND i_del=0 FOR UPDATE;
  IF v_cons.id IS NULL OR v_cons.lawyer_uid<>p_lawyer_uid THEN RAISE EXCEPTION 'NOT_ASSIGNED_LAWYER'; END IF;
  SELECT * INTO v_session FROM public.consultation_chat_sessions
   WHERE consultation_id=v_cons.id AND status='active' ORDER BY ordinal DESC LIMIT 1 FOR UPDATE;
  IF v_session.id IS NULL THEN RAISE EXCEPTION 'CHAT_NOT_OPEN'; END IF;
  IF v_session.free_extension_minutes<>0 THEN RAISE EXCEPTION 'ALREADY_EXTENDED'; END IF;
  IF now()>v_session.ends_at+interval '5 minutes' THEN RAISE EXCEPTION 'EXTENSION_WINDOW_EXPIRED'; END IF;
  UPDATE public.consultation_chat_sessions SET free_extension_minutes=5,ends_at=ends_at+interval '5 minutes',ts_upd=now()
   WHERE id=v_session.id;
  UPDATE public.legal_consultations SET extended=true,extended_by=p_lawyer_uid::text,
    chat_duration_minutes=v_session.duration_minutes+5,ts_upd=now() WHERE id=v_cons.id;
  RETURN jsonb_build_object('success',true,'session_id',v_session.id,'ends_at',v_session.ends_at+interval '5 minutes');
END;
$function$;

CREATE OR REPLACE FUNCTION public.advance_chat_sessions_v2()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE r record; v_started integer:=0; v_ended integer:=0;
BEGIN
  FOR r IN
    UPDATE public.consultation_chat_sessions s SET status='active',start_reason='grace_expired',ts_upd=now()
    WHERE s.status='join_window' AND s.starts_at<=now()
    RETURNING s.*
  LOOP
    v_started:=v_started+1;
    UPDATE public.legal_consultations SET status=1,chat_started_at=r.starts_at,
      chat_duration_minutes=r.duration_minutes+r.free_extension_minutes,ts_upd=now() WHERE id=r.consultation_id;
    INSERT INTO public.notifications(uid,tp,ttl,bdy,ref_id,act,i_rd,i_del,ts_crt)
    SELECT l.user_uid,1,'⏱️ بدأ وقت الاستشارة تلقائياً',
      'لم تدخل خلال مهلة الدقيقتين، وبدأ عداد الاستشارة تلقائياً.',l.id::text,
      'legal_session_auto_started',0,0,now() FROM public.legal_consultations l WHERE l.id=r.consultation_id;
  END LOOP;
  FOR r IN
    UPDATE public.consultation_chat_sessions s SET status='ended',ended_at=now(),ts_upd=now()
    WHERE s.status='active' AND s.ends_at<=now() RETURNING s.*
  LOOP
    v_ended:=v_ended+1;
    UPDATE public.legal_consultations SET status=2,ts_upd=now() WHERE id=r.consultation_id;
    INSERT INTO public.notifications(uid,tp,ttl,bdy,ref_id,act,i_rd,i_del,ts_crt)
    SELECT l.user_uid,1,'⏱️ انتهى وقت الاستشارة',
      'يمكنك تجديد المحادثة أو تحويلها إلى جلسة حضورية أو إنهاء القضية وتقييمها.',
      l.id::text,'legal_session_ended',0,0,now() FROM public.legal_consultations l WHERE l.id=r.consultation_id;
  END LOOP;
  RETURN jsonb_build_object('success',true,'started',v_started,'ended',v_ended,'ran_at',now());
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_current_chat_session_v2(p_user_uid uuid,p_consultation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v_cons public.legal_consultations%ROWTYPE; v_session public.consultation_chat_sessions%ROWTYPE;
BEGIN
  SELECT * INTO v_cons FROM public.legal_consultations WHERE id=p_consultation_id AND i_del=0;
  IF v_cons.id IS NULL THEN RAISE EXCEPTION 'CONSULTATION_NOT_FOUND'; END IF;
  IF p_user_uid<>v_cons.user_uid
     AND (v_cons.lawyer_uid IS NULL OR p_user_uid<>v_cons.lawyer_uid)
     AND NOT EXISTS(SELECT 1 FROM public.users WHERE id=p_user_uid AND role=6 AND sts=0 AND i_del=0) THEN
    RAISE EXCEPTION 'NOT_PARTICIPANT';
  END IF;
  SELECT * INTO v_session FROM public.consultation_chat_sessions
   WHERE consultation_id=v_cons.id ORDER BY ordinal DESC LIMIT 1;
  IF v_session.id IS NULL THEN RETURN jsonb_build_object('success',true,'session',NULL); END IF;
  RETURN jsonb_build_object('success',true,'session',to_jsonb(v_session),
    'seconds_until_auto_start',CASE WHEN v_session.status='join_window' THEN GREATEST(0,extract(epoch FROM v_session.starts_at-now())::integer) ELSE 0 END,
    'remaining_seconds',CASE WHEN v_session.status IN ('join_window','active') THEN GREATEST(0,extract(epoch FROM v_session.ends_at-now())::integer) ELSE 0 END);
END;
$function$;

-- رباعي التحصين.
REVOKE ALL ON FUNCTION public.ensure_initial_chat_session_v2(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lawyer_ready_chat_session_v2(uuid,uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.join_chat_session_v2(uuid,uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.extend_chat_session_v2(uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.advance_chat_sessions_v2() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_current_chat_session_v2(uuid,uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.ensure_initial_chat_session_v2(uuid) FROM anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.lawyer_ready_chat_session_v2(uuid,uuid,uuid) FROM anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.join_chat_session_v2(uuid,uuid,uuid) FROM anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.extend_chat_session_v2(uuid,uuid) FROM anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.advance_chat_sessions_v2() FROM anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.get_current_chat_session_v2(uuid,uuid) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ensure_initial_chat_session_v2(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.lawyer_ready_chat_session_v2(uuid,uuid,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.join_chat_session_v2(uuid,uuid,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.extend_chat_session_v2(uuid,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.advance_chat_sessions_v2() TO service_role;
GRANT EXECUTE ON FUNCTION public.get_current_chat_session_v2(uuid,uuid) TO service_role;

DO $cron$
DECLARE v_job integer;
BEGIN
  SELECT jobid INTO v_job FROM cron.job WHERE command='SELECT public.advance_chat_sessions_v2();' LIMIT 1;
  IF v_job IS NOT NULL THEN PERFORM cron.unschedule(v_job); END IF;
  PERFORM cron.schedule('advance-chat-sessions-v2','* * * * *','SELECT public.advance_chat_sessions_v2();');
END;
$cron$;
