-- ════════════════════════════════════════════════════════════════════════
-- Migration: 2026_08_05_fix_lawyer_appointments.sql
-- Purpose: إصلاح خطأ "column reference 'id' is ambiguous"
-- Bug: BUG-002 — تضارب اسم العمود في RETURNS TABLE
-- Impact: المحامي يستطيع رؤية مواعيده
-- ════════════════════════════════════════════════════════════════════════

-- 🔧 Step 1: DROP التوقيع القديم
DROP FUNCTION IF EXISTS public.get_lawyer_appointments(uuid);

-- ✅ Step 2: CREATE بالتوقيع الصحيح (appt_id بدل id)
CREATE OR REPLACE FUNCTION public.get_lawyer_appointments(p_lawyer_uid uuid)
RETURNS TABLE(
  appt_id uuid,
  client_name text,
  client_phone text,
  dt timestamp with time zone,
  appt_sts integer,
  notes text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_role int;
BEGIN
  SELECT role INTO v_role
  FROM public.users
  WHERE id = p_lawyer_uid AND i_del = 0 AND sts = 0;

  IF v_role <> 7 THEN
    RAISE EXCEPTION 'LAWYER_ROLE_REQUIRED';
  END IF;

  RETURN QUERY
  SELECT
    a.id AS appt_id,
    COALESCE(u.nm, '') AS client_name,
    COALESCE(u.ph, '') AS client_phone,
    a.dt,
    a.sts AS appt_sts,
    COALESCE(a.executor_notes, '') AS notes
  FROM public.appointments a
  JOIN public.users u ON u.id = a.req_uid
  WHERE a.bkr_id = p_lawyer_uid
  ORDER BY a.dt DESC;
END;
$function$;

-- 🔒 Step 3: رباعي التحصين
REVOKE ALL ON FUNCTION public.get_lawyer_appointments(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_lawyer_appointments(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_lawyer_appointments(uuid) TO service_role;
