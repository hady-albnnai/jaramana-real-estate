-- ════════════════════════════════════════════════════════════════════════════
-- إصلاح: notifications.typ → notifications.tp في كل الدوال
-- العمود الفعلي بالجدول اسمه tp وليس typ
-- ════════════════════════════════════════════════════════════════════════════

-- 1. trg_offer_status_changed
CREATE OR REPLACE FUNCTION trg_offer_status_changed()
RETURNS TRIGGER AS $$
DECLARE
  v_offer_title TEXT;
  v_offer_num TEXT;
  v_title TEXT;
  v_body TEXT;
  v_type INT;
BEGIN
  IF NEW.sts = OLD.sts THEN RETURN NEW; END IF;
  v_offer_title := COALESCE(NEW.ttl, 'عرض');
  v_offer_num := COALESCE(NEW.offer_number::TEXT, '');

  IF NEW.sts = 2 AND OLD.sts = 1 THEN
    v_title := '✅ تم نشر العرض الخاص بك';
    v_body := 'تمت الموافقة على العرض رقم ' || v_offer_num || ' — "' || v_offer_title || '" وهو متاح الآن للجمهور.';
    v_type := 0;
  ELSIF NEW.sts = 3 AND OLD.sts = 1 THEN
    v_title := '❌ تم رفض العرض الخاص بك';
    v_body := 'العرض رقم ' || v_offer_num || ' — "' || v_offer_title || '" مرفوض. السبب: ' || COALESCE(NEW.rsn, 'غير محدد');
    v_type := 0;
  ELSIF NEW.sts = 4 AND OLD.sts = 2 THEN
    v_title := '⏰ انتهت صلاحية العرض الخاص بك';
    v_body := 'العرض رقم ' || v_offer_num || ' — "' || v_offer_title || '" انتهت مدته. يمكنك تجديده بالنقاط.';
    v_type := 0;
  ELSIF NEW.sts = 5 AND OLD.sts = 2 THEN
    v_title := '🔒 العرض الخاص بك محجوز';
    v_body := 'تم حجز العرض رقم ' || v_offer_num || ' — "' || v_offer_title || '" بانتظار إتمام الصفقة.';
    v_type := 0;
  ELSE
    RETURN NEW;
  END IF;

  INSERT INTO notifications (uid, tp, ttl, bdy, ref_id, ts_crt)
  VALUES (NEW.usr_id, v_type, v_title, v_body, NEW.id, NOW());
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. process_completion_request
DROP FUNCTION IF EXISTS process_completion_request(UUID, UUID, TEXT, TEXT);
CREATE OR REPLACE FUNCTION process_completion_request(
  p_admin_uid UUID, p_request_id UUID, p_decision TEXT, p_office_notes TEXT DEFAULT ''
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_role INT; v_req RECORD; v_off_id UUID;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 4 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  SELECT * INTO v_req FROM completion_requests WHERE id = p_request_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND'; END IF;
  IF v_req.decision <> 'pending' THEN RAISE EXCEPTION 'REQUEST_ALREADY_PROCESSED'; END IF;

  UPDATE completion_requests SET decision = p_decision, decided_by = p_admin_uid,
    office_notes = COALESCE(p_office_notes, ''), ts_decided = NOW() WHERE id = p_request_id;
  SELECT off_id INTO v_off_id FROM appointments WHERE id = v_req.app_id;

  IF p_decision = 'approved' THEN
    UPDATE appointments SET sts = 2 WHERE id = v_req.app_id AND sts <> 2;
    UPDATE offers SET sts = 5, i_pub = 0 WHERE id = v_off_id AND sts IN (2, 5);
    UPDATE appointments SET sts = 3, cnl_rsn = 'تم إتمام معاملة على هذا العرض', dt_end = NOW()
      WHERE off_id = v_off_id AND id <> v_req.app_id AND sts IN (0, 1);
    INSERT INTO notifications (uid, tp, ttl, bdy, ref_id, ts_crt)
      SELECT a.req_uid, 0, 'تم إلغاء موعدك', 'تم إلغاء موعدك لأن العرض اكتمل بمعاملة أخرى.', a.id, NOW()
      FROM appointments a WHERE a.off_id = v_off_id AND a.id <> v_req.app_id AND a.sts = 3
        AND a.cnl_rsn = 'تم إتمام معاملة على هذا العرض';
  ELSIF p_decision = 'rejected' THEN
    UPDATE appointments SET sts = 4, outcome = 'reject' WHERE id = v_req.app_id;
    UPDATE offers SET sts = 2, i_pub = 1 WHERE id = v_off_id AND sts = 5;
  END IF;

  INSERT INTO notifications (uid, tp, ttl, bdy, ref_id, ts_crt) VALUES (
    v_req.req_by, 20,
    CASE WHEN p_decision = 'approved' THEN 'تمت الموافقة على طلب الإتمام' ELSE 'تم رفض طلب الإتمام' END,
    CASE WHEN p_decision = 'approved' THEN 'تمت الموافقة على طلب إتمام المعاملة ✓'
         ELSE 'تم رفض طلب الإتمام: ' || COALESCE(p_office_notes, '') END,
    v_req.app_id, NOW());
  RETURN TRUE;
END; $$;
GRANT EXECUTE ON FUNCTION process_completion_request(UUID, UUID, TEXT, TEXT) TO anon, authenticated;

-- 3. request_completion_by_appointment
DROP FUNCTION IF EXISTS request_completion_by_appointment(UUID, UUID, TEXT);
CREATE OR REPLACE FUNCTION request_completion_by_appointment(
  p_user_uid UUID, p_appointment_id UUID, p_notes TEXT DEFAULT ''
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_appt RECORD; v_existing INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT * INTO v_appt FROM appointments WHERE id = p_appointment_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'APPOINTMENT_NOT_FOUND'; END IF;
  IF v_appt.supervisor_uid <> p_user_uid THEN RAISE EXCEPTION 'NOT_YOUR_TASK'; END IF;
  SELECT COUNT(*) INTO v_existing FROM completion_requests WHERE app_id = p_appointment_id AND decision = 'pending';
  IF v_existing > 0 THEN RAISE EXCEPTION 'يوجد طلب إتمام معلق مسبقاً'; END IF;

  UPDATE appointments SET outcome = 'accept', executor_notes = COALESCE(p_notes, ''),
    completion_date = NOW(), sts = CASE WHEN sts IN (0, 1) THEN 2 ELSE sts END WHERE id = p_appointment_id;
  INSERT INTO completion_requests (app_id, req_by, notes) VALUES (p_appointment_id, p_user_uid, COALESCE(p_notes, ''));

  INSERT INTO notifications (uid, tp, ttl, bdy, ref_id, ts_crt)
    SELECT u.id, 20, 'طلب إتمام معاملة', 'المنفذ أرسل طلب إتمام لموعد — يرجى المراجعة',
      p_appointment_id, NOW() FROM users u WHERE u.role >= 4 AND u.sts = 0 AND u.i_del = 0;
  RETURN TRUE;
END; $$;
GRANT EXECUTE ON FUNCTION request_completion_by_appointment(UUID, UUID, TEXT) TO anon, authenticated;

-- 4. admin_approve_verification_by_admin
DROP FUNCTION IF EXISTS admin_approve_verification_by_admin(UUID, UUID);
CREATE OR REPLACE FUNCTION admin_approve_verification_by_admin(
  p_admin_uid UUID, p_target_uid UUID
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 3 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  UPDATE users SET vrf = 2, ts_upd = NOW() WHERE id = p_target_uid AND i_del = 0 AND vrf = 1;
  IF FOUND THEN
    INSERT INTO notifications (uid, tp, ttl, bdy, ts_crt)
    VALUES (p_target_uid, 10, 'تم اعتماد توثيقك', 'تهانينا! تم اعتماد حسابك رسمياً ✓', NOW());
  END IF;
  RETURN FOUND;
END; $$;
GRANT EXECUTE ON FUNCTION admin_approve_verification_by_admin(UUID, UUID) TO anon, authenticated;

-- 5. admin_reject_verification_by_admin
DROP FUNCTION IF EXISTS admin_reject_verification_by_admin(UUID, UUID, TEXT);
CREATE OR REPLACE FUNCTION admin_reject_verification_by_admin(
  p_admin_uid UUID, p_target_uid UUID, p_reason TEXT DEFAULT ''
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 3 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  UPDATE users SET vrf = 0, ts_upd = NOW() WHERE id = p_target_uid AND i_del = 0;
  IF FOUND THEN
    INSERT INTO notifications (uid, tp, ttl, bdy, ts_crt)
    VALUES (p_target_uid, 10, 'تم رفض طلب التوثيق', COALESCE(NULLIF(p_reason,''), 'لم يتم قبول الوثائق المرفقة'), NOW());
  END IF;
  RETURN FOUND;
END; $$;
GRANT EXECUTE ON FUNCTION admin_reject_verification_by_admin(UUID, UUID, TEXT) TO anon, authenticated;
