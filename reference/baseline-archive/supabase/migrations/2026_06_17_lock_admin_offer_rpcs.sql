-- ══════════════════════════════════════════════════════════════════════
-- Migration: Lock Admin Offer RPCs after admin-offers Edge Function
-- Date: 2026-06-17
-- Purpose:
--   These RPCs are now called only by the admin-offers Edge Function using
--   service_role after validating staff_session_token / admin session.
--   Do NOT apply before deploying supabase/functions/admin-offers.
-- ══════════════════════════════════════════════════════════════════════

REVOKE ALL ON FUNCTION public.get_admin_pending_offers_internal(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_admin_pending_offers_internal(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.get_admin_pending_offers_internal(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_admin_pending_offers_internal(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.get_admin_offers_internal(uuid, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_admin_offers_internal(uuid, integer) FROM anon;
REVOKE ALL ON FUNCTION public.get_admin_offers_internal(uuid, integer) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_admin_offers_internal(uuid, integer) TO service_role;

REVOKE ALL ON FUNCTION public.admin_review_offer_internal(uuid, uuid, boolean, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_review_offer_internal(uuid, uuid, boolean, text) FROM anon;
REVOKE ALL ON FUNCTION public.admin_review_offer_internal(uuid, uuid, boolean, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.admin_review_offer_internal(uuid, uuid, boolean, text) TO service_role;

REVOKE ALL ON FUNCTION public.admin_set_offer_priority_internal(uuid, uuid, text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_set_offer_priority_internal(uuid, uuid, text, integer) FROM anon;
REVOKE ALL ON FUNCTION public.admin_set_offer_priority_internal(uuid, uuid, text, integer) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_offer_priority_internal(uuid, uuid, text, integer) TO service_role;

REVOKE ALL ON FUNCTION public.admin_delete_offer_internal(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_delete_offer_internal(uuid, uuid) FROM anon;
REVOKE ALL ON FUNCTION public.admin_delete_offer_internal(uuid, uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_offer_internal(uuid, uuid) TO service_role;
