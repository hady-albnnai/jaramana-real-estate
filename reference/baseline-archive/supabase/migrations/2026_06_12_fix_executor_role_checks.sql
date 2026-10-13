-- ════════════════════════════════════════════════════════════════════════════
-- إصلاح حدود الصلاحيات في دوال المنفذ بعد ترقية الأدوار
-- role >= 2 (مصور) → role >= 4 (موظف مكتب فما فوق)
-- ════════════════════════════════════════════════════════════════════════════

-- 1. تحديث RLS على completion_requests
DROP POLICY IF EXISTS "completion_requests_select" ON completion_requests;
CREATE POLICY "completion_requests_select" ON completion_requests FOR SELECT
  USING (
    req_by = auth.uid()
    OR EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role >= 4)
  );

-- 2. تحديث get_all_pending_completion_requests — role >= 4
DROP FUNCTION IF EXISTS get_all_pending_completion_requests(uuid);

CREATE OR REPLACE FUNCTION get_all_pending_completion_requests(
  p_admin_uid UUID DEFAULT NULL
)
RETURNS TABLE(
  request_id UUID,
  appointment_id UUID,
  off_id UUID,
  display_title TEXT,
  offer_number TEXT,
  task_type TEXT,
  client_name TEXT,
  client_phone TEXT,
  executor_name TEXT,
  executor_notes TEXT,
  request_date TIMESTAMPTZ,
  appointment_date TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_uid UUID;
  v_role INT;
BEGIN
  v_uid := COALESCE(p_admin_uid, auth.uid());
  IF v_uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;

  SELECT role INTO v_role FROM users WHERE id = v_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 4 THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  RETURN QUERY
  SELECT
    cr.id              AS request_id,
    cr.app_id          AS appointment_id,
    a.off_id,
    COALESCE(o.ttl, '') AS display_title,
    COALESCE(o.ttl, '') AS offer_number,
    CASE WHEN o.typ = 0 THEN 'property' ELSE 'car' END AS task_type,
    ''::TEXT            AS client_name,
    ''::TEXT            AS client_phone,
    COALESCE(u.nm, '')  AS executor_name,
    COALESCE(cr.notes, '') AS executor_notes,
    cr.ts_crt           AS request_date,
    a.dt                AS appointment_date
  FROM completion_requests cr
  JOIN appointments a ON a.id = cr.app_id
  JOIN offers o ON o.id = a.off_id
  LEFT JOIN users u ON u.id = cr.req_by
  WHERE cr.decision = 'pending'
  ORDER BY cr.ts_crt DESC;
END;
$$;

-- 3. تحديث process_completion_request — role >= 4
DROP FUNCTION IF EXISTS process_completion_request(uuid, uuid, text, text);

CREATE OR REPLACE FUNCTION process_completion_request(
  p_admin_uid UUID,
  p_request_id UUID,
  p_decision TEXT,
  p_office_notes TEXT DEFAULT ''
) RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_role INT;
  v_req RECORD;
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

  UPDATE completion_requests
  SET decision = p_decision,
      decided_by = p_admin_uid,
      office_notes = COALESCE(p_office_notes, ''),
      ts_decided = NOW()
  WHERE id = p_request_id;

  IF p_decision = 'approved' THEN
    UPDATE appointments SET sts = 2 WHERE id = v_req.app_id AND sts <> 2;
  ELSIF p_decision = 'rejected' THEN
    UPDATE appointments SET sts = 4, outcome = 'reject' WHERE id = v_req.app_id;
  END IF;

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

-- 4. تحديث request_completion_by_appointment — إشعار role >= 4 بدل role >= 2
DROP FUNCTION IF EXISTS request_completion_by_appointment(uuid, uuid, text);

CREATE OR REPLACE FUNCTION request_completion_by_appointment(
  p_user_uid UUID,
  p_appointment_id UUID,
  p_notes TEXT DEFAULT ''
) RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_appt RECORD;
  v_existing INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_MISMATCH';
  END IF;

  SELECT * INTO v_appt FROM appointments WHERE id = p_appointment_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'APPOINTMENT_NOT_FOUND'; END IF;
  IF v_appt.supervisor_uid <> p_user_uid THEN RAISE EXCEPTION 'NOT_YOUR_TASK'; END IF;

  SELECT COUNT(*) INTO v_existing
  FROM completion_requests
  WHERE app_id = p_appointment_id AND decision = 'pending';
  IF v_existing > 0 THEN
    RAISE EXCEPTION 'يوجد طلب إتمام معلق مسبقاً';
  END IF;

  UPDATE appointments
  SET outcome = 'accept',
      executor_notes = COALESCE(p_notes, ''),
      completion_date = NOW(),
      sts = CASE WHEN sts IN (0, 1) THEN 2 ELSE sts END
  WHERE id = p_appointment_id;

  INSERT INTO completion_requests (app_id, req_by, notes)
  VALUES (p_appointment_id, p_user_uid, COALESCE(p_notes, ''));

  -- إشعار موظفي المكتب فما فوق (role >= 4)
  INSERT INTO notifications (uid, typ, ttl, bdy, ref_id, ts_crt)
  SELECT u.id, 20, 'طلب إتمام معاملة',
         'المنفذ أرسل طلب إتمام لموعد — يرجى المراجعة',
         p_appointment_id, NOW()
  FROM users u
  WHERE u.role >= 4 AND u.sts = 0 AND u.i_del = 0;

  RETURN TRUE;
END;
$$;

-- 5. GRANTs
GRANT EXECUTE ON FUNCTION get_all_pending_completion_requests TO anon, authenticated;
GRANT EXECUTE ON FUNCTION process_completion_request TO anon, authenticated;
GRANT EXECUTE ON FUNCTION request_completion_by_appointment TO anon, authenticated;
