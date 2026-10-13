-- إصلاح جلسات تسجيل الدخول بكلمة المرور وتغيير كلمة المرور من الملف الشخصي
-- السبب: user-account يحتاج توثيق مستخدم عادي أيضاً، وليس موظفاً بدور >= 5 فقط.
-- هذا يضمن أن login_with_password يصدر session token لكل الأدوار،
-- بينما تبقى دالة validate_staff_session قابلة للتقييد عبر p_min_role في Edge Functions الإدارية.

CREATE OR REPLACE FUNCTION public._issue_staff_session(
  p_user_uid UUID,
  p_device_id TEXT DEFAULT '',
  p_ip TEXT DEFAULT '',
  p_ttl INTERVAL DEFAULT INTERVAL '7 days'
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
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
$$;

REVOKE ALL ON FUNCTION public._issue_staff_session(UUID, TEXT, TEXT, INTERVAL) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._issue_staff_session(UUID, TEXT, TEXT, INTERVAL) TO service_role;
