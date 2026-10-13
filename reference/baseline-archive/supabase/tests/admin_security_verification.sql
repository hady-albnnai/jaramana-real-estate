-- Admin security verification checklist
-- Run manually in Supabase SQL Editor after applying admin/security migrations.

WITH function_audit AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'name', p.proname,
      'args', pg_get_function_identity_arguments(p.oid),
      'result', pg_get_function_result(p.oid),
      'security_definer', p.prosecdef
    )
    ORDER BY p.proname, pg_get_function_identity_arguments(p.oid)
  ) AS data
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN (
      'validate_staff_session',
      '_issue_staff_session',
      'revoke_staff_session',
      'revoke_all_staff_sessions',
      'get_admin_dashboard_stats',
      'get_all_staff_users',
      'admin_create_staff_user',
      'admin_update_staff_role',
      'admin_toggle_staff_status',
      'admin_reset_staff_password',
      'admin_delete_staff_user'
    )
), bad_grants AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'routine', routine_name,
      'grantee', grantee,
      'privilege', privilege_type
    )
    ORDER BY routine_name, grantee
  ) AS data
  FROM information_schema.routine_privileges
  WHERE specific_schema = 'public'
    AND routine_name IN (
      '_issue_staff_session',
      'validate_staff_session',
      'revoke_all_staff_sessions',
      'admin_update_user_role',
      'admin_set_user_status',
      'admin_update_user_permissions_by_admin',
      'soft_delete'
    )
    AND grantee IN ('PUBLIC', 'anon', 'authenticated')
), manager AS (
  SELECT id
  FROM public.users
  WHERE role = 6 AND i_del = 0
  ORDER BY ts_crt
  LIMIT 1
), stats_test AS (
  SELECT public.get_admin_dashboard_stats((SELECT id FROM manager)) AS data
), invalid_session_test AS (
  SELECT public.validate_staff_session((SELECT id FROM manager), 'invalid-token', 5) AS data
)
SELECT jsonb_pretty(
  jsonb_build_object(
    'checked_at', now(),
    'function_audit', COALESCE((SELECT data FROM function_audit), '[]'::jsonb),
    'bad_grants_should_be_empty', COALESCE((SELECT data FROM bad_grants), '[]'::jsonb),
    'stats_test', COALESCE((SELECT data FROM stats_test), '{}'::jsonb),
    'invalid_session_test_should_fail', COALESCE((SELECT data FROM invalid_session_test), '{}'::jsonb)
  )
) AS admin_security_verification_json;
