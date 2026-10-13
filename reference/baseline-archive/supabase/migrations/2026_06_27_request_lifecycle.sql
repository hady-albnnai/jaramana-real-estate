-- Request lifecycle: expiry/renewal/closure with strict server-side authorization.

-- 1) Schema additions.
ALTER TABLE public.requests
  ADD COLUMN IF NOT EXISTS ts_end TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS ts_ren TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS rmnd_ren INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS closed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS closed_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS closed_reason TEXT DEFAULT '',
  ADD COLUMN IF NOT EXISTS closed_note TEXT DEFAULT '',
  ADD COLUMN IF NOT EXISTS closed_offer_id UUID REFERENCES public.offers(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS closed_appointment_id UUID REFERENCES public.appointments(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS closed_completion_request_id UUID REFERENCES public.completion_requests(id) ON DELETE SET NULL;

ALTER TABLE public.requests
  DROP CONSTRAINT IF EXISTS requests_sts_check,
  ADD CONSTRAINT requests_sts_check CHECK (sts >= 0 AND sts <= 4);

ALTER TABLE public.requests
  DROP CONSTRAINT IF EXISTS requests_rmnd_ren_check,
  ADD CONSTRAINT requests_rmnd_ren_check CHECK (rmnd_ren IN (0, 1));

CREATE INDEX IF NOT EXISTS idx_requests_lifecycle ON public.requests(sts, i_del, ts_end);
CREATE INDEX IF NOT EXISTS idx_requests_closed ON public.requests(closed_at) WHERE closed_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_requests_closed_by ON public.requests(closed_by) WHERE closed_by IS NOT NULL;

-- Backfill active requests created before lifecycle deployment.
UPDATE public.requests
SET ts_end = COALESCE(ts_end, ts_crt + INTERVAL '30 days'),
    rmnd_ren = COALESCE(rmnd_ren, 0),
    closed_reason = COALESCE(closed_reason, ''),
    closed_note = COALESCE(closed_note, '')
WHERE ts_end IS NULL;

-- Config defaults: request lifecycle. d=initial days, warn=days before expiry, ren=renewal days, purge=archive/anonymize days.
UPDATE public.app_config
SET value = jsonb_set(
  value,
  '{req}',
  COALESCE(value->'req', '{"d":30,"warn":3,"ren":30,"purge":180}'::jsonb),
  true
)
WHERE key = 'main';

-- 2) Helpers.
CREATE OR REPLACE FUNCTION public.request_lifecycle_days(p_key TEXT, p_default INT)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, extensions, pg_temp
AS $$
DECLARE
  v_config JSONB;
  v_value INT;
BEGIN
  SELECT value INTO v_config FROM public.app_config WHERE key = 'main';
  v_value := COALESCE((v_config->'req'->>p_key)::INT, p_default);
  IF v_value IS NULL OR v_value <= 0 OR v_value > 3650 THEN
    RETURN p_default;
  END IF;
  RETURN v_value;
EXCEPTION WHEN OTHERS THEN
  RETURN p_default;
END;
$$;

CREATE OR REPLACE FUNCTION public.request_assert_owner_active(p_user_uid UUID, p_request_id UUID)
RETURNS public.requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, extensions, pg_temp
AS $$
DECLARE
  v_req public.requests%ROWTYPE;
BEGIN
  SELECT * INTO v_req
  FROM public.requests
  WHERE id = p_request_id
    AND usr_id = p_user_uid
    AND i_del = 0;

  IF v_req.id IS NULL THEN
    RAISE EXCEPTION 'REQUEST_NOT_FOUND_OR_NOT_ALLOWED';
  END IF;
  RETURN v_req;
END;
$$;

-- 3) Existing RPCs updated.
CREATE OR REPLACE FUNCTION public.create_request_internal(p_user_uid UUID, p_request JSONB)
RETURNS SETOF public.requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, extensions, pg_temp
AS $$
DECLARE
  v_user public.users%ROWTYPE;
  v_config JSONB;
  v_limit INT;
  v_used INT;
  v_name TEXT;
  v_phone TEXT;
  v_notes TEXT;
  v_price NUMERIC;
  v_days INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT * INTO v_user FROM public.users WHERE id = p_user_uid AND i_del = 0 AND sts = 0;
  IF v_user.id IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_ACTIVE_OR_NOT_FOUND';
  END IF;

  v_name := public.app_assert_text_len(p_request->>'cl_nm', 'client_name', 2, 60);
  v_phone := public.app_assert_phone(p_request->>'cl_ph');
  v_notes := public.app_clean_text(p_request->>'notes', 1000);
  v_price := COALESCE((p_request->>'prc')::NUMERIC, 0);
  IF v_price < 0 OR v_price > 999999999999 THEN
    RAISE EXCEPTION 'INVALID_PRICE';
  END IF;

  -- Staff office and above are exempt. Only active/in-progress requests consume quota.
  IF COALESCE(v_user.role, 0) < 4 THEN
    SELECT value INTO v_config FROM public.app_config WHERE key = 'main';
    v_limit := CASE WHEN COALESCE(v_user.role, 0) = 1
      THEN COALESCE((v_config->'qta'->'b'->>'r')::INT, 5)
      ELSE COALESCE((v_config->'qta'->'u'->>'r')::INT, 3)
    END;

    SELECT COUNT(*) INTO v_used
    FROM public.requests
    WHERE usr_id = p_user_uid
      AND i_del = 0
      AND sts IN (0, 1);

    IF COALESCE(v_used, 0) >= COALESCE(v_limit, 3) THEN
      RAISE EXCEPTION 'QUOTA_EXCEEDED';
    END IF;
  END IF;

  v_days := public.request_lifecycle_days('d', 30);

  RETURN QUERY
  INSERT INTO public.requests (
    typ, elm, cl_nm, cl_ph, prc, cur, notes, specs,
    usr_id, sts, matches, i_del, ts_crt, ts_end, rmnd_ren,
    closed_reason, closed_note
  ) VALUES (
    COALESCE((p_request->>'typ')::INT, 0),
    COALESCE((p_request->>'elm')::INT, 0),
    v_name,
    v_phone,
    v_price,
    COALESCE((p_request->>'cur')::INT, 0),
    v_notes,
    COALESCE(p_request->'specs', '{}'::jsonb),
    p_user_uid,
    0,
    COALESCE(p_request->'matches', '{}'::jsonb),
    0,
    NOW(),
    NOW() + (v_days || ' days')::INTERVAL,
    0,
    '',
    ''
  ) RETURNING *;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_request_internal(p_user_uid UUID, p_request_id UUID, p_patch JSONB)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, extensions, pg_temp
AS $$
DECLARE
  v_name TEXT;
  v_phone TEXT;
  v_notes TEXT;
  v_price NUMERIC;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  v_name := CASE WHEN p_patch ? 'cl_nm' THEN public.app_assert_text_len(p_patch->>'cl_nm', 'client_name', 2, 60) ELSE NULL END;
  v_phone := CASE WHEN p_patch ? 'cl_ph' THEN public.app_assert_phone(p_patch->>'cl_ph') ELSE NULL END;
  v_notes := CASE WHEN p_patch ? 'notes' THEN public.app_clean_text(p_patch->>'notes', 1000) ELSE NULL END;
  v_price := CASE WHEN p_patch ? 'prc' THEN (p_patch->>'prc')::NUMERIC ELSE NULL END;
  IF v_price IS NOT NULL AND (v_price < 0 OR v_price > 999999999999) THEN
    RAISE EXCEPTION 'INVALID_PRICE';
  END IF;

  UPDATE public.requests
  SET typ = COALESCE((p_patch->>'typ')::INT, typ),
      elm = COALESCE((p_patch->>'elm')::INT, elm),
      cl_nm = COALESCE(v_name, cl_nm),
      cl_ph = COALESCE(v_phone, cl_ph),
      prc = COALESCE(v_price, prc),
      cur = COALESCE((p_patch->>'cur')::INT, cur),
      notes = COALESCE(v_notes, notes),
      specs = COALESCE(p_patch->'specs', specs)
  WHERE id = p_request_id
    AND usr_id = p_user_uid
    AND i_del = 0
    AND sts IN (0, 1);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'REQUEST_NOT_FOUND_OR_NOT_EDITABLE';
  END IF;
  RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_user_requests_internal(p_user_uid UUID)
RETURNS SETOF public.requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, extensions, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  RETURN QUERY
  SELECT * FROM public.requests
  WHERE usr_id = p_user_uid
    AND i_del = 0
  ORDER BY ts_crt DESC;
END;
$$;

DROP FUNCTION IF EXISTS public.get_admin_requests_internal(UUID);

CREATE OR REPLACE FUNCTION public.get_admin_requests_internal(p_admin_uid UUID)
RETURNS TABLE(
  id UUID, typ INT, elm INT, cl_nm TEXT, cl_ph TEXT,
  prc NUMERIC, cur INT, notes TEXT, specs JSONB,
  usr_id UUID, sts INT, matches JSONB, i_del INT, ts_crt TIMESTAMPTZ,
  ts_end TIMESTAMPTZ, ts_ren TIMESTAMPTZ, rmnd_ren INT,
  closed_at TIMESTAMPTZ, closed_by UUID, closed_by_name TEXT, closed_by_role INT,
  closed_reason TEXT, closed_note TEXT,
  closed_offer_id UUID, closed_appointment_id UUID, closed_completion_request_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, extensions, pg_temp
AS $$
DECLARE
  v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_MISMATCH';
  END IF;
  SELECT role INTO v_role FROM public.users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 3 THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  RETURN QUERY
  SELECT r.id, r.typ, r.elm, r.cl_nm, r.cl_ph, r.prc, r.cur, r.notes, r.specs,
         r.usr_id, r.sts, r.matches, r.i_del, r.ts_crt,
         r.ts_end, r.ts_ren, r.rmnd_ren,
         r.closed_at, r.closed_by, COALESCE(u.nm, '') AS closed_by_name, u.role AS closed_by_role,
         COALESCE(r.closed_reason, ''), COALESCE(r.closed_note, ''),
         r.closed_offer_id, r.closed_appointment_id, r.closed_completion_request_id
  FROM public.requests r
  LEFT JOIN public.users u ON u.id = r.closed_by
  WHERE r.i_del = 0
  ORDER BY r.ts_crt DESC;
END;
$$;

-- User cancel replaces destructive soft-delete for normal lifecycle. Old soft_delete is kept as compatibility wrapper.
CREATE OR REPLACE FUNCTION public.cancel_request_internal(p_user_uid UUID, p_request_id UUID, p_reason TEXT DEFAULT '')
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, extensions, pg_temp
AS $$
DECLARE
  v_note TEXT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  v_note := public.app_clean_text(COALESCE(p_reason, ''), 500);

  UPDATE public.requests
  SET sts = 3,
      closed_at = NOW(),
      closed_by = p_user_uid,
      closed_reason = 'cancelled_by_user',
      closed_note = v_note,
      rmnd_ren = 0
  WHERE id = p_request_id
    AND usr_id = p_user_uid
    AND i_del = 0
    AND sts IN (0, 1, 4);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'REQUEST_NOT_FOUND_OR_NOT_CANCELLABLE';
  END IF;

  PERFORM public.notify_user(
    p_user_uid, 1,
    'تم إلغاء طلبك',
    'تم إلغاء طلبك بناءً على طلبك. يمكنك إنشاء طلب جديد عند الحاجة.',
    p_request_id::TEXT, 'request'
  );
  RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.soft_delete_request_internal(p_user_uid UUID, p_request_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, extensions, pg_temp
AS $$
BEGIN
  -- Compatibility path: do not erase accountability; mark as user-cancelled.
  RETURN public.cancel_request_internal(p_user_uid, p_request_id, '');
END;
$$;

CREATE OR REPLACE FUNCTION public.renew_request_internal(p_user_uid UUID, p_request_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, extensions, pg_temp
AS $$
DECLARE
  v_req public.requests%ROWTYPE;
  v_days INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  v_req := public.request_assert_owner_active(p_user_uid, p_request_id);
  IF v_req.sts NOT IN (0, 1, 4) THEN
    RAISE EXCEPTION 'REQUEST_NOT_RENEWABLE';
  END IF;

  v_days := public.request_lifecycle_days('ren', 30);

  UPDATE public.requests
  SET ts_end = GREATEST(COALESCE(ts_end, NOW()), NOW()) + (v_days || ' days')::INTERVAL,
      ts_ren = NOW(),
      rmnd_ren = 0,
      sts = CASE WHEN sts = 4 THEN 0 ELSE sts END,
      closed_at = CASE WHEN sts = 4 THEN NULL ELSE closed_at END,
      closed_by = CASE WHEN sts = 4 THEN NULL ELSE closed_by END,
      closed_reason = CASE WHEN sts = 4 THEN '' ELSE closed_reason END,
      closed_note = CASE WHEN sts = 4 THEN '' ELSE closed_note END
  WHERE id = p_request_id
    AND usr_id = p_user_uid
    AND i_del = 0;

  PERFORM public.notify_user(
    p_user_uid, 1,
    'تم تجديد طلبك',
    'تم تجديد مدة طلبك بنجاح وسيبقى ظاهراً للمطابقة والمتابعة.',
    p_request_id::TEXT, 'request'
  );
  RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.can_publish_request_internal(p_user_uid UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, extensions, pg_temp
AS $$
DECLARE
  v_user public.users%ROWTYPE;
  v_config JSONB;
  v_limit INT;
  v_used INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT * INTO v_user FROM public.users WHERE id = p_user_uid AND i_del = 0 AND sts = 0;
  IF v_user.id IS NULL THEN
    RETURN jsonb_build_object('allowed', false, 'used', 0, 'limit', 0, 'reason', 'USER_NOT_ACTIVE_OR_NOT_FOUND');
  END IF;

  IF COALESCE(v_user.role, 0) >= 4 THEN
    RETURN jsonb_build_object('allowed', true, 'used', 0, 'limit', 999999, 'reason', '');
  END IF;

  SELECT value INTO v_config FROM public.app_config WHERE key = 'main';
  v_limit := CASE WHEN COALESCE(v_user.role, 0) = 1
    THEN COALESCE((v_config->'qta'->'b'->>'r')::INT, 5)
    ELSE COALESCE((v_config->'qta'->'u'->>'r')::INT, 3)
  END;

  SELECT COUNT(*) INTO v_used
  FROM public.requests
  WHERE usr_id = p_user_uid
    AND i_del = 0
    AND sts IN (0, 1);

  RETURN jsonb_build_object(
    'allowed', COALESCE(v_used, 0) < COALESCE(v_limit, 3),
    'used', COALESCE(v_used, 0),
    'limit', COALESCE(v_limit, 3),
    'reason', CASE WHEN COALESCE(v_used, 0) < COALESCE(v_limit, 3) THEN '' ELSE 'QUOTA_EXCEEDED' END
  );
END;
$$;

-- 4) Appointment/request lifecycle linkage.
CREATE OR REPLACE FUNCTION public.book_appointment_internal(
  p_user_uid UUID,
  p_offer_id UUID,
  p_dt TIMESTAMPTZ,
  p_broker_id UUID DEFAULT NULL,
  p_request_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, extensions, pg_temp
AS $$
DECLARE
  v_offer      public.offers%ROWTYPE;
  v_req        public.requests%ROWTYPE;
  v_day_key    TEXT;
  v_slot       TEXT;
  v_slot_from  INT;
  v_slot_to    INT;
  v_req_mins   INT;
  v_avl_slots  JSONB;
  v_found_slot BOOLEAN := FALSE;
  v_supervisor UUID;
  v_active_count INT;
  v_pending_completion INT;
  v_appointment_id UUID;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT * INTO v_offer FROM public.offers WHERE id = p_offer_id AND i_del = 0;
  IF v_offer.id IS NULL THEN RAISE EXCEPTION 'OFFER_NOT_FOUND'; END IF;
  IF v_offer.sts NOT IN (2) THEN RAISE EXCEPTION 'OFFER_NOT_AVAILABLE'; END IF;
  IF p_user_uid = v_offer.usr_id THEN RAISE EXCEPTION 'CANNOT_BOOK_OWN_OFFER'; END IF;
  IF p_dt <= NOW() THEN RAISE EXCEPTION 'INVALID_APPOINTMENT_TIME'; END IF;

  IF p_request_id IS NOT NULL THEN
    SELECT * INTO v_req
    FROM public.requests
    WHERE id = p_request_id
      AND usr_id = p_user_uid
      AND i_del = 0
      AND sts IN (0, 1)
      AND (ts_end IS NULL OR ts_end > NOW());
    IF v_req.id IS NULL THEN
      RAISE EXCEPTION 'REQUEST_NOT_FOUND_OR_NOT_ACTIVE';
    END IF;
    IF v_req.elm <> v_offer.typ OR v_req.typ <> v_offer.trx THEN
      RAISE EXCEPTION 'REQUEST_OFFER_MISMATCH';
    END IF;
  END IF;

  SELECT COUNT(*) INTO v_pending_completion
  FROM public.completion_requests cr
  JOIN public.appointments a ON a.id = cr.app_id
  WHERE a.off_id = p_offer_id
    AND cr.decision = 'pending';
  IF v_pending_completion > 0 THEN RAISE EXCEPTION 'OFFER_HAS_PENDING_COMPLETION'; END IF;

  IF v_offer.avl IS NOT NULL AND v_offer.avl <> '{}'::jsonb AND v_offer.avl <> 'null'::jsonb THEN
    v_day_key := LOWER(to_char(p_dt AT TIME ZONE 'Asia/Damascus', 'Dy'));
    v_day_key := CASE v_day_key
      WHEN 'mon' THEN 'mon' WHEN 'tue' THEN 'tue' WHEN 'wed' THEN 'wed'
      WHEN 'thu' THEN 'thu' WHEN 'fri' THEN 'fri' WHEN 'sat' THEN 'sat'
      WHEN 'sun' THEN 'sun' ELSE v_day_key END;

    v_avl_slots := v_offer.avl -> v_day_key;
    IF v_avl_slots IS NULL OR jsonb_array_length(v_avl_slots) = 0 THEN
      RAISE EXCEPTION 'DAY_NOT_AVAILABLE';
    END IF;

    v_req_mins := EXTRACT(HOUR FROM p_dt AT TIME ZONE 'Asia/Damascus')::INT * 60
                + EXTRACT(MINUTE FROM p_dt AT TIME ZONE 'Asia/Damascus')::INT;
    FOR v_slot IN SELECT jsonb_array_elements_text(v_avl_slots)
    LOOP
      v_slot_from := SPLIT_PART(SPLIT_PART(v_slot, '-', 1), ':', 1)::INT * 60
                   + SPLIT_PART(SPLIT_PART(v_slot, '-', 1), ':', 2)::INT;
      v_slot_to := SPLIT_PART(SPLIT_PART(v_slot, '-', 2), ':', 1)::INT * 60
                 + SPLIT_PART(SPLIT_PART(v_slot, '-', 2), ':', 2)::INT;
      IF v_req_mins >= v_slot_from AND v_req_mins < v_slot_to THEN
        v_found_slot := TRUE; EXIT;
      END IF;
    END LOOP;
    IF NOT v_found_slot THEN RAISE EXCEPTION 'TIME_NOT_IN_AVAILABLE_SLOTS'; END IF;
  END IF;

  IF EXISTS (SELECT 1 FROM public.appointments WHERE off_id = p_offer_id AND dt = p_dt AND sts IN (0, 1)) THEN
    RAISE EXCEPTION 'TIME_CONFLICT_ON_OFFER';
  END IF;

  IF EXISTS (SELECT 1 FROM public.appointments WHERE off_id = p_offer_id AND req_uid = p_user_uid AND sts IN (0, 1)) THEN
    RAISE EXCEPTION 'DUPLICATE_APPOINTMENT';
  END IF;

  SELECT u.id INTO v_supervisor
  FROM public.users u
  WHERE u.role = 3 AND u.sts = 0 AND u.i_del = 0
    AND NOT EXISTS (
      SELECT 1 FROM public.appointments a
      WHERE a.supervisor_uid = u.id AND a.sts IN (0, 1) AND a.dt = p_dt
    )
  ORDER BY (
    SELECT COUNT(*) FROM public.appointments a2 WHERE a2.supervisor_uid = u.id AND a2.sts IN (0, 1)
  ) ASC, u.ts_crt ASC
  LIMIT 1;
  IF v_supervisor IS NULL THEN RAISE EXCEPTION 'NO_SUPERVISOR_AVAILABLE'; END IF;

  INSERT INTO public.appointments (
    off_id, req_id, req_uid, own_id, bkr_id, dt, sts,
    supervisor_uid,
    fbk_own, fbk_req, i_force, rmnd_24, rmnd_2, rmnd_qtr, rmnd_end, ts_crt
  ) VALUES (
    p_offer_id, p_request_id, p_user_uid, v_offer.usr_id, COALESCE(p_broker_id, v_offer.brk_id), p_dt, 0,
    v_supervisor,
    0, 0, 0, 0, 0, 0, 0, NOW()
  ) RETURNING id INTO v_appointment_id;

  IF p_request_id IS NOT NULL THEN
    UPDATE public.requests
    SET sts = 1
    WHERE id = p_request_id
      AND usr_id = p_user_uid
      AND sts = 0
      AND i_del = 0;
  END IF;

  SELECT COUNT(*) INTO v_active_count FROM public.appointments WHERE off_id = p_offer_id AND sts IN (0, 1);
  RETURN jsonb_build_object('success', true, 'appointment_id', v_appointment_id, 'active_appointments', v_active_count, 'supervisor_uid', v_supervisor);
END;
$$;

CREATE OR REPLACE FUNCTION public.process_completion_request(
  p_admin_uid UUID,
  p_request_id UUID,
  p_decision TEXT,
  p_office_notes TEXT DEFAULT ''
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, extensions, pg_temp
AS $$
DECLARE
  v_role INT;
  v_req RECORD;
  v_appt RECORD;
  v_off_id UUID;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  IF p_decision NOT IN ('approved', 'rejected') THEN RAISE EXCEPTION 'INVALID_DECISION'; END IF;

  SELECT role INTO v_role FROM public.users WHERE id = p_admin_uid AND i_del = 0 AND sts = 0;
  IF v_role IS NULL OR v_role < 4 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;

  SELECT * INTO v_req FROM public.completion_requests WHERE id = p_request_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND'; END IF;
  IF v_req.decision <> 'pending' THEN RAISE EXCEPTION 'REQUEST_ALREADY_PROCESSED'; END IF;

  SELECT * INTO v_appt FROM public.appointments WHERE id = v_req.app_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'APPOINTMENT_NOT_FOUND'; END IF;
  v_off_id := v_appt.off_id;

  UPDATE public.completion_requests
  SET decision = p_decision,
      decided_by = p_admin_uid,
      office_notes = COALESCE(p_office_notes, ''),
      ts_decided = NOW()
  WHERE id = p_request_id;

  IF p_decision = 'approved' THEN
    UPDATE public.appointments SET sts = 2 WHERE id = v_req.app_id AND sts <> 2;
    UPDATE public.offers SET sts = 5, i_pub = 0 WHERE id = v_off_id AND sts IN (2, 5);

    UPDATE public.appointments
    SET sts = 3, cnl_rsn = 'تم إتمام معاملة على هذا العرض', dt_end = NOW()
    WHERE off_id = v_off_id AND id <> v_req.app_id AND sts IN (0, 1);

    IF v_appt.req_id IS NOT NULL THEN
      UPDATE public.requests
      SET sts = 2,
          closed_at = NOW(),
          closed_by = p_admin_uid,
          closed_reason = 'fulfilled_by_offer_completion',
          closed_note = COALESCE(p_office_notes, ''),
          closed_offer_id = v_off_id,
          closed_appointment_id = v_req.app_id,
          closed_completion_request_id = p_request_id,
          rmnd_ren = 0
      WHERE id = v_appt.req_id
        AND i_del = 0
        AND sts IN (0, 1, 4);

      PERFORM public.notify_user(
        v_appt.req_uid, 1,
        'تمت تلبية طلبك',
        'تم إغلاق طلبك بعد إتمام معاملة مرتبطة به عبر المكتب.',
        v_appt.req_id::TEXT, 'request'
      );
    END IF;

    INSERT INTO public.notifications (uid, tp, ttl, bdy, ref_id, ts_crt)
      SELECT a.req_uid, 0, 'تم إلغاء موعدك', 'تم إلغاء موعدك لأن العرض اكتمل بمعاملة أخرى.', a.id::TEXT, NOW()
      FROM public.appointments a
      WHERE a.off_id = v_off_id AND a.id <> v_req.app_id AND a.sts = 3
        AND a.cnl_rsn = 'تم إتمام معاملة على هذا العرض';

  ELSIF p_decision = 'rejected' THEN
    UPDATE public.appointments SET sts = 4, outcome = 'reject' WHERE id = v_req.app_id;
    UPDATE public.offers SET sts = 2, i_pub = 1 WHERE id = v_off_id AND sts = 5;
  END IF;

  INSERT INTO public.notifications (uid, tp, ttl, bdy, ref_id, ts_crt) VALUES (
    v_req.req_by, 20,
    CASE WHEN p_decision = 'approved' THEN 'تمت الموافقة على طلب الإتمام' ELSE 'تم رفض طلب الإتمام' END,
    CASE WHEN p_decision = 'approved' THEN 'تمت الموافقة على طلب إتمام المعاملة ✓'
         ELSE 'تم رفض طلب الإتمام: ' || COALESCE(p_office_notes, '') END,
    v_req.app_id::TEXT, NOW()
  );
  RETURN TRUE;
END;
$$;

-- 5) Administrative closure.
CREATE OR REPLACE FUNCTION public.admin_close_request_internal(
  p_admin_uid UUID,
  p_request_id UUID,
  p_status INT,
  p_reason TEXT DEFAULT 'closed_by_admin',
  p_note TEXT DEFAULT ''
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, extensions, pg_temp
AS $$
DECLARE
  v_role INT;
  v_reason TEXT;
  v_note TEXT;
  v_owner UUID;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM public.users WHERE id = p_admin_uid AND i_del = 0 AND sts = 0;
  IF v_role IS NULL OR v_role < 4 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  IF p_status NOT IN (2, 3, 4) THEN RAISE EXCEPTION 'INVALID_REQUEST_CLOSE_STATUS'; END IF;

  v_reason := public.app_clean_text(COALESCE(NULLIF(p_reason, ''), 'closed_by_admin'), 120);
  v_note := public.app_clean_text(COALESCE(p_note, ''), 500);

  UPDATE public.requests
  SET sts = p_status,
      closed_at = NOW(),
      closed_by = p_admin_uid,
      closed_reason = v_reason,
      closed_note = v_note,
      rmnd_ren = 0
  WHERE id = p_request_id
    AND i_del = 0
    AND sts IN (0, 1, 4)
  RETURNING usr_id INTO v_owner;

  IF NOT FOUND THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND_OR_NOT_CLOSABLE'; END IF;

  IF v_owner IS NOT NULL THEN
    PERFORM public.notify_user(
      v_owner, 1,
      CASE WHEN p_status = 2 THEN 'تمت تلبية طلبك' WHEN p_status = 4 THEN 'انتهت صلاحية طلبك' ELSE 'تم إغلاق طلبك' END,
      COALESCE(NULLIF(v_note, ''), 'تم تحديث حالة طلبك من قبل المكتب.'),
      p_request_id::TEXT, 'request'
    );
  END IF;
  RETURN TRUE;
END;
$$;

-- 6) Cron functions.
CREATE OR REPLACE FUNCTION public.send_request_renewal_reminders()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, extensions, pg_temp
AS $$
DECLARE
  v_count INT := 0;
  v_warn INT;
  v_req RECORD;
BEGIN
  v_warn := public.request_lifecycle_days('warn', 3);

  FOR v_req IN
    SELECT id, usr_id, typ, elm, ts_end
    FROM public.requests
    WHERE i_del = 0
      AND sts IN (0, 1)
      AND usr_id IS NOT NULL
      AND rmnd_ren = 0
      AND ts_end IS NOT NULL
      AND ts_end <= NOW() + (v_warn || ' days')::INTERVAL
      AND ts_end > NOW()
  LOOP
    PERFORM public.notify_user(
      v_req.usr_id, 1,
      'تذكير بتجديد طلبك',
      'طلبك سينتهي قريباً. جدده إذا كنت ما زلت تبحث ليبقى ضمن مطابقة عروض المكتب.',
      v_req.id::TEXT, 'request'
    );
    UPDATE public.requests SET rmnd_ren = 1 WHERE id = v_req.id;
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.expire_requests()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, extensions, pg_temp
AS $$
DECLARE
  v_count INT := 0;
  v_req RECORD;
BEGIN
  FOR v_req IN
    SELECT id, usr_id
    FROM public.requests
    WHERE i_del = 0
      AND sts IN (0, 1)
      AND ts_end IS NOT NULL
      AND ts_end <= NOW()
  LOOP
    UPDATE public.requests
    SET sts = 4,
        closed_at = NOW(),
        closed_by = NULL,
        closed_reason = 'expired',
        closed_note = '',
        rmnd_ren = 0
    WHERE id = v_req.id;

    IF v_req.usr_id IS NOT NULL THEN
      PERFORM public.notify_user(
        v_req.usr_id, 1,
        'انتهت صلاحية طلبك',
        'انتهت مدة طلبك تلقائياً. يمكنك تجديده إذا كنت ما زلت تبحث.',
        v_req.id::TEXT, 'request'
      );
    END IF;
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.purge_old_closed_requests()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, extensions, pg_temp
AS $$
DECLARE
  v_days INT;
  v_count INT := 0;
BEGIN
  v_days := public.request_lifecycle_days('purge', 180);

  UPDATE public.requests
  SET cl_nm = '',
      cl_ph = '',
      notes = '',
      specs = '{}'::jsonb,
      matches = '{}'::jsonb,
      i_del = 1
  WHERE i_del = 0
    AND sts IN (2, 3, 4)
    AND closed_at IS NOT NULL
    AND closed_at < NOW() - (v_days || ' days')::INTERVAL;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- 7) Stats and matching correctness.
CREATE OR REPLACE FUNCTION public.update_user_stats_on_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, extensions, pg_temp
AS $$
DECLARE
  v_count INT;
  v_uid UUID;
BEGIN
  v_uid := COALESCE(NEW.usr_id, OLD.usr_id);
  IF v_uid IS NULL THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM public.requests
  WHERE usr_id = v_uid
    AND i_del = 0
    AND sts IN (0, 1);

  UPDATE public.users
  SET stats = jsonb_set(COALESCE(stats, '{}'::jsonb), '{req}', to_jsonb(v_count)),
      ts_upd = NOW()
  WHERE id = v_uid;

  IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_offer_published_match_requests()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, extensions, pg_temp
AS $$
DECLARE
  v_request RECORD;
  v_title TEXT;
  v_body TEXT;
BEGIN
  IF NEW.i_pub != 1 OR OLD.i_pub = 1 THEN RETURN NEW; END IF;

  v_title := '🎯 عرض جديد يطابق بحثك';
  v_body := 'تم إضافة عرض جديد: "' || COALESCE(NEW.ttl, 'عرض') || '" بسعر ' ||
            COALESCE(NEW.prc::TEXT, '—') || ' — يطابق طلبك.';

  FOR v_request IN
    SELECT id, usr_id
    FROM public.requests
    WHERE i_del = 0
      AND sts IN (0, 1)
      AND usr_id IS NOT NULL
      AND elm = NEW.typ
      AND typ = NEW.trx
      AND usr_id <> NEW.usr_id
      AND (prc = 0 OR NEW.prc BETWEEN prc * 0.8 AND prc * 1.2)
    LIMIT 20
  LOOP
    PERFORM public.notify_user(v_request.usr_id, 1, v_title, v_body, NEW.id::TEXT, 'offer');
    PERFORM public.send_push_notification(
      v_request.usr_id, v_title, v_body,
      jsonb_build_object('type', 'offer', 'id', NEW.id::TEXT)
    );
  END LOOP;
  RETURN NEW;
END;
$$;

-- 8) Schedule cron jobs if pg_cron is available.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'cron') THEN
    IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'daily-request-renewal-reminders') THEN
      PERFORM cron.schedule('daily-request-renewal-reminders', '20 3 * * *', 'SELECT public.send_request_renewal_reminders();');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'daily-expire-requests') THEN
      PERFORM cron.schedule('daily-expire-requests', '25 3 * * *', 'SELECT public.expire_requests();');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'weekly-purge-old-closed-requests') THEN
      PERFORM cron.schedule('weekly-purge-old-closed-requests', '35 3 * * 0', 'SELECT public.purge_old_closed_requests();');
    END IF;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'request lifecycle cron scheduling skipped: %', SQLERRM;
END $$;

-- 9) Harden EXECUTE privileges: Edge Functions call via service_role; direct anon/authenticated calls remain closed.
REVOKE EXECUTE ON FUNCTION public.request_lifecycle_days(TEXT, INT) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.request_assert_owner_active(UUID, UUID) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.create_request_internal(UUID, JSONB) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.update_request_internal(UUID, UUID, JSONB) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_user_requests_internal(UUID) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_admin_requests_internal(UUID) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.cancel_request_internal(UUID, UUID, TEXT) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.soft_delete_request_internal(UUID, UUID) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.renew_request_internal(UUID, UUID) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.can_publish_request_internal(UUID) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_close_request_internal(UUID, UUID, INT, TEXT, TEXT) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.send_request_renewal_reminders() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.expire_requests() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.purge_old_closed_requests() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.book_appointment_internal(UUID, UUID, TIMESTAMPTZ, UUID, UUID) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.process_completion_request(UUID, UUID, TEXT, TEXT) FROM anon, authenticated;

GRANT EXECUTE ON FUNCTION public.request_lifecycle_days(TEXT, INT) TO service_role;
GRANT EXECUTE ON FUNCTION public.request_assert_owner_active(UUID, UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.create_request_internal(UUID, JSONB) TO service_role;
GRANT EXECUTE ON FUNCTION public.update_request_internal(UUID, UUID, JSONB) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_user_requests_internal(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_admin_requests_internal(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.cancel_request_internal(UUID, UUID, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.soft_delete_request_internal(UUID, UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.renew_request_internal(UUID, UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.can_publish_request_internal(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_close_request_internal(UUID, UUID, INT, TEXT, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.send_request_renewal_reminders() TO service_role;
GRANT EXECUTE ON FUNCTION public.expire_requests() TO service_role;
GRANT EXECUTE ON FUNCTION public.purge_old_closed_requests() TO service_role;
GRANT EXECUTE ON FUNCTION public.book_appointment_internal(UUID, UUID, TIMESTAMPTZ, UUID, UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.process_completion_request(UUID, UUID, TEXT, TEXT) TO service_role;
