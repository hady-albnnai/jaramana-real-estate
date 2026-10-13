-- ══════════════════════════════════════════════════════════════════════
-- Migration: Lock Admin Verification RPCs after admin-verifications Edge Function
-- Date: 2026-06-17
-- Purpose:
--   Verification review actions now go through admin-verifications Edge Function
--   with staff_session_token/service_role validation.
--   Do NOT apply before deploying and testing supabase/functions/admin-verifications.
-- ══════════════════════════════════════════════════════════════════════

REVOKE ALL ON FUNCTION public.admin_approve_verification_by_admin(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_approve_verification_by_admin(uuid, uuid) FROM anon;
REVOKE ALL ON FUNCTION public.admin_approve_verification_by_admin(uuid, uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.admin_approve_verification_by_admin(uuid, uuid) TO service_role;

REVOKE ALL ON FUNCTION public.admin_reject_verification_by_admin(uuid, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_reject_verification_by_admin(uuid, uuid, text) FROM anon;
REVOKE ALL ON FUNCTION public.admin_reject_verification_by_admin(uuid, uuid, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reject_verification_by_admin(uuid, uuid, text) TO service_role;
