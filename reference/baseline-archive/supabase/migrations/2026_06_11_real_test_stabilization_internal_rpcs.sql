-- ════════════════════════════════════════════════════════════════════════════
-- Real test stabilization RPCs and policy fixes
-- Date: 2026-06-11
-- Purpose:
--   Replace remaining fragile direct client writes/reads in core flows with
--   SECURITY DEFINER RPCs compatible with the current auth model.
-- ════════════════════════════════════════════════════════════════════════════
--
-- FIXES vs original draft (verified against live schema 2026-06-11):
--   1. offers has NO ts_upd column → removed from all offer UPDATEs
--   2. offers.brk_id is UUID → NULLIF(brk_id,'') is invalid; use brk_id directly
--   3. activity_log columns: act(INT) not action(TEXT), det(TEXT) not details
--      → broker_request mapped to act=10, det = text summary
--   4. payments has NO ts_upd column → removed from payment UPDATE
-- ════════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) Appointments read policy aligned with requester field
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Related users can read appointments" ON appointments;
CREATE POLICY "Related users can read appointments" ON appointments
  FOR SELECT USING (
    auth.uid() = own_id
    OR auth.uid() = bkr_id
    OR auth.uid() = req_uid
    OR EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role >= 2)
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) READ RPCs (SECURITY DEFINER — bypass RLS safely)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION get_offer_by_id_internal(
  p_offer_id UUID,
  p_user_uid UUID DEFAULT NULL
)
RETURNS SETOF offers AS $$
DECLARE
  v_role INT := 0;
BEGIN
  IF p_user_uid IS NOT NULL AND auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  IF p_user_uid IS NOT NULL THEN
    SELECT COALESCE(role, 0) INTO v_role FROM users WHERE id = p_user_uid AND i_del = 0;
  END IF;

  RETURN QUERY
  SELECT *
  FROM offers
  WHERE id = p_offer_id
    AND i_del = 0
    AND (
      i_pub = 1
      OR (p_user_uid IS NOT NULL AND usr_id = p_user_uid)
      OR (p_user_uid IS NOT NULL AND v_role >= 2)
    )
  LIMIT 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_user_offers_internal(p_user_uid UUID)
RETURNS SETOF offers AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  RETURN QUERY
  SELECT * FROM offers
  WHERE usr_id = p_user_uid
    AND i_del = 0
  ORDER BY ts_crt DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_user_requests_internal(p_user_uid UUID)
RETURNS SETOF requests AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  RETURN QUERY
  SELECT * FROM requests
  WHERE usr_id = p_user_uid
    AND i_del = 0
  ORDER BY ts_crt DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_user_payments_internal(p_user_uid UUID)
RETURNS SETOF payments AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  RETURN QUERY
  SELECT * FROM payments
  WHERE uid = p_user_uid
  ORDER BY ts_crt DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_user_notifications_internal(p_user_uid UUID)
RETURNS SETOF notifications AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  RETURN QUERY
  SELECT * FROM notifications
  WHERE uid = p_user_uid
    AND i_del = 0
  ORDER BY ts_crt DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_user_appointments_internal(p_user_uid UUID)
RETURNS SETOF appointments AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  RETURN QUERY
  SELECT * FROM appointments
  WHERE req_uid = p_user_uid
  ORDER BY dt ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_owner_appointments_internal(p_owner_uid UUID)
RETURNS SETOF appointments AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_owner_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  RETURN QUERY
  SELECT * FROM appointments
  WHERE own_id = p_owner_uid
  ORDER BY dt ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_broker_offers_internal(p_broker_uid UUID)
RETURNS SETOF offers AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_broker_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  RETURN QUERY
  SELECT * FROM offers
  WHERE i_del = 0
    AND (usr_id = p_broker_uid OR brk_id = p_broker_uid)
  ORDER BY ts_crt DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_broker_appointments_internal(p_broker_uid UUID)
RETURNS SETOF appointments AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_broker_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  RETURN QUERY
  SELECT DISTINCT a.*
  FROM appointments a
  LEFT JOIN offers o ON o.id = a.off_id
  WHERE a.bkr_id = p_broker_uid
     OR a.own_id = p_broker_uid
     OR o.usr_id = p_broker_uid
  ORDER BY dt ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_broker_deals_internal(p_broker_uid UUID)
RETURNS SETOF deals AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_broker_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  RETURN QUERY
  SELECT * FROM deals
  WHERE brk_uid = p_broker_uid
    AND i_del = 0
  ORDER BY ts_crt DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_admin_pending_offers_internal(p_admin_uid UUID)
RETURNS SETOF offers AS $$
DECLARE
  v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 2 THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  RETURN QUERY
  SELECT * FROM offers
  WHERE sts = 1
    AND i_del = 0
  ORDER BY ts_crt DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_admin_offers_internal(p_admin_uid UUID, p_limit INT DEFAULT 100)
RETURNS SETOF offers AS $$
DECLARE
  v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 2 THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  RETURN QUERY
  SELECT * FROM offers
  WHERE i_del = 0
  ORDER BY ts_crt DESC
  LIMIT GREATEST(COALESCE(p_limit, 100), 1);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_admin_appointments_internal(p_admin_uid UUID)
RETURNS SETOF appointments AS $$
DECLARE
  v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 2 THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  RETURN QUERY SELECT * FROM appointments ORDER BY dt DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_admin_deals_internal(p_admin_uid UUID)
RETURNS SETOF deals AS $$
DECLARE
  v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 2 THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  RETURN QUERY SELECT * FROM deals WHERE i_del = 0 ORDER BY ts_crt DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_admin_payments_internal(p_admin_uid UUID)
RETURNS SETOF payments AS $$
DECLARE
  v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 2 THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  RETURN QUERY SELECT * FROM payments ORDER BY ts_crt DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_admin_reports_internal(p_admin_uid UUID)
RETURNS SETOF reports AS $$
DECLARE
  v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 2 THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  RETURN QUERY SELECT * FROM reports ORDER BY ts_crt DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) WRITE RPCs
-- ─────────────────────────────────────────────────────────────────────────────

-- FIX #1: offers has no ts_upd → removed from SET clause
CREATE OR REPLACE FUNCTION admin_review_offer_internal(
  p_admin_uid UUID,
  p_offer_id UUID,
  p_approve BOOLEAN,
  p_reason TEXT DEFAULT ''
)
RETURNS BOOLEAN AS $$
DECLARE
  v_role INT;
  v_owner_uid UUID;
  v_now TIMESTAMPTZ := NOW();
  v_rejected_count INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 2 THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  SELECT usr_id INTO v_owner_uid FROM offers WHERE id = p_offer_id AND i_del = 0;
  IF v_owner_uid IS NULL THEN
    RAISE EXCEPTION 'OFFER_NOT_FOUND';
  END IF;

  -- FIX: offers has no ts_upd column
  UPDATE offers
  SET sts    = CASE WHEN p_approve THEN 2 ELSE 3 END,
      i_pub  = CASE WHEN p_approve THEN 1 ELSE 0 END,
      rsn    = CASE WHEN p_approve THEN '' ELSE COALESCE(p_reason, '') END,
      ts_pub = CASE WHEN p_approve THEN v_now ELSE NULL END
  WHERE id = p_offer_id;

  IF NOT p_approve THEN
    SELECT COUNT(*) INTO v_rejected_count
    FROM offers
    WHERE usr_id = v_owner_uid
      AND sts = 3
      AND ts_crt >= NOW() - INTERVAL '30 days';
    IF v_rejected_count > 0 AND MOD(v_rejected_count, 3) = 0 THEN
      PERFORM add_points(v_owner_uid, -1000);
    END IF;
  END IF;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION create_request_internal(
  p_user_uid UUID,
  p_request JSONB
)
RETURNS SETOF requests AS $$
DECLARE
  v_user users%ROWTYPE;
  v_config JSONB;
  v_limit INT;
  v_used INT;
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

  IF COALESCE(v_user.role, 0) < 2 THEN
    SELECT value INTO v_config FROM app_config WHERE key = 'main';
    v_limit := CASE WHEN COALESCE(v_user.role, 0) = 1
      THEN COALESCE((v_config->'qta'->'b'->>'r')::INT, 5)
      ELSE COALESCE((v_config->'qta'->'u'->>'r')::INT, 3)
    END;

    SELECT COUNT(*) INTO v_used
    FROM requests
    WHERE usr_id = p_user_uid AND i_del = 0;

    IF COALESCE(v_used, 0) >= COALESCE(v_limit, 3) THEN
      RAISE EXCEPTION 'QUOTA_EXCEEDED';
    END IF;
  END IF;

  RETURN QUERY
  INSERT INTO requests (
    typ, elm, cl_nm, cl_ph, prc, cur, notes, specs,
    usr_id, sts, matches, i_del, ts_crt
  ) VALUES (
    COALESCE((p_request->>'typ')::INT, 0),
    COALESCE((p_request->>'elm')::INT, 0),
    COALESCE(p_request->>'cl_nm', ''),
    COALESCE(p_request->>'cl_ph', ''),
    COALESCE((p_request->>'prc')::NUMERIC, 0),
    COALESCE((p_request->>'cur')::INT, 1),
    COALESCE(p_request->>'notes', ''),
    COALESCE(p_request->'specs', '{}'::jsonb),
    p_user_uid,
    0,
    COALESCE(p_request->'matches', '{}'::jsonb),
    0,
    NOW()
  ) RETURNING *;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION update_request_internal(
  p_user_uid UUID,
  p_request_id UUID,
  p_patch JSONB
)
RETURNS BOOLEAN AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  -- requests has no ts_upd column, not needed
  UPDATE requests
  SET typ   = COALESCE((p_patch->>'typ')::INT, typ),
      elm   = COALESCE((p_patch->>'elm')::INT, elm),
      cl_nm = COALESCE(NULLIF(p_patch->>'cl_nm', ''), cl_nm),
      cl_ph = COALESCE(NULLIF(p_patch->>'cl_ph', ''), cl_ph),
      prc   = COALESCE((p_patch->>'prc')::NUMERIC, prc),
      cur   = COALESCE((p_patch->>'cur')::INT, cur),
      notes = COALESCE(p_patch->>'notes', notes),
      specs = COALESCE(p_patch->'specs', specs)
  WHERE id     = p_request_id
    AND usr_id = p_user_uid
    AND i_del  = 0;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'REQUEST_NOT_FOUND_OR_NOT_ALLOWED';
  END IF;
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION soft_delete_request_internal(
  p_user_uid UUID,
  p_request_id UUID
)
RETURNS BOOLEAN AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  UPDATE requests
  SET i_del = 1
  WHERE id     = p_request_id
    AND usr_id = p_user_uid
    AND i_del  = 0;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'REQUEST_NOT_FOUND_OR_NOT_ALLOWED';
  END IF;
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- FIX #4: payments has no ts_upd → removed from SET clause
CREATE OR REPLACE FUNCTION create_payment_internal(
  p_user_uid UUID,
  p_payment JSONB
)
RETURNS SETOF payments AS $$
DECLARE
  v_user users%ROWTYPE;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT * INTO v_user FROM users WHERE id = p_user_uid AND i_del = 0 AND sts = 0;
  IF v_user.id IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_ACTIVE_OR_NOT_FOUND';
  END IF;

  IF COALESCE(trim(p_payment->>'proof'), '') = '' OR COALESCE(trim(p_payment->>'ref'), '') = '' THEN
    RAISE EXCEPTION 'MISSING_PAYMENT_PROOF_OR_REFERENCE';
  END IF;

  RETURN QUERY
  INSERT INTO payments (
    uid, tp, pkg, amt, cur, mtd, channel, proof, ref, sts, appr_by, ts_crt
  ) VALUES (
    p_user_uid,
    COALESCE((p_payment->>'tp')::INT, 0),
    COALESCE((p_payment->>'pkg')::INT, 0),
    COALESCE((p_payment->>'amt')::NUMERIC, 0),
    COALESCE((p_payment->>'cur')::INT, 1),
    COALESCE((p_payment->>'mtd')::INT, 0),
    COALESCE(p_payment->>'channel', ''),
    COALESCE(p_payment->>'proof', ''),
    COALESCE(p_payment->>'ref', ''),
    0,
    NULL,
    NOW()
  ) RETURNING *;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- FIX #4: payments has no ts_upd → removed from SET clause
CREATE OR REPLACE FUNCTION admin_reject_payment_internal(
  p_admin_uid UUID,
  p_payment_id UUID
)
RETURNS BOOLEAN AS $$
DECLARE
  v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 2 THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  -- FIX: payments has no ts_upd column
  UPDATE payments
  SET sts     = 2,
      appr_by = p_admin_uid
  WHERE id  = p_payment_id
    AND sts = 0;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PAYMENT_NOT_PENDING_OR_NOT_FOUND';
  END IF;
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION create_report_internal(
  p_reporter_uid UUID,
  p_report JSONB
)
RETURNS SETOF reports AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_reporter_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  RETURN QUERY
  INSERT INTO reports (
    rep_uid, tgt_uid, tgt_tp, tgt_id, rsn, det, sts, act, act_dur, note, act_by, ts_crt
  ) VALUES (
    p_reporter_uid,
    NULLIF(p_report->>'tgt_uid', '')::UUID,
    COALESCE((p_report->>'tgt_tp')::INT, 0),
    COALESCE(p_report->>'tgt_id', ''),
    COALESCE((p_report->>'rsn')::INT, 0),
    COALESCE(p_report->>'det', ''),
    0,
    0,
    0,
    '',
    NULL,
    NOW()
  ) RETURNING *;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION admin_handle_report_internal(
  p_admin_uid UUID,
  p_report_id UUID,
  p_action INT,
  p_note TEXT DEFAULT '',
  p_duration INT DEFAULT 0
)
RETURNS BOOLEAN AS $$
DECLARE
  v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 2 THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  UPDATE reports
  SET sts     = 1,
      act     = COALESCE(p_action, 0),
      act_dur = COALESCE(p_duration, 0),
      note    = COALESCE(p_note, ''),
      act_by  = p_admin_uid
  WHERE id = p_report_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'REPORT_NOT_FOUND';
  END IF;
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- FIX #2: offers.brk_id is UUID → NULLIF(brk_id,'') is invalid type; use brk_id directly
CREATE OR REPLACE FUNCTION book_appointment_internal(
  p_user_uid UUID,
  p_offer_id UUID,
  p_dt TIMESTAMPTZ,
  p_broker_id UUID DEFAULT NULL,
  p_request_id UUID DEFAULT NULL
)
RETURNS SETOF appointments AS $$
DECLARE
  v_offer offers%ROWTYPE;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT * INTO v_offer FROM offers WHERE id = p_offer_id AND i_del = 0;
  IF v_offer.id IS NULL THEN
    RAISE EXCEPTION 'OFFER_NOT_FOUND';
  END IF;
  IF p_user_uid = v_offer.usr_id THEN
    RAISE EXCEPTION 'CANNOT_BOOK_OWN_OFFER';
  END IF;
  IF p_dt <= NOW() THEN
    RAISE EXCEPTION 'INVALID_APPOINTMENT_TIME';
  END IF;
  IF EXISTS (
    SELECT 1 FROM appointments
    WHERE off_id  = p_offer_id
      AND req_uid = p_user_uid
      AND dt      = p_dt
      AND sts IN (0, 1)
  ) THEN
    RAISE EXCEPTION 'DUPLICATE_APPOINTMENT';
  END IF;

  RETURN QUERY
  INSERT INTO appointments (
    off_id, req_id, req_uid, own_id, bkr_id, dt, sts,
    fbk_own, fbk_req, i_force, rmnd_24, rmnd_2, rmnd_qtr, rmnd_end, ts_crt
  ) VALUES (
    p_offer_id,
    p_request_id,
    p_user_uid,
    v_offer.usr_id,
    -- FIX: brk_id is UUID, use COALESCE directly without NULLIF text trick
    COALESCE(p_broker_id, v_offer.brk_id),
    p_dt,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    NOW()
  ) RETURNING *;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION cancel_appointment_internal(
  p_requester_uid UUID,
  p_appointment_id UUID,
  p_reason TEXT DEFAULT ''
)
RETURNS BOOLEAN AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_requester_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  UPDATE appointments
  SET sts     = 3,
      cnl_by  = p_requester_uid,
      cnl_rsn = COALESCE(p_reason, ''),
      dt_end  = NOW()
  WHERE id      = p_appointment_id
    AND req_uid = p_requester_uid
    AND sts IN (0, 1);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'APPOINTMENT_NOT_FOUND_OR_NOT_ALLOWED';
  END IF;
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION broker_handle_appointment_internal(
  p_broker_uid UUID,
  p_appointment_id UUID,
  p_action TEXT
)
RETURNS BOOLEAN AS $$
DECLARE
  v_allowed BOOLEAN := FALSE;
  v_now TIMESTAMPTZ := NOW();
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_broker_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM appointments a
    LEFT JOIN offers o ON o.id = a.off_id
    WHERE a.id = p_appointment_id
      AND (a.bkr_id = p_broker_uid OR a.own_id = p_broker_uid OR o.usr_id = p_broker_uid)
  ) INTO v_allowed;

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'APPOINTMENT_NOT_FOUND_OR_NOT_ALLOWED';
  END IF;

  IF p_action = 'confirm' THEN
    UPDATE appointments
    SET sts        = 1,
        fbk_own    = 1,
        fbk_own_dt = v_now
    WHERE id = p_appointment_id;
  ELSIF p_action = 'reject' THEN
    UPDATE appointments
    SET sts        = 4,
        fbk_own    = 2,
        fbk_own_dt = v_now,
        dt_end     = v_now
    WHERE id = p_appointment_id;
  ELSIF p_action = 'complete' THEN
    UPDATE appointments
    SET sts    = 2,
        dt_end = v_now
    WHERE id = p_appointment_id;
  ELSE
    RAISE EXCEPTION 'INVALID_ACTION';
  END IF;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION admin_update_appointment_status_internal(
  p_admin_uid UUID,
  p_appointment_id UUID,
  p_status INT,
  p_admin_note TEXT DEFAULT ''
)
RETURNS BOOLEAN AS $$
DECLARE
  v_role INT;
  v_requester_uid UUID;
  v_cancel_count INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 2 THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  SELECT req_uid INTO v_requester_uid FROM appointments WHERE id = p_appointment_id;

  UPDATE appointments
  SET sts      = p_status,
      admin_nt = CASE WHEN COALESCE(trim(p_admin_note), '') = '' THEN admin_nt ELSE p_admin_note END,
      dt_end   = CASE WHEN p_status >= 2 THEN NOW() ELSE dt_end END
  WHERE id = p_appointment_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'APPOINTMENT_NOT_FOUND';
  END IF;

  IF p_status = 5 AND v_requester_uid IS NOT NULL THEN
    PERFORM add_points(v_requester_uid, -500);
  ELSIF p_status = 3 AND v_requester_uid IS NOT NULL THEN
    SELECT COUNT(*) INTO v_cancel_count
    FROM appointments
    WHERE req_uid = v_requester_uid
      AND sts     = 3
      AND ts_crt >= NOW() - INTERVAL '30 days';
    IF v_cancel_count > 0 AND MOD(v_cancel_count, 3) = 0 THEN
      PERFORM add_points(v_requester_uid, -300);
    END IF;
  END IF;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION admin_force_appointment_internal(
  p_admin_uid UUID,
  p_appointment_id UUID
)
RETURNS BOOLEAN AS $$
DECLARE
  v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 2 THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  UPDATE appointments
  SET i_force  = 1,
      force_by = p_admin_uid,
      sts      = 1
  WHERE id = p_appointment_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'APPOINTMENT_NOT_FOUND';
  END IF;
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION create_deal_internal(
  p_admin_uid UUID,
  p_deal JSONB
)
RETURNS SETOF deals AS $$
DECLARE
  v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 2 THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  RETURN QUERY
  INSERT INTO deals (
    off_id, app_id, sell_uid, buy_uid, brk_uid, fin_prc, cur,
    com_pct, com_val, com_note, form, sts, cmpl_by, i_del, ts_crt, ts_cmpl
  ) VALUES (
    NULLIF(p_deal->>'off_id',   '')::UUID,
    NULLIF(p_deal->>'app_id',   '')::UUID,
    NULLIF(p_deal->>'sell_uid', '')::UUID,
    NULLIF(p_deal->>'buy_uid',  '')::UUID,
    NULLIF(p_deal->>'brk_uid',  '')::UUID,
    COALESCE((p_deal->>'fin_prc')::NUMERIC, 0),
    COALESCE((p_deal->>'cur')::INT, 1),
    COALESCE((p_deal->>'com_pct')::NUMERIC, 0),
    COALESCE((p_deal->>'com_val')::NUMERIC, 0),
    NULLIF(p_deal->>'com_note', ''),
    COALESCE(p_deal->'form', '{}'::jsonb),
    COALESCE((p_deal->>'sts')::INT, 0),
    NULL,
    0,
    NOW(),
    NULL
  ) RETURNING *;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION complete_deal_internal(
  p_admin_uid UUID,
  p_deal_id UUID,
  p_commission NUMERIC DEFAULT NULL,
  p_note TEXT DEFAULT NULL
)
RETURNS BOOLEAN AS $$
DECLARE
  v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 2 THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  UPDATE deals
  SET sts      = 1,
      cmpl_by  = p_admin_uid,
      ts_cmpl  = NOW(),
      com_val  = COALESCE(p_commission, com_val),
      com_note = COALESCE(p_note, com_note)
  WHERE id    = p_deal_id
    AND i_del = 0;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'DEAL_NOT_FOUND';
  END IF;
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION mark_notification_read_internal(
  p_user_uid UUID,
  p_notification_id UUID
)
RETURNS BOOLEAN AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  UPDATE notifications
  SET i_rd = 1
  WHERE id  = p_notification_id
    AND uid = p_user_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOTIFICATION_NOT_FOUND_OR_NOT_ALLOWED';
  END IF;
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION mark_all_notifications_read_internal(p_user_uid UUID)
RETURNS BOOLEAN AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  UPDATE notifications
  SET i_rd = 1
  WHERE uid  = p_user_uid
    AND i_rd = 0;
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION create_rating_internal(
  p_reviewer_uid UUID,
  p_target_uid UUID,
  p_stars INT,
  p_comment TEXT DEFAULT ''
)
RETURNS BOOLEAN AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_reviewer_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  INSERT INTO ratings (reviewer_uid, target_uid, stars, comment)
  VALUES (p_reviewer_uid, p_target_uid, p_stars, COALESCE(p_comment, ''));
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION register_daily_streak_internal(
  p_user_uid UUID,
  p_points INT DEFAULT 50
)
RETURNS JSONB AS $$
DECLARE
  v_current_streak INT := 0;
  v_last_ts TIMESTAMPTZ;
  v_now TIMESTAMPTZ := NOW();
  v_today TEXT;
  v_last_day TEXT;
  v_new_streak INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT COALESCE(strk, 0), strk_dt INTO v_current_streak, v_last_ts
  FROM users
  WHERE id    = p_user_uid
    AND i_del = 0;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;

  v_today := to_char((v_now AT TIME ZONE 'UTC' + INTERVAL '3 hours')::date, 'YYYY-MM-DD');
  IF v_last_ts IS NOT NULL THEN
    v_last_day := to_char((v_last_ts AT TIME ZONE 'UTC' + INTERVAL '3 hours')::date, 'YYYY-MM-DD');
  END IF;

  IF v_last_day = v_today THEN
    RETURN jsonb_build_object('streak', v_current_streak, 'changed', false, 'awarded', false);
  END IF;

  v_new_streak := CASE WHEN v_last_day IS NULL THEN 1 ELSE v_current_streak + 1 END;

  UPDATE users
  SET strk    = v_new_streak,
      strk_dt = v_now,
      ts_upd  = v_now
  WHERE id = p_user_uid;

  PERFORM add_points(p_user_uid, p_points);

  RETURN jsonb_build_object('streak', v_new_streak, 'changed', true, 'awarded', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION update_user_profile_internal(
  p_user_uid UUID,
  p_payload JSONB
)
RETURNS BOOLEAN AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  UPDATE users
  SET nm     = COALESCE(p_payload->>'nm',  nm),
      sid    = COALESCE(p_payload->>'sid', sid),
      ad     = COALESCE(p_payload->>'ad',  ad),
      img    = COALESCE(p_payload->>'img', img),
      ts_upd = NOW()
  WHERE id    = p_user_uid
    AND i_del = 0;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION update_user_notification_settings_internal(
  p_user_uid UUID,
  p_ntf JSONB
)
RETURNS BOOLEAN AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  IF jsonb_typeof(COALESCE(p_ntf, '{}'::jsonb)) <> 'object' THEN
    RAISE EXCEPTION 'INVALID_NOTIFICATION_SETTINGS';
  END IF;

  UPDATE users
  SET ntf    = p_ntf,
      ts_upd = NOW()
  WHERE id    = p_user_uid
    AND i_del = 0;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- FIX #3: activity_log uses act(INT) and det(TEXT), not action(TEXT) and details(JSONB)
--         broker_request mapped to act = 10 (reserved code for broker requests)
CREATE OR REPLACE FUNCTION submit_broker_request_internal(
  p_user_uid UUID,
  p_business_name TEXT,
  p_category INT,
  p_experience TEXT DEFAULT '',
  p_about TEXT DEFAULT ''
)
RETURNS BOOLEAN AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  UPDATE users
  SET brk_nm = COALESCE(p_business_name, ''),
      brk_cls = COALESCE(p_category, 0),
      vrf     = CASE WHEN vrf = 0 THEN 1 ELSE vrf END,
      ts_upd  = NOW()
  WHERE id    = p_user_uid
    AND i_del = 0;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;

  -- FIX: activity_log schema → act INT, det TEXT (not action TEXT / details JSONB)
  -- act = 10 reserved for broker_request events
  INSERT INTO activity_log (uid, act, det, ts_crt)
  VALUES (
    p_user_uid,
    10,
    'broker_request: ' || COALESCE(p_business_name, '') ||
      ' cat=' || COALESCE(p_category::TEXT, '0') ||
      CASE WHEN COALESCE(trim(p_experience), '') <> ''
           THEN ' exp=' || p_experience ELSE '' END,
    NOW()
  );

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- FIX #1: offers has no ts_upd column → removed from SET clause
CREATE OR REPLACE FUNCTION mark_social_published_internal(
  p_user_uid UUID,
  p_offer_id UUID,
  p_text TEXT
)
RETURNS BOOLEAN AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  -- FIX: offers has no ts_upd column
  UPDATE offers
  SET soc_pub = 1,
      soc_txt = COALESCE(p_text, '')
  WHERE id     = p_offer_id
    AND usr_id = p_user_uid
    AND i_del  = 0;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'OFFER_NOT_FOUND_OR_NOT_ALLOWED';
  END IF;
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION increment_offer_views_internal(p_offer_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  UPDATE offers
  SET vws = COALESCE(vws, 0) + 1
  WHERE id    = p_offer_id
    AND i_del = 0
    AND i_pub = 1;
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4) GRANTS
-- ─────────────────────────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION get_offer_by_id_internal(UUID, UUID)                          TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_user_offers_internal(UUID)                                 TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_user_requests_internal(UUID)                               TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_user_payments_internal(UUID)                               TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_user_notifications_internal(UUID)                          TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_user_appointments_internal(UUID)                           TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_owner_appointments_internal(UUID)                          TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_broker_offers_internal(UUID)                               TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_broker_appointments_internal(UUID)                         TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_broker_deals_internal(UUID)                                TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_admin_pending_offers_internal(UUID)                        TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_admin_offers_internal(UUID, INT)                           TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_admin_appointments_internal(UUID)                          TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_admin_deals_internal(UUID)                                 TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_admin_payments_internal(UUID)                              TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_admin_reports_internal(UUID)                               TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_review_offer_internal(UUID, UUID, BOOLEAN, TEXT)         TO anon, authenticated;
GRANT EXECUTE ON FUNCTION create_request_internal(UUID, JSONB)                           TO anon, authenticated;
GRANT EXECUTE ON FUNCTION update_request_internal(UUID, UUID, JSONB)                     TO anon, authenticated;
GRANT EXECUTE ON FUNCTION soft_delete_request_internal(UUID, UUID)                       TO anon, authenticated;
GRANT EXECUTE ON FUNCTION create_payment_internal(UUID, JSONB)                           TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_reject_payment_internal(UUID, UUID)                      TO anon, authenticated;
GRANT EXECUTE ON FUNCTION create_report_internal(UUID, JSONB)                            TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_handle_report_internal(UUID, UUID, INT, TEXT, INT)       TO anon, authenticated;
GRANT EXECUTE ON FUNCTION book_appointment_internal(UUID, UUID, TIMESTAMPTZ, UUID, UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION cancel_appointment_internal(UUID, UUID, TEXT)                  TO anon, authenticated;
GRANT EXECUTE ON FUNCTION broker_handle_appointment_internal(UUID, UUID, TEXT)           TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_update_appointment_status_internal(UUID, UUID, INT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_force_appointment_internal(UUID, UUID)                   TO anon, authenticated;
GRANT EXECUTE ON FUNCTION create_deal_internal(UUID, JSONB)                              TO anon, authenticated;
GRANT EXECUTE ON FUNCTION complete_deal_internal(UUID, UUID, NUMERIC, TEXT)              TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mark_notification_read_internal(UUID, UUID)                    TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mark_all_notifications_read_internal(UUID)                     TO anon, authenticated;
GRANT EXECUTE ON FUNCTION create_rating_internal(UUID, UUID, INT, TEXT)                  TO anon, authenticated;
GRANT EXECUTE ON FUNCTION register_daily_streak_internal(UUID, INT)                      TO anon, authenticated;
GRANT EXECUTE ON FUNCTION update_user_profile_internal(UUID, JSONB)                      TO anon, authenticated;
GRANT EXECUTE ON FUNCTION update_user_notification_settings_internal(UUID, JSONB)        TO anon, authenticated;
GRANT EXECUTE ON FUNCTION submit_broker_request_internal(UUID, TEXT, INT, TEXT, TEXT)    TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mark_social_published_internal(UUID, UUID, TEXT)               TO anon, authenticated;
GRANT EXECUTE ON FUNCTION increment_offer_views_internal(UUID)                           TO anon, authenticated;
