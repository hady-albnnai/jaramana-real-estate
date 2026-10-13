-- =============================================================================
-- 2026-08-16 — reliable Push outbox worker for Consultation V2
-- =============================================================================

CREATE OR REPLACE FUNCTION public.enqueue_consultation_notification_push()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v_role integer;
BEGIN
  SELECT role INTO v_role FROM public.users WHERE id=NEW.uid;
  IF NEW.act IN ('legal_session_auto_started','legal_session_ended','legal_waitlist_available')
     OR (NEW.act='legal_onsite_confirmed' AND v_role=7) THEN
    INSERT INTO public.consultation_event_outbox(event_key,event_type,recipient_uid,reference_id,payload)
    VALUES('notification:'||NEW.id,NEW.act,NEW.uid,
      CASE WHEN NEW.ref_id ~* '^[0-9a-f-]{36}$' THEN NEW.ref_id::uuid ELSE NULL END,
      jsonb_build_object('title',NEW.ttl,'body',NEW.bdy,'act',NEW.act,'ref_id',NEW.ref_id))
    ON CONFLICT(event_key) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_enqueue_consultation_push ON public.notifications;
CREATE TRIGGER trg_enqueue_consultation_push
AFTER INSERT ON public.notifications
FOR EACH ROW EXECUTE FUNCTION public.enqueue_consultation_notification_push();

CREATE OR REPLACE FUNCTION public.process_consultation_outbox_v2()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE r record; v_title text; v_body text; v_sent integer:=0; v_failed integer:=0;
BEGIN
  FOR r IN
    SELECT * FROM public.consultation_event_outbox
    WHERE status IN ('pending','failed') AND next_attempt_at<=now() AND attempts<8
    ORDER BY ts_crt FOR UPDATE SKIP LOCKED LIMIT 50
  LOOP
    UPDATE public.consultation_event_outbox SET status='processing',attempts=attempts+1 WHERE id=r.id;
    v_title:=NULLIF(r.payload->>'title',''); v_body:=NULLIF(r.payload->>'body','');
    IF v_title IS NULL THEN
      v_title:=CASE r.event_type
        WHEN 'legal_lawyer_ready' THEN '💬 المحامي جاهز لبدء الاستشارة'
        WHEN 'legal_user_joined' THEN '✅ انضم العميل وبدأت الاستشارة'
        WHEN 'legal_consultation_new' THEN '⚖️ استشارة قانونية جديدة'
        WHEN 'legal_renewal_paid_ready' THEN '✅ تجديد مدفوع جاهز'
        ELSE '⚖️ تحديث الاستشارة القانونية' END;
    END IF;
    IF v_body IS NULL THEN
      v_body:=CASE r.event_type
        WHEN 'legal_lawyer_ready' THEN 'افتح المحادثة خلال دقيقتين. يبدأ الوقت عند دخولك أو تلقائياً بعد المهلة.'
        WHEN 'legal_user_joined' THEN 'انضم العميل وبدأ عداد الاستشارة.'
        WHEN 'legal_consultation_new' THEN 'وصلت استشارة مدفوعة جديدة للمراجعة.'
        WHEN 'legal_renewal_paid_ready' THEN 'لدى العميل مدة مدفوعة جاهزة. اضغط استئناف عندما تصبح جاهزاً.'
        ELSE 'لديك تحديث جديد في الاستشارة القانونية.' END;
    END IF;
    BEGIN
      PERFORM public.send_push_notification(r.recipient_uid,v_title,v_body,
        jsonb_build_object('act',r.event_type,'ref_id',COALESCE(r.reference_id::text,r.payload->>'ref_id')));
      UPDATE public.consultation_event_outbox SET status='sent',sent_at=now(),last_error=NULL WHERE id=r.id;
      v_sent:=v_sent+1;
    EXCEPTION WHEN OTHERS THEN
      UPDATE public.consultation_event_outbox SET status='failed',last_error=left(SQLERRM,300),
        next_attempt_at=now()+make_interval(mins=>LEAST(60,GREATEST(1,attempts*2))) WHERE id=r.id;
      v_failed:=v_failed+1;
    END;
  END LOOP;
  RETURN jsonb_build_object('success',true,'sent',v_sent,'failed',v_failed,'ran_at',now());
END;
$function$;

REVOKE ALL ON FUNCTION public.enqueue_consultation_notification_push() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.process_consultation_outbox_v2() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.enqueue_consultation_notification_push() FROM anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.process_consultation_outbox_v2() FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_consultation_notification_push() TO service_role;
GRANT EXECUTE ON FUNCTION public.process_consultation_outbox_v2() TO service_role;

DO $cron$
DECLARE v_job integer;
BEGIN
 SELECT jobid INTO v_job FROM cron.job WHERE command='SELECT public.process_consultation_outbox_v2();' LIMIT 1;
 IF v_job IS NOT NULL THEN PERFORM cron.unschedule(v_job); END IF;
 PERFORM cron.schedule('process-consultation-outbox-v2','* * * * *',
  'SELECT public.process_consultation_outbox_v2();');
END;
$cron$;
