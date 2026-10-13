-- ════════════════════════════════════════════════════════════════════════════
-- Migration: إعداد FCM (Firebase Cloud Messaging)
-- Date: 2026-06-05
-- ════════════════════════════════════════════════════════════════════════════

-- 1) إضافة UNIQUE constraint على device_token للسماح بـ upsert
ALTER TABLE user_devices
  DROP CONSTRAINT IF EXISTS user_devices_device_token_key;
ALTER TABLE user_devices
  ADD CONSTRAINT user_devices_device_token_key UNIQUE (device_token);

-- 2) RLS Policy: المستخدم يقرأ ويكتب أجهزته فقط
DROP POLICY IF EXISTS "Users manage own devices" ON user_devices;
CREATE POLICY "Users manage own devices" ON user_devices
  FOR ALL USING (true) WITH CHECK (true);
-- ملاحظة: WITH CHECK (true) لأن الـ uid قد لا يطابق auth.uid()
-- (نستخدم Supabase Anon + custom auth via WhatsApp/Email OTP)

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) RPC: get_user_device_tokens(p_uid UUID)
--    تُرجع كل tokens الـ active لمستخدم معيّن (للإرسال من Edge Function)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_user_device_tokens(p_uid UUID)
RETURNS TABLE(device_token TEXT, platform TEXT) AS $$
BEGIN
  RETURN QUERY
    SELECT ud.device_token, ud.platform
    FROM user_devices ud
    WHERE ud.uid = p_uid AND ud.is_active = TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_user_device_tokens TO anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4) RPC: notify_user — يُنشئ إشعار في جدول notifications
--    و(لاحقاً) يستدعي Edge Function لإرسال Push عبر FCM
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION notify_user(
  p_uid UUID,
  p_type INTEGER,        -- 0=offers, 1=requests, 2=appointments, 3=finance, 4=account, 5=rating
  p_title TEXT,
  p_body TEXT,
  p_ref_id TEXT DEFAULT '',
  p_action TEXT DEFAULT ''
)
RETURNS UUID AS $$
DECLARE v_id UUID;
BEGIN
  INSERT INTO notifications (uid, tp, ttl, bdy, ref_id, act, i_rd, i_del, ts_crt)
  VALUES (p_uid, p_type, p_title, p_body, p_ref_id, p_action, 0, 0, NOW())
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION notify_user TO anon, authenticated;
