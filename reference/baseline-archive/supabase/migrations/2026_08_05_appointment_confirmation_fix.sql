-- ============================================================================
-- 🔧 إصلاح إشعار تأكيد الموعد - إشعار واحد فقط (Bug #17)
-- ============================================================================
--
-- المشكلة: إشعارين يصلان عند تأكيد الموعد لصاحب الطلب
-- السبب: RPC owner_respond_appointment يرسل إشعارين:
--   1. "✅ تم قبول طلب موعدك" (قبول طلب الموعد) - غير مطلوب
--   2. "📅 موعد مؤكد" (تأكيد الموعد) - مطلوب
--
-- الحل: إزالة الإشعار الأول والإبقاء على الإشعار الثاني فقط
-- ============================================================================

DROP FUNCTION IF EXISTS public.owner_respond_appointment(UUID, UUID, BOOLEAN, INT, TEXT, TIMESTAMPTZ);

CREATE FUNCTION public.owner_respond_appointment(
  p_owner_uid UUID,
  p_appointment_id UUID,
  p_accept BOOLEAN,
  p_reject_reason INT DEFAULT 0,
  p_reject_text TEXT DEFAULT '',
  p_proposed_dt TIMESTAMPTZ DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, extensions, pg_temp
AS $$
DECLARE
  v_appt       public.appointments%ROWTYPE;
  v_rounds     INT;
  v_neog       JSONB;
  v_supervisor UUID;
  v_suggest    TIMESTAMPTZ;
  v_gap        INT := (public.appt_booking_config()->>'gap_mins')::INT;
  v_offer      public.offers%ROWTYPE;
  v_owner_name TEXT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_owner_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT * INTO v_appt
  FROM public.appointments
  WHERE id = p_appointment_id
    AND own_id = p_owner_uid
    AND sts = 0;

  IF v_appt.id IS NULL THEN
    RAISE EXCEPTION 'APPOINTMENT_NOT_FOUND_OR_NOT_ALLOWED';
  END IF;

  -- جلب معلومات العرض والمالك للإشعار المفصل
  SELECT * INTO v_offer FROM public.offers WHERE id = v_appt.off_id;
  SELECT nm INTO v_owner_name FROM public.users WHERE id = p_owner_uid;

  -- ─── موافقة ───
  IF p_accept THEN
    UPDATE public.appointments
    SET sts        = 1,
        fbk_own    = 1,
        fbk_own_dt = NOW()
    WHERE id = p_appointment_id;

    -- ✅ Fix for Bug #17: إرسال إشعار واحد فقط (تأكيد الموعد)
    -- إزالة إشعار "✅ تم قبول طلب موعدك" والإبقاء على "📅 موعد مؤكد" فقط
    PERFORM public.notify_user(
      v_appt.req_uid, 2,
      '📅 تم تأكيد موعدك',
      'وافق صاحب العرض على موعد المعاينة.' || E'\n\n'
      || 'العرض: ' || COALESCE(v_offer.ttl, 'عرض') || E'\n'
      || 'الموعد: ' || TO_CHAR(v_appt.dt AT TIME ZONE 'Asia/Damascus', 'YYYY/MM/DD HH24:MI') || E'\n'
      || 'الموقع: ' || COALESCE(v_offer.loc->>'city', v_offer.loc->>'d', 'غير محدد') || E'\n\n'
      || 'سيتواصل معك المكتب لتأكيد التفاصيل.',
      p_appointment_id::text, 'appointment_confirmed'
    );

    -- إشعار للإدارة (مشرف)
    PERFORM public.notify_user(
      (SELECT id FROM public.users WHERE role >= 2 AND sts = 0 AND i_del = 0
       ORDER BY ts_crt ASC LIMIT 1),
      2,
      '📅 موعد مؤكد - يحتاج مراجعة',
      'وافق صاحب العرض على موعد معاينة.' || E'\n\n'
      || 'العرض: ' || COALESCE(v_offer.ttl, 'عرض') || E'\n'
      || 'الموعد: ' || TO_CHAR(v_appt.dt AT TIME ZONE 'Asia/Damascus', 'YYYY/MM/DD HH24:MI') || E'\n'
      || 'صاحب العرض: ' || COALESCE(v_owner_name, 'غير معروف') || E'\n\n'
      || 'المشرف معيَّن تلقائياً.',
      p_appointment_id::text, 'appointment_confirmed_admin'
    );

    RETURN jsonb_build_object('success', true);
  END IF;

  -- ─── رفض ───
  v_neog   := COALESCE(v_appt.neog, '[]'::jsonb);
  v_rounds := jsonb_array_length(v_neog);

  -- p_reject_reason: 0=الوقت لا يناسب، 1=غير مهتم، 2=آخر

  -- رفض نهائي (غير مهتم أو آخر)
  IF p_reject_reason = 1 OR p_reject_reason = 2 THEN
    UPDATE public.appointments
    SET sts     = 4,
        cnl_rsn = COALESCE(NULLIF(p_reject_text,''), CASE p_reject_reason WHEN 1 THEN 'لم يعد مهتماً' ELSE 'سبب آخر' END),
        dt_end  = NOW()
    WHERE id = p_appointment_id;

    IF p_reject_reason = 1 THEN
      UPDATE public.offers SET i_del = 1 WHERE id = v_appt.off_id AND usr_id = p_owner_uid;
    END IF;

    PERFORM public.notify_user(
      v_appt.req_uid, 2,
      '❌ تم رفض طلب موعدك',
      CASE p_reject_reason
        WHEN 1 THEN 'أفاد صاحب العرض بأنه لم يعد مهتماً بالبيع/الإيجار.'
        ELSE 'تم رفض طلب موعدك. السبب: ' || COALESCE(NULLIF(p_reject_text,''), 'غير محدد')
      END,
      p_appointment_id::text, 'appointment'
    );
    PERFORM public.notify_user(
      (SELECT id FROM public.users WHERE role >= 2 AND sts = 0 AND i_del = 0
       ORDER BY ts_crt ASC LIMIT 1),
      2,
      '⚠️ رفض موعد' || CASE p_reject_reason WHEN 1 THEN ' — العرض أُزيل' ELSE '' END,
      'رفض صاحب العرض الموعد. السبب: ' || CASE p_reject_reason WHEN 1 THEN 'غير مهتم — تم حذف العرض تلقائياً' ELSE COALESCE(NULLIF(p_reject_text,''), 'آخر') END,
      p_appointment_id::text, 'appointment'
    );
    RETURN jsonb_build_object('success', true);
  END IF;

  -- ─── رفض بسبب الوقت — اقتراح بديل (تراشق) ───
  IF p_reject_reason = 0 THEN
    IF p_proposed_dt IS NULL THEN
      RAISE EXCEPTION 'PROPOSED_DT_REQUIRED';
    END IF;

    IF p_proposed_dt <= NOW() THEN
      RAISE EXCEPTION 'INVALID_APPOINTMENT_TIME';
    END IF;

    -- فحص قاعدة الساعة (مع استثناء الموعد الجاري تعديله نفسه)
    IF EXISTS (
      SELECT 1 FROM public.appointments
      WHERE off_id = v_appt.off_id
        AND id <> p_appointment_id
        AND sts IN (0, 1)
        AND ABS(EXTRACT(EPOCH FROM (dt - p_proposed_dt)) / 60) < v_gap
    ) THEN
      RAISE EXCEPTION 'TIME_CONFLICT_ON_OFFER';
    END IF;

    -- فحص توفر مشرف ضمن فارق الساعة
    v_supervisor := public.get_available_supervisor(p_proposed_dt);
    IF v_supervisor IS NULL THEN
      v_suggest := public.suggest_appointment_slot(v_appt.off_id, p_proposed_dt);
      -- إشعار للمقترِح بالبديل
      PERFORM public.notify_user(
        p_owner_uid, 2,
        '🔄 لا مشرف متاح للوقت المقترح',
        'لا يتوفر مشرف للوقت الذي اقترحته. أقرب وقت متاح: '
        || COALESCE(TO_CHAR(v_suggest AT TIME ZONE 'Asia/Damascus', 'YYYY/MM/DD HH24:MI'), 'غير متوفر خلال 14 يوم'),
        p_appointment_id::text, 'appointment'
      );
      RETURN jsonb_build_object(
        'success', false,
        'error', 'NO_SUPERVISOR_AVAILABLE',
        'suggested_dt', v_suggest
      );
    END IF;

    -- ─── نجاح اقتراح البديل ───
    v_neog := v_neog || jsonb_build_object(
      'by', 'owner',
      'dt', p_proposed_dt,
      'at', NOW()
    );

    UPDATE public.appointments
    SET neog         = v_neog,
        supervisor_uid = v_supervisor
    WHERE id = p_appointment_id;

    PERFORM public.notify_user(
      v_appt.req_uid, 2,
      '🔄 اقتراح وقت بديل',
      'اقترح صاحب العرض وقتاً بديلاً للموعد: '
      || TO_CHAR(p_proposed_dt AT TIME ZONE 'Asia/Damascus', 'YYYY/MM/DD HH24:MI')
      || '. يرجى الموافقة أو اقتراح وقت آخر.',
      p_appointment_id::text, 'appointment'
    );

    RETURN jsonb_build_object('success', true);
  END IF;

  RAISE EXCEPTION 'INVALID_REJECT_REASON';
END;
$$;

-- تحصين الـ RPC
REVOKE ALL ON FUNCTION public.owner_respond_appointment(UUID, UUID, BOOLEAN, INT, TEXT, TIMESTAMPTZ) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.owner_respond_appointment(UUID, UUID, BOOLEAN, INT, TEXT, TIMESTAMPTZ) FROM anon;
REVOKE ALL ON FUNCTION public.owner_respond_appointment(UUID, UUID, BOOLEAN, INT, TEXT, TIMESTAMPTZ) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.owner_respond_appointment(UUID, UUID, BOOLEAN, INT, TEXT, TIMESTAMPTZ) TO service_role;
