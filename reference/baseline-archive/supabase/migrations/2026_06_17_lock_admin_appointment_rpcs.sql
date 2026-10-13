-- ══════════════════════════════════════════════════════════════════════
-- Migration: Lock Admin Appointment RPCs after admin-appointments Edge Function
-- Date: 2026-06-17
-- Purpose:
--   Appointment admin operations now go through admin-appointments Edge Function
--   with staff_session_token/service_role validation.
--   Do NOT apply before deploying and testing supabase/functions/admin-appointments.
-- ══════════════════════════════════════════════════════════════════════

REVOKE ALL ON FUNCTION public.get_admin_appointments_internal(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_admin_appointments_internal(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.get_admin_appointments_internal(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_admin_appointments_internal(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.admin_update_appointment_status_internal(uuid, uuid, integer, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_update_appointment_status_internal(uuid, uuid, integer, text) FROM anon;
REVOKE ALL ON FUNCTION public.admin_update_appointment_status_internal(uuid, uuid, integer, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_appointment_status_internal(uuid, uuid, integer, text) TO service_role;

REVOKE ALL ON FUNCTION public.admin_force_appointment_internal(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_force_appointment_internal(uuid, uuid) FROM anon;
REVOKE ALL ON FUNCTION public.admin_force_appointment_internal(uuid, uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.admin_force_appointment_internal(uuid, uuid) TO service_role;
