-- ============================================================================
-- 🔧 إصلاح زر إكمال الموعد - إضافة عمليات الإكمال (Bug #19)
-- ============================================================================
--
-- المشكلة: عند الضغط على "إكمال" من حساب الإدارة، لا يتم نقل العملية
--          إلى تبويب مكتمل في إدارة المواعيد
-- السبب: RPC admin_update_appointment_status_internal يقوم فقط بتحديث الحالة
--        دون تنفيذ عمليات الإكمال (إنشاء صفقة، إرسال إشعارات، إلخ)
--
-- الحل: تحديث RPC ليقوم بعمليات الإكمال عند تعيين sts = 2
-- ============================================================================

DROP FUNCTION IF EXISTS admin_update_appointment_status_internal(UUID, UUID, INT, TEXT);

CREATE OR REPLACE FUNCTION admin_update_appointment_status_internal(
  p_admin_uid UUID, 
  p_appointment_id UUID, 
  p_status INT, 
  p_admin_note TEXT DEFAULT ''
) RETURNS BOOLEAN 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path TO public, extensions, pg_temp
AS $$
DECLARE 
  v_role INT;
  v_appt appointments%ROWTYPE;
  v_offer offers%ROWTYPE;
  v_deal_id UUID;
BEGIN
  -- التحقق من الصلاحيات
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN 
    RAISE EXCEPTION 'AUTH_MISMATCH'; 
  END IF;
  
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 3 THEN 
    RAISE EXCEPTION 'NOT_AUTHORIZED'; 
  END IF;

  -- جلب بيانات الموعد
  SELECT * INTO v_appt FROM appointments WHERE id = p_appointment_id;
  IF v_appt.id IS NULL THEN
    RAISE EXCEPTION 'APPOINTMENT_NOT_FOUND';
  END IF;

  -- جلب بيانات العرض
  SELECT * INTO v_offer FROM offers WHERE id = v_appt.off_id;

  -- تحديث الحالة
  UPDATE appointments 
  SET sts = p_status, 
      admin_nt = COALESCE(p_admin_note, ''),
      dt_end = CASE WHEN p_status = 2 THEN NOW() ELSE dt_end END
  WHERE id = p_appointment_id;

  -- ✅ عمليات الإكمال عند تعيين sts = 2
  IF p_status = 2 AND v_appt.sts <> 2 THEN
    -- إنشاء صفقة إذا لم تكن موجودة
    IF NOT EXISTS (SELECT 1 FROM deals WHERE appt_id = p_appointment_id) THEN
      INSERT INTO deals (
        off_id, appt_id, seller_uid, buyer_uid, broker_uid,
        prc, com, sts, ts_crt
      ) VALUES (
        v_appt.off_id,
        p_appointment_id,
        v_appt.own_id,
        v_appt.req_uid,
        v_appt.bkr_id,
        v_offer.prc,
        COALESCE(v_offer.com, 0),
        1, -- مكتمل
        NOW()
      ) RETURNING id INTO v_deal_id;

      -- إرسال إشعار للبائع
      PERFORM notify_user(
        v_appt.own_id,
        2,
        '🎉 تمت الصفقة بنجاح',
        'تم إكمال موعد المعاينة وإنشاء الصفقة. سيتم التواصل معك قريباً لإتمام الإجراءات.',
        v_deal_id::text,
        'deal_completed'
      );

      -- إرسال إشعار للمشتري
      PERFORM notify_user(
        v_appt.req_uid,
        2,
        '🎉 تمت الصفقة بنجاح',
        'تم إكمال موعد المعاينة وإنشاء الصفقة. سيتم التواصل معك قريباً لإتمام الإجراءات.',
        v_deal_id::text,
        'deal_completed'
      );

      -- إرسال إشعار للوسيط (إذا موجود)
      IF v_appt.bkr_id IS NOT NULL THEN
        PERFORM notify_user(
          v_appt.bkr_id,
          2,
          '🎉 صفقة جديدة',
          'تم إتمام صفقة على أحد عروضك. راجع التفاصيل في لوحة الوسيط.',
          v_deal_id::text,
          'deal_completed'
        );
      END IF;

      -- إرسال إشعار للإدارة
      PERFORM notify_user(
        p_admin_uid,
        2,
        '✅ تم إكمال موعد وإنشاء صفقة',
        'تم إكمال الموعد بنجاح وإنشاء الصفقة المرتبطة.',
        v_deal_id::text,
        'appointment_completed'
      );
    END IF;

    -- تحديث حالة الطلب المرتبط (إذا موجود)
    IF v_appt.req_id IS NOT NULL THEN
      UPDATE requests 
      SET sts = 2, -- مكتمل
          ts_upd = NOW()
      WHERE id = v_appt.req_id AND sts <> 2;
    END IF;
  END IF;

  RETURN FOUND;
END;
$$;

-- تحصين الـ RPC
REVOKE ALL ON FUNCTION admin_update_appointment_status_internal(UUID, UUID, INT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION admin_update_appointment_status_internal(UUID, UUID, INT, TEXT) FROM anon;
REVOKE ALL ON FUNCTION admin_update_appointment_status_internal(UUID, UUID, INT, TEXT) FROM authenticated;
GRANT EXECUTE ON FUNCTION admin_update_appointment_status_internal(UUID, UUID, INT, TEXT) TO service_role;
