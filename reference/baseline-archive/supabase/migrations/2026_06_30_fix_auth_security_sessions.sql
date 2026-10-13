-- 1. Update _issue_staff_session to allow all users (role >= 0)
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

  -- ALLOW ALL ROLES NOW
  -- IF v_role < 2 THEN
  --   RETURN jsonb_build_object('success', false, 'error', 'NOT_STAFF');
  -- END IF;

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

-- 2. Update login_with_password to always issue a session
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

  -- Always issue session for any authenticated user
  v_session := _issue_staff_session(v_user.id, '', '', INTERVAL '7 days');

  RETURN jsonb_build_object(
    'success', true,
    'user_id', v_user.id,
    'role', v_user.role,
    'nm', v_user.nm,
    'staff_session', v_session
  );
END;
$$;
