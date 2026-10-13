-- ══════════════════════════════════════════════════════════════════════
-- Migration: Lock Legacy Admin RPCs
-- Date: 2026-06-15
-- Purpose:
--   After moving role/status/permission changes to staff-session protected
--   Edge Functions, remove direct client access to legacy sensitive RPCs.
-- ══════════════════════════════════════════════════════════════════════

-- These functions remain available to service_role Edge Functions only.
REVOKE ALL ON FUNCTION admin_update_user_role(UUID, UUID, INT) FROM PUBLIC;
REVOKE ALL ON FUNCTION admin_update_user_role(UUID, UUID, INT) FROM anon;
REVOKE ALL ON FUNCTION admin_update_user_role(UUID, UUID, INT) FROM authenticated;
GRANT EXECUTE ON FUNCTION admin_update_user_role(UUID, UUID, INT) TO service_role;

REVOKE ALL ON FUNCTION admin_set_user_status(UUID, UUID, INT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION admin_set_user_status(UUID, UUID, INT, TEXT) FROM anon;
REVOKE ALL ON FUNCTION admin_set_user_status(UUID, UUID, INT, TEXT) FROM authenticated;
GRANT EXECUTE ON FUNCTION admin_set_user_status(UUID, UUID, INT, TEXT) TO service_role;

REVOKE ALL ON FUNCTION admin_update_user_permissions_by_admin(UUID, UUID, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION admin_update_user_permissions_by_admin(UUID, UUID, JSONB) FROM anon;
REVOKE ALL ON FUNCTION admin_update_user_permissions_by_admin(UUID, UUID, JSONB) FROM authenticated;
GRANT EXECUTE ON FUNCTION admin_update_user_permissions_by_admin(UUID, UUID, JSONB) TO service_role;

-- soft_delete was already locked in previous patch; keep it explicit here.
REVOKE ALL ON FUNCTION soft_delete(TEXT, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION soft_delete(TEXT, UUID) FROM anon;
REVOKE ALL ON FUNCTION soft_delete(TEXT, UUID) FROM authenticated;
GRANT EXECUTE ON FUNCTION soft_delete(TEXT, UUID) TO service_role;
