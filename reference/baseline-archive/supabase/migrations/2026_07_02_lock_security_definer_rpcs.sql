-- =====================================================================
-- Migration: 2026_07_02_lock_security_definer_rpcs.sql
-- الغرض: سحب صلاحيات الاستدعاء المباشر (anon/authenticated/public) عن دوال
-- SECURITY DEFINER الأربع وحصرها بـ service_role، لإغلاق تحذيرات Linter الأمان
-- وحماية قاعدة البيانات دون أي تأثير على التطبيق (الذي يمر عبر Edge Functions).
-- =====================================================================

REVOKE ALL ON FUNCTION public.check_username_available(TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_username_available(TEXT) TO service_role;

REVOKE ALL ON FUNCTION public.register_password(UUID, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_password(UUID, TEXT, TEXT) TO service_role;

REVOKE ALL ON FUNCTION public.login_with_password(TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.login_with_password(TEXT, TEXT) TO service_role;

REVOKE ALL ON FUNCTION public.create_offer_internal(UUID, JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_offer_internal(UUID, JSONB) TO service_role;
