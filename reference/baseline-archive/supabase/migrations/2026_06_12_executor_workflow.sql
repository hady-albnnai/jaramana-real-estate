-- ════════════════════════════════════════════════════════════════════════════
-- نظام المنفذ الميداني (المشرف) — 2026-06-12
-- ════════════════════════════════════════════════════════════════════════════
-- التدفق:
--   1. المنفذ يشوف مهامه (مواعيد معيّن فيها supervisor_uid = uid)
--   2. ينفذ المهمة: يقبل (يطلب إتمام) / يرفض (مع سبب) / يؤجل (وقت جديد)
--   3. المكتب (مدير/نائب/موظف) يراجع طلب الإتمام: يوافق أو يرفض
-- ════════════════════════════════════════════════════════════════════════════

-- ─── الخطوة 1: أعمدة جديدة في appointments ───

ALTER TABLE appointments
  ADD COLUMN IF NOT EXISTS outcome TEXT DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS executor_notes TEXT DEFAULT '',
  ADD COLUMN IF NOT EXISTS rejection_reason TEXT DEFAULT '',
  ADD COLUMN IF NOT EXISTS completion_date TIMESTAMPTZ DEFAULT NULL;

COMMENT ON COLUMN appointments.outcome IS 'نتيجة تنفيذ المهمة: accept/reject/postpone — NULL = لم تُنفَّذ بعد';
COMMENT ON COLUMN appointments.executor_notes IS 'ملاحظات المنفذ عند تنفيذ المهمة';
COMMENT ON COLUMN appointments.rejection_reason IS 'سبب الرفض من المنفذ';
COMMENT ON COLUMN appointments.completion_date IS 'تاريخ تنفيذ المهمة فعلياً';

-- ─── الخطوة 2: جدول طلبات الإتمام ───

CREATE TABLE IF NOT EXISTS completion_requests (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  app_id      UUID NOT NULL REFERENCES appointments(id),
  req_by      UUID NOT NULL REFERENCES users(id),
  notes       TEXT DEFAULT '',
  decision    TEXT DEFAULT 'pending',   -- pending / approved / rejected
  decided_by  UUID REFERENCES users(id),
  office_notes TEXT DEFAULT '',
  ts_crt      TIMESTAMPTZ DEFAULT NOW(),
  ts_decided  TIMESTAMPTZ DEFAULT NULL
);

COMMENT ON TABLE completion_requests IS 'طلبات إتمام المعاملة — المنفذ يطلب، المكتب يراجع';

ALTER TABLE completion_requests ENABLE ROW LEVEL SECURITY;

-- المنفذ يقرأ طلباته + المكتب (role >= 2) يقرأ الكل
CREATE POLICY "completion_requests_select" ON completion_requests FOR SELECT
  USING (
    req_by = auth.uid()
    OR EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role >= 2)
  );

-- الإدراج فقط عبر RPC (SECURITY DEFINER)
CREATE POLICY "completion_requests_insert" ON completion_requests FOR INSERT
  WITH CHECK (false);

-- التحديث فقط عبر RPC
CREATE POLICY "completion_requests_update" ON completion_requests FOR UPDATE
  USING (false);

-- ─── الخطوة 3: RPCs المنفذ ───

-- 3.1 جلب مهام اليوم للمنفذ
CREATE OR REPLACE FUNCTION get_my_tasks(p_user_uid UUID DEFAULT NULL)
RETURNS TABLE(
  appointment_id UUID,
  off_id UUID,
  offer_number TEXT,
  display_title TEXT,
  task_type TEXT,
  client_name TEXT,
  client_phone TEXT,
  appointment_date TIMESTAMPTZ,
  location JSONB,
  description TEXT,
  price NUMERIC,
  offer_cur INT,
  outcome TEXT,
  sts INT
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_uid UUID;
BEGIN
  v_uid := COALESCE(p_user_uid, auth.uid());
  IF v_uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;

  RETURN QUERY
  SELECT
    a.id            AS appointment_id,
    a.off_id,
    COALESCE(o.ttl, '')  AS offer_number,
    COALESCE(o.ttl, '')  AS display_title,
    CASE WHEN o.typ = 0 THEN 'property' ELSE 'car' END AS task_type,
    ''::TEXT         AS client_name,
    ''::TEXT         AS client_phone,
    a.dt             AS appointment_date,
    COALESCE(o.loc, '{}'::jsonb) AS location,
    COALESCE(o.descript, '') AS description,
    COALESCE(o.prc, 0)  AS price,
    COALESCE(o.cur, 0)  AS offer_cur,
    a.outcome,
    a.sts
  FROM appointments a
  JOIN offers o ON o.id = a.off_id
  WHERE a.supervisor_uid = v_uid
    AND a.sts IN (0, 1)
    AND a.outcome IS NULL
    AND a.dt::date = CURRENT_DATE
  ORDER BY a.dt ASC;
END;
$$;

-- 3.2 جلب المهام المؤجلة
CREATE OR REPLACE FUNCTION get_postponed_tasks(p_user_uid UUID DEFAULT NULL)
RETURNS TABLE(
  appointment_id UUID,
  off_id UUID,
  offer_number TEXT,
  display_title TEXT,
  task_type TEXT,
  client_name TEXT,
  client_phone TEXT,
  appointment_date TIMESTAMPTZ,
  location JSONB,
  description TEXT,
  price NUMERIC,
  offer_cur INT,
  outcome TEXT,
  sts INT
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_uid UUID;
BEGIN
  v_uid := COALESCE(p_user_uid, auth.uid());
  IF v_uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;

  RETURN QUERY
  SELECT
    a.id            AS appointment_id,
    a.off_id,
    COALESCE(o.ttl, '')  AS offer_number,
    COALESCE(o.ttl, '')  AS display_title,
    CASE WHEN o.typ = 0 THEN 'property' ELSE 'car' END AS task_type,
    ''::TEXT         AS client_name,
    ''::TEXT         AS client_phone,
    a.dt             AS appointment_date,
    COALESCE(o.loc, '{}'::jsonb) AS location,
    COALESCE(o.descript, '') AS description,
    COALESCE(o.prc, 0)  AS price,
    COALESCE(o.cur, 0)  AS offer_cur,
    a.outcome,
    a.sts
  FROM appointments a
  JOIN offers o ON o.id = a.off_id
  WHERE a.supervisor_uid = v_uid
    AND a.sts IN (0, 1)
    AND a.outcome IS NULL
    AND a.dt::date > CURRENT_DATE
  ORDER BY a.dt ASC;
END;
$$;

-- 3.3 جلب المهام المنفذة
CREATE OR REPLACE FUNCTION get_completed_tasks(p_user_uid UUID DEFAULT NULL)
RETURNS TABLE(
  appointment_id UUID,
  off_id UUID,
  offer_number TEXT,
  display_title TEXT,
  task_type TEXT,
  client_name TEXT,
  client_phone TEXT,
  appointment_date TIMESTAMPTZ,
  location JSONB,
  description TEXT,
  price NUMERIC,
  offer_cur INT,
  outcome TEXT,
  completion_date TIMESTAMPTZ,
  rejection_reason TEXT,
  sts INT
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_uid UUID;
BEGIN
  v_uid := COALESCE(p_user_uid, auth.uid());
  IF v_uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;

  RETURN QUERY
  SELECT
    a.id            AS appointment_id,
    a.off_id,
    COALESCE(o.ttl, '')  AS offer_number,
    COALESCE(o.ttl, '')  AS display_title,
    CASE WHEN o.typ = 0 THEN 'property' ELSE 'car' END AS task_type,
    ''::TEXT         AS client_name,
    ''::TEXT         AS client_phone,
    a.dt             AS appointment_date,
    COALESCE(o.loc, '{}'::jsonb) AS location,
    COALESCE(o.descript, '') AS description,
    COALESCE(o.prc, 0)  AS price,
    COALESCE(o.cur, 0)  AS offer_cur,
    a.outcome,
    a.completion_date,
    a.rejection_reason,
    a.sts
  FROM appointments a
  JOIN offers o ON o.id = a.off_id
  WHERE a.supervisor_uid = v_uid
    AND a.outcome IS NOT NULL
  ORDER BY a.completion_date DESC NULLS LAST, a.dt DESC;
END;
$$;

-- 3.4 تحديث نتيجة المهمة (قبول مبدئي / رفض / تأجيل)
CREATE OR REPLACE FUNCTION update_task_outcome(
  p_user_uid UUID,
  p_appointment_id UUID,
  p_outcome TEXT,
  p_notes TEXT DEFAULT '',
  p_rejection_reason TEXT DEFAULT '',
  p_new_date TIMESTAMPTZ DEFAULT NULL
) RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_appt RECORD;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_MISMATCH';
  END IF;

  SELECT * INTO v_appt FROM appointments WHERE id = p_appointment_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'APPOINTMENT_NOT_FOUND'; END IF;
  IF v_appt.supervisor_uid <> p_user_uid THEN RAISE EXCEPTION 'NOT_YOUR_TASK'; END IF;
  IF v_appt.outcome IS NOT NULL THEN RAISE EXCEPTION 'TASK_ALREADY_PROCESSED'; END IF;

  IF p_outcome = 'reject' THEN
    UPDATE appointments
    SET outcome = 'reject',
        sts = 4,
        executor_notes = COALESCE(p_notes, ''),
        rejection_reason = COALESCE(p_rejection_reason, ''),
        completion_date = NOW()
    WHERE id = p_appointment_id;

  ELSIF p_outcome = 'postpone' THEN
    IF p_new_date IS NULL THEN RAISE EXCEPTION 'NEW_DATE_REQUIRED'; END IF;
    IF p_new_date <= NOW() THEN RAISE EXCEPTION 'DATE_MUST_BE_FUTURE'; END IF;
    UPDATE appointments
    SET dt = p_new_date,
        executor_notes = COALESCE(p_notes, '')
    WHERE id = p_appointment_id;

  ELSIF p_outcome = 'accept' THEN
    -- القبول المبدئي — يسجل النية، طلب الإتمام يكون بـ request_completion
    UPDATE appointments
    SET outcome = 'accept',
        executor_notes = COALESCE(p_notes, ''),
        completion_date = NOW()
    WHERE id = p_appointment_id;

  ELSE
    RAISE EXCEPTION 'INVALID_OUTCOME: %', p_outcome;
  END IF;

  RETURN TRUE;
END;
$$;

-- 3.5 طلب إتمام المعاملة من المنفذ
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

  -- منع طلب مكرر معلق
  SELECT COUNT(*) INTO v_existing
  FROM completion_requests
  WHERE app_id = p_appointment_id AND decision = 'pending';
  IF v_existing > 0 THEN
    RAISE EXCEPTION 'يوجد طلب إتمام معلق مسبقاً';
  END IF;

  -- تحديث الموعد
  UPDATE appointments
  SET outcome = 'accept',
      executor_notes = COALESCE(p_notes, ''),
      completion_date = NOW(),
      sts = CASE WHEN sts IN (0, 1) THEN 2 ELSE sts END
  WHERE id = p_appointment_id;

  -- إنشاء طلب الإتمام
  INSERT INTO completion_requests (app_id, req_by, notes)
  VALUES (p_appointment_id, p_user_uid, COALESCE(p_notes, ''));

  -- إشعار الإدارة
  INSERT INTO notifications (uid, typ, ttl, bdy, ref_id, ts_crt)
  SELECT u.id, 20, 'طلب إتمام معاملة',
         'المنفذ أرسل طلب إتمام لموعد — يرجى المراجعة',
         p_appointment_id, NOW()
  FROM users u
  WHERE u.role >= 2 AND u.sts = 0 AND u.i_del = 0;

  RETURN TRUE;
END;
$$;

-- ─── الخطوة 4: RPCs المكتب ───

-- 4.1 جلب طلبات الإتمام المعلقة (للمكتب)
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
  IF v_role IS NULL OR v_role < 2 THEN
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

-- 4.2 معالجة طلب الإتمام (موافقة / رفض)
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
  IF v_role IS NULL OR v_role < 2 THEN
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

  -- تحديث الموعد حسب القرار
  IF p_decision = 'approved' THEN
    UPDATE appointments
    SET sts = 2  -- مكتمل
    WHERE id = v_req.app_id AND sts <> 2;
  ELSIF p_decision = 'rejected' THEN
    UPDATE appointments
    SET sts = 4,  -- مرفوض
        outcome = 'reject'
    WHERE id = v_req.app_id;
  END IF;

  -- إشعار المنفذ بالنتيجة
  INSERT INTO notifications (uid, typ, ttl, bdy, ref_id, ts_crt)
  VALUES (
    v_req.req_by,
    20,
    CASE WHEN p_decision = 'approved' THEN 'تمت الموافقة على طلب الإتمام'
         ELSE 'تم رفض طلب الإتمام' END,
    CASE WHEN p_decision = 'approved' THEN 'تمت الموافقة على طلب إتمام المعاملة ✓'
         ELSE 'تم رفض طلب الإتمام: ' || COALESCE(p_office_notes, '') END,
    v_req.app_id,
    NOW()
  );

  RETURN TRUE;
END;
$$;

-- ─── الخطوة 5: صلاحيات الاستدعاء ───

GRANT EXECUTE ON FUNCTION get_my_tasks TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_postponed_tasks TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_completed_tasks TO anon, authenticated;
GRANT EXECUTE ON FUNCTION update_task_outcome TO anon, authenticated;
GRANT EXECUTE ON FUNCTION request_completion_by_appointment TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_all_pending_completion_requests TO anon, authenticated;
GRANT EXECUTE ON FUNCTION process_completion_request TO anon, authenticated;
