-- ════════════════════════════════════════════════════════════════════════════
-- Cleanup: drop obsolete unused RPCs
-- Date: 2026-06-11
-- Purpose:
--   Remove RPCs that are no longer used by the current app flow and have no
--   internal server dependencies:
--     - admin_update_user_permissions(UUID, JSONB)
--     - verify_otp_safe(TEXT, TEXT)
-- ════════════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS admin_update_user_permissions(UUID, JSONB);
DROP FUNCTION IF EXISTS verify_otp_safe(TEXT, TEXT);
