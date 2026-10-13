-- ═══════════════════════════════════════════════════════════════════
-- ⚠️ تصحيح يدوي موثق 2026-07-27 (ليلة الاختبار الشامل):
--  admin_reject_payment_internal ← v2 بثلاثة باراميترات (p_reason)
--  approve_payment_final ← v3 نموذج التراكم + دعم الممولة (tp=1)
--  create_offer_internal ← احتساب pkg_xoff بالسقف
--  القيود: payments_channel_check تشمل syriatel_cash (مايغريشن 2026_06_06 محدّثة)
--  المنح الحية الآن (مُثبتة ببروبات 42501): ثلاثي التحصين مطبق على
--  الدوال الثلاث أعلاه + admin_set_offer_video + get_user_full_by_id
--  + 8 دوال helpers (app_assert_* ×5, app_clean_text, normalize_sy_phone,
--   normalize_arabic_username) — كلها service_role فقط
-- ⚠️ تصحيح يدوي موثق 2026-07-27 (إصلاح سلسلة FCM — مايغريشن 2026_07_27_fcm_push_fix.sql):
--  + register_fcm_token + unregister_fcm_token (service_role فقط) — تسجيل الأجهزة
--    انتقل من كتابة مباشرة محظورة RLS في التطبيق إلى RPC محصّن عبر user-account
--  ~ trg_payment_approved: جسم الرفض يقرأ meta->>'reject_reason'
--  ~ send_push_notification: ترويسة x-push-secret من public.internal_config
-- ═══════════════════════════════════════════════════════════════════
-- Functions Dump — السيرفر الحي
-- التاريخ: 2026-07-27 | عدد الدوال: 176

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
  ) RETURNING id INTO v_session_id;

  RETURN jsonb_build_object(
    'success', true,
    'session_id', v_session_id,
    'session_token', v_token,
    'expires_at', v_expires_at,
    'role', v_role
  );
END;
$function$

CREATE OR REPLACE FUNCTION public.accounts_on_same_device(p_device_id text)
 RETURNS TABLE(uid uuid, name text, signup_at timestamp with time zone, points integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  RETURN QUERY
  SELECT id, nm, ts_crt, pt FROM users
    WHERE device_id = p_device_id AND i_del = 0
    ORDER BY ts_crt;
END;
$function$

CREATE OR REPLACE FUNCTION public.add_points(p_uid uuid, p_pts integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$ BEGIN UPDATE users SET pt = pt + p_pts, ts_upd = NOW() WHERE id = p_uid; PERFORM update_user_badge(p_uid); END; $function$

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
    VALUES (p_target_uid, 10, 'تم اعتماد توثيقك', 'تهانينا! تم اعتماد حسابك رسمياً ✓', NOW());
    PERFORM public.log_admin_action(p_admin_uid, 103, 'اعتماد توثيق الهوية والحساب رسمياً', p_target_uid::TEXT, 'users');
  END IF;
  RETURN FOUND;
END; $function$

CREATE OR REPLACE FUNCTION public.admin_close_request_internal(p_admin_uid uuid, p_request_id uuid, p_status integer, p_reason text DEFAULT 'closed_by_admin'::text, p_note text DEFAULT ''::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

CREATE OR REPLACE FUNCTION public.admin_create_staff_user(p_admin_uid uuid, p_full_name text, p_phone text, p_email text DEFAULT ''::text, p_username text DEFAULT ''::text, p_password text DEFAULT ''::text, p_role integer DEFAULT 4)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  RAISE EXCEPTION 'FULL_IDENTITY_REQUIRED';
END;
$function$

CREATE OR REPLACE FUNCTION public.admin_create_staff_user(p_admin_uid uuid, p_full_name text, p_phone text, p_email text, p_username text, p_password text, p_role integer, p_address text DEFAULT ''::text, p_sid text DEFAULT ''::text, p_img text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

CREATE OR REPLACE FUNCTION public.admin_delete_offer_internal(p_admin_uid uuid, p_offer_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_role INT;
  v_rows INT;
  v_jwt_role TEXT;
BEGIN
  v_jwt_role := COALESCE(auth.jwt()->>'role', '');

  -- السماح فقط لمستخدم مسجّل أن يحذف باسمه، أو service_role من السيرفر
  IF v_jwt_role <> 'service_role' THEN
    IF auth.uid() IS NULL OR auth.uid() <> p_admin_uid THEN
      RAISE EXCEPTION 'AUTH_UID_MISMATCH';
    END IF;

    SELECT u.role
    INTO v_role
    FROM public.users u
    WHERE u.id = p_admin_uid
      AND u.i_del = 0;

    IF v_role IS NULL OR v_role < 2 THEN
      RAISE EXCEPTION 'FORBIDDEN: Admin permissions required';
    END IF;
  END IF;

  UPDATE public.offers
  SET
    i_del = 1,
    sts = 4
  WHERE id = p_offer_id;

  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows = 0 THEN
    RAISE EXCEPTION 'OFFER_NOT_FOUND';
  END IF;

  RETURN TRUE;
END;
$function$

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

CREATE OR REPLACE FUNCTION public.admin_fraud_suspects(p_admin_uid uuid)
 RETURNS SETOF fraud_suspects
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  -- Assert actor role 4 (Employee) or higher
  PERFORM _admin_employee_assert_actor(p_admin_uid, 4);
  
  RETURN QUERY SELECT * FROM fraud_suspects ORDER BY account_count DESC;
END;
$function$

CREATE OR REPLACE FUNCTION public.admin_get_id_signed_path(p_target_uid uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_admin_role INT;
  v_img TEXT;
BEGIN
  SELECT role INTO v_admin_role FROM users WHERE id = auth.uid();
  IF v_admin_role IS NULL OR v_admin_role < 2 THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;
  SELECT img INTO v_img FROM users WHERE id = p_target_uid;
  RETURN v_img;
END;
$function$

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
    VALUES (p_target_uid, 10, 'تم رفض طلب التوثيق', COALESCE(NULLIF(trim(p_reason),''), 'لم يتم قبول الوثائق المرفقة'), NOW());
    PERFORM public.log_admin_action(p_admin_uid, 104, 'رفض توثيق الهوية: ' || trim(p_reason), p_target_uid::TEXT, 'users');
  END IF;
  RETURN FOUND;
END; $function$

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

CREATE OR REPLACE FUNCTION public.admin_set_offer_priority_internal(p_admin_uid uuid, p_offer_id uuid, p_priority_type text, p_duration_days integer DEFAULT 7)
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
  IF v_role IS NULL OR v_role < 2 THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  -- تصفير الأولويات السابقة للعرض
  UPDATE offers SET
    i_pin = 0, pin_end = NULL,
    i_fms = 0, fms_end = NULL,
    i_bst = 0, bst_end = NULL
  WHERE id = p_offer_id;

  -- تعيين الأولوية الجديدة (أو تركها فارغة للوضع العادي)
  IF p_priority_type = 'pin' THEN
    UPDATE offers SET i_pin = 1, pin_end = NOW() + (p_duration_days || ' days')::interval WHERE id = p_offer_id;
  ELSIF p_priority_type = 'fms' THEN
    UPDATE offers SET i_fms = 1, fms_end = NOW() + (p_duration_days || ' days')::interval WHERE id = p_offer_id;
  ELSIF p_priority_type = 'bst' THEN
    UPDATE offers SET i_bst = 1, bst_end = NOW() + (p_duration_days || ' days')::interval WHERE id = p_offer_id;
  END IF;

  RETURN TRUE;
END;
$function$

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
  WHERE id = p_target_uid AND i_del = 0;
  IF v_target_role IS NULL THEN RAISE EXCEPTION 'USER_NOT_FOUND'; END IF;
  IF v_target_role = 6 THEN RAISE EXCEPTION 'CANNOT_MODIFY_MANAGER'; END IF;

  IF p_role NOT IN (2, 3, 4, 5, 7, 8) THEN
    RAISE EXCEPTION 'INVALID_ROLE';
  END IF;

  IF v_admin_role < 6 AND (p_role >= 5 OR v_target_role >= 5) THEN
    RAISE EXCEPTION 'ONLY_MANAGER_CAN_MANAGE_DEPUTIES';
  END IF;

  UPDATE public.users SET role = p_role, ts_upd = NOW() WHERE id = p_target_uid AND i_del = 0;
  PERFORM public._admin_employee_log(p_admin_uid, 'staff_role_update', p_target_uid, jsonb_build_object('old_role', v_target_role, 'new_role', p_role));
  RETURN jsonb_build_object('success', true);
END;
$function$

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

  IF p_role < 0 OR p_role > 8 THEN
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

  RETURN TRUE;
END;
$function$

CREATE OR REPLACE FUNCTION public.admin_upsert_lawyer_profile(p_admin_uid uuid, p_target_uid uuid, p_whatsapp text, p_address text DEFAULT ''::text, p_spec text DEFAULT 'عقارات وسيارات'::text, p_avl jsonb DEFAULT '{}'::jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_actor_role int;
  v_target_role int;
BEGIN
  IF p_admin_uid IS NULL OR p_target_uid IS NULL THEN
    RAISE EXCEPTION 'MISSING_REQUIRED_FIELDS';
  END IF;

  IF COALESCE(TRIM(p_whatsapp), '') = '' THEN
    RAISE EXCEPTION 'WHATSAPP_REQUIRED';
  END IF;

  SELECT role INTO v_actor_role
  FROM public.users
  WHERE id = p_admin_uid AND i_del = 0 AND sts = 0;

  IF v_actor_role IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND_OR_INACTIVE';
  END IF;

  SELECT role INTO v_target_role
  FROM public.users
  WHERE id = p_target_uid AND i_del = 0 AND sts = 0;

  IF v_target_role IS NULL THEN
    RAISE EXCEPTION 'TARGET_USER_NOT_FOUND_OR_INACTIVE';
  END IF;

  -- إدارة ملفات المحامين:
  -- 1) المحامي role=7 يعدّل ملفه فقط.
  -- 2) نائب المدير/المدير فقط role IN (5,6) يعدّلان ملف محامٍ موجود.
  -- 3) لا ترقية أدوار من هذه الدالة؛ تغيير الدور يتم حصراً من إدارة الموظفين.
  IF p_admin_uid = p_target_uid THEN
    IF v_actor_role <> 7 AND v_actor_role NOT IN (5, 6) THEN
      RAISE EXCEPTION 'NOT_AUTHORIZED';
    END IF;
  ELSE
    IF v_actor_role NOT IN (5, 6) THEN
      RAISE EXCEPTION 'NOT_AUTHORIZED';
    END IF;
  END IF;

  IF v_target_role <> 7 THEN
    RAISE EXCEPTION 'TARGET_NOT_LAWYER';
  END IF;

  INSERT INTO public.lawyer_profiles (uid, whatsapp_phone, office_address, specialization, avl, is_active, updated_at)
  VALUES (p_target_uid, TRIM(p_whatsapp), COALESCE(p_address, ''), COALESCE(p_spec, 'عقارات وسيارات'), COALESCE(p_avl, '{}'::jsonb), TRUE, NOW())
  ON CONFLICT (uid) DO UPDATE
  SET whatsapp_phone = EXCLUDED.whatsapp_phone,
      office_address = EXCLUDED.office_address,
      specialization = EXCLUDED.specialization,
      avl = EXCLUDED.avl,
      is_active = TRUE,
      updated_at = NOW();

  RETURN TRUE;
END;
$function$

CREATE OR REPLACE FUNCTION public.admin_wipe_test_data(p_admin_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_admin_role INT;
BEGIN
  v_admin_role := _admin_employee_assert_actor(p_admin_uid, 6); -- التأكد أنه المدير

  -- حذف البيانات بالترتيب لاحترام قيود الجداول
  DELETE FROM reports;
  DELETE FROM deals;
  DELETE FROM payments;
  DELETE FROM appointments;
  DELETE FROM photography_tasks;
  DELETE FROM requests;
  DELETE FROM offers;
  DELETE FROM notifications;
  DELETE FROM otp_codes;
  DELETE FROM activity_log WHERE uid <> p_admin_uid;
  
  -- تم تصحيح اسم الحقل هنا من uid إلى user_id
  DELETE FROM staff_sessions WHERE user_id <> p_admin_uid;
  
  -- حذف كل المستخدمين عدا المدير الحالي
  DELETE FROM users WHERE id <> p_admin_uid;

  RETURN jsonb_build_object('success', true, 'message', 'System wiped successfully');
END;
$function$

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

CREATE OR REPLACE FUNCTION public.apply_referral(p_new_uid uuid, p_referrer_code text, p_pts integer DEFAULT 1500)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_referrer_uid UUID;
  v_recent_refs INT;
  v_new_dev TEXT;
  v_ref_dev TEXT;
  v_new_ip INET;
  v_ref_ip INET;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_new_uid THEN
    RAISE EXCEPTION 'SECURITY: apply_referral can only be called by the new user.';
  END IF;

  SELECT id INTO v_referrer_uid FROM users
    WHERE REPLACE(id::text, '-', '') ILIKE p_referrer_code || '%'
      AND i_del = 0
    LIMIT 1;
  IF v_referrer_uid IS NULL OR v_referrer_uid = p_new_uid THEN
    RETURN FALSE;
  END IF;

  IF EXISTS(SELECT 1 FROM users WHERE id = p_new_uid AND ref_by IS NOT NULL) THEN
    RETURN FALSE;
  END IF;

  -- 🛡️ Phase 9: فحص نفس الجهاز/IP لمنع مزرعة الإحالة
  SELECT device_id, COALESCE(signup_ip, last_ip)
    INTO v_new_dev, v_new_ip FROM users WHERE id = p_new_uid;
  SELECT device_id, COALESCE(signup_ip, last_ip)
    INTO v_ref_dev, v_ref_ip FROM users WHERE id = v_referrer_uid;

  IF v_new_dev IS NOT NULL AND v_new_dev = v_ref_dev THEN
    RAISE EXCEPTION 'FRAUD_DETECTED: Same device.';
  END IF;
  IF v_new_ip IS NOT NULL AND v_new_ip = v_ref_ip THEN
    RAISE EXCEPTION 'FRAUD_DETECTED: Same IP.';
  END IF;

  -- Rate limit 5/h (كما في Phase 8)
  SELECT COUNT(*) INTO v_recent_refs FROM users
    WHERE ref_by = v_referrer_uid AND ts_crt > NOW() - INTERVAL '1 hour';
  IF v_recent_refs >= 5 THEN
    RAISE EXCEPTION 'RATE_LIMIT: Referrer reached 5 referrals/hour cap.';
  END IF;

  UPDATE users SET ref_by = v_referrer_uid WHERE id = p_new_uid;
  UPDATE users SET ref_cnt = COALESCE(ref_cnt, 0) + 1 WHERE id = v_referrer_uid;
  UPDATE users SET pt = pt + p_pts WHERE id IN (p_new_uid, v_referrer_uid);

  PERFORM update_user_badge(p_new_uid);
  PERFORM update_user_badge(v_referrer_uid);

  RETURN TRUE;
END;
$function$

CREATE OR REPLACE FUNCTION public.approve_expediting_task_internal(p_lawyer_uid uuid, p_task_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

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

CREATE OR REPLACE FUNCTION public.appt_booking_config()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
  SELECT '{"any_from":"09:00","any_to":"21:00","gap_mins":60}'::jsonb
         || COALESCE((SELECT value->'appt' FROM public.app_config WHERE key = 'main'), '{}'::jsonb);
$function$

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

CREATE OR REPLACE FUNCTION public.award_points_safe(p_uid uuid, p_event_type text, p_points integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_max_daily INT;
  v_current_count INT;
BEGIN
  -- 1. تحديد الحد اليومي بناءً على نوع الحدث
  v_max_daily := CASE p_event_type
    WHEN 'add_offer' THEN 3   -- بحد أقصى 3 عروض يومياً
    WHEN 'like'      THEN 10  -- بحد أقصى 10 لايكات
    WHEN 'comment'   THEN 5   -- بحد أقصى 5 تعليقات
    WHEN 'share'     THEN 5   -- بحد أقصى 5 مشاركات
    ELSE 999                  -- أحداث أخرى بدون حد (إحالات، صفقات، إلخ)
  END;

  -- 2. فحص العدد الحالي للمستخدم اليوم
  SELECT count INTO v_current_count 
  FROM user_daily_limits 
  WHERE uid = p_uid AND event_type = p_event_type AND event_date = CURRENT_DATE;

  IF v_current_count >= v_max_daily THEN
    RETURN jsonb_build_object('success', false, 'error', 'DAILY_LIMIT_REACHED', 'limit', v_max_daily);
  END IF;

  -- 3. إضافة النقاط
  PERFORM add_points(p_uid, p_points);

  -- 4. تحديث عداد اليوم
  INSERT INTO user_daily_limits (uid, event_type, event_date, count)
  VALUES (p_uid, p_event_type, CURRENT_DATE, 1)
  ON CONFLICT (uid, event_type, event_date) 
  DO UPDATE SET count = user_daily_limits.count + 1;

  RETURN jsonb_build_object('success', true, 'points_added', p_points);
END;
$function$

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

CREATE OR REPLACE FUNCTION public.calculate_commission(p_prc numeric, p_pct numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$ BEGIN RETURN ROUND(p_prc * p_pct / 100, 2); END; $function$

CREATE OR REPLACE FUNCTION public.can_publish_request_internal(p_user_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

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

CREATE OR REPLACE FUNCTION public.cancel_request_internal(p_user_uid uuid, p_request_id uuid, p_reason text DEFAULT ''::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

CREATE OR REPLACE FUNCTION public.change_password_internal(p_user_uid uuid, p_old_password text, p_new_password text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_pwd TEXT;
BEGIN
  SELECT pwd INTO v_pwd FROM users WHERE id = p_user_uid AND i_del = 0;
  IF v_pwd IS NULL THEN
    RAISE EXCEPTION 'NO_PASSWORD_SET';
  END IF;

  IF v_pwd != crypt(p_old_password, v_pwd) THEN
    RAISE EXCEPTION 'WRONG_OLD_PASSWORD';
  END IF;

  IF LENGTH(p_new_password) < 6 THEN
    RAISE EXCEPTION 'PASSWORD_TOO_SHORT';
  END IF;

  UPDATE users SET
    pwd = crypt(p_new_password, gen_salt('bf', 8)),
    ts_upd = NOW()
  WHERE id = p_user_uid;

  RETURN TRUE;
END;
$function$

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

CREATE OR REPLACE FUNCTION public.check_offer_safe_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF auth.uid() = OLD.usr_id THEN
    IF NEW.usr_id IS DISTINCT FROM OLD.usr_id THEN
      RAISE EXCEPTION 'SECURITY: Cannot change offer ownership.';
    END IF;
    -- منع تغيير العمولة/الترقيات يدوياً
    IF NEW.com IS DISTINCT FROM OLD.com THEN
      RAISE EXCEPTION 'SECURITY: Commission is admin/server-only.';
    END IF;
    IF NEW.i_pin IS DISTINCT FROM OLD.i_pin
       OR NEW.i_bst IS DISTINCT FROM OLD.i_bst
       OR NEW.i_fms IS DISTINCT FROM OLD.i_fms THEN
      RAISE EXCEPTION 'SECURITY: Boost flags via purchase_offer_boost RPC only.';
    END IF;
    -- منع تغيير عداد المشاهدات يدوياً
    IF NEW.vws > OLD.vws + 1 THEN
      RAISE EXCEPTION 'SECURITY: Views can only increment by 1.';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$

CREATE OR REPLACE FUNCTION public.check_rating_valid()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_has_completed BOOLEAN;
BEGIN
  -- نسمح بالتقييم إذا:
  --  (أ) موعد فعلي مع المستهدف اكتمل (sts=2)، أو
  --  (ب) صفقة فعلية بين الطرفين، أو
  --  (ج) المُقيِّم وسيط للمستهدف
  SELECT EXISTS (
    SELECT 1 FROM appointments a
    JOIN offers o ON o.id = a.off_id
    WHERE (a.own_id = NEW.target_uid AND o.usr_id = NEW.target_uid)
      AND a.sts = 2
      AND EXISTS (
        SELECT 1 FROM appointments a2
        WHERE a2.off_id = a.off_id
          AND a2.sts = 2
          -- المُقيِّم له موعد منتهٍ على نفس العرض
          AND (a2.bkr_id = NEW.reviewer_uid
               OR EXISTS (SELECT 1 FROM deals d
                          WHERE d.app_id = a2.id
                          AND (d.buy_uid = NEW.reviewer_uid
                               OR d.sell_uid = NEW.reviewer_uid)))
      )
  ) OR EXISTS (
    SELECT 1 FROM deals d
    WHERE d.sts = 1
      AND ((d.sell_uid = NEW.target_uid AND d.buy_uid = NEW.reviewer_uid)
        OR (d.buy_uid = NEW.target_uid AND d.sell_uid = NEW.reviewer_uid))
  ) INTO v_has_completed;

  IF NOT v_has_completed THEN
    RAISE EXCEPTION 'SECURITY: You can only rate users you have completed a deal/appointment with.';
  END IF;
  RETURN NEW;
END;
$function$

CREATE OR REPLACE FUNCTION public.check_user_safe_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  -- إذا auth.uid() NULL → SECURITY DEFINER من upsert_user_after_otp → نسمح
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;
  IF auth.uid() = NEW.id THEN
    IF NEW.role > 0 THEN
      RAISE EXCEPTION 'SECURITY: New users must start with role=0.';
    END IF;
    IF NEW.vrf > 0 THEN
      RAISE EXCEPTION 'SECURITY: New users start unverified.';
    END IF;
    IF COALESCE(NEW.pt, 0) > 0 THEN
      RAISE EXCEPTION 'SECURITY: New users start with 0 points. Use add_points RPC.';
    END IF;
    IF COALESCE(NEW.bg, 0) > 0 THEN
      RAISE EXCEPTION 'SECURITY: New users start with badge=0.';
    END IF;
    IF COALESCE(NEW.brk, 0) > 0 THEN
      RAISE EXCEPTION 'SECURITY: Broker status requires admin approval.';
    END IF;
    IF COALESCE(NEW.b_pkg, 0) > 0 THEN
      RAISE EXCEPTION 'SECURITY: Package must come via payment approval.';
    END IF;
    IF NEW.nm IS NOT NULL AND (
       NEW.nm ILIKE '%مكتب%' OR NEW.nm ILIKE '%إدارة%' OR
       NEW.nm ILIKE '%admin%' OR NEW.nm ILIKE '%مدير%' OR
       NEW.nm ILIKE '%إداري%' OR NEW.nm ILIKE '%official%'
    ) THEN
      RAISE EXCEPTION 'SECURITY: Display name contains reserved keywords.';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$

CREATE OR REPLACE FUNCTION public.check_user_safe_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  IF auth.uid() = NEW.id THEN
    IF NEW.role IS DISTINCT FROM OLD.role THEN
      RAISE EXCEPTION 'SECURITY: Cannot self-modify role. Use admin panel.';
    END IF;
    IF NEW.vrf IS DISTINCT FROM OLD.vrf THEN
      IF NOT (OLD.vrf = 0 AND NEW.vrf = 1) THEN
        RAISE EXCEPTION 'SECURITY: vrf can only go 0->1 by user; use admin RPC for approval.';
      END IF;
    END IF;
    IF NEW.pt IS DISTINCT FROM OLD.pt THEN
      RAISE EXCEPTION 'SECURITY: Points must be modified via add_points/award_points_safe RPC.';
    END IF;
    IF NEW.bg IS DISTINCT FROM OLD.bg THEN
      RAISE EXCEPTION 'SECURITY: Badge is computed by update_user_badge only.';
    END IF;
    IF NEW.brk IS DISTINCT FROM OLD.brk THEN
      RAISE EXCEPTION 'SECURITY: Broker activation requires admin approval.';
    END IF;
    IF NEW.b_pkg IS DISTINCT FROM OLD.b_pkg THEN
      RAISE EXCEPTION 'SECURITY: Package must be set via payment approval flow.';
    END IF;
    IF NEW.pkg_end IS DISTINCT FROM OLD.pkg_end THEN
      RAISE EXCEPTION 'SECURITY: Package expiry is server-managed.';
    END IF;
    IF NEW.pkg_grace IS DISTINCT FROM OLD.pkg_grace THEN
      RAISE EXCEPTION 'SECURITY: Package grace period is server-managed.';
    END IF;
    IF NEW.ref_by IS DISTINCT FROM OLD.ref_by THEN
      RAISE EXCEPTION 'SECURITY: Referrer is set only by apply_referral.';
    END IF;
    IF NEW.ref_cnt IS DISTINCT FROM OLD.ref_cnt THEN
      RAISE EXCEPTION 'SECURITY: Referral counter is server-managed.';
    END IF;
    IF NEW.sts IS DISTINCT FROM OLD.sts THEN
      RAISE EXCEPTION 'SECURITY: Account status is admin-only.';
    END IF;
    IF NEW.ban_rsn IS DISTINCT FROM OLD.ban_rsn THEN
      RAISE EXCEPTION 'SECURITY: Ban reason is admin-only.';
    END IF;
    IF NEW.nm IS DISTINCT FROM OLD.nm AND (
       NEW.nm ILIKE '%مكتب%' OR NEW.nm ILIKE '%إدارة%' OR
       NEW.nm ILIKE '%admin%' OR NEW.nm ILIKE '%مدير%' OR
       NEW.nm ILIKE '%إداري%' OR NEW.nm ILIKE '%official%'
    ) THEN
      RAISE EXCEPTION 'SECURITY: Display name contains reserved keywords.';
    END IF;
  END IF;

  RETURN NEW;
END;
$function$

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

CREATE OR REPLACE FUNCTION public.complete_expediting_task_internal(p_expediter_uid uuid, p_task_id uuid, p_notes text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

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

CREATE OR REPLACE FUNCTION public.create_expediting_task_internal(p_lawyer_uid uuid, p_expediter_uid uuid, p_item_type integer, p_target_property_num text DEFAULT ''::text, p_target_zone text DEFAULT ''::text, p_lawyer_notes text DEFAULT ''::text, p_checklist jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

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
$function$;

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
  INSERT INTO photography_tasks (offer_id, photographer_id, assigned_by, title, notes, loc, sts, ts_scheduled, ts_crt, ts_upd)
  VALUES (p_offer_id, p_photographer_id, p_admin_uid, v_offer.ttl, COALESCE(p_notes,''), COALESCE(v_offer.loc,'{}'::jsonb), 0, p_ts_scheduled, NOW(), NOW())
  RETURNING *;
END; $function$

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

CREATE OR REPLACE FUNCTION public.expire_offer_boosts()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE v_count INTEGER := 0;
BEGIN
  -- إلغاء pin المنتهي
  UPDATE offers SET i_pin = 0, pin_end = NULL
    WHERE i_pin = 1 AND pin_end < NOW();
  GET DIAGNOSTICS v_count = ROW_COUNT;

  -- إلغاء boost المنتهي
  UPDATE offers SET i_bst = 0, bst_end = NULL
    WHERE i_bst = 1 AND bst_end < NOW();

  -- إلغاء featured المنتهي
  UPDATE offers SET i_fms = 0, fms_end = NULL
    WHERE i_fms = 1 AND fms_end < NOW();

  -- إلغاء الخصم المنتهي
  UPDATE offers SET dsc_pct = 0, dsc_end = NULL
    WHERE dsc_pct > 0 AND dsc_end < NOW();

  RETURN v_count;
END;
$function$

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

CREATE OR REPLACE FUNCTION public.expire_packages()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_count  INTEGER := 0;
  v_rec    RECORD;
BEGIN
  -- نُعيد b_pkg=0 فقط للمستخدمين الذين تجاوزوا pkg_grace (فترة السماح)
  -- إذا pkg_grace NULL نعتمد على pkg_end مباشرة (للسجلات القديمة)
  FOR v_rec IN
    SELECT id, b_pkg
    FROM users
    WHERE b_pkg  > 0
      AND i_del  = 0
      AND (
        -- سجلات جديدة: انتهت فترة السماح
        (pkg_grace IS NOT NULL AND pkg_grace < NOW())
        OR
        -- سجلات قديمة بدون pkg_grace: انتهت pkg_end
        (pkg_grace IS NULL AND pkg_end IS NOT NULL AND pkg_end < NOW())
      )
  LOOP
    UPDATE users
    SET b_pkg  = 0,
        ts_upd = NOW()
    WHERE id = v_rec.id;

    -- إشعار المستخدم بانتهاء الباقة
    PERFORM notify_user(
      v_rec.id, 3,
      '⚠️ انتهت باقتك',
      'انتهت فترة السماح لباقتك. تم تحويلك للباقة المجانية. '
      'يمكنك تجديد اشتراكك في أي وقت من شاشة الباقات.',
      NULL, 'payment'
    );

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$function$

CREATE OR REPLACE FUNCTION public.expire_requests()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

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

CREATE OR REPLACE FUNCTION public.generate_otp_v2(p_identifier text, p_channel text DEFAULT 'sms'::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
  DECLARE
    v_code TEXT;
    v_count INT;
  BEGIN
    -- حماية من السبام: الحد الأقصى 5 طلبات كل 10 دقائق
    SELECT COUNT(*) INTO v_count FROM otp_codes
      WHERE identifier = p_identifier
        AND ts_crt > NOW() - INTERVAL '10 minutes';

    IF v_count >= 5 THEN
      RAISE EXCEPTION 'Too many OTP requests. Please wait a few minutes.';
    END IF;

    -- توليد رمز عشوائي آمن
    v_code := LPAD(FLOOR(RANDOM() * 900000 + 100000)::TEXT, 6, '0');

    -- التخزين في العمود الموحد فقط
    INSERT INTO otp_codes (identifier, channel, code, expires_at, used)
      VALUES (p_identifier, p_channel, v_code, NOW() + INTERVAL '10 minutes', 0);

    RETURN v_code;
  END;
$function$

CREATE OR REPLACE FUNCTION public.get_active_lawyers()
 RETURNS TABLE(uid uuid, nm text, ph text, whatsapp_phone text, office_address text, specialization text, avl jsonb, active_tasks_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
    RETURN QUERY
    SELECT lp.uid, COALESCE(u.nm, ''), COALESCE(u.ph, ''), lp.whatsapp_phone, lp.office_address, lp.specialization, lp.avl, lp.active_tasks_count
    FROM lawyer_profiles lp
    JOIN users u ON u.id = lp.uid
    WHERE lp.is_active = TRUE AND u.i_del = 0;
END;
$function$

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

CREATE OR REPLACE FUNCTION public.get_admin_requests_internal(p_admin_uid uuid)
 RETURNS TABLE(id uuid, typ integer, elm integer, cl_nm text, cl_ph text, prc numeric, cur integer, notes text, specs jsonb, usr_id uuid, sts integer, matches jsonb, i_del integer, ts_crt timestamp with time zone, ts_end timestamp with time zone, ts_ren timestamp with time zone, rmnd_ren integer, closed_at timestamp with time zone, closed_by uuid, closed_by_name text, closed_by_role integer, closed_reason text, closed_note text, closed_offer_id uuid, closed_appointment_id uuid, closed_completion_request_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

CREATE OR REPLACE FUNCTION public.get_all_pending_completion_requests(p_admin_uid uuid DEFAULT NULL::uuid)
 RETURNS TABLE(request_id uuid, appointment_id uuid, off_id uuid, display_title text, offer_number text, task_type text, client_name text, client_phone text, executor_name text, executor_notes text, request_date timestamp with time zone, appointment_date timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

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
      'id', u.id, 'nm', u.nm, 'ph', u.ph, 'eml', u.eml, 'ad', u.ad,
      'role', u.role, 'sid', u.sid, 'img', u.img, 'pt', u.pt, 'bg', u.bg,
      'bg_ts', u.bg_ts, 'b_pkg', u.b_pkg, 'pkg_end', u.pkg_end, 'pkg_grace', u.pkg_grace,
      'brk', u.brk, 'brk_cls', u.brk_cls, 'brk_nm', u.brk_nm,
      'sts', u.sts, 'ban_rsn', u.ban_rsn, 'ntf', u.ntf, 'stats', u.stats,
      'wk_lgn', u.wk_lgn, 'strk', u.strk, 'strk_dt', u.strk_dt, 'i_del', u.i_del,
      'perm', u.perm, 'ts_crt', u.ts_crt, 'ts_upd', u.ts_upd, 'vrf', u.vrf,
      'ref_by', u.ref_by, 'ref_cnt', u.ref_cnt, 'usr', u.usr,
      'pwd', CASE WHEN u.pwd IS NOT NULL THEN 'set' ELSE NULL END,
      'rl', u.rl, 'device_id', u.device_id, 'last_ip', u.last_ip, 'signup_ip', u.signup_ip, 'device_history', u.device_history
    )
    FROM public.users u
    WHERE u.i_del = 0
      AND u.role IN (2, 3, 4, 5, 6, 7, 8)
    ORDER BY u.role DESC, u.ts_crt DESC;
END;
$function$

CREATE OR REPLACE FUNCTION public.get_available_expediters()
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  RETURN QUERY
  SELECT jsonb_build_object(
    'id', u.id,
    'nm', u.nm,
    'ph', u.ph
  )
  FROM public.users u
  WHERE u.role = 8 AND u.sts = 0 AND u.i_del = 0
  ORDER BY u.nm;
END;
$function$

CREATE OR REPLACE FUNCTION public.get_available_supervisor(p_dt timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_uid UUID;
  v_gap INT := (public.appt_booking_config()->>'gap_mins')::INT;
BEGIN
  SELECT u.id INTO v_uid
  FROM public.users u
  WHERE u.role = 3 AND u.sts = 0 AND u.i_del = 0
    AND NOT EXISTS (
      SELECT 1 FROM public.appointments a
      WHERE a.supervisor_uid = u.id
        AND a.sts IN (0, 1)
        AND a.dt > p_dt - make_interval(mins => v_gap)
        AND a.dt < p_dt + make_interval(mins => v_gap)
    )
  ORDER BY (
    SELECT COUNT(*) FROM public.appointments a2
    WHERE a2.supervisor_uid = u.id AND a2.sts IN (0, 1)
  ) ASC, u.ts_crt ASC
  LIMIT 1;

  IF v_uid IS NULL THEN RAISE EXCEPTION 'NO_SUPERVISOR_AVAILABLE'; END IF;
  RETURN v_uid;
END;
$function$

CREATE OR REPLACE FUNCTION public.get_booked_slots_internal(p_offer_id uuid, p_date date)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
  SELECT COALESCE(
    array_agg(to_char(dt AT TIME ZONE 'Asia/Damascus', 'HH24:MI') ORDER BY dt),
    '{}'::text[]
  )
  FROM public.appointments
  WHERE off_id = p_offer_id
    AND sts IN (0, 1)
    AND (dt AT TIME ZONE 'Asia/Damascus')::date = p_date;
$function$

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

CREATE OR REPLACE FUNCTION public.get_completed_tasks(p_user_uid uuid DEFAULT NULL::uuid)
 RETURNS TABLE(appointment_id uuid, off_id uuid, offer_number text, display_title text, task_type text, client_name text, client_phone text, appointment_date timestamp with time zone, location jsonb, description text, price numeric, offer_cur integer, outcome text, completion_date timestamp with time zone, rejection_reason text, sts integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

CREATE OR REPLACE FUNCTION public.get_executor_task_by_appointment(p_user_uid uuid, p_appointment_id uuid)
 RETURNS TABLE(appointment_id uuid, off_id uuid, offer_number text, display_title text, task_type text, client_name text, client_phone text, appointment_date timestamp with time zone, location jsonb, description text, price numeric, offer_cur integer, outcome text, completion_date timestamp with time zone, rejection_reason text, sts integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_role INT;
BEGIN
  IF p_user_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_MISMATCH';
  END IF;

  SELECT role INTO v_role FROM public.users WHERE id = p_user_uid AND i_del = 0 AND sts = 0;
  IF v_role IS NULL OR v_role < 3 THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  RETURN QUERY
  SELECT
    a.id AS appointment_id,
    a.off_id,
    COALESCE(o.offer_number::text, o.ttl, '') AS offer_number,
    COALESCE(o.ttl, '') AS display_title,
    CASE WHEN o.typ = 0 THEN 'property' ELSE 'car' END AS task_type,
    ''::TEXT AS client_name,
    ''::TEXT AS client_phone,
    a.dt AS appointment_date,
    COALESCE(o.loc, '{}'::jsonb) AS location,
    COALESCE(o.descript, '') AS description,
    COALESCE(o.prc, 0) AS price,
    COALESCE(o.cur, 0) AS offer_cur,
    a.outcome,
    a.completion_date,
    a.rejection_reason,
    a.sts
  FROM public.appointments a
  JOIN public.offers o ON o.id = a.off_id
  WHERE a.id = p_appointment_id
    AND a.supervisor_uid = p_user_uid
  LIMIT 1;
END;
$function$

CREATE OR REPLACE FUNCTION public.get_lawyer_appointments(p_lawyer_uid uuid)
 RETURNS TABLE(id uuid, client_name text, client_phone text, dt timestamp with time zone, sts integer, notes text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_role int;
BEGIN
  SELECT role INTO v_role
  FROM public.users
  WHERE id = p_lawyer_uid AND i_del = 0 AND sts = 0;

  IF v_role <> 7 THEN
    RAISE EXCEPTION 'LAWYER_ROLE_REQUIRED';
  END IF;

  RETURN QUERY
  SELECT
    a.id,
    COALESCE(u.nm, '') AS client_name,
    COALESCE(u.ph, '') AS client_phone,
    a.dt,
    a.sts,
    COALESCE(a.note, '') AS notes
  FROM public.appointments a
  JOIN public.users u ON u.id = a.req_uid
  WHERE a.bkr_id = p_lawyer_uid
  ORDER BY a.dt DESC;
END;
$function$

CREATE OR REPLACE FUNCTION public.get_lawyer_expediting_tasks(p_lawyer_uid uuid)
 RETURNS SETOF expediting_tasks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_role int;
BEGIN
  SELECT role INTO v_role
  FROM public.users
  WHERE id = p_lawyer_uid AND i_del = 0 AND sts = 0;

  IF v_role <> 7 THEN
    RAISE EXCEPTION 'LAWYER_ROLE_REQUIRED';
  END IF;

  RETURN QUERY
  SELECT *
  FROM public.expediting_tasks
  WHERE lawyer_uid = p_lawyer_uid
  ORDER BY created_at DESC;
END;
$function$

CREATE OR REPLACE FUNCTION public.get_lawyer_profile(p_lawyer_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_profile jsonb;
  v_role int;
BEGIN
  SELECT role INTO v_role
  FROM public.users
  WHERE id = p_lawyer_uid AND i_del = 0 AND sts = 0;

  IF v_role <> 7 THEN
    RAISE EXCEPTION 'LAWYER_ROLE_REQUIRED';
  END IF;

  SELECT jsonb_build_object(
    'uid', lp.uid,
    'whatsapp_phone', lp.whatsapp_phone,
    'office_address', lp.office_address,
    'specialization', lp.specialization,
    'avl', lp.avl,
    'is_active', lp.is_active
  ) INTO v_profile
  FROM public.lawyer_profiles lp
  WHERE lp.uid = p_lawyer_uid;

  IF v_profile IS NULL THEN
    RETURN jsonb_build_object('found', false);
  END IF;
  RETURN v_profile || jsonb_build_object('found', true);
END;
$function$

CREATE OR REPLACE FUNCTION public.get_my_completion_requests(p_user_uid uuid)
 RETURNS TABLE(request_id uuid, appointment_id uuid, off_id uuid, display_title text, offer_number text, task_type text, executor_notes text, office_notes text, decision text, request_date timestamp with time zone, decided_date timestamp with time zone, appointment_date timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_role INT;
BEGIN
  IF p_user_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_MISMATCH';
  END IF;

  SELECT role INTO v_role FROM public.users WHERE id = p_user_uid AND i_del = 0 AND sts = 0;
  IF v_role IS NULL OR v_role < 3 THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  RETURN QUERY
  SELECT
    cr.id AS request_id,
    cr.app_id AS appointment_id,
    a.off_id,
    COALESCE(o.ttl, '') AS display_title,
    COALESCE(o.offer_number::text, o.ttl, '') AS offer_number,
    CASE WHEN o.typ = 0 THEN 'property' ELSE 'car' END AS task_type,
    COALESCE(cr.notes, '') AS executor_notes,
    COALESCE(cr.office_notes, '') AS office_notes,
    COALESCE(cr.decision, 'pending') AS decision,
    cr.ts_crt AS request_date,
    cr.ts_decided AS decided_date,
    a.dt AS appointment_date
  FROM public.completion_requests cr
  JOIN public.appointments a ON a.id = cr.app_id
  JOIN public.offers o ON o.id = a.off_id
  WHERE cr.req_by = p_user_uid
  ORDER BY cr.ts_crt DESC;
END;
$function$

CREATE OR REPLACE FUNCTION public.get_my_expediting_tasks(p_expediter_uid uuid)
 RETURNS SETOF expediting_tasks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_role int;
BEGIN
  SELECT role INTO v_role
  FROM public.users
  WHERE id = p_expediter_uid AND i_del = 0 AND sts = 0;

  IF v_role <> 8 THEN
    RAISE EXCEPTION 'EXPEDITER_ROLE_REQUIRED';
  END IF;

  RETURN QUERY
  SELECT *
  FROM public.expediting_tasks
  WHERE expediter_uid = p_expediter_uid
  ORDER BY created_at DESC;
END;
$function$

CREATE OR REPLACE FUNCTION public.get_my_tasks(p_user_uid uuid DEFAULT NULL::uuid)
 RETURNS TABLE(appointment_id uuid, off_id uuid, offer_number text, display_title text, task_type text, client_name text, client_phone text, appointment_date timestamp with time zone, location jsonb, description text, price numeric, offer_cur integer, outcome text, sts integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

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

CREATE OR REPLACE FUNCTION public.get_photographer_tasks_internal(p_photographer_uid uuid)
 RETURNS SETOF photography_tasks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_role INT;
BEGIN
  IF p_photographer_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_photographer_uid THEN
    RAISE EXCEPTION 'AUTH_MISMATCH';
  END IF;

  SELECT role INTO v_role FROM public.users WHERE id = p_photographer_uid AND i_del = 0 AND sts = 0;
  IF v_role IS NULL OR v_role < 2 THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  RETURN QUERY
  SELECT *
  FROM public.photography_tasks
  WHERE photographer_id = p_photographer_uid
  ORDER BY COALESCE(ts_scheduled, ts_crt) ASC, ts_crt DESC;
END;
$function$

CREATE OR REPLACE FUNCTION public.get_postponed_tasks(p_user_uid uuid DEFAULT NULL::uuid)
 RETURNS TABLE(appointment_id uuid, off_id uuid, offer_number text, display_title text, task_type text, client_name text, client_phone text, appointment_date timestamp with time zone, location jsonb, description text, price numeric, offer_cur integer, outcome text, sts integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

CREATE OR REPLACE FUNCTION public.get_resource_usage_internal(p_admin_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'storage', 'extensions', 'pg_catalog', 'pg_temp'
AS $function$
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
$function$

CREATE OR REPLACE FUNCTION public.get_staff_stats_internal(p_user_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role INT;
  v_result JSONB := '{}'::jsonb;
  v_count INT := 0;
BEGIN
  SELECT role INTO v_role FROM public.users WHERE id = p_user_uid AND i_del = 0;
  IF v_role IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'USER_NOT_FOUND'); END IF;

  IF v_role = 2 THEN
    SELECT COUNT(*) INTO v_count FROM public.photography_tasks WHERE photographer_id = p_user_uid AND sts = 3;
    v_result := v_result || jsonb_build_object('completed_tasks', v_count);
    SELECT COUNT(*) INTO v_count FROM public.photography_tasks WHERE photographer_id = p_user_uid AND sts IN (0, 1);
    v_result := v_result || jsonb_build_object('pending_tasks', v_count);
    SELECT COUNT(*) INTO v_count FROM public.photography_tasks WHERE photographer_id = p_user_uid AND sts = 2;
    v_result := v_result || jsonb_build_object('submitted_tasks', v_count);
  ELSIF v_role = 3 THEN
    SELECT COUNT(*) INTO v_count FROM public.appointments WHERE supervisor_uid = p_user_uid AND sts = 2;
    v_result := v_result || jsonb_build_object('completed_visits', v_count);
    SELECT COUNT(*) INTO v_count FROM public.appointments WHERE supervisor_uid = p_user_uid AND sts IN (0, 1);
    v_result := v_result || jsonb_build_object('active_tasks', v_count);
    v_result := v_result || jsonb_build_object('completion_requests', 0);
  ELSIF v_role = 4 THEN
    SELECT COUNT(*) INTO v_count FROM public.offers WHERE added_by = p_user_uid AND i_del = 0;
    v_result := v_result || jsonb_build_object('reviewed_offers', v_count);
    SELECT COUNT(*) INTO v_count FROM public.appointments WHERE bkr_id = p_user_uid AND sts = 2;
    v_result := v_result || jsonb_build_object('managed_appointments', v_count);
    v_result := v_result || jsonb_build_object('processed_completions', 0);
  ELSIF v_role = 7 THEN
    v_result := v_result || jsonb_build_object('message', 'Lawyer stats - consultations');
  ELSIF v_role = 8 THEN
    v_result := v_result || jsonb_build_object('message', 'Expediter stats - field tasks');
  ELSIF v_role >= 5 THEN
    SELECT COUNT(*) INTO v_count FROM public.deals WHERE i_del = 0;
    v_result := v_result || jsonb_build_object('total_deals', v_count);
    SELECT COUNT(*) INTO v_count FROM public.payments WHERE sts IN (1, 2);
    v_result := v_result || jsonb_build_object('approved_payments', v_count);
    SELECT COUNT(*) INTO v_count FROM public.payments WHERE sts = 0;
    v_result := v_result || jsonb_build_object('pending_payments', v_count);
    SELECT COUNT(*) INTO v_count FROM public.users WHERE vrf = 2 AND i_del = 0;
    v_result := v_result || jsonb_build_object('verified_users', v_count);
    SELECT COUNT(*) INTO v_count FROM public.users WHERE vrf = 1 AND i_del = 0;
    v_result := v_result || jsonb_build_object('pending_verifications', v_count);
    SELECT COUNT(*) INTO v_count FROM public.users WHERE i_del = 0;
    v_result := v_result || jsonb_build_object('total_users', v_count);
    SELECT COUNT(*) INTO v_count FROM public.offers WHERE sts = 2 AND i_del = 0;
    v_result := v_result || jsonb_build_object('active_offers', v_count);
  ELSE
    v_result := v_result || jsonb_build_object('message', 'No specific stats for this role');
  END IF;
  v_result := v_result || jsonb_build_object('role', v_role);
  RETURN v_result;
END;
$function$

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

CREATE OR REPLACE FUNCTION public.get_user_by_email(p_email text)
 RETURNS SETOF users
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  RETURN QUERY SELECT * FROM users WHERE eml = p_email AND i_del = 0;
END;
$function$

CREATE OR REPLACE FUNCTION public.get_user_by_phone(p_phone text)
 RETURNS SETOF users
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN RETURN QUERY SELECT * FROM users WHERE ph = p_phone AND i_del = 0; END;
$function$

CREATE OR REPLACE FUNCTION public.get_user_device_tokens(p_uid uuid)
 RETURNS TABLE(device_token text, platform text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  RETURN QUERY SELECT ud.device_token, ud.platform FROM user_devices ud
    WHERE ud.uid = p_uid AND ud.is_active = TRUE;
END;
$function$

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
$function$

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

CREATE OR REPLACE FUNCTION public.handle_email_auth_internal()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_auth_uid UUID;
  v_email TEXT;
  v_uid UUID;
  v_existing_email TEXT;
  v_is_new BOOLEAN := FALSE;
BEGIN
  v_auth_uid := auth.uid();
  v_email := lower(btrim(coalesce(auth.jwt() ->> 'email', '')));

  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  IF v_email = '' THEN
    RAISE EXCEPTION 'EMAIL_REQUIRED';
  END IF;

  IF position('@' in v_email) <= 1
     OR position('.' in split_part(v_email, '@', 2)) <= 1 THEN
    RAISE EXCEPTION 'EMAIL_INVALID';
  END IF;

  IF v_email LIKE '%@whatsapp.local' THEN
    RAISE EXCEPTION 'PSEUDO_EMAIL_NOT_ALLOWED';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_email));

  SELECT
    id,
    lower(btrim(coalesce(eml, '')))
  INTO
    v_uid,
    v_existing_email
  FROM public.users
  WHERE id = v_auth_uid
    AND i_del = 0
  LIMIT 1;

  IF v_uid IS NOT NULL THEN
    IF v_existing_email <> '' AND v_existing_email <> v_email THEN
      RAISE EXCEPTION 'AUTH_UID_EMAIL_CONFLICT';
    END IF;

    UPDATE public.users
    SET
      eml = v_email,
      ts_upd = now()
    WHERE id = v_uid;

    RETURN jsonb_build_object(
      'success', true,
      'user_id', v_uid,
      'is_new', false,
      'email', v_email
    );
  END IF;

  SELECT id
  INTO v_uid
  FROM public.users
  WHERE lower(btrim(coalesce(eml, ''))) = v_email
    AND i_del = 0
  ORDER BY ts_crt ASC
  LIMIT 1;

  IF v_uid IS NULL THEN
    INSERT INTO public.users (
      id,
      nm,
      ph,
      eml,
      role,
      sts,
      i_del,
      ts_crt,
      ts_upd
    )
    VALUES (
      v_auth_uid,
      '',
      '',
      v_email,
      0,
      0,
      0,
      now(),
      now()
    )
    RETURNING id INTO v_uid;

    v_is_new := TRUE;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'user_id', v_uid,
    'is_new', v_is_new,
    'email', v_email
  );
END;
$function$

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

CREATE OR REPLACE FUNCTION public.log_admin_action(p_admin_uid uuid, p_act integer, p_det text, p_ref_id text DEFAULT ''::text, p_ref_col text DEFAULT ''::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  INSERT INTO public.activity_log (uid, act, det, ref_id, ref_col, ts_crt)
  VALUES (p_admin_uid, p_act, COALESCE(p_det, ''), COALESCE(p_ref_id, ''), COALESCE(p_ref_col, ''), NOW());
END;
$function$

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
  v_profile JSONB := NULL;
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

  SELECT get_user_full_by_id(v_user.id) INTO v_profile;

  RETURN jsonb_build_object(
    'success', true,
    'user_id', v_user.id,
    'role', v_user.role,
    'nm', v_user.nm,
    'staff_session', v_session,
    'profile', v_profile
  );
END;
$function$

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

CREATE OR REPLACE FUNCTION public.normalize_arabic_username(p_str text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v TEXT;
BEGIN
  v := lower(btrim(COALESCE(p_str, '')));
  -- إزالة التشكيل والحركات والشدة والتطويل (الكشيدة)
  v := regexp_replace(v, '[\u064B-\u065F\u0670\u0640]', '', 'g');
  -- توحيد أشكال الألف (أ إ آ -> ا)
  v := regexp_replace(v, '[أإآ]', 'ا', 'g');
  -- توحيد التاء المربوطة والهاء (ة -> ه)
  v := replace(v, 'ة', 'ه');
  -- توحيد الياء والألف المقصورة (ى ئ -> ي)
  v := regexp_replace(v, '[ىئ]', 'ي', 'g');
  RETURN v;
END;
$function$

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

CREATE OR REPLACE FUNCTION public.notify_admin_on_new_offer()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_title TEXT;
  v_body TEXT;
  staff RECORD;
BEGIN
  IF NEW.sts <> 1 THEN RETURN NEW; END IF;

  v_title := '🆕 عرض جديد بانتظار المراجعة';
  v_body  := 'أضاف ' || COALESCE((SELECT nm FROM users WHERE id = NEW.added_by), 'موظف') 
             || ' عرضاً جديداً: ' || COALESCE(NEW.ttl, '');

  -- أشعر الشخص الذي أضاف العرض (أنت كمدير)
  IF NEW.added_by IS NOT NULL THEN
    PERFORM notify_user(NEW.added_by, 0, v_title, v_body, NEW.id::text, 'offer');
  END IF;

  -- أشعر كل الموظفين + المدراء (role >= 4)
  FOR staff IN 
    SELECT id FROM users 
    WHERE role >= 4 
      AND i_del = 0 
      AND sts = 0
      AND (NEW.added_by IS NULL OR id <> NEW.added_by)
  LOOP
    PERFORM notify_user(staff.id, 0, v_title, v_body, NEW.id::text, 'offer');
  END LOOP;

  RETURN NEW;
END;
$function$

CREATE OR REPLACE FUNCTION public.notify_user(p_uid uuid, p_type integer, p_title text, p_body text, p_ref_id text DEFAULT ''::text, p_action text DEFAULT ''::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE v_id UUID;
BEGIN
  INSERT INTO notifications (uid, tp, ttl, bdy, ref_id, act, i_rd, i_del, ts_crt)
  VALUES (p_uid, p_type, p_title, p_body, p_ref_id, p_action, 0, 0, NOW())
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$

CREATE OR REPLACE FUNCTION public.owner_respond_appointment(p_owner_uid uuid, p_appointment_id uuid, p_accept boolean, p_reject_reason integer DEFAULT 0, p_reject_text text DEFAULT ''::text, p_proposed_dt timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_appt       public.appointments%ROWTYPE;
  v_rounds     INT;
  v_neog       JSONB;
  v_supervisor UUID;
  v_suggest    TIMESTAMPTZ;
  v_gap        INT := (public.appt_booking_config()->>'gap_mins')::INT;
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

  -- ─── موافقة ───
  IF p_accept THEN
    UPDATE public.appointments
    SET sts        = 1,
        fbk_own    = 1,
        fbk_own_dt = NOW()
    WHERE id = p_appointment_id;

    PERFORM public.notify_user(
      v_appt.req_uid, 2,
      '✅ تم قبول طلب موعدك',
      'وافق صاحب العرض على موعد المعاينة. سيتواصل معك المكتب لتأكيد التفاصيل.',
      p_appointment_id::text, 'appointment'
    );
    PERFORM public.notify_user(
      (SELECT id FROM public.users WHERE role >= 2 AND sts = 0 AND i_del = 0
       ORDER BY ts_crt ASC LIMIT 1),
      2,
      '📅 موعد مؤكد',
      'وافق صاحب العرض على موعد معاينة — المشرف معيَّن تلقائياً.',
      p_appointment_id::text, 'appointment'
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

    -- ✅ فحص جديد: الوقت المقترح يجب أن يكون مستقبلياً
    IF p_proposed_dt <= NOW() THEN
      RETURN jsonb_build_object('success', false, 'error', 'INVALID_APPOINTMENT_TIME');
    END IF;

    IF v_rounds >= 5 THEN
      UPDATE public.appointments
      SET sts     = 4,
          cnl_rsn = 'انتهت جولات التفاوض بدون توافق',
          dt_end  = NOW()
      WHERE id = p_appointment_id;

      PERFORM public.notify_user(v_appt.req_uid, 2,
        '❌ انتهت جولات التفاوض',
        'لم يتم التوافق على موعد بعد 5 جولات. يمكنك المحاولة لاحقاً.',
        p_appointment_id::text, 'appointment');
      PERFORM public.notify_user(
        (SELECT id FROM public.users WHERE role >= 2 AND sts = 0 AND i_del = 0
         ORDER BY ts_crt ASC LIMIT 1),
        2,
        '⚠️ انتهت جولات التفاوض',
        'تم إلغاء الموعد تلقائياً بعد 5 جولات بدون توافق.',
        p_appointment_id::text, 'appointment');
      RETURN jsonb_build_object('success', true, 'auto_cancelled', true);
    END IF;

    -- ✅ فحص جديد (القاعدة 3): فارق الساعة على مواعيد نفس العرض
    -- (مع استثناء الموعد الجاري تعديله نفسه)
    IF EXISTS (
      SELECT 1 FROM public.appointments
      WHERE off_id = v_appt.off_id
        AND id <> p_appointment_id
        AND sts IN (0, 1)
        AND dt > p_proposed_dt - make_interval(mins => v_gap)
        AND dt < p_proposed_dt + make_interval(mins => v_gap)
    ) THEN
      RETURN jsonb_build_object('success', false, 'error', 'TIME_CONFLICT_ON_OFFER');
    END IF;

    -- ✅ معالجة غياب المشرف بدل الانفجار بخطأ خام:
    -- get_available_supervisor ترمي EXCEPTION — نلتقطها في block داخلي
    BEGIN
      v_supervisor := public.get_available_supervisor(p_proposed_dt);
    EXCEPTION WHEN OTHERS THEN
      v_supervisor := NULL;
    END;

    IF v_supervisor IS NULL THEN
      v_suggest := public.suggest_appointment_slot(v_appt.off_id, p_proposed_dt);
      PERFORM public.notify_user(
        p_owner_uid, 2,
        'لا يوجد مشرف متاح للوقت المقترح',
        CASE WHEN v_suggest IS NOT NULL
          THEN 'تعذّر اعتماد الوقت البديل لعدم توفر مشرف. أقرب وقت متاح: '
               || to_char(v_suggest AT TIME ZONE 'Asia/Damascus', 'YYYY/MM/DD HH24:MI')
               || ' — يمكنك اقتراحه أو اختيار وقت آخر.'
          ELSE 'تعذّر اعتماد الوقت البديل لعدم توفر مشرف. يرجى اقتراح وقت آخر.'
        END,
        p_appointment_id::text, 'appointment_suggest'
      );
      RETURN jsonb_build_object(
        'success', false,
        'error', 'NO_SUPERVISOR_AVAILABLE',
        'suggested_dt', v_suggest
      );
    END IF;

    v_neog := v_neog || jsonb_build_object(
      'round',    v_rounds + 1,
      'by',       'owner',
      'at',       NOW(),
      'action',   'counter',
      'proposed', p_proposed_dt
    );

    UPDATE public.appointments
    SET dt             = p_proposed_dt,
        supervisor_uid = v_supervisor,
        neog           = v_neog,
        fbk_own        = 2,
        fbk_own_dt     = NOW()
    WHERE id = p_appointment_id;

    PERFORM public.notify_user(
      v_appt.req_uid, 2,
      '🔄 اقتراح وقت بديل',
      'اقترح صاحب العرض وقتاً بديلاً للمعاينة: ' ||
        TO_CHAR(p_proposed_dt AT TIME ZONE 'Asia/Damascus', 'YYYY/MM/DD HH24:MI') ||
        '. يمكنك القبول أو اقتراح وقت آخر.',
      p_appointment_id::text, 'appointment'
    );
    PERFORM public.notify_user(
      (SELECT id FROM public.users WHERE role >= 2 AND sts = 0 AND i_del = 0
       ORDER BY ts_crt ASC LIMIT 1),
      2,
      '🔄 جولة تفاوض جديدة (' || (v_rounds + 1)::text || '/5)',
      'صاحب العرض اقترح وقتاً بديلاً — بانتظار رد الطالب.',
      p_appointment_id::text, 'appointment'
    );
    RETURN jsonb_build_object('success', true);
  END IF;

  RAISE EXCEPTION 'INVALID_REJECT_REASON';
END;
$function$

CREATE OR REPLACE FUNCTION public.process_completion_request(p_admin_uid uuid, p_request_id uuid, p_decision text, p_office_notes text DEFAULT ''::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

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
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_UID_MISMATCH');
  END IF;

  SELECT usr_id, sts
  INTO v_owner_id, v_offer_status
  FROM public.offers
  WHERE id = p_offer_id
    AND i_del = 0;

  IF v_owner_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'OFFER_NOT_FOUND');
  END IF;

  IF v_owner_id <> p_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_OWNER');
  END IF;

  SELECT value
  INTO v_config
  FROM public.app_config
  WHERE key = 'main';

  v_cost := CASE p_boost_type
    WHEN 'ren' THEN COALESCE((v_config->'spd'->>'ren')::INT, 500)
    WHEN 'pin' THEN COALESCE((v_config->'spd'->>'pin')::INT, 2000)
    WHEN 'bst' THEN COALESCE((v_config->'spd'->>'bst')::INT, 4000)
    WHEN 'dsc5' THEN COALESCE((v_config->'spd'->>'dsc5')::INT, 3000)
    WHEN 'fms' THEN COALESCE((v_config->'spd'->>'fms')::INT, 8000)
    ELSE NULL
  END;

  IF v_cost IS NULL OR v_cost <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_BOOST_TYPE');
  END IF;

  IF p_boost_type = 'ren' AND v_offer_status = 3 THEN
    RETURN jsonb_build_object('success', false, 'error', 'REJECTED_OFFER');
  END IF;

  -- Atomic points deduction prevents race conditions and forged/negative costs.
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
      SET ts_end = GREATEST(COALESCE(ts_end, v_now), v_now) + INTERVAL '30 days',
          ts_ren = v_now,
          sts = CASE WHEN sts = 4 THEN 2 ELSE sts END,
          i_pub = CASE WHEN sts = 4 THEN 1 ELSE i_pub END
      WHERE id = p_offer_id
        AND usr_id = p_uid
        AND i_del = 0;
      v_result := jsonb_build_object('boost_type', 'ren', 'duration_days', 30);

    WHEN 'pin' THEN
      UPDATE public.offers
      SET i_pin = 1,
          pin_end = v_now + INTERVAL '7 days'
      WHERE id = p_offer_id
        AND usr_id = p_uid
        AND i_del = 0;
      v_result := jsonb_build_object('boost_type', 'pin', 'duration_days', 7);

    WHEN 'bst' THEN
      UPDATE public.offers
      SET i_bst = 1,
          bst_end = v_now + INTERVAL '14 days'
      WHERE id = p_offer_id
        AND usr_id = p_uid
        AND i_del = 0;
      v_result := jsonb_build_object('boost_type', 'bst', 'duration_days', 14);

    WHEN 'dsc5' THEN
      UPDATE public.offers
      SET dsc_pct = 5,
          dsc_end = v_now + INTERVAL '60 days'
      WHERE id = p_offer_id
        AND usr_id = p_uid
        AND i_del = 0;
      v_result := jsonb_build_object('boost_type', 'dsc5', 'discount_pct', 5, 'duration_days', 60);

    WHEN 'fms' THEN
      UPDATE public.offers
      SET i_fms = 1,
          fms_end = v_now + INTERVAL '30 days'
      WHERE id = p_offer_id
        AND usr_id = p_uid
        AND i_del = 0;
      v_result := jsonb_build_object('boost_type', 'fms', 'duration_days', 30);
  END CASE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'OFFER_UPDATE_FAILED';
  END IF;

  INSERT INTO public.activity_log (uid, act, det, ref_id, ref_col, ts_crt)
  VALUES (
    p_uid,
    20,
    'offer_boost: type=' || p_boost_type || ' cost=' || v_cost::TEXT,
    p_offer_id::TEXT,
    'offers',
    v_now
  );

  RETURN jsonb_build_object(
    'success', true,
    'result', v_result,
    'new_balance', v_new_balance,
    'cost', v_cost
  );
END;
$function$

CREATE OR REPLACE FUNCTION public.purge_old_closed_requests()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

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

CREATE OR REPLACE FUNCTION public.register_device(p_device_id text, p_ip_hint text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_current TEXT;
  v_history JSONB;
BEGIN
  IF v_uid IS NULL THEN
    RETURN FALSE;
  END IF;
  IF p_device_id IS NULL OR LENGTH(TRIM(p_device_id)) = 0 THEN
    RETURN FALSE;
  END IF;

  SELECT device_id, COALESCE(device_history, '[]'::jsonb)
    INTO v_current, v_history FROM users WHERE id = v_uid;

  -- أول مرة → سجّل signup_ip + signup_device
  IF v_current IS NULL THEN
    UPDATE users SET
      device_id = p_device_id,
      signup_ip = NULLIF(p_ip_hint, '')::INET,
      last_ip   = NULLIF(p_ip_hint, '')::INET,
      device_history = v_history || jsonb_build_object(
        'd', p_device_id, 't', NOW(), 'first', true)
    WHERE id = v_uid;
  ELSIF v_current <> p_device_id THEN
    -- جهاز جديد → نُضيفه للسجل لكن لا نغيّر device_id الأساسي تلقائياً
    UPDATE users SET
      last_ip = COALESCE(NULLIF(p_ip_hint, '')::INET, last_ip),
      device_history = v_history || jsonb_build_object(
        'd', p_device_id, 't', NOW())
    WHERE id = v_uid;
  ELSE
    -- نفس الجهاز → فقط حدّث الـIP
    UPDATE users SET
      last_ip = COALESCE(NULLIF(p_ip_hint, '')::INET, last_ip)
    WHERE id = v_uid;
  END IF;

  RETURN TRUE;
END;
$function$

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

CREATE OR REPLACE FUNCTION public.register_weekly_login(p_uid uuid, p_pts integer DEFAULT 100)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_last TIMESTAMPTZ;
  v_now TIMESTAMPTZ := NOW();
  v_logins JSONB;
BEGIN
  SELECT wk_lgn INTO v_logins FROM users WHERE id = p_uid;
  v_logins := COALESCE(v_logins, '[]'::jsonb);

  IF jsonb_array_length(v_logins) > 0 THEN
    v_last := (v_logins->-1)::text::timestamptz;
    IF v_now - v_last < INTERVAL '7 days' THEN
      RETURN FALSE;
    END IF;
  END IF;

  v_logins := v_logins || to_jsonb(v_now::text);
  IF jsonb_array_length(v_logins) > 10 THEN
    v_logins := jsonb_path_query_array(v_logins, '$[last - 9 to last]');
  END IF;

  UPDATE users SET
    wk_lgn = v_logins,
    pt = pt + p_pts,
    ts_upd = NOW()
  WHERE id = p_uid;

  PERFORM update_user_badge(p_uid);
  RETURN TRUE;
END;
$function$

CREATE OR REPLACE FUNCTION public.renew_request_internal(p_user_uid uuid, p_request_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

CREATE OR REPLACE FUNCTION public.request_assert_owner_active(p_user_uid uuid, p_request_id uuid)
 RETURNS requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

CREATE OR REPLACE FUNCTION public.request_completion_by_appointment(p_user_uid uuid, p_appointment_id uuid, p_notes text DEFAULT ''::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
END; $function$

CREATE OR REPLACE FUNCTION public.request_expediting_item_revision_internal(p_lawyer_uid uuid, p_task_id uuid, p_item_key text, p_revision_notes text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

CREATE OR REPLACE FUNCTION public.request_lifecycle_days(p_key text, p_default integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

CREATE OR REPLACE FUNCTION public.request_verification_by_uid(p_user_uid uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_user RECORD;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT id, sid, img, vrf
    INTO v_user
  FROM users
  WHERE id = p_user_uid
    AND i_del = 0;

  IF v_user IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;

  IF v_user.vrf = 2 THEN
    RAISE EXCEPTION 'ALREADY_VERIFIED';
  END IF;

  IF v_user.vrf = 1 THEN
    RAISE EXCEPTION 'ALREADY_PENDING';
  END IF;

  IF v_user.sid IS NULL OR LENGTH(TRIM(v_user.sid)) = 0
     OR v_user.img IS NULL OR LENGTH(TRIM(v_user.img)) = 0 THEN
    RAISE EXCEPTION 'MISSING_DOCUMENTS';
  END IF;

  UPDATE users
  SET vrf = 1,
      ts_upd = NOW()
  WHERE id = p_user_uid;

  RETURN TRUE;
END;
$function$

CREATE OR REPLACE FUNCTION public.requester_counter_appointment(p_user_uid uuid, p_appointment_id uuid, p_accept boolean, p_proposed_dt timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_appt       public.appointments%ROWTYPE;
  v_rounds     INT;
  v_neog       JSONB;
  v_supervisor UUID;
  v_suggest    TIMESTAMPTZ;
  v_gap        INT := (public.appt_booking_config()->>'gap_mins')::INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT * INTO v_appt
  FROM public.appointments
  WHERE id      = p_appointment_id
    AND req_uid = p_user_uid
    AND sts     = 0;

  IF v_appt.id IS NULL THEN
    RAISE EXCEPTION 'APPOINTMENT_NOT_FOUND_OR_NOT_ALLOWED';
  END IF;

  v_neog   := COALESCE(v_appt.neog, '[]'::jsonb);
  v_rounds := jsonb_array_length(v_neog);

  -- ─── قبول الوقت البديل ───
  IF p_accept THEN
    UPDATE public.appointments
    SET sts        = 1,
        fbk_req    = 1,
        fbk_req_dt = NOW()
    WHERE id = p_appointment_id;

    PERFORM public.notify_user(
      v_appt.own_id, 2,
      '✅ قبل الطالب الوقت البديل',
      'تم تأكيد موعد المعاينة في الوقت المقترح. سيتواصل معك المكتب.',
      p_appointment_id::text, 'appointment'
    );
    PERFORM public.notify_user(
      (SELECT id FROM public.users WHERE role >= 2 AND sts = 0 AND i_del = 0
       ORDER BY ts_crt ASC LIMIT 1),
      2,
      '📅 موعد مؤكد بعد تفاوض',
      'قبل الطالب الوقت البديل — الموعد مؤكد والمشرف معيَّن.',
      p_appointment_id::text, 'appointment'
    );
    RETURN jsonb_build_object('success', true);
  END IF;

  -- ─── رفض + اقتراح وقت آخر ───
  IF p_proposed_dt IS NULL THEN
    RAISE EXCEPTION 'PROPOSED_DT_REQUIRED';
  END IF;

  -- ✅ فحص جديد: الوقت المقترح يجب أن يكون مستقبلياً
  IF p_proposed_dt <= NOW() THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_APPOINTMENT_TIME');
  END IF;

  IF v_rounds >= 5 THEN
    UPDATE public.appointments
    SET sts     = 4,
        cnl_rsn = 'انتهت جولات التفاوض بدون توافق',
        dt_end  = NOW()
    WHERE id = p_appointment_id;

    PERFORM public.notify_user(
      v_appt.own_id, 2,
      '❌ انتهت جولات التفاوض',
      'لم يتم التوافق على موعد بعد 5 جولات.',
      p_appointment_id::text, 'appointment'
    );
    PERFORM public.notify_user(
      (SELECT id FROM public.users WHERE role >= 2 AND sts = 0 AND i_del = 0
       ORDER BY ts_crt ASC LIMIT 1),
      2,
      '⚠️ انتهت جولات التفاوض',
      'تم إلغاء الموعد تلقائياً بعد 5 جولات بدون توافق.',
      p_appointment_id::text, 'appointment'
    );
    RETURN jsonb_build_object('success', true, 'auto_cancelled', true);
  END IF;

  -- ✅ فحص جديد (القاعدة 3): فارق الساعة على مواعيد نفس العرض
  IF EXISTS (
    SELECT 1 FROM public.appointments
    WHERE off_id = v_appt.off_id
      AND id <> p_appointment_id
      AND sts IN (0, 1)
      AND dt > p_proposed_dt - make_interval(mins => v_gap)
      AND dt < p_proposed_dt + make_interval(mins => v_gap)
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'TIME_CONFLICT_ON_OFFER');
  END IF;

  -- ✅ معالجة غياب المشرف بدل الانفجار بخطأ خام
  BEGIN
    v_supervisor := public.get_available_supervisor(p_proposed_dt);
  EXCEPTION WHEN OTHERS THEN
    v_supervisor := NULL;
  END;

  IF v_supervisor IS NULL THEN
    v_suggest := public.suggest_appointment_slot(v_appt.off_id, p_proposed_dt);
    PERFORM public.notify_user(
      p_user_uid, 2,
      'لا يوجد مشرف متاح للوقت المقترح',
      CASE WHEN v_suggest IS NOT NULL
        THEN 'تعذّر اعتماد الوقت البديل لعدم توفر مشرف. أقرب وقت متاح: '
             || to_char(v_suggest AT TIME ZONE 'Asia/Damascus', 'YYYY/MM/DD HH24:MI')
             || ' — يمكنك اقتراحه أو اختيار وقت آخر.'
        ELSE 'تعذّر اعتماد الوقت البديل لعدم توفر مشرف. يرجى اقتراح وقت آخر.'
      END,
      p_appointment_id::text, 'appointment_suggest'
    );
    RETURN jsonb_build_object(
      'success', false,
      'error', 'NO_SUPERVISOR_AVAILABLE',
      'suggested_dt', v_suggest
    );
  END IF;

  v_neog := v_neog || jsonb_build_object(
    'round',    v_rounds + 1,
    'by',       'requester',
    'at',       NOW(),
    'action',   'counter',
    'proposed', p_proposed_dt
  );

  UPDATE public.appointments
  SET dt             = p_proposed_dt,
      supervisor_uid = v_supervisor,
      neog           = v_neog,
      fbk_req        = 2,
      fbk_req_dt     = NOW()
  WHERE id = p_appointment_id;

  PERFORM public.notify_user(
    v_appt.own_id, 2,
    '🔄 اقتراح وقت بديل من الطالب',
    'اقترح طالب الموعد وقتاً بديلاً: ' ||
      TO_CHAR(p_proposed_dt AT TIME ZONE 'Asia/Damascus', 'YYYY/MM/DD HH24:MI') ||
      '. يمكنك القبول أو اقتراح وقت آخر.',
    p_appointment_id::text, 'appointment'
  );
  PERFORM public.notify_user(
    (SELECT id FROM public.users WHERE role >= 2 AND sts = 0 AND i_del = 0
     ORDER BY ts_crt ASC LIMIT 1),
    2,
    '🔄 جولة تفاوض جديدة (' || (v_rounds + 1)::text || '/5)',
    'الطالب اقترح وقتاً بديلاً — بانتظار رد صاحب العرض.',
    p_appointment_id::text, 'appointment'
  );
  RETURN jsonb_build_object('success', true);
END;
$function$

CREATE OR REPLACE FUNCTION public.reset_password_with_otp(p_user_uid uuid, p_new_password text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF LENGTH(p_new_password) < 6 THEN
    RAISE EXCEPTION 'PASSWORD_TOO_SHORT';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_user_uid AND i_del = 0) THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;

  UPDATE users SET
    pwd = crypt(p_new_password, gen_salt('bf', 8)),
    ts_upd = NOW()
  WHERE id = p_user_uid;

  RETURN TRUE;
END;
$function$

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

CREATE OR REPLACE FUNCTION public.send_appointment_reminders()
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$ BEGIN
  UPDATE appointments SET rmnd_2 = 1 WHERE sts IN (0, 1) AND i_force = 0 AND dt <= NOW() + INTERVAL '2 hours' AND dt > NOW() AND rmnd_2 = 0;
  UPDATE appointments SET rmnd_24 = 1 WHERE sts IN (0, 1) AND i_force = 0 AND dt <= NOW() + INTERVAL '24 hours' AND dt > NOW() AND rmnd_24 = 0;
END; $function$

CREATE OR REPLACE FUNCTION public.send_push_notification(p_uid uuid, p_title text, p_body text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_config JSONB;
  v_request_id BIGINT;
BEGIN
  -- لا نرسل لمستخدم فارغ أو غير موجود
  IF p_uid IS NULL THEN RETURN NULL; END IF;

  SELECT value INTO v_config FROM app_config WHERE key = 'fcm';
  IF v_config IS NULL THEN
    RAISE WARNING 'FCM config not found in app_config';
    RETURN NULL;
  END IF;

  -- استدعاء غير متزامن (لا يبطئ trigger)
  SELECT net.http_post(
    url := v_config->>'url',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', v_config->>'anon_key'
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
$function$

CREATE OR REPLACE FUNCTION public.send_renewal_reminders()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_count INTEGER := 0;
  v_offer RECORD;
BEGIN
  FOR v_offer IN
    SELECT id, usr_id, ttl
    FROM offers
    WHERE sts = 2 AND i_del = 0
      AND (
        (ts_ren IS NULL AND COALESCE(ts_pub, ts_crt) BETWEEN NOW() - INTERVAL '28 days' AND NOW() - INTERVAL '27 days')
        OR
        (ts_ren IS NOT NULL AND ts_end BETWEEN NOW() + INTERVAL '2 days' AND NOW() + INTERVAL '3 days')
      )
  LOOP
    -- إدراج الإشعار في جدول الإشعارات
    INSERT INTO notifications (uid, tp, ttl, bdy, ref_id, act, ts_crt)
    VALUES (
      v_offer.usr_id, 
      1, 
      'تذكير بتجديد العرض', 
      'العرض الخاص بك "' || COALESCE(v_offer.ttl, 'بدون عنوان') || '" سينتهي قريباً. قم بتجديده بالنقاط لتجنب نقله للأرشيف.', 
      v_offer.id,
      '/offer/' || v_offer.id,
      NOW()
    );
    v_count := v_count + 1;
  END LOOP;
  
  RETURN v_count;
END;
$function$

CREATE OR REPLACE FUNCTION public.send_request_renewal_reminders()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

CREATE OR REPLACE FUNCTION public.set_offer_number()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF NEW.offer_number IS NULL THEN
    NEW.offer_number := nextval('offer_number_seq');
  END IF;
  RETURN NEW;
END;
$function$

CREATE OR REPLACE FUNCTION public.soft_delete(p_table text, p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$ BEGIN EXECUTE format('UPDATE %I SET i_del = 1 WHERE id = %L', p_table, p_id); END; $function$

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

CREATE OR REPLACE FUNCTION public.start_photography_task_internal(p_photographer_uid uuid, p_task_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_role INT;
BEGIN
  IF p_photographer_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_photographer_uid THEN
    RAISE EXCEPTION 'AUTH_MISMATCH';
  END IF;

  SELECT role INTO v_role FROM public.users WHERE id = p_photographer_uid AND i_del = 0 AND sts = 0;
  IF v_role IS NULL OR v_role < 2 THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  UPDATE public.photography_tasks
  SET sts = 1,
      ts_upd = now()
  WHERE id = p_task_id
    AND photographer_id = p_photographer_uid
    AND sts IN (0, 4);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'TASK_NOT_FOUND_OR_NOT_ALLOWED';
  END IF;

  RETURN TRUE;
END;
$function$

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

CREATE OR REPLACE FUNCTION public.suggest_appointment_slot(p_offer_id uuid, p_from timestamp with time zone DEFAULT now())
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_offer   public.offers%ROWTYPE;
  v_cfg     JSONB := public.appt_booking_config();
  v_gap     INT;
  v_date    DATE;
  v_day_key TEXT;
  v_slots   JSONB;
  v_slot    TEXT;
  v_from_m  INT;
  v_to_m    INT;
  v_m       INT;
  v_cand    TIMESTAMPTZ;
  d         INT;
BEGIN
  v_gap := (v_cfg->>'gap_mins')::INT;

  SELECT * INTO v_offer FROM public.offers WHERE id = p_offer_id AND i_del = 0;
  IF v_offer.id IS NULL THEN RETURN NULL; END IF;
  IF v_offer.avl IS NULL OR v_offer.avl = '{}'::jsonb OR v_offer.avl = 'null'::jsonb THEN
    RETURN NULL;
  END IF;

  FOR d IN 0..13 LOOP
    v_date := (p_from AT TIME ZONE 'Asia/Damascus')::date + d;
    v_day_key := LOWER(to_char(v_date, 'Dy'));

    IF v_offer.avl ? 'any' THEN
      v_slots := jsonb_build_array((v_cfg->>'any_from') || '-' || (v_cfg->>'any_to'));
    ELSE
      v_slots := v_offer.avl -> v_day_key;
    END IF;

    IF v_slots IS NULL OR jsonb_array_length(v_slots) = 0 THEN CONTINUE; END IF;

    FOR v_slot IN SELECT jsonb_array_elements_text(v_slots) LOOP
      v_from_m := SPLIT_PART(SPLIT_PART(v_slot, '-', 1), ':', 1)::INT * 60
                + SPLIT_PART(SPLIT_PART(v_slot, '-', 1), ':', 2)::INT;
      v_to_m   := SPLIT_PART(SPLIT_PART(v_slot, '-', 2), ':', 1)::INT * 60
                + SPLIT_PART(SPLIT_PART(v_slot, '-', 2), ':', 2)::INT;

      v_m := v_from_m;
      WHILE v_m < v_to_m LOOP
        v_cand := ((v_date::text || ' ' ||
                    LPAD((v_m / 60)::text, 2, '0') || ':' ||
                    LPAD((v_m % 60)::text, 2, '0'))::timestamp)
                  AT TIME ZONE 'Asia/Damascus';

        IF v_cand > NOW()
           AND NOT EXISTS (
             SELECT 1 FROM public.appointments
             WHERE off_id = p_offer_id AND sts IN (0, 1)
               AND dt > v_cand - make_interval(mins => v_gap)
               AND dt < v_cand + make_interval(mins => v_gap)
           )
           AND EXISTS (
             SELECT 1 FROM public.users u
             WHERE u.role = 3 AND u.sts = 0 AND u.i_del = 0
               AND NOT EXISTS (
                 SELECT 1 FROM public.appointments a
                 WHERE a.supervisor_uid = u.id AND a.sts IN (0, 1)
                   AND a.dt > v_cand - make_interval(mins => v_gap)
                   AND a.dt < v_cand + make_interval(mins => v_gap)
               )
           )
        THEN
          RETURN v_cand;
        END IF;

        v_m := v_m + v_gap;
      END LOOP;
    END LOOP;
  END LOOP;

  RETURN NULL;
END;
$function$

CREATE OR REPLACE FUNCTION public.trg_appointment_created()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_title      TEXT;
  v_body       TEXT;
  v_admin_uid  UUID;
BEGIN
  v_title := '📅 طلب معاينة جديد';
  v_body  := 'يوجد طلب حجز موعد بتاريخ ' ||
             TO_CHAR(NEW.dt AT TIME ZONE 'Asia/Damascus', 'YYYY/MM/DD HH24:MI');

  -- إشعار صاحب العرض فقط (بدون أي معلومة عن الطالب)
  IF NEW.own_id IS NOT NULL THEN
    PERFORM notify_user(
      NEW.own_id, 2, v_title, v_body,
      NEW.id::text, 'appointment'
    );
    PERFORM send_push_notification(
      NEW.own_id, v_title, v_body,
      jsonb_build_object('type', 'appointment', 'id', NEW.id::text)
    );
  END IF;

  -- إشعار الوسيط (إذا موجود ومختلف عن المالك — بدون معلومة عن الطالب)
  IF NEW.bkr_id IS NOT NULL AND NEW.bkr_id <> NEW.own_id THEN
    PERFORM notify_user(
      NEW.bkr_id, 2, v_title, v_body,
      NEW.id::text, 'appointment'
    );
    PERFORM send_push_notification(
      NEW.bkr_id, v_title, v_body,
      jsonb_build_object('type', 'appointment', 'id', NEW.id::text)
    );
  END IF;

  -- إشعار الإدارة (أول مدير/مشرف نشط)
  SELECT id INTO v_admin_uid
  FROM users
  WHERE role >= 2 AND sts = 0 AND i_del = 0
  ORDER BY ts_crt ASC
  LIMIT 1;

  IF v_admin_uid IS NOT NULL THEN
    PERFORM notify_user(
      v_admin_uid, 2,
      '📅 طلب موعد جديد — للمراجعة',
      'طلب موعد معاينة جديد بتاريخ ' ||
        TO_CHAR(NEW.dt AT TIME ZONE 'Asia/Damascus', 'YYYY/MM/DD HH24:MI') ||
        '. بانتظار رد صاحب العرض.',
      NEW.id::text, 'appointment'
    );
  END IF;

  RETURN NEW;
END;
$function$

CREATE OR REPLACE FUNCTION public.trg_appointment_status_changed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_title      TEXT;
  v_body       TEXT;
  v_admin_uid  UUID;
  v_admin_body TEXT;
BEGIN
  IF NEW.sts = OLD.sts THEN RETURN NEW; END IF;

  -- إشعار الإدارة دائماً
  SELECT id INTO v_admin_uid
  FROM users
  WHERE role >= 2 AND sts = 0 AND i_del = 0
  ORDER BY ts_crt ASC
  LIMIT 1;

  CASE NEW.sts
    WHEN 1 THEN
      -- مؤكد: أشعر الطالب
      v_title := '✅ تم تأكيد موعدك';
      v_body  := 'وافق صاحب العرض على موعد المعاينة. سيتواصل معك المكتب لتأكيد التفاصيل.';
      v_admin_body := 'تم تأكيد موعد معاينة — المشرف معيَّن.';

      IF NEW.req_uid IS NOT NULL THEN
        PERFORM notify_user(
          NEW.req_uid, 2, v_title, v_body,
          NEW.id::text, 'appointment'
        );
        PERFORM send_push_notification(
          NEW.req_uid, v_title, v_body,
          jsonb_build_object('type', 'appointment', 'id', NEW.id::text)
        );
      END IF;

    WHEN 2 THEN
      -- مكتمل: أشعر الطالب
      v_title := '🎉 تمت المعاينة';
      v_body  := 'تم إكمال المعاينة بنجاح. يمكنك تقييم تجربتك الآن.';
      v_admin_body := 'اكتملت معاينة — يمكن تسجيل صفقة.';

      IF NEW.req_uid IS NOT NULL THEN
        PERFORM notify_user(
          NEW.req_uid, 2, v_title, v_body,
          NEW.id::text, 'appointment'
        );
        PERFORM send_push_notification(
          NEW.req_uid, v_title, v_body,
          jsonb_build_object('type', 'appointment', 'id', NEW.id::text)
        );
      END IF;

    WHEN 3 THEN
      -- ملغي: أشعر الطالب والمالك
      v_title := '⚠️ تم إلغاء الموعد';
      v_body  := 'تم إلغاء موعد المعاينة. ' || COALESCE(NEW.cnl_rsn, '');
      v_admin_body := 'إلغاء موعد — ' || COALESCE(NEW.cnl_rsn, 'بدون سبب');

      IF NEW.req_uid IS NOT NULL THEN
        PERFORM notify_user(
          NEW.req_uid, 2, v_title, v_body,
          NEW.id::text, 'appointment'
        );
      END IF;
      IF NEW.own_id IS NOT NULL THEN
        PERFORM notify_user(
          NEW.own_id, 2, v_title, v_body,
          NEW.id::text, 'appointment'
        );
      END IF;

    WHEN 4 THEN
      -- مرفوض: أشعر الطالب
      v_title := '❌ تم رفض طلب موعدك';
      v_body  := 'لم يُقبل طلب المعاينة. ' || COALESCE(NEW.cnl_rsn, '');
      v_admin_body := 'رفض موعد — ' || COALESCE(NEW.cnl_rsn, 'بدون سبب');

      IF NEW.req_uid IS NOT NULL THEN
        PERFORM notify_user(
          NEW.req_uid, 2, v_title, v_body,
          NEW.id::text, 'appointment'
        );
        PERFORM send_push_notification(
          NEW.req_uid, v_title, v_body,
          jsonb_build_object('type', 'appointment', 'id', NEW.id::text)
        );
      END IF;

    WHEN 5 THEN
      -- لم يحضر: أشعر الطالب
      v_title := '😞 سُجّل عدم حضور';
      v_body  := 'لم تحضر للموعد. سيتم خصم 500 نقطة من رصيدك.';
      v_admin_body := 'عدم حضور مسجَّل على طالب موعد.';

      IF NEW.req_uid IS NOT NULL THEN
        PERFORM notify_user(
          NEW.req_uid, 2, v_title, v_body,
          NEW.id::text, 'appointment'
        );
      END IF;

    ELSE
      RETURN NEW;
  END CASE;

  -- إشعار الإدارة في كل حالة
  IF v_admin_uid IS NOT NULL THEN
    PERFORM notify_user(
      v_admin_uid, 2,
      '📋 تحديث موعد — ' || v_title,
      v_admin_body,
      NEW.id::text, 'appointment'
    );
  END IF;

  RETURN NEW;
END;
$function$

CREATE OR REPLACE FUNCTION public.trg_deal_completed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_title TEXT;
  v_body TEXT;
BEGIN
  -- نهتم فقط لما الحالة تتغير لـ 1 (مكتملة)
  IF NEW.sts != 1 OR (TG_OP = 'UPDATE' AND OLD.sts = 1) THEN
    RETURN NEW;
  END IF;

  v_title := '🎉 تمت الصفقة بنجاح';
  v_body := 'مبروك! تم إتمام الصفقة بمبلغ ' || COALESCE(NEW.fin_prc::text, '—') || '.';

  -- إشعار للبائع
  IF NEW.sell_uid IS NOT NULL THEN
    PERFORM notify_user(NEW.sell_uid, 3, v_title, v_body, NEW.id::text, 'payment');
    PERFORM send_push_notification(
      NEW.sell_uid, v_title, v_body,
      jsonb_build_object('type', 'payment', 'id', NEW.id::text)
    );
  END IF;

  -- إشعار للمشتري (إن وجد ومختلف)
  IF NEW.buy_uid IS NOT NULL AND NEW.buy_uid != NEW.sell_uid THEN
    PERFORM notify_user(NEW.buy_uid, 3, v_title, v_body, NEW.id::text, 'payment');
    PERFORM send_push_notification(
      NEW.buy_uid, v_title, v_body,
      jsonb_build_object('type', 'payment', 'id', NEW.id::text)
    );
  END IF;

  -- إشعار للسمسار إن وجد
  IF NEW.brk_uid IS NOT NULL THEN
    PERFORM notify_user(
      NEW.brk_uid, 3,
      '💰 صفقة جديدة لك',
      'تم إتمام صفقة وستحصل على عمولتك.',
      NEW.id::text, 'payment'
    );
    PERFORM send_push_notification(
      NEW.brk_uid,
      '💰 صفقة جديدة لك',
      'تم إتمام صفقة وستحصل على عمولتك.',
      jsonb_build_object('type', 'payment', 'id', NEW.id::text)
    );
  END IF;

  RETURN NEW;
END;
$function$

CREATE OR REPLACE FUNCTION public.trg_offer_published_match_requests()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

CREATE OR REPLACE FUNCTION public.trg_offer_status_changed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

CREATE OR REPLACE FUNCTION public.trg_payment_approved()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_title TEXT;
  v_body TEXT;
  v_pkg_name TEXT;
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
  ELSIF NEW.sts = 2 THEN -- رفض
    v_title := '❌ تم رفض الدفعة';
    v_body := 'لم تُقبل الدفعة. يرجى مراجعة بيانات الدفع والمحاولة مرة أخرى.';
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
$function$

CREATE OR REPLACE FUNCTION public.trg_rating_bonus()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF NEW.stars = 5 THEN
    PERFORM award_points_safe(NEW.target_uid, 'top_rating', 200);
  END IF;
  RETURN NEW;
END;
$function$

CREATE OR REPLACE FUNCTION public.update_expediting_checklist_item(p_actor_uid uuid, p_task_id uuid, p_item_key text, p_status integer, p_input_value text DEFAULT ''::text, p_attachment_url text DEFAULT ''::text, p_notes text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

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
  UPDATE photography_tasks SET sts = p_status, office_note = COALESCE(p_office_note,''), ts_upd = NOW() WHERE id = p_task_id;
  RETURN FOUND;
END; $function$

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

CREATE OR REPLACE FUNCTION public.update_task_outcome(p_user_uid uuid, p_appointment_id uuid, p_outcome text, p_notes text DEFAULT ''::text, p_rejection_reason text DEFAULT ''::text, p_new_date timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

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

CREATE OR REPLACE FUNCTION public.update_user_stats_on_appointment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_count INT;
  v_uid UUID;
BEGIN
  v_uid := COALESCE(NEW.own_id, OLD.own_id);
  IF v_uid IS NULL THEN RETURN NEW; END IF;
  SELECT COUNT(*) INTO v_count FROM appointments
    WHERE own_id = v_uid;
  UPDATE users SET stats = jsonb_set(
    COALESCE(stats, '{}'::jsonb), '{app}', to_jsonb(v_count)
  ), ts_upd = NOW() WHERE id = v_uid;
  RETURN NEW;
END;
$function$

CREATE OR REPLACE FUNCTION public.update_user_stats_on_deal()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_seller UUID;
  v_buyer UUID;
  v_seller_count INT;
  v_buyer_count INT;
BEGIN
  v_seller := COALESCE(NEW.sell_uid, OLD.sell_uid);
  v_buyer := COALESCE(NEW.buy_uid, OLD.buy_uid);

  IF v_seller IS NOT NULL THEN
    SELECT COUNT(*) INTO v_seller_count FROM deals WHERE sell_uid = v_seller;
    UPDATE users SET stats = jsonb_set(
      COALESCE(stats, '{}'::jsonb), '{dl}', to_jsonb(v_seller_count)
    ), ts_upd = NOW() WHERE id = v_seller;
  END IF;

  IF v_buyer IS NOT NULL AND v_buyer <> v_seller THEN
    SELECT COUNT(*) INTO v_buyer_count FROM deals WHERE buy_uid = v_buyer;
    UPDATE users SET stats = jsonb_set(
      COALESCE(stats, '{}'::jsonb), '{dl}', to_jsonb(v_buyer_count)
    ), ts_upd = NOW() WHERE id = v_buyer;
  END IF;

  RETURN NEW;
END;
$function$

CREATE OR REPLACE FUNCTION public.update_user_stats_on_offer()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_count INT;
  v_uid UUID;
BEGIN
  v_uid := COALESCE(NEW.usr_id, OLD.usr_id);
  IF v_uid IS NULL THEN RETURN NEW; END IF;
  SELECT COUNT(*) INTO v_count FROM offers
    WHERE usr_id = v_uid AND i_del = 0;
  UPDATE users SET stats = jsonb_set(
    COALESCE(stats, '{}'::jsonb), '{off}', to_jsonb(v_count)
  ), ts_upd = NOW() WHERE id = v_uid;
  RETURN NEW;
END;
$function$

CREATE OR REPLACE FUNCTION public.update_user_stats_on_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$

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

CREATE OR REPLACE FUNCTION public.verify_otp_v2(p_identifier text, p_code text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE v_found BOOLEAN;
BEGIN
  -- البحث في العمود الموحد فقط وبشكل صارم
  SELECT EXISTS(
    SELECT 1 FROM otp_codes
    WHERE identifier = p_identifier
      AND code = p_code
      AND used = 0
      AND expires_at > NOW()
  ) INTO v_found;

  IF v_found THEN
    -- تحديث الحالة لمنع إعادة استخدام الرمز
    UPDATE otp_codes SET used = 1
      WHERE identifier = p_identifier
        AND code = p_code
        AND used = 0;
    
    -- حذف الرمز فور استخدامه لزيادة الأمان وتوفير المساحة
    DELETE FROM otp_codes
      WHERE identifier = p_identifier
        AND used = 1;

    RETURN TRUE;
  END IF;
  RETURN FALSE;
END;
$function$

CREATE OR REPLACE FUNCTION public.register_fcm_token(p_user_uid uuid, p_token text, p_platform text DEFAULT 'android'::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_token TEXT;
  v_exists BOOLEAN;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;
  SELECT TRUE INTO v_exists FROM public.users WHERE id = p_user_uid AND i_del = 0;
  IF v_exists IS NULL THEN RAISE EXCEPTION 'USER_NOT_FOUND'; END IF;
  v_token := BTRIM(COALESCE(p_token, ''));
  IF LENGTH(v_token) < 20 OR LENGTH(v_token) > 512 THEN RAISE EXCEPTION 'DEVICE_TOKEN_INVALID'; END IF;
  IF COALESCE(p_platform, '') NOT IN ('android', 'ios', 'web') THEN RAISE EXCEPTION 'PLATFORM_INVALID'; END IF;
  UPDATE public.user_devices SET is_active = FALSE, ts_upd = NOW()
    WHERE uid = p_user_uid AND device_token <> v_token AND is_active = TRUE;
  INSERT INTO public.user_devices (uid, device_token, platform, is_active, ts_crt, ts_upd)
  VALUES (p_user_uid, v_token, p_platform, TRUE, NOW(), NOW())
  ON CONFLICT (device_token) DO UPDATE
    SET uid = EXCLUDED.uid, platform = EXCLUDED.platform, is_active = TRUE, ts_upd = NOW();
  RETURN TRUE;
END;
$function$;

REVOKE ALL ON FUNCTION public.register_fcm_token(p_user_uid uuid, p_token text, p_platform text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.register_fcm_token(p_user_uid uuid, p_token text, p_platform text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_fcm_token(p_user_uid uuid, p_token text, p_platform text) TO service_role;

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
  UPDATE public.user_devices SET is_active = FALSE, ts_upd = NOW()
    WHERE device_token = BTRIM(COALESCE(p_token, '')) AND uid = p_user_uid;
  RETURN TRUE;
END;
$function$;

REVOKE ALL ON FUNCTION public.unregister_fcm_token(p_user_uid uuid, p_token text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.unregister_fcm_token(p_user_uid uuid, p_token text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.unregister_fcm_token(p_user_uid uuid, p_token text) TO service_role;

-- ── 2026-07-27: منحة نقاط صاحب العرض عند الاعتماد (sts→2) — تريغر سيرفري خالص ──
CREATE OR REPLACE FUNCTION public.trg_offer_approved_award_points()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_pts INT := 500;
  v_cfg JSONB;
BEGIN
  -- منح مرة واحدة فقط عند الانتقال الحقيقي إلى «منشور»، والحد اليومي 3 يقطع حلقة رفع-تعديل-إعادة اعتماد
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
$function$;

REVOKE ALL ON FUNCTION public.trg_offer_approved_award_points() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.trg_offer_approved_award_points() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.trg_offer_approved_award_points() TO service_role;
