-- ============================================
-- Migration: Payment Approval Logic (Automation)
-- Date: 2026-06-06
-- ============================================

CREATE OR REPLACE FUNCTION approve_payment_final(
  p_payment_id UUID,
  p_admin_id UUID
) RETURNS JSONB AS $$
DECLARE
  v_user_id UUID;
  v_pkg_id INT;
  v_pkg_duration INT;
  v_config JSONB;
BEGIN
  -- 1. جلب بيانات الدفعة
  SELECT uid, pkg INTO v_user_id, v_pkg_id 
  FROM payments 
  WHERE id = p_payment_id;

  IF v_user_id IS NULL THEN 
    RETURN jsonb_build_object('success', false, 'error', 'PAYMENT_NOT_FOUND'); 
  END IF;

  -- 2. جلب مدة الباقة من app_config/main (مفتاح pkg)
  SELECT value INTO v_config FROM app_config WHERE key = 'main';
  
  v_pkg_duration := (v_config->'pkg'->(v_pkg_id::text)->>'d')::INT;

  IF v_pkg_duration IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'PKG_DURATION_NOT_FOUND');
  END IF;

  -- 3. تنفيذ التحديثات في Transaction واحد
  UPDATE payments 
  SET sts = 1, appr_by = p_admin_id, ts_upd = NOW() 
  WHERE id = p_payment_id;

  UPDATE users 
  SET b_pkg = v_pkg_id, 
      pkg_end = NOW() + (v_pkg_duration || ' days')::interval,
      ts_upd = NOW()
  WHERE id = v_user_id;

  RETURN jsonb_build_object(
    'success', true, 
    'message', 'Package activated successfully',
    'duration', v_pkg_duration
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION approve_payment_final TO authenticated;
