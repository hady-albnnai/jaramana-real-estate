-- ══════════════════════════════════════════════════════════════════════
-- Migration: Admin Employee Management Final
-- Date: 2026-06-15
-- Purpose:
--   Final safe RPC layer for employee management inspired by Final project
--   while respecting Sweeda users table, numeric roles, usr/pwd auth model.
-- ══════════════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Ensure auth/password fields exist for staff accounts.
ALTER TABLE users ADD COLUMN IF NOT EXISTS eml TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS usr TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS pwd TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS vrf INT DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS pkg_grace TIMESTAMPTZ;

-- Ensure final 0..6 role contract.
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check;
ALTER TABLE users ADD CONSTRAINT users_role_check CHECK (role BETWEEN 0 AND 8);

CREATE UNIQUE INDEX IF NOT EXISTS ux_users_username_active
  ON users (LOWER(usr))
  WHERE usr IS NOT NULL AND i_del = 0;

-- ────────────────────────────────────────────────────────────────────
-- Shared helpers
-- ────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION _admin_employee_assert_actor(
  p_admin_uid UUID,
  p_min_role INT DEFAULT 5
) RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_role INT;
BEGIN
  IF p_admin_uid IS NULL THEN
    RAISE EXCEPTION 'ADMIN_UID_REQUIRED';
  END IF;

  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_MISMATCH';
  END IF;

  SELECT role INTO v_role
  FROM users
  WHERE id = p_admin_uid AND i_del = 0 AND sts = 0;

  IF v_role IS NULL OR v_role < p_min_role THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  RETURN v_role;
END;
$$;

CREATE OR REPLACE FUNCTION _admin_employee_log(
  p_admin_uid UUID,
  p_action TEXT,
  p_target_uid UUID DEFAULT NULL,
  p_payload JSONB DEFAULT '{}'::jsonb
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO activity_log (uid, act, det, ref_id, ref_col, ts_crt)
  VALUES (
    p_admin_uid,
    99,
    p_action || ': ' || COALESCE(p_payload::TEXT, '{}'),
    COALESCE(p_target_uid::TEXT, ''),
    'users',
    NOW()
  );
END;
$$;

-- ────────────────────────────────────────────────────────────────────
-- Read staff users for management screen
-- ────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_all_staff_users(p_admin_uid UUID)
RETURNS SETOF JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_admin_role INT;
BEGIN
  v_admin_role := _admin_employee_assert_actor(p_admin_uid, 5);

  RETURN QUERY
    SELECT jsonb_build_object(
      'id', u.id,
      'nm', u.nm,
      'ph', u.ph,
      'eml', u.eml,
      'ad', u.ad,
      'role', u.role,
      'sid', u.sid,
      'img', u.img,
      'pt', u.pt,
      'bg', u.bg,
      'bg_ts', u.bg_ts,
      'b_pkg', u.b_pkg,
      'pkg_end', u.pkg_end,
      'pkg_grace', u.pkg_grace,
      'brk', u.brk,
      'brk_cls', u.brk_cls,
      'brk_nm', u.brk_nm,
      'sts', u.sts,
      'ban_rsn', u.ban_rsn,
      'ntf', u.ntf,
      'stats', u.stats,
      'wk_lgn', u.wk_lgn,
      'strk', u.strk,
      'strk_dt', u.strk_dt,
      'i_del', u.i_del,
      'perm', u.perm,
      'ts_crt', u.ts_crt,
      'ts_upd', u.ts_upd,
      'vrf', u.vrf,
      'usr', u.usr,
      'pwd', CASE WHEN u.pwd IS NOT NULL THEN 'set' ELSE NULL END
    )
    FROM users u
    WHERE u.i_del = 0
      AND u.role IN (2, 3, 4, 5, 6)
    ORDER BY u.role DESC, u.ts_crt DESC;
END;
$$;
GRANT EXECUTE ON FUNCTION get_all_staff_users(UUID) TO anon, authenticated, service_role;

-- ────────────────────────────────────────────────────────────────────
-- Create staff user (called by Edge Function create-user)
-- ────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admin_create_staff_user(
  p_admin_uid UUID,
  p_full_name TEXT,
  p_phone TEXT,
  p_email TEXT,
  p_username TEXT,
  p_password TEXT,
  p_role INT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_admin_role INT;
  v_phone TEXT;
  v_username TEXT;
  v_new_id UUID;
BEGIN
  v_admin_role := _admin_employee_assert_actor(p_admin_uid, 5);

  IF p_role NOT IN (2, 3, 4, 5) THEN
    RAISE EXCEPTION 'INVALID_ROLE';
  END IF;

  IF v_admin_role < 6 AND p_role >= 5 THEN
    RAISE EXCEPTION 'ONLY_MANAGER_CAN_CREATE_DEPUTY';
  END IF;

  IF LENGTH(TRIM(COALESCE(p_full_name, ''))) < 2 THEN
    RAISE EXCEPTION 'NAME_REQUIRED';
  END IF;

  IF LENGTH(COALESCE(p_password, '')) < 8 THEN
    RAISE EXCEPTION 'PASSWORD_TOO_SHORT';
  END IF;

  v_phone := normalize_sy_phone(COALESCE(p_phone, ''));
  IF v_phone = '' THEN
    RAISE EXCEPTION 'PHONE_REQUIRED';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE normalize_sy_phone(ph) = v_phone AND i_del = 0) THEN
    RAISE EXCEPTION 'PHONE_EXISTS';
  END IF;

  v_username := NULLIF(LOWER(TRIM(COALESCE(p_username, ''))), '');
  IF v_username IS NOT NULL THEN
    IF LENGTH(v_username) < 3 OR LENGTH(v_username) > 30 THEN
      RAISE EXCEPTION 'USERNAME_LENGTH';
    END IF;
    IF NOT v_username ~ '^[a-z0-9_.]+$' THEN
      RAISE EXCEPTION 'USERNAME_INVALID_CHARS';
    END IF;
    IF EXISTS (SELECT 1 FROM users WHERE LOWER(usr) = v_username AND i_del = 0) THEN
      RAISE EXCEPTION 'USERNAME_TAKEN';
    END IF;
  END IF;

  INSERT INTO users (nm, ph, eml, usr, pwd, role, sts, vrf, i_del, ts_crt, ts_upd)
  VALUES (
    TRIM(COALESCE(p_full_name, '')),
    v_phone,
    NULLIF(TRIM(COALESCE(p_email, '')), ''),
    v_username,
    crypt(p_password, gen_salt('bf', 8)),
    p_role,
    0,
    0,
    0,
    NOW(),
    NOW()
  )
  RETURNING id INTO v_new_id;

  PERFORM _admin_employee_log(
    p_admin_uid,
    'staff_create',
    v_new_id,
    jsonb_build_object('role', p_role, 'phone', v_phone, 'username', v_username)
  );

  RETURN jsonb_build_object('success', true, 'user_id', v_new_id);
END;
$$;
REVOKE ALL ON FUNCTION admin_create_staff_user(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_create_staff_user(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, INT) TO service_role;

-- ────────────────────────────────────────────────────────────────────
-- Update staff role (called by Edge Function update-user-role)
-- ────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admin_update_staff_role(
  p_admin_uid UUID,
  p_target_uid UUID,
  p_role INT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_admin_role INT;
  v_target_role INT;
BEGIN
  v_admin_role := _admin_employee_assert_actor(p_admin_uid, 5);

  SELECT role INTO v_target_role FROM users WHERE id = p_target_uid AND i_del = 0;
  IF v_target_role IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;
  IF v_target_role = 6 THEN
    RAISE EXCEPTION 'CANNOT_MODIFY_MANAGER';
  END IF;
  IF p_role NOT IN (2, 3, 4, 5) THEN
    RAISE EXCEPTION 'INVALID_ROLE';
  END IF;
  IF v_admin_role < 6 AND (p_role >= 5 OR v_target_role >= 5) THEN
    RAISE EXCEPTION 'ONLY_MANAGER_CAN_MANAGE_DEPUTIES';
  END IF;

  UPDATE users
  SET role = p_role,
      brk = CASE WHEN p_role = 1 THEN 1 ELSE brk END,
      ts_upd = NOW()
  WHERE id = p_target_uid AND i_del = 0;

  PERFORM _admin_employee_log(
    p_admin_uid,
    'staff_role_update',
    p_target_uid,
    jsonb_build_object('old_role', v_target_role, 'new_role', p_role)
  );

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE ALL ON FUNCTION admin_update_staff_role(UUID, UUID, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_update_staff_role(UUID, UUID, INT) TO service_role;

-- ────────────────────────────────────────────────────────────────────
-- Toggle staff status (called by Edge Function toggle-user-status)
-- ────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admin_toggle_staff_status(
  p_admin_uid UUID,
  p_target_uid UUID,
  p_status INT,
  p_reason TEXT DEFAULT ''
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_admin_role INT;
  v_target_role INT;
BEGIN
  v_admin_role := _admin_employee_assert_actor(p_admin_uid, 5);

  SELECT role INTO v_target_role FROM users WHERE id = p_target_uid AND i_del = 0;
  IF v_target_role IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;
  IF v_target_role = 6 THEN
    RAISE EXCEPTION 'CANNOT_MODIFY_MANAGER';
  END IF;
  IF v_admin_role < 6 AND v_target_role >= 5 THEN
    RAISE EXCEPTION 'ONLY_MANAGER_CAN_MANAGE_DEPUTIES';
  END IF;
  IF p_status NOT IN (0, 1, 2) THEN
    RAISE EXCEPTION 'INVALID_STATUS';
  END IF;

  UPDATE users
  SET sts = p_status,
      ban_rsn = CASE WHEN p_status IN (1, 2) THEN COALESCE(p_reason, '') ELSE '' END,
      ts_upd = NOW()
  WHERE id = p_target_uid AND i_del = 0;

  PERFORM _admin_employee_log(
    p_admin_uid,
    'staff_status_update',
    p_target_uid,
    jsonb_build_object('status', p_status, 'reason', COALESCE(p_reason, ''))
  );

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE ALL ON FUNCTION admin_toggle_staff_status(UUID, UUID, INT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_toggle_staff_status(UUID, UUID, INT, TEXT) TO service_role;

-- ────────────────────────────────────────────────────────────────────
-- Reset staff password (called by Edge Function reset-user-password)
-- ────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admin_reset_staff_password(
  p_admin_uid UUID,
  p_target_uid UUID,
  p_new_password TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_admin_role INT;
  v_target_role INT;
BEGIN
  v_admin_role := _admin_employee_assert_actor(p_admin_uid, 5);

  SELECT role INTO v_target_role FROM users WHERE id = p_target_uid AND i_del = 0;
  IF v_target_role IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;
  IF v_target_role = 6 THEN
    RAISE EXCEPTION 'CANNOT_MODIFY_MANAGER';
  END IF;
  IF v_admin_role < 6 AND v_target_role >= 5 THEN
    RAISE EXCEPTION 'ONLY_MANAGER_CAN_MANAGE_DEPUTIES';
  END IF;
  IF LENGTH(COALESCE(p_new_password, '')) < 8 THEN
    RAISE EXCEPTION 'PASSWORD_TOO_SHORT';
  END IF;

  UPDATE users
  SET pwd = crypt(p_new_password, gen_salt('bf', 8)),
      ts_upd = NOW()
  WHERE id = p_target_uid AND i_del = 0;

  PERFORM _admin_employee_log(p_admin_uid, 'staff_password_reset', p_target_uid, '{}'::jsonb);

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE ALL ON FUNCTION admin_reset_staff_password(UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_reset_staff_password(UUID, UUID, TEXT) TO service_role;

-- ────────────────────────────────────────────────────────────────────
-- Delete staff user (soft delete, called by Edge Function delete-user)
-- ────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admin_delete_staff_user(
  p_admin_uid UUID,
  p_target_uid UUID
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_admin_role INT;
  v_target_role INT;
BEGIN
  v_admin_role := _admin_employee_assert_actor(p_admin_uid, 5);

  SELECT role INTO v_target_role FROM users WHERE id = p_target_uid AND i_del = 0;
  IF v_target_role IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;
  IF v_target_role = 6 THEN
    RAISE EXCEPTION 'CANNOT_DELETE_MANAGER';
  END IF;
  IF v_admin_role < 6 AND v_target_role >= 5 THEN
    RAISE EXCEPTION 'ONLY_MANAGER_CAN_MANAGE_DEPUTIES';
  END IF;

  UPDATE users
  SET i_del = 1,
      sts = 1,
      ts_upd = NOW()
  WHERE id = p_target_uid AND i_del = 0;

  PERFORM _admin_employee_log(p_admin_uid, 'staff_delete', p_target_uid, '{}'::jsonb);

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE ALL ON FUNCTION admin_delete_staff_user(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_delete_staff_user(UUID, UUID) TO service_role;
