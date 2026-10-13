-- ════════════════════════════════════════════════════════════════════════════
-- Migration: تشديد أمان متقدم (Phase 9)
-- Date: 2026-06-07
-- المرجع: تقرير Phase 8 — الثغرات المتبقية
-- يعالج:
--   - OTP cryptographic (استبدال RANDOM بـpgcrypto)
--   - Device fingerprinting (كشف مزارع الإحالة)
--   - Storage policies لصور الهوية (ids_private bucket)
--   - فهرس فحص الاحتيال
-- ════════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) OTP بـcryptographic RNG (pgcrypto)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- نُعيد كتابة generate_otp + generate_otp_v2 لاستخدام gen_random_bytes
-- gen_random_bytes(3) = 24 bit = 16,777,216 احتمال (بدل random() المُتنبأ به)

CREATE OR REPLACE FUNCTION generate_otp(p_phone TEXT)
RETURNS TEXT AS $$
DECLARE
  v_code TEXT;
  v_int  BIGINT;
BEGIN
  -- نأخذ 3 بايت = 0 .. 16,777,215 ثم نطبّقها mod 900000 + 100000
  v_int := (get_byte(gen_random_bytes(3), 0) * 65536
          + get_byte(gen_random_bytes(3), 1) * 256
          + get_byte(gen_random_bytes(3), 2));
  v_code := LPAD(((v_int % 900000) + 100000)::TEXT, 6, '0');
  INSERT INTO otp_codes (phone, code, expires_at)
    VALUES (p_phone, v_code, NOW() + INTERVAL '5 minutes');
  RETURN v_code;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION generate_otp TO anon, authenticated;

-- نفس الشيء لـgenerate_otp_v2 إن وُجدت (نتركها متوافقة)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'generate_otp_v2') THEN
    EXECUTE $sql$
      CREATE OR REPLACE FUNCTION generate_otp_v2(
        p_identifier TEXT,
        p_channel TEXT DEFAULT 'whatsapp'
      )
      RETURNS TEXT AS $fn$
      DECLARE
        v_code TEXT;
        v_int  BIGINT;
        v_count INT;
      BEGIN
        SELECT COUNT(*) INTO v_count FROM otp_codes
          WHERE identifier = p_identifier
            AND ts_crt > NOW() - INTERVAL '10 minutes';
        IF v_count >= 5 THEN
          RAISE EXCEPTION 'Too many OTP requests. Please wait a few minutes.';
        END IF;
        v_int := (get_byte(gen_random_bytes(3), 0) * 65536
                + get_byte(gen_random_bytes(3), 1) * 256
                + get_byte(gen_random_bytes(3), 2));
        v_code := LPAD(((v_int % 900000) + 100000)::TEXT, 6, '0');
        INSERT INTO otp_codes (identifier, channel, code, expires_at)
          VALUES (p_identifier, p_channel, v_code, NOW() + INTERVAL '5 minutes');
        RETURN v_code;
      END;
      $fn$ LANGUAGE plpgsql SECURITY DEFINER;
    $sql$;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) Device Fingerprinting (كشف مزارع الإحالة + multi-account abuse)
-- ─────────────────────────────────────────────────────────────────────────────
-- نضيف device_id + last_ip + signup_ip في users
ALTER TABLE users ADD COLUMN IF NOT EXISTS device_id TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS signup_ip INET;
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_ip INET;
ALTER TABLE users ADD COLUMN IF NOT EXISTS device_history JSONB DEFAULT '[]'::jsonb;

CREATE INDEX IF NOT EXISTS idx_users_device_id ON users(device_id) WHERE device_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_signup_ip ON users(signup_ip) WHERE signup_ip IS NOT NULL;

-- جدول مساعد: حسابات نفس الجهاز
CREATE OR REPLACE FUNCTION accounts_on_same_device(p_device_id TEXT)
RETURNS TABLE (
  uid UUID, name TEXT, signup_at TIMESTAMPTZ, points INT
) AS $$
BEGIN
  RETURN QUERY
  SELECT id, nm, ts_crt, pt FROM users
    WHERE device_id = p_device_id AND i_del = 0
    ORDER BY ts_crt;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION accounts_on_same_device TO authenticated;

-- تحديث apply_referral ليرفض إذا كان المُحال + المحيل من نفس الجهاز/IP
CREATE OR REPLACE FUNCTION apply_referral(
  p_new_uid UUID,
  p_referrer_code TEXT,
  p_pts INT DEFAULT 1500
)
RETURNS BOOLEAN AS $$
DECLARE
  v_referrer_uid UUID;
  v_recent_refs INT;
  v_new_dev TEXT;
  v_ref_dev TEXT;
  v_new_ip INET;
  v_ref_ip INET;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_new_uid THEN
    RAISE EXCEPTION 'SECURITY: apply_referral can only be called by the new user.';
  END IF;

  SELECT id INTO v_referrer_uid FROM users
    WHERE REPLACE(id::text, '-', '') ILIKE p_referrer_code || '%'
      AND i_del = 0
    LIMIT 1;
  IF v_referrer_uid IS NULL OR v_referrer_uid = p_new_uid THEN
    RETURN FALSE;
  END IF;

  IF EXISTS(SELECT 1 FROM users WHERE id = p_new_uid AND ref_by IS NOT NULL) THEN
    RETURN FALSE;
  END IF;

  -- 🛡️ Phase 9: فحص نفس الجهاز/IP لمنع مزرعة الإحالة
  SELECT device_id, COALESCE(signup_ip, last_ip)
    INTO v_new_dev, v_new_ip FROM users WHERE id = p_new_uid;
  SELECT device_id, COALESCE(signup_ip, last_ip)
    INTO v_ref_dev, v_ref_ip FROM users WHERE id = v_referrer_uid;

  IF v_new_dev IS NOT NULL AND v_new_dev = v_ref_dev THEN
    RAISE EXCEPTION 'FRAUD_DETECTED: Same device.';
  END IF;
  IF v_new_ip IS NOT NULL AND v_new_ip = v_ref_ip THEN
    RAISE EXCEPTION 'FRAUD_DETECTED: Same IP.';
  END IF;

  -- Rate limit 5/h (كما في Phase 8)
  SELECT COUNT(*) INTO v_recent_refs FROM users
    WHERE ref_by = v_referrer_uid AND ts_crt > NOW() - INTERVAL '1 hour';
  IF v_recent_refs >= 5 THEN
    RAISE EXCEPTION 'RATE_LIMIT: Referrer reached 5 referrals/hour cap.';
  END IF;

  UPDATE users SET ref_by = v_referrer_uid WHERE id = p_new_uid;
  UPDATE users SET ref_cnt = COALESCE(ref_cnt, 0) + 1 WHERE id = v_referrer_uid;
  UPDATE users SET pt = pt + p_pts WHERE id IN (p_new_uid, v_referrer_uid);

  PERFORM update_user_badge(p_new_uid);
  PERFORM update_user_badge(v_referrer_uid);

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION apply_referral FROM anon;
GRANT EXECUTE ON FUNCTION apply_referral TO authenticated;

-- RPC للـclient لتسجيل/تحديث device_id (idempotent)
CREATE OR REPLACE FUNCTION register_device(
  p_device_id TEXT,
  p_ip_hint TEXT DEFAULT NULL
)
RETURNS BOOLEAN AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_current TEXT;
  v_history JSONB;
BEGIN
  IF v_uid IS NULL THEN
    RETURN FALSE;
  END IF;
  IF p_device_id IS NULL OR LENGTH(TRIM(p_device_id)) = 0 THEN
    RETURN FALSE;
  END IF;

  SELECT device_id, COALESCE(device_history, '[]'::jsonb)
    INTO v_current, v_history FROM users WHERE id = v_uid;

  -- أول مرة → سجّل signup_ip + signup_device
  IF v_current IS NULL THEN
    UPDATE users SET
      device_id = p_device_id,
      signup_ip = NULLIF(p_ip_hint, '')::INET,
      last_ip   = NULLIF(p_ip_hint, '')::INET,
      device_history = v_history || jsonb_build_object(
        'd', p_device_id, 't', NOW(), 'first', true)
    WHERE id = v_uid;
  ELSIF v_current <> p_device_id THEN
    -- جهاز جديد → نُضيفه للسجل لكن لا نغيّر device_id الأساسي تلقائياً
    UPDATE users SET
      last_ip = COALESCE(NULLIF(p_ip_hint, '')::INET, last_ip),
      device_history = v_history || jsonb_build_object(
        'd', p_device_id, 't', NOW())
    WHERE id = v_uid;
  ELSE
    -- نفس الجهاز → فقط حدّث الـIP
    UPDATE users SET
      last_ip = COALESCE(NULLIF(p_ip_hint, '')::INET, last_ip)
    WHERE id = v_uid;
  END IF;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION register_device TO authenticated;

-- نُحدّث check_user_safe_update ليسمح لـdevice fingerprint بالتحديث من المالك
-- (موجود مسبقاً في Phase 8، نضيف استثناء)
-- الحقول الجديدة (device_id/signup_ip/last_ip/device_history) لا تخضع لقاعدة المنع
-- لأنها غير مذكورة في trg_user_safe_update — جيد.

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) Storage policies لـbucket خاص بصور الهوية (CVE-4 extension)
-- ─────────────────────────────────────────────────────────────────────────────
-- نُنشئ bucket جديد ids_private (private)
INSERT INTO storage.buckets (id, name, public)
  VALUES ('ids_private', 'ids_private', false)
  ON CONFLICT (id) DO UPDATE SET public = false;

-- المالك يرفع/يقرأ فقط ملفاته (المسار = userId/...)
DROP POLICY IF EXISTS "ids_private_owner_insert" ON storage.objects;
CREATE POLICY "ids_private_owner_insert" ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'ids_private'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

DROP POLICY IF EXISTS "ids_private_owner_select" ON storage.objects;
CREATE POLICY "ids_private_owner_select" ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'ids_private'
    AND (
      -- المالك يقرأ صوره
      auth.uid()::text = (storage.foldername(name))[1]
      -- أو المشرفون (role >= 2)
      OR EXISTS (
        SELECT 1 FROM users
        WHERE id = auth.uid() AND role >= 2 AND i_del = 0
      )
    )
  );

DROP POLICY IF EXISTS "ids_private_owner_update" ON storage.objects;
CREATE POLICY "ids_private_owner_update" ON storage.objects
  FOR UPDATE
  USING (
    bucket_id = 'ids_private'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

DROP POLICY IF EXISTS "ids_private_owner_delete" ON storage.objects;
CREATE POLICY "ids_private_owner_delete" ON storage.objects
  FOR DELETE
  USING (
    bucket_id = 'ids_private'
    AND (
      auth.uid()::text = (storage.foldername(name))[1]
      OR EXISTS (
        SELECT 1 FROM users
        WHERE id = auth.uid() AND role >= 2 AND i_del = 0
      )
    )
  );

-- RPC للأدمن لجلب signed URL لصورة هوية (المسار آمن)
CREATE OR REPLACE FUNCTION admin_get_id_signed_path(p_target_uid UUID)
RETURNS TEXT AS $$
DECLARE
  v_admin_role INT;
  v_img TEXT;
BEGIN
  SELECT role INTO v_admin_role FROM users WHERE id = auth.uid();
  IF v_admin_role IS NULL OR v_admin_role < 2 THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;
  SELECT img INTO v_img FROM users WHERE id = p_target_uid;
  RETURN v_img;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION admin_get_id_signed_path TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4) فهرس لكشف الاحتيال (Admin Dashboard)
-- ─────────────────────────────────────────────────────────────────────────────
-- VIEW يعرض المستخدمين المشتبهين (نفس الجهاز/IP)
DROP VIEW IF EXISTS fraud_suspects CASCADE;
CREATE VIEW fraud_suspects AS
SELECT
  device_id,
  COUNT(*) AS account_count,
  ARRAY_AGG(id) AS user_ids,
  ARRAY_AGG(nm) AS names,
  MIN(ts_crt) AS first_signup,
  MAX(ts_crt) AS last_signup
FROM users
WHERE device_id IS NOT NULL AND i_del = 0
GROUP BY device_id
HAVING COUNT(*) > 1;

ALTER VIEW fraud_suspects SET (security_invoker = true);
GRANT SELECT ON fraud_suspects TO authenticated;

-- يمكن للأدمن فقط القراءة (نضع policy إضافية بـ RPC)
CREATE OR REPLACE FUNCTION admin_fraud_suspects()
RETURNS SETOF fraud_suspects AS $$
DECLARE v_role INT;
BEGIN
  SELECT role INTO v_role FROM users WHERE id = auth.uid();
  IF v_role IS NULL OR v_role < 2 THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;
  RETURN QUERY SELECT * FROM fraud_suspects ORDER BY account_count DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION admin_fraud_suspects TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- تعليقات
-- ─────────────────────────────────────────────────────────────────────────────
COMMENT ON FUNCTION generate_otp IS
  'Phase 9: OTP مع pgcrypto.gen_random_bytes (cryptographic RNG).';
COMMENT ON FUNCTION register_device IS
  'Phase 9: تسجيل device fingerprint للمستخدم (idempotent).';
COMMENT ON VIEW fraud_suspects IS
  'Phase 9: حسابات متعددة من نفس الجهاز (مشتبه بمزرعة إحالات).';
COMMENT ON FUNCTION admin_fraud_suspects IS
  'Phase 9: Wrapper آمن لـfraud_suspects (role>=2 only).';
COMMENT ON FUNCTION admin_get_id_signed_path IS
  'Phase 9: إرجاع مسار صورة الهوية للأدمن (للتحقق من التوثيق).';

-- ════════════════════════════════════════════════════════════════════════════
-- نهاية Phase 9 Advanced Hardening
-- ════════════════════════════════════════════════════════════════════════════
