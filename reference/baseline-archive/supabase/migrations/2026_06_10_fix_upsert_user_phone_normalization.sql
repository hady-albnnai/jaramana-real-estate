-- ════════════════════════════════════════════════════════════════════════════
-- Ensure WhatsApp/SMS auth upsert uses normalized phone
-- Date: 2026-06-10
-- Purpose:
--   The dev fallback login path calls upsert_user_after_otp, so it must use
--   normalize_sy_phone to avoid duplicated accounts for the same phone.
-- ════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION upsert_user_after_otp(
  p_identifier TEXT,
  p_channel TEXT
)
RETURNS TABLE(user_id UUID, is_new BOOLEAN) AS $$
DECLARE
  v_uid UUID;
  v_new BOOLEAN := FALSE;
  v_identifier TEXT;
BEGIN
  IF p_channel = 'whatsapp' OR p_channel = 'sms' THEN
    v_identifier := normalize_sy_phone(p_identifier);

    SELECT id INTO v_uid
    FROM users
    WHERE normalize_sy_phone(ph) = v_identifier
      AND i_del = 0
    LIMIT 1;

    IF v_uid IS NULL THEN
      INSERT INTO users (nm, ph, eml, role, sts, i_del, ts_crt)
      VALUES ('', v_identifier, '', 0, 0, 0, NOW())
      RETURNING id INTO v_uid;
      v_new := TRUE;
    END IF;
  ELSIF p_channel = 'email' THEN
    v_identifier := LOWER(TRIM(p_identifier));

    SELECT id INTO v_uid
    FROM users
    WHERE LOWER(COALESCE(eml, '')) = v_identifier
      AND i_del = 0
    LIMIT 1;

    IF v_uid IS NULL THEN
      INSERT INTO users (nm, ph, eml, role, sts, i_del, ts_crt)
      VALUES ('', '', v_identifier, 0, 0, 0, NOW())
      RETURNING id INTO v_uid;
      v_new := TRUE;
    END IF;
  END IF;

  RETURN QUERY SELECT v_uid, v_new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION upsert_user_after_otp(TEXT, TEXT) TO anon, authenticated;
