-- ════════════════════════════════════════════════════════════════════════════
-- users_public: remove private identity path from public view
-- Date: 2026-06-10
-- Purpose:
--   After moving identity images to ids_private, users.img may hold a private
--   storage path. It must not remain exposed in users_public.
-- ════════════════════════════════════════════════════════════════════════════

DROP VIEW IF EXISTS users_public CASCADE;
CREATE VIEW users_public AS
SELECT
  id,
  nm,
  role,
  brk,
  brk_cls,
  brk_nm,
  bg,
  vrf,
  pt,
  ref_cnt,
  ts_crt
FROM users
WHERE i_del = 0;

GRANT SELECT ON users_public TO anon, authenticated;
ALTER VIEW users_public SET (security_invoker = true);
