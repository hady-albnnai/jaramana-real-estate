-- ══════════════════════════════════════════════════════════════════════
-- Migration: Executor & Photography Flow Fixes
-- Date: 2026-06-17
-- Purpose:
--   1. Provide executor task lookup by appointment id.
--   2. Provide executor's own completion requests instead of all office requests.
--   3. Provide RPC-based photographer task loading.
--   4. Add explicit start photography task transition (0/4 -> 1).
-- ══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_executor_task_by_appointment(
  p_user_uid UUID,
  p_appointment_id UUID
)
RETURNS TABLE(
  appointment_id UUID,
  off_id UUID,
  offer_number TEXT,
  display_title TEXT,
  task_type TEXT,
  client_name TEXT,
  client_phone TEXT,
  appointment_date TIMESTAMPTZ,
  location JSONB,
  description TEXT,
  price NUMERIC,
  offer_cur INT,
  outcome TEXT,
  completion_date TIMESTAMPTZ,
  rejection_reason TEXT,
  sts INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_role INT;
BEGIN
  IF p_user_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_MISMATCH';
  END IF;

  SELECT role INTO v_role FROM public.users WHERE id = p_user_uid AND i_del = 0 AND sts = 0;
  IF v_role IS NULL OR v_role < 3 THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  RETURN QUERY
  SELECT
    a.id AS appointment_id,
    a.off_id,
    COALESCE(o.offer_number::text, o.ttl, '') AS offer_number,
    COALESCE(o.ttl, '') AS display_title,
    CASE WHEN o.typ = 0 THEN 'property' ELSE 'car' END AS task_type,
    ''::TEXT AS client_name,
    ''::TEXT AS client_phone,
    a.dt AS appointment_date,
    COALESCE(o.loc, '{}'::jsonb) AS location,
    COALESCE(o.descript, '') AS description,
    COALESCE(o.prc, 0) AS price,
    COALESCE(o.cur, 0) AS offer_cur,
    a.outcome,
    a.completion_date,
    a.rejection_reason,
    a.sts
  FROM public.appointments a
  JOIN public.offers o ON o.id = a.off_id
  WHERE a.id = p_appointment_id
    AND a.supervisor_uid = p_user_uid
  LIMIT 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_completion_requests(
  p_user_uid UUID
)
RETURNS TABLE(
  request_id UUID,
  appointment_id UUID,
  off_id UUID,
  display_title TEXT,
  offer_number TEXT,
  task_type TEXT,
  executor_notes TEXT,
  office_notes TEXT,
  decision TEXT,
  request_date TIMESTAMPTZ,
  decided_date TIMESTAMPTZ,
  appointment_date TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_role INT;
BEGIN
  IF p_user_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_MISMATCH';
  END IF;

  SELECT role INTO v_role FROM public.users WHERE id = p_user_uid AND i_del = 0 AND sts = 0;
  IF v_role IS NULL OR v_role < 3 THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  RETURN QUERY
  SELECT
    cr.id AS request_id,
    cr.app_id AS appointment_id,
    a.off_id,
    COALESCE(o.ttl, '') AS display_title,
    COALESCE(o.offer_number::text, o.ttl, '') AS offer_number,
    CASE WHEN o.typ = 0 THEN 'property' ELSE 'car' END AS task_type,
    COALESCE(cr.notes, '') AS executor_notes,
    COALESCE(cr.office_notes, '') AS office_notes,
    COALESCE(cr.decision, 'pending') AS decision,
    cr.ts_crt AS request_date,
    cr.ts_decided AS decided_date,
    a.dt AS appointment_date
  FROM public.completion_requests cr
  JOIN public.appointments a ON a.id = cr.app_id
  JOIN public.offers o ON o.id = a.off_id
  WHERE cr.req_by = p_user_uid
  ORDER BY cr.ts_crt DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_photographer_tasks_internal(
  p_photographer_uid UUID
)
RETURNS SETOF public.photography_tasks
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_role INT;
BEGIN
  IF p_photographer_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_photographer_uid THEN
    RAISE EXCEPTION 'AUTH_MISMATCH';
  END IF;

  SELECT role INTO v_role FROM public.users WHERE id = p_photographer_uid AND i_del = 0 AND sts = 0;
  IF v_role IS NULL OR v_role < 2 THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  RETURN QUERY
  SELECT *
  FROM public.photography_tasks
  WHERE photographer_id = p_photographer_uid
  ORDER BY COALESCE(ts_scheduled, ts_crt) ASC, ts_crt DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.start_photography_task_internal(
  p_photographer_uid UUID,
  p_task_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_role INT;
BEGIN
  IF p_photographer_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_photographer_uid THEN
    RAISE EXCEPTION 'AUTH_MISMATCH';
  END IF;

  SELECT role INTO v_role FROM public.users WHERE id = p_photographer_uid AND i_del = 0 AND sts = 0;
  IF v_role IS NULL OR v_role < 2 THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  UPDATE public.photography_tasks
  SET sts = 1,
      ts_upd = now()
  WHERE id = p_task_id
    AND photographer_id = p_photographer_uid
    AND sts IN (0, 4);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'TASK_NOT_FOUND_OR_NOT_ALLOWED';
  END IF;

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_executor_task_by_appointment(UUID, UUID) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_completion_requests(UUID) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_photographer_tasks_internal(UUID) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.start_photography_task_internal(UUID, UUID) TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.get_my_completion_requests(UUID) IS
  'Returns only completion requests created by the executor/supervisor himself, not all office pending requests.';
COMMENT ON FUNCTION public.start_photography_task_internal(UUID, UUID) IS
  'Photographer starts assigned task: status 0/4 -> 1.';
