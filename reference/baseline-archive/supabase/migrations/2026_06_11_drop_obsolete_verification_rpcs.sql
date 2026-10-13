-- ════════════════════════════════════════════════════════════════════════════
-- Cleanup: drop obsolete verification RPCs
-- Date: 2026-06-11
-- Purpose:
--   Remove old verification RPCs that were replaced by the current
--   dev-compatible versions:
--     - request_verification_by_uid
--     - admin_approve_verification_by_admin
--     - admin_reject_verification_by_admin
-- ════════════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS request_verification();
DROP FUNCTION IF EXISTS admin_approve_verification(UUID);
DROP FUNCTION IF EXISTS admin_reject_verification(UUID, TEXT);
