-- ════════════════════════════════════════════════════════════════════════════
-- Internal dynamic permissions
-- Date: 2026-06-10
-- Purpose:
--   Adds optional per-user permission overrides without changing the existing
--   numeric role model (0=user, 1=broker, 2=moderator, 3=deputy, 4=manager).
-- ════════════════════════════════════════════════════════════════════════════

ALTER TABLE users
ADD COLUMN IF NOT EXISTS perm JSONB NOT NULL DEFAULT '[]'::jsonb;

COMMENT ON COLUMN users.perm IS
  'Internal permissions override. Empty array means use default permissions for numeric role.';

CREATE OR REPLACE FUNCTION admin_update_user_permissions(
  p_target_uid UUID,
  p_perm JSONB DEFAULT '[]'::jsonb
)
RETURNS BOOLEAN AS $$
DECLARE
  v_admin_role INT;
  v_item TEXT;
  v_allowed TEXT[] := ARRAY[
    'admin_dashboard',
    'office_operations',
    'manage_users',
    'manage_permissions',
    'review_offers',
    'review_verifications',
    'media_review',
    'fraud_suspects',
    'manage_appointments',
    'manage_deals',
    'manage_payments',
    'manage_reports',
    'manage_config',
    'view_analytics',
    'broker_dashboard',
    'broker_offers',
    'broker_appointments',
    'broker_deals',
    'broker_stats',
    'user_home',
    'user_offers',
    'user_requests',
    'user_appointments',
    'user_profile'
  ];
BEGIN
  SELECT role INTO v_admin_role FROM users WHERE id = auth.uid();

  IF v_admin_role IS NULL OR v_admin_role < 3 THEN
    RAISE EXCEPTION 'FORBIDDEN: Deputy/admin role required.';
  END IF;

  IF p_perm IS NULL THEN
    p_perm := '[]'::jsonb;
  END IF;

  IF jsonb_typeof(p_perm) <> 'array' THEN
    RAISE EXCEPTION 'INVALID_PERMISSIONS: Expected JSON array.';
  END IF;

  FOR v_item IN SELECT jsonb_array_elements_text(p_perm)
  LOOP
    IF NOT (v_item = ANY(v_allowed)) THEN
      RAISE EXCEPTION 'INVALID_PERMISSION: %', v_item;
    END IF;
  END LOOP;

  UPDATE users
  SET perm = p_perm,
      ts_upd = NOW()
  WHERE id = p_target_uid
    AND i_del = 0;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION admin_update_user_permissions FROM anon;
GRANT EXECUTE ON FUNCTION admin_update_user_permissions TO authenticated;

COMMENT ON FUNCTION admin_update_user_permissions IS
  'Internal permissions management. Requires role>=3 and validates allowed permission keys.';
