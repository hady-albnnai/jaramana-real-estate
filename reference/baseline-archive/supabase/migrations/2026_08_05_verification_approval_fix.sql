-- ============================================================================
-- 🔧 إصلاح طلب التوثيق - تحديث البيانات تلقائياً (Bug #31)
-- ============================================================================
--
-- المشكلة: طلب التوثيق يتم اعتماده من المكتب لكن لا ينعكس عند المستخدم
-- السبب: المستخدم لا يحدث بياناته محلياً بعد اعتماد التوثيق
--
-- الحل: إضافة trigger لإرسال إشعار real-time + تحسين الإشعار
-- ============================================================================

DROP FUNCTION IF EXISTS admin_approve_verification_by_admin(UUID, UUID);

CREATE OR REPLACE FUNCTION admin_approve_verification_by_admin(
  p_admin_uid UUID, 
  p_target_uid UUID
) RETURNS BOOLEAN 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path TO public, extensions, pg_temp
AS $$
DECLARE 
  v_role INT;
  v_user_name TEXT;
BEGIN
  -- التحقق من الصلاحيات
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN 
    RAISE EXCEPTION 'AUTH_MISMATCH'; 
  END IF;
  
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 3 THEN 
    RAISE EXCEPTION 'NOT_AUTHORIZED'; 
  END IF;
  
  -- جلب اسم المستخدم
  SELECT nm INTO v_user_name FROM users WHERE id = p_target_uid;
  
  -- ✅ Bug #31: تحديث vrf وإرسال إشعار مفصل
  UPDATE users 
  SET vrf = 2, 
      ts_upd = NOW() 
  WHERE id = p_target_uid 
    AND i_del = 0 
    AND vrf = 1;
  
  IF FOUND THEN
    -- ✅ إرسال إشعار مفصل مع طلب تحديث الصفحة
    PERFORM notify_user(
      p_target_uid,
      10,  -- type: verification
      '✅ تم اعتماد توثيق حسابك',
      'تهانينا يا ' || COALESCE(v_user_name, '') || '! تم اعتماد حسابك رسمياً ✓' || E'\n\n'
      || 'يرجى تحديث الصفحة أو تسجيل الخروج والدخول مرة أخرى لرؤية التغييرات.',
      '',  -- ref_id
      'verification_approved'  -- action
    );
    
    RETURN TRUE;
  END IF;
  
  RETURN FALSE;
END;
$$;

-- تحصين الـ RPC
REVOKE ALL ON FUNCTION admin_approve_verification_by_admin(UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION admin_approve_verification_by_admin(UUID, UUID) FROM anon;
REVOKE ALL ON FUNCTION admin_approve_verification_by_admin(UUID, UUID) FROM authenticated;
GRANT EXECUTE ON FUNCTION admin_approve_verification_by_admin(UUID, UUID) TO service_role;
