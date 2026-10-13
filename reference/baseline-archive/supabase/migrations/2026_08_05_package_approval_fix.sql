-- ============================================================================
-- 🔧 إصلاح تحديث الحالة بعد الموافقة على الباقة (Bug #37)
-- ============================================================================
--
-- المشكلة: الحالة لا تتحدث بعد الموافقة على الباقة
-- السبب: approve_payment_final يحدث b_pkg و pkg_end فقط، وليس pkg
--
-- الحل: إضافة تحديث pkg أيضاً + إرسال إشعار للمستخدم
-- ============================================================================

DROP FUNCTION IF EXISTS approve_payment_final(UUID, UUID);

CREATE OR REPLACE FUNCTION approve_payment_final(
  p_payment_id UUID,
  p_admin_id UUID
) RETURNS JSONB 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path TO public, extensions, pg_temp
AS $$
DECLARE
  v_user_id UUID;
  v_pkg_id INT;
  v_pkg_duration INT;
  v_config JSONB;
  v_admin_role INT;
  v_payment_status INT;
  v_payment_type INT;
  v_user_name TEXT;
  v_pkg_name TEXT;
BEGIN
  -- التحقق من الهوية
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_UID_MISMATCH');
  END IF;

  -- التحقق من صلاحيات الإداري
  SELECT role INTO v_admin_role
  FROM users
  WHERE id = p_admin_id
    AND i_del = 0;

  IF v_admin_role IS NULL OR v_admin_role < 2 THEN
    RETURN jsonb_build_object('success', false, 'error', 'FORBIDDEN');
  END IF;

  -- جلب بيانات الدفعة
  SELECT uid, pkg, sts, tp
    INTO v_user_id, v_pkg_id, v_payment_status, v_payment_type
  FROM payments
  WHERE id = p_payment_id;

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'PAYMENT_NOT_FOUND');
  END IF;

  IF COALESCE(v_payment_status, -1) <> 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'PAYMENT_NOT_PENDING');
  END IF;

  IF COALESCE(v_payment_type, -1) <> 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNSUPPORTED_PAYMENT_TYPE');
  END IF;

  -- جلب مدة الباقة من app_config
  SELECT value INTO v_config FROM app_config WHERE key = 'main';
  v_pkg_duration := (v_config->'pkg'->(v_pkg_id::text)->>'d')::INT;

  IF v_pkg_duration IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'PKG_DURATION_NOT_FOUND');
  END IF;

  -- جلب اسم المستخدم واسم الباقة
  SELECT nm INTO v_user_name FROM users WHERE id = v_user_id;
  
  v_pkg_name := CASE v_pkg_id
    WHEN 1 THEN 'الفضية'
    WHEN 2 THEN 'الذهبية'
    ELSE 'المجانية'
  END;

  -- تحديث الدفعة
  UPDATE payments
  SET sts = 1,  -- مقبولة
      appr_by = p_admin_id,
      ts_upd = NOW()
  WHERE id = p_payment_id
    AND sts = 0;

  -- ✅ Bug #37: تحديث pkg أيضاً (ليس فقط b_pkg و pkg_end)
  UPDATE users
  SET pkg = v_pkg_id,  -- ✅ إضافة تحديث pkg
      b_pkg = v_pkg_id,
      pkg_end = GREATEST(COALESCE(pkg_end, NOW()), NOW()) + (v_pkg_duration || ' days')::interval,
      ts_upd = NOW()
  WHERE id = v_user_id;

  -- ✅ إرسال إشعار للمستخدم
  PERFORM notify_user(
    v_user_id,
    3,  -- type: payment
    '✅ تم تفعيل باقتك',
    'تهانينا يا ' || COALESCE(v_user_name, '') || '! تم تفعيل باقة ' || v_pkg_name || ' بنجاح.' || E'\n\n'
    || 'مدة الباقة: ' || v_pkg_duration || ' يوم' || E'\n'
    || 'تاريخ الانتهاء: ' || TO_CHAR(NOW() + (v_pkg_duration || ' days')::interval, 'YYYY/MM/DD') || E'\n\n'
    || 'يمكنك الآن الاستمتاع بجميع مميزات الباقة.',
    p_payment_id::text,  -- ref_id
    'package_activated'  -- action
  );

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Package activated successfully',
    'duration', v_pkg_duration,
    'package_name', v_pkg_name
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- تحصين الـ RPC
REVOKE ALL ON FUNCTION approve_payment_final(UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION approve_payment_final(UUID, UUID) FROM anon;
REVOKE ALL ON FUNCTION approve_payment_final(UUID, UUID) FROM authenticated;
GRANT EXECUTE ON FUNCTION approve_payment_final(UUID, UUID) TO service_role;
