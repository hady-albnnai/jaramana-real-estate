-- ══════════════════════════════════════════════════════════════════════
-- Migration: Input Validation & Abuse Hardening
-- Date: 2026-06-15
-- Purpose:
--   Add server-side input validation/sanitization helpers and patch key RPCs
--   so the server rejects malformed/abusive input even if the client UI is bypassed.
--
-- Notes:
--   This version preserves the current production logic for offer quotas,
--   package grace, and offers.added_by while adding validation.
-- ══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION app_clean_text(p_value TEXT, p_max_len INT DEFAULT 1000)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v TEXT;
BEGIN
  v := COALESCE(p_value, '');
  v := regexp_replace(v, '[[:cntrl:]]', '', 'g');
  v := regexp_replace(v, '\s+', ' ', 'g');
  v := btrim(v);
  IF p_max_len IS NOT NULL AND p_max_len > 0 AND length(v) > p_max_len THEN
    v := substring(v from 1 for p_max_len);
  END IF;
  RETURN v;
END;
$$;

CREATE OR REPLACE FUNCTION app_assert_text_len(
  p_value TEXT,
  p_field TEXT,
  p_min INT DEFAULT 0,
  p_max INT DEFAULT 1000
) RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v TEXT;
BEGIN
  v := app_clean_text(p_value, p_max + 1);
  IF length(v) < p_min THEN
    RAISE EXCEPTION '%_TOO_SHORT', upper(p_field);
  END IF;
  IF length(v) > p_max THEN
    RAISE EXCEPTION '%_TOO_LONG', upper(p_field);
  END IF;
  IF v ~ '[<>]' THEN
    RAISE EXCEPTION '%_INVALID_CHARS', upper(p_field);
  END IF;
  RETURN v;
END;
$$;

CREATE OR REPLACE FUNCTION app_assert_username(p_username TEXT, p_required BOOLEAN DEFAULT TRUE)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v TEXT;
BEGIN
  v := lower(btrim(COALESCE(p_username, '')));
  IF v = '' THEN
    IF p_required THEN
      RAISE EXCEPTION 'USERNAME_REQUIRED';
    END IF;
    RETURN NULL;
  END IF;
  IF length(v) < 3 OR length(v) > 30 THEN
    RAISE EXCEPTION 'USERNAME_LENGTH';
  END IF;
  IF NOT v ~ '^[a-z0-9_.]+$' THEN
    RAISE EXCEPTION 'USERNAME_INVALID_CHARS';
  END IF;
  RETURN v;
END;
$$;

CREATE OR REPLACE FUNCTION app_assert_password(p_password TEXT, p_min INT DEFAULT 8)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF length(COALESCE(p_password, '')) < p_min THEN
    RAISE EXCEPTION 'PASSWORD_TOO_SHORT';
  END IF;
  IF length(COALESCE(p_password, '')) > 128 THEN
    RAISE EXCEPTION 'PASSWORD_TOO_LONG';
  END IF;
  RETURN p_password;
END;
$$;

CREATE OR REPLACE FUNCTION app_assert_phone(p_phone TEXT)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v TEXT;
BEGIN
  v := normalize_sy_phone(COALESCE(p_phone, ''));
  IF v = '' THEN
    RAISE EXCEPTION 'PHONE_REQUIRED';
  END IF;
  IF v !~ '^\+9639[0-9]{8}$' THEN
    RAISE EXCEPTION 'PHONE_INVALID';
  END IF;
  RETURN v;
END;
$$;

CREATE OR REPLACE FUNCTION app_assert_price(p_value NUMERIC, p_required BOOLEAN DEFAULT TRUE)
RETURNS NUMERIC
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_value IS NULL THEN
    IF p_required THEN
      RAISE EXCEPTION 'PRICE_REQUIRED';
    END IF;
    RETURN NULL;
  END IF;
  IF p_value <= 0 THEN
    RAISE EXCEPTION 'INVALID_PRICE';
  END IF;
  IF p_value > 999999999999 THEN
    RAISE EXCEPTION 'PRICE_TOO_LARGE';
  END IF;
  RETURN p_value;
END;
$$;

-- Harden register_password username/password validation.
CREATE OR REPLACE FUNCTION register_password(
  p_user_uid UUID,
  p_username TEXT,
  p_password TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_usr TEXT;
  v_existing UUID;
BEGIN
  v_usr := app_assert_username(p_username, TRUE);
  PERFORM app_assert_password(p_password, 8);

  SELECT id INTO v_existing
  FROM users
  WHERE lower(usr) = v_usr
    AND i_del = 0
    AND id <> p_user_uid;

  IF v_existing IS NOT NULL THEN
    RAISE EXCEPTION 'USERNAME_TAKEN';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_user_uid AND i_del = 0) THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;

  UPDATE users
  SET usr = v_usr,
      pwd = crypt(p_password, gen_salt('bf', 8)),
      ts_upd = NOW()
  WHERE id = p_user_uid;

  RETURN jsonb_build_object('success', true, 'username', v_usr);
END;
$$;
GRANT EXECUTE ON FUNCTION register_password(UUID, TEXT, TEXT) TO anon, authenticated, service_role;

-- Harden admin staff creation.
CREATE OR REPLACE FUNCTION admin_create_staff_user(
  p_admin_uid UUID,
  p_full_name TEXT,
  p_phone TEXT,
  p_email TEXT DEFAULT '',
  p_username TEXT DEFAULT '',
  p_password TEXT DEFAULT '',
  p_role INT DEFAULT 4
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_admin_role INT;
  v_phone TEXT;
  v_username TEXT;
  v_name TEXT;
  v_email TEXT;
  v_new_id UUID;
BEGIN
  v_admin_role := _admin_employee_assert_actor(p_admin_uid, 5);

  IF p_role NOT IN (2, 3, 4, 5) THEN
    RAISE EXCEPTION 'INVALID_ROLE';
  END IF;
  IF v_admin_role < 6 AND p_role >= 5 THEN
    RAISE EXCEPTION 'ONLY_MANAGER_CAN_CREATE_DEPUTY';
  END IF;

  v_name := app_assert_text_len(p_full_name, 'name', 2, 60);
  v_phone := app_assert_phone(p_phone);
  v_username := app_assert_username(p_username, FALSE);
  PERFORM app_assert_password(p_password, 8);
  v_email := NULLIF(app_clean_text(p_email, 120), '');

  IF v_email IS NOT NULL AND v_email !~* '^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$' THEN
    RAISE EXCEPTION 'EMAIL_INVALID';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE normalize_sy_phone(ph) = v_phone AND i_del = 0) THEN
    RAISE EXCEPTION 'PHONE_EXISTS';
  END IF;
  IF v_username IS NOT NULL AND EXISTS (SELECT 1 FROM users WHERE lower(usr) = v_username AND i_del = 0) THEN
    RAISE EXCEPTION 'USERNAME_TAKEN';
  END IF;

  INSERT INTO users (nm, ph, eml, usr, pwd, role, sts, vrf, i_del, ts_crt, ts_upd)
  VALUES (v_name, v_phone, v_email, v_username, crypt(p_password, gen_salt('bf', 8)), p_role, 0, 0, 0, NOW(), NOW())
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

-- Harden profile updates.
CREATE OR REPLACE FUNCTION update_user_profile_internal(
  p_user_uid UUID,
  p_payload JSONB
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_nm TEXT;
  v_sid TEXT;
  v_ad TEXT;
  v_img TEXT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  v_nm := CASE WHEN p_payload ? 'nm' THEN app_assert_text_len(p_payload->>'nm', 'name', 2, 60) ELSE NULL END;
  v_sid := CASE WHEN p_payload ? 'sid' THEN app_clean_text(p_payload->>'sid', 60) ELSE NULL END;
  v_ad := CASE WHEN p_payload ? 'ad' THEN app_clean_text(p_payload->>'ad', 200) ELSE NULL END;
  v_img := CASE WHEN p_payload ? 'img' THEN app_clean_text(p_payload->>'img', 500) ELSE NULL END;

  UPDATE users
  SET nm = COALESCE(v_nm, nm),
      sid = COALESCE(v_sid, sid),
      ad = COALESCE(v_ad, ad),
      img = COALESCE(v_img, img),
      ts_upd = NOW()
  WHERE id = p_user_uid
    AND i_del = 0;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;
  RETURN TRUE;
END;
$$;
GRANT EXECUTE ON FUNCTION update_user_profile_internal(UUID, JSONB) TO anon, authenticated, service_role;

-- Harden request create/update.
CREATE OR REPLACE FUNCTION create_request_internal(
  p_user_uid UUID,
  p_request JSONB
) RETURNS SETOF requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user users%ROWTYPE;
  v_config JSONB;
  v_limit INT;
  v_used INT;
  v_name TEXT;
  v_phone TEXT;
  v_notes TEXT;
  v_price NUMERIC;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT * INTO v_user FROM users WHERE id = p_user_uid AND i_del = 0 AND sts = 0;
  IF v_user.id IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_ACTIVE_OR_NOT_FOUND';
  END IF;

  v_name := app_assert_text_len(p_request->>'cl_nm', 'client_name', 2, 60);
  v_phone := app_assert_phone(p_request->>'cl_ph');
  v_notes := app_clean_text(p_request->>'notes', 1000);
  v_price := COALESCE((p_request->>'prc')::NUMERIC, 0);
  IF v_price < 0 OR v_price > 999999999999 THEN
    RAISE EXCEPTION 'INVALID_PRICE';
  END IF;

  -- موظف المكتب فما فوق معفي من الحصة.
  IF COALESCE(v_user.role, 0) < 4 THEN
    SELECT value INTO v_config FROM app_config WHERE key = 'main';
    v_limit := CASE WHEN COALESCE(v_user.role, 0) = 1
      THEN COALESCE((v_config->'qta'->'b'->>'r')::INT, 5)
      ELSE COALESCE((v_config->'qta'->'u'->>'r')::INT, 3)
    END;

    SELECT COUNT(*) INTO v_used FROM requests WHERE usr_id = p_user_uid AND i_del = 0;
    IF COALESCE(v_used, 0) >= COALESCE(v_limit, 3) THEN
      RAISE EXCEPTION 'QUOTA_EXCEEDED';
    END IF;
  END IF;

  RETURN QUERY
  INSERT INTO requests (typ, elm, cl_nm, cl_ph, prc, cur, notes, specs, usr_id, sts, i_del, ts_crt)
  VALUES (
    COALESCE((p_request->>'typ')::INT, 0),
    COALESCE((p_request->>'elm')::INT, 0),
    v_name,
    v_phone,
    v_price,
    COALESCE((p_request->>'cur')::INT, 0),
    v_notes,
    COALESCE(p_request->'specs', '{}'::jsonb),
    p_user_uid,
    0,
    0,
    NOW()
  ) RETURNING *;
END;
$$;
GRANT EXECUTE ON FUNCTION create_request_internal(UUID, JSONB) TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION update_request_internal(
  p_user_uid UUID,
  p_request_id UUID,
  p_patch JSONB
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_name TEXT;
  v_phone TEXT;
  v_notes TEXT;
  v_price NUMERIC;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  v_name := CASE WHEN p_patch ? 'cl_nm' THEN app_assert_text_len(p_patch->>'cl_nm', 'client_name', 2, 60) ELSE NULL END;
  v_phone := CASE WHEN p_patch ? 'cl_ph' THEN app_assert_phone(p_patch->>'cl_ph') ELSE NULL END;
  v_notes := CASE WHEN p_patch ? 'notes' THEN app_clean_text(p_patch->>'notes', 1000) ELSE NULL END;
  v_price := CASE WHEN p_patch ? 'prc' THEN (p_patch->>'prc')::NUMERIC ELSE NULL END;
  IF v_price IS NOT NULL AND (v_price < 0 OR v_price > 999999999999) THEN
    RAISE EXCEPTION 'INVALID_PRICE';
  END IF;

  UPDATE requests
  SET typ = COALESCE((p_patch->>'typ')::INT, typ),
      elm = COALESCE((p_patch->>'elm')::INT, elm),
      cl_nm = COALESCE(v_name, cl_nm),
      cl_ph = COALESCE(v_phone, cl_ph),
      prc = COALESCE(v_price, prc),
      cur = COALESCE((p_patch->>'cur')::INT, cur),
      notes = COALESCE(v_notes, notes),
      specs = COALESCE(p_patch->'specs', specs)
  WHERE id = p_request_id
    AND usr_id = p_user_uid
    AND i_del = 0;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'REQUEST_NOT_FOUND_OR_NOT_ALLOWED';
  END IF;
  RETURN TRUE;
END;
$$;
GRANT EXECUTE ON FUNCTION update_request_internal(UUID, UUID, JSONB) TO anon, authenticated, service_role;

-- Harden offer creation while preserving current production logic.
CREATE OR REPLACE FUNCTION create_offer_internal(
  p_user_uid UUID,
  p_offer JSONB
) RETURNS SETOF offers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user users%ROWTYPE;
  v_config JSONB;
  v_limit INT;
  v_used INT;
  v_recent_deleted INT;
  v_duplicate BOOLEAN;
  v_effective_pkg INT;
  v_title TEXT;
  v_contact_ph TEXT;
  v_desc TEXT;
  v_exact_loc TEXT;
  v_soc_txt TEXT;
  v_price NUMERIC;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT * INTO v_user FROM users WHERE id = p_user_uid AND i_del = 0 AND sts = 0;
  IF v_user.id IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_ACTIVE_OR_NOT_FOUND';
  END IF;

  v_title := app_assert_text_len(p_offer->>'ttl', 'title', 2, 120);
  v_contact_ph := app_assert_phone(p_offer->>'contact_ph');
  v_price := app_assert_price(COALESCE((p_offer->>'prc')::NUMERIC, 0), TRUE);
  v_desc := app_clean_text(p_offer->>'descript', 2000);
  v_exact_loc := app_clean_text(p_offer->>'exact_loc', 300);
  v_soc_txt := app_clean_text(p_offer->>'soc_txt', 500);

  -- الإدارة الداخلية (موظف مكتب فما فوق) غير مقيّدة بحصة.
  IF COALESCE(v_user.role, 0) < 4 THEN
    SELECT value INTO v_config FROM app_config WHERE key = 'main';

    v_effective_pkg := CASE
      WHEN COALESCE(v_user.b_pkg, 0) = 0 THEN 0
      WHEN v_user.pkg_grace IS NOT NULL AND v_user.pkg_grace > NOW() THEN v_user.b_pkg
      WHEN v_user.pkg_end IS NOT NULL AND v_user.pkg_end > NOW() THEN v_user.b_pkg
      ELSE 0
    END;

    v_limit := COALESCE((v_config->'pkg'->(v_effective_pkg::TEXT)->>'o')::INT,
      CASE WHEN COALESCE(v_user.role, 0) = 1 THEN 5 ELSE 1 END);

    SELECT COUNT(*) INTO v_used
    FROM offers
    WHERE usr_id = p_user_uid
      AND i_del = 0
      AND sts IN (0, 1, 2, 5);

    SELECT COUNT(*) INTO v_recent_deleted
    FROM offers
    WHERE usr_id = p_user_uid
      AND i_del = 1
      AND ts_crt >= NOW() - INTERVAL '24 hours';

    v_used := COALESCE(v_used, 0) + COALESCE(v_recent_deleted, 0);
    IF v_used >= v_limit THEN
      RAISE EXCEPTION 'QUOTA_EXCEEDED';
    END IF;
  END IF;

  SELECT check_offer_duplicate(
    v_title,
    v_price,
    COALESCE(p_offer->'loc', '{"r":0,"d":""}'::jsonb),
    p_user_uid
  ) INTO v_duplicate;

  IF v_duplicate THEN
    RAISE EXCEPTION 'DUPLICATE_OFFER';
  END IF;

  RETURN QUERY
  INSERT INTO offers (
    usr_id, brk_id, brk_pct, typ, trx, cat, sub, contact_ph,
    ttl, prc, cur, loc, descript, imgs, vdo, doc_tp, doc_img,
    exact_loc, specs, com, sts, rsn, vws, fvs, i_pub, i_soc,
    soc_pub, soc_txt, i_dup, dup_of, avl, i_del, ts_crt, ts_pub, ts_end, ts_ren, added_by
  ) VALUES (
    p_user_uid,
    NULLIF(p_offer->>'brk_id', '')::UUID,
    COALESCE((p_offer->>'brk_pct')::NUMERIC, 0),
    COALESCE((p_offer->>'typ')::INT, 0),
    COALESCE((p_offer->>'trx')::INT, 0),
    COALESCE((p_offer->>'cat')::INT, 0),
    COALESCE((p_offer->>'sub')::INT, 0),
    v_contact_ph,
    v_title,
    v_price,
    COALESCE((p_offer->>'cur')::INT, 0),
    COALESCE(p_offer->'loc', '{}'::jsonb),
    v_desc,
    COALESCE(p_offer->'imgs', '[]'::jsonb),
    app_clean_text(p_offer->>'vdo', 500),
    COALESCE((p_offer->>'doc_tp')::INT, 0),
    app_clean_text(p_offer->>'doc_img', 500),
    v_exact_loc,
    COALESCE(p_offer->'specs', '{}'::jsonb),
    COALESCE((p_offer->>'com')::NUMERIC, 0),
    1,
    '',
    0,
    0,
    0,
    COALESCE((p_offer->>'i_soc')::INT, 0),
    0,
    v_soc_txt,
    0,
    NULL,
    COALESCE(p_offer->'avl', '{}'::jsonb),
    0,
    NOW(),
    NULL,
    NULL,
    NULL,
    CASE WHEN COALESCE(v_user.role, 0) >= 4 THEN p_user_uid ELSE NULL END
  ) RETURNING *;
END;
$$;
GRANT EXECUTE ON FUNCTION create_offer_internal(UUID, JSONB) TO anon, authenticated, service_role;
