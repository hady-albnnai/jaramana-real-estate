-- ============================================================================
-- 🔔 إصلاح push notifications للتوثيق (Bug #13) — 2026-08-05
--
-- المشكلة: عند اعتماد/رفض التوثيق، يصل إشعار للمستخدم داخل التطبيق فقط،
--          لكن بدون push notification (لأن RPCs تستخدم INSERT INTO notifications
--          مباشرة بدلاً من notify_user الذي يرسل push).
--
-- الحل: تحديث RPCs لتستخدم notify_user بدلاً من INSERT المباشر.
--       هذا سيجعلها تحصل على push notifications تلقائياً (بعد migration
--       2026_07_30_notify_user_push.sql الذي أضاف send_push_notification
--       داخل notify_user).
--
-- الملفات المعدلة:
--   • admin_approve_verification_by_admin
--   • admin_reject_verification_by_admin
-- ============================================================================

-- ── A) admin_approve_verification_by_admin ─────────────────────────────────
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

  -- ✅ Fix for Bug #13: Use notify_user instead of INSERT INTO notifications
  -- This will automatically send push notification (after 2026_07_30_notify_user_push.sql)
  PERFORM notify_user(
    p_target_uid,
    4,  -- type: verification
    '✅ تم اعتماد توثيق حسابك',
    'تهانينا! حسابك أصبح موثقاً رسمياً.',
    '',  -- ref_id
    'verification'  -- action
  );
  
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── B) admin_reject_verification_by_admin ─────────────────────────────────
CREATE OR REPLACE FUNCTION admin_reject_verification_by_admin(
  p_admin_uid UUID,
  p_target_uid UUID,
  p_reason TEXT
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

  -- ✅ Fix for Bug #13: Use notify_user instead of INSERT INTO notifications
  -- This will automatically send push notification (after 2026_07_30_notify_user_push.sql)
  PERFORM notify_user(
    p_target_uid,
    4,  -- type: verification
    '❌ تم رفض طلب التوثيق',
    COALESCE(NULLIF(p_reason, ''), 'لم يتم قبول الوثائق المرفقة. يرجى المحاولة مرة أخرى.'),
    '',  -- ref_id
    'verification_rejected'  -- action
  );
  
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── C) تحصين RPCs ────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION admin_approve_verification_by_admin(UUID, UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION admin_approve_verification_by_admin(UUID, UUID) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_approve_verification_by_admin(UUID, UUID) TO service_role;

REVOKE ALL ON FUNCTION admin_reject_verification_by_admin(UUID, UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION admin_reject_verification_by_admin(UUID, UUID, TEXT) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_reject_verification_by_admin(UUID, UUID, TEXT) TO service_role;

-- ============================================================================
-- ✅ تحققات
-- ============================================================================

-- ① RPCs صارت تستخدم notify_user → المتوقع: true
SELECT position('notify_user' in pg_get_functiondef(p.oid)) > 0 AS uses_notify_user
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname IN ('admin_approve_verification_by_admin', 'admin_reject_verification_by_admin');

-- ② التحصين سليم → المتوقع: secdef=true · anon=false · service=true
SELECT p.proname,
       p.prosecdef AS secdef,
       has_function_privilege('anon',         p.oid, 'EXECUTE') AS anon_exec,
       has_function_privilege('service_role', p.oid, 'EXECUTE') AS svc_exec
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname IN ('admin_approve_verification_by_admin', 'admin_reject_verification_by_admin');
