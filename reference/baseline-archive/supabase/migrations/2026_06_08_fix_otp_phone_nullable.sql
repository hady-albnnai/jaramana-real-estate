-- ════════════════════════════════════════════════════════════════════════════
-- Fix: تصحيح schema otp_codes — العمود phone يجب أن يكون nullable
-- Date: 2026-06-08
-- المشكلة: generate_otp_v2 يكتب في identifier فقط، لكن phone مازال NOT NULL
-- النتيجة: 23502 null value in column "phone" violates not-null constraint
-- ════════════════════════════════════════════════════════════════════════════

-- 1) إزالة قيد NOT NULL عن phone (للتوافق مع v2 الذي يستخدم identifier)
ALTER TABLE otp_codes ALTER COLUMN phone DROP NOT NULL;

-- 2) ضمان أن identifier موجود ومُفهرس
ALTER TABLE otp_codes ADD COLUMN IF NOT EXISTS identifier TEXT;
ALTER TABLE otp_codes ADD COLUMN IF NOT EXISTS channel TEXT DEFAULT 'sms';

-- 3) لكل صف قديم (إن وُجد): نسخ phone إلى identifier إذا كان فاضي
UPDATE otp_codes
   SET identifier = phone
 WHERE identifier IS NULL AND phone IS NOT NULL;

-- 4) فهرس + قيد: identifier لا يجب أن يكون فارغاً (مع phone كاحتياط)
-- نضيف CHECK يضمن أن أحدهما على الأقل موجود
ALTER TABLE otp_codes DROP CONSTRAINT IF EXISTS otp_phone_or_identifier;
ALTER TABLE otp_codes ADD CONSTRAINT otp_phone_or_identifier
  CHECK (phone IS NOT NULL OR identifier IS NOT NULL);

-- 5) تحديث verify_otp_v2 لو كان لا يدعم identifier (للأمان)
CREATE OR REPLACE FUNCTION verify_otp_v2(p_identifier TEXT, p_code TEXT)
RETURNS BOOLEAN AS $$
DECLARE v_found BOOLEAN;
BEGIN
  SELECT EXISTS(
    SELECT 1 FROM otp_codes
    WHERE (identifier = p_identifier OR phone = p_identifier)
      AND code = p_code
      AND used = 0
      AND expires_at > NOW()
  ) INTO v_found;

  IF v_found THEN
    UPDATE otp_codes SET used = 1
      WHERE (identifier = p_identifier OR phone = p_identifier)
        AND code = p_code
        AND used = 0;
    DELETE FROM otp_codes
      WHERE (identifier = p_identifier OR phone = p_identifier)
        AND used = 1;
    RETURN TRUE;
  END IF;
  RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION verify_otp_v2 TO anon, authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- بعد التشغيل: السطر السابق
--   SELECT generate_otp_v2('+963999999999', 'whatsapp');
-- يجب أن يُرجع كوداً من 6 أرقام بدون خطأ.
-- ════════════════════════════════════════════════════════════════════════════
