-- 2026-08-16 — daily orphan cleanup via protected Edge worker.
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION public.list_consultation_orphan_files_v2()
RETURNS TABLE(bucket_id text,name text)
LANGUAGE sql SECURITY DEFINER
SET search_path TO 'public','storage','extensions','pg_temp'
AS $function$
 SELECT o.bucket_id,o.name
 FROM storage.objects o
 WHERE o.bucket_id IN ('payment_proofs','consultation_files')
   AND o.created_at<now()-interval '24 hours'
   AND (
    (o.bucket_id='payment_proofs' AND NOT EXISTS(
      SELECT 1 FROM public.payments p WHERE p.proof=o.name))
    OR
    (o.bucket_id='consultation_files'
      AND NOT EXISTS(SELECT 1 FROM public.consultation_chats c WHERE c.file_url=o.name AND c.i_del=0)
      AND NOT EXISTS(SELECT 1 FROM public.legal_consultations l WHERE o.name=ANY(COALESCE(l.attachments,'{}'::text[])) AND l.i_del=0))
   )
 LIMIT 1000;
$function$;
REVOKE ALL ON FUNCTION public.list_consultation_orphan_files_v2() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.list_consultation_orphan_files_v2() FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.list_consultation_orphan_files_v2() TO service_role;

DO $cron$
DECLARE v_job integer;
BEGIN
 SELECT jobid INTO v_job FROM cron.job WHERE jobname='cleanup-consultation-orphans-daily' LIMIT 1;
 IF v_job IS NOT NULL THEN PERFORM cron.unschedule(v_job); END IF;
 PERFORM cron.schedule(
  'cleanup-consultation-orphans-daily',
  '15 4 * * *',
  $cmd$
  SELECT net.http_post(
    url := 'https://vsgkgnjtebjxyqwpuopz.supabase.co/functions/v1/cleanup-consultation-orphans',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'apikey',(SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='CONSULTATION_CLEANUP_ANON' LIMIT 1),
      'x-cleanup-token',(SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='CONSULTATION_CLEANUP_TOKEN' LIMIT 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000
  );
  $cmd$
 );
END;
$cron$;
