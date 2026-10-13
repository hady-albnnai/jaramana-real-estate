-- ════════════════════════════════════════════════════════════════════════════
-- إعادة هيكلة الأدوار — النسخة النهائية المصحّحة
-- نفّذ هذا الملف مرة واحدة في Supabase SQL Editor
-- ════════════════════════════════════════════════════════════════════════════

-- ── 0. توسيع CHECK CONSTRAINT ──
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check;
ALTER TABLE users ADD CONSTRAINT users_role_check CHECK (role >= 0 AND role <= 6);

-- ── 1. ترقية الأدوار ──
UPDATE users SET role = 6 WHERE role = 4 AND i_del = 0;
UPDATE users SET role = 5 WHERE role = 3 AND i_del = 0;
UPDATE users SET role = 4 WHERE role = 2 AND i_del = 0;
UPDATE users SET role = 2 WHERE perm::text LIKE '%photographer_tasks%' AND role < 2 AND i_del = 0;

-- ── 2. حذف الدوال (كل التوقيعات الممكنة) ──
DROP FUNCTION IF EXISTS admin_update_user_role(uuid, uuid, int);
DROP FUNCTION IF EXISTS admin_set_user_status(uuid, uuid, int, text);
DROP FUNCTION IF EXISTS admin_update_user_permissions_by_admin(uuid, uuid, jsonb);
DROP FUNCTION IF EXISTS get_admin_pending_offers_internal(uuid);
DROP FUNCTION IF EXISTS get_admin_offers_internal(uuid, int);
DROP FUNCTION IF EXISTS get_admin_appointments_internal(uuid);
DROP FUNCTION IF EXISTS get_admin_deals_internal(uuid);
DROP FUNCTION IF EXISTS get_admin_payments_internal(uuid);
DROP FUNCTION IF EXISTS get_admin_reports_internal(uuid);
DROP FUNCTION IF EXISTS get_admin_requests_internal(uuid);
DROP FUNCTION IF EXISTS admin_review_offer_internal(uuid, uuid, boolean, text);
DROP FUNCTION IF EXISTS admin_update_appointment_status_internal(uuid, uuid, int);
DROP FUNCTION IF EXISTS admin_update_appointment_status_internal(uuid, uuid, int, text);
DROP FUNCTION IF EXISTS admin_reject_payment_internal(uuid, uuid);
DROP FUNCTION IF EXISTS get_available_supervisor(timestamptz);
DROP FUNCTION IF EXISTS create_photography_task_internal(uuid, uuid, uuid, text, timestamptz);
DROP FUNCTION IF EXISTS update_photography_task_status_internal(uuid, uuid, int, text);
DROP FUNCTION IF EXISTS attach_photography_media_to_offer_internal(uuid, uuid);
DROP FUNCTION IF EXISTS admin_approve_verification_by_admin(uuid, uuid);
DROP FUNCTION IF EXISTS admin_reject_verification_by_admin(uuid, uuid, text);

-- ── 3. إعادة إنشاء الدوال ──

CREATE OR REPLACE FUNCTION admin_update_user_role(
  p_admin_uid UUID, p_target_uid UUID, p_role INT
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_admin_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_admin_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_admin_role IS NULL OR v_admin_role < 5 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  IF p_role < 0 OR p_role > 6 THEN RAISE EXCEPTION 'INVALID_ROLE'; END IF;
  UPDATE users SET role = p_role, brk = CASE WHEN p_role = 1 THEN 1 ELSE brk END, ts_upd = NOW()
  WHERE id = p_target_uid AND i_del = 0;
  RETURN FOUND;
END; $$;

CREATE OR REPLACE FUNCTION admin_set_user_status(
  p_admin_uid UUID, p_target_uid UUID, p_status INT, p_reason TEXT DEFAULT ''
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_admin_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_admin_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_admin_role IS NULL OR v_admin_role < 3 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  UPDATE users SET sts = p_status, ban_rsn = CASE WHEN p_status = 2 THEN COALESCE(p_reason, '') ELSE ban_rsn END, ts_upd = NOW()
  WHERE id = p_target_uid AND i_del = 0;
  RETURN FOUND;
END; $$;

CREATE OR REPLACE FUNCTION admin_update_user_permissions_by_admin(
  p_admin_uid UUID, p_target_uid UUID, p_perm JSONB
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_admin_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_admin_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_admin_role IS NULL OR v_admin_role < 5 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  UPDATE users SET perm = p_perm, ts_upd = NOW() WHERE id = p_target_uid AND i_del = 0;
  RETURN FOUND;
END; $$;

CREATE OR REPLACE FUNCTION get_admin_pending_offers_internal(p_admin_uid UUID)
RETURNS SETOF offers LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 3 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  RETURN QUERY SELECT * FROM offers WHERE sts = 1 AND i_del = 0 ORDER BY ts_crt DESC;
END; $$;

CREATE OR REPLACE FUNCTION get_admin_offers_internal(p_admin_uid UUID, p_limit INT DEFAULT 100)
RETURNS SETOF offers LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 3 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  RETURN QUERY SELECT * FROM offers WHERE i_del = 0 ORDER BY ts_crt DESC LIMIT p_limit;
END; $$;

CREATE OR REPLACE FUNCTION get_admin_appointments_internal(p_admin_uid UUID)
RETURNS SETOF appointments LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 3 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  RETURN QUERY SELECT * FROM appointments ORDER BY ts_crt DESC;
END; $$;

CREATE OR REPLACE FUNCTION get_admin_deals_internal(p_admin_uid UUID)
RETURNS SETOF deals LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 3 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  RETURN QUERY SELECT * FROM deals ORDER BY ts_crt DESC;
END; $$;

CREATE OR REPLACE FUNCTION get_admin_payments_internal(p_admin_uid UUID)
RETURNS SETOF payments LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 3 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  RETURN QUERY SELECT * FROM payments ORDER BY ts_crt DESC;
END; $$;

CREATE OR REPLACE FUNCTION get_admin_reports_internal(p_admin_uid UUID)
RETURNS SETOF reports LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 3 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  RETURN QUERY SELECT * FROM reports WHERE i_del = 0 ORDER BY ts_crt DESC;
END; $$;

CREATE OR REPLACE FUNCTION get_admin_requests_internal(p_admin_uid UUID)
RETURNS TABLE(
  id UUID, typ INT, elm INT, cl_nm TEXT, cl_ph TEXT,
  prc NUMERIC, cur INT, notes TEXT, specs JSONB,
  usr_id UUID, sts INT, matches JSONB, i_del INT, ts_crt TIMESTAMPTZ
) LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 3 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  RETURN QUERY
    SELECT r.id, r.typ, r.elm, r.cl_nm, r.cl_ph, r.prc, r.cur, r.notes, r.specs,
           r.usr_id, r.sts, r.matches, r.i_del, r.ts_crt
    FROM requests r WHERE r.i_del = 0 ORDER BY r.ts_crt DESC;
END; $$;

CREATE OR REPLACE FUNCTION admin_review_offer_internal(
  p_admin_uid UUID, p_offer_id UUID, p_approve BOOLEAN, p_reject_reason TEXT DEFAULT NULL
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 3 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  IF p_approve THEN
    UPDATE offers SET sts = 2, i_pub = 1, ts_pub = NOW() WHERE id = p_offer_id AND i_del = 0;
  ELSE
    UPDATE offers SET sts = 3, rsn = COALESCE(p_reject_reason, ''), i_pub = 0 WHERE id = p_offer_id AND i_del = 0;
  END IF;
  RETURN FOUND;
END; $$;

CREATE OR REPLACE FUNCTION admin_update_appointment_status_internal(
  p_admin_uid UUID, p_appointment_id UUID, p_status INT, p_admin_note TEXT DEFAULT ''
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 3 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  UPDATE appointments SET sts = p_status, admin_nt = COALESCE(p_admin_note, '') WHERE id = p_appointment_id;
  RETURN FOUND;
END; $$;

CREATE OR REPLACE FUNCTION admin_reject_payment_internal(
  p_admin_uid UUID, p_payment_id UUID
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 3 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  UPDATE payments SET sts = 2, appr_by = p_admin_uid WHERE id = p_payment_id AND sts = 0;
  RETURN FOUND;
END; $$;

CREATE OR REPLACE FUNCTION get_available_supervisor(p_dt TIMESTAMPTZ)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_uid UUID;
BEGIN
  SELECT u.id INTO v_uid FROM users u
  WHERE u.role = 3 AND u.sts = 0 AND u.i_del = 0
    AND NOT EXISTS (SELECT 1 FROM appointments a WHERE a.supervisor_uid = u.id AND a.sts = 1 AND a.dt = p_dt)
  ORDER BY (SELECT COUNT(*) FROM appointments a2 WHERE a2.supervisor_uid = u.id AND a2.sts IN (0,1)) ASC, u.ts_crt ASC
  LIMIT 1;
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NO_SUPERVISOR_AVAILABLE'; END IF;
  RETURN v_uid;
END; $$;

CREATE OR REPLACE FUNCTION create_photography_task_internal(
  p_admin_uid UUID, p_offer_id UUID, p_photographer_id UUID, p_notes TEXT, p_ts_scheduled TIMESTAMPTZ
) RETURNS SETOF photography_tasks LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_role INT; v_offer RECORD;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 3 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  SELECT * INTO v_offer FROM offers WHERE id = p_offer_id AND i_del = 0;
  IF NOT FOUND THEN RAISE EXCEPTION 'OFFER_NOT_FOUND'; END IF;
  RETURN QUERY
  INSERT INTO photography_tasks (offer_id, photographer_id, assigned_by, title, notes, loc, sts, ts_scheduled, ts_crt, ts_upd)
  VALUES (p_offer_id, p_photographer_id, p_admin_uid, v_offer.ttl, COALESCE(p_notes,''), COALESCE(v_offer.loc,'{}'::jsonb), 0, p_ts_scheduled, NOW(), NOW())
  RETURNING *;
END; $$;

CREATE OR REPLACE FUNCTION update_photography_task_status_internal(
  p_admin_uid UUID, p_task_id UUID, p_status INT, p_office_note TEXT DEFAULT ''
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 3 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  UPDATE photography_tasks SET sts = p_status, office_note = COALESCE(p_office_note,''), ts_upd = NOW() WHERE id = p_task_id;
  RETURN FOUND;
END; $$;

CREATE OR REPLACE FUNCTION attach_photography_media_to_offer_internal(
  p_admin_uid UUID, p_task_id UUID
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_role INT; v_task RECORD; v_imgs JSONB; v_merged JSONB;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 3 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  SELECT * INTO v_task FROM photography_tasks WHERE id = p_task_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'TASK_NOT_FOUND'; END IF;
  SELECT COALESCE(imgs,'[]'::jsonb) INTO v_imgs FROM offers WHERE id = v_task.offer_id;
  SELECT jsonb_agg(DISTINCT val) INTO v_merged FROM (
    SELECT jsonb_array_elements(v_imgs) AS val UNION SELECT jsonb_array_elements(COALESCE(v_task.media,'[]'::jsonb))
  ) c;
  UPDATE offers SET imgs = COALESCE(v_merged,'[]'::jsonb) WHERE id = v_task.offer_id;
  UPDATE photography_tasks SET sts = 3, ts_upd = NOW() WHERE id = p_task_id;
  RETURN TRUE;
END; $$;

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
    INSERT INTO notifications (uid, typ, ttl, bdy, ts_crt) VALUES (p_target_uid, 10, 'تم اعتماد توثيقك', 'تهانينا! تم اعتماد حسابك رسمياً ✓', NOW());
  END IF;
  RETURN FOUND;
END; $$;

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
    INSERT INTO notifications (uid, typ, ttl, bdy, ts_crt) VALUES (p_target_uid, 10, 'تم رفض طلب التوثيق', COALESCE(NULLIF(p_reason,''), 'لم يتم قبول الوثائق المرفقة'), NOW());
  END IF;
  RETURN FOUND;
END; $$;

-- ── 4. Config ──
UPDATE app_config
SET value = jsonb_set(value, '{roles}',
  '{"0":{"nm":"مستخدم"},"1":{"nm":"وسيط"},"2":{"nm":"مصور"},"3":{"nm":"مشرف"},"4":{"nm":"موظف مكتب"},"5":{"nm":"نائب مدير"},"6":{"nm":"مدير"}}'::jsonb)
WHERE key = 'main' AND value ? 'roles';

-- ── 5. RLS ──
DO $$ BEGIN
  DROP POLICY IF EXISTS "Admin can read all offers" ON offers;
  CREATE POLICY "Admin can read all offers" ON offers FOR SELECT USING (
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role >= 3)
    OR (i_pub = 1 AND sts = 2 AND i_del = 0) OR usr_id = auth.uid());
EXCEPTION WHEN OTHERS THEN NULL;
END; $$;

-- ── 6. GRANTs ──
GRANT EXECUTE ON FUNCTION admin_update_user_role TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_set_user_status TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_update_user_permissions_by_admin TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_admin_pending_offers_internal TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_admin_offers_internal TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_admin_appointments_internal TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_admin_deals_internal TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_admin_payments_internal TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_admin_reports_internal TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_admin_requests_internal TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_review_offer_internal TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_update_appointment_status_internal TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_reject_payment_internal TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_available_supervisor TO anon, authenticated;
GRANT EXECUTE ON FUNCTION create_photography_task_internal TO anon, authenticated;
GRANT EXECUTE ON FUNCTION update_photography_task_status_internal TO anon, authenticated;
GRANT EXECUTE ON FUNCTION attach_photography_media_to_offer_internal TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_approve_verification_by_admin TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_reject_verification_by_admin TO anon, authenticated;

-- ✅ تم: 0=مستخدم 1=وسيط 2=مصور 3=مشرف 4=موظف 5=نائب 6=مدير
