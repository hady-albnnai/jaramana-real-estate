-- ══════════════════════════════════════════════════════════════════
-- 2026-08-20 — تقييد صلاحيات إدارة المواعيد (م5 — قرار المالك)
--
-- قرار المالك: لا يجوز للإدارة القيام بكل شيء على المواعيد.
--   • «فرض» موعد  → معطَّل سيرفرياً (يعود ADMIN_FORCE_DISABLED)
--   • «عدم حضور»  → معطَّل (ADMIN_CANNOT_NO_SHOW)
--   • «إكمال»     → مسموح فقط للمواعيد التي مضى وقتها
--   • «إلغاء»     → مسموح بشرط سبب إلزامي (admin_note)
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_update_appointment_status_internal(
  p_admin_uid uuid, p_appointment_id uuid, p_status integer, p_admin_note text DEFAULT ''::text
)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE v_role INT; v_appt public.appointments%ROWTYPE;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 3 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  SELECT * INTO v_appt FROM appointments WHERE id = p_appointment_id;
  IF v_appt.id IS NULL THEN RAISE EXCEPTION 'APPOINTMENT_NOT_FOUND'; END IF;

  -- 🔒 م5: «عدم حضور» من اختصاص الطرفين/المشرف — لا الإدارة
  IF p_status = 5 THEN RAISE EXCEPTION 'ADMIN_CANNOT_NO_SHOW'; END IF;
  -- 🔒 م5: الإكمال فقط بعد مضيّ وقت الموعد
  IF p_status = 2 AND v_appt.dt > now() THEN RAISE EXCEPTION 'APPOINTMENT_NOT_PAST'; END IF;
  -- 🔒 م5: الإلغاء الإداري يتطلب سبباً مكتوباً
  IF p_status = 3 AND COALESCE(trim(p_admin_note), '') = '' THEN
    RAISE EXCEPTION 'CANCEL_REASON_REQUIRED';
  END IF;

  UPDATE appointments SET sts = p_status, admin_nt = COALESCE(p_admin_note, '') WHERE id = p_appointment_id;
  RETURN FOUND;
END;
$function$;

REVOKE ALL ON FUNCTION admin_update_appointment_status_internal(p_admin_uid uuid, p_appointment_id uuid, p_status integer, p_admin_note text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_update_appointment_status_internal(p_admin_uid uuid, p_appointment_id uuid, p_status integer, p_admin_note text) TO service_role;

-- «فرض» معطَّل نهائياً
CREATE OR REPLACE FUNCTION public.admin_force_appointment_internal(p_admin_uid uuid, p_appointment_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  -- 🔒 م5 (2026-08-20): فرض الموعد من الإدارة أُلغي بقرار المالك —
  -- الحجز والتراشق من اختصاص الطرفين فقط.
  RAISE EXCEPTION 'ADMIN_FORCE_DISABLED';
END;
$function$;

REVOKE ALL ON FUNCTION admin_force_appointment_internal(p_admin_uid uuid, p_appointment_id uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_force_appointment_internal(p_admin_uid uuid, p_appointment_id uuid) TO service_role;

-- ──────────────────────────────────────────────────────────────────────
-- تحقق نهائي مدمج
-- ──────────────────────────────────────────────────────────────────────
SELECT
  pg_get_functiondef('public.admin_update_appointment_status_internal(uuid,uuid,integer,text)'::regprocedure)
    LIKE '%ADMIN_CANNOT_NO_SHOW%' AS noshow_guard,
  pg_get_functiondef('public.admin_update_appointment_status_internal(uuid,uuid,integer,text)'::regprocedure)
    LIKE '%CANCEL_REASON_REQUIRED%' AS reason_guard,
  pg_get_functiondef('public.admin_force_appointment_internal(uuid,uuid)'::regprocedure)
    LIKE '%ADMIN_FORCE_DISABLED%' AS force_disabled;
