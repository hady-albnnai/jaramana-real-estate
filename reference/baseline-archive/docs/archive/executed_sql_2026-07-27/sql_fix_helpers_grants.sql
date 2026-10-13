-- ═══════════════════════════════════════════════════
-- تحصين 8 دوال helpers — service_role فقط
-- كشفها السحب الأمني الشامل 2026-07-27 (anon-executable)
-- خطورتها منخفضة (pure validators بدون كتابة) — قفل احترازي
-- شغّل الملف كاملاً — آمن وقابل للتكرار
-- ═══════════════════════════════════════════════════

REVOKE ALL ON FUNCTION public.app_assert_password(p_password text, p_min integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.app_assert_password(p_password text, p_min integer) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.app_assert_password(p_password text, p_min integer) TO service_role;

REVOKE ALL ON FUNCTION public.app_assert_phone(p_phone text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.app_assert_phone(p_phone text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.app_assert_phone(p_phone text) TO service_role;

REVOKE ALL ON FUNCTION public.app_assert_price(p_value numeric, p_required boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.app_assert_price(p_value numeric, p_required boolean) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.app_assert_price(p_value numeric, p_required boolean) TO service_role;

REVOKE ALL ON FUNCTION public.app_assert_text_len(p_value text, p_field text, p_min integer, p_max integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.app_assert_text_len(p_value text, p_field text, p_min integer, p_max integer) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.app_assert_text_len(p_value text, p_field text, p_min integer, p_max integer) TO service_role;

REVOKE ALL ON FUNCTION public.app_assert_username(p_username text, p_required boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.app_assert_username(p_username text, p_required boolean) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.app_assert_username(p_username text, p_required boolean) TO service_role;

REVOKE ALL ON FUNCTION public.app_clean_text(p_value text, p_max_len integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.app_clean_text(p_value text, p_max_len integer) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.app_clean_text(p_value text, p_max_len integer) TO service_role;

REVOKE ALL ON FUNCTION public.normalize_sy_phone(p_phone text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.normalize_sy_phone(p_phone text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.normalize_sy_phone(p_phone text) TO service_role;

REVOKE ALL ON FUNCTION public.normalize_arabic_username(p_str text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.normalize_arabic_username(p_str text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.normalize_arabic_username(p_str text) TO service_role;
