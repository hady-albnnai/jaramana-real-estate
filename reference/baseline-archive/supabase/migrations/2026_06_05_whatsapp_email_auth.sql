-- ════════════════════════════════════════════════════════════════════════════
-- Migration: WhatsApp OTP + Email Magic Link Authentication
-- Date: 2026-06-05
-- ════════════════════════════════════════════════════════════════════════════
-- يضيف:
--   1. عمود `eml` (email) في جدول users
--   2. توسعة `otp_codes` لدعم channel (whatsapp/email/sms) و identifier موحّد
--   3. RPC جديدة: generate_otp_v2, verify_otp_v2
--   4. RPC مساعدة: get_user_by_email
-- ════════════════════════════════════════════════════════════════════════════

-- 1) عمود البريد الإلكتروني في users (اختياري، فريد لو موجود)
ALTER TABLE users ADD COLUMN IF NOT EXISTS eml TEXT DEFAULT '';
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_eml_unique
  ON users(eml) WHERE eml IS NOT NULL AND eml <> '' AND i_del = 0;

-- 2) توسعة otp_codes (نسخة موحّدة)
-- نضيف عمود channel (whatsapp/email/sms) و identifier (هاتف أو إيميل)
-- نُبقي phone للتوافق مع الكود القديم
ALTER TABLE otp_codes ADD COLUMN IF NOT EXISTS channel TEXT DEFAULT 'sms'
  CHECK (channel IN ('sms','whatsapp','email'));
ALTER TABLE otp_codes ADD COLUMN IF NOT EXISTS identifier TEXT;

-- backfill: identifier = phone للسجلات القديمة
UPDATE otp_codes SET identifier = phone WHERE identifier IS NULL;

CREATE INDEX IF NOT EXISTS idx_otp_identifier
  ON otp_codes(identifier, channel, used, expires_at);

-- ════════════════════════════════════════════════════════════════════════════
-- 3) RPC: generate_otp_v2
--    - identifier: رقم الهاتف (+963...) أو الإيميل
--    - channel: 'whatsapp' أو 'email' أو 'sms'
--    - يعيد الكود (الـ Edge Function هي اللي بترسله)
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION generate_otp_v2(
  p_identifier TEXT,
  p_channel TEXT DEFAULT 'whatsapp'
)
RETURNS TEXT AS $$
DECLARE v_code TEXT;
BEGIN
  -- منع spam: بحدّ أقصى 3 طلبات بآخر 10 دقائق لنفس identifier
  IF (SELECT COUNT(*) FROM otp_codes
      WHERE identifier = p_identifier
        AND ts_crt > NOW() - INTERVAL '10 minutes') >= 5 THEN
    RAISE EXCEPTION 'Too many OTP requests. Please wait a few minutes.';
  END IF;

  v_code := LPAD(FLOOR(RANDOM() * 900000 + 100000)::TEXT, 6, '0');

  INSERT INTO otp_codes (phone, identifier, channel, code, expires_at)
  VALUES (p_identifier, p_identifier, p_channel, v_code, NOW() + INTERVAL '5 minutes');

  RETURN v_code;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ════════════════════════════════════════════════════════════════════════════
-- 4) RPC: verify_otp_v2
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION verify_otp_v2(
  p_identifier TEXT,
  p_code TEXT
)
RETURNS BOOLEAN AS $$
DECLARE v_found BOOLEAN;
BEGIN
  SELECT EXISTS(
    SELECT 1 FROM otp_codes
    WHERE identifier = p_identifier
      AND code = p_code
      AND used = 0
      AND expires_at > NOW()
  ) INTO v_found;

  IF v_found THEN
    UPDATE otp_codes SET used = 1
    WHERE identifier = p_identifier AND code = p_code AND used = 0;
    -- تنظيف القديم
    DELETE FROM otp_codes WHERE identifier = p_identifier AND used = 1
      AND ts_crt < NOW() - INTERVAL '1 day';
    RETURN TRUE;
  END IF;

  RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ════════════════════════════════════════════════════════════════════════════
-- 5) RPC: get_user_by_email
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION get_user_by_email(p_email TEXT)
RETURNS SETOF users AS $$
BEGIN
  RETURN QUERY SELECT * FROM users WHERE eml = p_email AND i_del = 0;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ════════════════════════════════════════════════════════════════════════════
-- 6) RPC: upsert_user_after_otp
--    يستخدم بعد التحقق من WhatsApp OTP لإنشاء/جلب user بدون auth.users
--    (لأن OTP عبر واتساب لا يمرّ بـ Supabase Auth)
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION upsert_user_after_otp(
  p_identifier TEXT,
  p_channel TEXT
)
RETURNS TABLE(user_id UUID, is_new BOOLEAN) AS $$
DECLARE
  v_uid UUID;
  v_new BOOLEAN := FALSE;
BEGIN
  IF p_channel = 'whatsapp' OR p_channel = 'sms' THEN
    SELECT id INTO v_uid FROM users WHERE ph = p_identifier AND i_del = 0 LIMIT 1;
    IF v_uid IS NULL THEN
      INSERT INTO users (nm, ph, eml, role, sts, i_del, ts_crt)
      VALUES ('', p_identifier, '', 0, 0, 0, NOW())
      RETURNING id INTO v_uid;
      v_new := TRUE;
    END IF;
  ELSIF p_channel = 'email' THEN
    SELECT id INTO v_uid FROM users WHERE eml = p_identifier AND i_del = 0 LIMIT 1;
    IF v_uid IS NULL THEN
      INSERT INTO users (nm, ph, eml, role, sts, i_del, ts_crt)
      VALUES ('', '', p_identifier, 0, 0, 0, NOW())
      RETURNING id INTO v_uid;
      v_new := TRUE;
    END IF;
  END IF;

  RETURN QUERY SELECT v_uid, v_new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ════════════════════════════════════════════════════════════════════════════
-- 7) RLS: السماح بالاستدعاء من الـ Edge Function (anon role)
-- ════════════════════════════════════════════════════════════════════════════
GRANT EXECUTE ON FUNCTION generate_otp_v2 TO anon, authenticated;
GRANT EXECUTE ON FUNCTION verify_otp_v2 TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_user_by_email TO anon, authenticated;
GRANT EXECUTE ON FUNCTION upsert_user_after_otp TO anon, authenticated;
