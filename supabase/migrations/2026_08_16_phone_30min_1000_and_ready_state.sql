-- =============================================================================
-- 2026-08-16 — Phone/renewal = 30 min, 1000 SYP; ready renewal reopens case
-- =============================================================================
UPDATE public.app_config
SET value=jsonb_set(
  jsonb_set(
    jsonb_set(value,'{legalPrice,phone}','1000'::jsonb,true),
    '{legalPrice,renew}','1000'::jsonb,true),
  '{legalPrice,durationMins}','30'::jsonb,true)
WHERE key='main';

CREATE OR REPLACE FUNCTION public.trg_ready_session_consultation_state()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
BEGIN
 IF NEW.status='ready' THEN
  UPDATE public.legal_consultations SET status=1,ts_upd=now()
   WHERE id=NEW.consultation_id AND i_del=0;
 ELSIF OLD.status='ready' AND NEW.status IN('cancelled','reversed') THEN
  UPDATE public.legal_consultations SET status=2,ts_upd=now()
   WHERE id=NEW.consultation_id AND i_del=0
    AND NOT EXISTS(SELECT 1 FROM public.consultation_chat_sessions s
      WHERE s.consultation_id=NEW.consultation_id AND s.id<>NEW.id
       AND s.status IN('ready','join_window','active'));
 END IF;
 RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_ready_session_consultation_state ON public.consultation_chat_sessions;
CREATE TRIGGER trg_ready_session_consultation_state
AFTER INSERT OR UPDATE OF status ON public.consultation_chat_sessions
FOR EACH ROW EXECUTE FUNCTION public.trg_ready_session_consultation_state();

REVOKE ALL ON FUNCTION public.trg_ready_session_consultation_state() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.trg_ready_session_consultation_state() FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.trg_ready_session_consultation_state() TO service_role;

-- V2 هو المصدر الوحيد لنهاية الوقت؛ الوظيفة القديمة كانت تغلق parent رغم وجود renewal ready.
DO $cron$
DECLARE r record;
BEGIN
 FOR r IN SELECT jobid FROM cron.job
  WHERE jobname='close-expired-phone-consultations'
     OR command='SELECT public.close_expired_phone_consultations();'
 LOOP
  PERFORM cron.unschedule(r.jobid);
 END LOOP;
END;
$cron$;

-- الجلسة الحالية دُفعت بالسعر القديم، لكن لم تبدأ بعد؛ نمنحها المدة الجديدة دون تزوير مبلغها التاريخي.
UPDATE public.consultation_chat_sessions
SET duration_minutes=30,ts_upd=now()
WHERE status='ready' AND kind='renewal' AND starts_at IS NULL;

UPDATE public.legal_consultations l
SET status=1,ts_upd=now()
WHERE EXISTS(SELECT 1 FROM public.consultation_chat_sessions s
 WHERE s.consultation_id=l.id AND s.status='ready');

-- تصحيح نص الرسالة النظامية للجلسات الجاهزة الحالية فقط.
UPDATE public.consultation_chats c
SET content=regexp_replace(content,'[0-9]+ دقيقة جاهزة','30 دقيقة جاهزة')
WHERE c.message_type='system'
 AND c.content LIKE 'تم اعتماد التجديد — % دقيقة جاهزة عند استئناف المحامي.'
 AND EXISTS(SELECT 1 FROM public.consultation_chat_sessions s
  WHERE s.consultation_id=c.consultation_id AND s.status='ready');
