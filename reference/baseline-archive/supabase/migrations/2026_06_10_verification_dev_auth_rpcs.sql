-- ════════════════════════════════════════════════════════════════════════════
-- Verification RPCs compatible with current dev auth model
-- Date: 2026-06-10
-- Purpose:
--   Keep verification workflow functional when auth.uid() is unavailable in the
--   current dev fallback, while still enforcing auth.uid() alignment whenever a
--   real Supabase Auth session exists.
-- ════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION request_verification_by_uid(p_user_uid UUID)
RETURNS BOOLEAN AS $$
DECLARE
  v_user RECORD;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT id, sid, img, vrf INTO v_user FROM users WHERE id = p_user_uid AND i_del = 0;
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;
  IF v_user.vrf = 2 THEN
    RAISE EXCEPTION 'ALREADY_VERIFIED';
  END IF;
  IF v_user.vrf = 1 THEN
    RAISE EXCEPTION 'ALREADY_PENDING';
  END IF;
  IF v_user.sid IS NULL OR LENGTH(TRIM(v_user.sid)) = 0
     OR v_user.img IS NULL OR LENGTH(TRIM(v_user.img)) = 0 THEN
    RAISE EXCEPTION 'MISSING_DOCUMENTS';
  END IF;

  UPDATE users SET vrf = 1, ts_upd = NOW() WHERE id = p_user_uid;
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION admin_approve_verification_by_admin(
  p_admin_uid UUID,
  p_target_uid UUID
)
RETURNS BOOLEAN AS $$
DECLARE
  v_admin_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT role INTO v_admin_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_admin_role IS NULL OR v_admin_role < 2 THEN
    RAISE EXCEPTION 'FORBIDDEN: Admin role required.';
  END IF;

  UPDATE users SET vrf = 2, ts_upd = NOW() WHERE id = p_target_uid AND i_del = 0;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;

  INSERT INTO notifications (uid, tp, ttl, bdy, act)
    VALUES (p_target_uid, 4, '✅ تم اعتماد توثيق حسابك',
            'تهانينا! حسابك أصبح موثقاً رسمياً.', 'verification');
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION admin_reject_verification_by_admin(
  p_admin_uid UUID,
  p_target_uid UUID,
  p_reason TEXT DEFAULT ''
)
RETURNS BOOLEAN AS $$
DECLARE
  v_admin_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT role INTO v_admin_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_admin_role IS NULL OR v_admin_role < 2 THEN
    RAISE EXCEPTION 'FORBIDDEN: Admin role required.';
  END IF;

  UPDATE users SET vrf = 0, ts_upd = NOW() WHERE id = p_target_uid AND i_del = 0;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;

  INSERT INTO notifications (uid, tp, ttl, bdy, act)
    VALUES (p_target_uid, 4, '🚫 رفض طلب التوثيق',
            CASE WHEN LENGTH(TRIM(p_reason)) > 0
                 THEN 'السبب: ' || p_reason
                 ELSE 'يرجى التأكد من وضوح صورة الهوية وإعادة المحاولة.'
            END, 'verification');
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION request_verification_by_uid(UUID) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION admin_approve_verification_by_admin(UUID, UUID) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION admin_reject_verification_by_admin(UUID, UUID, TEXT) TO authenticated, anon;
