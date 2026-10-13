-- ══════════════════════════════════════════════════════════════════════
-- Migration: Lock Admin Payment RPCs after admin-payments Edge Function
-- Date: 2026-06-17
-- Purpose:
--   Payment admin operations now go through admin-payments Edge Function
--   with staff_session_token/service_role validation.
--   Do NOT apply before deploying and testing supabase/functions/admin-payments.
-- ══════════════════════════════════════════════════════════════════════

REVOKE ALL ON FUNCTION public.get_admin_payments_internal(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_admin_payments_internal(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.get_admin_payments_internal(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_admin_payments_internal(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.approve_payment_final(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.approve_payment_final(uuid, uuid) FROM anon;
REVOKE ALL ON FUNCTION public.approve_payment_final(uuid, uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.approve_payment_final(uuid, uuid) TO service_role;

REVOKE ALL ON FUNCTION public.admin_reject_payment_internal(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_reject_payment_internal(uuid, uuid) FROM anon;
REVOKE ALL ON FUNCTION public.admin_reject_payment_internal(uuid, uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reject_payment_internal(uuid, uuid) TO service_role;
