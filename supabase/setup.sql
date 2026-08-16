-- ============================================================================
--  عقارات السويداء — Supabase Database Setup
--  ============================================================================

CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nm TEXT NOT NULL DEFAULT '', ph TEXT UNIQUE NOT NULL DEFAULT '',
  ad TEXT DEFAULT '', role INTEGER DEFAULT 0 CHECK (role BETWEEN 0 AND 8),
  sid TEXT DEFAULT '', img TEXT DEFAULT '', pt INTEGER DEFAULT 0,
  bg INTEGER DEFAULT 0 CHECK (bg BETWEEN 0 AND 4), bg_ts TIMESTAMPTZ,
  b_pkg INTEGER DEFAULT 0 CHECK (b_pkg BETWEEN 0 AND 2), pkg_end TIMESTAMPTZ,
  brk INTEGER DEFAULT 0 CHECK (brk IN (0,1)),
  brk_cls INTEGER DEFAULT 0 CHECK (brk_cls BETWEEN 0 AND 2), brk_nm TEXT DEFAULT '',
  sts INTEGER DEFAULT 0 CHECK (sts BETWEEN 0 AND 2), ban_rsn TEXT DEFAULT '',
  ntf JSONB DEFAULT '{"off":0,"app":0,"fin":0,"rat":0}'::jsonb,
  perm JSONB DEFAULT '[]'::jsonb,
  stats JSONB DEFAULT '{"off":0,"req":0,"app":0,"dl":0}'::jsonb,
  wk_lgn JSONB DEFAULT '[]'::jsonb, strk INTEGER DEFAULT 0, strk_dt TIMESTAMPTZ,
  i_del INTEGER DEFAULT 0 CHECK (i_del IN (0,1)),
  ts_crt TIMESTAMPTZ DEFAULT NOW(), ts_upd TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_users_ph ON users(ph);
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
CREATE INDEX IF NOT EXISTS idx_users_sts ON users(sts);
CREATE INDEX IF NOT EXISTS idx_users_iDel ON users(i_del);

CREATE TABLE IF NOT EXISTS offers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usr_id UUID REFERENCES users(id) ON DELETE SET NULL,
  brk_id UUID REFERENCES users(id) ON DELETE SET NULL,
  brk_pct NUMERIC(5,2) DEFAULT 0,
  typ INTEGER NOT NULL CHECK (typ IN (0,1)), trx INTEGER NOT NULL CHECK (trx IN (0,1)),
  cat INTEGER NOT NULL DEFAULT 0, sub INTEGER DEFAULT 0,
  ttl TEXT NOT NULL DEFAULT '', prc NUMERIC(15,2) NOT NULL DEFAULT 0,
  cur INTEGER DEFAULT 1 CHECK (cur IN (0,1)),
  loc JSONB DEFAULT '{"r":0,"d":""}'::jsonb,
  descript TEXT DEFAULT '', imgs JSONB DEFAULT '[]'::jsonb,
  vdo TEXT DEFAULT '', doc_tp INTEGER DEFAULT 0, doc_img TEXT DEFAULT '',
  exact_loc TEXT DEFAULT '', specs JSONB DEFAULT '{}'::jsonb,
  com NUMERIC(10,2) DEFAULT 0, sts INTEGER DEFAULT 0 CHECK (sts BETWEEN 0 AND 6),
  rsn TEXT DEFAULT '', vws INTEGER DEFAULT 0, fvs INTEGER DEFAULT 0,
  i_pub INTEGER DEFAULT 0 CHECK (i_pub IN (0,1)), i_soc INTEGER DEFAULT 0 CHECK (i_soc IN (0,1)),
  soc_pub INTEGER DEFAULT 0 CHECK (soc_pub IN (0,1,2)), soc_txt TEXT DEFAULT '',
  i_dup INTEGER DEFAULT 0 CHECK (i_dup IN (0,1)), dup_of UUID,
  avl JSONB DEFAULT '{}'::jsonb,
  i_del INTEGER DEFAULT 0 CHECK (i_del IN (0,1)),
  ts_crt TIMESTAMPTZ DEFAULT NOW(), ts_pub TIMESTAMPTZ, ts_end TIMESTAMPTZ, ts_ren TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_offers_usr ON offers(usr_id, i_del);
CREATE INDEX IF NOT EXISTS idx_offers_sts ON offers(sts, i_del);
CREATE INDEX IF NOT EXISTS idx_offers_iPub ON offers(i_pub, i_del, ts_crt DESC);
CREATE INDEX IF NOT EXISTS idx_offers_typ ON offers(typ, sts, i_del);
CREATE INDEX IF NOT EXISTS idx_offers_trx ON offers(trx, sts, i_del);

CREATE TABLE IF NOT EXISTS requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  typ INTEGER NOT NULL CHECK (typ IN (0,1)), elm INTEGER NOT NULL CHECK (elm IN (0,1)),
  cl_nm TEXT NOT NULL DEFAULT '', cl_ph TEXT NOT NULL DEFAULT '',
  prc NUMERIC(15,2), cur INTEGER DEFAULT 1 CHECK (cur IN (0,1)),
  notes TEXT DEFAULT '', specs JSONB DEFAULT '{}'::jsonb,
  usr_id UUID REFERENCES users(id) ON DELETE SET NULL,
  sts INTEGER DEFAULT 0 CHECK (sts BETWEEN 0 AND 4), matches JSONB DEFAULT '{}'::jsonb,
  i_del INTEGER DEFAULT 0 CHECK (i_del IN (0,1)), ts_crt TIMESTAMPTZ DEFAULT NOW(),
  ts_end TIMESTAMPTZ, ts_ren TIMESTAMPTZ,
  rmnd_ren INTEGER DEFAULT 0 CHECK (rmnd_ren IN (0,1)),
  closed_at TIMESTAMPTZ,
  closed_by UUID REFERENCES users(id) ON DELETE SET NULL,
  closed_reason TEXT DEFAULT '', closed_note TEXT DEFAULT '',
  closed_offer_id UUID REFERENCES offers(id) ON DELETE SET NULL,
  closed_appointment_id UUID,
  closed_completion_request_id UUID
);
CREATE INDEX IF NOT EXISTS idx_requests_usr ON requests(usr_id, i_del);
CREATE INDEX IF NOT EXISTS idx_requests_sts ON requests(sts, i_del);
CREATE INDEX IF NOT EXISTS idx_requests_lifecycle ON requests(sts, i_del, ts_end);

CREATE TABLE IF NOT EXISTS appointments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  off_id UUID REFERENCES offers(id) ON DELETE SET NULL,
  req_id UUID REFERENCES requests(id) ON DELETE SET NULL,
  req_uid UUID REFERENCES users(id) ON DELETE SET NULL,
  own_id UUID REFERENCES users(id) ON DELETE SET NULL,
  bkr_id UUID REFERENCES users(id) ON DELETE SET NULL,
  dt TIMESTAMPTZ NOT NULL, dt_end TIMESTAMPTZ,
  sts INTEGER DEFAULT 0 CHECK (sts BETWEEN 0 AND 5),
  cnl_by UUID, cnl_rsn TEXT,
  fbk_own INTEGER DEFAULT 0 CHECK (fbk_own BETWEEN 0 AND 3),
  fbk_req INTEGER DEFAULT 0 CHECK (fbk_req BETWEEN 0 AND 3),
  fbk_own_dt TIMESTAMPTZ, fbk_req_dt TIMESTAMPTZ,
  fbk_own_dur INTEGER DEFAULT 0, fbk_req_dur INTEGER DEFAULT 0,
  admin_nt TEXT, i_force INTEGER DEFAULT 0 CHECK (i_force IN (0,1)), force_by UUID,
  rmnd_24 INTEGER DEFAULT 0 CHECK (rmnd_24 IN (0,1)),
  rmnd_2 INTEGER DEFAULT 0 CHECK (rmnd_2 IN (0,1)),
  rmnd_qtr INTEGER DEFAULT 0 CHECK (rmnd_qtr IN (0,1)),
  rmnd_end INTEGER DEFAULT 0 CHECK (rmnd_end IN (0,1)),
  ts_crt TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_appointments_own ON appointments(own_id, sts);
CREATE INDEX IF NOT EXISTS idx_appointments_req_uid ON appointments(req_uid, sts);
CREATE INDEX IF NOT EXISTS idx_appointments_off ON appointments(off_id, sts);
CREATE INDEX IF NOT EXISTS idx_appointments_dt ON appointments(dt, sts);

CREATE TABLE IF NOT EXISTS notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid UUID REFERENCES users(id) ON DELETE CASCADE,
  tp INTEGER NOT NULL CHECK (tp BETWEEN 0 AND 5),
  ttl TEXT NOT NULL DEFAULT '', bdy TEXT NOT NULL DEFAULT '',
  act TEXT DEFAULT '', ref_id TEXT DEFAULT '',
  i_rd INTEGER DEFAULT 0 CHECK (i_rd IN (0,1)), i_del INTEGER DEFAULT 0 CHECK (i_del IN (0,1)),
  ts_crt TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_notifications_uid ON notifications(uid, i_rd, ts_crt DESC);

CREATE TABLE IF NOT EXISTS payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid UUID REFERENCES users(id) ON DELETE SET NULL,
  tp INTEGER NOT NULL CHECK (tp BETWEEN 0 AND 2), pkg INTEGER DEFAULT 0 CHECK (pkg BETWEEN 0 AND 2),
  amt NUMERIC(10,2) NOT NULL DEFAULT 0, cur INTEGER DEFAULT 1 CHECK (cur BETWEEN 0 AND 2),
  mtd INTEGER DEFAULT 0 CHECK (mtd BETWEEN 0 AND 2),
  proof TEXT DEFAULT '', ref TEXT DEFAULT '', meta JSONB NOT NULL DEFAULT '{}',
  sts INTEGER DEFAULT 0 CHECK (sts BETWEEN 0 AND 2), appr_by UUID,
  ts_crt TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_payments_uid ON payments(uid, ts_crt DESC);
CREATE INDEX IF NOT EXISTS idx_payments_sts ON payments(sts);

CREATE TABLE IF NOT EXISTS reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rep_uid UUID REFERENCES users(id) ON DELETE SET NULL,
  tgt_uid UUID REFERENCES users(id) ON DELETE SET NULL,
  tgt_tp INTEGER NOT NULL CHECK (tgt_tp BETWEEN 0 AND 2),
  tgt_id TEXT NOT NULL DEFAULT '', rsn INTEGER NOT NULL,
  det TEXT DEFAULT '', sts INTEGER DEFAULT 0 CHECK (sts BETWEEN 0 AND 3),
  act INTEGER DEFAULT 0 CHECK (act BETWEEN 0 AND 3), act_dur INTEGER DEFAULT 0,
  note TEXT DEFAULT '', act_by UUID, ts_crt TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_reports_rep ON reports(rep_uid, ts_crt DESC);
CREATE INDEX IF NOT EXISTS idx_reports_sts ON reports(sts);

CREATE TABLE IF NOT EXISTS deals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  off_id UUID REFERENCES offers(id) ON DELETE SET NULL,
  app_id UUID REFERENCES appointments(id) ON DELETE SET NULL,
  sell_uid UUID REFERENCES users(id) ON DELETE SET NULL,
  buy_uid UUID REFERENCES users(id) ON DELETE SET NULL,
  brk_uid UUID REFERENCES users(id) ON DELETE SET NULL,
  fin_prc NUMERIC(15,2), cur INTEGER DEFAULT 1 CHECK (cur IN (0,1)),
  com_pct NUMERIC(5,2), com_val NUMERIC(10,2), com_note TEXT,
  form JSONB DEFAULT '{}'::jsonb,
  sts INTEGER DEFAULT 0 CHECK (sts BETWEEN 0 AND 2), cmpl_by UUID,
  i_del INTEGER DEFAULT 0 CHECK (i_del IN (0,1)),
  ts_crt TIMESTAMPTZ DEFAULT NOW(), ts_cmpl TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_deals_sell ON deals(sell_uid, sts);
CREATE INDEX IF NOT EXISTS idx_deals_buy ON deals(buy_uid, sts);

CREATE TABLE IF NOT EXISTS activity_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid UUID REFERENCES users(id) ON DELETE SET NULL,
  act INTEGER NOT NULL, det TEXT DEFAULT '', ref_id TEXT DEFAULT '', ref_col TEXT DEFAULT '',
  i_del INTEGER DEFAULT 0 CHECK (i_del IN (0,1)), ts_crt TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS stats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tp INTEGER NOT NULL CHECK (tp BETWEEN 0 AND 2), dt TIMESTAMPTZ NOT NULL, cnt INTEGER DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_stats_tp_dt ON stats(tp, dt);

CREATE TABLE IF NOT EXISTS app_config (
  key TEXT PRIMARY KEY, value JSONB NOT NULL, description TEXT DEFAULT ''
);

CREATE TABLE IF NOT EXISTS social_publications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  offer_id UUID NOT NULL REFERENCES offers(id) ON DELETE CASCADE,
  platform TEXT NOT NULL CHECK (platform IN ('facebook', 'instagram')),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','publishing','published','failed')),
  post_id TEXT NOT NULL DEFAULT '', attempt_token UUID,
  attempts INTEGER NOT NULL DEFAULT 0, error_message TEXT NOT NULL DEFAULT '',
  published_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (offer_id, platform)
);
CREATE INDEX IF NOT EXISTS idx_social_publications_status ON social_publications(status, updated_at);

CREATE TABLE IF NOT EXISTS otp_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone TEXT NOT NULL, code TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL, used INTEGER DEFAULT 0 CHECK (used IN (0,1)),
  ts_crt TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_otp_phone ON otp_codes(phone, used, expires_at);

CREATE TABLE IF NOT EXISTS user_devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid UUID REFERENCES users(id) ON DELETE CASCADE,
  device_token TEXT NOT NULL,
  platform TEXT NOT NULL CHECK (platform IN ('android','ios','web')),
  is_active BOOLEAN DEFAULT TRUE,
  ts_crt TIMESTAMPTZ DEFAULT NOW(), ts_upd TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_devices_uid ON user_devices(uid, is_active);

-- Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE offers;
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE appointments;
ALTER PUBLICATION supabase_realtime ADD TABLE deals;
ALTER PUBLICATION supabase_realtime ADD TABLE requests;

-- RLS
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE offers ENABLE ROW LEVEL SECURITY;
ALTER TABLE requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointments ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE deals ENABLE ROW LEVEL SECURITY;
ALTER TABLE activity_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE social_publications ENABLE ROW LEVEL SECURITY;
ALTER TABLE otp_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_devices ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read config" ON app_config FOR SELECT USING (true);
CREATE POLICY "Admin can write config" ON app_config FOR ALL USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role >= 2));
CREATE POLICY "Users can read active users" ON users FOR SELECT USING (i_del = 0);
CREATE POLICY "Users can update own profile" ON users FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Users can insert own profile" ON users FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "Anyone can read published offers" ON offers FOR SELECT USING (i_del = 0 AND (i_pub = 1 OR auth.uid() = usr_id OR EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role >= 2)));
CREATE POLICY "Authenticated can create offers" ON offers FOR INSERT WITH CHECK (auth.uid() = usr_id);
CREATE POLICY "Owner can update own offer" ON offers FOR UPDATE USING (auth.uid() = usr_id);
CREATE POLICY "Users read own notifications" ON notifications FOR SELECT USING (auth.uid() = uid);
CREATE POLICY "Authenticated can create appointments" ON appointments FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "Related users can read appointments" ON appointments FOR SELECT USING (auth.uid() = own_id OR auth.uid() = bkr_id);
CREATE POLICY "Users can read own requests" ON requests FOR SELECT USING (auth.uid() = usr_id AND i_del = 0);
CREATE POLICY "Authenticated can create requests" ON requests FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "Users read own payments" ON payments FOR SELECT USING (auth.uid() = uid);
CREATE POLICY "Authenticated can create payments" ON payments FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "Users read own reports" ON reports FOR SELECT USING (auth.uid() = rep_uid);
CREATE POLICY "Authenticated can create reports" ON reports FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "Related users can read deals" ON deals FOR SELECT USING (auth.uid() = sell_uid OR auth.uid() = buy_uid);
CREATE POLICY "Admin can read activity log" ON activity_log FOR SELECT USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role >= 2));
CREATE POLICY "Authenticated can generate OTP" ON otp_codes FOR INSERT WITH CHECK (true);
CREATE POLICY "Users manage own devices" ON user_devices FOR ALL USING (auth.uid() = uid);

-- Admin UPDATE policies (for payments, reports, deals, offers review etc.)
CREATE POLICY "Admin can update payments" ON payments FOR UPDATE USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role >= 2));
CREATE POLICY "Admin can update reports" ON reports FOR UPDATE USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role >= 2));
CREATE POLICY "Admin can update deals" ON deals FOR UPDATE USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role >= 2));
CREATE POLICY "Admin can update appointments" ON appointments FOR UPDATE USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role >= 2));
CREATE POLICY "Admin can update offers" ON offers FOR UPDATE USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role >= 2) OR auth.uid() = usr_id);

-- Functions

-- =====================================================================
-- Functions — مُولّدة لمطابقة الخادم الحيّ تمامًا (2026-07-04)
-- المصدر: functions_dump.sql (pg_get_functiondef + proacl من الكتالوج الحيّ).
-- كل دالة: تعريف + REVOKE ALL FROM PUBLIC + GRANT بالأدوار المخوّلة فقط.
-- =====================================================================

CREATE OR REPLACE FUNCTION public._admin_employee_assert_actor(p_admin_uid uuid, p_min_role integer DEFAULT 5)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role INT;
BEGIN
  IF p_admin_uid IS NULL THEN
    RAISE EXCEPTION 'ADMIN_UID_REQUIRED';
  END IF;

  -- عند وجود جلسة Supabase حقيقية، نمنع mismatch.
  -- في وضع service_role أو dev auth غالباً auth.uid() = NULL.
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_MISMATCH';
  END IF;

  SELECT role INTO v_role
  FROM public.users
  WHERE id = p_admin_uid
    AND i_del = 0
    AND sts = 0;

  IF v_role IS NULL THEN
    RAISE EXCEPTION 'ADMIN_NOT_FOUND_OR_INACTIVE';
  END IF;

  IF v_role < p_min_role THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  RETURN v_role;
END;
$function$

REVOKE ALL ON FUNCTION _admin_employee_assert_actor(p_admin_uid uuid, p_min_role integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION _admin_employee_assert_actor(p_admin_uid uuid, p_min_role integer) TO service_role;

CREATE OR REPLACE FUNCTION public._admin_employee_log(p_admin_uid uuid, p_action text, p_target_uid uuid DEFAULT NULL::uuid, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.activity_log (uid, act, det, ref_id, ref_col, ts_crt)
  VALUES (
    p_admin_uid,
    99,
    p_action || ': ' || COALESCE(p_payload::TEXT, '{}'),
    COALESCE(p_target_uid::TEXT, ''),
    'users',
    NOW()
  );
END;
$function$

REVOKE ALL ON FUNCTION _admin_employee_log(p_admin_uid uuid, p_action text, p_target_uid uuid, p_payload jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION _admin_employee_log(p_admin_uid uuid, p_action text, p_target_uid uuid, p_payload jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public._issue_staff_session(p_user_uid uuid, p_device_id text DEFAULT ''::text, p_ip text DEFAULT ''::text, p_ttl interval DEFAULT '7 days'::interval)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_role INT;
  v_token TEXT;
  v_expires_at TIMESTAMPTZ;
  v_session_id UUID;
BEGIN
  SELECT role INTO v_role
  FROM public.users
  WHERE id = p_user_uid
    AND i_del = 0
    AND sts = 0;

  IF v_role IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND_OR_INACTIVE';
  END IF;

  -- تسمح لكل الأدوار بإصدار جلسة مخصصة بعد تسجيل دخول صحيح بكلمة المرور.
  -- الصلاحيات الفعلية تضبط لاحقاً عند التحقق عبر p_min_role.
  v_token := encode(gen_random_bytes(32), 'hex');
  v_expires_at := NOW() + p_ttl;

  INSERT INTO public.staff_sessions (
    user_id,
    token_hash,
    role_snapshot,
    device_id,
    ip,
    expires_at
  ) VALUES (
    p_user_uid,
    crypt(v_token, gen_salt('bf', 8)),
    v_role,
    COALESCE(p_device_id, ''),
    COALESCE(p_ip, ''),
    v_expires_at
  )
  RETURNING id INTO v_session_id;

  RETURN jsonb_build_object(
    'success', true,
    'session_id', v_session_id,
    'session_token', v_token,
    'expires_at', v_expires_at,
    'role', v_role
  );
END;
$function$

REVOKE ALL ON FUNCTION _issue_staff_session(p_user_uid uuid, p_device_id text, p_ip text, p_ttl interval) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION _issue_staff_session(p_user_uid uuid, p_device_id text, p_ip text, p_ttl interval) TO service_role;

CREATE OR REPLACE FUNCTION public.add_points(p_uid uuid, p_pts integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$ BEGIN UPDATE users SET pt = pt + p_pts, ts_upd = NOW() WHERE id = p_uid; PERFORM update_user_badge(p_uid); END; $function$

REVOKE ALL ON FUNCTION add_points(p_uid uuid, p_pts integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION add_points(p_uid uuid, p_pts integer) TO service_role;

CREATE OR REPLACE FUNCTION public.admin_create_staff_user(
  p_admin_uid uuid,
  p_full_name text,
  p_phone text,
  p_email text DEFAULT ''::text,
  p_username text DEFAULT ''::text,
  p_password text DEFAULT ''::text,
  p_role integer DEFAULT 4
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'FULL_IDENTITY_REQUIRED';
END;
$$;

REVOKE ALL ON FUNCTION public.admin_create_staff_user(uuid, text, text, text, text, text, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_create_staff_user(uuid, text, text, text, text, text, integer) TO service_role;

CREATE OR REPLACE FUNCTION public.admin_create_staff_user(
  p_admin_uid uuid,
  p_full_name text,
  p_phone text,
  p_email text,
  p_username text,
  p_password text,
  p_role integer,
  p_address text DEFAULT ''::text,
  p_sid text DEFAULT ''::text,
  p_img text DEFAULT ''::text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_admin_role INT;
  v_phone TEXT;
  v_username TEXT;
  v_new_id UUID;
BEGIN
  v_admin_role := public._admin_employee_assert_actor(p_admin_uid, 5);

  IF p_role NOT IN (2, 3, 4, 5, 7, 8) THEN
    RAISE EXCEPTION 'INVALID_ROLE';
  END IF;

  IF v_admin_role < 6 AND p_role >= 5 THEN
    RAISE EXCEPTION 'ONLY_MANAGER_CAN_CREATE_DEPUTY';
  END IF;

  IF LENGTH(TRIM(COALESCE(p_full_name, ''))) < 2 THEN
    RAISE EXCEPTION 'NAME_REQUIRED';
  END IF;

  IF LENGTH(COALESCE(p_password, '')) < 8 THEN
    RAISE EXCEPTION 'PASSWORD_TOO_SHORT';
  END IF;

  IF LENGTH(TRIM(COALESCE(p_address, ''))) < 3 THEN
    RAISE EXCEPTION 'ADDRESS_REQUIRED';
  END IF;

  IF LENGTH(TRIM(COALESCE(p_sid, ''))) < 3 THEN
    RAISE EXCEPTION 'SID_REQUIRED';
  END IF;

  v_phone := public.normalize_sy_phone(p_phone);
  IF v_phone = '' THEN
    RAISE EXCEPTION 'PHONE_REQUIRED';
  END IF;

  v_username := NULLIF(public.normalize_arabic_username(p_username), '');

  IF EXISTS (SELECT 1 FROM public.users WHERE public.normalize_sy_phone(ph) = v_phone AND i_del = 0) THEN
    RAISE EXCEPTION 'PHONE_EXISTS';
  END IF;

  IF v_username IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.users
    WHERE public.normalize_arabic_username(usr) = v_username
      AND i_del = 0
  ) THEN
    RAISE EXCEPTION 'USERNAME_EXISTS';
  END IF;

  INSERT INTO public.users (
    nm, ph, eml, usr, pwd,
    role, ad, sid, img,
    sts, vrf, i_del, ts_crt, ts_upd
  ) VALUES (
    TRIM(p_full_name),
    v_phone,
    NULLIF(TRIM(COALESCE(p_email, '')), ''),
    v_username,
    crypt(p_password, gen_salt('bf', 10)),
    p_role,
    TRIM(COALESCE(p_address, '')),
    TRIM(COALESCE(p_sid, '')),
    COALESCE(p_img, ''),
    0,
    2,
    0,
    NOW(),
    NOW()
  ) RETURNING id INTO v_new_id;

  PERFORM public._admin_employee_log(
    p_admin_uid,
    'create_staff_full',
    v_new_id,
    jsonb_build_object('role', p_role, 'nm', p_full_name, 'sid', p_sid)
  );

  RETURN jsonb_build_object('success', true, 'user_id', v_new_id, 'role', p_role);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_create_staff_user(uuid, text, text, text, text, text, integer, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_create_staff_user(uuid, text, text, text, text, text, integer, text, text, text) TO service_role;

CREATE OR REPLACE FUNCTION public.admin_delete_staff_user(p_admin_uid uuid, p_target_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin_role INT;
  v_target_role INT;
BEGIN
  v_admin_role := public._admin_employee_assert_actor(p_admin_uid, 5);

  SELECT role INTO v_target_role
  FROM public.users
  WHERE id = p_target_uid
    AND i_del = 0;

  IF v_target_role IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;

  IF v_target_role = 6 THEN
    RAISE EXCEPTION 'CANNOT_DELETE_MANAGER';
  END IF;

  IF v_admin_role < 6 AND v_target_role >= 5 THEN
    RAISE EXCEPTION 'ONLY_MANAGER_CAN_MANAGE_DEPUTIES';
  END IF;

  UPDATE public.users
  SET i_del = 1,
      sts = 1,
      ts_upd = NOW()
  WHERE id = p_target_uid
    AND i_del = 0;

  PERFORM public._admin_employee_log(
    p_admin_uid,
    'staff_delete',
    p_target_uid,
    '{}'::jsonb
  );

  RETURN jsonb_build_object('success', true);
END;
$function$

REVOKE ALL ON FUNCTION admin_delete_staff_user(p_admin_uid uuid, p_target_uid uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_delete_staff_user(p_admin_uid uuid, p_target_uid uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.admin_force_appointment_internal(p_admin_uid uuid, p_appointment_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

REVOKE ALL ON FUNCTION admin_force_appointment_internal(p_admin_uid uuid, p_appointment_id uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_force_appointment_internal(p_admin_uid uuid, p_appointment_id uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.admin_handle_report_internal(p_admin_uid uuid, p_report_id uuid, p_action integer, p_note text DEFAULT ''::text, p_duration integer DEFAULT 0)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

REVOKE ALL ON FUNCTION admin_handle_report_internal(p_admin_uid uuid, p_report_id uuid, p_action integer, p_note text, p_duration integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_handle_report_internal(p_admin_uid uuid, p_report_id uuid, p_action integer, p_note text, p_duration integer) TO service_role;

CREATE OR REPLACE FUNCTION public.admin_reject_payment_internal(p_admin_uid uuid, p_payment_id uuid, p_reason text DEFAULT '')
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 5 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  UPDATE payments
  SET sts = 2, appr_by = p_admin_uid,
      meta = COALESCE(meta, '{}'::jsonb) || jsonb_build_object(
        'reject_reason', COALESCE(NULLIF(BTRIM(p_reason), ''), ''),
        'reject_ts', NOW())
  WHERE id = p_payment_id AND sts = 0;
  IF FOUND THEN
    PERFORM public.log_admin_action(p_admin_uid, 106,
      'رفض دفعة — السبب: ' || LEFT(COALESCE(NULLIF(BTRIM(p_reason), ''), 'بدون سبب'), 120),
      p_payment_id::TEXT, 'payments');
  END IF;
  RETURN FOUND;
END; $function$;

REVOKE ALL ON FUNCTION public.admin_reject_payment_internal(p_admin_uid uuid, p_payment_id uuid, p_reason text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_reject_payment_internal(p_admin_uid uuid, p_payment_id uuid, p_reason text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reject_payment_internal(p_admin_uid uuid, p_payment_id uuid, p_reason text) TO service_role;

CREATE OR REPLACE FUNCTION public.admin_reset_staff_password(p_admin_uid uuid, p_target_uid uuid, p_new_password text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_admin_role INT;
  v_target_role INT;
BEGIN
  v_admin_role := public._admin_employee_assert_actor(p_admin_uid, 5);

  SELECT role INTO v_target_role
  FROM public.users
  WHERE id = p_target_uid
    AND i_del = 0;

  IF v_target_role IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;

  IF v_target_role = 6 THEN
    RAISE EXCEPTION 'CANNOT_MODIFY_MANAGER';
  END IF;

  IF v_admin_role < 6 AND v_target_role >= 5 THEN
    RAISE EXCEPTION 'ONLY_MANAGER_CAN_MANAGE_DEPUTIES';
  END IF;

  IF LENGTH(COALESCE(p_new_password, '')) < 8 THEN
    RAISE EXCEPTION 'PASSWORD_TOO_SHORT';
  END IF;

  UPDATE public.users
  SET pwd = crypt(p_new_password, gen_salt('bf', 8)),
      ts_upd = NOW()
  WHERE id = p_target_uid
    AND i_del = 0;

  PERFORM public._admin_employee_log(
    p_admin_uid,
    'staff_password_reset',
    p_target_uid,
    '{}'::jsonb
  );

  RETURN jsonb_build_object('success', true);
END;
$function$

REVOKE ALL ON FUNCTION admin_reset_staff_password(p_admin_uid uuid, p_target_uid uuid, p_new_password text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_reset_staff_password(p_admin_uid uuid, p_target_uid uuid, p_new_password text) TO service_role;

CREATE OR REPLACE FUNCTION public.admin_review_offer_internal(p_admin_uid uuid, p_offer_id uuid, p_approve boolean, p_reject_reason text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 4 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  IF p_approve THEN
    UPDATE offers SET sts = 2, i_pub = 1, ts_pub = NOW() WHERE id = p_offer_id AND i_del = 0;
    PERFORM public.log_admin_action(p_admin_uid, 101, 'اعتماد العرض العقاري ونشره للعموم', p_offer_id::TEXT, 'offers');
  ELSE
    IF COALESCE(trim(p_reject_reason), '') = '' THEN
      RAISE EXCEPTION 'REJECTION_REASON_REQUIRED';
    END IF;
    UPDATE offers SET sts = 3, rsn = trim(p_reject_reason), i_pub = 0 WHERE id = p_offer_id AND i_del = 0;
    PERFORM public.log_admin_action(p_admin_uid, 102, 'رفض العرض العقاري: ' || trim(p_reject_reason), p_offer_id::TEXT, 'offers');
  END IF;
  RETURN FOUND;
END; $function$

REVOKE ALL ON FUNCTION admin_review_offer_internal(p_admin_uid uuid, p_offer_id uuid, p_approve boolean, p_reject_reason text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_review_offer_internal(p_admin_uid uuid, p_offer_id uuid, p_approve boolean, p_reject_reason text) TO service_role;

CREATE OR REPLACE FUNCTION public.admin_set_user_status(p_admin_uid uuid, p_target_uid uuid, p_status integer, p_reason text DEFAULT ''::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin_role INT;
  v_target_role INT;
BEGIN
  v_admin_role := public._admin_employee_assert_actor(p_admin_uid, 4);

  SELECT role INTO v_target_role
  FROM public.users
  WHERE id = p_target_uid
    AND i_del = 0;

  IF v_target_role IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;

  IF v_target_role = 6 THEN
    RAISE EXCEPTION 'CANNOT_MODIFY_MANAGER';
  END IF;

  IF v_admin_role < 6 AND v_target_role >= 5 THEN
    RAISE EXCEPTION 'ONLY_MANAGER_CAN_MANAGE_DEPUTIES';
  END IF;

  IF p_status NOT IN (0, 1, 2) THEN
    RAISE EXCEPTION 'INVALID_STATUS';
  END IF;

  UPDATE public.users
  SET sts = p_status,
      ban_rsn = CASE
        WHEN p_status IN (1, 2) THEN COALESCE(p_reason, '')
        ELSE ''
      END,
      ts_upd = NOW()
  WHERE id = p_target_uid
    AND i_del = 0;

  PERFORM public._admin_employee_log(
    p_admin_uid,
    'legacy_user_status_update',
    p_target_uid,
    jsonb_build_object(
      'status', p_status,
      'reason', COALESCE(p_reason, '')
    )
  );

  RETURN FOUND;
END;
$function$

REVOKE ALL ON FUNCTION admin_set_user_status(p_admin_uid uuid, p_target_uid uuid, p_status integer, p_reason text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_set_user_status(p_admin_uid uuid, p_target_uid uuid, p_status integer, p_reason text) TO service_role;

CREATE OR REPLACE FUNCTION public.admin_toggle_staff_status(p_admin_uid uuid, p_target_uid uuid, p_status integer, p_reason text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin_role INT;
  v_target_role INT;
BEGIN
  v_admin_role := public._admin_employee_assert_actor(p_admin_uid, 5);

  SELECT role INTO v_target_role
  FROM public.users
  WHERE id = p_target_uid
    AND i_del = 0;

  IF v_target_role IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;

  IF v_target_role = 6 THEN
    RAISE EXCEPTION 'CANNOT_MODIFY_MANAGER';
  END IF;

  IF v_admin_role < 6 AND v_target_role >= 5 THEN
    RAISE EXCEPTION 'ONLY_MANAGER_CAN_MANAGE_DEPUTIES';
  END IF;

  IF p_status NOT IN (0, 1, 2) THEN
    RAISE EXCEPTION 'INVALID_STATUS';
  END IF;

  UPDATE public.users
  SET sts = p_status,
      ban_rsn = CASE
        WHEN p_status IN (1, 2) THEN COALESCE(p_reason, '')
        ELSE ''
      END,
      ts_upd = NOW()
  WHERE id = p_target_uid
    AND i_del = 0;

  PERFORM public._admin_employee_log(
    p_admin_uid,
    'staff_status_update',
    p_target_uid,
    jsonb_build_object(
      'status', p_status,
      'reason', COALESCE(p_reason, '')
    )
  );

  RETURN jsonb_build_object('success', true);
END;
$function$

REVOKE ALL ON FUNCTION admin_toggle_staff_status(p_admin_uid uuid, p_target_uid uuid, p_status integer, p_reason text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_toggle_staff_status(p_admin_uid uuid, p_target_uid uuid, p_status integer, p_reason text) TO service_role;

CREATE OR REPLACE FUNCTION public.admin_update_appointment_status_internal(p_admin_uid uuid, p_appointment_id uuid, p_status integer, p_admin_note text DEFAULT ''::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 3 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  UPDATE appointments SET sts = p_status, admin_nt = COALESCE(p_admin_note, '') WHERE id = p_appointment_id;
  RETURN FOUND;
END; $function$

REVOKE ALL ON FUNCTION admin_update_appointment_status_internal(p_admin_uid uuid, p_appointment_id uuid, p_status integer, p_admin_note text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_update_appointment_status_internal(p_admin_uid uuid, p_appointment_id uuid, p_status integer, p_admin_note text) TO service_role;

CREATE OR REPLACE FUNCTION public.admin_update_staff_role(p_admin_uid uuid, p_target_uid uuid, p_role integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin_role INT;
  v_target_role INT;
BEGIN
  v_admin_role := public._admin_employee_assert_actor(p_admin_uid, 5);

  SELECT role INTO v_target_role
  FROM public.users
  WHERE id = p_target_uid
    AND i_del = 0;

  IF v_target_role IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;

  IF v_target_role = 6 THEN
    RAISE EXCEPTION 'CANNOT_MODIFY_MANAGER';
  END IF;

  IF p_role NOT IN (2, 3, 4, 5) THEN
    RAISE EXCEPTION 'INVALID_ROLE';
  END IF;

  IF v_admin_role < 6 AND (p_role >= 5 OR v_target_role >= 5) THEN
    RAISE EXCEPTION 'ONLY_MANAGER_CAN_MANAGE_DEPUTIES';
  END IF;

  UPDATE public.users
  SET role = p_role,
      ts_upd = NOW()
  WHERE id = p_target_uid
    AND i_del = 0;

  PERFORM public._admin_employee_log(
    p_admin_uid,
    'staff_role_update',
    p_target_uid,
    jsonb_build_object(
      'old_role', v_target_role,
      'new_role', p_role
    )
  );

  RETURN jsonb_build_object('success', true);
END;
$function$

REVOKE ALL ON FUNCTION admin_update_staff_role(p_admin_uid uuid, p_target_uid uuid, p_role integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_update_staff_role(p_admin_uid uuid, p_target_uid uuid, p_role integer) TO service_role;

CREATE OR REPLACE FUNCTION public.admin_update_user_permissions_by_admin(p_admin_uid uuid, p_target_uid uuid, p_perm jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE v_admin_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_admin_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_admin_role IS NULL OR v_admin_role < 5 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  UPDATE users SET perm = p_perm, ts_upd = NOW() WHERE id = p_target_uid AND i_del = 0;
  RETURN FOUND;
END; $function$

REVOKE ALL ON FUNCTION admin_update_user_permissions_by_admin(p_admin_uid uuid, p_target_uid uuid, p_perm jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_update_user_permissions_by_admin(p_admin_uid uuid, p_target_uid uuid, p_perm jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.admin_update_user_role(p_admin_uid uuid, p_target_uid uuid, p_role integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin_role INT;
  v_target_role INT;
BEGIN
  v_admin_role := public._admin_employee_assert_actor(p_admin_uid, 5);

  SELECT role INTO v_target_role
  FROM public.users
  WHERE id = p_target_uid
    AND i_del = 0;

  IF v_target_role IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;

  IF v_target_role = 6 THEN
    RAISE EXCEPTION 'CANNOT_MODIFY_MANAGER';
  END IF;

  -- لا نسمح بإنشاء مدير جديد من هذه الدالة القديمة
  IF p_role < 0 OR p_role > 5 THEN
    RAISE EXCEPTION 'INVALID_ROLE';
  END IF;

  IF v_admin_role < 6 AND (p_role >= 5 OR v_target_role >= 5) THEN
    RAISE EXCEPTION 'ONLY_MANAGER_CAN_MANAGE_DEPUTIES';
  END IF;

  UPDATE public.users
  SET role = p_role,
      brk = CASE WHEN p_role = 1 THEN 1 ELSE brk END,
      ts_upd = NOW()
  WHERE id = p_target_uid
    AND i_del = 0;

  PERFORM public._admin_employee_log(
    p_admin_uid,
    'legacy_user_role_update',
    p_target_uid,
    jsonb_build_object(
      'old_role', v_target_role,
      'new_role', p_role
    )
  );

  RETURN FOUND;
END;
$function$

REVOKE ALL ON FUNCTION admin_update_user_role(p_admin_uid uuid, p_target_uid uuid, p_role integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_update_user_role(p_admin_uid uuid, p_target_uid uuid, p_role integer) TO service_role;

CREATE OR REPLACE FUNCTION public.app_assert_password(p_password text, p_min integer DEFAULT 8)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF length(COALESCE(p_password, '')) < p_min THEN
    RAISE EXCEPTION 'PASSWORD_TOO_SHORT';
  END IF;
  IF length(COALESCE(p_password, '')) > 128 THEN
    RAISE EXCEPTION 'PASSWORD_TOO_LONG';
  END IF;
  RETURN p_password;
END;
$function$

REVOKE ALL ON FUNCTION app_assert_password(p_password text, p_min integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.app_assert_password(p_password text, p_min integer) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.app_assert_password(p_password text, p_min integer) TO service_role;

CREATE OR REPLACE FUNCTION public.app_assert_phone(p_phone text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v TEXT;
BEGIN
  v := normalize_sy_phone(COALESCE(p_phone, ''));
  IF v = '' THEN
    RAISE EXCEPTION 'PHONE_REQUIRED';
  END IF;
  IF v !~ '^\+9639[0-9]{8}$' THEN
    RAISE EXCEPTION 'PHONE_INVALID';
  END IF;
  RETURN v;
END;
$function$

REVOKE ALL ON FUNCTION app_assert_phone(p_phone text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.app_assert_phone(p_phone text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.app_assert_phone(p_phone text) TO service_role;

CREATE OR REPLACE FUNCTION public.app_assert_price(p_value numeric, p_required boolean DEFAULT true)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF p_value IS NULL THEN
    IF p_required THEN
      RAISE EXCEPTION 'PRICE_REQUIRED';
    END IF;
    RETURN NULL;
  END IF;
  IF p_value <= 0 THEN
    RAISE EXCEPTION 'INVALID_PRICE';
  END IF;
  IF p_value > 999999999999 THEN
    RAISE EXCEPTION 'PRICE_TOO_LARGE';
  END IF;
  RETURN p_value;
END;
$function$

REVOKE ALL ON FUNCTION app_assert_price(p_value numeric, p_required boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.app_assert_price(p_value numeric, p_required boolean) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.app_assert_price(p_value numeric, p_required boolean) TO service_role;

CREATE OR REPLACE FUNCTION public.app_assert_text_len(p_value text, p_field text, p_min integer DEFAULT 0, p_max integer DEFAULT 1000)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v TEXT;
BEGIN
  v := app_clean_text(p_value, p_max + 1);
  IF length(v) < p_min THEN
    RAISE EXCEPTION '%_TOO_SHORT', upper(p_field);
  END IF;
  IF length(v) > p_max THEN
    RAISE EXCEPTION '%_TOO_LONG', upper(p_field);
  END IF;
  IF v ~ '[<>]' THEN
    RAISE EXCEPTION '%_INVALID_CHARS', upper(p_field);
  END IF;
  RETURN v;
END;
$function$

REVOKE ALL ON FUNCTION app_assert_text_len(p_value text, p_field text, p_min integer, p_max integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.app_assert_text_len(p_value text, p_field text, p_min integer, p_max integer) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.app_assert_text_len(p_value text, p_field text, p_min integer, p_max integer) TO service_role;

CREATE OR REPLACE FUNCTION public.app_assert_username(p_username text, p_required boolean DEFAULT true)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v TEXT;
BEGIN
  v := lower(btrim(COALESCE(p_username, '')));
  IF v = '' THEN
    IF p_required THEN
      RAISE EXCEPTION 'USERNAME_REQUIRED';
    END IF;
    RETURN NULL;
  END IF;
  IF length(v) < 3 OR length(v) > 30 THEN
    RAISE EXCEPTION 'USERNAME_LENGTH';
  END IF;
  -- منع خلط اللغات: إما أحرف لاتينية وأرقام ورمزين، أو أحرف عربية وأرقام ورمزين
  IF NOT v ~ '^([a-z0-9_.]+|[\u0600-\u06FF0-9_.]+)$' THEN
    RAISE EXCEPTION 'USERNAME_INVALID_CHARS';
  END IF;
  RETURN v;
END;
$function$

REVOKE ALL ON FUNCTION app_assert_username(p_username text, p_required boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.app_assert_username(p_username text, p_required boolean) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.app_assert_username(p_username text, p_required boolean) TO service_role;

CREATE OR REPLACE FUNCTION public.app_clean_text(p_value text, p_max_len integer DEFAULT 1000)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v TEXT;
BEGIN
  v := COALESCE(p_value, '');
  v := regexp_replace(v, '[[:cntrl:]]', '', 'g');
  v := regexp_replace(v, '\s+', ' ', 'g');
  v := btrim(v);
  IF p_max_len IS NOT NULL AND p_max_len > 0 AND length(v) > p_max_len THEN
    v := substring(v from 1 for p_max_len);
  END IF;
  RETURN v;
END;
$function$

REVOKE ALL ON FUNCTION app_clean_text(p_value text, p_max_len integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.app_clean_text(p_value text, p_max_len integer) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.app_clean_text(p_value text, p_max_len integer) TO service_role;

CREATE OR REPLACE FUNCTION public.attach_photography_media_to_offer_internal(p_admin_uid uuid, p_task_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
END; $function$

REVOKE ALL ON FUNCTION attach_photography_media_to_offer_internal(p_admin_uid uuid, p_task_id uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION attach_photography_media_to_offer_internal(p_admin_uid uuid, p_task_id uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.book_appointment_internal(p_user_uid uuid, p_offer_id uuid, p_dt timestamp with time zone, p_broker_id uuid DEFAULT NULL::uuid, p_request_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_offer      public.offers%ROWTYPE;
  v_req        public.requests%ROWTYPE;
  v_cfg        JSONB := public.appt_booking_config();
  v_gap        INT;
  v_day_key    TEXT;
  v_slot       TEXT;
  v_slot_from  INT;
  v_slot_to    INT;
  v_req_mins   INT;
  v_avl_slots  JSONB;
  v_found_slot BOOLEAN := FALSE;
  v_supervisor UUID;
  v_suggest    TIMESTAMPTZ;
  v_active_count INT;
  v_pending_completion INT;
  v_appointment_id UUID;
BEGIN
  v_gap := (v_cfg->>'gap_mins')::INT;

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

  -- ✅ القاعدة 1: الحجز حصراً ضمن مواعيد صاحب العرض
  -- avl فارغة = لا معاينة على هذا العرض إطلاقاً (سد ثغرة تخطي الفحص)
  IF v_offer.avl IS NULL OR v_offer.avl = '{}'::jsonb OR v_offer.avl = 'null'::jsonb THEN
    RAISE EXCEPTION 'NO_AVAILABILITY';
  END IF;

  v_day_key := LOWER(to_char(p_dt AT TIME ZONE 'Asia/Damascus', 'Dy'));

  -- 'any' = جاهز بأي وقت → كل الأيام ضمن دوام الإعدادات (09:00-21:00 افتراضياً)
  IF v_offer.avl ? 'any' THEN
    v_avl_slots := jsonb_build_array((v_cfg->>'any_from') || '-' || (v_cfg->>'any_to'));
  ELSE
    v_avl_slots := v_offer.avl -> v_day_key;
  END IF;

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

  -- ✅ القاعدة 3: عدم التعارض — فارق لا يقل عن ساعة بين مواعيد نفس العرض
  -- (موعد 10:00 → أقرب حجز مسموح 11:00)
  IF EXISTS (
    SELECT 1 FROM public.appointments
    WHERE off_id = p_offer_id AND sts IN (0, 1)
      AND dt > p_dt - make_interval(mins => v_gap)
      AND dt < p_dt + make_interval(mins => v_gap)
  ) THEN
    RAISE EXCEPTION 'TIME_CONFLICT_ON_OFFER';
  END IF;

  IF EXISTS (SELECT 1 FROM public.appointments WHERE off_id = p_offer_id AND req_uid = p_user_uid AND sts IN (0, 1)) THEN
    RAISE EXCEPTION 'DUPLICATE_APPOINTMENT';
  END IF;

  -- ✅ القاعدة 2: المشرف الأقل مواعيد نشطة، مع استبعاد المشغول ضمن فارق الساعة
  -- (استعلام مرتّب: إن كان الأقل حمولة مشغولاً ينتقل تلقائياً للتالي)
  SELECT u.id INTO v_supervisor
  FROM public.users u
  WHERE u.role = 3 AND u.sts = 0 AND u.i_del = 0
    AND NOT EXISTS (
      SELECT 1 FROM public.appointments a
      WHERE a.supervisor_uid = u.id AND a.sts IN (0, 1)
        AND a.dt > p_dt - make_interval(mins => v_gap)
        AND a.dt < p_dt + make_interval(mins => v_gap)
    )
  ORDER BY (
    SELECT COUNT(*) FROM public.appointments a2 WHERE a2.supervisor_uid = u.id AND a2.sts IN (0, 1)
  ) ASC, u.ts_crt ASC
  LIMIT 1;

  -- ✅ القاعدة 2 (تكملة): لا مشرف متاح → إشعار الطالب + اقتراح أقرب موعد متاح
  IF v_supervisor IS NULL THEN
    v_suggest := public.suggest_appointment_slot(p_offer_id, p_dt);
    PERFORM public.notify_user(
      p_user_uid,
      2,
      'لا يوجد مشرف متاح للتوقيت المطلوب',
      CASE WHEN v_suggest IS NOT NULL
        THEN 'تعذّر تثبيت موعد المعاينة في التوقيت الذي اخترته لعدم توفر مشرف. أقرب موعد متاح: '
             || to_char(v_suggest AT TIME ZONE 'Asia/Damascus', 'YYYY/MM/DD HH24:MI')
             || ' — يمكنك إعادة الحجز عليه أو اختيار وقت آخر.'
        ELSE 'تعذّر تثبيت موعد المعاينة في التوقيت الذي اخترته لعدم توفر مشرف. يرجى اختيار وقت آخر.'
      END,
      p_offer_id::text,
      'appointment_suggest'
    );
    RETURN jsonb_build_object(
      'success', false,
      'error', 'NO_SUPERVISOR_AVAILABLE',
      'suggested_dt', v_suggest
    );
  END IF;

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
$function$

REVOKE ALL ON FUNCTION book_appointment_internal(p_user_uid uuid, p_offer_id uuid, p_dt timestamp with time zone, p_broker_id uuid, p_request_id uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION book_appointment_internal(p_user_uid uuid, p_offer_id uuid, p_dt timestamp with time zone, p_broker_id uuid, p_request_id uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.broker_handle_appointment_internal(p_broker_uid uuid, p_appointment_id uuid, p_action text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

REVOKE ALL ON FUNCTION broker_handle_appointment_internal(p_broker_uid uuid, p_appointment_id uuid, p_action text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION broker_handle_appointment_internal(p_broker_uid uuid, p_appointment_id uuid, p_action text) TO service_role;

CREATE OR REPLACE FUNCTION public.calculate_commission(p_prc numeric, p_pct numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$ BEGIN RETURN ROUND(p_prc * p_pct / 100, 2); END; $function$

REVOKE ALL ON FUNCTION calculate_commission(p_prc numeric, p_pct numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION calculate_commission(p_prc numeric, p_pct numeric) TO service_role;

CREATE OR REPLACE FUNCTION public.cancel_appointment_internal(p_requester_uid uuid, p_appointment_id uuid, p_reason text DEFAULT ''::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

REVOKE ALL ON FUNCTION cancel_appointment_internal(p_requester_uid uuid, p_appointment_id uuid, p_reason text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION cancel_appointment_internal(p_requester_uid uuid, p_appointment_id uuid, p_reason text) TO service_role;

CREATE OR REPLACE FUNCTION public.check_offer_duplicate(p_ttl text, p_prc numeric, p_loc jsonb, p_usr_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE v_dup BOOLEAN;
BEGIN
  -- تطبيع النص: lowercase + إزالة المسافات المتعددة
  SELECT EXISTS(
    SELECT 1 FROM offers
    WHERE LOWER(REGEXP_REPLACE(ttl, '\s+', ' ', 'g')) =
          LOWER(REGEXP_REPLACE(p_ttl, '\s+', ' ', 'g'))
      AND prc = p_prc
      AND i_del = 0
      -- نكشف التكرار حتى من نفس المستخدم (لمنع نشر متعدد بنفس الحساب)
  ) INTO v_dup;
  RETURN v_dup;
END;
$function$

REVOKE ALL ON FUNCTION check_offer_duplicate(p_ttl text, p_prc numeric, p_loc jsonb, p_usr_id uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION check_offer_duplicate(p_ttl text, p_prc numeric, p_loc jsonb, p_usr_id uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.complete_deal_internal(p_admin_uid uuid, p_deal_id uuid, p_commission numeric DEFAULT NULL::numeric, p_note text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

REVOKE ALL ON FUNCTION complete_deal_internal(p_admin_uid uuid, p_deal_id uuid, p_commission numeric, p_note text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION complete_deal_internal(p_admin_uid uuid, p_deal_id uuid, p_commission numeric, p_note text) TO service_role;

CREATE OR REPLACE FUNCTION public.create_deal_internal(p_admin_uid uuid, p_deal jsonb)
 RETURNS SETOF deals
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

REVOKE ALL ON FUNCTION create_deal_internal(p_admin_uid uuid, p_deal jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_deal_internal(p_admin_uid uuid, p_deal jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.create_offer_internal(p_user_uid uuid, p_offer jsonb)
 RETURNS SETOF offers
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user users%ROWTYPE;
  v_config JSONB;
  v_limit INT;
  v_used INT;
  v_recent_deleted INT;
  v_duplicate BOOLEAN;
  v_effective_pkg INT;
  v_title TEXT;
  v_contact_ph TEXT;
  v_desc TEXT;
  v_exact_loc TEXT;
  v_soc_txt TEXT;
  v_price NUMERIC;
  v_admin_role INT;
  v_added_by UUID := NULL;
  v_is_admin_action BOOLEAN := FALSE;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT * INTO v_user FROM users WHERE id = p_user_uid AND i_del = 0 AND sts = 0;
  IF v_user.id IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_ACTIVE_OR_NOT_FOUND';
  END IF;

  -- التحقق من هوية المنفذ الإداري (added_by) وحراسته من التلاعب
  IF p_offer ? 'added_by' AND NULLIF(p_offer->>'added_by', '') IS NOT NULL THEN
    SELECT role INTO v_admin_role FROM users
    WHERE id = (p_offer->>'added_by')::UUID AND sts = 0 AND i_del = 0;

    IF COALESCE(v_admin_role, 0) >= 4 THEN
      v_added_by := (p_offer->>'added_by')::UUID;
      v_is_admin_action := TRUE;
    ELSE
      -- إذا حاول شخص غير إداري تمرير added_by نرفض القيمة ونعتبرها NULL
      v_added_by := NULL;
    END IF;
  ELSE
    -- إذا كان المنفذ هو المستخدم نفسه ولكنه موظف إداري يضيف لنفسه
    IF COALESCE(v_user.role, 0) >= 4 THEN
      v_added_by := p_user_uid;
      v_is_admin_action := TRUE;
    END IF;
  END IF;

  v_title := app_assert_text_len(COALESCE(p_offer->>'ttl', p_offer->>'title'), 'title', 2, 120);
  v_contact_ph := app_assert_phone(p_offer->>'contact_ph');
  v_price := app_assert_price(COALESCE((p_offer->>'prc')::NUMERIC, 0), TRUE);
  v_desc := app_clean_text(p_offer->>'descript', 2000);
  v_exact_loc := app_clean_text(p_offer->>'exact_loc', 300);
  v_soc_txt := app_clean_text(p_offer->>'soc_txt', 500);

  -- الإدارة الداخلية (موظف مكتب فما فوق أو إضافة إدارية لعميل) غير مقيّدة بحصة.
  IF NOT v_is_admin_action THEN
    SELECT value INTO v_config FROM app_config WHERE key = 'main';

    v_effective_pkg := CASE
      WHEN COALESCE(v_user.b_pkg, 0) = 0 THEN 0
      WHEN v_user.pkg_grace IS NOT NULL AND v_user.pkg_grace > NOW() THEN v_user.b_pkg
      WHEN v_user.pkg_end IS NOT NULL AND v_user.pkg_end > NOW() THEN v_user.b_pkg
      ELSE 0
    END;

    v_limit := COALESCE((v_config->'pkg'->(v_effective_pkg::TEXT)->>'o')::INT,
      CASE WHEN COALESCE(v_user.role, 0) = 1 THEN 5 ELSE 1 END)
      -- التجميع (2026-07-27): السقف الإضافي من الباقات المكدّسة يُحتسب ما دامت الباقة فعالة
      + CASE WHEN v_effective_pkg > 0 THEN COALESCE(v_user.pkg_xoff, 0) ELSE 0 END;

    SELECT COUNT(*) INTO v_used
    FROM offers
    WHERE usr_id = p_user_uid
      AND i_del = 0
      AND sts IN (0, 1, 2, 5);

    SELECT COUNT(*) INTO v_recent_deleted
    FROM offers
    WHERE usr_id = p_user_uid
      AND i_del = 1
      AND ts_crt >= NOW() - INTERVAL '24 hours';

    v_used := COALESCE(v_used, 0) + COALESCE(v_recent_deleted, 0);
    IF v_used >= v_limit THEN
      RAISE EXCEPTION 'QUOTA_EXCEEDED';
    END IF;
  END IF;

  SELECT check_offer_duplicate(
    v_title,
    v_price,
    COALESCE(p_offer->'loc', '{"r":0,"d":""}'::jsonb),
    p_user_uid
  ) INTO v_duplicate;

  IF v_duplicate THEN
    RAISE EXCEPTION 'DUPLICATE_OFFER';
  END IF;

  RETURN QUERY
  INSERT INTO offers (
    usr_id, brk_id, brk_pct, typ, trx, cat, sub, contact_ph,
    ttl, prc, cur, loc, descript, imgs, vdo, doc_tp, doc_img,
    exact_loc, specs, com, sts, rsn, vws, fvs, i_pub, i_soc,
    soc_pub, soc_txt, i_dup, dup_of, avl, i_del, ts_crt, ts_pub, ts_end, ts_ren, added_by
  ) VALUES (
    p_user_uid,
    NULLIF(p_offer->>'brk_id', '')::UUID,
    COALESCE((p_offer->>'brk_pct')::NUMERIC, 0),
    COALESCE((p_offer->>'typ')::INT, 0),
    COALESCE((p_offer->>'trx')::INT, 0),
    COALESCE((p_offer->>'cat')::INT, 0),
    COALESCE((p_offer->>'sub')::INT, 0),
    v_contact_ph,
    v_title,
    v_price,
    COALESCE((p_offer->>'cur')::INT, 0),
    COALESCE(p_offer->'loc', '{}'::jsonb),
    v_desc,
    COALESCE(p_offer->'imgs', '[]'::jsonb),
    app_clean_text(p_offer->>'vdo', 500),
    COALESCE((p_offer->>'doc_tp')::INT, 0),
    app_clean_text(p_offer->>'doc_img', 500),
    v_exact_loc,
    COALESCE(p_offer->'specs', '{}'::jsonb),
    COALESCE((p_offer->>'com')::NUMERIC, 0),
    1,
    '',
    0,
    0,
    0,
    COALESCE((p_offer->>'i_soc')::INT, 0),
    0,
    v_soc_txt,
    0,
    NULL,
    COALESCE(p_offer->'avl', '{}'::jsonb),
    0,
    NOW(),
    NULL,
    NULL,
    NULL,
    v_added_by
  ) RETURNING *;
END;
$function$

REVOKE ALL ON FUNCTION public.create_offer_internal(p_user_uid uuid, p_offer jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_offer_internal(p_user_uid uuid, p_offer jsonb) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_offer_internal(p_user_uid uuid, p_offer jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.create_payment_internal(p_user_uid uuid, p_payment jsonb)
 RETURNS SETOF payments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_user        users%ROWTYPE;
  v_pending_cnt INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT * INTO v_user
  FROM users WHERE id = p_user_uid AND i_del = 0 AND sts = 0;
  IF v_user.id IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_ACTIVE_OR_NOT_FOUND';
  END IF;

  IF COALESCE(trim(p_payment->>'proof'), '') = '' OR
     COALESCE(trim(p_payment->>'ref'),   '') = '' THEN
    RAISE EXCEPTION 'MISSING_PAYMENT_PROOF_OR_REFERENCE';
  END IF;

  -- FIX: منع الدفعة المزدوجة المعلقة لنفس الباقة
  SELECT COUNT(*) INTO v_pending_cnt
  FROM payments
  WHERE uid = p_user_uid
    AND sts = 0
    AND pkg = COALESCE((p_payment->>'pkg')::INT, 0)
    AND tp  = 0;

  IF v_pending_cnt > 0 THEN
    RAISE EXCEPTION 'PENDING_PAYMENT_EXISTS';
  END IF;

  RETURN QUERY
  INSERT INTO payments (
    uid, tp, pkg, amt, cur, mtd, channel, proof, ref, sts, appr_by, ts_crt
  ) VALUES (
    p_user_uid,
    COALESCE((p_payment->>'tp')::INT,      0),
    COALESCE((p_payment->>'pkg')::INT,     0),
    COALESCE((p_payment->>'amt')::NUMERIC, 0),
    COALESCE((p_payment->>'cur')::INT,     1),
    COALESCE((p_payment->>'mtd')::INT,     0),
    COALESCE(p_payment->>'channel', ''),
    COALESCE(p_payment->>'proof',   ''),
    COALESCE(p_payment->>'ref',     ''),
    0,
    NULL,
    NOW()
  ) RETURNING *;
END;
$function$

REVOKE ALL ON FUNCTION create_payment_internal(p_user_uid uuid, p_payment jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_payment_internal(p_user_uid uuid, p_payment jsonb) TO service_role;

-- ═════════════════════════════════════════════════════════════════════
-- التعريف المرجعي الموحد لجدول مهام التصوير (مطابق للهجرة 2026_06_10_photography_tasks.sql)
-- ملاحظة: كان الجدول موثقاً فقط بالهجرات؛ نُزّل هنا كمرجع وحيد للحقيقة
CREATE TABLE IF NOT EXISTS public.photography_tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  off_id UUID REFERENCES public.offers(id) ON DELETE CASCADE,
  photographer_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  requested_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  ttl TEXT NOT NULL DEFAULT '',
  notes TEXT NOT NULL DEFAULT '',
  loc JSONB DEFAULT '{}'::jsonb,
  media JSONB NOT NULL DEFAULT '[]'::jsonb,
  photographer_note TEXT NOT NULL DEFAULT '',
  office_note TEXT NOT NULL DEFAULT '',
  sts INTEGER NOT NULL DEFAULT 0 CHECK (sts BETWEEN 0 AND 5),
  ts_scheduled TIMESTAMPTZ,
  ts_submit TIMESTAMPTZ,
  ts_done TIMESTAMPTZ,
  ts_crt TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ts_upd TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_photo_tasks_offer ON public.photography_tasks(off_id);
CREATE INDEX IF NOT EXISTS idx_photo_tasks_photographer ON public.photography_tasks(photographer_id, sts);
CREATE INDEX IF NOT EXISTS idx_photo_tasks_status ON public.photography_tasks(sts, ts_crt DESC);

ALTER TABLE public.photography_tasks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Photography tasks read" ON public.photography_tasks;
CREATE POLICY "Photography tasks read" ON public.photography_tasks
FOR SELECT USING (
  auth.uid() = photographer_id
  OR auth.uid() = requested_by
  OR EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role >= 2 AND i_del = 0)
);

DROP POLICY IF EXISTS "Admin can insert photography tasks" ON public.photography_tasks;
CREATE POLICY "Admin can insert photography tasks" ON public.photography_tasks
FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role >= 2 AND i_del = 0)
);

DROP POLICY IF EXISTS "Admin or photographer can update photography tasks" ON public.photography_tasks;
CREATE POLICY "Admin or photographer can update photography tasks" ON public.photography_tasks
FOR UPDATE USING (
  auth.uid() = photographer_id
  OR EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role >= 2 AND i_del = 0)
);

CREATE OR REPLACE FUNCTION public.create_photography_task_internal(p_admin_uid uuid, p_offer_id uuid, p_photographer_id uuid, p_notes text, p_ts_scheduled timestamp with time zone)
 RETURNS SETOF photography_tasks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE v_role INT; v_offer RECORD;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 3 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  SELECT * INTO v_offer FROM offers WHERE id = p_offer_id AND i_del = 0;
  IF NOT FOUND THEN RAISE EXCEPTION 'OFFER_NOT_FOUND'; END IF;
  RETURN QUERY
  INSERT INTO public.photography_tasks (off_id, photographer_id, requested_by, ttl, notes, loc, sts, ts_scheduled, ts_crt, ts_upd)
  VALUES (p_offer_id, p_photographer_id, p_admin_uid, v_offer.ttl, COALESCE(p_notes,''), COALESCE(v_offer.loc,'{}'::jsonb), 0, p_ts_scheduled, NOW(), NOW())
  RETURNING *;
END; $function$

REVOKE ALL ON FUNCTION create_photography_task_internal(p_admin_uid uuid, p_offer_id uuid, p_photographer_id uuid, p_notes text, p_ts_scheduled timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_photography_task_internal(p_admin_uid uuid, p_offer_id uuid, p_photographer_id uuid, p_notes text, p_ts_scheduled timestamp with time zone) TO service_role;

CREATE OR REPLACE FUNCTION public.create_rating_internal(p_reviewer_uid uuid, p_target_uid uuid, p_stars integer, p_comment text DEFAULT ''::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_reviewer_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  INSERT INTO ratings (reviewer_uid, target_uid, stars, comment)
  VALUES (p_reviewer_uid, p_target_uid, p_stars, COALESCE(p_comment, ''));
  RETURN TRUE;
END;
$function$

REVOKE ALL ON FUNCTION create_rating_internal(p_reviewer_uid uuid, p_target_uid uuid, p_stars integer, p_comment text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_rating_internal(p_reviewer_uid uuid, p_target_uid uuid, p_stars integer, p_comment text) TO service_role;

CREATE OR REPLACE FUNCTION public.create_report_internal(p_reporter_uid uuid, p_report jsonb)
 RETURNS SETOF reports
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

REVOKE ALL ON FUNCTION create_report_internal(p_reporter_uid uuid, p_report jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_report_internal(p_reporter_uid uuid, p_report jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.create_request_internal(p_user_uid uuid, p_request jsonb)
 RETURNS SETOF requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

REVOKE ALL ON FUNCTION create_request_internal(p_user_uid uuid, p_request jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_request_internal(p_user_uid uuid, p_request jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.create_user_from_phone(p_phone text, p_nm text DEFAULT ''::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_uid UUID;
  v_phone TEXT;
BEGIN
  v_phone := public.normalize_sy_phone(p_phone);

  SELECT id
  INTO v_uid
  FROM public.users
  WHERE public.normalize_sy_phone(ph) = v_phone
    AND i_del = 0
  LIMIT 1;

  IF v_uid IS NOT NULL THEN
    RETURN v_uid;
  END IF;

  INSERT INTO public.users (nm, ph, role, sts, i_del, ts_crt)
  VALUES (p_nm, v_phone, 0, 0, 0, NOW())
  RETURNING id INTO v_uid;

  PERFORM public.add_points(v_uid, 1000);
  RETURN v_uid;
END;
$function$

REVOKE ALL ON FUNCTION create_user_from_phone(p_phone text, p_nm text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_user_from_phone(p_phone text, p_nm text) TO service_role;

CREATE OR REPLACE FUNCTION public.expire_offers()
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  UPDATE offers
  SET sts = 4, ts_end = NOW()
  WHERE sts = 2
    AND i_del = 0
    AND (
      (ts_ren IS NULL AND COALESCE(ts_pub, ts_crt) < NOW() - INTERVAL '30 days')
      OR
      (ts_ren IS NOT NULL AND ts_end < NOW())
    );
END;
$function$

REVOKE ALL ON FUNCTION expire_offers() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION expire_offers() TO service_role;

CREATE OR REPLACE FUNCTION public.generate_otp(p_phone text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_code TEXT;
  v_int  BIGINT;
BEGIN
  -- نأخذ 3 بايت = 0 .. 16,777,215 ثم نطبّقها mod 900000 + 100000
  v_int := (get_byte(gen_random_bytes(3), 0) * 65536
          + get_byte(gen_random_bytes(3), 1) * 256
          + get_byte(gen_random_bytes(3), 2));
  v_code := LPAD(((v_int % 900000) + 100000)::TEXT, 6, '0');
  INSERT INTO otp_codes (phone, code, expires_at)
    VALUES (p_phone, v_code, NOW() + INTERVAL '5 minutes');
  RETURN v_code;
END;
$function$

REVOKE ALL ON FUNCTION generate_otp(p_phone text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION generate_otp(p_phone text) TO service_role;

CREATE OR REPLACE FUNCTION public.get_admin_appointments_internal(p_admin_uid uuid)
 RETURNS SETOF appointments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 3 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  RETURN QUERY SELECT * FROM appointments ORDER BY ts_crt DESC;
END; $function$

REVOKE ALL ON FUNCTION get_admin_appointments_internal(p_admin_uid uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_admin_appointments_internal(p_admin_uid uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.get_admin_dashboard_stats(p_admin_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_MISMATCH';
  END IF;

  SELECT role INTO v_role
  FROM users
  WHERE id = p_admin_uid
    AND i_del = 0
    AND sts = 0;

  IF v_role IS NULL OR v_role < 4 THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  RETURN jsonb_build_object(
    'totalOffers', (SELECT COUNT(*) FROM offers WHERE i_del = 0),
    'pendingOffers', (SELECT COUNT(*) FROM offers WHERE sts = 1 AND i_del = 0),
    'publishedOffers', (SELECT COUNT(*) FROM offers WHERE sts = 2 AND i_del = 0),

    'totalUsers', (SELECT COUNT(*) FROM users WHERE i_del = 0),
    'activeUsers', (SELECT COUNT(*) FROM users WHERE sts = 0 AND i_del = 0),
    'bannedUsers', (SELECT COUNT(*) FROM users WHERE sts = 2 AND i_del = 0),
    'brokers', (SELECT COUNT(*) FROM users WHERE role = 1 AND i_del = 0),

    'totalDeals', (SELECT COUNT(*) FROM deals WHERE i_del = 0),
    'completedDeals', (SELECT COUNT(*) FROM deals WHERE sts IN (1, 2) AND i_del = 0),
    'totalCommission', COALESCE((SELECT SUM(com_val) FROM deals WHERE sts IN (1, 2) AND i_del = 0), 0),

    'totalAppointments', (SELECT COUNT(*) FROM appointments),
    'completedAppointments', (SELECT COUNT(*) FROM appointments WHERE sts = 2),

    'pendingPayments', (SELECT COUNT(*) FROM payments WHERE sts = 0),
    'approvedPayments', (SELECT COUNT(*) FROM payments WHERE sts IN (1, 2)),
    'openReports', (SELECT COUNT(*) FROM reports WHERE sts = 0),
    'pendingVerifications', (SELECT COUNT(*) FROM users WHERE vrf = 1 AND i_del = 0)
  );
END;
$function$

REVOKE ALL ON FUNCTION get_admin_dashboard_stats(p_admin_uid uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_admin_dashboard_stats(p_admin_uid uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.get_admin_deals_internal(p_admin_uid uuid)
 RETURNS SETOF deals
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 3 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  RETURN QUERY SELECT * FROM deals ORDER BY ts_crt DESC;
END; $function$

REVOKE ALL ON FUNCTION get_admin_deals_internal(p_admin_uid uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_admin_deals_internal(p_admin_uid uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.get_admin_offers_internal(p_admin_uid uuid, p_limit integer DEFAULT 100)
 RETURNS SETOF offers
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 3 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  RETURN QUERY SELECT * FROM offers WHERE i_del = 0 ORDER BY ts_crt DESC LIMIT p_limit;
END; $function$

REVOKE ALL ON FUNCTION get_admin_offers_internal(p_admin_uid uuid, p_limit integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_admin_offers_internal(p_admin_uid uuid, p_limit integer) TO service_role;

CREATE OR REPLACE FUNCTION public.get_admin_payments_internal(p_admin_uid uuid)
 RETURNS SETOF payments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 3 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  RETURN QUERY SELECT * FROM payments ORDER BY ts_crt DESC;
END; $function$

REVOKE ALL ON FUNCTION get_admin_payments_internal(p_admin_uid uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_admin_payments_internal(p_admin_uid uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.get_admin_pending_offers_internal(p_admin_uid uuid)
 RETURNS SETOF offers
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 3 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  RETURN QUERY SELECT * FROM offers WHERE sts = 1 AND i_del = 0 ORDER BY ts_crt DESC;
END; $function$

REVOKE ALL ON FUNCTION get_admin_pending_offers_internal(p_admin_uid uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_admin_pending_offers_internal(p_admin_uid uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.get_admin_reports_internal(p_admin_uid uuid)
 RETURNS SETOF reports
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 3 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  RETURN QUERY SELECT * FROM reports WHERE i_del = 0 ORDER BY ts_crt DESC;
END; $function$

REVOKE ALL ON FUNCTION get_admin_reports_internal(p_admin_uid uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_admin_reports_internal(p_admin_uid uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.get_all_staff_users(p_admin_uid uuid)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin_role INT;
BEGIN
  v_admin_role := public._admin_employee_assert_actor(p_admin_uid, 5);

  RETURN QUERY
    SELECT jsonb_build_object(
      'id', u.id,
      'nm', u.nm,
      'ph', u.ph,
      'eml', u.eml,
      'ad', u.ad,
      'role', u.role,
      'sid', u.sid,
      'img', u.img,
      'pt', u.pt,
      'bg', u.bg,
      'bg_ts', u.bg_ts,
      'b_pkg', u.b_pkg,
      'pkg_end', u.pkg_end,
      'pkg_grace', u.pkg_grace,
      'brk', u.brk,
      'brk_cls', u.brk_cls,
      'brk_nm', u.brk_nm,
      'sts', u.sts,
      'ban_rsn', u.ban_rsn,
      'ntf', u.ntf,
      'stats', u.stats,
      'wk_lgn', u.wk_lgn,
      'strk', u.strk,
      'strk_dt', u.strk_dt,
      'i_del', u.i_del,
      'perm', u.perm,
      'ts_crt', u.ts_crt,
      'ts_upd', u.ts_upd,
      'vrf', u.vrf,
      'ref_by', u.ref_by,
      'ref_cnt', u.ref_cnt,
      'usr', u.usr,
      'pwd', CASE WHEN u.pwd IS NOT NULL THEN 'set' ELSE NULL END,
      'rl', u.rl,
      'device_id', u.device_id,
      'last_ip', u.last_ip,
      'signup_ip', u.signup_ip,
      'device_history', u.device_history
    )
    FROM public.users u
    WHERE u.i_del = 0
      AND u.role IN (2, 3, 4, 5, 6)
    ORDER BY u.role DESC, u.ts_crt DESC;
END;
$function$

REVOKE ALL ON FUNCTION get_all_staff_users(p_admin_uid uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_all_staff_users(p_admin_uid uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.get_broker_appointments_internal(p_broker_uid uuid)
 RETURNS SETOF appointments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

REVOKE ALL ON FUNCTION get_broker_appointments_internal(p_broker_uid uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_broker_appointments_internal(p_broker_uid uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.get_broker_deals_internal(p_broker_uid uuid)
 RETURNS SETOF deals
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

REVOKE ALL ON FUNCTION get_broker_deals_internal(p_broker_uid uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_broker_deals_internal(p_broker_uid uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.get_broker_offers_internal(p_broker_uid uuid)
 RETURNS SETOF offers
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

REVOKE ALL ON FUNCTION get_broker_offers_internal(p_broker_uid uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_broker_offers_internal(p_broker_uid uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.get_offer_by_id_internal(p_offer_id uuid, p_user_uid uuid DEFAULT NULL::uuid)
 RETURNS SETOF offers
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

REVOKE ALL ON FUNCTION get_offer_by_id_internal(p_offer_id uuid, p_user_uid uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_offer_by_id_internal(p_offer_id uuid, p_user_uid uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.get_owner_appointments_internal(p_owner_uid uuid)
 RETURNS SETOF appointments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_owner_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  RETURN QUERY
  SELECT * FROM appointments
  WHERE own_id = p_owner_uid
  ORDER BY dt ASC;
END;
$function$

REVOKE ALL ON FUNCTION get_owner_appointments_internal(p_owner_uid uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_owner_appointments_internal(p_owner_uid uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.get_pending_offers_count()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_cnt INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_cnt
  FROM offers
  WHERE sts = 1
    AND i_del = 0;
  RETURN v_cnt;
END;
$function$

REVOKE ALL ON FUNCTION get_pending_offers_count() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_pending_offers_count() TO service_role;

CREATE OR REPLACE FUNCTION public.get_user_appointments_internal(p_user_uid uuid)
 RETURNS SETOF appointments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  RETURN QUERY
  SELECT * FROM appointments
  WHERE req_uid = p_user_uid
  ORDER BY dt ASC;
END;
$function$

REVOKE ALL ON FUNCTION get_user_appointments_internal(p_user_uid uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_user_appointments_internal(p_user_uid uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.get_user_by_phone(p_phone text)
 RETURNS SETOF users
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN RETURN QUERY SELECT * FROM users WHERE ph = p_phone AND i_del = 0; END;
$function$

REVOKE ALL ON FUNCTION get_user_by_phone(p_phone text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_user_by_phone(p_phone text) TO service_role;

CREATE OR REPLACE FUNCTION public.get_user_notifications_internal(p_user_uid uuid)
 RETURNS SETOF notifications
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

REVOKE ALL ON FUNCTION get_user_notifications_internal(p_user_uid uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_user_notifications_internal(p_user_uid uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.get_user_offers_internal(p_user_uid uuid)
 RETURNS SETOF offers
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

REVOKE ALL ON FUNCTION get_user_offers_internal(p_user_uid uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_user_offers_internal(p_user_uid uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.get_user_payments_internal(p_user_uid uuid)
 RETURNS SETOF payments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  RETURN QUERY
  SELECT * FROM payments
  WHERE uid = p_user_uid
  ORDER BY ts_crt DESC;
END;
$function$

REVOKE ALL ON FUNCTION get_user_payments_internal(p_user_uid uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_user_payments_internal(p_user_uid uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.get_user_requests_internal(p_user_uid uuid)
 RETURNS SETOF requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

REVOKE ALL ON FUNCTION get_user_requests_internal(p_user_uid uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_user_requests_internal(p_user_uid uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.increment_offer_views_internal(p_offer_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  UPDATE offers
  SET vws = COALESCE(vws, 0) + 1
  WHERE id    = p_offer_id
    AND i_del = 0
    AND i_pub = 1;
  RETURN TRUE;
END;
$function$

REVOKE ALL ON FUNCTION increment_offer_views_internal(p_offer_id uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION increment_offer_views_internal(p_offer_id uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.login_with_password(p_identifier text, p_password text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_user RECORD;
  v_identifier TEXT;
  v_norm TEXT;
  v_session JSONB := NULL;
BEGIN
  v_identifier := LOWER(TRIM(p_identifier));
  v_norm := normalize_arabic_username(v_identifier);

  SELECT id, nm, role, pwd, sts, i_del INTO v_user
  FROM users
  WHERE (normalize_arabic_username(usr) = v_norm
         OR normalize_sy_phone(ph) = normalize_sy_phone(v_identifier))
    AND i_del = 0
  LIMIT 1;

  IF v_user IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING HINT = 'لم يتم العثور على حساب بهذا الاسم أو الرقم';
  END IF;

  IF v_user.pwd IS NULL THEN
    RAISE EXCEPTION 'NO_PASSWORD_SET' USING HINT = 'لم يتم تعيين كلمة مرور لهذا الحساب، سجّل دخولك عبر واتساب أولاً';
  END IF;

  IF v_user.sts = 2 THEN
    RAISE EXCEPTION 'USER_BANNED';
  END IF;

  IF v_user.sts = 1 THEN
    RAISE EXCEPTION 'USER_FROZEN';
  END IF;

  IF v_user.pwd != crypt(p_password, v_user.pwd) THEN
    RAISE EXCEPTION 'WRONG_PASSWORD' USING HINT = 'كلمة المرور غير صحيحة';
  END IF;

  -- Always issue session for any authenticated user
  v_session := _issue_staff_session(v_user.id, '', '', INTERVAL '7 days');

  RETURN jsonb_build_object(
    'success', true,
    'user_id', v_user.id,
    'role', v_user.role,
    'nm', v_user.nm,
    'staff_session', v_session
  );
END;
$function$

REVOKE ALL ON FUNCTION login_with_password(p_identifier text, p_password text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION login_with_password(p_identifier text, p_password text) TO service_role;

CREATE OR REPLACE FUNCTION public.mark_all_notifications_read_internal(p_user_uid uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

REVOKE ALL ON FUNCTION mark_all_notifications_read_internal(p_user_uid uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mark_all_notifications_read_internal(p_user_uid uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.mark_notification_read_internal(p_user_uid uuid, p_notification_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

REVOKE ALL ON FUNCTION mark_notification_read_internal(p_user_uid uuid, p_notification_id uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mark_notification_read_internal(p_user_uid uuid, p_notification_id uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.mark_social_published_internal(p_user_uid uuid, p_offer_id uuid, p_text text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  UPDATE offers
  SET soc_pub = 1,
      soc_txt = COALESCE(p_text, '')
  WHERE id = p_offer_id
    AND usr_id = p_user_uid
    AND i_del = 0;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'OFFER_NOT_FOUND_OR_NOT_ALLOWED';
  END IF;
  RETURN TRUE;
END;
$function$

REVOKE ALL ON FUNCTION mark_social_published_internal(p_user_uid uuid, p_offer_id uuid, p_text text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mark_social_published_internal(p_user_uid uuid, p_offer_id uuid, p_text text) TO service_role;

CREATE OR REPLACE FUNCTION public.normalize_sy_phone(p_phone text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v TEXT;
BEGIN
  v := COALESCE(p_phone, '');
  -- ترجمة الأرقام العربية المشرقية (٠-٩) والفارسية (۰-۹) إلى لاتينية (0-9)
  v := translate(v, '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789');
  v := regexp_replace(v, '[^0-9+]', '', 'g');

  IF v = '' THEN
    RETURN '';
  END IF;

  IF left(v, 1) = '+' THEN
    IF left(v, 4) = '+963' THEN
      RETURN v;
    END IF;
    RETURN v;
  END IF;

  IF left(v, 5) = '00963' THEN
    RETURN '+963' || substring(v from 6);
  END IF;

  IF left(v, 3) = '963' THEN
    RETURN '+' || v;
  END IF;

  IF left(v, 1) = '0' THEN
    RETURN '+963' || substring(v from 2);
  END IF;

  IF left(v, 1) = '9' THEN
    RETURN '+963' || v;
  END IF;

  RETURN v;
END;
$function$

REVOKE ALL ON FUNCTION normalize_sy_phone(p_phone text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.normalize_sy_phone(p_phone text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.normalize_sy_phone(p_phone text) TO service_role;

CREATE OR REPLACE FUNCTION public.register_daily_streak_internal(p_user_uid uuid, p_points integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_current_streak INT := 0;
  v_last_ts        TIMESTAMPTZ;
  v_now            TIMESTAMPTZ := NOW();
  v_today          TEXT;
  v_last_day       TEXT;
  v_yesterday      TEXT;
  v_new_streak     INT;
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

  v_today := to_char(
    (v_now AT TIME ZONE 'UTC' + INTERVAL '3 hours')::date,
    'YYYY-MM-DD'
  );

  v_yesterday := to_char(
    ((v_now - INTERVAL '1 day') AT TIME ZONE 'UTC' + INTERVAL '3 hours')::date,
    'YYYY-MM-DD'
  );

  IF v_last_ts IS NOT NULL THEN
    v_last_day := to_char(
      (v_last_ts AT TIME ZONE 'UTC' + INTERVAL '3 hours')::date,
      'YYYY-MM-DD'
    );
  END IF;

  -- نفس اليوم → لا شيء
  IF v_last_day = v_today THEN
    RETURN jsonb_build_object('streak', v_current_streak, 'changed', false, 'awarded', false);
  END IF;

  -- FIX: تصحيح منطق الـ streak
  -- أمس بالضبط → يكمل السلسلة
  -- NULL أو أكثر من يوم → يُصفَّر إلى 1
  v_new_streak := CASE
    WHEN v_last_day IS NULL        THEN 1
    WHEN v_last_day = v_yesterday  THEN v_current_streak + 1
    ELSE                                1
  END;

  UPDATE users
  SET strk    = v_new_streak,
      strk_dt = v_now,
      ts_upd  = v_now
  WHERE id = p_user_uid;

  PERFORM add_points(p_user_uid, p_points);

  RETURN jsonb_build_object('streak', v_new_streak, 'changed', true, 'awarded', true);
END;
$function$

REVOKE ALL ON FUNCTION register_daily_streak_internal(p_user_uid uuid, p_points integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION register_daily_streak_internal(p_user_uid uuid, p_points integer) TO service_role;

CREATE OR REPLACE FUNCTION public.check_username_available(p_username text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_usr TEXT;
  v_norm TEXT;
BEGIN
  BEGIN
    v_usr := public.app_assert_username(p_username, TRUE);
  EXCEPTION WHEN OTHERS THEN
    RETURN FALSE;
  END;
  v_norm := public.normalize_arabic_username(v_usr);
  RETURN NOT EXISTS (
    SELECT 1 FROM public.users
    WHERE public.normalize_arabic_username(usr) = v_norm AND i_del = 0
  );
END;
$function$

REVOKE ALL ON FUNCTION public.check_username_available(TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.check_username_available(TEXT) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_username_available(TEXT) TO service_role;

CREATE OR REPLACE FUNCTION public.register_password(p_user_uid uuid, p_username text, p_password text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_usr TEXT;
  v_norm TEXT;
  v_existing UUID;
BEGIN
  v_usr := public.app_assert_username(p_username, TRUE);
  v_norm := public.normalize_arabic_username(v_usr);
  PERFORM public.app_assert_password(p_password, 8);

  SELECT id INTO v_existing
  FROM public.users
  WHERE public.normalize_arabic_username(usr) = v_norm
    AND i_del = 0
    AND id <> p_user_uid;

  IF v_existing IS NOT NULL THEN
    RAISE EXCEPTION 'USERNAME_TAKEN';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = p_user_uid AND i_del = 0) THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;

  BEGIN
    UPDATE public.users
    SET usr = v_usr,
        pwd = crypt(p_password, gen_salt('bf', 8)),
        ts_upd = NOW()
    WHERE id = p_user_uid;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'USERNAME_TAKEN';
  END;

  RETURN jsonb_build_object('success', true, 'username', v_usr);
END;
$function$

REVOKE ALL ON FUNCTION public.register_password(UUID, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.register_password(UUID, TEXT, TEXT) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_password(UUID, TEXT, TEXT) TO service_role;

CREATE UNIQUE INDEX IF NOT EXISTS ux_users_username_normalized_active
ON public.users (public.normalize_arabic_username(usr))
WHERE usr IS NOT NULL AND NULLIF(BTRIM(usr), '') IS NOT NULL AND i_del = 0;

CREATE OR REPLACE FUNCTION public.revoke_all_staff_sessions(p_user_uid uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count INT;
BEGIN
  UPDATE public.staff_sessions
  SET revoked = 1
  WHERE user_id = p_user_uid
    AND revoked = 0;

  GET DIAGNOSTICS v_count = ROW_COUNT;

  RETURN v_count;
END;
$function$

REVOKE ALL ON FUNCTION revoke_all_staff_sessions(p_user_uid uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION revoke_all_staff_sessions(p_user_uid uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.revoke_staff_session(p_user_uid uuid, p_token text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_session RECORD;
BEGIN
  IF p_user_uid IS NULL OR COALESCE(p_token, '') = '' THEN
    RETURN FALSE;
  END IF;

  FOR v_session IN
    SELECT id, token_hash
    FROM public.staff_sessions
    WHERE user_id = p_user_uid
      AND revoked = 0
  LOOP
    IF v_session.token_hash = crypt(p_token, v_session.token_hash) THEN
      UPDATE public.staff_sessions
      SET revoked = 1
      WHERE id = v_session.id;

      RETURN TRUE;
    END IF;
  END LOOP;

  RETURN FALSE;
END;
$function$

REVOKE ALL ON FUNCTION revoke_staff_session(p_user_uid uuid, p_token text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION revoke_staff_session(p_user_uid uuid, p_token text) TO service_role;

CREATE OR REPLACE FUNCTION public.send_appointment_reminders()
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$ BEGIN
  UPDATE appointments SET rmnd_2 = 1 WHERE sts IN (0, 1) AND i_force = 0 AND dt <= NOW() + INTERVAL '2 hours' AND dt > NOW() AND rmnd_2 = 0;
  UPDATE appointments SET rmnd_24 = 1 WHERE sts IN (0, 1) AND i_force = 0 AND dt <= NOW() + INTERVAL '24 hours' AND dt > NOW() AND rmnd_24 = 0;
END; $function$

REVOKE ALL ON FUNCTION send_appointment_reminders() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION send_appointment_reminders() TO service_role;

CREATE OR REPLACE FUNCTION public.soft_delete(p_table text, p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$ BEGIN EXECUTE format('UPDATE %I SET i_del = 1 WHERE id = %L', p_table, p_id); END; $function$

REVOKE ALL ON FUNCTION soft_delete(p_table text, p_id uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION soft_delete(p_table text, p_id uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.soft_delete_request_internal(p_user_uid uuid, p_request_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  -- Compatibility path: do not erase accountability; mark as user-cancelled.
  RETURN public.cancel_request_internal(p_user_uid, p_request_id, '');
END;
$function$

REVOKE ALL ON FUNCTION soft_delete_request_internal(p_user_uid uuid, p_request_id uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION soft_delete_request_internal(p_user_uid uuid, p_request_id uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.submit_broker_request_internal(p_user_uid uuid, p_business_name text, p_category integer, p_experience text DEFAULT ''::text, p_about text DEFAULT ''::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

REVOKE ALL ON FUNCTION submit_broker_request_internal(p_user_uid uuid, p_business_name text, p_category integer, p_experience text, p_about text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION submit_broker_request_internal(p_user_uid uuid, p_business_name text, p_category integer, p_experience text, p_about text) TO service_role;

CREATE OR REPLACE FUNCTION public.submit_photography_task_internal(p_photographer_uid uuid, p_task_id uuid, p_media jsonb, p_photographer_note text DEFAULT ''::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_photographer_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  IF jsonb_typeof(COALESCE(p_media, '[]'::jsonb)) <> 'array' THEN
    RAISE EXCEPTION 'INVALID_MEDIA_ARRAY';
  END IF;

  UPDATE photography_tasks
  SET media = COALESCE(p_media, '[]'::jsonb),
      photographer_note = COALESCE(p_photographer_note, ''),
      sts = 2,
      ts_submit = NOW(),
      ts_upd = NOW()
  WHERE id = p_task_id
    AND photographer_id = p_photographer_uid
    AND sts IN (0, 1, 4);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'TASK_NOT_FOUND_OR_NOT_ALLOWED';
  END IF;

  RETURN TRUE;
END;
$function$

REVOKE ALL ON FUNCTION submit_photography_task_internal(p_photographer_uid uuid, p_task_id uuid, p_media jsonb, p_photographer_note text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION submit_photography_task_internal(p_photographer_uid uuid, p_task_id uuid, p_media jsonb, p_photographer_note text) TO service_role;

CREATE OR REPLACE FUNCTION public.update_photography_task_status_internal(p_admin_uid uuid, p_task_id uuid, p_status integer, p_office_note text DEFAULT ''::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 3 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  IF p_status < 0 OR p_status > 5 THEN RAISE EXCEPTION 'INVALID_STATUS'; END IF;
  UPDATE photography_tasks
  SET sts = p_status,
      office_note = COALESCE(p_office_note,''),
      ts_done = CASE WHEN p_status IN (3, 4, 5) THEN NOW() ELSE ts_done END,
      ts_upd = NOW()
  WHERE id = p_task_id;
  RETURN FOUND;
END; $function$

REVOKE ALL ON FUNCTION update_photography_task_status_internal(p_admin_uid uuid, p_task_id uuid, p_status integer, p_office_note text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION update_photography_task_status_internal(p_admin_uid uuid, p_task_id uuid, p_status integer, p_office_note text) TO service_role;

CREATE OR REPLACE FUNCTION public.update_request_internal(p_user_uid uuid, p_request_id uuid, p_patch jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

REVOKE ALL ON FUNCTION update_request_internal(p_user_uid uuid, p_request_id uuid, p_patch jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION update_request_internal(p_user_uid uuid, p_request_id uuid, p_patch jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.update_user_badge(p_uid uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE v_pts INTEGER; v_new_bg INTEGER;
BEGIN
  SELECT pt INTO v_pts FROM users WHERE id = p_uid;
  IF v_pts IS NULL THEN RETURN; END IF;
  IF v_pts >= 40000 THEN v_new_bg := 4;
  ELSIF v_pts >= 30000 THEN v_new_bg := 3;
  ELSIF v_pts >= 20000 THEN v_new_bg := 2;
  ELSIF v_pts >= 10000 THEN v_new_bg := 1;
  ELSE v_new_bg := 0; END IF;
  UPDATE users SET bg = v_new_bg, bg_ts = NOW() WHERE id = p_uid AND bg != v_new_bg;
END;
$function$

REVOKE ALL ON FUNCTION update_user_badge(p_uid uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION update_user_badge(p_uid uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.update_user_notification_settings_internal(p_user_uid uuid, p_ntf jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

REVOKE ALL ON FUNCTION update_user_notification_settings_internal(p_user_uid uuid, p_ntf jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION update_user_notification_settings_internal(p_user_uid uuid, p_ntf jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.update_user_profile_internal(p_user_uid uuid, p_payload jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_nm TEXT;
  v_sid TEXT;
  v_ad TEXT;
  v_img TEXT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  v_nm := CASE WHEN p_payload ? 'nm' THEN app_assert_text_len(p_payload->>'nm', 'name', 2, 60) ELSE NULL END;
  v_sid := CASE WHEN p_payload ? 'sid' THEN app_clean_text(p_payload->>'sid', 60) ELSE NULL END;
  v_ad := CASE WHEN p_payload ? 'ad' THEN app_clean_text(p_payload->>'ad', 200) ELSE NULL END;
  v_img := CASE WHEN p_payload ? 'img' THEN app_clean_text(p_payload->>'img', 500) ELSE NULL END;

  UPDATE users
  SET nm = COALESCE(v_nm, nm),
      sid = COALESCE(v_sid, sid),
      ad = COALESCE(v_ad, ad),
      img = COALESCE(v_img, img),
      ts_upd = NOW()
  WHERE id = p_user_uid
    AND i_del = 0;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;
  RETURN TRUE;
END;
$function$

REVOKE ALL ON FUNCTION update_user_profile_internal(p_user_uid uuid, p_payload jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION update_user_profile_internal(p_user_uid uuid, p_payload jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.upsert_user_after_otp(p_identifier text, p_channel text)
 RETURNS TABLE(user_id uuid, is_new boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_uid UUID;
  v_new BOOLEAN := FALSE;
  v_identifier TEXT;
BEGIN
  IF p_channel = 'whatsapp' OR p_channel = 'sms' THEN
    v_identifier := normalize_sy_phone(p_identifier);

    SELECT id INTO v_uid
    FROM users
    WHERE normalize_sy_phone(ph) = v_identifier
      AND i_del = 0
    LIMIT 1;

    IF v_uid IS NULL THEN
      INSERT INTO users (nm, ph, eml, role, sts, i_del, ts_crt)
      VALUES ('', v_identifier, '', 0, 0, 0, NOW())
      RETURNING id INTO v_uid;
      v_new := TRUE;
    END IF;
  ELSIF p_channel = 'email' THEN
    v_identifier := LOWER(TRIM(p_identifier));

    SELECT id INTO v_uid
    FROM users
    WHERE LOWER(COALESCE(eml, '')) = v_identifier
      AND i_del = 0
    LIMIT 1;

    IF v_uid IS NULL THEN
      INSERT INTO users (nm, ph, eml, role, sts, i_del, ts_crt)
      VALUES ('', '', v_identifier, 0, 0, 0, NOW())
      RETURNING id INTO v_uid;
      v_new := TRUE;
    END IF;
  END IF;

  RETURN QUERY SELECT v_uid, v_new;
END;
$function$

REVOKE ALL ON FUNCTION upsert_user_after_otp(p_identifier text, p_channel text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION upsert_user_after_otp(p_identifier text, p_channel text) TO service_role;

CREATE OR REPLACE FUNCTION public.validate_staff_session(p_user_uid uuid, p_token text, p_min_role integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_session RECORD;
  v_user RECORD;
BEGIN
  IF p_user_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'USER_UID_REQUIRED');
  END IF;

  IF COALESCE(p_token, '') = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'SESSION_TOKEN_REQUIRED');
  END IF;

  SELECT id, role, sts, i_del INTO v_user
  FROM public.users
  WHERE id = p_user_uid
    AND i_del = 0;

  IF v_user IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'USER_NOT_FOUND');
  END IF;

  IF v_user.sts <> 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'USER_INACTIVE');
  END IF;

  IF v_user.role < p_min_role THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  FOR v_session IN
    SELECT id, token_hash, expires_at
    FROM public.staff_sessions
    WHERE user_id = p_user_uid
      AND revoked = 0
      AND expires_at > NOW()
    ORDER BY created_at DESC
  LOOP
    IF v_session.token_hash = crypt(p_token, v_session.token_hash) THEN
      UPDATE public.staff_sessions
      SET last_used_at = NOW()
      WHERE id = v_session.id;

      RETURN jsonb_build_object(
        'success', true,
        'user_id', p_user_uid,
        'role', v_user.role,
        'session_id', v_session.id,
        'expires_at', v_session.expires_at
      );
    END IF;
  END LOOP;

  RETURN jsonb_build_object('success', false, 'error', 'INVALID_SESSION');
END;
$function$

REVOKE ALL ON FUNCTION validate_staff_session(p_user_uid uuid, p_token text, p_min_role integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION validate_staff_session(p_user_uid uuid, p_token text, p_min_role integer) TO service_role;

CREATE OR REPLACE FUNCTION public.verify_otp(p_phone text, p_code text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE v_found BOOLEAN;
BEGIN
  SELECT EXISTS(SELECT 1 FROM otp_codes WHERE phone = p_phone AND code = p_code AND used = 0 AND expires_at > NOW()) INTO v_found;
  IF v_found THEN
    UPDATE otp_codes SET used = 1 WHERE phone = p_phone AND code = p_code AND used = 0 AND expires_at > NOW();
    DELETE FROM otp_codes WHERE phone = p_phone AND used = 1;
    RETURN TRUE;
  END IF;
  RETURN FALSE;
END;
$function$

REVOKE ALL ON FUNCTION verify_otp(p_phone text, p_code text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION verify_otp(p_phone text, p_code text) TO service_role;

-- ---------------------------------------------------------------------
-- دوال في setup.sql الأصلي وغير موجودة على الخادم الحيّ (تُركت كما هي):
-- [STALE] admin_update_user_permissions
CREATE OR REPLACE FUNCTION admin_update_user_permissions(
  p_target_uid UUID,
  p_perm JSONB DEFAULT '[]'::jsonb
)
RETURNS BOOLEAN AS $$
DECLARE
  v_admin_role INT;
  v_item TEXT;
  v_allowed TEXT[] := ARRAY[
    'admin_dashboard',
    'office_operations',
    'manage_users',
    'manage_permissions',
    'review_offers',
    'review_verifications',
    'media_review',
    'photography_management',
    'photographer_tasks',
    'fraud_suspects',
    'manage_appointments',
    'manage_deals',
    'manage_payments',
    'manage_reports',
    'manage_config',
    'view_analytics',
    'broker_dashboard',
    'broker_offers',
    'broker_appointments',
    'broker_deals',
    'broker_stats',
    'user_home',
    'user_offers',
    'user_requests',
    'user_appointments',
    'user_photography',
    'user_profile'
  ];
BEGIN
  SELECT role INTO v_admin_role FROM users WHERE id = auth.uid();

  IF v_admin_role IS NULL OR v_admin_role < 3 THEN
    RAISE EXCEPTION 'FORBIDDEN: Deputy/admin role required.';
  END IF;

  IF p_perm IS NULL THEN
    p_perm := '[]'::jsonb;
  END IF;

  IF jsonb_typeof(p_perm) <> 'array' THEN
    RAISE EXCEPTION 'INVALID_PERMISSIONS: Expected JSON array.';
  END IF;

  FOR v_item IN SELECT jsonb_array_elements_text(p_perm)
  LOOP
    IF NOT (v_item = ANY(v_allowed)) THEN
      RAISE EXCEPTION 'INVALID_PERMISSION: %', v_item;
    END IF;
  END LOOP;

  UPDATE users
  SET perm = p_perm,
      ts_upd = NOW()
  WHERE id = p_target_uid
    AND i_del = 0;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION admin_update_user_permissions FROM anon;
GRANT EXECUTE ON FUNCTION admin_update_user_permissions TO authenticated;
-- ---------------------------------------------------------------------

-- =====================================================================
-- 2026-07-04: Expediting task completion flow (lawyer ↔ expediter)
-- =====================================================================
-- =====================================================================
-- Migration: 2026_07_04_expediting_task_completion_flow.sql
-- الغرض:
--   إكمال دورة مهمة التعقيب: إشعار المعقب عند إنشاء المهمة، تأكيد إنجاز
--   المعقب للمهمة، إشعار المحامي، ثم اعتماد المحامي للإنجاز وإشعار المعقب.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.create_expediting_task_internal(
  p_lawyer_uid uuid,
  p_expediter_uid uuid,
  p_item_type integer,
  p_target_property_num text DEFAULT '',
  p_target_zone text DEFAULT '',
  p_lawyer_notes text DEFAULT '',
  p_checklist jsonb DEFAULT '[]'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_task_id uuid;
  v_default_checklist jsonb;
  v_lawyer_role int;
  v_expediter_role int;
BEGIN
  IF p_lawyer_uid IS NULL OR p_expediter_uid IS NULL THEN
    RAISE EXCEPTION 'MISSING_REQUIRED_FIELDS';
  END IF;

  SELECT role INTO v_lawyer_role
  FROM public.users
  WHERE id = p_lawyer_uid AND i_del = 0 AND sts = 0;

  IF v_lawyer_role <> 7 THEN
    RAISE EXCEPTION 'LAWYER_ROLE_REQUIRED';
  END IF;

  SELECT role INTO v_expediter_role
  FROM public.users
  WHERE id = p_expediter_uid AND i_del = 0 AND sts = 0;

  IF v_expediter_role <> 8 THEN
    RAISE EXCEPTION 'EXPEDITER_ROLE_REQUIRED';
  END IF;

  IF p_item_type NOT IN (0, 1) THEN
    RAISE EXCEPTION 'INVALID_ITEM_TYPE';
  END IF;

  IF p_checklist IS NULL OR p_checklist = '[]'::jsonb THEN
    IF p_item_type = 0 THEN
      v_default_checklist := '[
        {"key": "extract", "title": "إخراج قيد عقاري حديث", "status": 0},
        {"key": "area_stmt", "title": "بيان مساحة عقاري", "status": 0},
        {"key": "fin_clearance", "title": "براءة ذمة مالية وبلدية", "status": 0},
        {"key": "fin_record", "title": "قيد مالي للعقار", "status": 0},
        {"key": "sales_tax", "title": "ضريبة البيوع العقارية", "status": 0},
        {"key": "poa_chain", "title": "تسلسل وكالات كاتب بالعدل", "status": 0}
      ]'::jsonb;
    ELSE
      v_default_checklist := '[
        {"key": "traffic_info", "title": "كشف اطلاع مروري", "status": 0},
        {"key": "traffic_clearance", "title": "براءة ذمة مرورية ومخالفات", "status": 0},
        {"key": "tech_inspect", "title": "كشف فني ومطابقة الأرقام", "status": 0},
        {"key": "title_deed", "title": "سند الملكية / ميكانيك المركبة", "status": 0}
      ]'::jsonb;
    END IF;
  ELSE
    v_default_checklist := p_checklist;
  END IF;

  INSERT INTO public.expediting_tasks (
    lawyer_uid, expediter_uid, item_type,
    target_property_num, target_zone,
    checklist, status, lawyer_notes, created_at
  ) VALUES (
    p_lawyer_uid, p_expediter_uid, p_item_type,
    COALESCE(p_target_property_num, ''), COALESCE(p_target_zone, ''),
    v_default_checklist, 0, COALESCE(p_lawyer_notes, ''), NOW()
  ) RETURNING id INTO v_task_id;

  INSERT INTO public.notifications (uid, tp, ttl, bdy, ref_id, act, ts_crt)
  VALUES (
    p_expediter_uid,
    2,
    'مهمة تعقيب جديدة',
    CASE WHEN p_item_type = 0 THEN 'تم تكليفك بمهمة استخراج ثبوتيات عقار جديدة.' ELSE 'تم تكليفك بمهمة استخراج ثبوتيات مركبة جديدة.' END,
    v_task_id::text,
    'expediting_task_assigned',
    NOW()
  );

  RETURN jsonb_build_object('success', true, 'task_id', v_task_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.update_expediting_checklist_item(
  p_actor_uid uuid,
  p_task_id uuid,
  p_item_key text,
  p_status integer,
  p_input_value text DEFAULT '',
  p_attachment_url text DEFAULT '',
  p_notes text DEFAULT ''
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_task record;
  v_new_checklist jsonb := '[]'::jsonb;
  v_item jsonb;
  v_found boolean := false;
BEGIN
  IF p_actor_uid IS NULL THEN
    RAISE EXCEPTION 'USER_UID_REQUIRED';
  END IF;

  IF p_status NOT IN (0, 1, 2, 3) THEN
    RAISE EXCEPTION 'INVALID_STATUS';
  END IF;

  SELECT * INTO v_task
  FROM public.expediting_tasks
  WHERE id = p_task_id
  FOR UPDATE;

  IF v_task IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'TASK_NOT_FOUND');
  END IF;

  IF v_task.expediter_uid <> p_actor_uid AND v_task.lawyer_uid <> p_actor_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  IF v_task.status = 3 THEN
    RETURN jsonb_build_object('success', false, 'error', 'TASK_ALREADY_APPROVED');
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(v_task.checklist)
  LOOP
    IF v_item->>'key' = p_item_key THEN
      v_found := true;
      v_item := jsonb_set(v_item, '{status}', to_jsonb(p_status));
      IF COALESCE(p_input_value, '') <> '' THEN v_item := jsonb_set(v_item, '{input_value}', to_jsonb(p_input_value)); END IF;
      IF COALESCE(p_attachment_url, '') <> '' THEN v_item := jsonb_set(v_item, '{attachment_url}', to_jsonb(p_attachment_url)); END IF;
      IF COALESCE(p_notes, '') <> '' THEN v_item := jsonb_set(v_item, '{notes}', to_jsonb(p_notes)); END IF;
    END IF;
    v_new_checklist := v_new_checklist || v_item;
  END LOOP;

  IF NOT v_found THEN
    RETURN jsonb_build_object('success', false, 'error', 'ITEM_NOT_FOUND');
  END IF;

  UPDATE public.expediting_tasks
  SET checklist = v_new_checklist,
      status = CASE WHEN status < 2 AND p_status IN (1, 2, 3) THEN 1 ELSE status END
  WHERE id = p_task_id;

  RETURN jsonb_build_object('success', true, 'checklist', v_new_checklist);
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_expediting_task_internal(
  p_expediter_uid uuid,
  p_task_id uuid,
  p_notes text DEFAULT ''
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_task record;
  v_expediter_role int;
  v_incomplete int;
BEGIN
  SELECT role INTO v_expediter_role
  FROM public.users
  WHERE id = p_expediter_uid AND i_del = 0 AND sts = 0;

  IF v_expediter_role <> 8 THEN
    RAISE EXCEPTION 'EXPEDITER_ROLE_REQUIRED';
  END IF;

  SELECT * INTO v_task
  FROM public.expediting_tasks
  WHERE id = p_task_id
  FOR UPDATE;

  IF v_task IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'TASK_NOT_FOUND');
  END IF;

  IF v_task.expediter_uid <> p_expediter_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  IF v_task.status = 3 THEN
    RETURN jsonb_build_object('success', false, 'error', 'TASK_ALREADY_APPROVED');
  END IF;

  IF v_task.status = 2 THEN
    RETURN jsonb_build_object('success', true, 'already_completed', true);
  END IF;

  SELECT COUNT(*) INTO v_incomplete
  FROM jsonb_array_elements(v_task.checklist) item
  WHERE COALESCE((item->>'status')::int, 0) <> 2;

  IF v_incomplete > 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'CHECKLIST_NOT_COMPLETE', 'incomplete_count', v_incomplete);
  END IF;

  UPDATE public.expediting_tasks
  SET status = 2,
      completed_at = NOW(),
      expediter_notes = COALESCE(p_notes, expediter_notes)
  WHERE id = p_task_id;

  INSERT INTO public.notifications (uid, tp, ttl, bdy, ref_id, act, ts_crt)
  VALUES (
    v_task.lawyer_uid,
    2,
    'مهمة تعقيب مكتملة',
    'أتم المعقب مهمة التعقيب بنجاح وهي بانتظار اعتمادك.',
    p_task_id::text,
    'expediting_task_completed',
    NOW()
  );

  RETURN jsonb_build_object('success', true, 'status', 2);
END;
$$;

CREATE OR REPLACE FUNCTION public.approve_expediting_task_internal(
  p_lawyer_uid uuid,
  p_task_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_task record;
  v_lawyer_role int;
BEGIN
  SELECT role INTO v_lawyer_role
  FROM public.users
  WHERE id = p_lawyer_uid AND i_del = 0 AND sts = 0;

  IF v_lawyer_role <> 7 THEN
    RAISE EXCEPTION 'LAWYER_ROLE_REQUIRED';
  END IF;

  SELECT * INTO v_task
  FROM public.expediting_tasks
  WHERE id = p_task_id
  FOR UPDATE;

  IF v_task IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'TASK_NOT_FOUND');
  END IF;

  IF v_task.lawyer_uid <> p_lawyer_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  IF v_task.status = 3 THEN
    RETURN jsonb_build_object('success', true, 'already_approved', true);
  END IF;

  IF v_task.status <> 2 THEN
    RETURN jsonb_build_object('success', false, 'error', 'TASK_NOT_COMPLETED_BY_EXPEDITER');
  END IF;

  UPDATE public.expediting_tasks
  SET status = 3
  WHERE id = p_task_id;

  INSERT INTO public.notifications (uid, tp, ttl, bdy, ref_id, act, ts_crt)
  VALUES (
    v_task.expediter_uid,
    2,
    'تم اعتماد مهمة التعقيب',
    'اعتمد المحامي مهمة التعقيب المكتملة. شكراً لجهودك.',
    p_task_id::text,
    'expediting_task_approved',
    NOW()
  );

  RETURN jsonb_build_object('success', true, 'status', 3);
END;
$$;

REVOKE ALL ON FUNCTION public.create_expediting_task_internal(uuid, uuid, integer, text, text, text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_expediting_task_internal(uuid, uuid, integer, text, text, text, jsonb) TO service_role;

REVOKE ALL ON FUNCTION public.update_expediting_checklist_item(uuid, uuid, text, integer, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_expediting_checklist_item(uuid, uuid, text, integer, text, text, text) TO service_role;

REVOKE ALL ON FUNCTION public.complete_expediting_task_internal(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_expediting_task_internal(uuid, uuid, text) TO service_role;

REVOKE ALL ON FUNCTION public.approve_expediting_task_internal(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.approve_expediting_task_internal(uuid, uuid) TO service_role;

-- =====================================================================
-- 2026-07-05: RLS service_role-only policies for internal locked tables
-- =====================================================================
-- =====================================================================
-- Migration: 2026_07_05_rls_service_role_policy_cleanup.sql
-- الغرض:
--   إزالة تحذير RLS Enabled No Policy من الجداول الداخلية المقفلة، بدون فتح
--   أي صلاحية للعميل. السياسات موجهة إلى service_role فقط.
-- =====================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'staff_sessions'
      AND policyname = 'staff_sessions_service_role_all'
  ) THEN
    CREATE POLICY staff_sessions_service_role_all
    ON public.staff_sessions
    FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'stats'
      AND policyname = 'stats_service_role_all'
  ) THEN
    CREATE POLICY stats_service_role_all
    ON public.stats
    FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'user_daily_limits'
      AND policyname = 'user_daily_limits_service_role_all'
  ) THEN
    CREATE POLICY user_daily_limits_service_role_all
    ON public.user_daily_limits
    FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);
  END IF;
END $$;

-- =====================================================================
-- 2026-07-05: Expediting document image upload and lawyer review flow
-- =====================================================================
-- =====================================================================
-- Migration: 2026_07_05_expediting_documents_review_flow.sql
-- الغرض:
--   رفع صور سندات/وثائق التعقيب إلى bucket خاص، وتمكين المحامي من طلب
--   إعادة إنجاز بند محدد إذا كان غير صحيح، مع إشعار المعقب.
-- =====================================================================

INSERT INTO storage.buckets (id, name, public)
VALUES ('expediting_docs', 'expediting_docs', false)
ON CONFLICT (id) DO UPDATE SET public = false;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'expediting_docs_service_role_all'
  ) THEN
    CREATE POLICY expediting_docs_service_role_all
    ON storage.objects
    FOR ALL TO service_role
    USING (bucket_id = 'expediting_docs')
    WITH CHECK (bucket_id = 'expediting_docs');
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.update_expediting_checklist_item(
  p_actor_uid uuid,
  p_task_id uuid,
  p_item_key text,
  p_status integer,
  p_input_value text DEFAULT '',
  p_attachment_url text DEFAULT '',
  p_notes text DEFAULT ''
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_task record;
  v_new_checklist jsonb := '[]'::jsonb;
  v_item jsonb;
  v_found boolean := false;
BEGIN
  IF p_actor_uid IS NULL THEN
    RAISE EXCEPTION 'USER_UID_REQUIRED';
  END IF;

  IF p_status NOT IN (0, 1, 2, 3) THEN
    RAISE EXCEPTION 'INVALID_STATUS';
  END IF;

  SELECT * INTO v_task
  FROM public.expediting_tasks
  WHERE id = p_task_id
  FOR UPDATE;

  IF v_task IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'TASK_NOT_FOUND');
  END IF;

  IF v_task.expediter_uid <> p_actor_uid AND v_task.lawyer_uid <> p_actor_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  IF v_task.status = 3 THEN
    RETURN jsonb_build_object('success', false, 'error', 'TASK_ALREADY_APPROVED');
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(v_task.checklist)
  LOOP
    IF v_item->>'key' = p_item_key THEN
      v_found := true;
      v_item := jsonb_set(v_item, '{status}', to_jsonb(p_status));
      IF COALESCE(p_input_value, '') <> '' THEN
        v_item := jsonb_set(v_item, '{input_value}', to_jsonb(p_input_value));
      END IF;
      IF COALESCE(p_attachment_url, '') <> '' THEN
        v_item := jsonb_set(v_item, '{attachment_url}', to_jsonb(p_attachment_url));
      END IF;
      IF COALESCE(p_notes, '') <> '' THEN
        v_item := jsonb_set(v_item, '{notes}', to_jsonb(p_notes));
      END IF;
    END IF;
    v_new_checklist := v_new_checklist || v_item;
  END LOOP;

  IF NOT v_found THEN
    RETURN jsonb_build_object('success', false, 'error', 'ITEM_NOT_FOUND');
  END IF;

  UPDATE public.expediting_tasks
  SET checklist = v_new_checklist,
      status = CASE
        WHEN p_status IN (0, 1, 3) THEN 1
        WHEN status < 2 AND p_status = 2 THEN 1
        ELSE status
      END,
      completed_at = CASE WHEN p_status IN (0, 1, 3) THEN NULL ELSE completed_at END
  WHERE id = p_task_id;

  RETURN jsonb_build_object('success', true, 'checklist', v_new_checklist);
END;
$$;

CREATE OR REPLACE FUNCTION public.request_expediting_item_revision_internal(
  p_lawyer_uid uuid,
  p_task_id uuid,
  p_item_key text,
  p_revision_notes text DEFAULT ''
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_task record;
  v_role int;
  v_new_checklist jsonb := '[]'::jsonb;
  v_item jsonb;
  v_found boolean := false;
  v_item_title text := '';
BEGIN
  SELECT role INTO v_role
  FROM public.users
  WHERE id = p_lawyer_uid AND i_del = 0 AND sts = 0;

  IF v_role <> 7 THEN
    RAISE EXCEPTION 'LAWYER_ROLE_REQUIRED';
  END IF;

  SELECT * INTO v_task
  FROM public.expediting_tasks
  WHERE id = p_task_id
  FOR UPDATE;

  IF v_task IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'TASK_NOT_FOUND');
  END IF;

  IF v_task.lawyer_uid <> p_lawyer_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  IF v_task.status = 3 THEN
    RETURN jsonb_build_object('success', false, 'error', 'TASK_ALREADY_APPROVED');
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(v_task.checklist)
  LOOP
    IF v_item->>'key' = p_item_key THEN
      v_found := true;
      v_item_title := COALESCE(v_item->>'title', 'وثيقة');
      v_item := jsonb_set(v_item, '{status}', to_jsonb(1));
      v_item := jsonb_set(v_item, '{revision_notes}', to_jsonb(COALESCE(p_revision_notes, '')));
    END IF;
    v_new_checklist := v_new_checklist || v_item;
  END LOOP;

  IF NOT v_found THEN
    RETURN jsonb_build_object('success', false, 'error', 'ITEM_NOT_FOUND');
  END IF;

  UPDATE public.expediting_tasks
  SET checklist = v_new_checklist,
      status = 1,
      completed_at = NULL
  WHERE id = p_task_id;

  INSERT INTO public.notifications (uid, tp, ttl, bdy, ref_id, act, ts_crt)
  VALUES (
    v_task.expediter_uid,
    2,
    'إعادة تدقيق وثيقة تعقيب',
    'طلب المحامي إعادة إنجاز/تصحيح: ' || v_item_title,
    p_task_id::text,
    'expediting_item_revision_requested',
    NOW()
  );

  RETURN jsonb_build_object('success', true, 'status', 1, 'item_key', p_item_key);
END;
$$;

REVOKE ALL ON FUNCTION public.update_expediting_checklist_item(uuid, uuid, text, integer, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_expediting_checklist_item(uuid, uuid, text, integer, text, text, text) TO service_role;

REVOKE ALL ON FUNCTION public.request_expediting_item_revision_internal(uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.request_expediting_item_revision_internal(uuid, uuid, text, text) TO service_role;

-- =====================================================================
-- 2026-07-05: Resource usage monitor for admins
-- =====================================================================
-- =====================================================================
-- Migration: 2026_07_05_resource_usage_monitor.sql
-- الغرض:
--   توفير RPC محصنة لإعطاء الإدارة قياسات دقيقة لحجم قاعدة البيانات
--   وحجم Storage حسب كل bucket. قياس Bandwidth/egress الحقيقي يتطلب
--   Supabase Dashboard/Management API، لذلك نعيد ملاحظة صريحة بهذا الخصوص.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.get_resource_usage_internal(p_admin_uid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage, extensions, pg_catalog, pg_temp
AS $$
DECLARE
  v_role int;
  v_db_bytes bigint := 0;
  v_public_schema_bytes bigint := 0;
  v_storage_schema_bytes bigint := 0;
  v_table_stats jsonb := '[]'::jsonb;
  v_bucket_stats jsonb := '[]'::jsonb;
  v_storage_total_bytes bigint := 0;
  v_storage_total_files bigint := 0;
  v_storage_month_bytes bigint := 0;
  v_storage_month_files bigint := 0;
  v_object_type_stats jsonb := '[]'::jsonb;
BEGIN
  SELECT role INTO v_role
  FROM public.users
  WHERE id = p_admin_uid
    AND i_del = 0
    AND sts = 0;

  IF v_role NOT IN (4, 5, 6) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  SELECT pg_database_size(current_database()) INTO v_db_bytes;

  SELECT COALESCE(SUM(pg_total_relation_size(c.oid)), 0)::bigint
  INTO v_public_schema_bytes
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relkind IN ('r', 'p', 'm');

  SELECT COALESCE(SUM(pg_total_relation_size(c.oid)), 0)::bigint
  INTO v_storage_schema_bytes
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'storage'
    AND c.relkind IN ('r', 'p', 'm');

  SELECT COALESCE(jsonb_agg(row_data ORDER BY (row_data->>'total_bytes')::bigint DESC), '[]'::jsonb)
  INTO v_table_stats
  FROM (
    SELECT jsonb_build_object(
      'schema', n.nspname,
      'table', c.relname,
      'total_bytes', pg_total_relation_size(c.oid),
      'table_bytes', pg_relation_size(c.oid),
      'index_bytes', pg_indexes_size(c.oid),
      'row_estimate', GREATEST(c.reltuples::bigint, 0)
    ) AS row_data
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname IN ('public', 'storage')
      AND c.relkind IN ('r', 'p', 'm')
    ORDER BY pg_total_relation_size(c.oid) DESC
    LIMIT 25
  ) s;

  WITH object_sizes AS (
    SELECT
      b.id AS bucket_id,
      b.public AS is_public,
      o.id AS object_id,
      o.created_at,
      COALESCE(o.metadata->>'mimetype', 'unknown') AS mimetype,
      CASE
        WHEN o.metadata ? 'size' AND (o.metadata->>'size') ~ '^[0-9]+$' THEN (o.metadata->>'size')::bigint
        WHEN o.metadata ? 'contentLength' AND (o.metadata->>'contentLength') ~ '^[0-9]+$' THEN (o.metadata->>'contentLength')::bigint
        ELSE 0
      END AS bytes
    FROM storage.buckets b
    LEFT JOIN storage.objects o ON o.bucket_id = b.id
  ), bucket_rows AS (
    SELECT
      bucket_id,
      is_public,
      COUNT(object_id)::bigint AS file_count,
      COALESCE(SUM(bytes), 0)::bigint AS total_bytes,
      COALESCE(AVG(bytes), 0)::bigint AS avg_bytes,
      COALESCE(MAX(bytes), 0)::bigint AS largest_bytes,
      COALESCE(SUM(bytes) FILTER (WHERE created_at >= date_trunc('month', now())), 0)::bigint AS current_month_uploaded_bytes,
      COUNT(object_id) FILTER (WHERE created_at >= date_trunc('month', now()))::bigint AS current_month_uploaded_files,
      MAX(created_at) AS last_upload_at
    FROM object_sizes
    GROUP BY bucket_id, is_public
  )
  SELECT
    COALESCE(SUM(total_bytes), 0)::bigint,
    COALESCE(SUM(file_count), 0)::bigint,
    COALESCE(SUM(current_month_uploaded_bytes), 0)::bigint,
    COALESCE(SUM(current_month_uploaded_files), 0)::bigint,
    COALESCE(jsonb_agg(jsonb_build_object(
      'bucket_id', bucket_id,
      'public', is_public,
      'file_count', file_count,
      'total_bytes', total_bytes,
      'avg_bytes', avg_bytes,
      'largest_bytes', largest_bytes,
      'current_month_uploaded_bytes', current_month_uploaded_bytes,
      'current_month_uploaded_files', current_month_uploaded_files,
      'last_upload_at', last_upload_at
    ) ORDER BY total_bytes DESC), '[]'::jsonb)
  INTO v_storage_total_bytes, v_storage_total_files, v_storage_month_bytes, v_storage_month_files, v_bucket_stats
  FROM bucket_rows;

  WITH object_sizes AS (
    SELECT
      COALESCE(metadata->>'mimetype', 'unknown') AS mimetype,
      CASE
        WHEN metadata ? 'size' AND (metadata->>'size') ~ '^[0-9]+$' THEN (metadata->>'size')::bigint
        WHEN metadata ? 'contentLength' AND (metadata->>'contentLength') ~ '^[0-9]+$' THEN (metadata->>'contentLength')::bigint
        ELSE 0
      END AS bytes
    FROM storage.objects
  ), type_rows AS (
    SELECT
      mimetype,
      COUNT(*)::bigint AS file_count,
      COALESCE(SUM(bytes), 0)::bigint AS total_bytes
    FROM object_sizes
    GROUP BY mimetype
    ORDER BY SUM(bytes) DESC
    LIMIT 20
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'mimetype', mimetype,
    'file_count', file_count,
    'total_bytes', total_bytes
  ) ORDER BY total_bytes DESC), '[]'::jsonb)
  INTO v_object_type_stats
  FROM type_rows;

  RETURN jsonb_build_object(
    'success', true,
    'generated_at', now(),
    'database', jsonb_build_object(
      'database_name', current_database(),
      'total_bytes', v_db_bytes,
      'public_schema_bytes', v_public_schema_bytes,
      'storage_schema_bytes', v_storage_schema_bytes
    ),
    'storage', jsonb_build_object(
      'total_bytes', v_storage_total_bytes,
      'total_files', v_storage_total_files,
      'current_month_uploaded_bytes', v_storage_month_bytes,
      'current_month_uploaded_files', v_storage_month_files,
      'buckets', v_bucket_stats,
      'by_mimetype', v_object_type_stats
    ),
    'tables', v_table_stats,
    'network', jsonb_build_object(
      'exact_bandwidth_available_from_db', false,
      'note', 'قاعدة البيانات تعطي حجم التخزين وقاعدة البيانات بدقة. أما egress/API bandwidth الحقيقي فيلزم Supabase Dashboard أو Management API/Log Drain.'
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_resource_usage_internal(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_resource_usage_internal(uuid) TO service_role;

-- Phase 2 social publishing: atomic per-platform claim (service role only).
CREATE OR REPLACE FUNCTION public.claim_social_publication(
  p_offer_id UUID,
  p_platform TEXT,
  p_attempt_token UUID
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_row public.social_publications%ROWTYPE;
BEGIN
  IF p_platform NOT IN ('facebook', 'instagram') THEN
    RAISE EXCEPTION 'INVALID_SOCIAL_PLATFORM';
  END IF;
  INSERT INTO public.social_publications
    (offer_id, platform, status, attempt_token, attempts, updated_at)
  VALUES (p_offer_id, p_platform, 'publishing', p_attempt_token, 1, NOW())
  ON CONFLICT (offer_id, platform) DO NOTHING
  RETURNING * INTO v_row;
  IF FOUND THEN RETURN 'claimed'; END IF;

  SELECT * INTO v_row FROM public.social_publications
  WHERE offer_id = p_offer_id AND platform = p_platform FOR UPDATE;
  IF v_row.status = 'published' THEN RETURN 'published'; END IF;
  IF v_row.status IN ('pending', 'failed')
     OR (v_row.status = 'publishing' AND v_row.updated_at < NOW() - INTERVAL '10 minutes') THEN
    UPDATE public.social_publications
    SET status='publishing', attempt_token=p_attempt_token,
        attempts=attempts+1, error_message='', updated_at=NOW()
    WHERE id=v_row.id;
    RETURN 'claimed';
  END IF;
  RETURN 'busy';
END;
$$;
REVOKE ALL ON FUNCTION public.claim_social_publication(UUID, TEXT, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_social_publication(UUID, TEXT, UUID) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_social_publication(UUID, TEXT, UUID) TO service_role;

-- ══════════════════════════════════════════════════════════════════════════════
-- 2026-07-26: قيم افتراضية لتصنيفات وإعدادات شاشة إضافة العرض (app_config / key=main)
-- الهدف: catVeh / carDocTp / plateTp لم يكن لها أي seed رسمي — كانت تضاف يدوياً
--        مما تسبب بعرض تصنيفات العقارات عند اختيار "سيارة" في شاشة إضافة العرض.
-- idempotent: (defaults || value) يضيف فقط المفاتيح الناقصة ولا يمس أي قيمة موجودة.
-- ⚠️ تنبيه: إن كان مفتاح موجوداً بمحتوى خاطئ (مثلاً catVeh منسوخ من العقارات)
--    فهذا البلوك لن يصححه — يحتاج UPDATE مستقل (راجع docs/ADD_OFFER_SCREEN_AUDIT_2026-07-26.md)
-- ══════════════════════════════════════════════════════════════════════════════

INSERT INTO public.app_config (key, value, description)
VALUES ('main', '{}'::jsonb, 'إعدادات التطبيق الرئيسية')
ON CONFLICT (key) DO NOTHING;

-- ⚠️ ملاحظة عن "pkg" بالافتراضيات أعلاه: لا يوجد مفتاح "0" (المجاني) قصداً —
-- غيابه يفعّل fallback الدالة: مستخدم عادي (role 0) ← حصة 1، وسيط (role 1) ← حصة 5.
-- وجود "0" بقيمة o:5 على السيرفر الحي (قيمة يدوية قديمة) كان سبب بلاغ «النشر بلا حدود»
-- بتاريخ 2026-07-26 ويُعالج بـ UPDATE مستقل: UPDATE app_config SET value = value #- '{pkg,0}' WHERE key='main';
UPDATE public.app_config
SET value = $defaults$
{
  "catProp": {
    "0": {"nm": "شقة",          "sub": ["استوديو", "غرفة وصالة", "غرفتين وصالة", "ثلاث غرف وصالة", "دوبلكس", "بنتهاوس"]},
    "1": {"nm": "منزل مستقل",   "sub": ["بيت عربي", "بيت حديث", "فيلا"]},
    "2": {"nm": "أرض",          "sub": ["سكنية", "تجارية", "زراعية", "صناعية"]},
    "3": {"nm": "محل تجاري",    "sub": ["على الشارع", "ضمن سوق", "مكتب", "مستودع"]},
    "4": {"nm": "مزرعة",        "sub": ["مع إنشاءات", "بدون إنشاءات", "بيت جبلي"]},
    "5": {"nm": "بناء كامل",    "sub": ["جديد", "قديم", "هيكل"]}
  },
  "catVeh": {
    "0": {"nm": "سيارة سياحية", "sub": ["سياحية", "هاتشباك", "دفع رباعي (SUV)", "كوبيه", "كابروليه", "ستيشن"]},
    "1": {"nm": "بيك أب / فان", "sub": ["بيك أب", "فان", "ميني باص"]},
    "2": {"nm": "شاحنة / نقل",  "sub": ["شاحنة صغيرة", "شاحنة كبيرة", "صهريج", "براد"]},
    "3": {"nm": "دراجة نارية",  "sub": ["سكوتر", "رياضية", "طرق وعرة"]},
    "4": {"nm": "آليات ومعدات", "sub": ["جرار زراعي", "حفارة", "رافعة", "مولدة كهربائية"]},
    "5": {"nm": "باص",          "sub": ["باص كبير", "ميكروباص"]}
  },
  "docTp": {
    "0": "سند ملكية (طابو أخضر)",
    "1": "حكم محكمة",
    "2": "وكالة قانونية",
    "3": "عقد بيع مبدئي",
    "4": "سند زراعي",
    "5": "أخرى"
  },
  "carDocTp": {
    "0": "دفتر سيارة (ملكية كاملة)",
    "1": "وكالة خاصة",
    "2": "سند مؤقت",
    "3": "أخرى"
  },
  "txts": {
    "videoRequestWhatsApp": "",
    "videoRequestGroupLink": "",
    "appDownloadLink": ""
  },
  "pkg": {
    "1": {"d": 45, "o": 15, "nm": "فضي", "pr": 10},
    "2": {"d": 60, "o": 40, "nm": "ذهبي", "pr": 25},
    "grace_days": 3
  },
  "plateTp": {
    "0": "خصوصي",
    "1": "عمومي",
    "2": "أجرة",
    "3": "حكومي",
    "4": "دخول مؤقت",
    "5": "أخرى"
  }
}
$defaults$::jsonb || value
WHERE key = 'main';
-- =====================================================================
-- توثيق الحسابات: اعتماد / رفض (تستدعى حصراً عبر edge function admin-verifications)
-- ملاحظة: tp=4 (حساب) مطابق لـ NotificationType.account والقيد CHECK (tp BETWEEN 0 AND 5)
-- =====================================================================
CREATE OR REPLACE FUNCTION public.admin_approve_verification_by_admin(p_admin_uid uuid, p_target_uid uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 4 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  UPDATE users SET vrf = 2, ts_upd = NOW() WHERE id = p_target_uid AND i_del = 0 AND vrf = 1;
  IF FOUND THEN
    INSERT INTO notifications (uid, tp, ttl, bdy, ts_crt)
    VALUES (p_target_uid, 4, 'تم اعتماد توثيقك', 'تهانينا! تم اعتماد حسابك رسمياً ✓', NOW());
    PERFORM public.log_admin_action(p_admin_uid, 103, 'اعتماد توثيق الهوية والحساب رسمياً', p_target_uid::TEXT, 'users');
  END IF;
  RETURN FOUND;
END;
$function$;
REVOKE ALL ON FUNCTION admin_approve_verification_by_admin(p_admin_uid uuid, p_target_uid uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_approve_verification_by_admin(p_admin_uid uuid, p_target_uid uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.admin_reject_verification_by_admin(p_admin_uid uuid, p_target_uid uuid, p_reason text DEFAULT ''::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 4 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  IF COALESCE(trim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'REJECTION_REASON_REQUIRED';
  END IF;
  UPDATE users SET vrf = 0, ts_upd = NOW() WHERE id = p_target_uid AND i_del = 0;
  IF FOUND THEN
    INSERT INTO notifications (uid, tp, ttl, bdy, ts_crt)
    VALUES (p_target_uid, 4, 'تم رفض طلب التوثيق', COALESCE(NULLIF(trim(p_reason),''), 'لم يتم قبول الوثائق المرفقة'), NOW());
    PERFORM public.log_admin_action(p_admin_uid, 104, 'رفض توثيق الهوية: ' || trim(p_reason), p_target_uid::TEXT, 'users');
  END IF;
  RETURN FOUND;
END;
$function$;
REVOKE ALL ON FUNCTION admin_reject_verification_by_admin(p_admin_uid uuid, p_target_uid uuid, p_reason text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_reject_verification_by_admin(p_admin_uid uuid, p_target_uid uuid, p_reason text) TO service_role;

-- =====================================================================
-- [drift-closure] دوال موجودة على السيرفر الحي فقط — نسخها إلى setup.sql
-- النسخة مطابقة للـ functions_dump.sql (المصدر الحي الموثوق)
-- =====================================================================

-- الملف الشخصي الكامل (يُستخدم من user-account.get_full_profile و login)
CREATE OR REPLACE FUNCTION public.get_user_full_by_id(p_uid uuid)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  RETURN QUERY
    SELECT jsonb_build_object(
      'id', u.id, 'nm', u.nm, 'ph', u.ph, 'eml', u.eml, 'ad', u.ad, 'role', u.role,
      'sid', u.sid, 'img', u.img, 'pt', u.pt, 'bg', u.bg, 'bg_ts', u.bg_ts,
      'b_pkg', u.b_pkg, 'pkg_end', u.pkg_end, 'pkg_grace', u.pkg_grace,
      'brk', u.brk, 'brk_cls', u.brk_cls, 'brk_nm', u.brk_nm, 'sts', u.sts, 'ban_rsn', u.ban_rsn,
      'ntf', u.ntf, 'stats', u.stats, 'wk_lgn', u.wk_lgn, 'strk', u.strk, 'strk_dt', u.strk_dt,
      'i_del', u.i_del, 'perm', u.perm, 'ts_crt', u.ts_crt, 'ts_upd', u.ts_upd,
      'vrf', u.vrf, 'ref_by', u.ref_by, 'ref_cnt', u.ref_cnt,
      'usr', u.usr,
      'pwd', CASE WHEN u.pwd IS NOT NULL THEN 'set' ELSE NULL END,
      'rl', u.rl, 'device_id', u.device_id, 'last_ip', u.last_ip, 'signup_ip', u.signup_ip,
      'device_history', u.device_history
    )
    FROM users u
    WHERE u.id = p_uid AND u.i_del = 0;
END;
$function$;
REVOKE ALL ON FUNCTION get_user_full_by_id(p_uid uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_user_full_by_id(p_uid uuid) TO service_role;

-- طلب التوثيق الرسمي (يُستدعى من user-account.request_verification عبر service role فقط)
-- يرفع vrf من 0 إلى 1 بعد التحقق من الرقم الوطني والصورة، مع أخطاء مترجمة بالكلاينت:
-- ALREADY_VERIFIED / ALREADY_PENDING / MISSING_DOCUMENTS
CREATE OR REPLACE FUNCTION public.request_verification_by_uid(p_user_uid uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE v RECORD;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN RAISE EXCEPTION 'AUTH_UID_MISMATCH'; END IF;
  SELECT id, sid, img, vrf INTO v FROM users WHERE id = p_user_uid AND i_del = 0;
  IF v.id IS NULL THEN RAISE EXCEPTION 'USER_NOT_FOUND'; END IF;
  IF v.vrf = 2 THEN RAISE EXCEPTION 'ALREADY_VERIFIED'; END IF;
  IF v.vrf = 1 THEN RAISE EXCEPTION 'ALREADY_PENDING'; END IF;
  IF COALESCE(btrim(v.sid), '') = '' OR COALESCE(btrim(v.img), '') = '' THEN RAISE EXCEPTION 'MISSING_DOCUMENTS'; END IF;
  UPDATE users SET vrf = 1, ts_upd = NOW() WHERE id = p_user_uid;
  RETURN TRUE;
END;
$function$;
REVOKE ALL ON FUNCTION request_verification_by_uid(p_user_uid uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION request_verification_by_uid(p_user_uid uuid) TO service_role;


-- purchase_offer_boost (live-only drift) + منطق التجديد المجاني (قرار المالك 2026-07-26):
-- باقة فعالة → تجديد مجاني دائماً | بلا باقة + العرض الوحيد + آخر يومين (غير منتهٍ) → مجاني |
-- زيادة عن الحق بدون باقة أو عرض منتهي الصلاحية → spd.ren نقطة (500 افتراضياً)
-- ترميم 2026-07-26 (باگ التجديد التراكمي): أساس التجديد والمجانية = تاريخ الانتهاء الفعلي
-- (ts_end المحفوظ، وإلا تاريخ النشر/الإنشاء + 30 يوم — مطابق لمنطق الإكسبايري والتطبيق) ثم +30 يوم إضافية.
CREATE OR REPLACE FUNCTION public.purchase_offer_boost(p_uid uuid, p_offer_id uuid, p_boost_type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_owner_id UUID;
  v_now TIMESTAMPTZ := NOW();
  v_result JSONB;
  v_cost INTEGER;
  v_offer_status INTEGER;
  v_config JSONB;
  v_new_balance INTEGER;
  -- متغيرات قاعدة التجديد المجاني
  v_b_pkg INT;
  v_pkg_end TIMESTAMPTZ;
  v_pkg_grace TIMESTAMPTZ;
  v_has_pkg BOOLEAN;
  v_others INT;
  v_ts_end TIMESTAMPTZ;
  v_ts_pub TIMESTAMPTZ;
  v_ts_crt TIMESTAMPTZ;
  v_exp TIMESTAMPTZ;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_UID_MISMATCH');
  END IF;

  SELECT usr_id, sts, ts_end, ts_pub, ts_crt
  INTO v_owner_id, v_offer_status, v_ts_end, v_ts_pub, v_ts_crt
  FROM public.offers WHERE id = p_offer_id AND i_del = 0;

  IF v_owner_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'OFFER_NOT_FOUND');
  END IF;

  IF v_owner_id <> p_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_OWNER');
  END IF;

  SELECT value INTO v_config FROM public.app_config WHERE key = 'main';

  IF p_boost_type = 'ren' THEN
    IF v_offer_status = 3 THEN
      RETURN jsonb_build_object('success', false, 'error', 'REJECTED_OFFER');
    END IF;

    -- (1) باقة فعالة؟ → مجاني دائماً
    SELECT b_pkg, pkg_end, pkg_grace INTO v_b_pkg, v_pkg_end, v_pkg_grace
    FROM public.users WHERE id = p_uid AND i_del = 0;
    v_has_pkg := COALESCE(v_b_pkg, 0) > 0
      AND ( (v_pkg_end IS NOT NULL AND v_pkg_end > v_now)
         OR (v_pkg_grace IS NOT NULL AND v_pkg_grace > v_now) );

    -- تاريخ الانتهاء الفعلي: المحفوظ، وإلا (النشر أو الإنشاء) + 30 يوم — مطابق لمنطق الإكسبايري والتطبيق
    v_exp := COALESCE(v_ts_end, COALESCE(v_ts_pub, v_ts_crt) + INTERVAL '30 days');

    IF v_has_pkg THEN
      v_cost := 0;
    ELSE
      SELECT COUNT(*) INTO v_others FROM public.offers
      WHERE usr_id = p_uid AND i_del = 0 AND id <> p_offer_id AND sts IN (0,1,2,5);

      IF COALESCE(v_others, 0) = 0
         AND v_exp >= v_now AND v_exp <= v_now + INTERVAL '2 days' THEN
        -- (2) بلا باقة + عرض وحيد + ضمن آخر يومين ولم ينتهِ → مجاني
        v_cost := 0;
      ELSIF COALESCE(v_others, 0) = 0 AND v_exp > v_now + INTERVAL '2 days' THEN
        -- مجاني خارج نافذة اليومين → مرفوض (الواجهة تعطّل أساساً، هذا حسم خادمي)
        RETURN jsonb_build_object('success', false, 'error', 'RENEW_TOO_EARLY');
      ELSE
        -- (3) عروض زائدة بلا باقة نشطة، أو عرض منتهي الصلاحية → بالنقاط
        v_cost := COALESCE((v_config->'spd'->>'ren')::INT, 500);
      END IF;
    END IF;
  ELSE
    v_cost := CASE p_boost_type
      WHEN 'pin' THEN COALESCE((v_config->'spd'->>'pin')::INT, 2000)
      WHEN 'bst' THEN COALESCE((v_config->'spd'->>'bst')::INT, 4000)
      WHEN 'dsc5' THEN COALESCE((v_config->'spd'->>'dsc5')::INT, 3000)
      WHEN 'fms' THEN COALESCE((v_config->'spd'->>'fms')::INT, 8000)
      ELSE NULL
    END;
    IF v_cost IS NULL OR v_cost <= 0 THEN
      RETURN jsonb_build_object('success', false, 'error', 'INVALID_BOOST_TYPE');
    END IF;
  END IF;

  -- خصم النقاط ذرّياً (v_cost = 0 يمر تلقائياً للتجديد المجاني)
  UPDATE public.users
  SET pt = pt - v_cost,
      ts_upd = v_now
  WHERE id = p_uid
    AND i_del = 0
    AND sts = 0
    AND COALESCE(pt, 0) >= v_cost
  RETURNING pt INTO v_new_balance;

  IF v_new_balance IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'INSUFFICIENT_POINTS', 'required', v_cost);
  END IF;

  CASE p_boost_type
    WHEN 'ren' THEN
      UPDATE public.offers
      SET ts_end = GREATEST(v_exp, v_now) + INTERVAL '30 days',
          ts_ren = v_now,
          sts = CASE WHEN sts = 4 THEN 2 ELSE sts END,
          i_pub = CASE WHEN sts = 4 THEN 1 ELSE i_pub END
      WHERE id = p_offer_id AND usr_id = p_uid AND i_del = 0;
      v_result := jsonb_build_object('boost_type', 'ren', 'duration_days', 30,
        'new_end', (GREATEST(v_exp, v_now) + INTERVAL '30 days')::TEXT);

    WHEN 'pin' THEN
      UPDATE public.offers
      SET i_pin = 1, pin_end = v_now + INTERVAL '7 days'
      WHERE id = p_offer_id AND usr_id = p_uid AND i_del = 0;
      v_result := jsonb_build_object('boost_type', 'pin', 'duration_days', 7);

    WHEN 'bst' THEN
      UPDATE public.offers
      SET i_bst = 1, bst_end = v_now + INTERVAL '14 days'
      WHERE id = p_offer_id AND usr_id = p_uid AND i_del = 0;
      v_result := jsonb_build_object('boost_type', 'bst', 'duration_days', 14);

    WHEN 'dsc5' THEN
      UPDATE public.offers
      SET dsc_pct = 5, dsc_end = v_now + INTERVAL '60 days'
      WHERE id = p_offer_id AND usr_id = p_uid AND i_del = 0;
      v_result := jsonb_build_object('boost_type', 'dsc5', 'discount_pct', 5, 'duration_days', 60);

    WHEN 'fms' THEN
      UPDATE public.offers
      SET i_fms = 1, fms_end = v_now + INTERVAL '30 days'
      WHERE id = p_offer_id AND usr_id = p_uid AND i_del = 0;
      v_result := jsonb_build_object('boost_type', 'fms', 'duration_days', 30);
  END CASE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'OFFER_UPDATE_FAILED';
  END IF;

  INSERT INTO public.activity_log (uid, act, det, ref_id, ref_col, ts_crt)
  VALUES (
    p_uid, 20,
    'offer_boost: type=' || p_boost_type || ' cost=' || v_cost::TEXT,
    p_offer_id::TEXT, 'offers', v_now
  );

  RETURN jsonb_build_object(
    'success', true,
    'result', v_result,
    'new_balance', v_new_balance,
    'cost', v_cost
  );
END;
$function$;
REVOKE ALL ON FUNCTION purchase_offer_boost(p_uid uuid, p_offer_id uuid, p_boost_type text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION purchase_offer_boost(p_uid uuid, p_offer_id uuid, p_boost_type text) TO service_role;

-- ════════════════════════════════════════════════════════════════════
-- الإعلان المميز المدفوع (قرار المالك 2026-07-26): payments.tp=1
-- المدة 1-4 أسابيع بالمصاري عبر نفس مسار الدفع اليدوي، التفعيل عند موافقة الأدمن
-- ════════════════════════════════════════════════════════════════════
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS meta JSONB NOT NULL DEFAULT '{}';

-- إنشاء دفعة: نفس الأصل + دعم tp=1 (إعلان مميز) مع تحقق الملكية والمدة ومنع التكرار
CREATE OR REPLACE FUNCTION public.create_payment_internal(p_user_uid uuid, p_payment jsonb)
 RETURNS SETOF payments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_user        users%ROWTYPE;
  v_pending_cnt INT;
  v_tp          INT;
  v_offer_id    UUID;
  v_weeks       INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT * INTO v_user
  FROM users WHERE id = p_user_uid AND i_del = 0 AND sts = 0;
  IF v_user.id IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_ACTIVE_OR_NOT_FOUND';
  END IF;

  IF COALESCE(trim(p_payment->>'proof'), '') = '' OR
     COALESCE(trim(p_payment->>'ref'),   '') = '' THEN
    RAISE EXCEPTION 'MISSING_PAYMENT_PROOF_OR_REFERENCE';
  END IF;

  v_tp := COALESCE((p_payment->>'tp')::INT, 0);

  IF v_tp = 1 THEN
    -- إعلان مميز: عرض + مدة (1-4 أسابيع) إلزاميان
    v_offer_id := NULLIF(p_payment->'meta'->>'offer_id', '')::UUID;
    v_weeks := COALESCE((p_payment->'meta'->>'weeks')::INT, 0);
    IF v_offer_id IS NULL OR v_weeks < 1 OR v_weeks > 4 THEN
      RAISE EXCEPTION 'INVALID_FEATURED_AD_META';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM offers WHERE id = v_offer_id AND usr_id = p_user_uid AND i_del = 0) THEN
      RAISE EXCEPTION 'NOT_OFFER_OWNER';
    END IF;
    -- منع دفعتين معلقتين لنفس العرض
    SELECT COUNT(*) INTO v_pending_cnt
    FROM payments
    WHERE uid = p_user_uid AND sts = 0 AND tp = 1
      AND meta->>'offer_id' = v_offer_id::TEXT;
    IF v_pending_cnt > 0 THEN
      RAISE EXCEPTION 'PENDING_PAYMENT_EXISTS';
    END IF;
  ELSE
    -- المنطق الأصلي: منع الدفعة المزدوجة المعلقة لنفس الباقة
    SELECT COUNT(*) INTO v_pending_cnt
    FROM payments
    WHERE uid = p_user_uid
      AND sts = 0
      AND pkg = COALESCE((p_payment->>'pkg')::INT, 0)
      AND tp  = 0;
    IF v_pending_cnt > 0 THEN
      RAISE EXCEPTION 'PENDING_PAYMENT_EXISTS';
    END IF;
  END IF;

  RETURN QUERY
  INSERT INTO payments (
    uid, tp, pkg, amt, cur, mtd, channel, proof, ref, meta, sts, appr_by, ts_crt
  ) VALUES (
    p_user_uid,
    v_tp,
    COALESCE((p_payment->>'pkg')::INT,     0),
    COALESCE((p_payment->>'amt')::NUMERIC, 0),
    COALESCE((p_payment->>'cur')::INT,     1),
    COALESCE((p_payment->>'mtd')::INT,     0),
    COALESCE(p_payment->>'channel', ''),
    COALESCE(p_payment->>'proof',   ''),
    COALESCE(p_payment->>'ref',     ''),
    COALESCE(p_payment->'meta', '{}'::jsonb),
    0,
    NULL,
    NOW()
  ) RETURNING *;
END;
$function$;
REVOKE ALL ON FUNCTION create_payment_internal(p_user_uid uuid, p_payment jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_payment_internal(p_user_uid uuid, p_payment jsonb) TO service_role;

-- موافقة الأدمن: tp=0 تفعيل باقة (كما كان) | tp=1 تفعيل إعلان مميز للعرض بالمدة المدفوعة
CREATE OR REPLACE FUNCTION public.approve_payment_final(p_payment_id uuid, p_admin_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_user_id UUID; v_pkg_id INT; v_admin_role INT;
  v_payment_status INT; v_payment_type INT; v_meta JSONB;
  v_config JSONB; v_pkg_duration INT; v_grace_days INT;
  v_old_pkg INT; v_old_end TIMESTAMPTZ; v_old_xoff INT;
  v_offer UUID; v_weeks INT; v_base TIMESTAMPTZ; v_new_end TIMESTAMPTZ;
  v_new_pkg INT; v_new_xoff INT; v_o_old INT; v_o_new INT;
  v_active BOOLEAN; v_upgraded BOOLEAN := false;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_UID_MISMATCH');
  END IF;
  SELECT role INTO v_admin_role FROM users WHERE id = p_admin_id AND i_del = 0;
  IF v_admin_role IS NULL OR v_admin_role < 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'FORBIDDEN');
  END IF;
  SELECT uid, pkg, sts, tp, meta INTO v_user_id, v_pkg_id, v_payment_status, v_payment_type, v_meta
  FROM payments WHERE id = p_payment_id;
  IF v_user_id IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'PAYMENT_NOT_FOUND'); END IF;
  IF COALESCE(v_payment_status, -1) <> 0 THEN RETURN jsonb_build_object('success', false, 'error', 'PAYMENT_NOT_PENDING'); END IF;
  SELECT value INTO v_config FROM app_config WHERE key = 'main';

  IF COALESCE(v_payment_type, -1) = 0 THEN
    v_pkg_duration := (v_config->'pkg'->(v_pkg_id::text)->>'d')::INT;
    v_grace_days := COALESCE((v_config->'pkg'->>'grace_days')::INT, 3);
    IF v_pkg_duration IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'PKG_DURATION_NOT_FOUND'); END IF;
    SELECT b_pkg, pkg_end, COALESCE(pkg_xoff, 0)
      INTO v_old_pkg, v_old_end, v_old_xoff
      FROM users WHERE id = v_user_id;

    -- نموذج التجميع (2026-07-27): الباقة الجديدة تُضاف للرصيد، ولا يُلغى شيء مدفوع.
    -- ترقية ← سقف القديمة ينتقل للإضافي (pkg_xoff) وتصبح الجديدة الأساس.
    -- تجديد/شراء أدنى ← سقف المشترى يُضاف للإضافي والأساس يبقى الأعلى.
    -- الأيام تُضاف فوق المتبقي دائماً. عند الانتهاء يسقط الكل مع التاريخ الموحد.
    v_active := COALESCE(v_old_pkg, 0) > 0 AND v_old_end IS NOT NULL AND v_old_end > NOW();
    IF v_active THEN
      v_base := v_old_end;
      v_o_old := (v_config->'pkg'->(v_old_pkg::text)->>'o')::INT;
      v_o_new := (v_config->'pkg'->(v_pkg_id::text)->>'o')::INT;
      IF v_pkg_id > v_old_pkg THEN
        v_new_pkg := v_pkg_id;
        v_new_xoff := v_old_xoff + COALESCE(v_o_old, 0);
        v_upgraded := true;
      ELSE
        v_new_pkg := GREATEST(v_old_pkg, v_pkg_id);
        v_new_xoff := v_old_xoff + COALESCE(v_o_new, 0);
      END IF;
    ELSE
      v_base := NOW();
      v_new_pkg := v_pkg_id;
      v_new_xoff := 0;
    END IF;
    v_new_end := v_base + (v_pkg_duration || ' days')::interval;
    UPDATE payments SET sts = 1, appr_by = p_admin_id WHERE id = p_payment_id AND sts = 0;
    UPDATE users SET b_pkg = v_new_pkg, pkg_xoff = v_new_xoff, pkg_end = v_new_end,
      pkg_grace = v_new_end + (v_grace_days || ' days')::interval, ts_upd = NOW()
    WHERE id = v_user_id;
    RETURN jsonb_build_object('success', true, 'type', 'package', 'pkg', v_new_pkg,
      'until', to_char(v_new_end, 'YYYY-MM-DD'),
      'upgraded', v_upgraded, 'stacked', v_active,
      'quota', ((v_config->'pkg'->(v_new_pkg::text)->>'o')::INT + v_new_xoff));
  END IF;

  IF COALESCE(v_payment_type, -1) = 1 THEN
    v_offer := NULLIF(v_meta->>'offer_id', '')::UUID;
    v_weeks := COALESCE((v_meta->>'weeks')::INT, 0);
    IF v_offer IS NULL OR v_weeks < 1 THEN
      RETURN jsonb_build_object('success', false, 'error', 'FEATURED_META_INVALID');
    END IF;
    UPDATE offers
    SET fms_end = GREATEST(NOW(), COALESCE(fms_end, NOW())) + ((v_weeks * 7) || ' days')::interval
    WHERE id = v_offer AND i_del = 0
    RETURNING fms_end INTO v_new_end;
    IF v_new_end IS NULL THEN
      RAISE EXCEPTION 'OFFER_NOT_FOUND';
    END IF;
    UPDATE payments SET sts = 1, appr_by = p_admin_id WHERE id = p_payment_id AND sts = 0;
    RETURN jsonb_build_object('success', true, 'type', 'featured', 'offer_id', v_offer,
      'until', to_char(v_new_end, 'YYYY-MM-DD'));
  END IF;

  RETURN jsonb_build_object('success', false, 'error', 'UNSUPPORTED_PAYMENT_TYPE');
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END; $function$;

REVOKE ALL ON FUNCTION public.approve_payment_final(p_payment_id uuid, p_admin_id uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.approve_payment_final(p_payment_id uuid, p_admin_id uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.approve_payment_final(p_payment_id uuid, p_admin_id uuid) TO service_role;

REVOKE ALL ON FUNCTION admin_set_offer_video(p_admin_uid uuid, p_offer_id uuid, p_has_video boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_set_offer_video(p_admin_uid uuid, p_offer_id uuid, p_has_video boolean) TO service_role;


-- ════════════════════════════════════════════════════════════════════════════
-- 2026-07-27: FCM push fix — المصدر supabase/migrations/2026_07_27_fcm_push_fix.sql
--   (يُبقي setup.sql هو المرجع لتجهيز بيئة جديدة — لا تعديلات هنا، النسخة متطابقة)
-- ════════════════════════════════════════════════════════════════════════════
-- ════════════════════════════════════════════════════════════════════════════
-- 2026-07-27 — إصلاح سلسلة إشعارات FCM الكاملة (4 علل مترابطة)
-- ────────────────────────────────────────────────────────────────────────────
--  ① register_fcm_token: RPC محصّن يستبدل الكتابة المباشرة من التطبيق في
--     user_devices (كانت محظورة بـ RLS منذ 2026-06-28 → صفر أجهزة مسجلة)
--  ② unregister_fcm_token: مسار إلغاء التسجيل عند تسجيل الخروج (نفس العلة)
--  ③ send_push_notification: يرسل ترويسة x-push-secret من جدول internal_config
--     (قفل الـ edge الذي كان مفتوحاً relay للسبام) — السر يُولَّد هنا ولا
--     يُخزَّن في app_config لأن صف fcm مقروء من anon
--  ④ trg_payment_approved: جسم إشعار الرفض يتضمن سبب الرفض الحقيقي من
--     payments.meta->>'reject_reason' بدل النص العام
--
-- التشغيل: الصق الملف كاملاً في SQL Editor وشغّله — كل البلوكات idempotent.
-- بعده مباشرة: SELECT value FROM public.internal_config WHERE key='push_secret';
-- ════════════════════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- ── A) جدول أسرار داخلي: لا منح لأي دور — يُقرأ فقط عبر SECURITY DEFINER ────
CREATE TABLE IF NOT EXISTS public.internal_config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL DEFAULT ''
);
ALTER TABLE public.internal_config ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.internal_config FROM PUBLIC;
REVOKE ALL ON public.internal_config FROM anon;
REVOKE ALL ON public.internal_config FROM authenticated;

-- سياسة رفض صريحة لأدوار العميل على جدول الأسرار الداخلي — توثّق default-deny وتُخضر linter 0008
DROP POLICY IF EXISTS internal_config_client_deny ON public.internal_config;
CREATE POLICY internal_config_client_deny ON public.internal_config
  FOR ALL TO anon, authenticated
  USING (false) WITH CHECK (false);

-- توليد سر الإرسال (48 محرف hex). لا يُكتب في المستودع أبداً.
INSERT INTO public.internal_config(key, value)
VALUES ('push_secret', encode(extensions.gen_random_bytes(24), 'hex'))
ON CONFLICT (key) DO NOTHING;

-- قيد UNIQUE على device_token (مطلوب لـ ON CONFLICT) — موجود أصلاً في الأغلب
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'user_devices_device_token_key'
      AND conrelid = 'public.user_devices'::regclass
  ) THEN
    ALTER TABLE public.user_devices
      ADD CONSTRAINT user_devices_device_token_key UNIQUE (device_token);
  END IF;
END $$;

-- ── B) ① register_fcm_token — تسجيل/تنشيط توكن جهاز المستخدم ────────────────
CREATE OR REPLACE FUNCTION public.register_fcm_token(p_user_uid uuid, p_token text, p_platform text DEFAULT 'android')
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_token TEXT;
  v_exists BOOLEAN;
BEGIN
  -- توافق الهوية عند وجود جلسة Supabase حقيقية (نمط الدوال الداخلية)
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  -- المستخدم موجود وغير محذوف
  SELECT TRUE INTO v_exists FROM public.users
    WHERE id = p_user_uid AND i_del = 0;
  IF v_exists IS NULL THEN RAISE EXCEPTION 'USER_NOT_FOUND'; END IF;

  -- تحقق من التوكن والمنصة
  v_token := BTRIM(COALESCE(p_token, ''));
  IF LENGTH(v_token) < 20 OR LENGTH(v_token) > 512 THEN
    RAISE EXCEPTION 'DEVICE_TOKEN_INVALID';
  END IF;
  IF COALESCE(p_platform, '') NOT IN ('android', 'ios', 'web') THEN
    RAISE EXCEPTION 'PLATFORM_INVALID';
  END IF;

  -- جهاز نشط واحد لكل مستخدم: شطّب أي توكن آخر له
  UPDATE public.user_devices
     SET is_active = FALSE, ts_upd = NOW()
   WHERE uid = p_user_uid
     AND device_token <> v_token
     AND is_active = TRUE;

  -- سجّل/أعد تنشيط هذا التوكن؛ وإن كان مسنداً لمستخدم آخر أعِد إسناده
  INSERT INTO public.user_devices (uid, device_token, platform, is_active, ts_crt, ts_upd)
  VALUES (p_user_uid, v_token, p_platform, TRUE, NOW(), NOW())
  ON CONFLICT (device_token) DO UPDATE
    SET uid = EXCLUDED.uid,
        platform = EXCLUDED.platform,
        is_active = TRUE,
        ts_upd = NOW();

  RETURN TRUE;
END;
$function$;

REVOKE ALL ON FUNCTION public.register_fcm_token(p_user_uid uuid, p_token text, p_platform text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.register_fcm_token(p_user_uid uuid, p_token text, p_platform text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_fcm_token(p_user_uid uuid, p_token text, p_platform text) TO service_role;

-- ── C) ② unregister_fcm_token — إلغاء التوكن عند تسجيل الخروج ────────────────
CREATE OR REPLACE FUNCTION public.unregister_fcm_token(p_user_uid uuid, p_token text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  -- يشطّب فقط سجلاً يملكه هذا المستخدم (لا يمس توكنات الآخرين)
  UPDATE public.user_devices
     SET is_active = FALSE, ts_upd = NOW()
   WHERE device_token = BTRIM(COALESCE(p_token, ''))
     AND uid = p_user_uid;

  RETURN TRUE;
END;
$function$;

REVOKE ALL ON FUNCTION public.unregister_fcm_token(p_user_uid uuid, p_token text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.unregister_fcm_token(p_user_uid uuid, p_token text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.unregister_fcm_token(p_user_uid uuid, p_token text) TO service_role;

-- ── D) ④ trg_payment_approved — سبب الرفض الحقيقي في جسم الإشعار ────────────
CREATE OR REPLACE FUNCTION public.trg_payment_approved()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $$
DECLARE
  v_title TEXT;
  v_body TEXT;
  v_pkg_name TEXT;
  v_reason TEXT;
BEGIN
  IF NEW.sts = OLD.sts THEN RETURN NEW; END IF;

  v_pkg_name := CASE NEW.pkg
    WHEN 1 THEN 'الفضية'
    WHEN 2 THEN 'الذهبية'
    ELSE 'المجانية'
  END;

  IF NEW.sts = 1 THEN -- موافقة
    v_title := '✅ تم تفعيل اشتراكك';
    v_body := 'تم تفعيل الباقة ' || v_pkg_name || ' بنجاح. استمتع بالمزايا الجديدة!';
  ELSIF NEW.sts = 2 THEN -- رفض — مع السبب المسجل في meta
    v_title := '❌ تم رفض الدفعة';
    v_reason := COALESCE(NULLIF(BTRIM(COALESCE(NEW.meta->>'reject_reason', '')), ''), '');
    IF v_reason <> '' THEN
      v_body := 'لم تُقبل الدفعة — السبب: ' || LEFT(v_reason, 140) ||
                ' · صحّح البيانات وأعد الطلب من «سجل دفعاتي».';
    ELSE
      v_body := 'لم تُقبل الدفعة. يرجى مراجعة بيانات الدفع والمحاولة مرة أخرى.';
    END IF;
  ELSE
    RETURN NEW;
  END IF;

  PERFORM notify_user(NEW.uid, 3, v_title, v_body, NEW.id::text, 'payment');
  PERFORM send_push_notification(
    NEW.uid, v_title, v_body,
    jsonb_build_object('type', 'payment', 'id', NEW.id::text)
  );

  RETURN NEW;
END;
$$;

-- ── E) ③ send_push_notification — ترويسة x-push-secret لقفل الـ edge ────────
CREATE OR REPLACE FUNCTION public.send_push_notification(
  p_uid UUID,
  p_title TEXT,
  p_body TEXT,
  p_data JSONB DEFAULT '{}'::jsonb
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $$
DECLARE
  v_config JSONB;
  v_secret TEXT;
  v_request_id BIGINT;
BEGIN
  -- لا نرسل لمستخدم فارغ أو غير موجود
  IF p_uid IS NULL THEN RETURN NULL; END IF;

  SELECT value INTO v_config FROM app_config WHERE key = 'fcm';
  IF v_config IS NULL THEN
    RAISE WARNING 'FCM config not found in app_config';
    RETURN NULL;
  END IF;

  -- السر الداخلي من جدول لا يصله anon (الـ edge يرفض الطلب بدونه)
  SELECT value INTO v_secret FROM public.internal_config WHERE key = 'push_secret';
  IF v_secret IS NULL OR v_secret = '' THEN
    RAISE WARNING 'push_secret missing — شغّل مايغريشن 2026_07_27_fcm_push_fix.sql';
    RETURN NULL;
  END IF;

  -- استدعاء غير متزامن (لا يبطئ trigger)
  SELECT net.http_post(
    url := v_config->>'url',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', v_config->>'anon_key',
      'x-push-secret', v_secret
    ),
    body := jsonb_build_object(
      'uid', p_uid,
      'title', p_title,
      'body', p_body,
      'data', p_data
    )
  ) INTO v_request_id;

  RETURN v_request_id;
EXCEPTION WHEN OTHERS THEN
  -- لا نريد فشل trigger بسبب خطأ في الإشعار
  RAISE WARNING 'send_push_notification failed: %', SQLERRM;
  RETURN NULL;
END;
$$;

-- إبقاء التحصين الحي (مُثبت ببروبات PGRST202) كدفاع إضافي
REVOKE ALL ON FUNCTION public.send_push_notification(p_uid uuid, p_title text, p_body text, p_data jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.send_push_notification(p_uid uuid, p_title text, p_body text, p_data jsonb) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.send_push_notification(p_uid uuid, p_title text, p_body text, p_data jsonb) TO service_role;

-- ============================================================
-- 2026-07-27 — منحة نقاط صاحب العرض عند الاعتماد (تريغر سيرفري)
-- المرايا مع supabase/migrations/2026_07_27_offer_approve_award_points.sql
-- ============================================================
CREATE OR REPLACE FUNCTION public.trg_offer_approved_award_points()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $$
DECLARE
  v_pts INT := 500;
  v_cfg JSONB;
BEGIN
  IF NEW.sts = 2 AND (OLD.sts IS DISTINCT FROM 2) THEN
    IF NEW.usr_id IS NOT NULL AND NEW.i_del = 0 THEN
      SELECT value INTO v_cfg FROM public.app_config WHERE key = 'main';
      IF v_cfg IS NOT NULL AND (v_cfg -> 'pts' ->> 'addO') ~ '^\d+$' THEN
        v_pts := (v_cfg -> 'pts' ->> 'addO')::INT;
      END IF;
      PERFORM public.award_points_safe(NEW.usr_id, 'add_offer', v_pts);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_offer_approved_award_points ON public.offers;
CREATE TRIGGER trg_offer_approved_award_points
  AFTER UPDATE OF sts ON public.offers
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_offer_approved_award_points();

REVOKE ALL ON FUNCTION public.trg_offer_approved_award_points() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.trg_offer_approved_award_points() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.trg_offer_approved_award_points() TO service_role;
