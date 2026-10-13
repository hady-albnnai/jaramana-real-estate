-- ════════════════════════════════════════════════════════════════════════════
-- إصلاح شامل: حجز المواعيد + دورة حياة العرض + أدوار الدوال المتبقية
-- 2026-06-12
-- ════════════════════════════════════════════════════════════════════════════
-- يشمل:
--   1. إعادة كتابة book_appointment_internal (10 فحوصات)
--   2. تحديث process_completion_request (يغير offers.sts + يلغي مواعيد)
--   3. تحديث create_deal_internal (يحوّل العرض لمحجوز + role>=5)
--   4. تحديث complete_deal_internal (يحوّل العرض لمكتمل + يلغي مواعيد + role>=5)
--   5. تحديث admin_force_appointment_internal (role>=4)
--   6. تحديث admin_handle_report_internal (role>=4)
--   7. تحديث create_request_internal (إعفاء role>=4)
-- ════════════════════════════════════════════════════════════════════════════


-- ──────────────────────────────────────────────────────────────────────────
-- 1. book_appointment_internal — إعادة كتابة كاملة
-- ──────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS book_appointment_internal(UUID, UUID, TIMESTAMPTZ, UUID, UUID);

CREATE OR REPLACE FUNCTION book_appointment_internal(
  p_user_uid  UUID,
  p_offer_id  UUID,
  p_dt        TIMESTAMPTZ,
  p_broker_id UUID DEFAULT NULL,
  p_request_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_offer      offers%ROWTYPE;
  v_day_key    TEXT;
  v_time_str   TEXT;
  v_slot       TEXT;
  v_slot_from  INT;
  v_slot_to    INT;
  v_req_mins   INT;
  v_avl_slots  JSONB;
  v_found_slot BOOLEAN := FALSE;
  v_supervisor UUID;
  v_active_count INT;
  v_pending_completion INT;
BEGIN
  -- 0. فحص الهوية
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  -- 1. العرض موجود ومنشور
  SELECT * INTO v_offer FROM offers WHERE id = p_offer_id AND i_del = 0;
  IF v_offer.id IS NULL THEN
    RAISE EXCEPTION 'OFFER_NOT_FOUND';
  END IF;
  IF v_offer.sts NOT IN (2) THEN
    RAISE EXCEPTION 'OFFER_NOT_AVAILABLE';
  END IF;

  -- 2. ما يحجز عرضه الشخصي
  IF p_user_uid = v_offer.usr_id THEN
    RAISE EXCEPTION 'CANNOT_BOOK_OWN_OFFER';
  END IF;

  -- 3. الوقت بالمستقبل
  IF p_dt <= NOW() THEN
    RAISE EXCEPTION 'INVALID_APPOINTMENT_TIME';
  END IF;

  -- 4. فحص طلب إتمام معلق على هالعرض
  SELECT COUNT(*) INTO v_pending_completion
  FROM completion_requests cr
  JOIN appointments a ON a.id = cr.app_id
  WHERE a.off_id = p_offer_id
    AND cr.decision = 'pending';
  IF v_pending_completion > 0 THEN
    RAISE EXCEPTION 'OFFER_HAS_PENDING_COMPLETION';
  END IF;

  -- 5. فحص avl (المواعيد المتاحة لصاحب العرض)
  IF v_offer.avl IS NOT NULL AND v_offer.avl <> '{}'::jsonb AND v_offer.avl <> 'null'::jsonb THEN
    v_day_key := LOWER(to_char(p_dt AT TIME ZONE 'Asia/Damascus', 'Dy'));
    -- تحويل اسم اليوم من PostgreSQL إلى المفتاح المستخدم بالتطبيق
    v_day_key := CASE v_day_key
      WHEN 'mon' THEN 'mon' WHEN 'tue' THEN 'tue' WHEN 'wed' THEN 'wed'
      WHEN 'thu' THEN 'thu' WHEN 'fri' THEN 'fri' WHEN 'sat' THEN 'sat'
      WHEN 'sun' THEN 'sun' ELSE v_day_key
    END;

    v_avl_slots := v_offer.avl -> v_day_key;

    IF v_avl_slots IS NULL OR jsonb_array_length(v_avl_slots) = 0 THEN
      RAISE EXCEPTION 'DAY_NOT_AVAILABLE';
    END IF;

    -- فحص أن الوقت ضمن إحدى الفترات المتاحة
    v_req_mins := EXTRACT(HOUR FROM p_dt AT TIME ZONE 'Asia/Damascus')::INT * 60
                + EXTRACT(MINUTE FROM p_dt AT TIME ZONE 'Asia/Damascus')::INT;

    FOR v_slot IN SELECT jsonb_array_elements_text(v_avl_slots)
    LOOP
      -- الفترة بصيغة "HH:MM-HH:MM"
      v_slot_from := SPLIT_PART(SPLIT_PART(v_slot, '-', 1), ':', 1)::INT * 60
                   + SPLIT_PART(SPLIT_PART(v_slot, '-', 1), ':', 2)::INT;
      v_slot_to   := SPLIT_PART(SPLIT_PART(v_slot, '-', 2), ':', 1)::INT * 60
                   + SPLIT_PART(SPLIT_PART(v_slot, '-', 2), ':', 2)::INT;

      IF v_req_mins >= v_slot_from AND v_req_mins < v_slot_to THEN
        v_found_slot := TRUE;
        EXIT;
      END IF;
    END LOOP;

    IF NOT v_found_slot THEN
      RAISE EXCEPTION 'TIME_NOT_IN_AVAILABLE_SLOTS';
    END IF;
  END IF;

  -- 6. فحص تعارض العقار (ما في موعد مؤكد بنفس الوقت على نفس العرض)
  IF EXISTS (
    SELECT 1 FROM appointments
    WHERE off_id = p_offer_id
      AND dt = p_dt
      AND sts IN (0, 1)
  ) THEN
    RAISE EXCEPTION 'TIME_CONFLICT_ON_OFFER';
  END IF;

  -- 7. منع تكرار نفس المستخدم نفس الوقت
  IF EXISTS (
    SELECT 1 FROM appointments
    WHERE off_id = p_offer_id
      AND req_uid = p_user_uid
      AND sts IN (0, 1)
  ) THEN
    RAISE EXCEPTION 'DUPLICATE_APPOINTMENT';
  END IF;

  -- 8. اختيار منفذ متاح
  SELECT u.id INTO v_supervisor
  FROM users u
  WHERE u.role = 3
    AND u.sts = 0
    AND u.i_del = 0
    AND NOT EXISTS (
      SELECT 1 FROM appointments a
      WHERE a.supervisor_uid = u.id
        AND a.sts IN (0, 1)
        AND a.dt = p_dt
    )
  ORDER BY (
    SELECT COUNT(*) FROM appointments a2
    WHERE a2.supervisor_uid = u.id AND a2.sts IN (0, 1)
  ) ASC, u.ts_crt ASC
  LIMIT 1;

  IF v_supervisor IS NULL THEN
    RAISE EXCEPTION 'NO_SUPERVISOR_AVAILABLE';
  END IF;

  -- 9. إنشاء الموعد مع supervisor_uid
  INSERT INTO appointments (
    off_id, req_id, req_uid, own_id, bkr_id, dt, sts,
    supervisor_uid,
    fbk_own, fbk_req, i_force, rmnd_24, rmnd_2, rmnd_qtr, rmnd_end, ts_crt
  ) VALUES (
    p_offer_id,
    p_request_id,
    p_user_uid,
    v_offer.usr_id,
    COALESCE(p_broker_id, v_offer.brk_id),
    p_dt,
    0,
    v_supervisor,
    0, 0, 0, 0, 0, 0, 0,
    NOW()
  );

  -- 10. حساب عدد المواعيد النشطة على هالعرض
  SELECT COUNT(*) INTO v_active_count
  FROM appointments
  WHERE off_id = p_offer_id
    AND sts IN (0, 1);

  RETURN jsonb_build_object(
    'success', true,
    'active_appointments', v_active_count,
    'supervisor_uid', v_supervisor
  );
END;
$$;

GRANT EXECUTE ON FUNCTION book_appointment_internal(UUID, UUID, TIMESTAMPTZ, UUID, UUID) TO anon, authenticated;


-- ──────────────────────────────────────────────────────────────────────────
-- 2. process_completion_request — يغير offers.sts + يلغي مواعيد
-- ──────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS process_completion_request(UUID, UUID, TEXT, TEXT);

CREATE OR REPLACE FUNCTION process_completion_request(
  p_admin_uid    UUID,
  p_request_id   UUID,
  p_decision     TEXT,
  p_office_notes TEXT DEFAULT ''
) RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_role    INT;
  v_req     RECORD;
  v_off_id  UUID;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_MISMATCH';
  END IF;

  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 4 THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  SELECT * INTO v_req FROM completion_requests WHERE id = p_request_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND'; END IF;
  IF v_req.decision <> 'pending' THEN RAISE EXCEPTION 'REQUEST_ALREADY_PROCESSED'; END IF;

  -- تحديث طلب الإتمام
  UPDATE completion_requests
  SET decision = p_decision,
      decided_by = p_admin_uid,
      office_notes = COALESCE(p_office_notes, ''),
      ts_decided = NOW()
  WHERE id = p_request_id;

  -- جلب offer_id من الموعد
  SELECT off_id INTO v_off_id FROM appointments WHERE id = v_req.app_id;

  IF p_decision = 'approved' THEN
    -- تحديث الموعد المعتمد
    UPDATE appointments SET sts = 2 WHERE id = v_req.app_id AND sts <> 2;

    -- تحويل العرض إلى محجوز + إخفاء من القوائم
    UPDATE offers
    SET sts = 5, i_pub = 0
    WHERE id = v_off_id AND sts = 2;

    -- إلغاء كل المواعيد الأخرى على نفس العرض
    UPDATE appointments
    SET sts = 3,
        cnl_rsn = 'تم إتمام معاملة على هذا العرض',
        dt_end = NOW()
    WHERE off_id = v_off_id
      AND id <> v_req.app_id
      AND sts IN (0, 1);

    -- إشعار أصحاب المواعيد الملغاة
    INSERT INTO notifications (uid, typ, ttl, bdy, ref_id, ts_crt)
    SELECT req_uid, 0, 'تم إلغاء موعدك',
           'تم إلغاء موعدك لأن العرض اكتمل بمعاملة أخرى.',
           id, NOW()
    FROM appointments
    WHERE off_id = v_off_id
      AND id <> v_req.app_id
      AND sts = 3
      AND cnl_rsn = 'تم إتمام معاملة على هذا العرض';

  ELSIF p_decision = 'rejected' THEN
    UPDATE appointments
    SET sts = 4, outcome = 'reject'
    WHERE id = v_req.app_id;
  END IF;

  -- إشعار المنفذ بالنتيجة
  INSERT INTO notifications (uid, typ, ttl, bdy, ref_id, ts_crt)
  VALUES (
    v_req.req_by, 20,
    CASE WHEN p_decision = 'approved' THEN 'تمت الموافقة على طلب الإتمام'
         ELSE 'تم رفض طلب الإتمام' END,
    CASE WHEN p_decision = 'approved' THEN 'تمت الموافقة على طلب إتمام المعاملة ✓'
         ELSE 'تم رفض طلب الإتمام: ' || COALESCE(p_office_notes, '') END,
    v_req.app_id, NOW()
  );

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION process_completion_request(UUID, UUID, TEXT, TEXT) TO anon, authenticated;


-- ──────────────────────────────────────────────────────────────────────────
-- 3. create_deal_internal — role>=5 + يحوّل العرض لمحجوز
-- ──────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS create_deal_internal(UUID, JSONB);

CREATE OR REPLACE FUNCTION create_deal_internal(
  p_admin_uid UUID,
  p_deal JSONB
) RETURNS SETOF deals
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_role   INT;
  v_off_id UUID;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 5 THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  v_off_id := NULLIF(p_deal->>'off_id', '')::UUID;

  -- تحويل العرض إلى محجوز
  IF v_off_id IS NOT NULL THEN
    UPDATE offers SET sts = 5, i_pub = 0 WHERE id = v_off_id AND sts = 2;
  END IF;

  RETURN QUERY
  INSERT INTO deals (
    off_id, app_id, sell_uid, buy_uid, brk_uid, fin_prc, cur,
    com_pct, com_val, com_note, form, sts, cmpl_by, i_del, ts_crt, ts_cmpl
  ) VALUES (
    v_off_id,
    NULLIF(p_deal->>'app_id', '')::UUID,
    NULLIF(p_deal->>'sell_uid', '')::UUID,
    NULLIF(p_deal->>'buy_uid', '')::UUID,
    NULLIF(p_deal->>'brk_uid', '')::UUID,
    COALESCE((p_deal->>'fin_prc')::NUMERIC, 0),
    COALESCE((p_deal->>'cur')::INT, 1),
    COALESCE((p_deal->>'com_pct')::NUMERIC, 0),
    COALESCE((p_deal->>'com_val')::NUMERIC, 0),
    NULLIF(p_deal->>'com_note', ''),
    COALESCE(p_deal->'form', '{}'::jsonb),
    COALESCE((p_deal->>'sts')::INT, 0),
    NULL, 0, NOW(), NULL
  ) RETURNING *;
END;
$$;

GRANT EXECUTE ON FUNCTION create_deal_internal(UUID, JSONB) TO anon, authenticated;


-- ──────────────────────────────────────────────────────────────────────────
-- 4. complete_deal_internal — role>=5 + يحوّل العرض لمكتمل + يلغي مواعيد
-- ──────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS complete_deal_internal(UUID, UUID, NUMERIC, TEXT);

CREATE OR REPLACE FUNCTION complete_deal_internal(
  p_admin_uid  UUID,
  p_deal_id    UUID,
  p_commission NUMERIC DEFAULT NULL,
  p_note       TEXT DEFAULT NULL
) RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_role   INT;
  v_off_id UUID;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 5 THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  -- إكمال الصفقة
  UPDATE deals
  SET sts = 1,
      cmpl_by = p_admin_uid,
      ts_cmpl = NOW(),
      com_val = COALESCE(p_commission, com_val),
      com_note = COALESCE(p_note, com_note)
  WHERE id = p_deal_id AND i_del = 0;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'DEAL_NOT_FOUND';
  END IF;

  -- جلب off_id من الصفقة
  SELECT off_id INTO v_off_id FROM deals WHERE id = p_deal_id;

  -- تحويل العرض إلى مكتمل
  IF v_off_id IS NOT NULL THEN
    UPDATE offers SET sts = 6, i_pub = 0 WHERE id = v_off_id AND sts IN (2, 5);

    -- إلغاء أي مواعيد متبقية
    UPDATE appointments
    SET sts = 3,
        cnl_rsn = 'تم إكمال صفقة على هذا العرض',
        dt_end = NOW()
    WHERE off_id = v_off_id AND sts IN (0, 1);
  END IF;

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION complete_deal_internal(UUID, UUID, NUMERIC, TEXT) TO anon, authenticated;


-- ──────────────────────────────────────────────────────────────────────────
-- 5. admin_force_appointment_internal — role>=4
-- ──────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS admin_force_appointment_internal(UUID, UUID);

CREATE OR REPLACE FUNCTION admin_force_appointment_internal(
  p_admin_uid      UUID,
  p_appointment_id UUID
) RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 4 THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  UPDATE appointments
  SET i_force = 1, force_by = p_admin_uid, sts = 1
  WHERE id = p_appointment_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'APPOINTMENT_NOT_FOUND'; END IF;
  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_force_appointment_internal(UUID, UUID) TO anon, authenticated;


-- ──────────────────────────────────────────────────────────────────────────
-- 6. admin_handle_report_internal — role>=4
-- ──────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS admin_handle_report_internal(UUID, UUID, INT, TEXT, INT);

CREATE OR REPLACE FUNCTION admin_handle_report_internal(
  p_admin_uid UUID,
  p_report_id UUID,
  p_action    INT,
  p_note      TEXT DEFAULT '',
  p_duration  INT DEFAULT 0
) RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 4 THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  UPDATE reports
  SET sts = 1,
      act = COALESCE(p_action, 0),
      act_dur = COALESCE(p_duration, 0),
      note = COALESCE(p_note, ''),
      act_by = p_admin_uid
  WHERE id = p_report_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'REPORT_NOT_FOUND'; END IF;
  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_handle_report_internal(UUID, UUID, INT, TEXT, INT) TO anon, authenticated;


-- ──────────────────────────────────────────────────────────────────────────
-- 7. create_request_internal — إعفاء role>=4
-- ──────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS create_request_internal(UUID, JSONB);

CREATE OR REPLACE FUNCTION create_request_internal(
  p_user_uid UUID,
  p_request  JSONB
) RETURNS SETOF requests
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_user   users%ROWTYPE;
  v_config JSONB;
  v_limit  INT;
  v_used   INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT * INTO v_user FROM users WHERE id = p_user_uid AND i_del = 0 AND sts = 0;
  IF v_user.id IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_ACTIVE_OR_NOT_FOUND';
  END IF;

  IF COALESCE(trim(p_request->>'cl_nm'), '') = '' OR COALESCE(trim(p_request->>'cl_ph'), '') = '' THEN
    RAISE EXCEPTION 'MISSING_CLIENT_DATA';
  END IF;

  -- موظف المكتب فما فوق معفي من الحصة
  IF COALESCE(v_user.role, 0) < 4 THEN
    SELECT value INTO v_config FROM app_config WHERE key = 'main';
    v_limit := CASE WHEN COALESCE(v_user.role, 0) = 1
      THEN COALESCE((v_config->'qta'->'b'->>'r')::INT, 5)
      ELSE COALESCE((v_config->'qta'->'u'->>'r')::INT, 3)
    END;

    SELECT COUNT(*) INTO v_used FROM requests WHERE usr_id = p_user_uid AND i_del = 0;

    IF COALESCE(v_used, 0) >= COALESCE(v_limit, 3) THEN
      RAISE EXCEPTION 'QUOTA_EXCEEDED';
    END IF;
  END IF;

  RETURN QUERY
  INSERT INTO requests (
    typ, elm, cl_nm, cl_ph, prc, cur, notes, specs,
    usr_id, sts, i_del, ts_crt
  ) VALUES (
    COALESCE((p_request->>'typ')::INT, 0),
    COALESCE((p_request->>'elm')::INT, 0),
    COALESCE(p_request->>'cl_nm', ''),
    COALESCE(p_request->>'cl_ph', ''),
    COALESCE((p_request->>'prc')::NUMERIC, 0),
    COALESCE((p_request->>'cur')::INT, 0),
    COALESCE(p_request->>'notes', ''),
    COALESCE(p_request->'specs', '{}'::jsonb),
    p_user_uid,
    0, 0, NOW()
  ) RETURNING *;
END;
$$;

GRANT EXECUTE ON FUNCTION create_request_internal(UUID, JSONB) TO anon, authenticated;


-- ════════════════════════════════════════════════════════════════════════════
-- ✅ ملخص التغييرات:
--
-- book_appointment_internal:
--   ✅ فحص العرض منشور (sts=2)
--   ✅ منع حجز العرض الخاص بك
--   ✅ وقت بالمستقبل
--   ✅ فحص طلب إتمام معلق على العرض
--   ✅ فحص avl (يوم + فترة زمنية)
--   ✅ فحص تعارض العقار (نفس الوقت)
--   ✅ منع تكرار نفس المستخدم
--   ✅ اختيار منفذ (role=3) متاح
--   ✅ إنشاء مع supervisor_uid
--   ✅ إرجاع عدد المواعيد النشطة
--   ✅ يرجع JSONB بدل SETOF (لإرجاع active_appointments)
--
-- process_completion_request (approved):
--   ✅ يحوّل offers.sts = 5 (محجوز) + i_pub = 0
--   ✅ يلغي كل المواعيد الأخرى على نفس العرض
--   ✅ يرسل إشعار لأصحاب المواعيد الملغاة
--
-- create_deal_internal:
--   ✅ role >= 5
--   ✅ يحوّل offers.sts = 5 + i_pub = 0
--
-- complete_deal_internal:
--   ✅ role >= 5
--   ✅ يحوّل offers.sts = 6 + i_pub = 0
--   ✅ يلغي مواعيد متبقية
--
-- admin_force_appointment_internal: role >= 4
-- admin_handle_report_internal: role >= 4
-- create_request_internal: إعفاء role >= 4
-- ════════════════════════════════════════════════════════════════════════════
