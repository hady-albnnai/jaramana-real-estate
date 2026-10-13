-- ═══════════════════════════════════════════════════
-- تنظيف صلاحيات admin_reject_payment_internal
-- ينهي تنبيهَي اللينتر 0028 (anon) و 0029 (authenticated)
-- آمن وقابل للتكرار — شغّل الملف كاملاً في SQL Editor
-- ═══════════════════════════════════════════════════

-- 1) قطع مسار PUBLIC المدمج (السبب الجذري للتسريب)
REVOKE ALL ON FUNCTION public.admin_reject_payment_internal(p_admin_uid uuid, p_payment_id uuid, p_reason text) FROM PUBLIC;

-- 2) قطع منح anon/authenticated (احترازي — ما بتضر إذا مو موجودة)
REVOKE EXECUTE ON FUNCTION public.admin_reject_payment_internal(p_admin_uid uuid, p_payment_id uuid, p_reason text) FROM anon, authenticated;

-- 3) الإبقاء على service_role فقط (إيدج admin-payments تنادي بالمفتاح)
GRANT EXECUTE ON FUNCTION public.admin_reject_payment_internal(p_admin_uid uuid, p_payment_id uuid, p_reason text) TO service_role;

-- فحص (اختياري) — النتيجة المتوقعة بعد التشغيل:
-- {postgres=X/postgres,service_role=X/postgres}
SELECT p.proacl
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'admin_reject_payment_internal';
