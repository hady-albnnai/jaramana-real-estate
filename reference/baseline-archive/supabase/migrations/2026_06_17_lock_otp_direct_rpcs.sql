-- ══════════════════════════════════════════════════════════════════════
-- Migration: Lock direct OTP verification/upsert RPCs
-- Date: 2026-06-17
-- Purpose:
--   OTP generation/verification and user upsert after OTP must be executed
--   only by Edge Functions using service_role. Clients must not call these
--   RPCs directly, otherwise upsert_user_after_otp could create accounts
--   without a verified OTP flow.
-- ══════════════════════════════════════════════════════════════════════

REVOKE ALL ON FUNCTION public.upsert_user_after_otp(TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.upsert_user_after_otp(TEXT, TEXT) FROM anon;
REVOKE ALL ON FUNCTION public.upsert_user_after_otp(TEXT, TEXT) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_user_after_otp(TEXT, TEXT) TO service_role;

REVOKE ALL ON FUNCTION public.verify_otp_v2(TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.verify_otp_v2(TEXT, TEXT) FROM anon;
REVOKE ALL ON FUNCTION public.verify_otp_v2(TEXT, TEXT) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.verify_otp_v2(TEXT, TEXT) TO service_role;

REVOKE ALL ON FUNCTION public.generate_otp_v2(TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.generate_otp_v2(TEXT, TEXT) FROM anon;
REVOKE ALL ON FUNCTION public.generate_otp_v2(TEXT, TEXT) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.generate_otp_v2(TEXT, TEXT) TO service_role;

COMMENT ON FUNCTION public.upsert_user_after_otp(TEXT, TEXT) IS
  'Locked: callable only by service_role Edge Functions after OTP verification.';
