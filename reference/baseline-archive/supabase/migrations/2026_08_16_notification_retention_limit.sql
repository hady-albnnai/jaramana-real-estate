-- =============================================================================
-- 2026-08-16 — latest 100 notifications + bounded retention
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_user_notifications_internal(p_user_uid uuid)
RETURNS SETOF public.notifications
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
BEGIN
 IF auth.uid() IS NOT NULL AND auth.uid()<>p_user_uid THEN RAISE EXCEPTION 'AUTH_UID_MISMATCH'; END IF;
 RETURN QUERY
 SELECT * FROM public.notifications
 WHERE uid=p_user_uid AND i_del=0
 ORDER BY ts_crt DESC
 LIMIT 100;
END;
$function$;
REVOKE ALL ON FUNCTION public.get_user_notifications_internal(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_user_notifications_internal(uuid) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_notifications_internal(uuid) TO service_role;

CREATE INDEX IF NOT EXISTS idx_notifications_user_recent
 ON public.notifications(uid,i_del,ts_crt DESC);

CREATE OR REPLACE FUNCTION public.cleanup_notifications_retention()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v_age integer:=0; v_cap integer:=0;
BEGIN
 WITH deleted AS (
  DELETE FROM public.notifications
  WHERE ts_crt<now()-interval '90 days'
     OR (i_rd=1 AND ts_crt<now()-interval '30 days')
  RETURNING 1)
 SELECT count(*) INTO v_age FROM deleted;

 WITH ranked AS (
  SELECT id,row_number() OVER(PARTITION BY uid ORDER BY ts_crt DESC) rn
  FROM public.notifications
 ),deleted AS (
  DELETE FROM public.notifications n USING ranked r
  WHERE n.id=r.id AND r.rn>300 RETURNING 1)
 SELECT count(*) INTO v_cap FROM deleted;
 RETURN jsonb_build_object('success',true,'deleted_by_age',v_age,'deleted_over_cap',v_cap,'ran_at',now());
END;
$function$;
REVOKE ALL ON FUNCTION public.cleanup_notifications_retention() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cleanup_notifications_retention() FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_notifications_retention() TO service_role;

DO $cron$
DECLARE r record;
BEGIN
 FOR r IN SELECT jobid FROM cron.job WHERE jobname='cleanup-notifications-retention' LOOP
  PERFORM cron.unschedule(r.jobid);
 END LOOP;
 PERFORM cron.schedule('cleanup-notifications-retention','45 4 * * *',
  'SELECT public.cleanup_notifications_retention();');
END;
$cron$;
