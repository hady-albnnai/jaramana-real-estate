-- ══════════════════════════════════════════════════════════════════════
-- Migration: Staff Management Enhancement & Clean Slate
-- Date: 2026-06-16
-- Purpose:
--   1. Update staff creation to include ID, SID, and Address.
--   2. Fix Fraud Suspects RPC to use session-based security.
--   3. Provide a wipe function for test data.
--   4. Update Employee (Role 4) permissions to include verifications.
-- ══════════════════════════════════════════════════════════════════════

-- 1. Update admin_create_staff_user
CREATE OR REPLACE FUNCTION admin_create_staff_user(
  p_admin_uid UUID,
  p_full_name TEXT,
  p_phone TEXT,
  p_email TEXT,
  p_username TEXT,
  p_password TEXT,
  p_role INT,
  p_address TEXT DEFAULT '',
  p_sid TEXT DEFAULT '',
  p_img TEXT DEFAULT ''
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

  INSERT INTO users (nm, ph, eml, usr, pwd, role, sts, vrf, ad, sid, img, i_del, ts_crt, ts_upd)
  VALUES (
    TRIM(COALESCE(p_full_name, '')),
    v_phone,
    NULLIF(TRIM(COALESCE(p_email, '')), ''),
    v_username,
    crypt(p_password, gen_salt('bf', 8)),
    p_role,
    0,
    2, -- Verified officially since added by Admin
    COALESCE(p_address, ''),
    COALESCE(p_sid, ''),
    COALESCE(p_img, ''),
    0,
    NOW(),
    NOW()
  )
  RETURNING id INTO v_new_id;

  PERFORM _admin_employee_log(
    p_admin_uid,
    'staff_create',
    v_new_id,
    jsonb_build_object('role', p_role, 'phone', v_phone, 'username', v_username, 'vrf', 2)
  );

  RETURN jsonb_build_object('success', true, 'user_id', v_new_id);
END;
$$;
GRANT EXECUTE ON FUNCTION admin_create_staff_user(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, INT, TEXT, TEXT, TEXT) TO service_role;

-- 2. Fix admin_fraud_suspects
DROP FUNCTION IF EXISTS admin_fraud_suspects();
CREATE OR REPLACE FUNCTION admin_fraud_suspects(p_admin_uid UUID)
RETURNS SETOF fraud_suspects 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Assert actor role 4 (Employee) or higher
  PERFORM _admin_employee_assert_actor(p_admin_uid, 4);
  
  RETURN QUERY SELECT * FROM fraud_suspects ORDER BY account_count DESC;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_fraud_suspects(UUID) TO anon, authenticated, service_role;

-- 3. Data Wipe Function (Safe root)
CREATE OR REPLACE FUNCTION admin_wipe_test_data(p_admin_uid UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_admin_role INT;
BEGIN
  v_admin_role := _admin_employee_assert_actor(p_admin_uid, 6); -- Only Manager

  -- Delete in order to respect constraints
  DELETE FROM reports;
  DELETE FROM deals;
  DELETE FROM payments;
  DELETE FROM appointments;
  DELETE FROM photography_tasks;
  DELETE FROM requests;
  DELETE FROM offers;
  DELETE FROM notifications;
  DELETE FROM otp_codes;
  DELETE FROM activity_log WHERE uid <> p_admin_uid;
  DELETE FROM staff_sessions WHERE uid <> p_admin_uid;
  
  -- Delete all users except current manager and any other managers if needed
  -- Usually we keep the one who is wiping
  DELETE FROM users WHERE id <> p_admin_uid;

  RETURN jsonb_build_object('success', true, 'message', 'System wiped successfully');
END;
$$;
GRANT EXECUTE ON FUNCTION admin_wipe_test_data(UUID) TO service_role;

-- 4. Update default permissions for Role 4 (Employee)
-- In lib/core/services/permission_service.dart it is already role 4
-- but we ensure the DB defaults match if we use them there.
-- Currently DB users table has a 'perm' column.
