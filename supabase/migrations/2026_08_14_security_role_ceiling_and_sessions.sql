-- ============================================================================
-- VULN-001 — إغلاق تصعيد الامتياز للدورين 7 (محامٍ) و8 (معقّب)
-- ============================================================================
-- الجذر: نموذج الأدوار تسلسلي (role >= min_role) وهو صحيح من 0 إلى 6:
--   0 مستخدم < 1 وسيط < 2 مصور < 3 مشرف < 4 موظف < 5 نائب < 6 مدير
-- لكن 7 و8 أُضيفا **فوق** المدير رقمياً بينما هما **تخصّصان جانبيان لا رتبتان**
-- ⇒ الشرط `7 < 5` = false فيُمرَّران إلى كل دالة إدارية.
--
-- أدلة حية (2026-08-14): محامٍ نفّذ update_sections وغيّر رقم تواصل فعلياً؛
-- معقّب قرأ كل المدفوعات، واجتاز بوابات delete-user / update-user-role /
-- reset-user-password / toggle-user-status / update-user-permissions،
-- ووصل في create-user إلى آخر تحقق تجاري قبل إنشاء **مدير جديد**.
--
-- الحل (خيار «أ» المعتمد من المالك): سقف علوي.
--   • الرتب الإدارية محصورة في المجال [min_role .. 6].
--   • الدوران 7 و8 يمرّان **فقط** عندما يكون min_role = 0، أي المسارات
--     التشغيلية العامة (legal-actions يستدعيها بـ p_min_role: 0) — فلا تنكسر
--     لوحة المحامي ولا شاشة المعقّب.
--   • المدير الرئيسي (6) يبقى يملك كل شيء.
--
-- ⚠️ التوقيع لم يتغيّر (p_user_uid, p_token, p_min_role) فلا يوجد overload
-- جديد ولا حاجة لتعديل أي Edge Function — الإصلاح مركزي بنقطة واحدة.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.validate_staff_session(
  p_user_uid uuid,
  p_token    text,
  p_min_role integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $fn$
DECLARE
  v_session RECORD;
  v_user    RECORD;
  -- أعلى دور يُعدّ رتبة إدارية. ما فوقه تخصّصات جانبية (7 محامٍ، 8 معقّب).
  c_max_admin_role CONSTANT integer := 6;
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

  -- الحدّ الأدنى (كما كان)
  IF v_user.role < p_min_role THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- 🔒 VULN-001: الحدّ الأعلى — يمنع الدورين 7 و8 من انتحال رتبة إدارية.
  -- يُطبَّق فقط حين تُطلب رتبة فعلية (p_min_role > 0)؛ المسارات العامة
  -- (p_min_role = 0) تبقى مفتوحة لهما كما يجب.
  IF p_min_role > 0 AND v_user.role > c_max_admin_role THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',   'ROLE_NOT_ADMINISTRATIVE',
      'detail',  'الدور تخصّص جانبي ولا يملك رتبة إدارية'
    );
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
        'success',    true,
        'user_id',    p_user_uid,
        'role',       v_user.role,
        'session_id', v_session.id,
        'expires_at', v_session.expires_at
      );
    END IF;
  END LOOP;

  RETURN jsonb_build_object('success', false, 'error', 'INVALID_SESSION');
END;
$fn$;

-- §7 رباعي التحصين
REVOKE ALL ON FUNCTION public.validate_staff_session(uuid, text, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.validate_staff_session(uuid, text, integer) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.validate_staff_session(uuid, text, integer) TO service_role;
-- ============================================================================
-- VULN-001 (الطبقة الثانية) — نفس الخلل داخل حارس قاعدة البيانات
-- ============================================================================
-- `_admin_employee_assert_actor` هو الحارس المشترك لكل دوال إدارة الموظفين
-- (admin_update_user_role / admin_set_user_status / admin_delete_staff_user /
--  admin_reset_staff_password). كان يتحقق من الحد الأدنى فقط:
--     IF v_role < p_min_role THEN RAISE EXCEPTION 'UNAUTHORIZED';
-- فيمرّ المحامي (7) والمعقّب (8) لأن 7 < 5 = false — نفس جذر VULN-001.
--
-- إغلاق validate_staff_session وحده لا يكفي: أي مسار يصل إلى هذه الدوال
-- بمفتاح الخدمة (أو عبر إيدج آخر) كان سيبقى مكشوفاً. الدفاع بالعمق.
-- ============================================================================

CREATE OR REPLACE FUNCTION public._admin_employee_assert_actor(
  p_admin_uid uuid,
  p_min_role  integer DEFAULT 5
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $fn$
DECLARE
  v_role INT;
  c_max_admin_role CONSTANT INT := 6; -- ما فوقه تخصّص جانبي لا رتبة إدارية
BEGIN
  IF p_admin_uid IS NULL THEN
    RAISE EXCEPTION 'ADMIN_UID_REQUIRED';
  END IF;

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

  -- 🔒 VULN-001: سقف علوي — 7 محامٍ و8 معقّب تخصّصان جانبيان.
  IF p_min_role > 0 AND v_role > c_max_admin_role THEN
    RAISE EXCEPTION 'ROLE_NOT_ADMINISTRATIVE';
  END IF;

  RETURN v_role;
END;
$fn$;

REVOKE ALL ON FUNCTION public._admin_employee_assert_actor(uuid, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._admin_employee_assert_actor(uuid, integer) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public._admin_employee_assert_actor(uuid, integer) TO service_role;


-- ============================================================================
-- admin_update_user_permissions_by_admin — كان بلا سقف وبلا حارس «المدير»
-- ============================================================================
-- ثلاث فجوات: (1) لا سقف علوي ⇒ معقّب يمنح صلاحيات؛ (2) لا حماية للمدير
-- (بقية الدوال فيها CANNOT_MODIFY_MANAGER وهذه لا) ⇒ نائب يجرّد المدير من
-- صلاحياته؛ (3) لا قفل ذات ⇒ مدير يجرّد نفسه فيقفل النظام بلا مسار استرداد.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.admin_update_user_permissions_by_admin(
  p_admin_uid  uuid,
  p_target_uid uuid,
  p_perm       jsonb
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $fn$
DECLARE
  v_admin_role  INT;
  v_target_role INT;
BEGIN
  -- الحارس المشترك يتكفّل بالحد الأدنى + السقف العلوي + AUTH_MISMATCH
  v_admin_role := public._admin_employee_assert_actor(p_admin_uid, 5);

  SELECT role INTO v_target_role
  FROM public.users
  WHERE id = p_target_uid AND i_del = 0;

  IF v_target_role IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;

  -- 🔒 قفل الذات: لا أحد يعدّل صلاحيات نفسه — يمنع القفل الدائم.
  IF p_admin_uid = p_target_uid THEN
    RAISE EXCEPTION 'CANNOT_MODIFY_SELF';
  END IF;

  -- 🔒 المدير محميّ كما في بقية دوال إدارة الموظفين.
  IF v_target_role = 6 THEN
    RAISE EXCEPTION 'CANNOT_MODIFY_MANAGER';
  END IF;

  IF v_admin_role < 6 AND v_target_role >= 5 THEN
    RAISE EXCEPTION 'ONLY_MANAGER_CAN_MANAGE_DEPUTIES';
  END IF;

  UPDATE public.users
  SET perm = p_perm, ts_upd = NOW()
  WHERE id = p_target_uid AND i_del = 0;

  PERFORM public._admin_employee_log(
    p_admin_uid, 'user_permissions_update', p_target_uid,
    jsonb_build_object('perm', p_perm)
  );

  RETURN TRUE;
END;
$fn$;

REVOKE ALL ON FUNCTION public.admin_update_user_permissions_by_admin(uuid, uuid, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_update_user_permissions_by_admin(uuid, uuid, jsonb) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_user_permissions_by_admin(uuid, uuid, jsonb) TO service_role;
-- ============================================================================
-- SEC-002 — إبطال الجلسات عند تجميد/حظر/حذف/تغيير دور/إعادة كلمة سر
-- ============================================================================
-- الفجوة (مؤكَّدة حياً 2026-08-14): لا أيّ من الدوال الأربع تلمس
-- `staff_sessions`. النتيجة: مدير يجمّد موظفاً فيظل الموظف يعمل بجلسته
-- النشطة حتى تنتهي صلاحيتها — التجميد **لا يسري فعلياً**. ونفس الشيء عند
-- خفض الدور (يحتفظ بصلاحياته القديمة) وعند إعادة كلمة السر (الجلسة القديمة
-- تبقى صالحة فلا تُطرد الجهة التي سُرقت منها كلمة السر).
-- كان هناك 26 جلسة نشطة لحظة الاكتشاف.
--
-- الحل: دالة مساعدة واحدة تُستدعى من الدوال الأربع.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.revoke_all_user_sessions(p_user_uid uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $fn$
DECLARE
  v_count INT;
BEGIN
  IF p_user_uid IS NULL THEN
    RETURN 0;
  END IF;

  UPDATE public.staff_sessions
  SET revoked = 1
  WHERE user_id = p_user_uid
    AND revoked = 0;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$fn$;

REVOKE ALL ON FUNCTION public.revoke_all_user_sessions(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.revoke_all_user_sessions(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_all_user_sessions(uuid) TO service_role;
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

  -- SEC-002: التجميد/الحظر لا يسري ما لم تُبطَل الجلسات النشطة.
  IF p_status <> 0 THEN
    PERFORM public.revoke_all_user_sessions(p_target_uid);
  END IF;

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
$function$;


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

  -- SEC-002: الدور الجديد لا يسري على جلسة قائمة — تُبطَل لإجبار دخول جديد.
  PERFORM public.revoke_all_user_sessions(p_target_uid);

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
$function$;


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

  -- SEC-002: الحساب المحذوف يجب ألا تبقى له جلسة صالحة.
  PERFORM public.revoke_all_user_sessions(p_target_uid);

  PERFORM public._admin_employee_log(
    p_admin_uid,
    'staff_delete',
    p_target_uid,
    '{}'::jsonb
  );

  RETURN jsonb_build_object('success', true);
END;
$function$;


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

  -- SEC-002: إعادة كلمة السر تطرد كل الجلسات القديمة.
  PERFORM public.revoke_all_user_sessions(p_target_uid);

  PERFORM public._admin_employee_log(
    p_admin_uid,
    'staff_password_reset',
    p_target_uid,
    '{}'::jsonb
  );

  RETURN jsonb_build_object('success', true);
END;
$function$;
