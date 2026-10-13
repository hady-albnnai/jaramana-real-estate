-- ============================================================================
-- 🔧 إصلاح الاشتراك بنفس الباقة - منع التكرار (Bug #36)
-- ============================================================================
--
-- المشكلة: يمكن طلب الاشتراك بنفس الباقة عدة مرات
-- السبب: create_payment_internal لا يتحقق من وجود دفعة معلقة لنفس الباقة
--
-- الحل: إضافة التحقق من وجود دفعة معلقة أو مقبولة لنفس الباقة
-- ============================================================================

DROP FUNCTION IF EXISTS create_payment_internal(UUID, JSONB);

CREATE OR REPLACE FUNCTION create_payment_internal(
  p_user_uid UUID,
  p_payment JSONB
)
RETURNS SETOF payments 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path TO public, extensions, pg_temp
AS $$
DECLARE
  v_user users%ROWTYPE;
  v_pkg INT;
  v_existing_payment payments%ROWTYPE;
  v_active_package BOOLEAN;
BEGIN
  -- التحقق من الهوية
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  -- التحقق من أن المستخدم نشط
  SELECT * INTO v_user FROM users WHERE id = p_user_uid AND i_del = 0 AND sts = 0;
  IF v_user.id IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_ACTIVE_OR_NOT_FOUND';
  END IF;

  -- التحقق من وجود proof و ref
  IF COALESCE(trim(p_payment->>'proof'), '') = '' OR COALESCE(trim(p_payment->>'ref'), '') = '' THEN
    RAISE EXCEPTION 'MISSING_PAYMENT_PROOF_OR_REFERENCE';
  END IF;

  -- ✅ Bug #36: التحقق من عدم وجود دفعة معلقة لنفس الباقة
  v_pkg := COALESCE((p_payment->>'pkg')::INT, 0);
  
  IF v_pkg > 0 THEN  -- فقط للباقات المدفوعة (ليس للباقة المجانية)
    -- التحقق من وجود دفعة معلقة (sts = 0) لنفس الباقة
    SELECT * INTO v_existing_payment 
    FROM payments 
    WHERE uid = p_user_uid 
      AND pkg = v_pkg 
      AND sts = 0  -- معلقة
      AND i_del = 0
    LIMIT 1;
    
    IF v_existing_payment.id IS NOT NULL THEN
      RAISE EXCEPTION 'PENDING_PAYMENT_EXISTS: لديك دفعة معلقة لنفس الباقة. يرجى انتظار الموافقة عليها أولاً.';
    END IF;
    
    -- ✅ التحقق من أن المستخدم لا يملك بالفعل الباقة المطلوبة (نشطة)
    -- الباقة نشطة إذا كان pkg_end > NOW()
    SELECT EXISTS (
      SELECT 1 FROM users 
      WHERE id = p_user_uid 
        AND pkg = v_pkg 
        AND pkg_end > NOW()
    ) INTO v_active_package;
    
    IF v_active_package THEN
      RAISE EXCEPTION 'ACTIVE_PACKAGE_EXISTS: لديك بالفعل الباقة المطلوبة وهي نشطة. يرجى انتظار انتهاء الباقة الحالية قبل التجديد.';
    END IF;
  END IF;

  -- إنشاء الدفعة
  RETURN QUERY
  INSERT INTO payments (
    uid, tp, pkg, amt, cur, mtd, channel, proof, ref, sts, appr_by, ts_crt
  ) VALUES (
    p_user_uid,
    COALESCE((p_payment->>'tp')::INT, 0),
    v_pkg,
    COALESCE((p_payment->>'amt')::NUMERIC, 0),
    COALESCE((p_payment->>'cur')::INT, 1),
    COALESCE((p_payment->>'mtd')::INT, 0),
    COALESCE(p_payment->>'channel', ''),
    COALESCE(p_payment->>'proof', ''),
    COALESCE(p_payment->>'ref', ''),
    0,  -- معلقة
    NULL,
    NOW()
  ) RETURNING *;
END;
$$;

-- تحصين الـ RPC
REVOKE ALL ON FUNCTION create_payment_internal(UUID, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION create_payment_internal(UUID, JSONB) FROM anon;
REVOKE ALL ON FUNCTION create_payment_internal(UUID, JSONB) FROM authenticated;
GRANT EXECUTE ON FUNCTION create_payment_internal(UUID, JSONB) TO service_role;
