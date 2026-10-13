-- إصلاح إسناد المصور من جلسات الدخول المخصصة عندما لا يرسل APK القديم admin_uid.
CREATE OR REPLACE FUNCTION public.resolve_staff_session_actor(
  p_token text,
  p_min_role integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_session record;
BEGIN
  IF COALESCE(p_token, '') = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'SESSION_TOKEN_REQUIRED');
  END IF;

  FOR v_session IN
    SELECT s.id AS session_id, s.user_id, s.token_hash, s.expires_at, u.role
    FROM public.staff_sessions s
    JOIN public.users u ON u.id = s.user_id
    WHERE s.revoked = 0
      AND s.expires_at > NOW()
      AND u.sts = 0
      AND u.i_del = 0
      AND u.role BETWEEN p_min_role AND 6
    ORDER BY s.created_at DESC
  LOOP
    IF v_session.token_hash = crypt(p_token, v_session.token_hash) THEN
      UPDATE public.staff_sessions
      SET last_used_at = NOW()
      WHERE id = v_session.session_id;

      RETURN jsonb_build_object(
        'success', true,
        'user_id', v_session.user_id,
        'role', v_session.role,
        'session_id', v_session.session_id,
        'expires_at', v_session.expires_at
      );
    END IF;
  END LOOP;

  RETURN jsonb_build_object('success', false, 'error', 'INVALID_SESSION');
END;
$function$;

REVOKE ALL ON FUNCTION public.resolve_staff_session_actor(text, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.resolve_staff_session_actor(text, integer) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_staff_session_actor(text, integer) TO service_role;
