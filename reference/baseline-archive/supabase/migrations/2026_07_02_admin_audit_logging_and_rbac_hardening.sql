-- =====================================================================
-- Migration: 2026_07_02_admin_audit_logging_and_rbac_hardening.sql
-- الغرض: توسيع التسجيل الآلي لتصرفات الإدارة في جدول activity_log عبر دالة موحدة
-- log_admin_action، وتطبيق التوصيات الإدارية: رفع صلاحية مراجعة العروض والتوثيق
-- إلى الرتبة 4 فما فوق، رفع مراجعة المدفوعات إلى الرتبة 5 فما فوق، وإلزامية سبب الرفض.
-- =====================================================================

-- 1. دالة موحدة لتسجيل حركات وتصرفات الموظفين الإداريين في activity_log
CREATE OR REPLACE FUNCTION public.log_admin_action(
  p_admin_uid UUID,
  p_act INT,
  p_det TEXT,
  p_ref_id TEXT DEFAULT '',
  p_ref_col TEXT DEFAULT ''
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, extensions, pg_temp
AS $$
BEGIN
  INSERT INTO public.activity_log (uid, act, det, ref_id, ref_col, ts_crt)
  VALUES (p_admin_uid, p_act, COALESCE(p_det, ''), COALESCE(p_ref_id, ''), COALESCE(p_ref_col, ''), NOW());
END;
$$;
REVOKE ALL ON FUNCTION public.log_admin_action(UUID, INT, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.log_admin_action(UUID, INT, TEXT, TEXT, TEXT) TO service_role;

-- 2. مراجعة العروض العقارية (تفرض الرتبة 4 فما فوق + إلزامية سبب الرفض + تسجيل الحركات)
CREATE OR REPLACE FUNCTION public.admin_review_offer_internal(
  p_admin_uid UUID, p_offer_id UUID, p_approve BOOLEAN, p_reject_reason TEXT DEFAULT NULL
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 4 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  IF p_approve THEN
    UPDATE offers SET sts = 2, i_pub = 1, ts_pub = NOW() WHERE id = p_offer_id AND i_del = 0;
    PERFORM public.log_admin_action(p_admin_uid, 101, 'اعتماد العرض العقاري ونشره للعموم', p_offer_id::TEXT, 'offers');
  ELSE
    IF COALESCE(trim(p_reject_reason), '') = '' THEN
      RAISE EXCEPTION 'REJECTION_REASON_REQUIRED';
    END IF;
    UPDATE offers SET sts = 3, rsn = trim(p_reject_reason), i_pub = 0 WHERE id = p_offer_id AND i_del = 0;
    PERFORM public.log_admin_action(p_admin_uid, 102, 'رفض العرض العقاري: ' || trim(p_reject_reason), p_offer_id::TEXT, 'offers');
  END IF;
  RETURN FOUND;
END; $$;
REVOKE ALL ON FUNCTION public.admin_review_offer_internal(UUID, UUID, BOOLEAN, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_review_offer_internal(UUID, UUID, BOOLEAN, TEXT) TO service_role;

-- 3. اعتماد توثيق هوية المستخدم (تفرض الرتبة 4 فما فوق + تسجيل الحركة)
CREATE OR REPLACE FUNCTION public.admin_approve_verification_by_admin(
  p_admin_uid UUID, p_target_uid UUID
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 4 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  UPDATE users SET vrf = 2, ts_upd = NOW() WHERE id = p_target_uid AND i_del = 0 AND vrf = 1;
  IF FOUND THEN
    INSERT INTO notifications (uid, tp, ttl, bdy, ts_crt)
    VALUES (p_target_uid, 10, 'تم اعتماد توثيقك', 'تهانينا! تم اعتماد حسابك رسمياً ✓', NOW());
    PERFORM public.log_admin_action(p_admin_uid, 103, 'اعتماد توثيق الهوية والحساب رسمياً', p_target_uid::TEXT, 'users');
  END IF;
  RETURN FOUND;
END; $$;
REVOKE ALL ON FUNCTION public.admin_approve_verification_by_admin(UUID, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_approve_verification_by_admin(UUID, UUID) TO service_role;

-- 4. رفض توثيق هوية المستخدم (تفرض الرتبة 4 فما فوق + إلزامية سبب الرفض + تسجيل الحركة)
CREATE OR REPLACE FUNCTION public.admin_reject_verification_by_admin(
  p_admin_uid UUID, p_target_uid UUID, p_reason TEXT DEFAULT ''
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 4 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  IF COALESCE(trim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'REJECTION_REASON_REQUIRED';
  END IF;
  UPDATE users SET vrf = 0, ts_upd = NOW() WHERE id = p_target_uid AND i_del = 0;
  IF FOUND THEN
    INSERT INTO notifications (uid, tp, ttl, bdy, ts_crt)
    VALUES (p_target_uid, 10, 'تم رفض طلب التوثيق', COALESCE(NULLIF(trim(p_reason),''), 'لم يتم قبول الوثائق المرفقة'), NOW());
    PERFORM public.log_admin_action(p_admin_uid, 104, 'رفض توثيق الهوية: ' || trim(p_reason), p_target_uid::TEXT, 'users');
  END IF;
  RETURN FOUND;
END; $$;
REVOKE ALL ON FUNCTION public.admin_reject_verification_by_admin(UUID, UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reject_verification_by_admin(UUID, UUID, TEXT) TO service_role;

-- 5. رفض إيصال التحويل البنكي (تفرض الرتبة 5 فما فوق مثل الاعتماد + تسجيل الحركة)
CREATE OR REPLACE FUNCTION public.admin_reject_payment_internal(
  p_admin_uid UUID, p_payment_id UUID
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 5 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  UPDATE payments SET sts = 2, appr_by = p_admin_uid WHERE id = p_payment_id AND sts = 0;
  IF FOUND THEN
    PERFORM public.log_admin_action(p_admin_uid, 106, 'رفض إيصال التحويل البنكي والدفعة', p_payment_id::TEXT, 'payments');
  END IF;
  RETURN FOUND;
END; $$;
REVOKE ALL ON FUNCTION public.admin_reject_payment_internal(UUID, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reject_payment_internal(UUID, UUID) TO service_role;
