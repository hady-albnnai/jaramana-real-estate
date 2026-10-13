-- ════════════════════════════════════════════════════════════════════════
-- Migration: 2026_08_05_fix_admin_requests_security.sql
-- Purpose: إغلاق الثغرة الأمنية في get_admin_requests_internal
-- Bug: BUG-001 — PII Leak via anon/authenticated access
-- Impact: يمنع anon/authenticated من استدعاء الدالة
-- ════════════════════════════════════════════════════════════════════════

-- 🔒 Step 1: REVOKE من PUBLIC أولاً (يسحب الصلاحيات الافتراضية)
REVOKE ALL ON FUNCTION public.get_admin_requests_internal(uuid) FROM PUBLIC;

-- 🔒 Step 2: REVOKE من anon و authenticated (للتأكيد)
REVOKE EXECUTE ON FUNCTION public.get_admin_requests_internal(uuid) 
FROM anon, authenticated;

-- ✅ Step 2: GRANT لـ service_role فقط
GRANT EXECUTE ON FUNCTION public.get_admin_requests_internal(uuid) 
TO service_role;

-- 🧪 Step 3: التحقق (يجب تشغيلها بعد اللصق)
-- SELECT has_function_privilege('anon', 'get_admin_requests_internal(uuid)', 'EXECUTE') AS anon_can_exec;
-- SELECT has_function_privilege('authenticated', 'get_admin_requests_internal(uuid)', 'EXECUTE') AS auth_can_exec;
-- SELECT has_function_privilege('service_role', 'get_admin_requests_internal(uuid)', 'EXECUTE') AS svc_can_exec;
