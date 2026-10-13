-- ══════════════════════════════════════════════════════════════════════
-- Migration: Staff Sessions Security
-- Date: 2026-06-15
-- Purpose:
--   Add server-side staff sessions so sensitive employee-management Edge
--   Functions do not rely on admin_uid alone.
-- ══════════════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS staff_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL,
  role_snapshot INT NOT NULL,
  device_id TEXT DEFAULT '',
  ip TEXT DEFAULT '',
  revoked INT DEFAULT 0 CHECK (revoked IN (0, 1)),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_used_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_staff_sessions_user_active
  ON staff_sessions (user_id, expires_at DESC)
  WHERE revoked = 0;

CREATE INDEX IF NOT EXISTS idx_staff_sessions_expiry
  ON staff_sessions (expires_at)
  WHERE revoked = 0;

-- Internal helper: creates a session and returns the plain token once.
CREATE OR REPLACE FUNCTION _issue_staff_session(
  p_user_uid UUID,
  p_device_id TEXT DEFAULT '',
  p_ip TEXT DEFAULT '',
  p_ttl INTERVAL DEFAULT INTERVAL '7 days'
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_role INT;
  v_token TEXT;
  v_expires_at TIMESTAMPTZ;
  v_session_id UUID;
BEGIN
  SELECT role INTO v_role
  FROM users
  WHERE id = p_user_uid
    AND i_del = 0
    AND sts = 0;

  IF v_role IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND_OR_INACTIVE';
  END IF;

  IF v_role < 2 THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_STAFF');
  END IF;

  v_token := encode(gen_random_bytes(32), 'hex');
  v_expires_at := NOW() + p_ttl;

  INSERT INTO staff_sessions (
    user_id,
    token_hash,
    role_snapshot,
    device_id,
    ip,
    expires_at
  ) VALUES (
    p_user_uid,
    crypt(v_token, gen_salt('bf', 8)),
    v_role,
    COALESCE(p_device_id, ''),
    COALESCE(p_ip, ''),
    v_expires_at
  ) RETURNING id INTO v_session_id;

  RETURN jsonb_build_object(
    'success', true,
    'session_id', v_session_id,
    'session_token', v_token,
    'expires_at', v_expires_at,
    'role', v_role
  );
END;
$$;

REVOKE ALL ON FUNCTION _issue_staff_session(UUID, TEXT, TEXT, INTERVAL) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION _issue_staff_session(UUID, TEXT, TEXT, INTERVAL) TO service_role;

-- Validates a staff/admin session token.
CREATE OR REPLACE FUNCTION validate_staff_session(
  p_user_uid UUID,
  p_token TEXT,
  p_min_role INT DEFAULT 5
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_session RECORD;
  v_user RECORD;
BEGIN
  IF p_user_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'USER_UID_REQUIRED');
  END IF;

  IF COALESCE(p_token, '') = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'SESSION_TOKEN_REQUIRED');
  END IF;

  SELECT id, role, sts, i_del INTO v_user
  FROM users
  WHERE id = p_user_uid
    AND i_del = 0;

  IF v_user IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'USER_NOT_FOUND');
  END IF;

  IF v_user.sts <> 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'USER_INACTIVE');
  END IF;

  IF v_user.role < p_min_role THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  FOR v_session IN
    SELECT id, token_hash, expires_at
    FROM staff_sessions
    WHERE user_id = p_user_uid
      AND revoked = 0
      AND expires_at > NOW()
    ORDER BY created_at DESC
  LOOP
    IF v_session.token_hash = crypt(p_token, v_session.token_hash) THEN
      UPDATE staff_sessions
      SET last_used_at = NOW()
      WHERE id = v_session.id;

      RETURN jsonb_build_object(
        'success', true,
        'user_id', p_user_uid,
        'role', v_user.role,
        'session_id', v_session.id,
        'expires_at', v_session.expires_at
      );
    END IF;
  END LOOP;

  RETURN jsonb_build_object('success', false, 'error', 'INVALID_SESSION');
END;
$$;

REVOKE ALL ON FUNCTION validate_staff_session(UUID, TEXT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION validate_staff_session(UUID, TEXT, INT) TO service_role;

CREATE OR REPLACE FUNCTION revoke_staff_session(
  p_user_uid UUID,
  p_token TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_session RECORD;
BEGIN
  IF p_user_uid IS NULL OR COALESCE(p_token, '') = '' THEN
    RETURN FALSE;
  END IF;

  FOR v_session IN
    SELECT id, token_hash
    FROM staff_sessions
    WHERE user_id = p_user_uid
      AND revoked = 0
  LOOP
    IF v_session.token_hash = crypt(p_token, v_session.token_hash) THEN
      UPDATE staff_sessions SET revoked = 1 WHERE id = v_session.id;
      RETURN TRUE;
    END IF;
  END LOOP;

  RETURN FALSE;
END;
$$;

REVOKE ALL ON FUNCTION revoke_staff_session(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION revoke_staff_session(UUID, TEXT) TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION revoke_all_staff_sessions(
  p_user_uid UUID
) RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_count INT;
BEGIN
  UPDATE staff_sessions
  SET revoked = 1
  WHERE user_id = p_user_uid
    AND revoked = 0;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION revoke_all_staff_sessions(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION revoke_all_staff_sessions(UUID) TO service_role;

-- Re-issue login_with_password with optional staff session info.
CREATE OR REPLACE FUNCTION login_with_password(
  p_identifier TEXT,
  p_password TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user RECORD;
  v_identifier TEXT;
  v_session JSONB := NULL;
BEGIN
  v_identifier := LOWER(TRIM(p_identifier));

  SELECT id, nm, role, pwd, sts, i_del INTO v_user
  FROM users
  WHERE (LOWER(usr) = v_identifier
         OR normalize_sy_phone(ph) = normalize_sy_phone(v_identifier))
    AND i_del = 0
  LIMIT 1;

  IF v_user IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING HINT = 'لم يتم العثور على حساب بهذا الاسم أو الرقم';
  END IF;

  IF v_user.pwd IS NULL THEN
    RAISE EXCEPTION 'NO_PASSWORD_SET' USING HINT = 'لم يتم تعيين كلمة مرور لهذا الحساب، سجّل دخولك عبر واتساب أولاً';
  END IF;

  IF v_user.sts = 2 THEN
    RAISE EXCEPTION 'USER_BANNED';
  END IF;

  IF v_user.sts = 1 THEN
    RAISE EXCEPTION 'USER_FROZEN';
  END IF;

  IF v_user.pwd != crypt(p_password, v_user.pwd) THEN
    RAISE EXCEPTION 'WRONG_PASSWORD' USING HINT = 'كلمة المرور غير صحيحة';
  END IF;

  IF v_user.role >= 2 THEN
    v_session := _issue_staff_session(v_user.id, '', '', INTERVAL '7 days');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'user_id', v_user.id,
    'role', v_user.role,
    'nm', v_user.nm,
    'staff_session', v_session
  );
END;
$$;

GRANT EXECUTE ON FUNCTION login_with_password(TEXT, TEXT) TO anon, authenticated, service_role;
