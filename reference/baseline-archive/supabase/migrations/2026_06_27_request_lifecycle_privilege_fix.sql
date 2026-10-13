-- Fix request lifecycle RPC privileges and remaining mutable search_path warnings.
-- SECURITY: internal SECURITY DEFINER functions must not be executable through PostgREST by PUBLIC/anon/authenticated.

-- Existing functions reported by linter after request lifecycle deployment.
ALTER FUNCTION public.admin_review_offer_internal(UUID, UUID, BOOLEAN, TEXT)
  SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.notify_admin_on_new_offer()
  SET search_path = public, extensions, pg_temp;

-- Revoke from PUBLIC as well as Supabase API roles; default function EXECUTE is granted to PUBLIC.
REVOKE EXECUTE ON FUNCTION public.admin_close_request_internal(UUID, UUID, INT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.can_publish_request_internal(UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.cancel_request_internal(UUID, UUID, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.expire_requests() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_admin_requests_internal(UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.purge_old_closed_requests() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.renew_request_internal(UUID, UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.request_assert_owner_active(UUID, UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.request_lifecycle_days(TEXT, INT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.send_request_renewal_reminders() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.create_request_internal(UUID, JSONB) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.update_request_internal(UUID, UUID, JSONB) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_user_requests_internal(UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.soft_delete_request_internal(UUID, UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.book_appointment_internal(UUID, UUID, TIMESTAMPTZ, UUID, UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.process_completion_request(UUID, UUID, TEXT, TEXT) FROM PUBLIC, anon, authenticated;

-- Trigger/helper functions should not be callable from API roles.
REVOKE EXECUTE ON FUNCTION public.notify_admin_on_new_offer() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_review_offer_internal(UUID, UUID, BOOLEAN, TEXT) FROM PUBLIC, anon, authenticated;

-- Keep service_role execution for Edge Functions.
GRANT EXECUTE ON FUNCTION public.admin_close_request_internal(UUID, UUID, INT, TEXT, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.can_publish_request_internal(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.cancel_request_internal(UUID, UUID, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.expire_requests() TO service_role;
GRANT EXECUTE ON FUNCTION public.get_admin_requests_internal(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.purge_old_closed_requests() TO service_role;
GRANT EXECUTE ON FUNCTION public.renew_request_internal(UUID, UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.request_assert_owner_active(UUID, UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.request_lifecycle_days(TEXT, INT) TO service_role;
GRANT EXECUTE ON FUNCTION public.send_request_renewal_reminders() TO service_role;
GRANT EXECUTE ON FUNCTION public.create_request_internal(UUID, JSONB) TO service_role;
GRANT EXECUTE ON FUNCTION public.update_request_internal(UUID, UUID, JSONB) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_user_requests_internal(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.soft_delete_request_internal(UUID, UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.book_appointment_internal(UUID, UUID, TIMESTAMPTZ, UUID, UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.process_completion_request(UUID, UUID, TEXT, TEXT) TO service_role;

-- Existing offer admin helpers are called through Edge Functions; keep service_role only.
GRANT EXECUTE ON FUNCTION public.admin_review_offer_internal(UUID, UUID, BOOLEAN, TEXT) TO service_role;
