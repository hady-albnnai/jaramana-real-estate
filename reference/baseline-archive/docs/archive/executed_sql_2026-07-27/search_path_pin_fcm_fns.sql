-- ============================================================
-- تثبيت search_path لدالتَي إصلاح الـ Push — 2026-07-27
-- السبب: تنبيه linter 0011 (Function Search Path Mutable) ×2
--   public.trg_payment_approved + public.send_push_notification
-- الجذر: مايغريشن 2026_07_27_fcm_push_fix.sql نسيت سطر الـ SET
--   بعكس شقيقاتها register/unregister_fcm_token (كانت مثبتة أصلاً)
-- idempotent + لا يغيّر أي سلوك — نفّذ بعد قسم D من المايغريشن
-- ============================================================

-- الخطوة 1/3: قبل الفيكس — لازم ترجع الدالتين بالضبط
SELECT p.proname AS unpinned_definer_fn
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prosecdef = true
  AND NOT EXISTS (
    SELECT 1 FROM unnest(COALESCE(p.proconfig, ARRAY[]::text[])) c
    WHERE c LIKE 'search_path=%'
  )
ORDER BY 1;

-- الخطوة 2/3: التثبيت (نفس نمط جولة 2026_07_04_search_path_hardening)
ALTER FUNCTION public.trg_payment_approved()
  SET search_path TO 'public', 'extensions', 'pg_temp';

ALTER FUNCTION public.send_push_notification(uuid, text, text, jsonb)
  SET search_path TO 'public', 'extensions', 'pg_temp';

-- الخطوة 3/3: بعد الفيكس — نفس الاستعلام لازم يرجع 0 صفوف
SELECT p.proname AS unpinned_definer_fn
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prosecdef = true
  AND NOT EXISTS (
    SELECT 1 FROM unnest(COALESCE(p.proconfig, ARRAY[]::text[])) c
    WHERE c LIKE 'search_path=%'
  )
ORDER BY 1;
